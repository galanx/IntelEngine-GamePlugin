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
