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

## Rendered Cache Persistence

```papyrus
String Function EncodeRenderedCache(String text) Global Native
```

The Native-owned encoder preserves plain Markdown renderer APIs and the scalar-cache workaround for immediate same-session visibility. Core calls it exactly once immediately before the four complete writes: task history, shared `InjectFact`, receiver gossip and giver gossip. Join each participant's heard+told sections first. Existing list storage/rendering and render-mode gates are unchanged.

One bytewise pass maps `%` → `%25`, BEL → `%07`, TAB → `%09`, LF → `%0A`, VT → `%0B`, FF → `%0C`, CR → `%0D`, ESC → `%1B`. Empty input stays empty; spaces, UTF-8, quotes and backslashes are unchanged. Embedded NUL/binary text is unsupported. The three cached readers reverse the seven control tokens, then `%25` **LAST**, once, before checking emptiness/output. This is neither URI decoding nor an idempotent encoder.

**BREAKING / fresh-new-game-only:** retain the existing keys but start a new game with the repaired DLL, both freshly compiled `IntelEngine.pex`/`IntelEngine_Core.pex` and all three repaired prompts already winning. Existing saves, including apparently cache-free saves, are unsupported: old values can poison restoration before scripts run or ambiguously decode literal percent text. No migration, raw fallback, original-name recovery or post-load safety guarantee is implemented.

Native owns C++/PSC/templates; Game is the Data-layout mirror. Keep both PSC files and all three prompt pairs byte-identical, and mirror this API document explicitly (root staging does not copy docs). Source equality does not prove DLL/PEX freshness, packaged equality does not identify installed winners, and neither proves runtime behavior. Stop on new PEX/old DLL missing binding, old Core PEX/new DLL raw writes, old templates/new encoded caches, or ambiguous providers; do not assume an unbound call's result.

Rollback requires the complete old DLL/PEX/template set and its separately preserved pre-cutover save lineage. Do not load repaired saves under old components or rewrite evidence saves.

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

### Private ADT runtime and offline checkpoint — 2026-10-13

The earlier LoopB/LoopC offline checkpoint is superseded by the named fresh-lineage checkpoints below on ADT / Skyrim 1.6.1170. Each companion inspection consumed all 12 SKSE v1 plugin blocks and the complete PapyrusUtil STRV v1 payload. Whole-span TAB/LF/VT/FF/CR scanning ran before key extraction and found zero hits; scalar grammar consumed every token with no trailing fields or empty-map count gap.

| Saved field coverage | A: `rc-01-populated` | B: `rc-02-postload` | C: `rc-03-session-end` | D: `rc-04-reload-verified` |
|---|---:|---:|---:|---:|
| Declared / parsed STRV objects | 56 / 56 | 64 / 64 | 68 / 68 | 68 / 68 |
| Stored RNE names | 42 | 43 | 43 | 43 |
| Encoded facts caches | 14 | 22 | 23 | 23 |
| Encoded gossip caches | 14 | 14 | 18 | 18 |
| Encoded task-history caches | 5 | 10 | 10 | 11 |
| Total rendered caches | 33 | 46 | 51 | 52 |

A's warm and independent cold loads restored all 33 encoded caches and all 42 stored names byte-for-byte on the same references. B's independent-process reload restored all 46 caches and all 43 stored names exactly. Sampled actual named facts, task-history and joined gossip prompts matched saved decoded expectations after standard SkyrimNet cleanup, including literal `75%` in B facts. B preserved all 42 A names and added one. These checks establish stored-name continuity, not independent verification of every displayed name.

After B reload, runtime writer logs establish fresh receiver/giver gossip and a two-hop sharing chain. Six new or updated gossip cache blocks are serialized in C, adding four cache owners. All 43 B names remain byte-identical, every B cache key remains present, the B-marked fact cache is unchanged, and all 51 C caches pass exact decode/re-encode checks. Actual StoryDM Recent Gossip input consumed both new topics; that input is **not** proof of the repaired full scalar character-bio gossip reader.

C's independently observed cold-process reload on 2026-10-13 restored all 51 caches and all 43 stored names exactly. All six actual named `submodules/character_bio/0200_intel_gossip` prompts for the fresh receiver/giver/joined caches matched decoded C expectations after standard blank-line cleanup, separately establishing the scalar reader path. The agent then saved the unique `rc-04-reload-verified` pair, observed Save finished, submitted `qqq` once and independently verified process absence; foreground input ended after 293.77 seconds. Logs were exported only after shutdown; exporter validation and independent ZIP CRC/product size/hash checks passed.

D's subsequent offline companion inspection consumed all 12 plugin frames and all 331 STRV tokens / 68 declared-written objects, with zero raw TAB/LF/VT/FF/CR and no empty-map gap. All 43 C names and all 18 gossip caches remain exact; every C cache key remains. Of C's 51 cache values, 50 are unchanged and Ulfgar's task history is updated; D also adds Grisvar's history cache. Matching current Papyrus completion logs account for both history changes. All 52 caches pass decode/re-encode equality. Original save/archive hashes remain unchanged; compressed ESS state and other plugin payloads were not semantically decoded. **D has not been reloaded.**

