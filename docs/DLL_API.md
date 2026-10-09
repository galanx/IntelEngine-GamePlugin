# IntelEngine Native DLL API Specification

## Overview

The `IntelEngine.dll` SKSE plugin provides high-performance functions that would be too slow in Papyrus:

- **Fuzzy string matching** - Find NPCs/locations even with typos
- **Game data indexing** - O(1) hash-based searches built from game data at startup
- **Semantic resolution** - Translate "upstairs" to actual door references
- **Action validation** - Pre-flight checks for feasibility

**No external databases required!** All indexes are built from game data at startup.

## Build Requirements

- Visual Studio 2022 (the supported script uses the VS 2022 Community developer shell), CMake, Ninja, and PowerShell on Windows.
- MSVC Release builds use `/Od /Ob0 /DNDEBUG` and `/std:c++23preview` for the native plugin and source-built CommonLib. `/O2`, `/std:c++latest`, and `/d2ReducedOptimizeHugeFunctions` are not used. This profile was rebuilt with VS 2022 MSVC 19.44 / toolset 14.44; the language mode retains MinLL's required C++23 support. These build settings do not by themselves establish a runtime black-screen fix.
- Dependencies are resolved through the repository's vcpkg manifest and baseline. CommonLibSSE is built from source at the enforced MinLL/CommonLibVR commit `550cc4fb9114649dcf526d1f3d73d710c5d7003b` (v4.39.5, MIT); the build verifies the Git revision, clean checkout, and license rather than accepting an imported prebuilt CommonLib target.
- The build applies one audited SE/AE header correction without modifying that checkout: generated `commonlib-abi/include/RE/T/TESObjectREFR.h` omits the VR-only `Unk_8C` virtual declaration. CMake verifies the upstream header's LF-normalized SHA-256 and places the generated include ahead of the upstream header for both CommonLib and IntelEngine. This corrects the pinned fork's non-VR virtual-slot shift; it is not a general patch or alternate-dependency mechanism.
- The native plugin is configured for Skyrim SE and AE with Address Library compatibility. The documented runtime targets are **1.5.97.0, 1.6.640.0, 1.6.1170.0, 1.7.99.0, and 1.7.104.0**. Address Library is the compatibility mechanism; this is not a fixed-version whitelist. VR is disabled and unsupported.

## Papyrus API

All functions are exposed to Papyrus via the `IntelEngine` script namespace.

---

## NPC Search Functions

### FindNPCByName
```papyrus
Actor Function FindNPCByName(String searchTerm) Global Native
```

Find an NPC by name using fuzzy matching.

**Parameters:**
- `searchTerm` - Name to search for (e.g., "Nazeem", "nazim", "the annoying guy")

**Returns:**
- Actor reference if found, None if not found

**Algorithm:**
1. Exact match check (case-insensitive)
2. Levenshtein distance fuzzy match (threshold: 3)
3. Partial match (contains substring)

**Index:** Built from all unique NPCs in game data at startup

**Performance:** O(1) average via pre-built hash index

**Example:**
```papyrus
Actor nazeem = IntelEngine.FindNPCByName("Nazeem")
Actor jarl = IntelEngine.FindNPCByName("jarl balgruuf")
Actor fuzzy = IntelEngine.FindNPCByName("nazim")  ; typo still works
```

---

### FindNPCsNearLocation
```papyrus
Actor[] Function FindNPCsNearLocation(String locationName, Float radius) Global Native
```

Find all NPCs near a named location.

**Parameters:**
- `locationName` - Location to search near
- `radius` - Search radius in game units

**Returns:**
- Array of Actor references

---

### GetNPCCurrentLocation
```papyrus
String Function GetNPCCurrentLocation(Actor akNPC) Global Native
```

Get human-readable location name for an NPC.

**Parameters:**
- `akNPC` - The NPC to query

**Returns:**
- Location name (e.g., "Whiterun Marketplace", "Dragonsreach")

---

### IsNPCAccessible
```papyrus
Bool Function IsNPCAccessible(Actor akNPC) Global Native
```

Check if an NPC can be interacted with (not in inaccessible cell, not disabled).

**Parameters:**
- `akNPC` - The NPC to check

**Returns:**
- True if NPC can be reached

---

