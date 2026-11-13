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
- The shared SE/AE/VR build uses the pinned fork's cross-VR wrappers: `GetSaveParentCell` selects slot `0x97` on SE/AE and `0x98` on VR. CMake retains the upstream header fingerprint guard and the flat-only `Unk_8C` correction for non-VR configurations; the mixed configuration does not apply that virtual-table transformation. Both targets inherit the same declarations.
- The 3.6.0 shared build includes Skyrim SE, AE and VR with Address Library compatibility. The documented SE/AE targets are **1.5.97.0, 1.6.640.0, 1.6.1170.0, 1.7.99.0, and 1.7.104.0**; Skyrim VR **1.4.15 / SKSEVR 2.0.12** should work and was partly tested. Tested runtimes: **1.6.1170.0 and 1.7.104.0**. Skyrim SE **1.5.x**: untested. Other listed targets are untested. Partial testing does not establish full VR qualification or every gameplay scenario.
- Offline synthetic-vtable checks and linked dispatch/import inspection passed. Packaged startup and fresh/converted-save smoke passed on 1.6.1170 and 1.7.104; VR coverage remains partial.
- Offline getter regression: build and run `ReferenceGetterDispatchCheck` from your configured build directory. It invokes the production CommonLib getter on synthetic SE, AE and VR vtables, checks the returned cell and unchanged parent/setter count, and exits nonzero on failure. `--wrong-slot` deliberately moves the fixture getter onto the adjacent setter slot and must exit 1.

## Papyrus API

All functions are exposed to Papyrus via the `IntelEngine` script namespace.

### Story load recovery
`Bool Function StoryLoadRecovered(Bool complete = false) Global Native` reads a nonpersisted, atomic readiness marker. Passing `true` marks StoryEngine load recovery complete; only `RestartMonitoring` does this after cleanup. Preload and serialization revert reset it, including same-process reloads. `CheckStoryNPCArrival` does nothing while it is false. A saved Papyrus property cannot provide this per-load boundary.

### Travel diagnostics
`String Function DescribeDistance(ObjectReference a, ObjectReference b) Global Native` returns `dist=<rounded 3D game units> sameSpace=yes` only for the same interior cell or matching nonnull exterior worldspaces. Null references, missing cells and different spaces return `sameSpace=no` without a distance.

Native `[diag:*]` logs require `DebugLevel=4`; Papyrus diagnostics use the existing MCM debug toggle. Off-screen phase-2 logs include actor/player context, movement and stationary ticks; phase 1 retains only initialization logging. Caller-status and linger logs are limited to once per ten real seconds per NPC. `[diag:path]` start/end pairs bracket the three remaining latent recovery calls without changing them. Offline production logic checks: `python SKSE/tests/RunDiagnosticCheck.py <vcpkg-triplet-dir>`. These checks do not establish live behavior.

### Read-only political feeds (pipe 2)

```papyrus
String Function GetPoliticalEventsAfter(Int afterId, Int limit = 50) Global Native
String Function GetFactionsJson() Global Native
```

Both return JSON with `schema_version: 1`, `save_id`, `db_uuid`, `load_id`, and `ready`. `db_uuid` is persisted per database generation and changes on deletion/recreation even with the same save ID. `load_id` changes on every load, including reloading the same save. Discard both caches and reset the event cursor when either identity changes; wait for `ready: true` before reading a new baseline. Readiness drops at load/revert and remains false until DB initialization and timeline cleanup succeed. A cleanup error logs a warning and keeps that load not ready. Not-ready responses contain empty data arrays.

`GetPoliticalEventsAfter` reads events in ascending ID order, strictly after `afterId` (negative cursors mean zero). `limit <= 0` means 50; limits above 200 are capped at 200. It returns `events`, `next_cursor` (last returned ID, or the normalized input cursor when empty), and `has_more`. IDs are not reused after timeline rollback. The feed retains all event types, including `pe_*` and replay-only `relation_adjustment`; consumers decide which to ignore. Loading a save does not create historical news.

Each event contains `id`, nullable `game_time`, `type`, `faction_a`, `faction_b`, `delta`, `description`, `location_name` (empty when unknown), and `position`. Position is explicitly null unless a reliable physical battle spawn was captured. Otherwise it contains `worldspace` (exterior) or `cell` (interior), the unused identity set to null, and finite `x`, `y`, `z` in game units. Each identity is `{plugin: "Origin.esm", local_id: 123}`: the originating filename and numeric plugin-local FormID, independent of load-order indices. Dynamic or unowned spaces remain null. Capture uses shared actor registration, including late-arrival spawns. Battle results record this position on both active-war and no-war finalization paths; no hold-centre or named-marker substitution is made.

Manifested assassination/brawl/skirmish rows remain position-null: they precede scene spawning, and the forward-only feed cannot deliver later position updates. Offscreen/narrative events also remain null.

`GetFactionsJson` returns `factions` with `id`, `name`, `hold`, `skyrim_faction_id`, `disbanded`, `allies`, and `rivals`, plus `revision`. Compare revisions only within the same `db_uuid`/`load_id`. The in-memory counter resets for a new load and advances on successful config reloads and observed disband/undisband transitions. Leader liveness is polled on getter reads; transitions entirely between reads are not tracked. A disbanded organization remains in the array.

Offline production-backed check (VS developer shell): `python SKSE/tests/RunPoliticalFeedCheck.py <vcpkg-triplet-dir>`. It covers pagination/limit edges, rollback cursors, DB recreation/load identities, readiness/failure latching, legacy schema upgrade and explicit 3.7-style reader/writer compatibility, retained PE events, narrative null positions, organization revisions, and battle position capture/persistence with modeled engine objects. Offline evidence does not establish Papyrus VM or live PE integration.