All six installed private-override files matched the test package at the B and C identity rechecks; base ESP/config/dashboard assets remain supplied by the enabled full base. The loaded IntelEngine module backing path and hash matched the repaired DLL. Source-qualified facts writes, actual Papyrus injection logs, encoded storage and decoded prompts support the exercised facts-write native binding; no standalone global native-call probe was performed. Installed PapyrusUtil source-revision correspondence and broader provider/binding acceptance remain separate gates.

The pre-reload C-session export passed complete indexed-snapshot validation and its audit found native-binding failures, maintenance/arrival None errors and gossip grounding/recipient consistency leads. The later C-reload export also now passes complete indexed validation and scout-assisted review: all eight current model pairs match, including one blank-channel Ulfgar dialogue. Current findings include seven IntelEngine and one SkyrimNetApi binding failures, separate four NiOverride binding failures, maintenance None-array casts, a rejected Ria conversation target and repeated Ulfgar dialogue already seeded in input history. Ulfgar travel reached dispatch and the Papyrus call, but movement/arrival and heard audio are unverified; explicit telepathy eavesdrop explains sampled thought voicing. These findings are not attributed to the codec, and their causes/repairs remain outside this change. Save/export validation does not establish overall gameplay health.

Source-qualified generation uses Director Story Dispatch / Informant for facts. Director NPC Social / Gossip writes facts, **not** the receiver/giver gossip caches; those require an eligible autonomous NPC Social gossip event. Completed history requires a non-cancelled task result before slot clearing; FetchPerson has a source-traced success route. Actual prompt verification must enter the scalar branches: task history is scalar only in outer `full` mode (`static` uses lists); inner mode expressions do not widen the outer gate. Do not prescribe guessed console calls or treat incidental logs as decoded-output proof.

Current acceptance: **26/30 items complete**. Procedural authorization, clean-A whole-stream inspection, fresh post-load B/C save/reload and layered evidence recording pass (8.1, 8.3, 8.6, 8.7); offline winner qualification plus the already exercised loaded DLL/native path also closes 7.3. Six repaired files retain their preserved winner hashes. Beta26 DLL/PDB GUID-age matching and 23 compiled-source checksum matches qualify six bridge/decorator/prompt sources and seventeen Inja headers against the identified beta26-rc4 release, not whole-DLL rebuild equivalence. PapyrusUtil installed-reader/source provenance remains unresolved (7.1), along with same-reference displayed-name baseline/warm/cold comparisons (8.2, 8.4, 8.5). Immediate pre-C-save prompts remain historically unobserved but are not an additional 8.6 requirement; D need not be reloaded to repeat the completed B/C criterion. Other scalar/list writers and legacy BEL/ESC fidelity remain outside the repair; existing-save migration stays **BLOCKED**. Detailed current qualification, saved handoff and private receipts are linked from Native's local `openspec/changes/safe-rendered-cache-persistence/tasks.md`; fixtures and raw logs are excluded from repository commits.

Historical unchanged-A template-name snapshot (private ADT, PID 62384; superseded as current status by the 2026-10-14 diagnostic below): 42/42 stored-name samples match A and all 42 `get_name(formid_to_uuid(ref))` strings resolve. Only 37 contain the saved personal name with role suffix; Heidmir (`00037057`), AsOrd (`0003706A`) and Tolfdir (`00037070`) read `Whiterun Guard`, Wilvor (`12009E9A`) `Labourer`, and Merta (`12009EAA`) `Noble`. These are potentially cached template-reader observations, not guaranteed fresh engine/HUD labels or a cold-load regression proof. The original full displayed baseline was unrecorded. Private `display-name-checks-20261013_214710/cold-display-result.json` retains strings and timestamps. Input/foreground released after 185.11 seconds; that phase left the game open without save/quit/extra reload/rename/repair. Subsequent closeout and diagnostics supersede its leave-open state and proposed next steps; acceptance remains 26/30, migration BLOCKED.

Five-reference read-only follow-up: both actor-decorator and HTTP actor-data form IDs match every intended reference. Heidmir now displays `Heidmir [Whiterun Guard]` with `is3DLoaded=false`; Merta displays `Merta [Noble]` with `is3DLoaded=true`. AsOrd/Tolfdir remain `Whiterun Guard` in the Guardhouse, Wilvor remains `Labourer` at an unknown location, all three `is3DLoaded=false`; every sampled actor is alive/nonvirtual. No agent rename/reload/movement occurred. This contradicts wrong-reference selection and the claim that all unloaded actors necessarily lose their personal label, but does not establish the RNE application/override mechanism or cold-load regression. Disabled state and original pre-A displays remain unobserved. Targeted live reads ended by 260.03 seconds, with no focus/input; private `five-reference-diagnosis-result.json` records raw-receipt links. No full-sweep/other-actor retest. Next separately authorized check remains read-only RNE settings/exclusion/quest-alias inspection; activation requires new gameplay authority. Acceptance/migration gates unchanged.