## Location Functions

### ResolveLocationToCell
```papyrus
Cell Function ResolveLocationToCell(String locationName) Global Native
```

Resolve a location name to a Cell using fuzzy matching.

**Parameters:**
- `locationName` - Named location (e.g., "Bannered Mare", "Dragonsreach")

**Returns:**
- Cell if found, None otherwise

**Use Case:** Give the Cell to Skyrim's AI pathfinding to handle travel.

---

### ResolveLocationToBGSLocation
```papyrus
Location Function ResolveLocationToBGSLocation(String locationName) Global Native
```

Resolve a location name to a BGSLocation (for broader areas).

**Parameters:**
- `locationName` - Named location (e.g., "Whiterun", "Solitude")

**Returns:**
- Location if found, None otherwise

---

### FindDoorToLocation
```papyrus
ObjectReference Function FindDoorToLocation(String locationName) Global Native
```

Find a door in loaded cells that leads to the target location.

**Parameters:**
- `locationName` - Named location

**Returns:**
- Door reference if found in current/loaded cells, None otherwise

**Use Case:** If door is found, NPC can walk to it directly. If None, fall back to AI package travel.

---

### ResolveLocation (Legacy)
```papyrus
ObjectReference Function ResolveLocation(String locationName) Global Native
```

Legacy function - tries FindDoorToLocation first, returns None if not found.

**Returns:**
- Door reference or None

**Supports Fuzzy Matching:**
- City names: "Whiterun", "Solitude", "Riften"
- Specific places: "Dragonsreach", "Blue Palace"
- Inns: "Bannered Mare", "Sleeping Giant"
- Typo tolerance via Levenshtein distance

---

### GetLocationSuggestion
```papyrus
String Function GetLocationSuggestion(String searchTerm) Global Native
```

Get suggested location name for a failed search (for "did you mean?" prompts).

**Returns:**
- Closest matching location name, or empty string

---

### ResolveSemanticLocation
```papyrus
ObjectReference Function ResolveSemanticLocation(Actor akNPC, String semanticTerm) Global Native
```

Resolve a semantic/relative location term to an actual marker.

**Parameters:**
- `akNPC` - The NPC (context for relative directions)
- `semanticTerm` - Relative term ("upstairs", "outside", "the back")

**Returns:**
- ObjectReference marker if resolvable, None if not possible

**Supported Terms:**

| Term | Resolution Logic |
|------|------------------|
| "upstairs" | Find door/stairs where destination Z > current Z |
| "downstairs" | Find door/stairs where destination Z < current Z |
| "outside" | Find nearest door marked as exterior transition |
| "inside" | If outside, find nearest interior door |
| "the back room" | Find door furthest from main entrance |
| "the cellar" / "basement" | Find door to cell with lower Z or matching name |
| "my room" | If NPC has owned bed, find that cell |
| "the bar" / "counter" | Find furniture of type bar/counter |
| "near the fire" | Find fireplace/campfire furniture |

**Example:**
```papyrus
; NPC is in Bannered Mare ground floor
ObjectReference upstairs = IntelEngine.ResolveSemanticLocation(npc, "upstairs")
; Returns marker for Bannered Mare upper floor

ObjectReference outside = IntelEngine.ResolveSemanticLocation(npc, "outside")
; Returns marker outside the inn door
```

---

### GetCellSpatialInfo
```papyrus
String Function GetCellSpatialInfo(Actor akNPC) Global Native
```

Get JSON-formatted spatial information about NPC's current cell.

**Returns:** JSON string with structure:
```json
{
  "cellName": "WhiterunBanneredMare",
  "cellType": "interior",
  "doors": [
    {
      "direction": "north",
      "leadsTo": "Whiterun",
      "isExterior": true,
      "isLocked": false
    },
    {
      "direction": "up",
      "leadsTo": "Bannered Mare (Upper Floor)",
      "isExterior": false,
      "isLocked": false
    }
  ],
  "hasStairsUp": true,
  "hasStairsDown": false,
  "notableAreas": [
    {"name": "bar counter", "direction": "west", "distance": 5.2},
    {"name": "fireplace", "direction": "center", "distance": 3.1}
  ]
}
```

---