### FriendlyKey
```papyrus
String Function FriendlyKey(String key) Global Native
```
Replaces underscores with spaces and uppercases an ASCII lowercase letter at each word start; preserves other characters and existing case. Empty input stays empty. Example: `war_declaration` → `War Declaration`. Director notice fallback only; supplied event labels remain unchanged.

### SkyrimNet speech state

```papyrus
Bool Function IsNPCSpeechPending(Actor akActor) Global Native
Float Function GetSecondsSinceNPCSpoke(Actor akActor) Global Native
```

`IsNPCSpeechPending` is true while SkyrimNet has a generated line of this NPC queued, being synthesized or audible. The DLL listens to SkyrimNet's outbound mod events (`SkyrimNet_SpeechStarted`, `SkyrimNet_AudioStarted`, `SkyrimNet_AudioEnded`), so it is also true in the seconds before the voice starts, which `IsActorTalking` cannot see. Narration segments are ignored. A queued segment that never becomes audible stops counting after 20 seconds, an audible one whose end notice never comes after 60. `GetSecondsSinceNPCSpoke` returns the real seconds since the NPC's last generated line stopped, or -1 when none was heard since the load. The state is per session and is cleared on load and on a new game. When SkyrimNet sends no such events (outbound mod events switched off, or an older version) both stay at "nothing pending" and -1, so callers use `IsActorTalking` beside them; `Core.LetFinishSpeaking` does. Offline check: `python SKSE/tests/RunSpeechTrackerCheck.py <vcpkg-triplet-dir>`.

### SkyrimNet package contract

```papyrus
Int Function GetSkyrimNetPackageApiVersion() Global Native
```

Returns the version of SkyrimNet's package contract (`PublicGetPackageApiVersion`), 0 when the installed SkyrimNet has none. `SkyrimNetApi.ListPackage`, `HoldPackages`, `ReleaseHeldPackages` and `UnregisterPackageEx` may only be called when this is 1 or more. Core lists each running task on SkyrimNet's package page under the owner `IntelEngine` and cancels the task when the row is removed there.

### Settings shared with SkyrimNet's settings page

```papyrus
Int Function SyncPluginSettings(String configJson) Global Native
Int Function ApplyPluginSettings(String configJson) Global Native
```

The gameplay settings of the MCM and the dashboard are also offered on SkyrimNet's plugin settings page. The fields come from `config/plugins/IntelEngine/manifest.yaml`, the values live in `config/plugins/IntelEngine/settings.yaml`, and one table (`SKSE/src/SettingsBridge.cpp`) names every shared setting with its range, default and the setting event that changes it. `configJson` is `Core.BuildConfigJson()`.

- `SyncPluginSettings`: the game wins. Every table value that differs from the file is written to it. Returns the number written. Called after a change in the MCM or on the dashboard, and once for a save from before the settings were shared.
- `ApplyPluginSettings`: the file wins. For every value that differs, the DLL sends the existing setting event (`IntelEngine_DashboardSetting` with the same key, or `IntelEngine_DashboardToggleStory` for a story type), then reloads the politics settings. A value the file lacks is filled in from the game; one that cannot be read (unknown choice, not a number) leaves the game as it is. Returns the number of settings that change. Called after a save on SkyrimNet's page (`SkyrimNet_OnPluginConfigSaved`) and on every load, so a new game starts with what the player set.

`configJson` is not trusted to be JSON as written. Script strings are case-insensitive in the game: a script's `true` arrives as `TRUE` or `True` when any other script used that spelling first, and a key can change case the same way. `SettingsBridge::ParseConfig` reads `true`, `false` and `null` in any case outside quoted text and looks the table's keys up without regard to case. Text that is still not a JSON object is refused with a warning in `IntelEngine.log` and nothing is synced. Any new native that parses JSON built by a script needs the same treatment (the dashboard state does it in `DashboardUIManager::ProcessFullState`).

The block of fields in `manifest.yaml` between the `>>> settings shared with the game` markers is generated from the table: `python SKSE/tests/RunSettingsBridgeCheck.py <vcpkg-triplet-dir> --write` rewrites it, and the same script without `--write` fails when the file and the table differ.

Checked in game on 2026-11-13 (SkyrimNet 1.1.1 Alpha, Skyrim 1.5.97): a new game adds the 59 settings to a file that lacks them; a save through SkyrimNet's `config?api=update` arrives as setting events within a second; a setting event on the game side is written to the file; loading a save made before a change on the page takes the file's values. Not exercised in game: a save from before the settings were shared (it calls the same `SyncPluginSettings`).

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

When the SkyrimNet API is available, the DLL registers one decorator on load (soft dependency: skipped if the API is missing):

| Decorator | Arguments | Returns | Description |
|-----------|-----------|---------|-------------|
| `get_intelengine_quests` | `actor` (unused) | string | Active IntelEngine quest details (location, type, briefing, objectives). Use instead of the generic quest list entry for IntelEngine quests. |

The IntelEngine prompts use SkyrimNet's own `get_place_names("nearby")` for location names.

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

## Rendered Cache Persistence

```papyrus
String Function EncodeRenderedCache(String text) Global Native
```

The Native-owned encoder preserves plain Markdown renderer APIs and the scalar-cache workaround for immediate same-session visibility. Core calls it exactly once immediately before the four complete writes: task history, shared `InjectFact`, receiver gossip and giver gossip. Join each participant's heard+told sections first. Existing list storage/rendering and render-mode gates are unchanged.

