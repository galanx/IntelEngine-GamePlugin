Scriptname IntelEngine_Politics extends Quest

; =============================================================================
; FACTION POLITICS ENGINE
;
; Autonomous political system running on a game-time timer. Every N hours,
; the Political DM evaluates faction relations and generates ONE political
; event that shifts the balance of power.
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
    If !Initialized || !IntelEngine.IsPoliticsEnabled()
        return
    EndIf

    Float intervalHours = IntelEngine.GetPoliticsTickInterval() as Float
    RegisterForSingleUpdateGameTime(intervalHours)
    Core.DebugMsg("Politics: Scheduled next tick in " + intervalHours + " game hours")
EndFunction

Function StopScheduler()
    UnregisterForUpdateGameTime()
    Core.DebugMsg("Politics: Scheduler stopped")
EndFunction

Event OnUpdateGameTime()
    If !Initialized || !IntelEngine.IsPoliticsEnabled()
        return
    EndIf

    If TickPending
        ; Previous tick still processing, skip
        StartScheduler()
        return
    EndIf

    Float currentTime = Utility.GetCurrentGameTime()
    Float intervalHours = IntelEngine.GetPoliticsTickInterval() as Float
    Float elapsed = (currentTime - LastTickGameTime) * 24.0  ; days to hours

    If elapsed >= intervalHours
        RunPoliticalTick(currentTime)
    EndIf

    StartScheduler()
EndEvent

; =============================================================================
; POLITICAL TICK — CORE LOOP
; =============================================================================

Function RunPoliticalTick(Float currentGameTime)
    TickPending = true
    LastTickGameTime = currentGameTime

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
        "intel_political_dm", contextJson, Self, "IntelEngine_Politics", "OnPoliticalDMResponse")

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

    If success != 1 || response == ""
        Core.DebugMsg("Politics: DM response failed or empty")
        return
    EndIf

    ; Parse response JSON
    Bool shouldAct = IntelEngine.StoryResponseShouldAct(response)
    If !shouldAct
        Core.DebugMsg("Politics: DM decided no event this tick")
        return
    EndIf

    String factionA = IntelEngine.StoryResponseGetField(response, "faction_a")
    String factionB = IntelEngine.StoryResponseGetField(response, "faction_b")
    String eventType = IntelEngine.StoryResponseGetField(response, "event_type")
    String description = IntelEngine.StoryResponseGetField(response, "description")
    String deltaStr = IntelEngine.StoryResponseGetField(response, "relation_delta")
    String instigator = IntelEngine.StoryResponseGetField(response, "instigator_npc")

    If factionA == "" || eventType == ""
        Core.DebugMsg("Politics: Invalid DM response — missing faction_a or event_type")
        return
    EndIf

    Int delta = deltaStr as Int
    Float gameTime = Utility.GetCurrentGameTime()

    ; Record event in IntelEngine.db and apply relation delta
    Int eventId = IntelEngine.RecordPoliticalEvent(factionA, factionB, eventType, description, delta, gameTime)

    If eventId >= 0
        Core.DebugMsg("Politics: Recorded event #" + eventId + " " + eventType + " (" + factionA + " vs " + factionB + ") delta=" + delta)

        ; Inject as SkyrimNet fact so NPCs gossip about it
        If description != ""
            InjectPoliticalFact(factionA, factionB, description)
        EndIf

        ; Check for war threshold crossing
        If eventType == "war_declaration"
            Core.DebugMsg("Politics: WAR DECLARED — " + factionA + " vs " + factionB)
        EndIf
    Else
        Core.DebugMsg("Politics: Failed to record event (validation failed?)")
    EndIf

    ; Apply player standing changes (if the DM included any based on player dialogue)
    Int standingsApplied = IntelEngine.ApplyPlayerStandingChanges(response)
    If standingsApplied > 0
        Core.DebugMsg("Politics: Applied " + standingsApplied + " player standing changes")
    EndIf

    ; Run periodic standing mechanics (crime gold penalties, decay)
    RunStandingMechanics()
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

Function RunStandingMechanics()
    ; Standing decay first — drift toward 0 before applying new penalties
    ; (prevents decay from immediately nullifying small crime penalties)
    Int decayed = IntelEngine.DecayPlayerStandings(1)
    If decayed > 0
        Core.DebugMsg("Politics: Decayed " + decayed + " player standings toward neutral")
    EndIf

    ; Crime gold penalties — checks crime gold against political factions
    Int crimeChanges = IntelEngine.CheckCrimeGoldStandings()
    If crimeChanges > 0
        Core.DebugMsg("Politics: Applied " + crimeChanges + " crime-based standing changes")
    EndIf

    ; Update state file if anything changed
    If decayed > 0 || crimeChanges > 0
        IntelEngine.WritePoliticalStateFile()
    EndIf
EndFunction

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
