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

**BREAKING / coherent providers required:** start a fresh new game with the repaired DLL, freshly compiled `IntelEngine.pex`/`IntelEngine_Core.pex` and all three repaired prompts already winning, or use only an eligible offline-converted copy as described below. Unconverted existing saves, including apparently cache-free saves, remain unsupported: old values can poison restoration before scripts run or ambiguously decode literal percent text. There is no raw fallback or general post-load safety guarantee.

Native owns C++/PSC/templates; Game is the Data-layout mirror. Keep both PSC files and all three prompt pairs byte-identical, and mirror this API document explicitly (root staging does not copy docs). Source equality does not prove DLL/PEX freshness, packaged equality does not identify installed winners, and neither proves runtime behavior. Stop on new PEX/old DLL missing binding, old Core PEX/new DLL raw writes, old templates/new encoded caches, or ambiguous providers; do not assume an unbound call's result.

Rollback requires the complete old DLL/PEX/template set and its separately preserved pre-cutover save lineage. Do not load repaired saves under old components or rewrite evidence saves.

### Player fix mode: How to convert an old save

The standalone Windows tool includes a one-save `fix` command for eligible IntelEngine 3.5.2 saves. Run it from anywhere: no installed PapyrusUtil hash, VFS or game-root placement is required. Qualification uses SKSE co-save format 1, owner `0x424510A2`, exactly one STRV v1 block with complete unique framing, and co-save runtime **1.6.1170.0** or **1.7.104.0** only. Other formats/runtimes refuse. Existing expert `convert`/`inspect` behavior is unchanged.

Offline production fix-entry comparisons passed after safety corrections: run12 produced 29 caches / 44 name spans and SKSE SHA-256 `645dd18910bac6c3f43f613cf2b16e700b36f235fb76eb40bc6dc49a70a3ea0b`; run15 produced 13 caches / 28 name spans and `224340e1407404d0a4c93f29dbae5a3cfb31654a355a884bcb7c589ef28b9441`. Both ESS outputs were unchanged and preserved-source hashes/metadata matched. These checks used the production fix entry with an injected no-game test predicate: the actual CLI correctly refused while Skyrim was running, so closed-game production CLI success is not claimed. Migration/codec checks, Unicode-path launcher checks and refusal/partial-publication regressions passed.

1. Close Skyrim. Keep the same-directory, same-stem `.ess` and `.skse` pair together. Make sure you have a backup of IntelEngine and SkyrimNet external data as well if you may need timeline rollback.
2. Put `LegacyCacheMigration.exe` beside `Convert-IE-Save.bat`, or run it directly from any working directory. Drag exactly one `.ess` onto the adjacent batch file, or run:

   ```powershell
   & "C:\path with spaces\LegacyCacheMigration.exe" fix --save "C:\path with spaces\My Save.ess"
   ```

3. Success creates `<stem>_IEbackup/` containing the original `.ess` and `.skse`, plus sibling `<stem>_IEconverted.ess` and `<stem>_IEconverted.skse`. The tool does not overwrite existing backup/output files. It leaves the original pair unchanged.
4. Exit **0** means both verified converted files were published; **2** means usage, eligibility or safety refusal; **3** means I/O, verification or publication failure. If publishing the second file fails, the first converted file may remain. This is an incomplete pair: do not load it, and retain the backup and all remaining files for diagnosis.
5. Install the complete repaired providers (DLL, both affected PEX files and all three prompts) before using the converted pair. Never load a converted save with IntelEngine 3.5.2. Do not convert again, mix original and converted companions, or assume already-lost names/history can be recovered.

Rollback means restoring the preserved original pair with its matching old providers and the corresponding IntelEngine/SkyrimNet external-data snapshot. The pair backup does not include external databases or their `-wal`/`-shm` files. Do not mix saves/providers or claim general legacy-save safety.

