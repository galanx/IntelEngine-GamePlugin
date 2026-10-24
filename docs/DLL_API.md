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
- The 3.6.0 shared build includes Skyrim SE, AE and VR with Address Library compatibility. The documented SE/AE targets are **1.5.97.0, 1.6.640.0, 1.6.1170.0, 1.7.99.0, and 1.7.104.0**; Skyrim VR **1.4.15 / SKSEVR 2.0.12** should work and was partly tested. Tested runtimes: **1.6.1170.0 and 1.7.104.0**. Skyrim SE **1.5.x**: untested. Other listed targets are untested. Skyrim 1.5.97 / SKSE64 2.0.20 saves should convert, untested; your original save is never changed. Partial testing does not establish full VR qualification or every gameplay scenario.
- Offline synthetic-vtable checks and linked dispatch/import inspection passed. Packaged startup and fresh/converted-save smoke passed on 1.6.1170 and 1.7.104; VR coverage remains partial.
- Offline getter regression: build and run `ReferenceGetterDispatchCheck` from your configured build directory. It invokes the production CommonLib getter on synthetic SE, AE and VR vtables, checks the returned cell and unchanged parent/setter count, and exits nonzero on failure. `--wrong-slot` deliberately moves the fixture getter onto the adjacent setter slot and must exit 1.

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

## Rendered Cache Persistence

```papyrus
String Function EncodeRenderedCache(String text) Global Native
```

The Native-owned encoder preserves plain Markdown renderer APIs and the scalar-cache workaround for immediate same-session visibility. Core calls it exactly once immediately before the four complete writes: task history, shared `InjectFact`, receiver gossip and giver gossip. Join each participant's heard+told sections first. Existing list storage/rendering and render-mode gates are unchanged.

One bytewise pass maps `%` → `%25`, BEL → `%07`, TAB → `%09`, LF → `%0A`, VT → `%0B`, FF → `%0C`, CR → `%0D`, ESC → `%1B`. Empty input stays empty; spaces, UTF-8, quotes and backslashes are unchanged. Embedded NUL/binary text is unsupported. The three cached readers reverse the seven control tokens, then `%25` **LAST**, once, before checking emptiness/output. This is neither URI decoding nor an idempotent encoder.

**BREAKING / coherent providers required:** start a fresh new game with the repaired DLL, freshly compiled `IntelEngine.pex`/`IntelEngine_Core.pex` and all three repaired prompts already winning, or use only an eligible offline-converted copy as described below. Unconverted existing saves, including apparently cache-free saves, remain unsupported: old values can poison restoration before scripts run or ambiguously decode literal percent text. There is no raw fallback or general post-load safety guarantee.

Native owns C++/PSC/templates; Game is the Data-layout mirror. Keep both PSC files and all three prompt pairs byte-identical, and mirror this API document explicitly (root staging does not copy docs). Source equality does not prove DLL/PEX freshness, packaged equality does not identify installed winners, and neither proves runtime behavior. Stop on new PEX/old DLL missing binding, old Core PEX/new DLL raw writes, old templates/new encoded caches, or ambiguous providers; do not assume an unbound call's result.

Rollback requires the complete old DLL/PEX/template set and its separately preserved pre-cutover save lineage. Do not load repaired saves under old components or rewrite evidence saves.

### 3.6.0 NPC Social DM scheduling repair (#15)

`BeginAsyncNPCDMTick` queues Phase A through SKSE tasks; Papyrus invocation is not a main-thread guarantee. Quest editor-ID inspection, actor/player/cell/race/faction reads, cooldown/calendar reads, inn detection and the empty callback run in that task. Only owned strings/scalars/IDs cross to Phase B. Phase C publishes the result's candidate pool and dispatches the callback on the main thread after validating `SlotTracker::loadGeneration`; revert invalidates queued snapshots/results and clears the social pool. The worker no longer publishes that pool.

Phase B still calls SkyrimNet's FormID/value APIs and reads bio files; this change does not establish the external provider's internal thread safety. No faction-name null/vtable workaround, Papyrus signature, serialization change, synchronous-API scheduling repair, Story/Political tick change or request-isolation contract is included. A discarded old-save tick intentionally does not call into the newly loaded save. Existing pending recovery remains in use (watchdog timeout: one game hour); task-interface failure still logs and drops the tick.

