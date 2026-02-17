Scriptname IntelEngine Hidden
{
    IntelEngine Native API v1.0

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
; dmContext is pre-escaped from BuildDungeonMasterContext; other values are escaped here.
String Function BuildStoryDMRequestJson(String dmContext, String recentLog, String excludedTypes) Global Native

; Build NPC-to-NPC interaction context for the NPC Social tick.
; Groups eligible loaded NPCs by location, scores by density and MemoryDB social history.
; Returns JSON-escaped markdown string, or "" if no eligible groups.
String Function BuildNPCInteractionContext(Int maxPairs = 4) Global Native

; Wrap NPC context + recent log into JSON for the NPC-to-NPC DM prompt.
; npcContext is pre-escaped from BuildNPCInteractionContext; recentLog is escaped here.
String Function BuildNPCInteractionRequestJson(String npcContext, String recentLog) Global Native

; Mirror story cooldown to C++ so candidate builders can filter before LLM call.
; gameTime: the Intel_StoryLastPicked timestamp (NOT current time on rejection).
Function NotifyStoryCooldown(Actor akActor, Float gameTime) Global Native

; Record that the LLM picked a story type. Used for DM prompt balancing.
Function NotifyStoryTypePicked(String storyType) Global Native

; Get FormIDs of all NPCs in the last DM candidate pool.
; Used to pre-warm cooldowns from StorageUtil before the DM prompt.
Int[] Function GetDMCandidatePoolFormIDs() Global Native

; Spawn leveled enemies at a location for quest system.
; Looks up vanilla ActorBases by EditorID (no CK properties needed).
; enemyType: "bandit", "draugr", or "dragon"
; Returns: array of spawned Actor references.
Actor[] Function SpawnQuestEnemies(ObjectReference location, String enemyType) Global Native

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

; =============================================================================
; DIALOGUE SAFETY NET FUNCTIONS
; =============================================================================

; Tick-based safety net check. Queries MemoryDB for new dialogue since last call,
; runs keyword matching, validates NPC. All logic in C++.
; Returns: 0=nothing, 1=meeting, 2=fetch, 3=delivery keywords detected.
; Call GetSafetyNetNPC() to retrieve the NPC after a positive result.
Int Function RunSafetyNetCheck() Global Native

; Returns the NPC from the last positive RunSafetyNetCheck() call.
Actor Function GetSafetyNetNPC() Global Native

; Get the last NPC the player had a conversation with (from MemoryDB).
Actor Function GetLastConversationPartner() Global Native

; Get recent dialogue text between player and NPC (from MemoryDB).
; Returns JSON-escaped conversation text for safe embedding in contextJson.
String Function GetRecentDialogue(Actor npc, Int maxExchanges = 4) Global Native

; Check if recent dialogue with NPC contains schedule-related keywords.
; Returns: 0=none, 1=meeting, 2=fetch, 3=delivery.
Int Function HasScheduleKeywords(Actor npc) Global Native

; Build JSON context for safety net LLM prompt (all values properly escaped in C++).
String Function BuildSafetyNetContextJson(Actor npc, Int keywordHint) Global Native

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