### IsSemanticTerm
```papyrus
Bool Function IsSemanticTerm(String term) Global Native
```

Check if a term is a semantic/relative location reference.

**Parameters:**
- `term` - The term to check

**Returns:**
- True if term is semantic ("upstairs", "outside", etc.)

---

## Action Validation Functions

### ValidateAction
```papyrus
Bool Function ValidateAction(Actor akNPC, String actionType, String targetParam) Global Native
```

Pre-validate if an action is possible before attempting.

**Parameters:**
- `akNPC` - NPC who would perform action
- `actionType` - Type of action ("travel", "fetch_npc", "fetch_item", "lockpick")
- `targetParam` - Action-specific target

**Returns:**
- True if action is feasible

**Example:**
```papyrus
; Can this NPC travel to Solitude?
Bool canTravel = IntelEngine.ValidateAction(npc, "travel", "Solitude")

; Can this NPC fetch Nazeem?
Bool canFetch = IntelEngine.ValidateAction(npc, "fetch_npc", "Nazeem")

; Can this NPC lockpick this chest?
Bool canPick = IntelEngine.ValidateAction(npc, "lockpick", refID)
```

---

### GetActionFailureReason
```papyrus
String Function GetActionFailureReason(Actor akNPC, String actionType, String targetParam) Global Native
```

Get human-readable reason why an action would fail.

**Returns:**
- Failure reason string, empty if action is valid

**Example reasons:**
- "Cannot find anyone named 'Nazim' - did you mean 'Nazeem'?"
- "Upstairs is not accessible from here - no stairs found"
- "Lockpicking requires lockpicks (you have none)"

---

## String Utility Functions

### StringToLower
```papyrus
String Function StringToLower(String text) Global Native
```

Convert string to lowercase. ~2000x faster than Papyrus loop.

---

### StringContains
```papyrus
Bool Function StringContains(String haystack, String needle) Global Native
```

Check if string contains substring. ~2000x faster than Papyrus.

---

### LevenshteinDistance
```papyrus
Int Function LevenshteinDistance(String a, String b) Global Native
```

Calculate edit distance between two strings for fuzzy matching.

---

## Index Management

Indexes are built automatically from game data on startup. No external JSON files needed.

### IsIndexLoaded
```papyrus
Bool Function IsIndexLoaded() Global Native
```

Check if NPC and location indexes are built (should be true after game load).

---

### GetIndexStats
```papyrus
String Function GetIndexStats() Global Native
```

Get JSON with index statistics (cell count, location count, NPC count).

---

### RebuildNPCIndex
```papyrus
Function RebuildNPCIndex() Global Native
```

Rebuild NPC index from game data (call after major NPC changes).

---

### RebuildLocationIndex
```papyrus
Function RebuildLocationIndex() Global Native
```

Rebuild location index from game data.

---

## Decorator Registration

The DLL automatically registers these decorators with SkyrimNet on load:

| Decorator | Arguments | Returns | Description |
|-----------|-----------|---------|-------------|
| `can_resolve_location` | `actor`, `locationName` | bool | Can travel to this location? |
| `can_resolve_semantic` | `actor`, `term` | bool | Can resolve "upstairs" etc? |
| `can_find_npc` | `npcName` | bool | Does this NPC exist? |
| `get_npc_location` | `npcName` | string | Where is this NPC? |
| `validate_task` | `actor`, `taskType`, `target` | bool | Is task feasible? |
| `get_task_failure_reason` | `actor`, `taskType`, `target` | string | Why would task fail? |

---

## Performance Characteristics

| Operation | DLL Time | Papyrus Time | Speedup |
|-----------|----------|--------------|---------|
| Find NPC by name | <1ms | 500-2000ms | 500-2000x |
| Resolve location | <0.5ms | 50-200ms | 100-400x |
| Semantic resolution | <2ms | N/A (not possible) | - |
| String lowercase | <0.01ms | 20-50ms | 2000-5000x |
| Levenshtein distance | <0.1ms | 100-500ms | 1000-5000x |

---

## Error Handling

All functions return sensible defaults on error:
- Actor functions return `None`
- String functions return `""`
- Bool functions return `false`
- Numeric functions return `0` or `-1`

Errors are logged to `IntelEngine.log` in the SKSE logs folder.

---