Offline check: compile `SKSE/tests/NPCTickGenerationCheck.cpp` in a VS2022 amd64 developer shell with `/std:c++20 /EHsc /W4 /WX /I SKSE/src`, then run the executable. It exercises production result publication: current/empty pools, duplicate names, revert clearing and stale results after subsequent loads. It does not exercise SKSE task dispatch or prove engine thread safety.

SE/AE soaks passed. Instrumented thread identity and stale-result drop on reload remain unverified; 1.5.97 remains untested. To verify on 1.6.1170, use a symbolized build with independently verified loaded DLL identity; enable debug logging and compare debugger thread IDs at `[NPCTick] Phase A snapshot`, the existing `async context` worker log, and `Phase C callback`. Phase A/C and the empty callback must match the engine main thread, not the Papyrus VM job thread; Phase B must differ. Exercise nonempty/empty ticks, named/unnamed factions, non-ASCII names, cell transitions, and loads with Phase A queued, Phase B blocked and Phase C queued. Expect generation-change drop logs and no old pool/callback; verify pending recovery and fresh ticks. On 1.5.97, the reporter should repeat Aela/Jenassa/Torvar contexts with NPC interactions enabled, retain DLL/PDB identity and collect logs/minidumps if faction-name dispatch still faults. A finite crash-free run is not proof of the exact CTD's cause or cure.

### 3.6.0 Story DM type filtering (#3)

The async Story DM path parses exclusions once and shares that set between prompt visibility flags and the session-count formatter. Excluded types are omitted from "Story Type Picks This Session"; NPC Social DM counts are unchanged. This does not remove type names from dispatch history or general guidance, and response validation remains the dispatch gate.

Offline check (requires `clang++`): `python SKSE/tests/RunStoryTypeCountFilterCheck.py`. It compiles the production formatter without the game ABI and checks allowed/excluded counts, empty/all exclusions, exact top-level matching and unchanged NPC counts. No in-game qualification is implied.


### Player fix mode: How to convert an old save

The standalone Windows tool includes a one-save `fix` command for eligible SE/AE saves from IntelEngine 3.5.2 or earlier and VR 1.4.15 saves from VR-capable IntelEngine 3.5.1 or earlier. One real 3.5.2 save per qualified SE/AE runtime and one real 3.5.1 VR fixture passed bounded acceptance; older versions are format-gated, not separately tested. Fix does not read the IntelEngine version. Run it from anywhere: no installed PapyrusUtil hash, VFS or game-root placement is required. Qualification uses SKSE co-save format 1, PapyrusUtil owner `0x424510A2`, complete unique framing and, when present, exactly one STRV v1 block. Exact SKSE/runtime pairs: **0x02000140 / 1.5.97.0** (SKSE64 2.0.20; runtime DWORD `0x01050610`, untested), **0x02020060 / 1.6.1170.0**, **0x02030010 / 1.7.104.0**, or **0x020000C0 / VR 1.4.15** (runtime DWORD `0x010400F1`, SKSEVR 2.0.12). VR also requires a bounded `TESV_SAVEGAME` ESS version-12 header. Other formats/header pairs refuse. Expert 1.5.97 and VR `convert` remain refused: no historical PapyrusUtil provider hash is qualified for either. `inspect` recognizes the VR tuple but never grants conversion eligibility.

Skyrim 1.5.97 / SKSE64 2.0.20 saves should convert, untested; your original save is never changed.

