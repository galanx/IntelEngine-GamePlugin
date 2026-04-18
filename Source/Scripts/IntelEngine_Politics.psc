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
    ; Politics does not own a timer. Ticking is driven by StoryEngine.TickScheduler
    ; which calls Politics.TickNow() alongside Story DM and NPC DM. This way the
    ; idle-poll backup that drives those two systems also drives Politics.
    If !Initialized || !IntelEngine.IsPoliticsEnabled()
        return
    EndIf
    Core.DebugMsg("Politics: Scheduler ready (driven by StoryEngine TickScheduler)")
EndFunction

Function StopScheduler()
    ; No-op — Politics self-gates via elapsed time in TickNow.
    Core.DebugMsg("Politics: Scheduler stopped (self-gate will skip ticks)")
EndFunction

; Evaluate whether a politics tick should fire and run it if due.
; Called from StoryEngine.TickScheduler on every scheduler poll. Self-gates
; on the configured politics interval so it's safe to call at any cadence.
Function TickNow()
    If !Initialized || !IntelEngine.IsPoliticsEnabled()
        return
    EndIf

    Float currentTime = Utility.GetCurrentGameTime()

    If TickPending
        ; C++ watchdog: DLL loads fresh every time, so it knows if the pending flag
        ; is stale (from a previous session or lost callback). 1h timeout.
        If IntelEngine.ShouldResetPending("politics", 1.0, currentTime)
            Core.DebugMsg("Politics: watchdog reset TickPending (stuck or stale)")
            TickPending = false
        Else
            return
        EndIf
    EndIf

    Float intervalHours = IntelEngine.GetPoliticsTickInterval() as Float
    Float elapsed = (currentTime - LastTickGameTime) * 24.0  ; days to hours

    If elapsed >= intervalHours
        Core.DebugMsg("Politics: interval reached (" + elapsed + "h >= " + intervalHours + "h) — ticking")
        RunPoliticalTick(currentTime)
    EndIf
EndFunction

; =============================================================================
; POLITICAL TICK — CORE LOOP
; =============================================================================

Function RunPoliticalTick(Float currentGameTime)
    TickPending = true
    IntelEngine.MarkSystemPending("politics", currentGameTime)
    LastTickGameTime = currentGameTime

    ; Process active wars first (morale decay, surrender checks) — fast, stays inline
    ProcessActiveWars(currentGameTime)

    ; Async path: snapshot leader/player state on main thread (fast),
    ; build the political DM context JSON on a worker thread, then fire
    ; OnPoliticsDMContextReady which dispatches the LLM call.
    ; Eliminates main-thread stutter from the political context build.
    IntelEngine.BeginAsyncPoliticalTick(currentGameTime, Self, "IntelEngine_Politics", "OnPoliticsDMContextReady")
EndFunction

Function OnPoliticsDMContextReady(String contextJson)
    If contextJson == "" || contextJson == "{}"
        Core.DebugMsg("Politics: Empty context, skipping tick")
        TickPending = false
        IntelEngine.ClearSystemPending("politics")
        return
    EndIf

    Core.DebugMsg("Politics: Sending DM request (async)")
    Int result = SkyrimNetApi.SendCustomPromptToLLM("intel_political_dm", \
        "intel_story_dm", contextJson, Self, "IntelEngine_Politics", "OnPoliticalDMResponse")

    If result < 0
        Core.DebugMsg("Politics: LLM call failed, code " + result)
        TickPending = false
        IntelEngine.ClearSystemPending("politics")
    EndIf
EndFunction

; =============================================================================
; DM RESPONSE HANDLER
; =============================================================================

Function OnPoliticalDMResponse(String response, Int success)
    TickPending = false
    IntelEngine.ClearSystemPending("politics")

    ; C++ handles ALL logic: parsing, validation, event recording, war/surrender/battle,
    ; standings, decay, crime checks. Returns JSON with Papyrus-only actions.
    String resultJson = IntelEngine.ProcessPoliticalDMResponse(response, success)

    String actedStr = IntelEngine.StoryResponseGetField(resultJson, "acted")
    Bool acted = actedStr == "true" || actedStr == "TRUE"
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
    Core.DebugMsg("Politics: manifest len=" + StringUtil.GetLength(manifestJson) + " Battle=" + (Battle != None))
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