Owner-requested closeout supersedes the prior leave-open state: matching installed SkyLink native/server artifacts connected through stdio MCP; one exact `qqq` returned `executed:true`/`Bye.`, followed by independent zero-process verification. No new save or foreground input. Only then did the existing ADT retention wrapper produce `SkyrimNetOutput_ADT_2026-10-14_03-36-21-045_08b4100b.zip` in `D:/Modlists/ADT/_log-dumps` (7,249,798 bytes; SHA-256 `71927877dd436c0f19eca84d6d629cef4c941cfa55c1f07a7a305c1b34af59c8`). All ZIP CRCs and nine manifest product sizes/hashes match; four raw logs retained, fullHistory merged view. This is local retention/integrity, not a full archive audit, release or acceptance closure. Private `skylink-shutdown.json` and `final-export-result.json` preserve control/effect evidence. Skyrim is closed; no additional RNE-settings/activation work assigned. Gates remain unchanged.

### Latest naming diagnostic and indexed audit — 2026-10-14

These observations supersede the earlier leave-open state and proposed diagnostic next steps above. Settings, typed FormList bindings, actor-base and RNE player-alias reads are retained in Native's owning journal; they do not establish every exclusion/override owner or live list membership.

**Runtime:** one qualified SkyLink `load rc-01-populated` from Main Menu loaded the unchanged exact A world, without agent foreground activation, AHK or keyboard input. Exact save-family copies and 117 SQLite online backups (`quick_check=ok`) preceded rewind; five installed artifact hashes remained unchanged. Two authorized actor teleports loaded AsOrd (`0003706A`) and Tolfdir (`00037070`) in Guard Barracks, then Wilvor (`12009E9A`) in Drunken Huntsman Cellar. Immediate template names remained generic while HTTP names were already personal. After 75.000 observed seconds, both readers agreed **3/3**: `AsOrd [Whiterun Guard]`, `Wilvor [Labourer]`, `Tolfdir [Whiterun Guard]`; exact reference identities, loaded 3D and delayed stored-name samples match. No rename, cache clear or new save. Target HUD labels and ordinary walking/door-entry remain unobserved.

**Source interpretation:** pinned beta26 `d0259b2f61483e81492771257b0fab88fd47796a` routes HTTP and executed `get_name` callbacks to `RE::Actor::GetDisplayFullName()`. Its callback wrapper caches `get_name`/`papyrus_util` results; executable default TTL is **55 seconds**, and cache hits do not extend expiry in pinned Inja `affabd9fb6e679b2535382063e11ac9cc5ff860c`. Delayed agreement strengthens callback-result reuse as the earlier discrepancy's explanation, not an instrumented cache-hit/expiry proof or a deployed repair. Inspected SkyLink source uses a separate base-name accessor for native detail names; whole candidate-source/binary equivalence remains unqualified.

**Closed-session evidence:** one `qqq` returned `Bye.`, independent process count reached zero at 214.30 seconds, then the existing exporter exited zero. ZIP `SkyrimNetOutput_ADT_2026-10-14_14-22-17-204_be1597f4.zip` is 1,885,041 bytes, SHA-256 `dbf7c4255d33bc2a30a1cc10196ebd57a1e4ec4b88e7406d5dd83cfbcfbab53c`, snapshot `be1597f4-2e51-47ce-8dfb-342ffcbd14ce`. Complete indexed contract validation passes. Current local-wall-time window is **09:17:01.182–09:21:55.016**: 5,173 records (4,633 main, 540 Papyrus), 28 main warnings, 36 indexed Papyrus error records, **zero current LLM requests/input/output**. OpenRouter records are historical, so no current generated-dialogue/coherence judgment is made. Non-atomic capture/offset/EOF limits remain; independent shutdown proof is separate.

**Audit findings, not codec attribution:** seven IntelEngine native registration attempts find no matching API PEX declarations (`Papyrus.0.log:199-205`), plus one SkyrimNetApi and four NiOverride binding reports. Four executed maintenance `None` array casts recur (`:214-217,300-304,350-352,354-357`). Ten RNE `Dispel` calls have unbound `[None]` receivers (`:436-541`); four SkyrimNet MCM variable-resolution diagnostics and six StalkingNPCs missing-script reports remain separate. One `dynamic_character_bio` render reports seven occurrences of the same missing `suppress_host_persona` variable (`SkyrimNet.log:3845-3852`); rendered-content impact is unproved. Initial OmniSight preload abort is followed by completed zero-entry cell preloads (`:4399-4401,4526-4528`), not proof of a permanent database failure. Generic-guard resolution warnings and their four UUID mapping deletions are conditional/expected noise, not failures of the three tested references. Event/memory newer-than-load-timestamp cleanup (`:3642-3647`) is expected rewind behavior; backup preservation does not assert zero database writes or zero deleted rows.

Private `rne-delayed-skylink-20261014_091832/delayed-name-result.json`, `offline-audit-result.json`, original-byte excerpt receipts and both qualified scout-result validations preserve the runtime/audit evidence. Subsequent `script-error-triage-result.json` and `script-triage-*.json` receipts record completed offline installed-script/native/maintenance/RNE triage, not a repair. **26/30 remains complete**: 7.1 PapyrusUtil correspondence and 8.2/8.4/8.5 original same-reference displayed baseline/warm/cold acceptance remain partial. No full-42 delayed sweep, HUD pass, baseline reconstruction or migration authorization follows from this three-reference diagnostic.

