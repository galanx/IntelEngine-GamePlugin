# Experimental IntelEngine 3.5.0 compatibility candidate for Skyrim 1.7.104

**Draft for maintainer review. This is not a generally supported release.**

The shipped IntelEngine 3.5.0 DLL fails to start on Skyrim 1.7.104.0 because its
embedded CommonLib classifies minor version 7 as SE, selects `version-*.bin`,
and only understands the old sparse address-library representation. The official
1.7.104 address library is format 5, a dense ID-indexed array.

This tool creates a separate diagnostic mod directory from two exact, locally
supplied inputs. It does not install anything, modify those inputs, change the
official address library, or edit an existing MO2 profile. No additional DLL or
address-library binary is distributed by this change.

## Reproduce

Python 3.11 or newer; standard library only. From the repository root:

```console
python -m unittest discover -s tools/compatibility/skyrim-1.7.104 -p test_patch_intelengine.py -v
python tools/compatibility/skyrim-1.7.104/patch_intelengine.py --dll SKSE/Plugins/IntelEngine.dll --address-library /path/to/versionlib-1-7-104-0.bin --output /path/to/NEW-private-candidate
```

The output directory must not exist. It contains `SKSE/Plugins/IntelEngine.dll`,
`SKSE/Plugins/intelport1-1-7-104-0.bin`, and `candidate.json` with hashes and the
exact reversible edits. Use only a disposable, isolated test profile. Preserve
the original DLL and keep the actual format-5 Address Library installed for the
other SKSE plugins. No support is claimed for another DLL, table, or runtime.

## Exact adaptation

Four bounded edits change 21 bytes, without changing PE section sizes:

| Change | Original location | Purpose |
| --- | --- | --- |
| Runtime classifier `setne` to `setb` after `cmp ax,6` | RVA `0x2E0DB` | Select AE rather than SE relocation IDs on minor 7; preceding VR branch is unchanged. |
| Same-length table filename | File offset `2754232` | Read `intelport1-{}.bin`, leaving the official `versionlib-{}.bin` untouched. |
| Same-length UTF-16 mapping prefix | File offset `2754496` | Use `IntelPortSSEOffsets-v2-` to avoid sharing the legacy mapping with other plugins. |
| `SkyrimVM::impl` access `0x200` to `0x210` | RVA `0x15D6BE` | Adapt the one proven VM member access after the 1.7.99 base-class changes. |

The VM access is reached through `SkyrimVM::GetSingleton`, identified by its
relocation-ID tuple `(514315, 400475, 514315)`. This is a targeted correction,
not a blanket replacement of displacements in unrelated engine/STL objects.

The converter reads the official 96-byte format-5 header and all 565,759 slots,
then emits the 435,162 nonzero mappings in the old reader's absolute format-2
encoding: one zero type byte, uint64 ID, uint64 offset. A second decoding pass
compares every ID/offset pair. REA/Ghidra and independent disassembly of the
original unpacker at RVA `0x31D90` establish that encoding; byte zero selects
eight-byte absolute reads and no pointer scaling. This is a full representation
conversion, not a renamed format-5 file with a changed header.

Input DLL SHA-256:
`92800123c011183e85ebdb6d8c54c61161f1a69fece257ce6bfbbb335338ed8c`

Input format-5 table SHA-256:
`8aab3dd251d135b849bd983f86a4a205c920fa3e81f8e30c0e63ccfef9423842`

Candidate DLL SHA-256:
`f0ddeea573386a651af78d4b9168e4dd0693994cb25adbb05175a88e361bf544`

## Validation performed

Target: Skyrim 1.7.104.0, SKSE 2.3.1, Address Library 13, SkyrimNet Beta27,
DevBench 1.29.0. A separate portable MO2 instance used local INI files and saves;
no existing character was imported. Original installed mods stayed unchanged.

- SKSE reports that the patched IntelEngine loads correctly; player and rendered
  frames become available in the Sleeping Giant Inn.
- Twelve targeted checks pass: native version, string trimming, hex conversion,
  index readiness/statistics, actor and parent location, war count, biography
  counts, and continued game responsiveness. Reading a war count is not a
  political-event test.
- A newly spawned disposable actor receives a travel command, slot, and the
  expected effective package. Its coordinates subsequently change to an
  exterior location; cancellation succeeds and releases its slot.
- The travel slot/type/package are restored from a private save after the live
  task has explicitly been cleared. The process was also fully restarted during
  the trials. Native queries remain functional after reload.
- A clean second generation of the candidate produces identical hashes; reversing
  the manifest edits reconstructs the original DLL byte for byte.

## Failures retained and unverified behavior

- An initial movement check at 28 seconds failed. Later observations showed
  exterior coordinates, but continuous walking/door animation was not observed.
  The author's travel script itself uses `MoveTo` when crossing a door; a final
  arrival, escort, delivery, or scheduled meeting is not claimed as validated.
- `StringToLower("PASCAL")` returned the original capitalization. Static tracing
  shows a real lowercase loop followed by BSFixedString construction, so
  case-insensitive interning is a hypothesis, not a proven explanation. No
  speculative string-function patch is included.
- Papyrus logs still contain unbound native declarations (including
  `GetSafetyNetNPC`, `NotifyNewDialogue`, `RunSafetyNetCheck`), None casts, an
  unsavable-callback warning, and UIExtensions/DLC binding warnings after load.
  Their origin has not been established. Successful restoration of one task
  does not establish persistence of every callback.
- PrismaUI was omitted from the minimal native test profile. The dashboard and
  UI were not validated. No LLM-originated command, autonomous political event,
  battle, long playthrough, or compatibility with other NPC controllers was
  validated. Other changed engine layouts may still require work.

## Upstream source references

The public repository has no C++ build source, so this proposal records a
reproducible binary experiment rather than claiming to rebuild IntelEngine.
A maintainer rebuild against current CommonLib, with an audit of the actual
engine accesses, is preferable for an official release.

- [CommonLib format-5 implementation](https://github.com/alandtse/CommonLibSSE-NG/commit/7b47c5a)
- [SkyrimVM/PlayerCharacter layout correction](https://github.com/alandtse/CommonLibSSE-NG/commit/68ae73e)
- [Current address-library reader](https://github.com/alandtse/CommonLibSSE-NG/blob/ng/src/REL/IDDB.cpp)

This proposal grants no redistribution permission for IntelEngine or the Address
Library. It adds only the patch/conversion tool, tests, and this report.
