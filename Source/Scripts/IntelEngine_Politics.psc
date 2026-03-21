Scriptname IntelEngine_Politics extends Quest

; =============================================================================
; FACTION POLITICS ENGINE
;
; Autonomous political system running on a game-time timer. Every N hours,
; the Political DM evaluates faction relations and generates ONE political
; event that shifts the balance of power.
;
; Phase 2: Wars can be declared when relations cross thresholds.
; Active wars have morale decay per tick and end via surrender (morale < 20).
; Off-screen battles are resolved by the DM.
;
; Consequences dispatch through the Story Engine (political_informant type)
; and NPC dialogue awareness via SkyrimNet's memory injection.
;
; Single source of truth: IntelEngine.db (managed by C++ PoliticalDB)
; Config: factions.yaml + settings.yaml (politics section)
; =============================================================================

; === Properties (set in CK or via Core) ===
IntelEngine_Core Property Core Auto
IntelEngine_StoryEngine Property StoryEngine Auto
IntelEngine_Battle Property Battle Auto

; === State ===
Float Property LastTickGameTime = 0.0 Auto Hidden
Bool Property TickPending = false Auto Hidden
Bool Property Initialized = false Auto Hidden

; =============================================================================
; INITIALIZATION
; =============================================================================

Function Initialize()
    If !IntelEngine.IsPoliticsEnabled()
        Core.DebugMsg("Politics: Disabled in settings")
        return
    EndIf

    LastTickGameTime = Utility.GetCurrentGameTime()
    Initialized = true
    StartScheduler()
    Core.DebugMsg("Politics: Initialized, first tick in " + IntelEngine.GetPoliticsTickInterval() + "h")
EndFunction

; =============================================================================
; TIMER MANAGEMENT
; =============================================================================

Function StartScheduler()
    ; Politics NO LONGER registers its own game-time timer.
    ; All scripts share the same quest — RegisterForSingleUpdateGameTime is per-quest.
    ; StoryEngine owns the shared timer and uses the shortest interval across all systems.
    ; Politics is ticked via OnUpdateGameTime (which fires for ALL scripts on the quest).
    If !Initialized || !IntelEngine.IsPoliticsEnabled()
        return
    EndIf
    Core.DebugMsg("Politics: Scheduler ready (driven by shared quest timer)")
EndFunction

Function StopScheduler()
    ; No-op — StoryEngine owns the timer. Politics self-gates via elapsed time.
    Core.DebugMsg("Politics: Scheduler stopped (self-gate will skip ticks)")
EndFunction

Event OnUpdateGameTime()
    ; Shared quest timer fires for all scripts. Politics self-gates via elapsed time.
    If !Initialized || !IntelEngine.IsPoliticsEnabled()
        return
    EndIf

    If TickPending
        return
    EndIf

    Float currentTime = Utility.GetCurrentGameTime()
    Float intervalHours = IntelEngine.GetPoliticsTickInterval() as Float
    Float elapsed = (currentTime - LastTickGameTime) * 24.0  ; days to hours

    If elapsed >= intervalHours
        RunPoliticalTick(currentTime)
    EndIf
    ; Do NOT call StartScheduler/RegisterForSingleUpdateGameTime here —
    ; StoryEngine owns the shared timer and will re-register it.
EndEvent

; =============================================================================
; POLITICAL TICK — CORE LOOP
; =============================================================================

Function RunPoliticalTick(Float currentGameTime)
    TickPending = true
    LastTickGameTime = currentGameTime

    ; Process active wars first (morale decay, surrender checks)
    ProcessActiveWars(currentGameTime)

    ; Build context in C++ (reads factions.yaml + IntelEngine.db)
    String contextJson = IntelEngine.BuildPoliticalContext(currentGameTime)

    If contextJson == "{}"
        Core.DebugMsg("Politics: Empty context, skipping tick")
        TickPending = false
        return
    EndIf

    ; Send to LLM via SkyrimNet
    Core.DebugMsg("Politics: Sending DM request")
    Int result = SkyrimNetApi.SendCustomPromptToLLM("intel_political_dm", \
        "intel_story_dm", contextJson, Self, "IntelEngine_Politics", "OnPoliticalDMResponse")

    If result < 0
        Core.DebugMsg("Politics: LLM call failed, code " + result)
        TickPending = false
    EndIf
EndFunction

; =============================================================================
; DM RESPONSE HANDLER
; =============================================================================

Function OnPoliticalDMResponse(String response, Int success)
    TickPending = false

    ; C++ handles ALL logic: parsing, validation, event recording, war/surrender/battle,
    ; standings, decay, crime checks. Returns JSON with Papyrus-only actions.
    String resultJson = IntelEngine.ProcessPoliticalDMResponse(response, success)

    Bool acted = IntelEngine.StoryResponseGetField(resultJson, "acted") == "true"
    If !acted
        return
    EndIf

    String description = IntelEngine.StoryResponseGetField(resultJson, "description")
    String factionA = IntelEngine.StoryResponseGetField(resultJson, "factionA")
    String factionB = IntelEngine.StoryResponseGetField(resultJson, "factionB")
    String eventType = IntelEngine.StoryResponseGetField(resultJson, "eventType")

    Core.DebugMsg("Politics: Event " + eventType + " (" + factionA + " vs " + factionB + ")")

    ; Papyrus-only: inject facts into loaded leaders (requires Actor handles for SkyrimNet API)
    If description != ""
        InjectPoliticalFact(factionA, factionB, description)
    EndIf

    ; Papyrus-only: battle notifications + pending poll start (requires engine operations)
    String notification = IntelEngine.StoryResponseGetField(resultJson, "notification")
    If notification != ""
        Debug.Notification(notification)
    EndIf

    ; Start pending battle polling if a pending battle was created
    If IntelEngine.StoryResponseGetField(resultJson, "startPendingPoll") == "true"
        If Battle
            Battle.StartPendingBattlePoll()
        EndIf
    EndIf

    ; Schedule a player-present battle if the DM requested one
    If IntelEngine.StoryResponseGetField(resultJson, "scheduleBattle") == "true"
        If Battle
            String sFactionA = IntelEngine.StoryResponseGetField(resultJson, "scheduleFactionA")
            String sFactionB = IntelEngine.StoryResponseGetField(resultJson, "scheduleFactionB")
            Int sWarId = IntelEngine.StoryResponseGetField(resultJson, "scheduleWarId") as Int
            Float sBattleTime = IntelEngine.StoryResponseGetField(resultJson, "scheduleBattleTime") as Float
            Battle.ScheduleBattle(sFactionA, sFactionB, sWarId, sBattleTime)
        EndIf
    EndIf

    ; Manifest political event near player if applicable (requires engine spawn operations)
    String manifestJson = IntelEngine.StoryResponseGetField(resultJson, "manifestJson")
    If manifestJson != ""
        If Battle
            Battle.ManifestEvent(manifestJson)
        EndIf
    EndIf