One bytewise pass maps `%` → `%25`, BEL → `%07`, TAB → `%09`, LF → `%0A`, VT → `%0B`, FF → `%0C`, CR → `%0D`, ESC → `%1B`. Empty input stays empty; spaces, UTF-8, quotes and backslashes are unchanged. Embedded NUL/binary text is unsupported. The three cached readers reverse the seven control tokens, then `%25` **LAST**, once, before checking emptiness/output. This is neither URI decoding nor an idempotent encoder.

Native text caps now retain complete UTF-8 code points: delivery-message task descriptions retain at most 80 bytes before `...`, and political event/battle narratives and dispatch prompt history use the same boundary helper with their existing caps/suffixes. This prevents new split-code-point text; it does not repair suffixes already lost in historical saves. `Utf8TruncateCheck` is the standalone boundary check. Source/build verification is separate from packaging, installation and in-game acceptance.

**BREAKING / coherent providers required:** start a fresh new game with the repaired DLL, freshly compiled `IntelEngine.pex`/`IntelEngine_Core.pex` and all three repaired prompts already winning, or use only an eligible offline-converted copy as described below. Unconverted existing saves, including apparently cache-free saves, remain unsupported: old values can poison restoration before scripts run or ambiguously decode literal percent text. There is no raw fallback or general post-load safety guarantee.

Native owns C++/PSC/templates; Game is the Data-layout mirror. Keep both PSC trees and all three prompt pairs byte-identical; `verify.ps1 -DataDir <Game tree>` checks every PSC and the existing prompt bundle. Mirror this API document explicitly (root staging does not copy docs). Source equality does not prove DLL/PEX freshness, packaged equality does not identify installed winners, and neither proves runtime behavior. Stop on new PEX/old DLL missing binding, old Core PEX/new DLL raw writes, old templates/new encoded caches, or ambiguous providers; do not assume an unbound call's result.

Rollback requires the complete old DLL/PEX/template set and its separately preserved pre-cutover save lineage. Do not load repaired saves under old components or rewrite evidence saves.

### 3.6.0 NPC Social DM scheduling repair

`BeginAsyncNPCDMTick` queues Phase A through SKSE tasks; Papyrus invocation is not a main-thread guarantee. Quest editor-ID inspection, actor/player/cell/race/faction reads, cooldown/calendar reads, inn detection and the empty callback run in that task. Only owned strings/scalars/IDs cross to Phase B. Phase C publishes the result's candidate pool and dispatches the callback on the main thread after validating `SlotTracker::loadGeneration`; revert invalidates queued snapshots/results and clears the social pool. The worker no longer publishes that pool.

Phase B still calls SkyrimNet's FormID/value APIs and reads bio files; this change does not establish the external provider's internal thread safety. No faction-name null/vtable workaround, Papyrus signature, serialization change, synchronous-API scheduling repair, Story/Political tick change or request-isolation contract is included. A discarded old-save tick intentionally does not call into the newly loaded save. Existing pending recovery remains in use (watchdog timeout: one game hour); task-interface failure still logs and drops the tick.

Offline check: compile `SKSE/tests/NPCTickGenerationCheck.cpp` in a VS2022 amd64 developer shell with `/std:c++20 /EHsc /W4 /WX /I SKSE/src`, then run the executable. It exercises production result publication: current/empty pools, duplicate names, revert clearing and stale results after subsequent loads. It does not exercise SKSE task dispatch or prove engine thread safety.

SE/AE soaks passed. Instrumented thread identity and stale-result drop on reload remain unverified; 1.5.97 remains untested. To verify on 1.6.1170, use a symbolized build with independently verified loaded DLL identity; enable debug logging and compare debugger thread IDs at `[NPCTick] Phase A snapshot`, the existing `async context` worker log, and `Phase C callback`. Phase A/C and the empty callback must match the engine main thread, not the Papyrus VM job thread; Phase B must differ. Exercise nonempty/empty ticks, named/unnamed factions, non-ASCII names, cell transitions, and loads with Phase A queued, Phase B blocked and Phase C queued. Expect generation-change drop logs and no old pool/callback; verify pending recovery and fresh ticks. On 1.5.97, the reporter should repeat Aela/Jenassa/Torvar contexts with NPC interactions enabled, retain DLL/PDB identity and collect logs/minidumps if faction-name dispatch still faults. A finite crash-free run is not proof of the exact CTD's cause or cure.

### 3.6.0 Story DM type filtering (#3)

The async Story DM path parses exclusions once and shares that set between prompt visibility flags and the session-count formatter. Excluded types are omitted from "Story Type Picks This Session"; NPC Social DM counts are unchanged. This does not remove type names from dispatch history or general guidance, and response validation remains the dispatch gate.

Offline check (requires `clang++`): `python SKSE/tests/RunStoryTypeCountFilterCheck.py`. It compiles the production formatter without the game ABI and checks allowed/excluded counts, empty/all exclusions, exact top-level matching and unchanged NPC counts. No in-game qualification is implied.


### Player fix mode: How to convert an old save

The standalone Windows tool includes a one-save `fix` command for eligible SE/AE saves from IntelEngine 3.5.2 or earlier and VR 1.4.15 saves from VR-capable IntelEngine 3.5.1 or earlier. One real 3.5.2 save per qualified SE/AE runtime and one real 3.5.1 VR fixture passed bounded acceptance; older versions are format-gated, not separately tested. Fix does not read the IntelEngine version. Run it from anywhere: no installed PapyrusUtil hash, VFS or game-root placement is required. Qualification uses SKSE co-save format 1, exactly one PapyrusUtil owner `0x424510A2`, complete framing and, when present, exactly one STRV v1 record. Exact SKSE/runtime pairs: **0x02000140 / 1.5.97.0** (SKSE64 2.0.20; runtime DWORD `0x01050610`, untested), **0x02020060, 0x02020070 or 0x02020080 / 1.6.1170.0** (SKSE64 2.2.6–2.2.8), **0x02030010 / 1.7.104.0**, or **0x020000C0 / VR 1.4.15** (runtime DWORD `0x010400F1`, SKSEVR 2.0.12). VR also requires a bounded `TESV_SAVEGAME` ESS version-12 header. Other formats/header pairs refuse. Expert 1.5.97 and VR `convert` remain refused: no historical PapyrusUtil provider hash is qualified for either. `inspect` recognizes these tuples but never grants conversion eligibility.