Source derivation: [SKSE64 v2.0.20](https://github.com/ianpatt/skse64/blob/0d6c91dc84f1d384da113bec9e298867a5c86ce1/skse64_common/skse_version.h) defines `MAKE_EXE_VERSION_EX`/`PACKED_SKSE_VERSION` and `RUNTIME_VERSION_1_5_97`, yielding SKSE `0x02000140` and runtime `0x01050610`; `Serialization.cpp` writes those version words.

**Convert before loading an old save with 3.6.0.** An unconverted VR copy restored and progressed its Travel task, but three of four original populated facts caches read back empty, the fourth only as a header, and both original rendered histories read back empty despite some raw history remaining. An earlier process crashed with cause unproven; the evidence does not establish that it read the unconverted pair. Task recovery does not establish safe unconverted loading.

Only the three rendered-cache keys are rewritten. Non-cache values, including BEL-bearing names and task destinations, pass through without decoding, normalization or re-encoding. Cache expansion adjusts enclosing STRV/plugin lengths; reverse-patch verification proves every other byte unchanged.

When STRV is absent, player `fix` permits a verified byte-identical cache-free pair only if the PapyrusUtil owner exists and its other record types/versions are recognized: MODS/PLGN v0 or INTV/FLOV/FORV/INTL/FLOL/STRL/FORL/PKGO v1. It verifies outer framing/counts/EOF and runtime/ESS gates, not opaque-record semantics, and uses the same exclusive backup/staging/publication path. Unknown records/versions, missing owner, malformed STRV or a present STRV without eligible cache targets refuse. This is a copy, not a repair; expert mode retains its STRV/provenance requirement.

Offline production byte comparisons passed after safety corrections on two preserved save pairs: one produced 29 caches / 44 name spans, the other 13 caches / 28 name spans. Both ESS outputs were unchanged and preserved-source hashes matched. The unmodified shipped batch and production CLI succeeded with Skyrim closed on ASCII and Unicode/space scratch paths; the actual CLI also correctly refused while Skyrim was running. Migration/codec checks and refusal/partial-publication regressions passed. Offline byte reproduction is distinct from the bounded historical converted-copy runtime acceptance below; detailed evidence is maintained privately.

1. Close Skyrim. Keep the same-directory, same-stem `.ess` and `.skse` pair together. Make sure you have a backup of IntelEngine and SkyrimNet external data as well if you may need timeline rollback.
2. Put `LegacyCacheMigration.exe` beside `Convert-IE-Save.bat`, or run it directly from any working directory. Drag exactly one `.ess` onto the adjacent batch file, or run:

   ```powershell
   & ".\IntelEngineTools\LegacyCacheMigration.exe" fix --save ".\My Save.ess"
   ```

3. Success creates `<stem>_IEbackup/` containing the original `.ess` and `.skse`, plus sibling `<stem>_IEconverted.ess` and `<stem>_IEconverted.skse`. The tool does not overwrite existing backup/output files. It leaves the original pair unchanged.
4. Exit **0** means both verified converted files were published; **2** means usage, eligibility or safety refusal; **3** means I/O, verification or publication failure. If publishing the second file fails, the first converted file may remain. This is an incomplete pair: do not load it, and retain the backup and all remaining files for diagnosis.
5. Install the complete repaired providers (DLL, both affected PEX files and all three prompts) before using the converted pair. Never load a converted save with 3.5.2 or earlier. Do not convert again, mix original and converted companions, or assume already-lost names/history can be recovered.

If the converter says the save path is not allowed (Reparse path rejected), your save folder is a link or junction (for example My Games moved to another drive, or OneDrive): copy the .ess and .skse pair to a normal folder such as Desktop\IE-convert and drag the .ess from there.

Rollback means restoring the preserved original pair with its matching old providers and the corresponding IntelEngine/SkyrimNet external-data snapshot. The pair backup does not include external databases or their `-wal`/`-shm` files. Do not mix saves/providers or claim general legacy-save safety.

The historical writer's identity/provenance cannot be proved from the file. Treating serialized BEL as a space is owner policy, not recovered original text. The required real-template smoke rendered all three full fixed prompts through Inja commit `affabd9fb6e679b2535382063e11ac9cc5ff860c`. Legacy literal `%07%09%0A%0B%0C%0D%1B%25%250A%0a%41%07` produced payload bytes `07090A0B0C0D1B2525304125306125343107`: the upper-case control tokens became their control bytes, `%25` became `%`, `%250A` became literal `%0A` without recursion, and lowercase `%0a` / unknown `%41` remained literal. Encoding that same literal input with the production codec preserved it through all three templates. This measured decoder behavior does not establish that native restoration of legacy percent text is safe.

### Offline legacy-save conversion

The standalone Windows converter supports eligible saves from IntelEngine 3.5.2 or earlier on Skyrim **1.6.1170.0** and **1.7.104.0**, not arbitrary existing saves. Tested on 3.5.2 saves; saves from older versions convert if their format matches and are refused otherwise. One real 1.6.1170 legacy save passed converted-copy acceptance: 28/28 sampled surviving cache values matched exact UTF-8, plus one explicitly policy-derived facts field; a separate checkpoint retained these and two naturally generated fresh caches (31 fields) through warm and independent cold reloads. Named production facts/gossip templates passed for two sampled actors. All 42 resolvable original names matched; two temporary-actor name spans were preserved byte-for-byte but **not live-verified**. This is not full-HUD or general form-resolution qualification.

The 1.7.104 qualification covers **one bounded converted-copy acceptance**: a uniquely framed co-save, 11/11 independently sampled caches and two explicitly owner-policy fields retained exactly through a new checkpoint, warm reload and independent cold reload. All 24 qualified live names matched; four other holders remain unverified and were omitted from the new checkpoint, while all 28 original/converted name spans were preserved. Natural UTF-8 survived storage/reloads and actual facts/gossip/task-history prompt checks; the API's blank-line normalization is reported separately from stored-byte equality. Its runtime, SKSE header and provider hash remain a separate exact tuple; mismatches still refuse. An initial attempt crashed with causation unresolved; the authorized recovery passed these migration checks, not a general stability or unrelated-feature qualification. This does not qualify arbitrary saves, unreadable holders, fresh-cache generation in that checkpoint, or every 1.7 configuration.

VR `fix` reuses the shared repair path for eligible VR-capable IE 3.5.1-or-earlier saves; IE 3.5.2 disabled VR. One real 3.5.1 VR fixture passed repair of six facts/task-history caches with all non-cache bytes preserved, task recovery/progression, a roughly 39-minute sampled soak and one cold reload. All 66 cold cache comparisons matched; 76/77 state fields matched, with a small scalar deadline difference and unexplained SkyrimNet timeline differences. Three actor mappings were absent before and after, not demonstrated cold-reload loss. The fixture had no gossip caches or stored names, so populated gossip/name migration is synthetic-only on VR. The original SkyrimNet database baseline, historical database restoration and native name index were not established. This does not close full VR/core-action, package/MCM, real-headset or general old-save qualification.

#### Eligibility and refusal policy

- Require complete supported SKSE/STRV framing, exact counts and EOF, canonical lowercase keys, pinned provider/runtime/codec provenance and evidence covering **every** target: `intel_factsrendered`, `intel_gossiprendered`, `intel_taskhistoryrendered`. Inspection alone never grants eligibility.
- `actor-in-place` requires explicit `legacy_writer: "IE-3.5.2"`, `actor_bel_policy: "space"` and `preserve_rne_name_bel: true` in both the evidence and qualification basis. It preserves serialized identities without resolving/remapping forms. Only qualified actor identities are eligible; temporary cache targets refuse. Temporary holders containing only supported unchanged names may be preserved, not declared runtime-qualified.
- In the actor cache policy, serialized BEL means space and LF is allowed within a complete cache value. Genuine original cache BEL, ESC, other C0 controls and DEL refuse. Non-cache values, including `rne_name` and task destinations, preserve BEL bytes without interpreting them; raw delimiters/ESC and existing malformed/UTF-8/control checks still refuse. `legacy` cache fields require independent original-byte evidence; `legacy-policy` cache fields additionally declare `original_basis: "owner-policy"`.
- Global mode remains stricter: every identity must be global, legacy BEL/ESC collisions refuse, and every target needs independent original-byte evidence. Neither mode guesses unknown sentinel meanings. Already-encoded fields require a pinned writer codec and exact expected original bytes; literal percent text or a filename does not prove encoding.
- Refuse the whole candidate on truncation, ambiguous framing, declared/written count gaps (including skipped empty maps), unsupported owner/version/identity/key, duplicate or noncanonical keys, missing/duplicate/extraneous field evidence, mismatched spans/hashes, unknown representation or unpinned encoded generation. No partial salvage or force switch.
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

Native owns the three repaired PSC files; Game's source mirrors are byte-identical. `IntelEngine.psc` now declares the existing registered implementations with these signatures; no native implementation, consumer dispatch or compatibility alias was added:

```papyrus
String Function ClaimPendingDirectorParams() Global Native
String Function BuildSafetyNetContextJson(Actor akActor, Int keywordHint) Global Native
Int Function HasScheduleKeywords(Actor akActor) Global Native
Actor Function GetLastConversationPartner() Global Native
Actor Function GetSafetyNetNPC() Global Native
Function NotifyNewDialogue() Global Native
Int Function RunSafetyNetCheck() Global Native
```

Schedule hints are `0=none`, `1=meeting`, `2=fetch`, `3=delivery`. `GetSafetyNetNPC` returns the last stored positive-check NPC if still resolvable; a negative check does not clear it. `NotifyNewDialogue` resets unchanged-dialogue backoff, not the cooldown timestamp. Context JSON is escaped and empty for unavailable actor/dialogue. Director claim atomically consumes pending parameters as JSON, returning empty when already claimed. Literal source consumers were not found in either repository; external/dynamic callers remain unexcluded.

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
