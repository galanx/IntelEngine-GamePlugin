Scriptname IntelEngine Hidden
{
    IntelEngine Native API v3.0

    SKSE DLL providing high-performance functions for intelligent NPC tasks:
    - Fuzzy NPC name search with Levenshtein distance
    - Semantic location resolution ("upstairs", "outside")
    - Action validation and failure reasoning
    - Fast string utilities

    All functions are Global Native - implemented in IntelEngine.dll
}

; =============================================================================
; NPC SEARCH FUNCTIONS
; =============================================================================

; Find an NPC by name using fuzzy matching
; Supports: exact match, Levenshtein fuzzy match, partial match
; Returns: Actor if found, None otherwise
Actor Function FindNPCByName(String searchTerm) Global Native

; Find NPC by name, preferring the closest one to akNear when multiple match.
; Use for actor-based actions where proximity matters (fetch, deliver, search).
Actor Function FindNPCByNameNear(String searchTerm, Actor akNear) Global Native

; Get human-readable location name for an NPC
; Returns: Location string (e.g., "Whiterun Marketplace", "Dragonsreach")
String Function GetNPCCurrentLocation(Actor akNPC) Global Native

; Check if an NPC can be interacted with (not disabled, accessible cell)
Bool Function IsNPCAccessible(Actor akNPC) Global Native

; Get suggested NPC name for a failed search (for "did you mean?" prompts)
; Returns: Closest matching NPC name, or empty string
String Function GetNPCNameSuggestion(String searchTerm) Global Native

; =============================================================================
; ACTOR LOCATION FUNCTIONS
; =============================================================================

; Get the parent BGSLocation name for an actor's current location
; Walks the location hierarchy (e.g., The Resting Pilgrim -> Helgen)
String Function GetActorParentLocationName(Actor akNPC) Global Native

; Unified destination resolver — handles semantic terms, compound phrases, and named locations
; All resolution intelligence is native C++ for performance and reliability
; Examples: "outside", "upstairs", "out of Helgen", "leave", "Bannered Mare"
ObjectReference Function ResolveAnyDestination(Actor akNPC, String destination) Global Native

; =============================================================================
; LOCATION RESOLUTION FUNCTIONS
; =============================================================================

; Resolve a named location to a Cell (fuzzy matching)
; Returns the Cell for Skyrim's AI to handle pathfinding
; Returns: Cell if found, None otherwise
Cell Function ResolveLocationToCell(String locationName) Global Native

; Resolve a named location to a BGSLocation (for broader areas like "Whiterun")
; Returns: Location if found, None otherwise
Location Function ResolveLocationToBGSLocation(String locationName) Global Native

; Find a door in loaded cells that leads to the target location
; If found, NPC can walk to this door and use it
; If not found (target not in loaded cells), returns None
ObjectReference Function FindDoorToLocation(String locationName) Global Native

; Resolve a semantic/relative location term to an actual door
; Terms: "upstairs", "downstairs", "outside", "inside", "the back", "cellar", etc.
; Context-dependent: uses NPC's current cell to determine valid options
; Returns: Door reference if resolvable, None if not possible
ObjectReference Function ResolveSemanticLocation(Actor akNPC, String semanticTerm) Global Native

; Get JSON-formatted spatial information about NPC's current cell
; Includes: doors (with destinations), stairs, notable areas
; Returns: JSON string with cell spatial data
String Function GetCellSpatialInfo(Actor akNPC) Global Native

; Check if a term is a semantic/relative location reference
; Returns: True for terms like "upstairs", "outside", etc.
Bool Function IsSemanticTerm(String term) Global Native

; Get available semantic directions from NPC's current location
; Returns: Array of available terms (e.g., ["upstairs", "outside"])
String[] Function GetAvailableSemanticDirections(Actor akNPC) Global Native

; Get suggestion for a failed location search (for "did you mean?" prompts)
; Returns: Closest matching location name, or empty string
String Function GetLocationSuggestion(String searchTerm) Global Native

; =============================================================================
; ACTION VALIDATION FUNCTIONS
; =============================================================================

; Pre-validate if an action is possible before attempting
; actionType: "travel", "fetch_npc", "fetch_item", "deliver_message"
; Returns: True if action is feasible
Bool Function ValidateAction(Actor akNPC, String actionType, String targetParam) Global Native

; Get human-readable reason why an action would fail
; Returns: Failure reason string, empty if action is valid
; Examples: "Cannot find anyone named 'Nazim' - did you mean 'Nazeem'?"
String Function GetActionFailureReason(Actor akNPC, String actionType, String targetParam) Global Native

; =============================================================================
; STRING UTILITY FUNCTIONS
; =============================================================================

; Convert string to lowercase (~2000x faster than Papyrus)
String Function StringToLower(String text) Global Native

; Convert string to uppercase
String Function StringToUpper(String text) Global Native

; Check if string contains substring (~2000x faster than Papyrus)
Bool Function StringContains(String haystack, String needle) Global Native

; Check if string starts with prefix
Bool Function StringStartsWith(String text, String prefix) Global Native

; Check if string ends with suffix
Bool Function StringEndsWith(String text, String suffix) Global Native

; Calculate Levenshtein edit distance between two strings
; Used for fuzzy matching - lower = more similar
Int Function LevenshteinDistance(String a, String b) Global Native

; Trim whitespace from string
String Function StringTrim(String text) Global Native

; Split string by delimiter
String[] Function StringSplit(String text, String delimiter) Global Native

; Escape a string for safe JSON embedding (backslash, quote, newline)
String Function StringEscapeJson(String text) Global Native

; =============================================================================
; INDEX MANAGEMENT FUNCTIONS
; =============================================================================

