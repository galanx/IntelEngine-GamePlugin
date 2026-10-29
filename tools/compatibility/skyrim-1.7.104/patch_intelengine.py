"""Private, hash-pinned IntelEngine 3.5.0 loader adaptation for Skyrim 1.7.104.

This adapts the loader and one verified VM access; remaining engine layouts are unaudited.
Use a disposable isolated profile; full gameplay compatibility is not established.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path

DLL_SHA256 = "92800123c011183e85ebdb6d8c54c61161f1a69fece257ce6bfbbb335338ed8c"
TABLE_SHA256 = "8aab3dd251d135b849bd983f86a4a205c920fa3e81f8e30c0e63ccfef9423842"
VERSION = (1, 7, 104, 0)
TABLE_NAME = "intelport1-1-7-104-0.bin"
HEADER_V5 = struct.Struct("<5I64s3I")
ABSOLUTE_V2_ENTRY = struct.Struct("<BQQ")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def parse_v5(data: bytes) -> tuple[int, ...]:
    """Read the exact public v5 dense layout, refusing unknown variants."""
    if len(data) < HEADER_V5.size:
        raise ValueError("Truncated v5 header")
    fmt, major, minor, patch, build, name, pointer_size, reserved, count = HEADER_V5.unpack_from(data)
    if (fmt, major, minor, patch, build) != (5, *VERSION):
        raise ValueError("Only format5 Skyrim1.7.104.0 is supported")
    if name.rstrip(b"\0") != b"SkyrimSE.exe" or pointer_size != 8 or reserved != 0:
        raise ValueError("Unknown v5 header variant")
    if not count or len(data) != HEADER_V5.size + 4 * count:
        raise ValueError("Truncated or trailing v5 data")
    return struct.unpack_from(f"<{count}I", data, HEADER_V5.size)


def encode_v2(offsets: tuple[int, ...]) -> bytes:
    """Lossless sparse representation: type0 means absolute uint64 ID + offset."""
    entries = [(ident, offset) for ident, offset in enumerate(offsets) if offset]
    name = b"SkyrimSE.exe"
    result = bytearray(struct.pack("<6I", 2, *VERSION, len(name)))
    result.extend(name)
    result.extend(struct.pack("<II", 8, len(entries)))
    for ident, offset in entries:
        result.extend(ABSOLUTE_V2_ENTRY.pack(0, ident, offset))
    return bytes(result)


def decode_v2_candidate(data: bytes) -> dict[int, int]:
    """Independent strict decoding of the absolute-only subset emitted here."""
    if len(data) < 32:
        raise ValueError("Truncated v2 header")
    fmt, *header = struct.unpack_from("<6I", data)
    if fmt != 2 or tuple(header[:4]) != VERSION:
        raise ValueError("Wrong v2 format/version")
    name_len = header[4]
    pos = 24 + name_len
    if pos + 8 > len(data) or data[24:pos] != b"SkyrimSE.exe":
        raise ValueError("Invalid module name")
    pointer_size, count = struct.unpack_from("<II", data, pos)
    pos += 8
    if pointer_size != 8 or len(data) != pos + count * ABSOLUTE_V2_ENTRY.size:
        raise ValueError("Invalid v2 entry count/size")
    result = {}
    previous = -1
    for at in range(pos, len(data), ABSOLUTE_V2_ENTRY.size):
        kind, ident, offset = ABSOLUTE_V2_ENTRY.unpack_from(data, at)
        if kind != 0 or ident <= previous or offset == 0:
            raise ValueError("Nonabsolute/duplicate/unsorted/zero mapping")
        result[ident] = offset
        previous = ident
    return result


def pe_rva_to_offset(data: bytes, rva: int) -> int:
    """Minimal bounds-checked PE64 section conversion; no third-party mutation."""
    if data[:2] != b"MZ" or len(data) < 64:
        raise ValueError("Not a PE")
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError("Not a PE")
    machine, count = struct.unpack_from("<HH", data, pe + 4)
    optional_size = struct.unpack_from("<H", data, pe + 20)[0]
    if machine != 0x8664 or struct.unpack_from("<H", data, pe + 24)[0] != 0x20B:
        raise ValueError("Not PE64")
    table = pe + 24 + optional_size
    for index in range(count):
        entry = table + index * 40
        _, base, raw_size, raw_at = struct.unpack_from("<4I", data, entry + 8)
        if base <= rva < base + raw_size:
            offset = raw_at + rva - base
            if offset >= len(data):
                raise ValueError("RVA beyond file")
            return offset
    raise ValueError("RVA has no raw section")


def patch_dll(data: bytes) -> tuple[bytes, list[dict]]:
    if sha256(data) != DLL_SHA256:
        raise ValueError("Unknown IntelEngine DLL hash")
    edits = [
        ("SkyrimVM impl moved by Amiibo bases on 1.7.99+", pe_rva_to_offset(data, 0x15D6BE),
         bytes.fromhex("488b8000020000"), bytes.fromhex("488b8010020000")),
        ("runtime classification AE >= 1.6", pe_rva_to_offset(data, 0x2E0DB),
         bytes.fromhex("6683f8060f95c0"), bytes.fromhex("6683f8060f92c0")),
        ("private address-table path", 2754232,
         b"Data/SKSE/Plugins/versionlib-{}.bin", b"Data/SKSE/Plugins/intelport1-{}.bin"),
        ("private shared mapping namespace", 2754496,
         "CommonLibSSEOffsets-v2-".encode("utf-16le"), "IntelPortSSEOffsets-v2-".encode("utf-16le")),
    ]
    output = bytearray(data)
    manifest = []
    for reason, offset, before, after in edits:
        if len(before) != len(after) or data[offset:offset + len(before)] != before:
            raise ValueError(f"Unexpected bytes: {reason}")
        output[offset:offset + len(after)] = after
        manifest.append({"reason": reason, "file_offset": offset,
                         "before_hex": before.hex(), "after_hex": after.hex()})
    expected = set()
    for edit in manifest:
        start = edit["file_offset"]
        before, after = bytes.fromhex(edit["before_hex"]), bytes.fromhex(edit["after_hex"])
        expected.update(start + i for i, (a, b) in enumerate(zip(before, after)) if a != b)
    actual = {i for i, (a, b) in enumerate(zip(data, output)) if a != b}
    if actual != expected or len(data) != len(output):
        raise AssertionError("Unspecified binary change")
    return bytes(output), manifest


def build(original_dll: Path, original_table: Path, output: Path) -> dict:
    dll_data = original_dll.read_bytes()
    table_data = original_table.read_bytes()
    if sha256(table_data) != TABLE_SHA256:
        raise ValueError("Unknown Address Library hash")
    offsets = parse_v5(table_data)
    translated = encode_v2(offsets)
    decoded = decode_v2_candidate(translated)
    expected = {ident: offset for ident, offset in enumerate(offsets) if offset}
    if decoded != expected:
        raise AssertionError("Address conversion not lossless")
    patched, patches = patch_dll(dll_data)
    if output.exists():
        raise FileExistsError("Fresh candidate output required")
    output.mkdir(parents=True)
    plugins = output / "SKSE" / "Plugins"
    plugins.mkdir(parents=True)
    (plugins / "IntelEngine.dll").write_bytes(patched)
    (plugins / TABLE_NAME).write_bytes(translated)
    report = {
        "status": "STATIC_LOADER_CANDIDATE_ONLY",
        "runtime": ".".join(map(str, VERSION)),
        "original_dll_sha256": sha256(dll_data),
        "candidate_dll_sha256": sha256(patched),
        "original_address_library_sha256": sha256(table_data),
        "candidate_address_library_sha256": sha256(translated),
        "dense_count": len(offsets), "nonzero_mappings_verified": len(decoded),
        "all_nonzero_mappings_identical": True, "patches": patches,
        "limitations": ["One verified VM access patched; remaining engine layouts unaudited", "Native load not tested by this builder",
                        "No gameplay compatibility claim", "Private diagnostic runtime only"],
    }
    (output / "candidate.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if original_dll.read_bytes() != dll_data or original_table.read_bytes() != table_data:
        raise AssertionError("Source changed during build")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dll", required=True, type=Path)
    parser.add_argument("--address-library", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(build(args.dll, args.address_library, args.output), indent=2))


if __name__ == "__main__":
    main()
