"""Safety/representation checks for the isolated IntelEngine loader experiment."""
import importlib.util
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location("intel_port", Path(__file__).with_name("patch_intelengine.py"))
port = importlib.util.module_from_spec(spec)
spec.loader.exec_module(port)


def fixture(offsets=(0, 0x12345678, 0, 0xFFFFFFFF)):
    return port.HEADER_V5.pack(5, 1, 7, 104, 0, b"SkyrimSE.exe", 8, 0, len(offsets)) + struct.pack(f"<{len(offsets)}I", *offsets)


class IntelPortTests(unittest.TestCase):
    def test_repository_binary_patch_is_exact_and_reversible(self):
        original = (Path(__file__).resolve().parents[3] / "SKSE/Plugins/IntelEngine.dll").read_bytes()
        patched, manifest = port.patch_dll(original)
        self.assertEqual(port.sha256(patched), "f0ddeea573386a651af78d4b9168e4dd0693994cb25adbb05175a88e361bf544")
        self.assertEqual(sum(a != b for a, b in zip(original, patched)), 21)
        restored = bytearray(patched)
        for edit in manifest:
            start = edit["file_offset"]
            old = bytes.fromhex(edit["before_hex"])
            restored[start:start + len(old)] = old
        self.assertEqual(bytes(restored), original)

    def test_dense_to_sparse_preserves_ids_and_offsets(self):
        offsets = port.parse_v5(fixture())
        data = port.encode_v2(offsets)
        self.assertEqual(port.decode_v2_candidate(data), {1: 0x12345678, 3: 0xFFFFFFFF})
        # Independently inspect the actual two on-disk entries: type0 + uint64 pair.
        self.assertEqual(data[-34:], bytes.fromhex("00") + struct.pack("<QQ", 1, 0x12345678) +
                         bytes.fromhex("00") + struct.pack("<QQ", 3, 0xFFFFFFFF))

    def test_all_zero_table_has_no_fabricated_mapping(self):
        self.assertEqual(port.decode_v2_candidate(port.encode_v2((0, 0, 0))), {})

    def test_invalid_v5_headers_fail_closed(self):
        for offset, value in [(0, 2), (8, 6), (12, 1130), (84, 4), (88, 1), (92, 99999)]:
            with self.subTest(offset=offset):
                data = bytearray(fixture())
                struct.pack_into("<I", data, offset, value)
                with self.assertRaises(ValueError):
                    port.parse_v5(bytes(data))

    def test_truncation_and_trailing_data_rejected(self):
        for data in [b"", fixture()[:90], fixture()[:-1], fixture() + b"\0"]:
            with self.assertRaises(ValueError):
                port.parse_v5(data)

    def test_unknown_dll_rejected(self):
        with self.assertRaisesRegex(ValueError, "DLL hash"):
            port.patch_dll(b"MZ fake")

    def test_malformed_v2_rejected(self):
        good = port.encode_v2((0, 123, 456))
        for data in [good[:-1], good + b"\0", good[:-34] + b"\x01" + good[-33:]]:
            with self.assertRaises(ValueError):
                port.decode_v2_candidate(data)

    def test_wrong_version_rejected(self):
        data = bytearray(port.encode_v2((0, 123)))
        struct.pack_into("<I", data, 8, 6)
        with self.assertRaises(ValueError):
            port.decode_v2_candidate(bytes(data))


if __name__ == "__main__":
    unittest.main()