; Check if NPC and location indexes are built
; Indexes are built automatically from game data on load
Bool Function IsIndexLoaded() Global Native

; Get JSON with index statistics
; Includes: cell count, location count, NPC count
String Function GetIndexStats() Global Native

; Rebuild NPC index from game data (call after major NPC changes)
Function RebuildNPCIndex() Global Native

; Rebuild location index from game data
Function RebuildLocationIndex() Global Native

; =============================================================================
; CELL ANALYSIS FUNCTIONS
; =============================================================================

; Get all doors in the NPC's current cell
; Returns: Array of door ObjectReferences
ObjectReference[] Function GetCellDoors(Actor akNPC) Global Native

; Get destination cell name for a door
String Function GetDoorDestination(ObjectReference akDoor) Global Native

; Get the door's destination reference (the linked door on the other side)
; Returns None if the door has no teleport data
ObjectReference Function GetDoorDestinationRef(ObjectReference akDoor) Global Native

; Check if a door leads to exterior
Bool Function IsDoorExterior(ObjectReference akDoor) Global Native

; Check if a door leads up (destination Z > current Z)
Bool Function IsDoorUpward(ObjectReference akDoor) Global Native

; Check if a door leads down (destination Z < current Z)
Bool Function IsDoorDownward(ObjectReference akDoor) Global Native

; =============================================================================
; ITEM FUNCTIONS
; =============================================================================

; Find an item in an actor's inventory by name (fuzzy match)
; Returns: Form of the item found, None if not found
Form Function FindItemInInventory(Actor akActor, String itemName) Global Native

; Find a nearby item reference by name (fuzzy match)
; Returns: ObjectReference of item, None if not found
ObjectReference Function FindNearbyItemByName(Actor akActor, String itemName, Float radius = 1000.0) Global Native

; =============================================================================
; DISTANCE / MATH UTILITY FUNCTIONS
; =============================================================================

; Get 3D distance between two references (works cross-cell via raw positions)
; Accepts any ObjectReference including Actors
Float Function GetDistance3D(ObjectReference ref1, ObjectReference ref2) Global Native

; Get 2D (XY only) distance between two references
; Useful for off-screen checks where Z height is irrelevant
Float Function GetDistance2D(ObjectReference ref1, ObjectReference ref2) Global Native

; Calculate a game-time deadline based on distance between source and target
; Applies pathfinding multiplier (1.5x), optional round-trip (2x), and safety margin (3x)
; Returns: Absolute game time (days) clamped to [minHours, maxHours]
Float Function CalculateDeadlineFromDistance(ObjectReference source, ObjectReference target, Bool isRoundTrip, Float minHours, Float maxHours) Global Native

; Get XY offset behind a reference (for teleporting behind camera)
; Returns: Float[2] = [offsetX, offsetY] for use with MoveTo
Float[] Function GetOffsetBehind(ObjectReference akRef, Float distance) Global Native

; =============================================================================
; TIME PARSING FUNCTIONS
; =============================================================================

; Parse natural language time condition to game hour
; Supports: named times (dawn, sunset, evening), relative (in 2 hours, soon),
; specific (3pm, 8am), and descriptive (dinner, breakfast, midnight)
; Returns: Target hour (0.0-23.99), or -1.0 if unparseable
Float Function ParseTimeCondition(String condition) Global Native

; Calculate absolute game time for a target hour
; If target hour is before or at current hour, returns tomorrow's time
; Returns: Absolute game time (days) for use with GetCurrentGameTime()
Float Function CalculateTargetGameTime(Float targetHour, Float currentHour) Global Native

; =============================================================================
; DEPARTURE DETECTION FUNCTIONS
; =============================================================================

; Check if an NPC has departed from their starting position in the given slot
; Tracks position internally in C++ — no StorageUtil reads/writes.
; Returns: 0=too early, 1=departed, 2=soft recovery needed, 3=escalate
Int Function CheckDepartureStatus(Actor akActor, Int slot, Float threshold) Global Native

; Reset departure tracking for a slot (call when starting a task)
; Stores actor's current XY position as baseline and clears counters.
Function ResetDepartureSlot(Int slot, Actor akActor) Global Native

; Get current departure retry count for a slot (read-only, for debug)
Int Function GetDepartureRetries(Int slot) Global Native

; =============================================================================
; STUCK DETECTION FUNCTIONS
; =============================================================================

; Check if an NPC is stuck in the given task slot
; Reads actor position natively and tracks movement between calls.
; Returns: 0=moving, 1=soft recovery needed, 3=teleport needed
Int Function CheckStuckStatus(Actor akActor, Int slot, Float threshold) Global Native

; Reset stuck tracking for a slot (call when starting/restarting a task)
; Stores actor's current position as baseline and clears all counters.
Function ResetStuckSlot(Int slot, Actor akActor) Global Native

; Get progressive teleport distance for a slot
; Decreases with each teleport attempt: 2000 -> 1000 -> 500 -> 250
Float Function GetTeleportDistance(Int slot) Global Native

; Get current recovery attempt count for a slot (read-only)
Int Function GetStuckRecoveryAttempts(Int slot) Global Native

; =============================================================================
; OFF-SCREEN TRAVEL DETECTION
; Estimates arrival time from distance, detects when off-screen NPCs are
; stationary (frozen in unloaded cells), and signals Papyrus to teleport.
; =============================================================================

; Initialize off-screen tracking for a slot with pre-computed estimated arrival
Function InitOffScreenTravel(Int slot, Float estimatedArrivalGameTime, Actor npc) Global Native

; Check off-screen progress. Returns 0=in transit, 1=should teleport.
; Before estimated arrival: always 0. After: checks position for movement.
Int Function CheckOffScreenProgress(Int slot, Actor npc, Float currentGameTime) Global Native