EndFunction

; =============================================================================
; WAR LIFECYCLE
; =============================================================================

; HandleWarDeclaration, HandleSurrender, HandleBattleResult, HandleBattleScheduled
; — ALL moved to C++ ProcessPoliticalDMResponse. No longer needed in Papyrus.

Function ProcessActiveWars(Float currentGameTime)
    Int warCount = IntelEngine.GetActiveWarCount()
    If warCount == 0
        return
    EndIf

    ; C++ handles morale decay and surrender detection for all active wars
    String warUpdatesJson = IntelEngine.ProcessWarTick(currentGameTime)

    If warUpdatesJson == "[]"
        return
    EndIf

    Core.DebugMsg("Politics: Processed " + warCount + " active war(s), morale decay applied")

    ; Parse war updates to detect ended wars and dispatch stories
    ; The JSON is an array of objects with optional "ended" and "victor" fields
    ; We use StoryResponseGetField on each element — but since this is an array,
    ; we handle it at the Papyrus level by checking for "ended" in the string
    If IntelEngine.StringContains(warUpdatesJson, "\"ended\"")
        Core.DebugMsg("Politics: One or more wars ended via morale collapse this tick")
        ; Note: The C++ ProcessWarTick already ended the wars in DB.
        ; Story dispatch for war endings will happen when the DM generates
        ; surrender events naturally, or we can parse the JSON here for
        ; immediate dispatch. For now, the DM will pick up the ended wars
        ; in the next tick's context and generate appropriate narrative.
    EndIf
EndFunction

; =============================================================================
; SKYRIMNET INTEGRATION — NPC AWARENESS
; =============================================================================

Function InjectPoliticalFact(String factionA, String factionB, String description)
    ; Political awareness uses two complementary systems:
    ;
    ; 1. Pull-based (C++): political_state.json written by FactionPolitics::WritePoliticalStateFile()
    ;    after each event. The prompt template (0810_intel_political_awareness.prompt) reads this
    ;    via read_json() at conversation time. Works for ALL NPCs — leaders, soldiers, civilians.
    ;    No UUID issues, no save bloat, zero cost when not in conversation.
    ;
    ; 2. Bio facts (Papyrus): Immediate context for currently-loaded faction leaders.
    ;    Uses Actor reference via StorageUtil — no UUID dependency. Gives leaders
    ;    first-person awareness ("I heard that...") in addition to the pull-based events.

    Int factCount = 0
    Actor[] loadedA = IntelEngine.GetFactionLeaderActors(factionA)
    Int i = 0
    While i < loadedA.Length
        If loadedA[i] != None
            Core.InjectFact(loadedA[i], description)
            factCount += 1
        EndIf
        i += 1
    EndWhile

    If factionB != ""
        Actor[] loadedB = IntelEngine.GetFactionLeaderActors(factionB)
        i = 0
        While i < loadedB.Length
            If loadedB[i] != None
                Core.InjectFact(loadedB[i], description)
                factCount += 1
            EndIf
            i += 1
        EndWhile
    EndIf

    Core.DebugMsg("Politics: Bio facts injected on " + factCount + " loaded leaders (pull-based awareness via political_state.json handles all NPCs)")
EndFunction

; =============================================================================
; PLAYER STANDING — ACTION HANDLER
; =============================================================================

Function ReportPlayerConduct(Actor akNPC, String factionId, String sentiment, String reason)
    ; Delegates to C++ which handles:
    ;   1. Primary standing change (sentiment -> delta)
    ;   2. Cross-faction: if reporter's faction is rival of factionId, inverse delta (halved)
    ;   3. Cross-faction: if reporter's faction is ally of factionId, matching delta (halved)
    Int changed = IntelEngine.ProcessPlayerConduct(akNPC, factionId, sentiment, reason)
    Core.DebugMsg("Politics: ProcessPlayerConduct -> " + changed + " standings changed (" + sentiment + " toward " + factionId + ")")

    ; Update state file so NPCs see the new standing immediately
    If changed > 0
        IntelEngine.WritePoliticalStateFile()
    EndIf
EndFunction

; =============================================================================
; PLAYER STANDING — PERIODIC MECHANICS (called during tick)
; =============================================================================

; RunStandingMechanics — moved to C++ RunStandingMechanicsInternal.
; Now called internally by ProcessPoliticalDMResponse. No longer needed standalone.

; =============================================================================
; PAPYRUS UTILITIES
; =============================================================================

Function Maintenance()
    If !Initialized
        Initialize()
    Else
        StartScheduler()
    EndIf
EndFunction