**Compiled/source triage checkpoint (2026-10-14):** exact installed API PEX SHA-256 `555892ac9a632c29a1d21f290e2892c93bf20a43e451bd5c21f1b0cbd1fdafc2` lacks `ClaimPendingDirectorParams`, `BuildSafetyNetContextJson`, `HasScheduleKeywords`, `GetLastConversationPartner`, `GetSafetyNetNPC`, `NotifyNewDialogue` and `RunSafetyNetCheck`; current native source registers them. This corrects the earlier declaration-with-missing-native interpretation. All seven names have zero literal occurrences across ten selected IntelEngine PEXs; external/dynamic consumers are not excluded, and no failed invocation is established.

At the pre-repair checkpoint, actual Core/Schedule bytecode cast literal `None` into typed array temporaries before equality checks against `SlotStates`/`ScheduledAgents`. This did not establish corrupted restored arrays. Co-save recovery (`Papyrus.0.log:292,353`) and schedule-monitoring restart (`:305,358`) followed the errors. The authorized source/compiled repair below supersedes the proposed/unapplied repair status, not those installed/runtime observations.

All seven selected RNE race-handler PEXs call `RealNamesExtended.LoadFromJson` before self-`Dispel` and contain no `OnEffectFinish`. The beta26-rc4 `RealNamesChange.pex` is the selected controller, not the original mod's copy. Full framing of the original defining ESP consumes 130 records; matching effects are NoDuration abilities, so zero EFIT duration alone does not prove instantaneous expiry. Active record overrides, target-associated native effect lifetime and name-write success for the failed instances remain unknown. Do not remove `Dispel`, extend duration or force names to suppress the error. No RNE change is justified or included; migration remains **BLOCKED**.

### Authorized offline script repairs — source and detached artifacts, 2026-10-14

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

**Executed:** original `PapyrusCompiler.exe` (SHA-256 `f441afa877ce0b315c6b613db7fe700a7bbc66b71a72fc4d0d8bc94577ceb0ce`), genuine flags/import roots recovered from the prior successful command, direct `-f/-i/-o` invocations from a new detached cwd. All three compiles exited zero with zero errors/warnings; existing `D:/git/SkyrimNet/external/papyrus-compiler/papyrus.exe read <PEX>` exited zero for each. Root `build.ps1` was not run: `-SkipDeploy -SkipGit` would still stage assets. No header sync, fabricated imports, production staging, installation or game activity.

Native output root: `SKSE/build-cache-persistence-20261012/script-repair-20261014_112533/pex/`.

| Detached artifact | Bytes | SHA-256 |
|---|---:|---|
| IntelEngine.pex | 18595 | `a3165edcda0c2921154e7d48b24a16c9632ebf841edc9b91cc5605da4211fc86` |
| IntelEngine_Core.pex | 91018 | `22128e4d2ee4ede8d499c94ebfee3a7961bfa12fcc8f8617b34e5de4556f0c4f` |
| IntelEngine_Schedule.pex | 24098 | `f9a8871d3ee276301f5d375de192a88a1382607f9f42a5f882fe32a4a0766059` |

Disassembly verifies all seven Global Native signatures plus unchanged `EncodeRenderedCache(String)`, one Core/two Schedule direct array `not` guards and **zero literal None-to-array casts in those methods**. Schedule's remaining None cast targets a scalar Actor for element comparison. All 288 existing API method records and 98 unaffected Core/32 unaffected Schedule instruction streams match the prior repository package after temporary-ID normalization; the four encoder-to-write dataflows match. These comparisons do not prove installed/runtime equivalence.

Owning journal records exact commands/imports. Private sibling receipts: `source-repair-start.json`, `compiler-plan.json`, `compile-results.json`, `disassembly-results.json`, `script-repair-verification.json` and `script-repair-documentation-checkpoint.json`. At this detached checkpoint, Game PEX/DLL payloads and Native canonical DLL were not replaced, and outputs were not yet packaged/installed/runtime-tested. The later three-PEX ZIP, owner installation and partial runtime check below supersede only that artifact/installed status; no RNE repair or full-42/HUD/warm-cold acceptance closure follows.

### Installed script-repair runtime check — partial, stopped 2026-10-14

Owner installed the three-PEX override over the rendered-cache override and v3.5.2 base, then started ADT at Main Menu and authorized background tests. Fresh PID **44792**, profile `iADT_IE-Rendered-Cache-fix`, actual Main Menu image and loaded IntelEngine/SkyrimNet/PapyrusUtil/SkyLink module identities verified. Current enabled loose winners for all three PEXs match the detached repair hashes above; all three decoder prompt winners match source. Before one qualified SkyLink `load rc-01-populated`, exact A ESS/SKSE hashes/copies and **117** read-only-source SQLite backups (`quick_check=ok`) were preserved. Independent Beta/level-1/expected-position read and actual world image confirm the fixture loaded; no agent focus/input, teleport or save.

Bounded captured logs show two `Maintenance(firstLoad=False)` executions, co-save recovery and schedule-monitoring restart with **0 pending tasks**, with **zero None-to-array cast diagnostics and zero diagnostics naming the seven repaired API bindings**. Native restored/synced one active Hisin slot; subsequent Story logs explicitly abandon `seek_player`, clear slot 0 and save its task history before the second native sync reports zero. Do not mislabel that logged lifecycle as guard-related array loss or claim nonzero schedule preservation.