Source derivation: [SKSE64 v2.0.20](https://github.com/ianpatt/skse64/blob/0d6c91dc84f1d384da113bec9e298867a5c86ce1/skse64_common/skse_version.h) defines `MAKE_EXE_VERSION_EX`/`PACKED_SKSE_VERSION` and `RUNTIME_VERSION_1_5_97`, yielding SKSE `0x02000140` and runtime `0x01050610`; `Serialization.cpp` writes those version words.

The [SKSE release history](https://github.com/ianpatt/skse64/blob/v2.2.8/skse64_whatsnew.txt) records 1.6.1170 support in 2.2.6 and maintenance releases 2.2.7/2.2.8. The tagged [2.2.7](https://github.com/ianpatt/skse64/blob/v2.2.7/skse64_common/skse_version.h) and [2.2.8](https://github.com/ianpatt/skse64/blob/v2.2.8/skse64_common/skse_version.h) headers both set `CURRENT_RELEASE_RUNTIME` to `RUNTIME_VERSION_1_6_1170`. These header additions do not expand the Skyrim runtime set or establish new in-game acceptance.

**Convert before loading an old save with 3.6.0.** An unconverted VR copy restored and progressed its Travel task, but three of four original populated facts caches read back empty, the fourth only as a header, and both original rendered histories read back empty despite some raw history remaining. An earlier process crashed with cause unproven; the evidence does not establish that it read the unconverted pair. Task recovery does not establish safe unconverted loading.

Only the three rendered-cache keys are rewritten. Other plugins' blocks, including duplicate unrelated owner IDs, and non-target keys, values and identity types pass through without decoding, normalization or re-encoding. Non-target control bytes and noncanonical text do not disqualify the target. Cache expansion adjusts enclosing STRV/plugin lengths; reverse-patch verification proves every other byte unchanged, and publication verifies the written output hashes. Inspection reports text-unsafe keys as `key_hex` instead of invalid JSON text.

After rewriting, target-only verification follows [PapyrusUtil's native scalar extraction](https://github.com/eeveelo/PapyrusUtil/blob/master/Data.cpp#L978-L1024): native whitespace, declared object/entry counts and the first NUL boundary. Every native cache assignment must match the expected serialized identity, key and value span, with no hidden extra or missing target. Opaque bytes remain unchanged, but a shifted, overwritten or hidden cache target refuses as ambiguous. Other mods' values and identities are not qualified or repaired.
Native cache keys with no extractable value also refuse, including aliases exposed by whitespace and a NUL boundary inside otherwise opaque fields.

When STRV is absent, player `fix` permits a verified byte-identical cache-free pair only if the PapyrusUtil owner exists and its other record types/versions are recognized: MODS/PLGN v0 or INTV/FLOV/FORV/INTL/FLOL/STRL/FORL/PKGO v1. It verifies outer framing/counts/EOF and runtime/ESS gates, not opaque-record semantics, and uses the same exclusive backup/staging/publication path. Unknown records/versions, missing owner, malformed STRV or a present STRV without eligible cache targets refuse. This is a copy, not a repair; expert mode retains its STRV/provenance requirement.

Offline production byte comparisons passed after safety corrections on two preserved save pairs: one produced 29 caches / 44 name spans, the other 13 caches / 28 name spans. Both ESS outputs were unchanged and preserved-source hashes matched. The unmodified shipped batch and production CLI succeeded with Skyrim closed on ASCII and Unicode/space scratch paths; the actual CLI also correctly refused while Skyrim was running. Migration/codec checks and refusal/partial-publication regressions passed. Offline byte reproduction is distinct from the bounded historical converted-copy runtime acceptance below; detailed evidence is maintained privately.

1. Close Skyrim. Keep the same-directory, same-stem `.ess` and `.skse` pair together. Make sure you have a backup of IntelEngine and SkyrimNet external data as well if you may need timeline rollback.
2. Put `LegacyCacheMigration.exe` beside `Convert-IE-Save.bat`, or run it directly from any working directory. Drag exactly one `.ess` onto the adjacent batch file, or run:

   ```powershell
   & ".\IntelEngineTools\LegacyCacheMigration.exe" fix --save ".\My Save.ess"
   ```

3. Success creates `<stem>_IEbackup/` containing the original `.ess` and `.skse`, plus sibling `<stem>_IEconverted.ess` and `<stem>_IEconverted.skse`. The tool does not overwrite existing backup/output files. It leaves the original pair unchanged.
   Player `fix` reports each converted cache, each unique temporary identity (decimal object ID and hexadecimal form ID), and each orphaned global cache key on separate lines. Its conversion result records temporary holders in `temporary_identities` and converted global keys in `global_entries`; expert JSON receipts and inspection output are unchanged.
4. Exit **0** means both verified converted files were published; **2** means usage, eligibility or safety refusal; **3** means I/O, verification or publication failure. If publishing the second file fails, the first converted file may remain. This is an incomplete pair: do not load it, and retain the backup and all remaining files for diagnosis.
5. Install the complete repaired providers (DLL, both affected PEX files and all three prompts) before using the converted pair. Never load a converted save with 3.5.2 or earlier. Do not convert again, mix original and converted companions, or assume already-lost names/history can be recovered.

Linked/cloud-managed components and extended/device paths remain unsupported. Copy **both** `.ess` and `.skse` to a short writable normal physical folder, e.g. `C:\IE-convert`, preserving the originals; Desktop/Documents may themselves be cloud-managed. Ordinary `.\My Save.ess` spelling and case-insensitive `.ess` extensions are accepted without renaming the input. Refusals identify resolved companion paths/OS errors, matched game executable/PID, detected and supported runtime/SKSE tuples, and retained output collisions. Inspect retained artifacts and retry the original pair in a fresh physical folder; never overwrite backups or load an incomplete pair.

Rollback means restoring the preserved original pair with its matching old providers and the corresponding IntelEngine/SkyrimNet external-data snapshot. The pair backup does not include external databases or their `-wal`/`-shm` files. Do not mix saves/providers or claim general legacy-save safety.

`fix` refuses input stems ending in `_IEconverted` (case-insensitive). It also refuses the whole save if any rendered-cache value contains `%0A` without a raw LF, naming the first such object/key: nonempty rendered sections begin with a heading and LF, which 3.6 encodes. If other target values contain raw LF, the refusal identifies mixed legacy/3.6 caches; header-only stubs without either are neutral. Already-encoded saves should load directly with IntelEngine 3.6.x, not be converted again. Support-only escape hatch: `fix --save FILE.ess --force` skips only this structural check and can double-encode text; all other refusals remain active.

The historical writer's identity/provenance cannot be proved from the file. Treating serialized BEL as a space is owner policy, not recovered original text. The required real-template smoke rendered all three full fixed prompts through Inja commit `affabd9fb6e679b2535382063e11ac9cc5ff860c`. Legacy literal `%07%09%0A%0B%0C%0D%1B%25%250A%0a%41%07` produced payload bytes `07090A0B0C0D1B2525304125306125343107`: the upper-case control tokens became their control bytes, `%25` became `%`, `%250A` became literal `%0A` without recursion, and lowercase `%0a` / unknown `%41` remained literal. Encoding that same literal input with the production codec preserved it through all three templates. This measured decoder behavior does not establish that native restoration of legacy percent text is safe.

### Offline legacy-save conversion

The standalone Windows converter's player `fix` mode supports eligible SE/AE saves from IntelEngine 3.5.2 or earlier on Skyrim **1.5.97 / SKSE64 2.0.20**, **1.6.1170.0** and **1.7.104.0**, and eligible VR-capable IE 3.5.1-or-earlier saves on **VR 1.4.15 / SKSEVR 2.0.12**; it does not support arbitrary existing saves. Real-save acceptance covers 3.5.2 SE/AE saves and one 3.5.1 VR fixture; 1.5.97 has synthetic coverage only. Older versions remain format-gated and are refused otherwise. Expert `convert` remains limited to the separately qualified 1.6.1170.0 and 1.7.104.0 provider/runtime pairs. One real 1.6.1170 legacy save passed converted-copy acceptance: 28/28 sampled surviving cache values matched exact UTF-8, plus one explicitly policy-derived facts field; a separate checkpoint retained these and two naturally generated fresh caches (31 fields) through warm and independent cold reloads. Named production facts/gossip templates passed for two sampled actors. All 42 resolvable original names matched; two temporary-actor name spans were preserved byte-for-byte but **not live-verified**. This is not full-HUD or general form-resolution qualification.

The 1.7.104 qualification covers **one bounded converted-copy acceptance**: a uniquely framed co-save, 11/11 independently sampled caches and two explicitly owner-policy fields retained exactly through a new checkpoint, warm reload and independent cold reload. All 24 qualified live names matched; four other holders remain unverified and were omitted from the new checkpoint, while all 28 original/converted name spans were preserved. Natural UTF-8 survived storage/reloads and actual facts/gossip/task-history prompt checks; the API's blank-line normalization is reported separately from stored-byte equality. Its runtime, SKSE header and provider hash remain a separate exact tuple; mismatches still refuse. An initial attempt crashed with causation unresolved; the authorized recovery passed these migration checks, not a general stability or unrelated-feature qualification. This does not qualify arbitrary saves, unreadable holders, fresh-cache generation in that checkpoint, or every 1.7 configuration.

VR `fix` reuses the shared repair path for eligible VR-capable IE 3.5.1-or-earlier saves; IE 3.5.2 disabled VR. One real 3.5.1 VR fixture passed repair of six facts/task-history caches with all non-cache bytes preserved, task recovery/progression, a roughly 39-minute sampled soak and one cold reload. All 66 cold cache comparisons matched; 76/77 state fields matched, with a small scalar deadline difference and unexplained SkyrimNet timeline differences. Three actor mappings were absent before and after, not demonstrated cold-reload loss. The fixture had no gossip caches or stored names, so populated gossip/name migration is synthetic-only on VR. The original SkyrimNet database baseline, historical database restoration and native name index were not established. This does not close full VR/core-action, package/MCM, real-headset or general old-save qualification.

#### Eligibility and refusal policy

- Require complete supported SKSE/STRV framing, exact counts and EOF, exactly one PapyrusUtil owner and STRV record, canonical lowercase target keys, pinned provider/runtime/codec provenance and evidence covering **every** target: `intel_factsrendered`, `intel_gossiprendered`, `intel_taskhistoryrendered`. Inspection alone never grants eligibility.
- Expert `actor-in-place` requires explicit `legacy_writer: "IE-3.5.2"`, `actor_bel_policy: "space"` and `preserve_rne_name_bel: true` in both the evidence and qualification basis. It preserves serialized identities without resolving/remapping forms. Only qualified actor identities carrying caches are eligible; temporary cache targets still refuse expert conversion. Player `fix` instead accepts `0xFF` cache holders with serialized actor type `62` and a nonzero form, plus orphaned global (object `0`) cache entries, re-encoding their values in place through the same owner-policy path as other actors. The non-global identity check remains unchanged: non-62 types and zero forms refuse. Non-target holders pass through, not declared runtime-qualified.
- In the actor cache policy (also used for global entries in player `fix`), serialized BEL means space and LF is allowed within a complete cache value. Player `fix` additionally admits TAB, VT, FF, CR and embedded ESC, and preserves malformed UTF-8 value bytes through the bytewise codec without transcoding/replacement; a lone ESC remains an ambiguous empty sentinel and refuses. NUL, DEL and unsupported C0 controls still refuse. Native assignment and reverse-patch proofs remain mandatory. Expert mode retains strict UTF-8 and its original BEL/ESC/control policy. Restored-original bytes must agree with the BEL-restored span. Non-cache values, including `rne_name` and task destinations, preserve all bytes without interpretation. `legacy` cache fields require independent original-byte evidence; `legacy-policy` cache fields additionally declare `original_basis: "owner-policy"`.
- Expert global mode remains stricter for targets: every cache identity must be global, legacy BEL/ESC collisions refuse, and every target needs independent original-byte evidence. Neither expert scope guesses unknown target sentinel meanings. Already-encoded fields require a pinned writer codec and exact expected original bytes; literal percent text or a filename does not prove encoding.
- Refuse the whole candidate on truncation, ambiguous target framing, duplicate PapyrusUtil owners or STRV records, declared/written count gaps (including skipped empty maps), unsupported target version/identity/key, duplicate or noncanonical target keys, repeated object identities involving a target, missing/duplicate/extraneous field evidence, mismatched spans/hashes, unknown target representation or unpinned encoded generation. No partial salvage or force switch.
- Refuse unmatched companion pairs, source drift, existing/overlapping destinations, unsafe aliases/reparse paths and protected save-directory destinations. Copy-only checks do not prove installation or runtime behavior.

#### Copy-only procedure

1. Close the game. Preserve a matching same-directory, same-stem `.ess` + `.skse` pair and any source archive; work on copies outside live save directories. Back up IntelEngine backing data, including `IntelEngine-<id>.db` and any `-wal`/`-shm` companions, **and SkyrimNet backing databases/data**. The converter backs up only the save pair; neither engine's external database is inside that pair. Loading an earlier save can permanently rewind the playthrough's shared political timeline.
2. Use the Native repository's standalone `SKSE/migration` build, independent of the DLL. On Windows, configure it with CMake and the existing `nlohmann_json` package via `CMAKE_PREFIX_PATH`, then build `LegacyCacheMigration` and `LegacyCacheMigrationCheck`. Do not substitute a different production codec header.
3. Inspect the copied co-save:

   ```powershell
   & ./LegacyCacheMigration.exe inspect --skse ./input/checkpoint.skse
   ```

4. Obtain source-specific, qualified `evidence.json` and `qualification.json`; these are not generated by `inspect`. Evidence schema 1 binds pair/provider/runtime/codec/qualification hashes and scope. Each field binds decimal-string `object`, exact `key`, byte `start`/`end`, provenance `evidence`, `original_hex` and `representation` (`legacy`, `legacy-policy` or `encoded`); encoded fields also pin `writer_codec_sha256`. The qualification receipt binds provider/runtime/scope and `owner_authorized_offline: true`. Do not copy another save's receipt or invent provenance to bypass a refusal.
5. Convert with **new**, separate backup/output directories outside all protected/input directories. Replace the example live-save directory with the actual one; repeat `--protected-dir` for every other protected directory:

   ```powershell
   & ./LegacyCacheMigration.exe convert --ess ./input/checkpoint.ess --skse ./input/checkpoint.skse --evidence ./proof/evidence.json --qualification ./proof/qualification.json --codec ./SKSE/src/RenderedCacheCodec.h --backup ./migration-backup --output ./migration-output --protected-dir "$liveSaveDirectory"
   ```

   Set `$liveSaveDirectory` to your existing live save directory before running. Optional `--archive FILE` requires matching archive/member hashes and independent membership evidence; the tool hashes but does not extract/authenticate archive membership.
6. Require successful `verified_offline_conversion` output and a published directory containing `converted.ess`, `converted.skse` and `manifest.json`. Originals are read-locked; `original.ess`/`original.skse` backups are hash-verified and made read-only. Output uses verified staging and no-replace publication; the ESS is unchanged, only qualified co-save spans and necessary enclosing lengths change. Encoded-only `no_conversion` publishes nothing. On refusal/failure, retain diagnostics/backups and do not load staging or incomplete output.
7. Install the **complete repaired** DLL/PEX/prompt set before manually copying the new pair into an isolated test save location. The tool never installs or loads it. Compare pre-frozen surviving names/text and actual named prompts, then a separate checkpoint's retained and freshly generated caches through warm and independent cold reloads before adopting that lineage. **Never load a converted save with 3.5.2 or earlier.**

**Rollback:** with the game closed, select the preserved original `.ess`/`.skse` pair with its complete matching old providers, and restore the corresponding IntelEngine/SkyrimNet backing-data snapshot when reverting that timeline. Keep the converted/repaired lineage separate; do not downgrade its saves or mix a pair from different checkpoints. Conversion preserves surviving serialized values, not already-lost names/history, truncated suffixes or unsaved session state; it cannot infer unknown sentinel meanings.

#### Converter checks

The Native source check `SKSE/tests/LegacyCacheMigrationCheck.cpp` uses the production codec and actual converter/transaction code. Run `LegacyCacheMigrationCheck.exe <new-unused-scratch-directory>` after building the standalone targets. It covers global/actor all-family bytes, policy/control/identity/count/framing refusals, mixed/encoded preservation, unchanged names/opaque bytes, exclusive backups and interrupted/failed publication. `SKSE/tests/RenderedCacheCodecCheck.cpp` covers the codec contract. Synthetic byte fixtures are not loadable saves; these checks do not replace the bounded runtime observations above.

### 3.6.0 NPC bio Content Library lookup (#18)

`MemoryDB::GetNPCBioSummary` and `GetNPCBioRelationships` read the same selected bio.
SkyrimNet's public API returns the template name, not resolved content; the optional
`PublicGetSaveUniqueID` export supplies the current playthrough ID. No new required
export, dependency, game ABI, or save format is introduced.

The reader makes a dynamic pass, then a static pass. Each pass checks the current
save (only with a usable ID), overlay, sorted external directories, then sorted
library directories with `skyrimnet.base` last. Missing save identity never triggers
an all-save Content Library search. Legacy roots and fuzzy matching remain the
last resort, retaining the existing legacy-only all-save fallback when identity is
unavailable.

This release-week resolver deliberately ignores registry priority, pins, provider
enable/missing state, activation and semantic versions. When two bio packs define
the same NPC, sorted-name order may differ from SkyrimNet's registry priority;
disabled or superseded on-disk copies can also be selected. It is not SkyrimNet's
content resolver. A future supported public content-reading API is the replacement
path, not another local mirror of SkyrimNet internals.

The existing new/load `ClearCaches` hooks sample the optional save-ID export on the
main thread and atomically replace a mutex-guarded identity snapshot, clear both bio
caches and advance their generation. Workers use only that snapshot (initially empty);
in-flight lookups cannot publish positive or negative entries after a clear.
File edits or newly generated bios are not promised visible until cache invalidation.
This is a raw block reader, not a profile renderer: it does not evaluate Inja,
decorators or submodules. Filesystem reads do not provide SkyrimNet's immutable
in-memory snapshot or reproduce its package compatibility gate.

Offline check, from Native in a VS2022 amd64 developer shell:

```powershell
New-Item -ItemType Directory -Path SKSE/build-bio-check -Force | Out-Null
cl /nologo /std:c++20 /EHsc /W4 /WX /I SKSE/src SKSE/tests/BioContentCheck.cpp /Fo:SKSE/build-bio-check/ /Fe:SKSE/build-bio-check/BioContentCheck.exe
if ($LASTEXITCODE -ne 0) { throw "Bio check compilation failed" }
& ./SKSE/build-bio-check/BioContentCheck.exe
if ($LASTEXITCODE -ne 0) { throw "Bio check failed" }
```

The check creates/removes a temporary tree and exercises both ordered passes,
base-last behavior, current-save selection, legacy exact/fuzzy fallback and literal
block extraction. Offline output is not a `Bio loaded` runtime observation. Base bios
were verified on SE/AE and VR; overlay precedence was verified on SE/AE only.
Dynamic save-layer bios remain offline-only. File edits or newly generated bios are
not promised visible until cache invalidation.
Cache invalidation across save loads remains to be qualified.

### Political Engine bridge — change intake

Optional read-only `PoliticalLetters.dll` detection requires API v3 and the snapshot export.
Missing or incompatible PE disables the bridge for the session. The bounded reader retains
four attempts, the 64 MiB limit, NUL validation and nonthrowing JSON parsing.

`PL_StateChanged` only marks dirty state. The political-context worker polls comparable public
district owners, war phases and present rulers. Initial attachment, loads and inactive reads
establish a fresh baseline without news. At most four comparable records are returned per revision;
district changes in one read are combined. Private puppet state, draft proposals and military
detail are excluded. The temporary snapshot files/event-log writer has been removed.
The worker records factual `pe_territory`, `pe_campaign` and `pe_ruler` rumors with zero
relation delta. Empty faction IDs are allowed only for `pe_*`; invalid nonempty IDs and
same-faction pairs still reject. Public PE news is visible to unaffiliated NPCs through 0810.
Optional `PE_GetIntelInitiatives080JSON` supplies public visits, gifts and disputes.
IE baselines the bounded journal on attach/load and deduplicates string IDs; PE must
not also call `RecordPoliticalEvent` for these initiatives. Missing export disables only this intake.
Active PE adds authoritative territory and recent public developments to the Political DM
context. A development is eligible for one `political_reaction` on the next tick through
`reacts_to`; expiry, load identity and duplicate responses reject stale reactions.
`politics.pe_integration` defaults true; when false IE ignores Political Engine (no polling, no context, no `pe_*` events) and re-enabling resets the baseline.
`politics.pe_reactions_move_relations` defaults true. Its persisted Papyrus/MCM/dashboard
toggle controls only tagged reaction relation and player-standing deltas, not IE's own
politics, standing decay or war/battle mechanics. Disabled still records the reaction.
Dashboard settings also report optional-provider detection. All of this remains offline-verified.
Optional `PE_GetPoliticalSides080JSON` joins current district owner IDs to realm sides;
both ownership and sides-only changes refresh context. A present but unreadable export
never invokes vanilla fallback. Only an absent export permits main-thread `CWOwner`
keyword-value reads, exposed separately as vanilla Civil War context, never district sides.
Civil War organizations match existing `CWImperialFaction`/`CWSonsFaction` IDs.
The active-only prompt forbids organization battles from inventing territory transfers.
PE territory/development context is Political-DM-only. NPC 0810 retains organization
events/relations and public PE news, without duplicating PE bio ranks, offices or reputation.
The worker polls/builds context; the existing game-thread callback commits news, then
dispatches the DM, only for the captured load generation. New news is eligible on the following tick.

Run `PoliticalEngineReadJSONCheck` and
`python SKSE/tests/RunPoliticalEngineBridgeCheck.py <vcpkg-triplet-dir> <private-sample-directory>`
from a VS2022 developer shell. These are offline checks, not provider/runtime verification.
`python SKSE/tests/RunPoliticalEngineTickCheck.py <vcpkg-triplet-dir>` exercises that thread/load boundary.

### Source-level checks

From Native in a VS2022 amd64 developer shell, create the detached check directory and run:

```powershell
New-Item -ItemType Directory -Path SKSE/build-cache-check -Force | Out-Null
cl /nologo /std:c++20 /EHsc /UNDEBUG /I SKSE/src SKSE/tests/RenderedCacheCodecCheck.cpp /Fo:SKSE/build-cache-check/ /Fe:SKSE/build-cache-check/RenderedCacheCodecCheck.exe
if ($LASTEXITCODE -ne 0) { throw "Codec check compilation failed" }
& ./SKSE/build-cache-check/RenderedCacheCodecCheck.exe
if ($LASTEXITCODE -ne 0) { throw "Codec check failed" }
```

The permanent stdlib-only check uses the real production helper, remains active with `DNDEBUG`, and verifies byte mappings, legacy space/empty transport and full scalar token grammar with unrelated names. Complete consumption means every written record parses with no leftover tokens: the pinned serializer declares its map size then skips empty maps, so record declared/written counts and their gap separately, not as codec failure. Partial records, extra tokens and expected-field mismatches fail; installed unresolved-form discards are a separate observation.

Every decoder-template edit additionally requires a temporary smoke of the actual files through revision-identified SkyrimNet/Inja and verified JSON headers. Only fixture-backed actor/getter/time inputs may be stubbed; never `replace`, literal parsing or output. Do not add Inja to Native dependencies. The DLL retains C++23/MinLL/ABI/release controls; this C++20 source check is not a plugin build or installed-game test.

### Papyrus API declarations and array guards

This cleanup removes unused safety-net and pending Director-parameter Papyrus natives,
their registrations and their exclusive C++ state. Source scans of both Native and Game
repositories found no script, prompt, YAML or JavaScript callers; external or dynamic
callers are not covered.


Core `Maintenance` uses `If !SlotStates`; Schedule `RestartMonitoring` uses `If !ScheduledAgents` twice. Initialization, Core's separate length validation, restored arrays, co-save/legacy recovery, recount and monitoring remain unchanged. The encoder declaration, four complete writes and three mirrored readers are preserved.

### Verification status

Verified on Skyrim 1.6.1170 and 1.7.104 with the coherent repaired DLL, PEX and prompt set, starting from a fresh new game:

- Facts, giver/receiver gossip and completed task history are written encoded and render decoded in actual prompts.
- A saved checkpoint keeps all rendered caches, stored RNE names and on-screen names identical across a warm reload (return to Main Menu in the same process) and an independent cold-process reload.
- Saved co-save streams parse completely with no raw delimiter bytes in rendered caches.
- Repaired scripts compile and disassemble cleanly; maintenance, recovery and populated-schedule retention were exercised across save/reload.

On 1.7.104, generated on-screen names can take a moment to reappear after a load; the stored names are unaffected. Detailed run evidence is kept in the maintainer's private evidence log.

### Known limitations

- **No blanket existing-save support.** Only the qualified offline conversion above extends the fresh-new-game baseline; already-lost names/history and unsaved state cannot be recovered.
- Exact binary-to-source provenance for the installed PapyrusUtil is unavailable; acceptance rests on observed behavior of the installed DLL.
- Other Intel narration/message/reason scalars (including rescue narration), names/destinations and string-list control handling remain outside this repair. This is not general Intel/PapyrusUtil storage safety.

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
.\verify.ps1 -DataDir "<IntelEngine-GamePlugin checkout>" -SkipDeployTargets
.\verify.ps1 -TestDest "<MO2 instance>\mods\<IntelEngine mod>"
```

The root `build.ps1` reads optional machine-specific defaults from gitignored `build.local.psd1`, a PowerShell data-file hashtable with `DataDir`, `ToolkitRoot`, `TestDest`, `VanillaDest` and `CKDest` keys. Explicit parameters override local defaults. Without local defaults, supply `-DataDir`, `-ToolkitRoot` when compiling, and all three deployment targets unless using `-SkipDeploy`. The verifier does not read this file; its defaults do not configure or authorize staging.

## Verification Evidence

Evidence must be described at the state actually observed; a source declaration or successful compile does not show installation, deployment, or runtime behavior.

### Rendered-cache source checkpoint (2026-10-12)

Source and template verification evidence is kept in the maintainer's private evidence log.

### Historical detached build attempt — prerequisite stop (2026-10-12)

Historical detached-build verification evidence is kept in the maintainer's private evidence log.

### Historical local rendered-cache packaging checkpoint — before deployment (2026-10-12)

Historical local-packaging verification evidence is kept in the maintainer's private evidence log.

### Historical RC1/RC2 checks (2026-10-05)

Historical ABI, package and partial runtime verification evidence is kept in the maintainer's private evidence log; the original RC1 candidate is rejected.

### VS 2022 flags-off full build and runtime checkpoint (2026-10-09)

Historical build, package and scoped runtime verification evidence is kept in the maintainer's private evidence log.

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