; Reset/clear off-screen tracking for a slot
Function ResetOffScreenSlot(Int slot) Global Native

; =============================================================================
; WAYPOINT NAVIGATION
; Finds nearest BGSLocation worldLocMarker toward a destination for stuck
; recovery. Returns a known-good navmesh position at a settlement entrance.
; =============================================================================

; Find nearest location marker that's closer to dest than the actor is
ObjectReference Function FindNearestWaypointToward(Actor npc, ObjectReference dest, Float maxRadius) Global Native

; =============================================================================
; HOME DOOR ACCESS (anti-trespass + pathfinding)
; Unlock/lock home doors and set cells public/private before NPC travel.
; Prevents trespass warnings and locked-door pathfinding failures.
; =============================================================================

; Unlock/lock NPC's home door + set cell public/private. Returns door ref.
; Call with unlock=true before travel, unlock=false on task completion.
ObjectReference Function SetHomeDoorAccess(Actor akNPC, Bool unlock) Global Native

; Same but takes a cell FormID directly (for target NPC's home in fetch/deliver).
ObjectReference Function SetHomeDoorAccessForCell(Int cellFormId, Bool unlock) Global Native

; Get the home cell ID from the last ResolveAnyDestination call.
; Returns 0 if the last destination was not a home. Used to store for re-locking.
Int Function GetLastResolvedHomeCellId() Global Native

; =============================================================================
; SLOT TRACKER FUNCTIONS (C++ state mirror for SkyrimNet decorators)
; Push slot state from Papyrus to C++ so SkyrimNet decorators and eligibility
; tags can read it synchronously. Called by Core on state changes and game load.
; =============================================================================

; Push a slot update to C++ SlotTracker. Called by AllocateSlot, SetSlotState.
Function UpdateSlotState(Int slot, Actor agent, Int newState, String taskType, String targetName) Global Native

; Clear a slot in C++ SlotTracker. Called by ClearSlot.
Function ClearSlotState(Int slot) Global Native

; Check if an actor is available for new tasks (no active task + no cooldown).
; Used as backend for SkyrimNet tag eligibility check.
Bool Function IsActorAvailable(Actor akActor) Global Native
Bool Function HasBaseAIPackages(Actor akActor) Global Native
Bool Function HasNonSandboxAI(Actor akActor) Global Native
ObjectReference Function GetEditorLocationRef(Actor akActor) Global Native

; =============================================================================
; STORY ENGINE FUNCTIONS
; =============================================================================

; Resolve a name from the DM response to the EXACT Actor from the last candidate pool.
; Uses stored FormIDs from BuildDungeonMasterContext/BuildNPCInteractionContext.
; Falls back to FindNPCByName if the name isn't in the pool.
; USE THIS instead of FindNPCByName for story dispatch to avoid name ambiguity.
Actor Function ResolveStoryCandidate(String name) Global Native

; Find a suitable messenger to deliver a message on behalf of sender.
; Cascade: household member → social associate → same-hold guard → any civilian.
; Returns None if no messenger found (caller decides self-delivery vs reject).
Actor Function FindMessengerForSender(Actor sender) Global Native

; Get a random NPC eligible for Story Engine dispatch.
; Filters: alive, not disabled, not in combat, not in player's cell,
; not on an active IntelEngine task, not on cooldown.
Actor Function GetRandomStoryCandidate() Global Native

; Get a story candidate ranked by MemoryDB engagement (memories + events).
; Falls back to GetRandomStoryCandidate if no memory-ranked candidates.
Actor Function GetMemoryDrivenCandidate() Global Native

; Get a story candidate related to the given actor (shared event history).
; Falls back to any ranked NPC excluding akRelatedTo.
Actor Function GetRelatedCandidate(Actor akRelatedTo) Global Native

; Get an actor's UUID as hex FormID string (e.g., "0x00013B9E").
; Used for SkyrimNet template context.
String Function GetActorUUID(Actor akActor) Global Native

; Check if the player is in a dangerous location (dungeon, crypt, cave, etc.).
; Used by Story Engine to avoid dispatching NPCs into danger zones.
Bool Function IsPlayerInDangerousLocation() Global Native

; Check if there are doors to dangerous interiors (dungeons, caves, forts) near a quest marker.
Bool Function HasNearbyDungeonEntrance(ObjectReference akQuestLocation) Global Native

; Check if the player is in their own home (LocTypePlayerHouse keyword).
; Used by Story Engine for knocking prompt.
Bool Function IsPlayerInOwnHome() Global Native

; Get the exterior-side door reference for the player's current home.
; Returns the door outside the home for MoveTo teleport targets.
ObjectReference Function GetPlayerHomeExteriorDoor() Global Native

; Get the interior-side door reference for the player's current home.
; Returns the door inside the home — used to place NPCs at the doorway.
ObjectReference Function GetPlayerHomeInteriorDoor() Global Native

; Check if an NPC has a civilian class (farmer, merchant, innkeeper, etc.).
; Civilians should not enter dangerous locations.
Bool Function IsCivilianClass(Actor akActor) Global Native

; Check if an NPC is a Jarl (has JobJarlFaction).
Bool Function IsJarl(Actor akActor) Global Native

; Set danger zone dispatch policy (0=allow all, 1=block civilians, 2=followers only, 3=block all).
Function SetDangerZonePolicy(Int policy) Global Native

; Set player home visit policy (0=allow all, 1=block civilians, 2=followers only, 3=block all).
Function SetPlayerHomePolicy(Int policy) Global Native

; Set per-story-type hold restriction (0=no restriction, 1=same hold civilians, 2=same hold except followers, 3=same hold everyone).
Function SetHoldRestrictionPolicy(String storyType, Int policy) Global Native

; Check if an NPC passes the hold restriction for a story type (true = allowed).
Bool Function CheckHoldRestriction(Actor akActor, String storyType) Global Native

; Get the hold name for an actor (walks BGSLocation hierarchy to hold level).
String Function GetActorHoldName(Actor akActor) Global Native

; Get recent dialogue history for an NPC. Returns formatted string, empty if no dialogue.
String Function GetRecentDialogue(Actor akActor, Int maxExchanges = 1) Global Native

; Check if an NPC knows the player (has dialogue, memories, or relationship data).
Bool Function NPCKnowsPlayer(Actor akActor) Global Native

; Check if actor is in PotentialFollowerFaction (can be recruited as follower).
Bool Function IsPotentialFollower(Actor akActor) Global Native

; Check if the player is in a location on the blocklist (plugin config, 30s cache).
Bool Function IsPlayerInBlockedLocation() Global Native
Bool Function IsPlayerInWhitelistedLocation() Global Native

; Check if a JSON LLM response contains "should_act":true.
; Faster than Papyrus string parsing. Used by Story Engine response handlers.
Bool Function StoryResponseShouldAct(String response) Global Native

; Extract a string field value from simple JSON (e.g., "narration", "subject").
; Handles escaped quotes. Returns "" if field not found.
String Function StoryResponseGetField(String json, String fieldName) Global Native

; Build a JSON fragment with actor data for LLM context.
; slot 0 = single actor: actorName, actorRace, actorGender, subj, obj, poss
; slot 1 = first in pair: actor1Name, actor1Race, actor1Gender
; slot 2 = second in pair: actor2Name, actor2Race, actor2Gender
String Function BuildActorContextJson(Actor akActor, Int slot) Global Native

; Build DM context (world state + candidate pool) for Story Engine tick.
; Returns JSON-safe pre-escaped markdown string, or "" if no eligible candidates.
; absenceDays: min days since player interaction for NPC eligibility (MCM-configurable).
String Function BuildDungeonMasterContext(Int maxCandidates = 7, Float absenceDays = 3.0) Global Native

; Build complete JSON request for Story DM prompt.
; dmContext is pre-escaped from BuildDungeonMasterContext; excludedTypes is escaped here.
String Function BuildStoryDMRequestJson(String dmContext, String excludedTypes) Global Native

; Build NPC-to-NPC interaction context for the NPC Social tick.
; Groups eligible loaded NPCs by location, scores by density and MemoryDB social history.
; Returns JSON-escaped markdown string, or "" if no eligible groups.
String Function BuildNPCInteractionContext(Int maxPairs = 4) Global Native

; Wrap NPC context into JSON for the NPC-to-NPC DM prompt.
; npcContext is pre-escaped from BuildNPCInteractionContext.
String Function BuildNPCInteractionRequestJson(String npcContext) Global Native

; Mirror story cooldown to C++ so candidate builders can filter before LLM call.
; gameTime: the Intel_StoryLastPicked timestamp (NOT current time on rejection).
Function NotifyStoryCooldown(Actor akActor, Float gameTime) Global Native

; Mirror social cooldown to C++ so pair pool can filter cooldown NPCs.
Function NotifySocialCooldown(Actor akActor, Float gameTime, Float cooldownHours) Global Native

; Check if an actor is currently on story cooldown (dispatched recently).
Bool Function IsActorOnStoryCooldown(Actor akActor) Global Native

; Record that the LLM picked a story type. Used for DM prompt balancing.
Function NotifyStoryTypePicked(String storyType) Global Native
Function WarmStoryTypeCountsFromCSV(String csv) Global Native
Function SetRecentGossipContext(String gossipLines) Global Native

; Get FormIDs of all NPCs in the last DM candidate pool.
; Used to pre-warm cooldowns from StorageUtil before the DM prompt.
Int[] Function GetDMCandidatePoolFormIDs() Global Native
Int[] Function GetNPCCandidatePoolFormIDs() Global Native

; Scan loaded actors for those currently running one of the given packages.
; Returns JSON: [{"name":"...","formId":123,"pkgFormId":456},...]
String Function ScanActorsWithPackages(Int[] packageFormIDs) Global Native

; Spawn leveled enemies at a location for quest system.
; Looks up vanilla ActorBases by EditorID (no CK properties needed).
; enemyType: "bandit", "draugr", or "dragon"
; Returns: array of spawned Actor references.
Actor[] Function SpawnQuestEnemies(ObjectReference location, String enemyType) Global Native

; Spawn a chest containing a specific named item at a location.
; itemName: exact item name (resolved via ItemIndex fuzzy match).
; Returns: the spawned chest ObjectReference, or None if item not found.
ObjectReference Function SpawnQuestChest(ObjectReference location, String itemName) Global Native

; Validate that an item name exists in the ItemIndex.
; Returns true if a matching item is found (exact or fuzzy).
Bool Function ValidateQuestItem(String itemName) Global Native

; Get a random valuable item name from the ItemIndex.
; minGoldValue: minimum gold value threshold (e.g. 500).
; Returns: item display name, or "" if no items qualify.
String Function GetRandomQuestItemName(Int minGoldValue = 500) Global Native

; Spawn a boss-tier enemy near a location.
; enemyType: "bandit" (LvlBanditBoss), "draugr" (LvlDraugrWarlockMale), or "dragon" (EncDragon01Fire).
; Returns: the spawned boss Actor, or None on failure.
Actor Function SpawnQuestBoss(ObjectReference location, String enemyType) Global Native

; Find a deeper spawn point in the current interior cell.
; Scans for dungeon landmarks (word walls, boss chests, coffins, shrines),
; then falls back to door traversal. Returns None if no deeper point found.
ObjectReference Function FindDeeperSpawnPoint(Actor akActor) Global Native

; Scan current interior cell for prisoner furniture (shackles, cages, stocks).
; Returns the highest-priority prisoner furniture ref, or None if none found.
ObjectReference Function FindPrisonerFurniture(Actor akActor) Global Native

; Scan current interior cell for USABLE prisoner furniture (Furniture form type only).
; Only returns objects NPCs can actually sit in (shackles, stocks with idle markers).
; Use for Activate() path — NPC plays bound/restrained idle animation.
ObjectReference Function FindUsablePrisonerFurniture(Actor akActor) Global Native

; Deep rescue anchor — scans current cell + cells behind doors for prisoner
; furniture or landmarks. Follows load doors to find cages/shackles deep inside.
ObjectReference Function FindRescueAnchor(Actor akActor) Global Native

; Get the boss room anchor for a dungeon location (from DungeonIndex).
; Returns a persistent ref deep inside the dungeon, accessible even when cell is unloaded.
; Used to pre-place rescue victims and quest chests at the boss room before the player enters.
ObjectReference Function GetDungeonBossAnchor(String locationName) Global Native

; Scan cells AHEAD of the actor (through doors, not current cell) for prisoner
; furniture or landmarks. Returns an anchor in the next cell (invisible to player).
ObjectReference Function ScanAheadForAnchor(Actor akActor) Global Native

; Check if a specific named item is still inside a container.
; Used to detect when the player retrieves the quest item from the chest.
Bool Function IsQuestItemInChest(ObjectReference container, String itemName) Global Native

; Record that a quest item was used (for rotation — avoids repeats).
Function NotifyQuestItemUsed(String itemName) Global Native

; Record that an NPC was used as a rescue victim (for rotation — avoids repeats).
Function NotifyRescueVictimUsed(String victimName) Global Native

; Record that a quest location was used (for rotation — avoids repeats).
Function NotifyQuestLocationUsed(String locationName) Global Native

; =============================================================================
; MEMORYDB FUNCTIONS (SkyrimNet SQLite reader)
; =============================================================================

; Get formatted memories for an NPC from SkyrimNet database.
; Returns LLM-ready text with memories ordered by importance and recency.
String Function GetNPCMemories(Actor akActor, Int maxCount = 5) Global Native

; Get recent world events from SkyrimNet database.
; eventTypeFilter: comma-separated types ("dialogue,direct_narration") or "" for all.
String Function GetRecentWorldEvents(Int maxCount = 10, String eventTypeFilter = "") Global Native

; Get NPCs ranked by story activity (memories + events weighted by recency).
; Returns comma-separated NPC names, excludes player.
String Function GetActiveStoryNPCs(Int maxCount = 10) Global Native

; Get relationship summary between two NPCs based on shared events and memories.
String Function GetNPCRelationshipSummary(Actor akActor1, Actor akActor2) Global Native

; Check if the MemoryDB is connected to SkyrimNet database.
; Returns "true" or "false".
String Function IsMemoryDBConnected() Global Native

; Get number of player interactions with an NPC from MemoryDB.
; Returns 0 if they have never interacted.
Int Function GetPlayerInteractionCount(Actor akNPC) Global Native


; =============================================================================
; BIO SECTION PRE-RENDERING FUNCTIONS
; Workaround: papyrus_util("GetStringList") can't see lists created during
; the current session. These render list data as a single string for
; papyrus_util("GetStringValue") which works immediately.
; =============================================================================

; Pre-render facts section (first person). Returns "## Things I Know\n- I ..."
; Store result with StorageUtil.SetStringValue(npc, "Intel_FactsRendered", ...)
String Function RenderFactsSection(String[] facts, Float[] factTimes, Float currentGameDays) Global Native

; Pre-render gossip heard section (first person). Returns "## Rumors I've Heard\n..."
String Function RenderGossipHeardSection(String[] rumors, String[] sources, Float[] times, Float currentGameDays) Global Native

; Pre-render gossip told section (first person). Returns "## Rumors I've Shared\n..."
String Function RenderGossipToldSection(String[] rumors, String[] recipients, Float[] times, Float currentGameDays) Global Native

; Pre-render task history section (first person). Returns "### Past Tasks\nWhat I've done:\n..."
String Function RenderTaskHistorySection(String[] descs, Float[] times, Float currentGameDays) Global Native

; =============================================================================
; DASHBOARD FUNCTIONS
; =============================================================================

; Notify the PrismaUI dashboard that slot data changed (triggers JS refresh)
Function NotifyDashboardSlotChanged() Global Native

; Get the current dashboard hotkey VK code (-1 = disabled, 120 = F9 default)
Int Function GetDashboardHotkey() Global Native

; Set the dashboard hotkey VK code and persist to settings.yaml
Bool Function SetDashboardHotkey(Int vkCode) Global Native

; Hot-reload the dashboard UI from disk without restarting the game
Function ReloadDashboardUI() Global Native

; Re-read hotkey config from settings.yaml (takes effect immediately)
Function ReloadDashboardConfig() Global Native

; Push comprehensive dashboard state JSON to PrismaUI frontend
Function PushDashboardFullState(String json) Global Native

; Check if dashboard is currently visible
Bool Function IsDashboardOpen() Global Native

; Retrieve a pending Director parameter stored by C++ (for Director mode dispatch)
String Function GetPendingDirectorParam(String key) Global Native

; Clear all pending Director parameters
Function ClearPendingDirectorParams() Global Native

; =============================================================================
; DEBUG / TESTING FUNCTIONS
; =============================================================================

; Test NPC search and log results
Function TestNPCSearch(String searchTerm) Global Native

; Test location resolution and log results
Function TestLocationResolve(String locationName) Global Native

; Test semantic resolution and log results
Function TestSemanticResolve(Actor akNPC, String term) Global Native

; Test action validation and log results
Function TestValidation(String actionType, String target) Global Native

; Set debug logging level (0=off, 1=errors, 2=warnings, 3=info, 4=verbose)
Function SetDebugLevel(Int level) Global Native

; Get current DLL version
String Function GetVersion() Global Native

; =============================================================================
; FACTION POLITICS FUNCTIONS
; =============================================================================

; Get relation score between two factions (-100 to +100)
Int Function GetFactionRelation(String factionA, String factionB) Global Native

; Adjust relation between two factions by delta, returns new score
Int Function AdjustFactionRelation(String factionA, String factionB, Int delta) Global Native

; Get player standing with a faction (-100 to +100)
Int Function GetPlayerFactionStanding(String factionId) Global Native

; Adjust player standing with a faction by delta, returns new standing
Int Function AdjustPlayerFactionStanding(String factionId, Int delta) Global Native

; Check if two factions are at war
Bool Function IsFactionAtWar(String factionA, String factionB) Global Native

; Get war morale for queryFaction in an active war between factionA and factionB (0-100, -1 if no war)
Int Function GetWarMorale(String factionA, String factionB, String queryFaction) Global Native

; Get human-readable relation status (Alliance/Friendly/Neutral/Tense/Hostile/Critical)
String Function GetRelationStatus(String factionA, String factionB) Global Native

; Build comprehensive political context JSON for LLM prompts
String Function BuildPoliticalContext(Float gameTime) Global Native

; Build compact political dashboard JSON for PrismaUI
String Function BuildPoliticalDashboardJson() Global Native

; Record a political event between factions, returns event ID (-1 on failure)
Int Function RecordPoliticalEvent(String factionA, String factionB, String eventType, String description, Int delta, Float gameTime) Global Native

; Check if a political event should physically manifest near the player.
; Returns JSON spawn instructions or empty string if player is not at the event location.
String Function CheckEventManifestation(String factionA, String factionB, String eventType) Global Native

; Confirm manifestation cooldown after Papyrus verified actors spawned successfully.
Function ConfirmManifestationCooldown() Global Native

; Check if faction politics system is enabled
Bool Function IsPoliticsEnabled() Global Native

; Get politics tick interval in game hours
Int Function GetPoliticsTickInterval() Global Native

; Hot-reload faction config from factions.yaml
Function ReloadFactionConfig() Global Native

; Get loaded faction leader Actor references (for fact injection)
; Returns only leaders currently loaded in the game world
Actor[] Function GetFactionLeaderActors(String factionId) Global Native

; Get FormIDs for all faction leaders (works even when unloaded)
; Use with Game.GetForm() to get Actor references regardless of load state
Int[] Function GetFactionLeaderFormIds(String factionId) Global Native

; Parse and apply player_standing_changes from Political DM response
; Returns number of standings applied
Int Function ApplyPlayerStandingChanges(String responseJson) Global Native

; Process player conduct with cross-faction consequences
; Applies primary delta to factionId, then checks if the reporter NPC belongs
; to a rival/ally faction and applies inverse/matching delta (halved)
; Returns number of standings changed (1-2)
Int Function ProcessPlayerConduct(Actor reporter, String factionId, String sentiment, String reason) Global Native

; Check crime gold against political factions, apply standing penalties for new bounties
; Returns number of standings changed
Int Function CheckCrimeGoldStandings() Global Native

; Decay all non-zero player standings by decayRate toward 0
; Returns number of standings decayed
Int Function DecayPlayerStandings(Int decayRate) Global Native

; Write political_state.json for pull-based NPC awareness
; Call after standing changes to make them visible to NPCs
Function WritePoliticalStateFile() Global Native

; --- Phase 2 Migration: FactionPolitics C++ Logic ---
; Process Political DM response in C++. Returns JSON with actions for Papyrus (fact injection, battle poll, etc.)
String Function ProcessPoliticalDMResponse(String response, Int success) Global Native

; Run standing mechanics (decay + crime). Returns JSON: {decayed, crimeChanges, updated}
String Function RunStandingMechanics() Global Native

; Runtime politics settings
Function SetPoliticsEnabled(Bool enabled) Global Native
Function SetPoliticsTickInterval(Int hours) Global Native

; === War Lifecycle ===

; Declare war between two factions. Returns war ID or -1 on failure.
; Validates: max wars, cooldown, faction existence, no duplicate war.
Int Function DeclareWar(String factionA, String factionB, Float gameTime) Global Native

; Process one war tick: apply morale decay, check surrender.
; Returns JSON array of war updates (including ended wars with victor).
String Function ProcessWarTick(Float gameTime) Global Native

; End a specific war with a named victor. Returns true on success.
Bool Function EndFactionWar(String factionA, String factionB, String victor, Float gameTime) Global Native

; Get number of currently active wars.
Int Function GetActiveWarCount() Global Native

; Get the DB war ID for an active war between two factions. Returns -1 if no war.
Int Function GetActiveWarId(String factionA, String factionB) Global Native

; Get war strength for a faction in an active war. Returns 0 if no war.
Int Function GetWarStrength(String factionA, String factionB, String queryFaction) Global Native

; Record an off-screen battle result. Applies morale/strength changes. Returns battle ID or -1.
Int Function RecordOffScreenBattle(String factionA, String factionB, String location, String result, String narrative, Int attackerLosses, Int defenderLosses, String victor) Global Native

; === Faction Query ===

; Returns true if the NPC is high-status (Jarl, unique+essential leader) and should never travel personally.
Bool Function IsHighStatusNPC(Actor npc) Global Native

; Extract faction ID from "faction:FactionId" format. Returns "" if no prefix.
String Function ExtractFactionId(String enemyType) Global Native

; Get display name for a faction ID. Returns the ID itself if not found.
String Function GetFactionDisplayName(String factionId) Global Native

; Get a rival faction ID for the given faction. Returns first rival, or "" if none.
String Function GetFactionRival(String factionId) Global Native

; Get the faction's current war enemy. If at war, returns the opponent. Falls back to rival.
String Function GetFactionWarEnemy(String factionId) Global Native

; Get the political faction ID an NPC belongs to ("StormcloakFaction", "ImperialFaction", etc).
; Returns "" if the NPC is not affiliated with any political faction.
String Function GetNPCPoliticalFactionId(Actor npc) Global Native

; Find a loaded NPC belonging to the given political faction.
; Returns None if no loaded faction member is found.
Actor Function FindFactionMember(String factionId) Global Native

; === Battle System (Player-Present) ===

; Get soldier template EditorID for a faction. Empty if not configured.
String Function GetFactionSoldierTemplate(String factionId) Global Native

; Spawn soldiers from a faction's template at the given reference.
; factionIdWithCount format: "FactionId:Count" (e.g., "StormcloakFaction:7")
; Falls back to generic bandit if template not found. Returns array of spawned Actors.
Actor[] Function SpawnBattleSoldiers(String factionIdWithCount, ObjectReference spawnAt) Global Native

; Execute the ENTIRE battle spawn sequence in C++: player join, position calculation,
; spawn both sides at anchor, faction assignment, leader selection, bounty snapshot.
; Returns JSON: {success, sideACount, sideBCount, paired, playerJoined, joinFaction, notification,
;                leaderFormId, sideAFormIds, sideBFormIds}
String Function ExecuteFullBattleSpawn(String questAutoJoinFaction, Actor player, Float playerAngleZ, ObjectReference spawnAnchor) Global Native

; Spawn reinforcements for an active battle (wave 2+). Handles factions, aggression, combat, crime factions.
String Function SpawnReinforcements(Int count, Actor player, ObjectReference spawnAnchor = None) Global Native

; Get FormIDs of soldiers on a given side ("A" or "B"). Returns JSON: {formIds: [...], count, alive}
String Function GetBattleSoldierFormIds(String side) Global Native

; Set all alive soldiers on a side as player teammates (C++ — bypasses FormID overflow).
Function SetBattleSoldiersAsTeammates(String side) Global Native

; Count dead soldiers on a given side ("A" or "B").
Int Function CountDeadBattleSoldiers(String side) Global Native

; Cleanup battle soldiers by proximity. Returns count of remaining actors.
Int Function CleanupBattleSoldiers(Float playerX, Float playerY, Float playerZ, Float playerAngleZ, Bool forceAll) Global Native

; Force cleanup ALL battle soldiers (hard timeout).
Function ForceCleanupAllSoldiers() Global Native

; Bounty prevention: removes crime factions from spawned soldiers at battle start.
Function SnapshotBounties() Global Native

; Clear kPlayerTeammate flag from all actors — called on battle end to restore normal guard behavior.
Function ClearBattleTeammates() Global Native

; Clear all hold bounties — called during active battle polls to suppress bounty from friendly fire.
Function ClearAllHoldBounties() Global Native

; Get an integer from a JSON array by key and index.
Int Function GetJsonArrayInt(String json, String arrayKey, Int index) Global Native

; Set per-actor Protected flag (instance-level, doesn't affect other actors sharing the same ActorBase).
Function SetActorProtected(Actor akActor, Bool protect) Global Native

; Get named NPCs near a reference point who witnessed the battle (excludes battle-spawned soldiers).
Actor[] Function GetNearbyWitnessNPCs(ObjectReference center, Float radius) Global Native

; Start a new player-present battle. Returns battle ID or -1 if already active.
Int Function StartBattle(String factionA, String factionB, String locationName, Int warId) Global Native

; End the active battle with a result and victor.
Function EndBattle(Int battleId, String result, String victor) Global Native

; Register a spawned actor in the active battle.
; tier: 0=generic soldier, 1=recruited NPC, 2=faction leader
Bool Function RegisterBattleActor(Actor akActor, String factionId, Int tier) Global Native

; Poll battle state. Returns JSON with events, morale, alive counts, wave triggers, battle_over.
; Returns "{}" if no battle active. Call every 3 seconds from Papyrus.
String Function PollBattleState() Global Native

; Get current morale for a faction in the active battle (0-100).
Int Function GetBattleMorale(String factionId) Global Native

; Adjust morale by delta (clamped 0-100).
Function AdjustBattleMorale(String factionId, Int delta) Global Native

; Check if a battle is currently active.
Bool Function IsBattleActive() Global Native

; Get active battle ID, or -1 if none.
Int Function GetActiveBattleId() Global Native

; Get alive count for a faction in the active battle.
Int Function GetBattleAliveCount(String factionId) Global Native

; Get current wave number (0=pre-battle, 1=vanguard, 2=reinforcements, 3=reserves).
Int Function GetBattleCurrentWave() Global Native

; Advance to next wave. Called after spawning wave actors.
Function AdvanceBattleWave() Global Native

; Set the player's battle side. Applies morale boost (+15 ally, -5 enemy).
; factionId must be factionA or factionB of the active battle. Empty string = leave.
; Returns false if no active battle or invalid faction.
Bool Function SetPlayerBattleSide(String factionId) Global Native

; Remove player from hold crime factions (prevents ALL bounty).
; Called at faction quest start. Stays removed until RestorePlayerCrimeFactions.
Function RemovePlayerCrimeFactions() Global Native

; Restore player to hold crime factions and clear residual bounty.
; Called when faction quest fully completes.
Function RestorePlayerCrimeFactions() Global Native

; Get the player's current battle side (empty = spectator/not participating).
String Function GetPlayerBattleSide() Global Native

; Get the ESP battle side ("A" or "B") for a political faction ID.
; Uses the normalized mapping where the player's allied faction is always SideA.
String Function GetFactionBattleSide(String factionId) Global Native

; Check if the player participated in the current battle at any point.
Bool Function HasPlayerParticipatedInBattle() Global Native

; Check if a faction is involved in the active battle (used for crime gold exemption).
Bool Function IsBattleFaction(String factionId) Global Native

; --- Remaining Migration: Text builders, math, display formatters ---
String Function BuildTaskHistoryDesc(String taskType, String target, String result, String msgContent, String meetLocation) Global Native
String Function GetSlotStatusNative(String taskType, Int taskState, String targetName, String cellName) Global Native
String Function GetPreciseTimeDescription(Float meetTimeHours, Float currentGameTime) Global Native
String Function GetTimeDescription(Float hours) Global Native
String Function DetermineLatenessOutcome(Float scheduledTime, Float arrivalTime, Float gracePeriod) Global Native
Bool Function IsUrgentMessage(String msgContent) Global Native
String Function BuildStuckNarration(String taskType) Global Native

; --- Phase 3 Migration: StoryEngine helpers ---
; Build exclude list from toggle bitmask + environment flags. Returns comma-separated string.
; Bitmask: bit0=seekPlayer..bit13=questFactionBattle. envFlags: bit0=isInterior, bit1=isDangerous.
String Function BuildExcludeList(Int toggleBitmask, Int envFlags) Global Native

; Validate a DM story response. Returns JSON: {valid, reason, type}
String Function ValidateStoryResponse(String responseJson, Int toggleBitmask, Int envFlags) Global Native
; Build fact text for faction_battle quest dispatch (courier wording).
String Function BuildFactionBattleDispatchFact(String alliedFaction, String questLocation, String playerName) Global Native

; Record faction_battle completion: facts for leaders + political event. Returns JSON.
String Function RecordFactionBattleCompletion(String alliedFaction, String questLocation, String playerName, String enemyFaction = "") Global Native

; Build expiry fact when player didn't show up for a faction_battle.
String Function BuildBattleExpiryFact(String alliedFaction, String questLocation, String playerName) Global Native

; --- Phase 1 Migration: BattleManager C++ Logic ---
; All game logic moved to C++. Papyrus calls these and uses return JSON for engine operations.

; Finalize battle: apply standings, record events, build narrative. Returns JSON with all results.
String Function FinalizeBattle(Int battleId, String result, String victor, Int deadA, Int deadB, String locationName, Float gameTime) Global Native

; Calculate reinforcement spawn positions behind player relative to battle center.
String Function CalculateReinforcementPositions(Float playerX, Float playerY, Float playerZ, Float centerX, Float centerY, Int waveNum) Global Native

; Evaluate whether player should auto-join a battle side. Returns JSON with decision.
String Function EvaluatePlayerJoinBattle(String questAutoJoinFaction) Global Native

; Get notification text for a battle event type.
String Function GetBattleNotification(String notificationType, String locationName, String victorName, Bool playerWon) Global Native

; Validate that a faction_battle quest can be dispatched. Returns JSON with canStart + enemyFaction.
String Function ValidateFactionBattleDispatch(String alliedFaction, String suggestedEnemy = "") Global Native

; Calculate mid-battle state for late-arriving player. Returns JSON with soldiersPerSide + moraleLoss.
String Function CalculateMidBattleState(Float scheduledTime, Float currentTime) Global Native

; Get action from poll result. Returns JSON with action type + params.
String Function GetBattlePollAction(String stateJson) Global Native

; Reset all battle state. Called after cleanup completes.
Function ResetBattleState() Global Native

; Calculate exterior battle marker position. Returns JSON with x/y/z.
String Function CalculateBattleMarkerPosition(Float playerX, Float playerY, Float locX, Float locY, Float locZ, Float offsetUnits) Global Native

; --- Pending Battle Functions ---
; Create a pending battle at a named location. Returns pending ID or -1 if location not found.
Int Function AddPendingBattle(String locationName, String factionA, String factionB, String resultJson) Global Native

; Poll pending battles for player proximity. Returns triggered pending ID or -1.
; Also auto-expires battles past their 3-hour deadline.
Int Function PollPendingBattles() Global Native

; Remove a pending battle by ID (after triggering or manual cleanup).
Function RemovePendingBattle(Int pendingId) Global Native

; Clear all pending battles and expired results. Called on game reload.
Function ClearPendingBattles() Global Native

; Get pending battle info as JSON string. Returns "{}" if not found.
String Function GetPendingBattleInfo(Int pendingId) Global Native

; Get count of active pending battles.
Int Function GetPendingBattleCount() Global Native

; Get and consume the last expired battle result JSON. Returns "" if none.
; Used to show RESULT notification when pending battles expire off-screen.
String Function GetLastExpiredBattleResult() Global Native

; --- JSON Array Helper Functions ---
; Get length of a JSON array. If key is empty, treats json as the array itself.
Int Function GetJsonArrayLength(String json, String key) Global Native

; Get item at index from a JSON array. If key is empty, treats json as the array.
String Function GetJsonArrayItem(String json, String key, Int index) Global Native