**STOP:** SkyLink `get_script_functions({"className":"IntelEngine"})` returned `isError:true`, `"An error occurred invoking 'get_script_functions'."` No retry, fallback provider, later live property read or explicit maintenance mutation. Failure Pushover sent successfully. Last live call precedes the **57.83-second** closeout upper bound; Skyrim left open on A, without saving/quitting. This is a metadata-tool failure of unknown cause, not demonstrated failure invoking an IntelEngine native function. Inspected SkyLink source uses PSC/catalog metadata, not live PEX VM introspection; whole source/installed-provider equivalence is not asserted.

Private Native evidence root `SKSE/build-cache-persistence-20261012/script-repair-runtime-20261014_122046/`: current winner/module/preflight/preservation/catalog/load/player/image/failure receipts, immutable pre-load/current/load-window logs, `runtime-log-proof.json`, `script-repair-runtime-result.json` and documentation checkpoint. **Observed load-maintenance smoke passes; full state/function validation remains partial.** Seven direct calls, live slot/array/counter comparison, nonzero scheduled entries, first-install/null-array/length-mismatch and legacy-recovery edges are untested. Continuing the planned narrow SkyrimNet quest-state reads on the already loaded fixture requires a new bounded block; no blind metadata retry, reload or save. RNE's two captured Dispel errors remain separate. **26/30; migration BLOCKED**, unchanged.

**Owner-authorized read-only continuation (2026-10-14), PASS within observed empty-state scope:** fresh same-PID/start-time/module hashes and successful world readiness reads; the named HUD/TrueHUD/BTPS menus exactly match the previously visually verified world baseline. An overly strict local `menu_open` check briefly misclassified them as blocking and sent a premature Pushover; corrected against retained evidence without repeating any game request or dismissing a menu. Fresh SkyrimNet SSE catalog/player/quest discovery confirms the same Beta/level/position and eight bound quest scripts, including Core/Schedule. Bulk property discovery supplies metadata, not values; all empty metadata `value` fields were treated as unknown, not unbound.

Fourteen typed value reads verify all **five Core arrays have length 5**, all **eight Schedule arrays have length 10**, `SlotStates=["0","0","0","0","0"]`, ten provider-serialized null Actor entries and `ScheduledCount=0`. Recount agrees with occupied entries for this empty schedule. Sequential reads are not an atomic snapshot, and occupied-state retention/nonzero recount are not tested. The known Hisin Story clear predates these reads. Live block finished at **168.625s**, without MCP errors, mutations, focus/input, reload/save/quit or SkyLink retry; left Skyrim open. Captured incremental logs contain zero repaired-binding/None-array diagnostics. Private root `SKSE/build-cache-persistence-20261012/script-repair-continuation-20261014_123248/` holds raw schemas/requests/replies/logs, `live-state-assertions.json`, `verified-continuation-result.json` and final documentation checkpoint. The verified result supersedes only the initial locally misclassified blocker receipt, retained for chronology. Seven direct global invocations and nonempty/first-install/null-array/length-mismatch/legacy-recovery cases remain unperformed; no mutation or general/static-call authority was inferred from quest-state reads. **26/30; migration BLOCKED**, unchanged.

**Next populated-schedule block: preparation only, BLOCKED before task creation.** Owner selected scheduling/restart/cancellation with startup/exact load if needed. Fresh ADT PID50472 loaded unchanged A after exact ESS/SKSE preservation and131 SQLite backing snapshots, all `quick_check=ok`; module/winner identity and live Schedule signatures verified. `ConfirmScheduleMeeting=2` requires normal Allow confirmation, absent from the agreed operation map. No meeting, restart or cancellation executed; no owned test task/cleanup. Skyrim left open, unsaved. Primary acknowledged failing to clearly announce startup immediately before launch; future launches require a clear notice, and no further live calls occurred after stop. Private `SKSE/build-cache-persistence-20261012/populated-schedule-20261014_125346/stopped-result.json` and owning journal record exact commands, local stderr-capture correction, alerts and limits. Continue only after explicit confirmation-handling authorization; never disable settings or assume a populated-state pass. Prior passes and **26/30; migration BLOCKED** remain unchanged.

**Owner-authorized normal-Allow populated schedule test — PASS (2026-10-14).** Same PID50472/already-loaded A, no startup/reload. Normal confirmation retained (`ConfirmScheduleMeeting=2`); pinned beta26 source exposes actual MessageBox body/buttons and `SelectOption`. Immediate baseline: all schedules empty/count0, all Core states0, TimeScale20. Before mutation,131 current backing DB snapshots passed `quick_check`; original A save identities unchanged. One `ScheduleMeeting(Actor 0x1200939C, "Whiterun", "tomorrow noon")` for Aurine Emarthe [Beggar]; exact observed confirmation body/buttons matched, one semantic HTTP Allow selection returned200/echoed Allow and UI returned to its world baseline. Slot0 contains that exact Actor reference/destination/time and count1.