The historical writer's identity/provenance cannot be proved from the file. Treating serialized BEL as a space is owner policy, not recovered original text. The required real-template smoke rendered all three full fixed prompts through Inja commit `affabd9fb6e679b2535382063e11ac9cc5ff860c`. Legacy literal `%07%09%0A%0B%0C%0D%1B%25%250A%0a%41%07` produced payload bytes `07090A0B0C0D1B2525304125306125343107`: the upper-case control tokens became their control bytes, `%25` became `%`, `%250A` became literal `%0A` without recursion, and lowercase `%0a` / unknown `%41` remained literal. Encoding that same literal input with the production codec preserved it through all three templates. This measured decoder behavior does not establish that native restoration of legacy percent text is safe.

### Offline legacy-save conversion

The standalone Windows converter supports a narrowly qualified IntelEngine **3.5.2** writer lineage on Skyrim **1.6.1170.0**, not arbitrary existing saves. One real legacy save passed converted-copy acceptance: 28/28 sampled surviving cache values matched exact UTF-8, plus one explicitly policy-derived facts field; a separate checkpoint retained these and two naturally generated fresh caches (31 fields) through warm and independent cold reloads. Named production facts/gossip templates passed for two sampled actors. All 42 resolvable original names matched; two temporary-actor name spans were preserved byte-for-byte but **not live-verified**. This is not full-HUD or general form-resolution qualification. **Migration on 1.7 is not yet verified**; fresh-new-game repair evidence on 1.7.104 does not establish migration support.

#### Eligibility and refusal policy

- Require complete supported SKSE/STRV framing, exact counts and EOF, canonical lowercase keys, pinned provider/runtime/codec provenance and evidence covering **every** target: `intel_factsrendered`, `intel_gossiprendered`, `intel_taskhistoryrendered`. Inspection alone never grants eligibility.
- `actor-in-place` requires explicit `legacy_writer: "IE-3.5.2"`, `actor_bel_policy: "space"` and `preserve_rne_name_bel: true` in both the evidence and qualification basis. It preserves serialized identities without resolving/remapping forms. Only qualified actor identities are eligible; temporary cache targets refuse. Temporary holders containing only supported unchanged names may be preserved, not declared runtime-qualified.
- In that actor policy, serialized BEL means space and LF is allowed within a complete value. Genuine original BEL, ESC, other C0 controls and DEL refuse; non-cache `rne_name` BEL spans remain unchanged. `legacy` fields require independently established original bytes; `legacy-policy` fields additionally declare `original_basis: "owner-policy"` rather than claiming independent originals.
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
7. Install the **complete repaired** DLL/PEX/prompt set before manually copying the new pair into an isolated test save location. The tool never installs or loads it. Compare pre-frozen surviving names/text and actual named prompts, then a separate checkpoint's retained and freshly generated caches through warm and independent cold reloads before adopting that lineage. **Never load a converted save with IntelEngine 3.5.2.**

**Rollback:** with the game closed, select the preserved original `.ess`/`.skse` pair with its complete matching old providers, and restore the corresponding IntelEngine/SkyrimNet backing-data snapshot when reverting that timeline. Keep the converted/repaired lineage separate; do not downgrade its saves or mix a pair from different checkpoints. Conversion preserves surviving serialized values, not already-lost names/history, truncated suffixes or unsaved session state; it cannot infer unknown sentinel meanings.

#### Converter checks

The Native source check `SKSE/tests/LegacyCacheMigrationCheck.cpp` uses the production codec and actual converter/transaction code. Run `LegacyCacheMigrationCheck.exe <new-unused-scratch-directory>` after building the standalone targets. It covers global/actor all-family bytes, policy/control/identity/count/framing refusals, mixed/encoded preservation, unchanged names/opaque bytes, exclusive backups and interrupted/failed publication. `SKSE/tests/RenderedCacheCodecCheck.cpp` covers the codec contract. Synthetic byte fixtures are not loadable saves; these checks do not replace the bounded runtime observations above.

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