## Thread Safety

All functions are thread-safe and can be called from multiple Papyrus threads simultaneously. Internal data structures use read-write locks for concurrent access.

---

## Memory Management

- NPC index: Built from all unique NPCs in game data (~5-10MB for vanilla + mods)
- Location index: Built from all Cells and BGSLocations (~2-5MB)
- Both indexes are built on game data load event
- Caches are cleared on cell change to prevent stale data
- Total memory footprint: ~10-15MB typical

---

## Building the DLL

Use the repository helper rather than cloning CommonLib or configuring CMake manually. From the repository root, choose a new, repository-local build directory that does not already contain a build (use a distinct name for each fresh build):

```powershell
Set-Location SKSE
.\BuildDLL.ps1 -BuildDir .\build-minll-fresh
```

`-BuildDir` accepts a path resolved from PowerShell's current location. The helper configures a Release Ninja build using the VS 2022 toolchain, x64-windows-static vcpkg triplet, and the static `/MT` runtime. It temporarily clears `SKYRIM_FOLDER` and `SKYRIM_MODS_FOLDER` before every configuration and build, then restores their prior values; it also restores process priority and vcpkg concurrency. The build writes to the chosen build directory and copies the result only to the canonical `SKSE/build/Release/IntelEngine.dll`, verifying that the two DLLs have matching SHA-256 hashes. It does not install or deploy the DLL to a game/mod directory. Keep the selected build directory inside the repository; do not use an installed-mod or other external destination.

The root `build.ps1` is an asset staging/deployment pipeline, not an isolated DLL build: `-SkipDeploy -SkipGit` still writes to its configured Data tree. Its DLL selection and the corresponding `verify.ps1` check use only the canonical path, with no stale-DLL fallback. `verify.ps1 -SkipDeployTargets` skips that DLL check and is not fresh-build proof.

`verify.ps1` is read-only. Its default Data root is the sibling `IntelEngine-GamePlugin` directory, relative to this repository; it no longer selects machine-specific mod directories automatically. Supply `-DataDir` to override that root and `-TestDest`, `-VanillaDest`, or `-CKDest` to check particular full-content deployment directories. Only supplied targets are checked. `-SkipDeployTargets` still omits both deployment checks and the canonical-DLL comparison; it checks source assets and retired loose content, not native build provenance.

```powershell
.\verify.ps1 -Quiet
.\verify.ps1 -DataDir D:\git\IntelEngine-GamePlugin -SkipDeployTargets
.\verify.ps1 -TestDest D:\Modlists\Example\mods\IntelEngine
```

The root `build.ps1` retains its existing toolkit/Data/deployment defaults. Pass its paths and opt-out flags explicitly; the verifier's defaults do not configure or authorize staging.

## Verification Evidence

Evidence must be described at the state actually observed; a source declaration or successful compile does not show installation, deployment, or runtime behavior.

### Historical RC1/RC2 checks (2026-10-05)