One `RestartMonitoring()` preserves **all eight serialized schedule arrays and count exactly**, still1; one `CancelSchedule(Actor 0x1200939C)` returns **all eight arrays/count to their exact immediate baseline**, count0. Live block231.641s (<300); no failed MCP calls, foreground/input, setting changes, new load/save/quit or operation replay. Captured logs show creation, monitoring restart with1 pending, cancellation and zero None-array cast errors. A local Python exact-lowercase task-type assertion briefly stopped on observed `Travel`; corrected that validator only, with explicit owner notice and no creation replay. Its stop/alert remains historical; final verified result supersedes the assessment. Capitalization mechanism is not attributed.

Evidence root `SKSE/build-cache-persistence-20261012/populated-schedule-confirmed-20261014_130236/`: exact requests/replies/Allow receipt, immediate/populated/restarted/cancelled values, preservation/logs, `runtime-assertions.json`, `verified-result.json` and documentation checkpoint. This proves **in-session populated restart preservation and count/occupancy consistency for one already-correct count**, not nonempty save/reload retention or repair of a deliberately desynchronized count. Normal scheduling/cancellation metadata/narration can persist; cancellation is not whole-world/backing rollback. Seven direct global calls and initialization/legacy edges remain untested. Skyrim left open, unsaved; **26/30; migration BLOCKED**, unchanged.

**Owner-authorized populated schedule save/reload — PASS (2026-10-14).** Game was closed; explicit **STARTING SKYRIM NOW** notice preceded the unchanged ADT SKSE launch. Fresh PID25200/module/provider/winner/profile identities qualified, eight original A/B/C/D save files copied and131 backing databases snapshotted before exact A load. Empty schedule/count0, Core states0, normal confirmation2 and TimeScale20 verified. One future Aurine meeting (`Actor 0x1200939C`, Whiterun, tomorrow noon) accepted through the observed normal Allow button; one dedicated SkyLink `save_game` writes new **`ie-schedule-retention-20261014-143124`**, never an original fixture.

Both new save files are nonempty and independently hashed/copied. SKSE framing consumes the entire file, matches the golden reader's format/runtime header, and the complete framed PapyrusUtil STRV span contains zero raw TAB/LF/VT/FF/CR. This framing/control check does **not** decode the primary ESS/Papyrus state or assert complete STRV scalar-grammar safety.131 additional current read-only-source SQLite backups precede one exact new-checkpoint reload.

| Disposable checkpoint artifact | Bytes | SHA-256 |
|---|---:|---|
| `ie-schedule-retention-20261014-143124.ess` | 2903065 | `65bf7f0e4791dc22c07a23175de7ecd18f60d73b9c26dceca03dace0b1ba379d` |
| `ie-schedule-retention-20261014-143124.skse` | 64806 | `0401431053e9ab749e5810e67eeb280912a5e864f7e81804bdb358d59ad270a7` |

Post-reload reads preserve **all eight arrays and ScheduledCount exactly**, including actor/destination/time/task fields and count1. Captured logs show automatic co-save recovery, two maintenance/monitoring restarts with1 pending, continued pending loops and zero None-array cast diagnostics. One `CancelSchedule(Actor 0x1200939C)` returns every array/count to the exact immediate empty baseline. Live block **210.953s** (<300), zero provider errors/native-operation replays, no foreground/input/settings changes; original four save families unchanged. Skyrim left open after cancellation, with no save of the canceled state.

A local exact-position assertion briefly stopped and sent an alert: same player ref/UUID/name/level and X/Y, Z differed by0.000488 game units. Corrected only that validator using retained replies and ordinary floating-point tolerance; exact schedule comparisons unchanged. Stop/alert/correction receipts retained; no creation/save/load replay or provider fallback, and continuation stayed within the original deadline.

Private root `SKSE/build-cache-persistence-20261012/schedule-save-reload-20261014_143124/` records exact lifecycle/native/Allow intents and responses, before/after arrays, two backing preservation sets, original and disposable save identities, framing/control scan, immutable logs, `verified-result.json` and documentation checkpoint. Generated artifacts are the **new test save family**, not new PEX/DLL/package/installation. The retained disposable checkpoint still contains an active test meeting: **do not use it as a normal-play checkpoint**. Cleanup proves schedule-array/count restoration, not whole-world/database rollback. Seven direct globals, initialization/legacy/counter-desynchronization edges and independent cold populated reload remain untested; **26/30; migration BLOCKED**, unchanged.

**Owner-authorized independent-process schedule attempt — BLOCKED before load (2026-10-14).** Existing ADT PID25200/world/player/module/winner/profile identities qualified. All five exact ESS/SKSE families (original four plus disposable `ie-schedule-retention-20261014-143124`) copied/hash-checked, complete input SKSE framing/whole-STRV control check preserved.132 current backing DB snapshots before quit and132 additional shutdown-final snapshots before any rewind, all `quick_check=ok`; inventory includes newly found `IntelEngine-1792005497652-314282.db`.

