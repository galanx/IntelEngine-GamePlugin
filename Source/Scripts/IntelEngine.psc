Scriptname IntelEngine Hidden
{
    IntelEngine Native API

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
Bool Function IsLocationNonCombative(ObjectReference ref) Global Native

; System Pending Watchdog (C++ tracks timestamps, DLL loads fresh every time)
Function MarkSystemPending(String system, Float gameTime) Global Native
Function ClearSystemPending(String system) Global Native
Bool Function ShouldResetPending(String system, Float timeoutHours, Float currentGameTime) Global Native

; Utility
Int Function HexToInt(String hexStr) Global Native
Int Function ParseFormID(String formId) Global Native

; Dialogue Tracker — Auto Bio Updates
Function SetAutoBioEnabled(Bool enabled) Global Native
Function SetAutoBioThreshold(Int threshold) Global Native
Function SetAutoBioCount(Actor akActor, Int count) Global Native
Int Function GetAutoBioCount(Actor akActor) Global Native
String Function GetAutoBioCountsJson() Global Native

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

; Actor targets use 200u plus current world speed × the estimated 0.50s
; response budget; actor |dZ| > 120u returns 0 (reject); markers retain 300u.
Float Function GetArrivalThreshold(Actor agent, ObjectReference target) Global Native

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

; ---- languages (4.0: language packs, Data/SKSE/Plugins/IntelEngine/languages/*.tsv; LanguageBridge in the DLL)
; A word of place said in another language, in English ("domoi", "nach Hause", "n'shpi" give "home") when the whole
; of what was said is one; a name, and English, come back as they were.
String Function PlaceInEnglish(String said) Global Native
; Nothing, "none", or the word for it in a language in force ("net", "keine", "asnje" in their own letters).
Bool Function IsNoneWord(String said) Global Native
; What the player reads, in the game's language where its pack has the sentence; else as it came.
String Function L(String english) Global Native
; Does a sentence speak of this name, in whatever form its language puts it (declined, with an ending)?
Bool Function TextMentionsName(String text, String name) Global Native
; The English name of the language the player reads in ("Russian"); "" for English.
String Function TextLanguage() Global Native
; Whole-word, case-insensitive replace with the word boundaries of any script.
String Function ReplaceWholeWord(String text, String what, String with) Global Native
; A list of names with plain commas, whatever separators the model wrote.
String Function CommaList(String said) Global Native

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
; Before estimated arrival: always 0. After: unloaded=1; loaded waits for stationary ticks.
Int Function CheckOffScreenProgress(Int slot, Actor npc, Float currentGameTime) Global Native
String Function DescribeDistance(ObjectReference a, ObjectReference b) Global Native

; Reset/clear off-screen tracking for a slot
Function ResetOffScreenSlot(Int slot) Global Native

; =============================================================================
; PROXIMITY MONITOR (fast-path arrival detection)
; Native monitor ticks every 150ms on the main thread and fires a Papyrus
; callback when the agent enters the threshold with |dZ| <= zTolerance.
; Actor thresholds are 200u plus actual world speed × an estimated 0.50s
; response budget; marker targets retain a 300u horizontal cylinder.
; The callback receives the slot index as a String ("0".."4").
; =============================================================================

; Arm proximity arrival for a slot. Overwrites any existing watch.
; C++ auto-selects thresholds based on target kind: speed-aware radial Actor
; threshold with 120u Z tolerance, 300u horizontal + 200u Z for markers.
; callbackQuest: quest holding the target script (pass Self from a quest script).
; scriptName: Papyrus script on the quest (e.g. "IntelEngine_Travel").
; callbackFn: function to invoke with slot index as a String arg.
Function ArmProximityArrival(Int slot, ObjectReference agent, ObjectReference target, Quest callbackQuest, String callbackScript, String callbackFunction) Global Native

; Disarm proximity for a slot. Safe to call on an unarmed slot.
; Always call from OnArrival / ClearSlot to prevent stale fire after the
; agent's state advances past the traveling phase.
Function DisarmProximityArrival(Int slot) Global Native

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
Function UpdateSlotState(Int slot, Actor agent, Int newState, String taskType, String targetName, String origin = "", Float startTime = -1.0, String reason = "") Global Native

; Clear a slot in C++ SlotTracker. Called by ClearSlot.
Function ClearSlotState(Int slot) Global Native

; Set per-slot fields in C++ SlotTracker for co-save persistence.
Function SetSlotSpeed(Int slot, Int speed) Global Native
Function SetSlotDeadline(Int slot, Float deadline) Global Native
Function SetSlotOffscreenArrival(Int slot, Float arrival) Global Native

; Returns true if slot state was recovered from SKSE co-save (skip StorageUtil recovery).
Bool Function HasCoSaveTaskData() Global Native
Bool Function StoryLoadRecovered(Bool complete = false) Global Native
; Which load of which session this is: a number no other load has. A time of the game's real-seconds clock that a
; script kept in the save means something only when it was taken after this very load.
Int Function LoadStamp() Global Native

; Push C++ SlotTracker state to Papyrus arrays (reverse of SyncSlotTrackerFromArrays).
; Called from Maintenance when co-save data exists.
Function SyncArraysFromSlotTracker() Global Native

; --- ProximityMonitor: C++ frame-rate distance/deadline checking ---
; All watches fire ModEvent "IntelEngine_ProximityEvent" with strArg=eventType, numArg=watchId.

; Register a distance watch between two refs. Fires when distance crosses threshold.
; greaterThan=false: fires when dist < threshold. greaterThan=true: fires when dist > threshold.
; zTolerance > 0: also checks vertical distance (multi-floor interiors).
Function RegisterDistanceWatch(Int watchId, Actor source, ObjectReference target, Float threshold, String eventType, Bool greaterThan = false, Float zTolerance = 0.0) Global Native

; Register a distance-to-player watch. Fires when source-to-player distance crosses threshold.
Function RegisterPlayerWatch(Int watchId, Actor source, Float threshold, String eventType, Bool greaterThan = false) Global Native

; Register a game-time deadline watch. Fires when currentGameTime >= gameTime.
Function RegisterDeadlineWatch(Int watchId, Float gameTime, String eventType) Global Native

; Clear all watches for a given ID (slot index).
Function ClearProximityWatches(Int watchId) Global Native

; Clear a specific watch by ID + event type.
Function ClearProximityWatch(Int watchId, String eventType) Global Native

; Check if an actor is available for new tasks (no active task + no cooldown).
; Used as backend for SkyrimNet tag eligibility check.
Bool Function IsActorAvailable(Actor akActor) Global Native
Bool Function HasBaseAIPackages(Actor akActor) Global Native
Bool Function HasNonSandboxAI(Actor akActor) Global Native
ObjectReference Function GetEditorLocationRef(Actor akActor) Global Native

; =============================================================================
; STORY ENGINE FUNCTIONS
; =============================================================================

; Automatic DM/social responses resolve only within the latest candidate pools.
; Exact names precede unique case/whitespace/role-normalized matches.
; Unknown names and distinct-ID matches reject; repeated reference IDs resolve, with no global fallback.
Actor Function ResolveStoryCandidate(String name, String partnerName = "", Actor anchor = None) Global Native

; Manual Director only: exact full display name across indexed actor references.
; Same-reference duplicates are allowed; distinct-reference clashes and dead/disabled/deleted actors reject.
Actor Function ResolveDirectorActor(String name) Global Native
String Function GetDirectorFailureMessage(String name) Global Native

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
; Expected-optional field: missing keys log at debug; malformed JSON still warns.
String Function StoryResponseGetOptionalField(String json, String fieldName) Global Native

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

; Async NPC DM tick. Captures engine state on the main thread (fast), builds the
; markdown context + JSON on a worker thread, then invokes the named callback on
; the quest with the prepared JSON string ("" if no eligible groups).
; Callback signature: Function <callbackFunction>(String contextJson)
Function BeginAsyncNPCDMTick(Int maxPairs, Quest callbackQuest, String callbackScript, String callbackFunction) Global Native

; Async Story DM tick. Same async pattern as BeginAsyncNPCDMTick — main-thread
; snapshot + worker-thread context+JSON build + callback dispatch.
; Eliminates ~30-60ms of synchronous SQL+actor-scan stutter per tick.
; Callback signature: Function <callbackFunction>(String contextJson)
Function BeginAsyncStoryDMTick(Int maxCandidates, Float absenceDays, String excludedTypes, Quest callbackQuest, String callbackScript, String callbackFunction) Global Native

; Mirror story cooldown to C++ so candidate builders can filter before LLM call.
; gameTime: the Intel_StoryLastPicked timestamp (NOT current time on rejection).
Function NotifyStoryCooldown(Actor akActor, Float gameTime) Global Native

; Mirror social cooldown to C++ so pair pool can filter cooldown NPCs.
Function NotifySocialCooldown(Actor akActor, Float gameTime, Float cooldownHours) Global Native

; Check if an actor is currently on story cooldown (dispatched recently).
Bool Function IsActorOnStoryCooldown(Actor akActor) Global Native

; Record that the LLM picked a story type. Used for DM prompt balancing.
Function NotifyStoryTypePicked(String storyType) Global Native

; Record a Story DM dispatch with full beat detail (type + dispatcher NPC +
; brief narration). The entry starts as DISPATCHED; if any validation gate
; aborts the dispatch, call MarkLastDispatchFailed with a reason and the head
; entry flips to REJECTED for the next DM tick to see.
Function RecordStoryDispatch(String storyType, String npcName, String narration) Global Native

; 4.0 living world: may a story moment land now? seam: 0 = the clock, 1 arrived in town, 2 entered an inn,
; 3 left a dungeon, 4 on the road, 5 woke up, 6 came home, 7 quest done. Always true at the Classic level.
Bool Function LivingWorldMayDeliver(Int seam, Bool urgent) Global Native

; 4.0 living world settings (indexes as on the settings page): level 0 Classic, 1 Rumors, 2 Lives; interruptions
; 0 Never, 1 If urgent, 2 Realistic; quest NPCs 0 Never, 1 If important, 2 Freely; pacing 0 Calm,
; 1 Normal, 2 Lively; then the days a follower told to wait keeps waiting and the days before a follower left
; behind starts a life of their own.
Function SetLivingWorldSettings(Int level, Int interruptions, Int questNpcs, Int pacing, Float waitDays, Float lifeDays, Bool skippedTimeCounts) Global Native

; 4.0 living world: a story moment really started with this NPC (counted for pacing and rotation). Not for rejections.
Function LivingWorldMomentDispatched(Actor npc, String storyType) Global Native

; 4.0 storylines (StorylineBridge). Kinds: 1 meeting, 2 request, 3 visit. Requests: 1 find someone, 2 bring an item,
; 3 deal with a threat, 4 take me somewhere, 5 speak with someone, 6 free a captive. Events: 1 achieved, 2 met,
; 3 declined, 4 time ran out, 5 someone died, 6 talked, 7 no-show, 8 fell through. Days: until the deadline, 0 none.
Int Function StorylineOpen(Int kind, Int request, Actor owner, Actor other, Location place, ObjectReference target, Form item, Float days, Int importance, Bool urgent) Global Native
String Function StorylineRefusal(Int kind, Int request, Actor owner) Global Native
Bool Function StorylineEvent(Int id, Int eventId) Global Native
Int[] Function StorylineOpenIds() Global Native
Int[] Function StorylineOverdue() Global Native
; field: "slot", "objective" (255 none), "stage", "kind", "request", "importance", "comes" (1: the one it is about goes
; along with the player), "replied" (1: they sent an answer); -1 when there is no such storyline
Int Function StorylineField(Int id, String field) Global Native
Actor Function StorylineOwner(Int id) Global Native
Actor Function StorylineOther(Int id) Global Native
Location Function StorylinePlace(Int id) Global Native
ObjectReference Function StorylineTarget(Int id) Global Native
Form Function StorylineItem(Int id) Global Native
String Function StorylineMemory(Int id) Global Native
Int Function StorylineReward(Int id, Int playerLevel) Global Native
Int Function StorylineOpenIdFor(Actor owner) Global Native
; Branches from conversation. CallOff: the one who asked no longer needs it (stage 14). Amend: change 1 more time,
; 2 hurry, 3 raise the reward (gold = the sum named), 4 a new person, place or item; returns "" when changed, else why
; not. Reply: the one it is about sends an answer back through the player and/or comes along; "" when recorded.
Bool Function StorylineCallOff(Int id, String note) Global Native
String Function StorylineAmend(Int id, Int change, Actor other, Location place, ObjectReference target, Form item, Int gold, String note) Global Native
String Function StorylineReply(Int id, Actor speaker, String reply, Bool comesAlong) Global Native
Int Function StorylineAboutId(Actor person) Global Native
String Function StorylineOtherMemory(Int id) Global Native
Int Function StorylineOfferedGold(Int id, Int playerLevel) Global Native
; Whether running quests let this person go along with the player (their own storyline objective left out).
Bool Function StorylineMayComeAlong(Actor person) Global Native
; Why a request was asked, in the asker's words; shown with it in both people's bios and memories.
Bool Function StorylineSetAbout(Int id, String text) Global Native
; field: "about" (why it was asked), "reply" (the answer sent back), "note" (the reason for the last change); "" when none.
String Function StorylineText(Int id, String field) Global Native

; 4.0 quests (QuestBridge; docs/QUESTS.md in the native plugin). Templates: 1 keepsake, 2 bounty, 3 venture. Phases:
; 0 planned, 1 open, 2 ended. Endings: 10 done, 11 kept, 12 declined, 13 ignored, 14 the giver died, 15 went alone,
; 16 the ally died, 17 lapsed. Every step is a fact the DLL reads from the game; the scripts show and place.
Int Function QuestPlanFor(Actor giver) Global Native
Int Function QuestPlanVenture(Actor ally) Global Native
; A venture where a former follower already is on an adventure of their own life (met at the dungeon).
Int Function QuestPlanVentureHere(Actor ally) Global Native
; Spots ahead of the player where people stand, along the way (dx, dy) they are going (0, 0: the way they face).
ObjectReference[] Function QuestSpotsAhead(Float dx, Float dy) Global Native
; Points on the ground ahead (the navmesh, roads first): x, y, z triples, best first.
Float[] Function QuestGroundAhead(Float dx, Float dy) Global Native
; The same, on roads only (an ambush waits on the road itself).
Float[] Function QuestRoadAhead(Float dx, Float dy) Global Native
; The planned venture this actor is the ally or companion of, 0 = none.
Int Function QuestVentureOf(Actor actor) Global Native
; A planned quest ends before it was taken on: 12 declined, 15 went alone, 17 nothing came of it.
Bool Function QuestEndPlanned(Int id, Int ending) Global Native
Bool Function QuestAccept(Int id) Global Native
Bool Function QuestDecline(Int id) Global Native
Int[] Function QuestLapse() Global Native
Int[] Function QuestOpenIds() Global Native
Int Function QuestPlannedFor(Actor giver) Global Native
; Reads the facts and moves the quest on: (ending * 256) + the bits of the steps done now; 0 = nothing changed.
Int Function QuestAdvance(Int id) Global Native
Bool Function QuestMayHandOver(Int id) Global Native
Bool Function QuestHandOver(Int id) Global Native
; field: "slot", "step", "steps", "phase", "ending", "template", "truth", "placed", "gold", "openstage", "endstage",
; "crypt", "objective" (of the current step, -1 none), "objective<n>" and "log<n>" (of step n); -1 when none
Int Function QuestField(Int id, String field) Global Native
; form: "giver", "foe", "ally", "companion", "place", "anchor", "item", "holder", "marker" (of the current step)
Form Function QuestForm(Int id, String field) Global Native
; text: "stamp", "title", "foename", "narration", "prompt", "memory", "place", "itembase"
String Function QuestText(Int id, String field) Global Native
String Function QuestSetFoe(Int id, Actor foe) Global Native
Function QuestSetPlaced(Int id, Int bits) Global Native
Function QuestApplyTitles() Global Native
; A venture was put on the road: what the two remember of falling in together is written.
Function QuestVenturePlaced(Int id) Global Native
; Test hook: who a venture's ally travels with (0 by chance, 1 a follower type never travelled with, 2 another former follower, 3 alone).
Function QuestDebugForceCompanion(Int mode) Global Native
; A venture's companion who could not be put beside the ally drops out of it (before the meeting only).
Function QuestDropCompanion(Int id) Global Native
; Part of a live quest: a giver on the way, a venture's ally or companion. Other systems leave them be.
Bool Function QuestInvolves(Actor akActor) Global Native
; Ends a casual follow of SeverActions (no roster entry, no teammate flag); true when one was ended. A roster
; companion is never touched.
Bool Function StopCasualFollow(Actor akActor) Global Native
; Makes them the player's follower (join) or lets them go: SeverActions when installed, else SkyrimNet's follow. The
; system's name, "" when none could be called.
String Function QuestFollower(Actor npc, Bool join) Global Native

; 4.0 story arcs (ArcBridge; docs/STORY_ARCS.md). IntelEngine_Arcs.psc offers, shows and carries out; the DLL decides.
; Plans an arc of this pattern (0 whichever fits, 1 a thief, 2 a feud, 3 a murder) with this asker: its id, 0 when none.
Int Function ArcPlan(Actor asker, Int pattern) Global Native
Bool Function ArcAccept(Int id) Global Native
Bool Function ArcDecline(Int id) Global Native
; A planned arc that never reached the player: dropped without a memory.
Bool Function ArcDrop(Int id) Global Native
; Planned arcs never offered in time (their ids).
Int[] Function ArcLapse() Global Native
Int[] Function ArcOpenIds() Global Native
; Reads the facts and moves the arc on: bits 0-7 nodes done now, 8-15 the ending, 16-19 the effect, 20-23 its role,
; 24 a prop goes in place now, 25 the choice may be offered, 26 the hand-over may be offered. 0 = nothing.
Int Function ArcAdvance(Int id) Global Native
; The choice popup's answer (the index of the node's options, -1 not now).
Bool Function ArcAnswer(Int id, Int option) Global Native
; The prop of the current hand-over goes from the player to who the node gives it to.
Bool Function ArcHandOver(Int id) Global Native
; How the brawl of the arc's fight ended: 1 the player won, -1 lost (or it turned into a real fight).
Bool Function ArcBrawl(Int id, Int result) Global Native
; A murder's victim, out of sight, taken home to be killed there; None when in sight, dead already, or no murder.
Actor Function ArcStageVictim(Int id) Global Native
; For this many seconds the arc's people speaking count as speaking with the player (a scene among them).
Function ArcScene(Int id, Float seconds) Global Native
; The prop was put at this reference (a container, or the floor beside it).
Function ArcPlanted(Int id, Int prop, ObjectReference akAt) Global Native
Int Function ArcField(Int id, String field) Global Native
Form Function ArcForm(Int id, String field) Global Native
String Function ArcText(Int id, String field) Global Native
Function ArcApplyTitles() Global Native
; Test hook: the next planned arc's thief, rival or killer is this person (when they may be cast).
Function ArcDebugCast(Actor akActor) Global Native
; Tales: the two holders whose names the journal log of a slot shows (the story so far, the ending), told again after
; every load; and a tale asked of the dungeon master for this asker (its answer sends IntelEngine_ArcOffer).
Function ArcSetHolders(Int slot, ObjectReference akTale, ObjectReference akClose) Global Native
Bool Function ArcRequestTale(Actor akAsker) Global Native
; The script let an arc step's person go after lingering with the player.
Function ArcLingerOver(Int id) Global Native
; A tale's places out in the world: the script places their masters and company (PlaceAtMe resolves leveled lists).
Function ArcBossPlaced(Int id, Int site, Actor akBoss) Global Native
; Someone held at a place for a tale: the script says where they stand (1 away, 2 bound at the heart, 4 gone home).
Function ArcCaptive(Int id, Int captiveState) Global Native
; A rescue asked for: a tale about someone held at a place near the giver's town is written, or nothing (false).
Bool Function ArcRequestRescue(Actor akGiver) Global Native
; What a tale leaves outside a place to be looked at closely (a victim's remains): the script laid it there.
; Where a sign of a trail is laid: x, y, z of a point on the ground out from the place; empty for what lies by the
; place itself (and when no ground was found).
Float[] Function ArcTrailSpot(Int id, Int clue) Global Native
Function ArcCluePlaced(Int id, Int clue, ObjectReference akLies) Global Native
; A hunt asked for: a tale about what is killing people near the giver's town is written, or nothing (false).
Bool Function ArcRequestHunt(Actor akGiver, Bool abRumored = false) Global Native
; What walks by night outside a place of a story (ArcBridge, Arcs.h SpiritState): asked for as a story of its own,
; put there and taken away by the script, laid to rest by the player's hand with what it wants in their pack.
Bool Function ArcRequestHaunt(Actor akGiver, Bool abRumored = false) Global Native
Function ArcSpiritOut(Int id, Actor akShade) Global Native
Function ArcSpiritGone(Int id, Int how) Global Native
Bool Function ArcSpiritRest(Int id) Global Native
; The talk of the day (RumorBridge): who would pass it on where the player stands (the innkeeper, a server, the
; bard; None at a bad moment), and what they bring up unasked (counted as told; "" when nothing is worth a word).
Actor Function RumorPublican() Global Native
String Function RumorBringUp(Actor akTeller) Global Native
; Test hook: something goes round the hold the player is in (with akLead: trouble, and they are the one to go to).
Int Function RumorDebugNote(String asText, Actor akLead, Float afWeight) Global Native
; Test hook: the faction editor's DLL side without the dashboard (FactionEditor.cpp); IntelEngine.log tells.
Function FactionEditorSelfTest() Global Native
Function ArcGangPlaced(Int id) Global Native
; A tale's ambush: one of its men placed (k = 0 leads), and what a look asked of the script done (1 placed, 2 they
; struck, 3 called off unseen).
Function ArcThugPlaced(Int id, Int k, Actor akThug) Global Native
Function ArcAmbushDone(Int id, Int what) Global Native
; Out in the wilds: outdoors and nowhere people live (no town, farm, inn or home): where an ambush may wait.
Bool Function ArcInWilds(ObjectReference akRef) Global Native
; Test hook: how far the director's distance rule takes someone to be (0 here, 1 the same hold, 2 another hold), plus
; 10 when they are close to the player. Logged too.
Int Function ArcDebugReach(Actor akActor) Global Native
; The offer of someone who came from another hold could not go out now: tried again in an hour.
Function ArcOfferLater(Int id) Global Native
; The asker set out at a walk and the player was gone before they got there: the offer goes out when they next meet.
Function ArcOfferDeferred(Int id) Global Native
; The offer of a planned story goes out: its asker comes to the player (IntelEngine_ArcOffer), or stays where they are
; and waits for the two to meet: a stranger, somebody with a post to keep, anybody once the player is out of their town.
Function ArcOffer(Int id, Actor akAsker) Global Native
; How somebody stands with the player where no relationship mod keeps it: read by the dialogue model from what they
; remember of the player (Bonds.h). Test hooks: read this person now; go on as if no relationship mod were installed;
; what was last read of them, in words.
Bool Function BondJudge(Actor akWho) Global Native
Function BondPretendNoMod(Bool on) Global Native
String Function BondDescribe(Actor akWho) Global Native
; Someone of this story (not its asker) who stands beside the player right now, or None: nobody brings their trouble
; to the player in front of the people it is about.
Actor Function ArcCompany(Int id) Global Native
; Somebody other than this visitor is talking with the player right now (a line to the player on its way or being
; said, one that ended within twenty seconds, or one the player answered within twenty seconds): the visitor waits
; their turn.
Bool Function ArcTalkWithAnother(Actor visitor) Global Native
; No other story came to the player or ended within the hour (asked again when a story's asker has reached the player:
; another story may have ended while they were on their way).
Bool Function ArcQuietNow(Int id) Global Native
; The player's answer to an offer, taken from the talk. ArcReadOffer has the talk with the one who asked read for a yes
; or a no; ArcOfferSpoken says what came of it: -1 while it is read, 0 nothing decided (the window asks), 1 yes, 2 no.
Function ArcReadOffer(Int id) Global Native
Int Function ArcOfferSpoken(Int id) Global Native
; Test hook: the player is in the middle of a quest of the journal (one that moved on in the last quarter of an hour and
; that the journal shows). Asking writes a log line for each quest that moved on lately.
Bool Function ArcQuestBusyNow() Global Native
; Test hook: times the parts of a tale's request for this person on the game's thread and writes them to the log.
Function ArcDebugCosts(Actor who) Global Native
; How far a line said to the player carries (SkyrimNet's interaction distance): the measure of "stands with the player".
Function ArcEarshot(Float units) Global Native
; The "Stories" switch: off, no new story of the town begins (ArcBridge::Pace); those open go on to their end.
Function ArcStoriesOn(Bool on) Global Native
; The story-type switches that are OFF, as bits: 1 ambush, 2 stalker, 4 rescue, 8 quest, 16 clear out enemies,
; 32 find an item. They hold inside a story of the town and for the engine's own quests too (ArcBridge.h).
Function ArcStorySwitches(Int off) Global Native
; A story that began as talk in town: someone near its asker whom they stop and ask on their way to the player, or
; None; and the test hook that makes the asker set out at the next look.
Actor Function ArcBystander(Int id, Actor akAsker) Global Native
Function ArcDebugSetOut(Int id) Global Native
; What only scripts can read of what stands between someone and the player (other mods keep it in script storage).
Function ArcHeart(Actor who, Int sparked, Int stance, Int withChild, Bool childIsPlayers, Int children, Bool playersChild, Float refusedAt = -1.0) Global Native
; The game's relationship rank after a story brought someone and the player a step closer, or apart (never beyond
; friendship either way: Hearts.h).
Int Function ArcRankAfter(Int rank, Bool closer) Global Native
; The asker held back for that reason: the story waits until the two are apart (a far-comer tries again in an hour).
Function ArcOfferHeldBack(Int id) Global Native
; Whether someone coming to the player has truly been looking for them (and so hurries): close to the player, come all
; the way from another hold (not someone who merely failed to reach them once). id: their arc when they bring one,
; else 0.
Bool Function ArcHurries(Int id, Actor akActor) Global Native
; How far someone is from the player: 0 loaded or of the player's own settlement, 1 the same hold, 2 another hold.
Int Function ArcReachOf(Actor akActor) Global Native
; Test hook: a tale as the director asks for one, with the asker's own reason, coming to the player from afar.
Bool Function ArcRequestTaleWhy(Actor akAsker, String why) Global Native
; A tale's "give": its prop goes from where it was put to the player; false when it was never put anywhere.
Bool Function ArcFetchProp(Int id, Int prop) Global Native
; Test hook: a hand-written tale (JSON file, absolute path) for this asker.
Bool Function ArcDebugTaleFile(Actor akAsker, String path) Global Native

; 4.0 lives of followers the player left behind (IntelEngine_Lives.psc carries the orders out, one at a time).
; Track: see who follows, who was left behind, who is on an errand, and plan the next change.
Function LivingWorldTrack() Global Native
; Test hook: the next life order sends this former follower adventuring at the nearest dungeon the player cannot see.
String Function LivingWorldDebugAdventure(Actor npc) Global Native
; They have just been with the player: their own life does not greet the player again for its current step.
Function LivingWorldMarkGreeted(Actor npc) Global Native
; The actor of the change that is out, None when there is none.
Actor Function LivingWorldTakeOrder() Global Native
; Followers whose life the record keeps (with the player now or left behind), at most limit: held in the lives
; quest's aliases so the game keeps them in memory (a hireling's reference is not persistent).
Actor[] Function LivingWorldKeepers(Int limit) Global Native
; 1 move them (their own life goes on somewhere), 2 home, 3 take the package off (back with the player, an errand,
; a story), 4 they notice the player
Int Function LivingWorldOrderKind() Global Native
ObjectReference Function LivingWorldOrderTarget() Global Native
; axis 0 x, 1 y, 2 z: from the target to where they stand
Float Function LivingWorldOrderOffset(Int axis) Global Native
Actor Function LivingWorldOrderCompanion() Global Native
Bool Function LivingWorldOrderProtect() Global Native
String Function LivingWorldOrderNarration() Global Native
; true: done; false: not now (someone could see), tried again later
Function LivingWorldOrderDone(Bool ok) Global Native
; The record of one NPC (flags, activity, place, when they parted...), for tests and the log.
String Function LivingWorldDescribe(Actor npc) Global Native
; May this kind of story moment move this NPC? ("Quest NPCs may move"; the target of an objective the
; player has open never moves; "message" always may, the sender stays and a courier goes)
Bool Function LivingWorldMayMove(Actor npc, String storyType) Global Native
; Held by the game right now, at every level of the living world: in a scene, or the target of an objective the
; player has open. Such a person takes no task and is sent nowhere.
Bool Function LivingWorldQuestHolds(Actor npc) Global Native
; Another mod's scene with the player in it has begun (true) or ended (false): nobody comes to the player meanwhile.
Function LivingWorldSceneBusy(Bool busy) Global Native

; 4.0: a place named in SkyrimNet (the player's /mark and Places page, a pack's, another mod's travel markers): a
; persistent reference in its cell or worldspace, None when the destination names no such place. The NPC's own
; marker goes to it with SkyrimNetPlaceOffset (axis 0 x, 1 y, 2 z); IntelEngine_Core.ResolveTravelTarget does both.
ObjectReference Function ResolveSkyrimNetPlace(Actor npc, String destination) Global Native
Float Function SkyrimNetPlaceOffset(Actor npc, Int axis) Global Native
; The base form of an item by its name (the item index), None when there is no such item.
Form Function ResolveItemByName(String itemName) Global Native
; An item this actor carries named exactly so (any case), else None: any mod's "Ale" counts, "Pale Ale" does not.
Form Function FindItemNamedExactly(Actor akActor, String itemName) Global Native

; Flip the most recent RecordStoryDispatch entry to REJECTED with a short
; reason. Called from any early-return path after RecordStoryDispatch.
Function MarkLastDispatchFailed(String reason) Global Native

Function WarmStoryTypeCountsFromCSV(String csv) Global Native
Function SetRecentGossipContext(String gossipLines) Global Native

; Get FormIDs of all NPCs in the last DM candidate pool.
; Used to pre-warm cooldowns from StorageUtil before the DM prompt.
Int[] Function GetDMCandidatePoolFormIDs() Global Native
Int[] Function GetNPCCandidatePoolFormIDs() Global Native

; Scan loaded actors for those currently running one of the given packages.
; Returns JSON: [{"name":"...","formId":123,"pkgFormId":456},...]
String Function ScanActorsWithPackages(Int[] packageFormIDs) Global Native

; The same scan, returning the actors themselves (for Core.SweepStalePackages).
Actor[] Function GetActorsWithPackages(Int[] packageFormIDs) Global Native


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

; Re-populate a quest chest on cell-load. Fixes the "first-open invisible" quirk
; for chests created via PlaceObjectAtMe in unloaded cells — script-added items
; don't sync to the inventory UI until the chest is first initialized.
Bool Function EnsureQuestItemInChest(ObjectReference container, String itemName) Global Native

; Record that a quest item was used (for rotation — avoids repeats).
Function NotifyQuestItemUsed(String itemName) Global Native

; Record that an NPC was used as a rescue victim (for rotation — avoids repeats).
Function NotifyRescueVictimUsed(String victimName) Global Native

; Record that a quest location was used (for rotation — avoids repeats).
Function NotifyQuestLocationUsed(String locationName) Global Native

; Push active quest state to C++ for SkyrimNet decorator exposure.
Function NotifyQuestActive(String locationName, String subType, String enemyType, String giverName, String briefing, String victimName, String itemName, String alliedFaction) Global Native

; Clear quest state when quest completes, fails, or expires.
Function NotifyQuestCleared() Global Native

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
; Encode the complete result once before StorageUtil.SetStringValue.
String Function RenderFactsSection(String[] facts, Float[] factTimes, Float currentGameDays) Global Native

; Pre-render gossip heard section (first person). Returns "## Rumors I've Heard\n..."
String Function RenderGossipHeardSection(String[] rumors, String[] sources, Float[] times, Float currentGameDays) Global Native

; Pre-render gossip told section (first person). Returns "## Rumors I've Shared\n..."
String Function RenderGossipToldSection(String[] rumors, String[] recipients, Float[] times, Float currentGameDays) Global Native

; Pre-render task history section (first person). Returns "### Past Tasks\nWhat I've done:\n..."
String Function RenderTaskHistorySection(String[] descs, Float[] times, Float currentGameDays) Global Native

; Lossless rendered-cache storage encoding; join gossip before calling once.
; Cached prompt readers reverse control tokens, then %25 LAST. Fresh games only.
String Function EncodeRenderedCache(String text) Global Native

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

; Lets a pad answer a Magelight view made from Papyrus (the choice popup): A is Enter, B is Escape, the d-pad and
; the left stick are the arrow keys. 1 = done, 0 = no gamepad layer (no Magelight 1.6+, VR, switched off), -1 = refused.
Int Function EnableMagelightGamepadKeys(Int view) Global Native

; Is this NPC saying a line right now? False for an unloaded actor.
Bool Function IsActorTalking(Actor akActor) Global Native

; Has SkyrimNet a generated line of this NPC queued, being synthesized or playing? Known from SkyrimNet's
; speech events, so it is also true in the seconds before the voice starts. Always false when SkyrimNet sends
; no such events (outbound mod events switched off, or an old version): use IsActorTalking beside it.
Bool Function IsNPCSpeechPending(Actor akActor) Global Native

; Seconds since this NPC's last generated line stopped playing; -1 when none was heard since the game loaded.
Float Function GetSecondsSinceNPCSpoke(Actor akActor) Global Native

; Seconds since the player last said a line (typed, spoken, or picked in the game's own dialogue menu), as
; SkyrimNet reports it; -1 when none since the game loaded. SkyrimNet names no addressee for a typed or spoken
; line, so this is one time for everybody.
Float Function GetSecondsSincePlayerSpoke() Global Native

; Version of SkyrimNet's package contract; 0 when SkyrimNet has none. SkyrimNetApi.ListPackage, HoldPackages,
; ReleaseHeldPackages and UnregisterPackageEx may only be called when this is 1 or more.
Int Function GetSkyrimNetPackageApiVersion() Global Native

; The gameplay settings are shared with SkyrimNet's plugin settings page through
; config/plugins/IntelEngine/settings.yaml. configJson is Core.BuildConfigJson().
; SyncPluginSettings: the game's values go into the file where they differ; returns how many were written.
Int Function SyncPluginSettings(String configJson) Global Native
; ApplyPluginSettings: the file's values go into the game where they differ (as IntelEngine_DashboardSetting
; and IntelEngine_DashboardToggleStory events); values the file lacks are filled in from the game. Returns
; how many settings change.
Int Function ApplyPluginSettings(String configJson) Global Native


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
; 4.0: a faction that holds the player for an enemy sends men after them now and then. Asked at a moment the director
; lets land: the faction and how many, as the dungeon master used to answer ({"ambushFaction":..,"ambushCount":..}),
; or "". FactionPatrolSent: one went out (the rest between two starts, the director's budget is charged).
String Function FactionPatrolDue() Global Native
Function FactionPatrolSent() Global Native
Function FactionPatrolTest(Bool always) Global Native
; Why nobody in arms would come upon the player now (a scene, a talk, resting, undressed, settled); "" when they may.
String Function PrivateMomentNow() Global Native
; How often the dungeon master looks by the clock above Classic (game hours): the director's smallest gap between
; two moments. At Classic the setting "Check interval" is the clock (Core.GetStoryClockHours).
Float Function LivingWorldClockHours() Global Native
; Places nobody is sent to (another plane or land, and above Classic a dungeon). PlaceBarsArrival: would this person,
; arriving unseen at akDest, be set down beside a player who is in such a place? 0 no, 1 a dungeon (a story's visitor
; is not set down there), 2 beyond reach (nobody is). PlaceBarsNow: the reason for where the player is now, or "".
Int Function PlaceBarsArrival(Actor akWho, ObjectReference akDest) Global Native
String Function PlaceBarsNow() Global Native

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

; Async Political DM tick. Captures faction-leader engine state on the main thread,
; then runs all DB queries + JSON build on a worker thread. Callback fires with the
; prepared political context JSON ("{}" if no eligible context).
; Callback signature: Function <callbackFunction>(String contextJson)
Function BeginAsyncPoliticalTick(Float currentGameTime, Quest callbackQuest, String callbackScript, String callbackFunction) Global Native

; Build compact political dashboard JSON for PrismaUI
String Function BuildPoliticalDashboardJson() Global Native

; The dashboard's World page: {rumors, stories, quests, asks, people} as JSON (the talk of the day, what the player
; has taken on, what people have asked of them, those who follow them or once did).
String Function BuildWorldDashboardJson() Global Native

; Record a political event between factions, returns event ID (-1 on failure)
Int Function RecordPoliticalEvent(String factionA, String factionB, String eventType, String description, Int delta, Float gameTime) Global Native
; Return political events after an ID with feed identity and pagination metadata.
String Function GetPoliticalEventsAfter(Int afterId, Int limit = 50) Global Native
; Return configured political factions as JSON.
String Function GetFactionsJson() Global Native


; Check if a political event should physically manifest near the player.
; Returns JSON spawn instructions or empty string if player is not at the event location.
String Function CheckEventManifestation(String factionA, String factionB, String eventType) Global Native

; Confirm manifestation cooldown after Papyrus verified actors spawned successfully.
Function ConfirmManifestationCooldown() Global Native

; Reset manifestation cooldown (director override — allows repeated testing).
Function ResetManifestationCooldown() Global Native

; An attempt on a leader's life: a leader of the target faction near the player (not a follower, a child or somebody
; in a scene), and a killer who comes from where the player does not see them appear: beyond a door of the room, or
; out of sight out of doors. In no faction, starting nothing until the blow. Returns the killer (None: not here, not
; now; the event is then told as written, see ManifestationFailed). Out of doors they are made switched off.
Actor Function ExecuteAssassination(String targetFaction, String attackerFaction) Global Native

; An event that was to be seen (held back by the DLL until then) could not be shown: recorded and told as written.
Function ManifestationFailed() Global Native

; It was shown and has recorded itself (a skirmish does, like a battle): nothing more to record.
Function ManifestationDone() Global Native

; How an attempt on a leader's life ended, as it was seen: "foiled" (the player killed the killer before the blow),
; "saved" (after it), "failed" (somebody else did), "killed" (the leader is dead), "slain_by_player", "escaped".
; Records it, tells it, moves the player's standing. Returns JSON: {notification, thanks, reward, targetFact, witnessFact}
String Function AssassinationOutcome(String targetFaction, String attackerFaction, String leaderName, String outcome) Global Native

; The active battle is a skirmish: size a side (2 to 6), nobody held back. To be said before the lines are drawn up.
Function BattleSetSkirmish(Int size) Global Native

; A side's hidden force: count soldiers made out to one side of the other side's line, out of the player's sight.
; first: their number in the group (0 picks where they break cover). Returns JSON: {success, count, formIds, error}
String Function BattleFlankLine(String side, Int first, Int count, Actor player) Global Native

; A side's champion, made behind their own line out of the player's sight (once a battle).
; Returns JSON: {success, count, formIds, champion: [id], error}
String Function BattleChampionLine(String side, Actor player) Global Native

; Some of one side's living turn their coats: from now on they count, live and die for the other side. The script
; changes their battle side and sets them on their old comrades. Returns JSON: {count, formIds}
String Function BattleTurnCoats(String side) Global Native

; Test hook: what the active battle has in store, said outright (champion: 0 none, 1 side A, 2 side B, 3 both;
; flank and turncoat: 0, 1 or 2).
Function BattleSetTwists(Int champion, Int flank, Int turncoat) Global Native

; The ladder: the rank a faction honours the player with now (0 to 5; none while it takes them for an enemy), and
; what that rank is called with it ("Veteran", "Trusted Hand"; "" for none).
Int Function PlayerFactionRank(String factionId) Global Native
String Function PlayerRankTitle(String factionId) Global Native

; Something done for a faction outside a battle: "quest" (a thing done at its asking), "saved" (a leader's life).
; Returns the name of the rank it lifted the player to, or "".
String Function PlayerDidFor(String factionId, String deed) Global Native

; Armies are drawn up or fighting, or a battle has only just ended (its dead on the field, its survivors walking
; off): nobody comes up to the player with a story of their own.
Bool Function BattleFieldBusy() Global Native

; Where a band that comes for the player themselves can come from: out of doors, not in or by a town or a house,
; from a spot the player does not see and that can be walked from. Returns JSON: {ok, x, y, z, reason}
String Function BattlePickAmbush(Actor player) Global Native

; Get the assassination target (leader) set by ExecuteAssassination.
Actor Function GetAssassinationTarget() Global Native

; Get the assassination leader's name set by ExecuteAssassination.
String Function GetAssassinationLeaderName() Global Native

; Trigger the attack phase: set aggression 2 + combat target on all tracked assassins.
Function TriggerAssassinationAttack() Global Native

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

; Sync vanilla faction membership with political standing.
; If player is in a vanilla faction but has 0 standing, grants 40 (friendly threshold).
Int Function SyncVanillaFactionStandings() Global Native

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
Bool Function GetPEIntegration() Global Native
Function SetPEIntegration(Bool enabled) Global Native
Bool Function GetPEReactionsMoveRelations() Global Native
Function SetPEReactionsMoveRelations(Bool enabled) Global Native
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

; Get the Skyrim engine faction (e.g., CWSonsFaction) for a political faction ID. Returns None if not configured.
Faction Function GetSkyrimFaction(String factionId) Global Native

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

; Where the two armies of the active battle can be drawn up near the player: never where the player stands, never
; where people live or stand about, on ground that is there, dry and not across a cliff. place: what the battle is
; named after (may be None). The field found is remembered for the battle.
; Returns JSON: {ok, x, y, z, axis, reason}
String Function BattlePickField(Actor player, ObjectReference place) Global Native

; Part of one army of the active battle drawn up on its field ("A" or "B"): soldiers first to first + count - 1
; of its first wave, in ranks, the commander (number 0) in front, facing the other line, standing down. Made
; switched off and not yet where they are to stand: BattleSettle, a frame later, does the rest, and then the script
; lets them fade in. One at a time: the game's own making of a soldier costs 0.4 ms of its frame.
; Returns JSON: {success, count, formIds, commander: [id] (with number 0), error}
String Function BattleMusterLine(String side, Int first, Int count, Actor player) Global Native

; The second half of making soldiers (BattleMusterLine, BattleReinforceLine, BattleFlankLine, BattleChampionLine, the
; killer of ExecuteAssassination), to be called a frame after the first: everybody made and not yet settled is set
; down where they are to stand, loses the factions they came with and gets their side and their orders. Nobody is
; switched on before this.
; Returns "" when all were settled, else JSON {count, formIds} of those who could not be (the battle ended in
; between, or their ground is no longer loaded): they were never seen, and the script deletes them.
String Function BattleSettle() Global Native

; Before a group comes up (kind 0 a wave: BattleReinforceLine; 1 the hidden force: BattleFlankLine; 2 a champion:
; BattleChampionLine; 3 a line of the muster: BattleMusterLine): where they come from, out of the player's sight, and
; who they are, chosen in a frame of its own. The making of the first of them follows a frame later.
; 1 chosen; 0 nowhere to come from unseen, or nobody to come; -1 no battle with a field.
Int Function BattlePrepareGroup(String side, Int kind, Actor player) Global Native

; count more soldiers for one side, created behind their own line where the player is least likely to see it,
; switched off. first: their number in the group that comes up together (0 picks where the group comes from).
; Returns JSON: {success, count, formIds, error}
String Function BattleReinforceLine(String side, Int first, Int count, Actor player) Global Native

; The lines have met: from now on the battle can be won and lost.
Function BattleBeginFight() Global Native

; Who has the better of a battle that is not fought out. Returns JSON: {result, victor} ("draw" and "" for nobody).
String Function BattleVerdict() Global Native

; Soldiers who stand about while the battle is on, each with the enemy nearest to them (at most `most`): JSON
; {count, idle: [ids], foe: [ids]}. Not those who keep by the player.
String Function BattleIdleHands(Int most) Global Native

; A side called the player to its line and was turned down or not answered.
Function BattleNoteTurnedDown(String factionId) Global Native

; The player walked away from a battle they had taken a side in.
Function BattleNotePlayerLeft() Global Native

; The gathering of armies one of whose sides calls the player (they hold a rank with it; of two, the one they stand
; higher with). Returns JSON: {id, faction, place, location: [id], marker: [id]}, "{}" when nobody calls.
String Function BattleCall() Global Native

; Where an army goes when its battle is over: the marker of a town to march toward by the roads (its home if that is far
; enough, else the nearest town; the beaten never through the army that beat them). x, y: where it was fought; dirX,
; dirY: from the other army toward this one; notTo: the town the other army goes to. None: no town to march to.
ObjectReference Function BattleWayHome(String factionId, Float x, Float y, Float dirX, Float dirY, Bool beaten, ObjectReference notTo) Global Native

; While the field of a battle the player fought in empties: what they have come to owe a hold for violent crime since
; they took a side is struck out again (a battle is no crime; older debts stay). During the fight the poll does it.
Function BattleTendBounty() Global Native

; Says the call's objective in the journal ("Stand with the Imperial Legion near Rorikstead ..."). Not kept by the
; game: said again after a load.
Function BattleCallText(String factionId, String place) Global Native

; The field of the active battle. Returns JSON: {set, x, y, z, axis, mustering, commanderA: [id], commanderB: [id]}
String Function BattleFieldInfo() Global Native

; Each army brings up its own reserves when it is the one that needs them. side: "A" or "B".
Int Function GetBattleWaveOf(String side) Global Native
Function AdvanceBattleWaveOf(String side) Global Native

; A sentence of a battle, whole: what the player reads (drawn_up, broke_out, stand_with, captain_fell, word_won,
; word_nobody, more_come, last_come, choice_body, choice_join, choice_out, commander_name, champion_name,
; champion_comes, champion_fell, flank, treachery, promoted, file, word_body, word_charge, word_hold, skirmish_met,
; ambush, stranger) or what somebody is given to say in their own words (hail, cry, champion_cry, turncoat_cry,
; after_won, after_drawn, after_lost). a, b: faction ids; name: someone's or some place's name.
; Whole, and made in the DLL, because the game keeps one spelling for all strings that differ only in capitals:
; "the Imperial Legion" put together in a script came out as "The Imperial Legion" in the middle of a sentence.
String Function BattleSay(String what, String a = "", String b = "", String name = "", Int number = 0, Int other = 0) Global Native

; Get FormIDs of soldiers on a given side ("A" or "B"). Returns JSON: {formIds: [...], count, alive}
String Function GetBattleSoldierFormIds(String side) Global Native

; Set all alive soldiers on a side as player teammates (C++ — bypasses FormID overflow).
Function SetBattleSoldiersAsTeammates(String side) Global Native

; Count dead soldiers on a given side ("A" or "B").
Int Function CountDeadBattleSoldiers(String side) Global Native

; The fighting is called off for count of the battle's soldiers from number first on: they start nothing any more,
; forget who struck them, and their fight ends. amongThemselves: only those whose fight is with another soldier of the
; battle. A few a call (no frame carries all of them). Returns how many soldiers come after these.
Int Function BattleCeaseFire(Int first, Int count, Bool amongThemselves) Global Native

; Test hook: where the battle's dead lie and who is held in a killing blow, into IntelEngine.log.
Function BattleDebugBodies() Global Native

; Cleanup battle soldiers by proximity. Returns count of remaining actors.
Int Function CleanupBattleSoldiers(Float playerX, Float playerY, Float playerZ, Float playerAngleZ, Bool forceAll) Global Native

; Force cleanup ALL battle soldiers (hard timeout).
Function ForceCleanupAllSoldiers() Global Native

; Drops the DLL's list of soldiers left to clean up without touching them. The battle script removes the
; soldiers itself when a battle is over (it never removes one the player is looking at).
Function ForgetBattleSoldiers() Global Native

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
String Function FriendlyKey(String key) Global Native
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