- **Source/configuration:** the plugin declares Independent struct compatibility and Address Library mode, with minimum SKSE version 0. The build enables Skyrim SE and AE and disables VR.
- **Original RC1 build:** the initial Ninja Release build in `SKSE/build-minll-989d4fb1` completed 513 steps and exported the expected SKSE entry points and Address Library metadata. Its DLL was 3,818,496 bytes, SHA-256 `69ce3e0c2797a561eb9311d8f3c398849d3513d6de1af642a64b792cea5fa2eb`. It was packaged as `IntelEngine-v3.5.2-rc1-dll.zip` and is now named `IntelEngine-v3.5.2-rc1-dllOnly.zip`; the archive still contains the original failing DLL, whose native metadata/log version is 3.5.1. This candidate is rejected for testing after the startup crash; successful compilation and metadata inspection did not establish ABI safety.
- **Installed RC1 incident artifact (historical):** at the time of the startup crash, the DLL in ADT's `IntelEngine-v3.5.2-rc1-dllOnly/SKSE/Plugins` folder matched the original RC1 hash. Read-only inspection established the selected `SkyrimNet_iActions_dev` profile with that mod enabled. This records the incident's installed-folder provenance, not the folder's later contents or a memory-image hash. No installed DLL was changed by the assistant.
- **Observed 1170 failure:** `crash-2026-10-05-20-17-52.log` faults in engine `TESObjectCELL::GetLocation` through `LocationHasKeyword` condition evaluation. The bad cell pointer is the actor's `SetParentCell` function address. Disassembly of the RC1 DLL shows saved-cell reads dispatching to slot `0x98`; the actual 1170 engine getter is at `0x97`. One compiled call loads the setter address into `RDX` before invoking it, matching the code-pointer-as-cell corruption.
- **Offline correction smoke:** the same engine-compatible saved-cell fixture compiled against the original header reported `FAIL: getter=0 setter=1 returned_expected=0 parent_unchanged=0`; with the generated corrected header it reported `PASS: getter=1 setter=0 returned_expected=1 parent_unchanged=1`. No Skyrim executable or plugin DLL was loaded by this fixture. The generated header SHA-256 is `066933f1dd09d4d2f0b681f90de4f9a4562a704bcbc3275178690afbfaf181ca`; the original LF-normalized header SHA-256 is `98a8a1cb24f51b893b4343c4c552e363d9bc90ee7a611c05f7719c2479bec2b6`.
- **Corrected compiled artifact:** all 513 source-build steps were attempted; the last link initially failed because the output DLL was held by the assistant's PE-inspection mapping. After closing that mapping, the remaining link succeeded. Fresh `SKSE/build-minll-989d4fb1/IntelEngine.dll` and canonical `SKSE/build/Release/IntelEngine.dll` are byte-identical: 3,818,496 bytes, SHA-256 `914d280e60f2183f627d1ca4fbbcaa89ea80f82d9fe9a39d673c8072f50a6ead`. Linked getter sites use `0x4B8` (slot `0x97`), not the former `0x4C0` (setter slot `0x98`); this was checked at the same four incident-relevant RVAs and across 24 indirect-call/load candidates. The three SKSE exports, native version 3.5.1, struct/address-library flags, and minimum SKSE 0 remain unchanged.
- **Corrected DLL-only package:** `SKSE/build/Release/IntelEngine-v3.5.2-rc2-dllOnly.zip` contains the corrected DLL plus ten license/notice files, without scripts or other gameplay assets. All eleven members were verified by byte comparison, ZIP CRC checks, and independent Windows ZIP extraction/hashing. The archive is 1,684,848 bytes, SHA-256 `09ffc0c11ccbe2883126738a8e2b09bbbfa1dce4dfab9e8091dbcfb1038e5f82`. RC2 is the package label; native metadata remains 3.5.1. The original RC1 archive still contains the rejected DLL.
- **Installed corrected artifact:** after the user's successful run, read-only inspection of the DLL in ADT's still-RC1-named enabled mod folder found the corrected `914d280e...` SHA-256 above. Folder/package names do not establish DLL identity. This is an installed-file hash, not a loaded-memory-image hash; the assistant did not replace the installed DLL or launch the game.
- **Observed corrected 1170 run:** the user's `SkyrimNetOutput_ADT_2026-10-05_21-23-25-556_7d79f3d1.zip`, correlated with separately captured native and SKSE logs, establishes Skyrim 1.6.1170.0, SKSE 2.2.6, and SkyrimNet Beta 26/API 12. IntelEngine loaded, registered 285 Papyrus functions, completed NPC/location indexing, and loaded a save. A dashboard FetchPerson request reached `ProximityMonitor::Arm`. Task arrival/completion and a serialized task save/reload round trip were not established by this capture.
- **IntelEngine runtime-audit limits:** the same session reports seven unavailable native static bindings and `None`-to-array cast errors in Core/Schedule Papyrus paths. Their cause and functional impact are not established; the loaded/VFS-winning script bytes were not captured. These findings are not proof of a new CommonLib ABI regression, and a DLL-only package does not update scripts.
- **Full runtime verification:** all five full NPC/location/action/save-load smoke scenarios remain incomplete. The corrected DLL has partial user-run evidence on 1.6.1170.0, not a full smoke pass; it has no established game run on 1.5.97.0, 1.6.640.0, 1.7.99.0, or 1.7.104.0. The separate original-RC1 user-reported 1.7.104.0 crash has no supplied crash log and no established shared signature. Further installation, game actions, deployment, commits, and publishing require separate authorization.