One qualified SkyLink `qqq` without saving; independent Windows wait/count confirms original exit/count0. Explicit **STARTING SKYRIM NOW** notice before one unchanged ADT SKSE launch. Independent new **PID58276**, distinct start time and all four loaded module hashes verified. After the fixed12-second launch settle interval, captured harness status is **`enabled=true`, `game_state="Data Loaded"`, `uptime_s=0`**; UI is **`menu_open=false`, `menus=[]`, `messagebox=null`**. This is not the required fresh Main Menu predicate. Stopped immediately, authorized Pushover delivered; no retry/fallback, checkpoint load, save, schedule/property reads, cancellation or later game query. Observation timestamp span47.405s (<300), not a completed cold-retention scenario.

Private root `SKSE/build-cache-persistence-20261012/schedule-cold-reload-20261014_150212/` retains preservation manifests/copies, old connection/player/quit/exit receipts, announced startup, old/new process/module identities, captured UI/status, previous-session and stopped-new-session log copies, `stop.json`, notification and `stopped-result.json`. All ten protected save files remain unchanged. New process left open at its **last observed** startup state; later UI progression unobserved. No test meeting was loaded/created, so cancellation is not applicable in this block. No new PEX/DLL/package/installation/test save or RNE/source/config/profile/publication changes.

**Outcome:** startup readiness unqualified at observation; cause UNKNOWN, not proof of a startup crash, IntelEngine regression or permanent blocker. Prior same-process populated restart/reload/cancellation passes remain scoped passes. Cold populated retention/monitoring/cancellation, direct globals and initialization/legacy edges remain unperformed; **26/30 / migration BLOCKED**, unchanged. Next requires a separately authorized bounded readiness check on the already-running intended instance, then only if qualified one exact disposable load/retention/cancel sequence; do not automatically repeat quit/startup or settled checks.

**Owner-authorized cold-readiness continuation — PASS (2026-10-14).** No further quit/startup. Fresh process/start-time/module/winner/profile checks match the already-running independent **PID58276** from the preserved old25200 exit/new58276 launch receipts. Named **Main Menu** now observed (`BTPS Menu`, `Cursor Menu`, `Main Menu`, `TrueHUD`), harness enabled; fresh SkyLink schema/connection qualified. Five complete save families unchanged/copied and132 fresh current backing DB snapshots passed `quick_check=ok` before timeline rewind. One background exact `load ie-schedule-retention-20261014-143124`, actual Running/named world UI and same Beta player ref/UUID/level/position qualified.

All **eight serialized schedule arrays and ScheduledCount match the saved populated snapshot exactly**, count1/Actor0x1200939C; five Core states0. Captured append-boundary-verified Papyrus logs show automatic co-save recovery/maintenance and monitoring restarted with1 pending at15:11:43 and15:11:46, followed by owned cancellation at15:11:57. One `CancelSchedule(Actor0x1200939C)` returns all eight arrays/count exactly to the original empty baseline,count0. Zero captured None-array diagnostics/provider errors/native-operation retries; **55.531s** live continuation (<300). Final same process/world UI observed open; no new meeting/save/quit/foreground-input/settings changes or later game queries.

Private root `SKSE/build-cache-persistence-20261012/schedule-cold-continuation-20261014_151109/`: preservation/catalog/readiness/load/signature/property/cancel receipts, exact before/cold/after-cancel fields, prefix-validated before/final/window logs, `log-proof.json`, `verified-result.json` and documentation checkpoint. Prior startup-stop/notification remain historical, not erased; this new authorized block closes the previously unperformed **one-meeting independent-process retention/automatic-monitoring/cancellation check** only. No new compiled/package/installed artifacts or test save; existing disposable family hashes remain as listed above. Retained checkpoint still contains the test meeting and is not a normal-play save; live cancellation is not whole-world/backing rollback.

Seven direct global consumer calls, first-init/null/length/legacy/desynchronized-count fixtures and remaining full42/HUD/warm-cold displayed-name/PapyrusUtil-reader-provenance checks remain untested. **26/30 / existing-save migration BLOCKED**, unchanged; no acceptance/migration gate closure inferred from this scoped schedule pass.

### Known limitations / deferred: existing-save migration

**BLOCKED.** Other Intel narration/message/reason scalars (including rescue narration), names/destinations and string-list control handling remain outside this repair. They can still expose persistence defects; this is not general Intel/PapyrusUtil storage safety. For future authorized A/B acceptance, scan the whole framed STRV span for raw TAB/LF/VT/FF/CR before key extraction, attribute only unambiguous boundaries and require expected-field/name equality. Original BEL/space and lone-ESC/empty fidelity in other scalars is unknown from serialized bytes alone.

Migration remains blocked until production codec/grammar and real-template checks, a coherent fresh package, installed winner/module/native-binding identity, immediate rendering, unchanged clean-A warm and independent cold loads, and fresh post-load cache B reload all pass with layered evidence. Source checks alone cannot unblock it. Even all passing gates permit only separately requested planning of an approved follow-up; no automatic migration or discarded-name recovery. The local OpenSpec record is gitignored; local docs/handoffs are not commit/push/publication evidence.

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

### Rendered-cache source checkpoint (2026-10-12)

- Production stdlib check passed: all 255 supported non-NUL bytes, exact percent/control mapping, UTF-8/quotes/backslash/empty transport, all three families and both gossip joins, unrelated names, full grammar, declared/written empty-map gap and malformed/raw controls.
- Actual Native and Game prompt files each passed 47 temporary real-Inja checks (SkyrimNet `87eccda247690c3b29c403e9e15b44f6747f159d`, Inja `affabd9fb6e679b2535382063e11ac9cc5ff860c`, JSON 3.12.0): byte recovery, percent-last literals, empty caches, list ordering, actor/mode gates and current-task behavior. The old gossip reader failed the same decoded-byte check before its repair.
- All five PSC/template mirrors and this API document matched byte-for-byte. `verify.ps1 -SkipDeployTargets -Quiet` passed 79 source-asset checks, not DLL/PEX freshness or runtime checks.
- **At the source-stage checkpoint:** canonical/package DLL and PEX files were still the old generation; source checks did not establish compiled/package/runtime acceptance. The detached build attempt below supersedes only the compiled-artifact status. Existing-save migration stays BLOCKED.

### Historical detached build attempt — prerequisite stop (2026-10-12)

- Detached Native DLL build completed 513/513 steps with VS2022 MSVC 19.44.35229.0, existing clean pinned CommonLib and installed static vcpkg dependencies. All 511 generated compiler commands retain `/Od /Ob0 /DNDEBUG /std:c++23preview -MT`; SE/AE enabled, VR disabled, audited ABI correction preserved. Manifest installation disabled and FetchContent disconnected; no downloads or deployment hooks.
- Fresh `SKSE/build-cache-persistence-20261012/IntelEngine.dll`: 5,639,680 bytes, SHA-256 `6eef089112311aba26a5d95af3fad1c506b6ab3923a8a2b3b29e9da6a76ddfb3`; expected SKSE exports inspected. Native canonical `SKSE/build/Release/IntelEngine.dll` remains unchanged at `4f8eec94da652362cabca0a3f45c323baaef92bb03cf7e8567863ba6d1bc6c17`.
- Original compiler built current `IntelEngine.psc` into detached `SKSE/build-papyrus-cache-persistence-20261012/IntelEngine.pex`: 18,229 bytes, SHA-256 `555892ac9a632c29a1d21f290e2892c93bf20a43e451bd5c21f1b0cbd1fdafc2`, zero warnings/errors. Read-only disassembly confirms the new String-returning Global Native encoder with one String parameter. This is not runtime native-binding proof.
- **Stopped:** Core compilation exited 255 because configured imports lack `SkyMessage` and `MiscUtil` declarations (Core 1140; transitive StoryEngine 1685,2086,3367,3369,4362). No fresh Core PEX, retry, stub headers or unrelated source repair. Read-only discovery found genuine SkyMessage source at `D:/git/MessageBox/Scripts/Source/SkyMessage.psc`; genuine MiscUtil header provenance remains unresolved in the inspected repositories.
- Per-run integrity checks preserved 130 compiler/source/header input files and all 61 Game payload files. **No compiled Game staging:** the DLL/two-PEX set is incomplete, so packaged binaries remain old. No installation, loaded module/binding, immediate rendering or clean-A/B Skyrim acceptance is claimed; migration remains BLOCKED. Resolve real headers and obtain continuation authority before retrying.

### Historical local rendered-cache packaging checkpoint — before deployment (2026-10-12)

- The supplied `D:/gerkgit/SkyrimNet_iPrompts/_build_tools/config.bat:29,37` resolved genuine local PapyrusUtil MiscUtil and Papyrus MessageBox SkyMessage headers. The authorized Core-only retry appended those two read-only folders to the explicit compiler import list, without editing config/shared headers, source or installed mods. Original compiler completed with zero errors/warnings; both PEX files exist only in the detached Native output before staging.
- Fresh `SKSE/build-papyrus-cache-persistence-20261012/IntelEngine_Core.pex`: 91,043 bytes, SHA-256 `77b5dfc9b7d390a77e9f6291a4be19a12ddf88c17289005612f01bb961860718`. Disassembly verifies all four completed scalar writes use the encoder exactly once, with heard+told joins before both gossip encoder calls. The prior successful DLL/API PEX were preserved, not rebuilt.
- Game `SKSE/Plugins/IntelEngine.dll`, `Scripts/IntelEngine.pex` and `Scripts/IntelEngine_Core.pex` now match the three fresh detached artifacts and hashes above. Payload integrity comparison found exactly those three changed files; unrelated package assets and 137 compiler/source/header inputs were preserved. All five PSC/template mirror pairs and this API document match; no extra matching affected DLL/PEX/prompt providers were found inside Game's repository.
- `verify.ps1 -SkipDeployTargets -Quiet` passed 79 source-asset checks; fresh/package SHA-256 equality separately covers the DLL/two PEX omitted by that flag. Native's canonical DLL intentionally remains the old hash above: do not run root staging, which would copy that old DLL back into Game. A full canonical-equality verifier is not the acceptance route for this authorized detached candidate.
- **At this packaging checkpoint: source, compiled and locally staged candidate only.** Installation and gameplay had not yet been verified; the private ADT runtime/offline checkpoint above supersedes that evidence status without implying release or publication. Existing saves remain unsupported, other scalar/list writers remain outside scope, and migration remains BLOCKED until the remaining acceptance gates pass.

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