### VS 2022 flags-off full build and ADT checkpoint (2026-10-09)

- **Source/build:** PR #1 baseline `247290858f69eb0a270f928db10795f5ab51e2c1` plus the approved local CMake flag correction, without the parked VS 2026 or NPC tick phase-A changes. VS 2022 MSVC 19.44.35229 / toolset 14.44.35207 completed 513 build steps; all 511 compiler invocations use `/Od /Ob0 /std:c++23preview`, without `/O2`, `/std:c++latest`, `/d2ReducedOptimizeHugeFunctions`, `/GL`, or `/LTCG`. Ten cached vcpkg dependencies were restored; their compiler detection was VS 18, not proof that every dependency was rebuilt with VS 2022.
- **Packaged artifact:** `SKSE/build/Release/IntelEngine-PR1-2472908-vs2022-flags-off-full.zip`, 5,372,037 bytes, SHA-256 `043969edb3dc7f030d82d83698f143c0d86fe549887efd149f073e2e9ea75299`. The DLL is 5,638,144 bytes, SHA-256 `4f8eec94da652362cabca0a3f45c323baaef92bb03cf7e8567863ba6d1bc6c17`, native version 3.5.1. The full package includes all 11 freshly compiled PEX files and the rebuilt dashboard; 80 asset checks and independent extraction/byte checks passed. The adjacent manifest preserves build-time source and ZIP-member hashes; this checkpoint was added after packaging and does not change the ZIP.
- **Installed files:** the user's enabled ADT `SkyrimNet_iActions_dev` profile selects `IntelEngine-PR1-2472908-vs2022-flags-off-full`; the older candidates are disabled. All 48 installed FOMOD runtime payload files match the staged package, including the DLL hash above. This is installed-file evidence, not a loaded-memory-image hash. The assistant did not install the mod or launch/control the game.
- **Runtime observation:** the user reported "Seems to have worked for me" and supplied `SkyrimNetOutput_ADT_2026-10-09_18-34-29-330_c31f306f.zip`. Its validated indexed snapshot `c31f306f-ba81-481e-8e62-bccabf6a0101` selects the 13:32:14.379–13:34:18.420 session; `SkyrimNet.log:6` identifies Skyrim **1.6.1170.0**. Captured SKSE/native logs show IntelEngine loaded, registered 285 functions, refreshed the NPC index after save loading, opened the dashboard, and dispatched Saadia's message through Hulda with a proximity monitor armed.
- **Contributor confirmation:** the user subsequently reported that Epicrob confirmed the corrected build worked on his affected **1.7.x** setup. This closes the reported black-screen compatibility check for his setup as contributor-reported success. The exact patch version, installed DLL hash, and logs for his run were not supplied; this is not independently log-verified coverage of every 1.7.x runtime.
- **Save evidence and limits:** native loading recovered one active Amren story slot from the co-save; a later save wrote active-slot state. This is serialization evidence, not proof that every task must resume: `seek_player` story dispatch is deliberately abandoned on load by the existing Papyrus code. The ADT capture does not establish Hulda's message arrival/completion, a new dispatched task's save/reload round trip, or a fix for CTD issue #15. Existing Papyrus and translation backlog fixes remain excluded; SKSE still reports the English translation encoding warning.
- **Supplemental log identity:** bounded copies captured at 18:37:41 UTC preserve native log SHA-256 `488144e167f22804c999d360c1fe847b5319c7fc674b76adb43cf3a8aaff3677` (180,659 bytes) and SKSE log SHA-256 `53e83934b8c85c94f3e0a3f4d2df7d83bf288dc08b66a3dd0c889b88d3bf5867` (47,150 bytes). Native lines 1754–1758 record save/index recovery; 1797–1803 record dashboard/message dispatch; SKSE line 186 records plugin acceptance. These are the captured logs, not an unbounded audit of a later live file.


## Testing

Test functions are exposed for validation:

```papyrus
; Test NPC search
IntelEngine.TestNPCSearch("Nazeem")  ; Should find and log

; Test location resolution
IntelEngine.TestLocationResolve("upstairs")  ; Context-dependent

; Test validation
IntelEngine.TestValidation("fetch_npc", "Nazeem")
```
