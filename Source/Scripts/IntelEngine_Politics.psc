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

        ; Handle war declaration
        If eventType == "war_declaration"
            HandleWarDeclaration(factionA, factionB, description, gameTime)
        EndIf

        ; Handle surrender — DM generated a surrender event for an active war
        If eventType == "surrender"
            HandleSurrender(factionA, factionB, description, gameTime)
        EndIf

        ; Handle off-screen battle result from DM
        If eventType == "battle_result"
            HandleBattleResult(response, factionA, factionB, description, gameTime)
        EndIf

        ; Handle DM scheduling a player-present battle
        If eventType == "battle_scheduled"
            HandleBattleScheduled(factionA, factionB, gameTime)
        EndIf

        ; Check if this witnessable event should physically manifest near the player
        If eventType == "assassination_attempt" || eventType == "brawl" || \
           eventType == "border_skirmish"
            String manifestJson = IntelEngine.CheckEventManifestation(factionA, factionB, eventType)
            If manifestJson != ""
                If Battle
                    Battle.ManifestEvent(manifestJson)
                EndIf
            EndIf
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
; WAR LIFECYCLE
; =============================================================================

Function HandleWarDeclaration(String factionA, String factionB, String description, Float gameTime)
    Int warId = IntelEngine.DeclareWar(factionA, factionB, gameTime)

    If warId >= 0
        Core.DebugMsg("Politics: WAR #" + warId + " DECLARED — " + factionA + " vs " + factionB)
        ; NPC awareness: political_state.json (pull-based) + bio facts (push-based on leaders)
        ; Players discover wars through NPC conversations + dashboard notifications
    Else
        Core.DebugMsg("Politics: War declaration blocked (cooldown/max wars/already active)")
    EndIf
EndFunction

Function HandleSurrender(String factionA, String factionB, String description, Float gameTime)
    ; The DM generates surrender events — faction_a is the surrendering faction
    ; faction_b is the victor
    Bool ended = IntelEngine.EndFactionWar(factionA, factionB, factionB, gameTime)

    If ended
        Core.DebugMsg("Politics: WAR ENDED — " + factionA + " surrendered to " + factionB)
    Else
        Core.DebugMsg("Politics: Surrender event but no active war found between " + factionA + " and " + factionB)
    EndIf
EndFunction

Function HandleBattleResult(String response, String factionA, String factionB, String description, Float gameTime)
    ; Parse battle location from DM response
    String battleLoc = IntelEngine.StoryResponseGetField(response, "battle_location")
    If battleLoc == ""
        battleLoc = "the field"
    EndIf

    ; Create a pending battle at the named location's real world coordinates.
    ; If the player travels there within 3 game hours, soldiers spawn.
    ; Otherwise it auto-resolves off-screen when the deadline expires.
    Int pendingId = IntelEngine.AddPendingBattle(battleLoc, factionA, factionB, response)

    If pendingId >= 0
        ; START notification — player sees battle beginning
        String nameA = IntelEngine.GetFactionDisplayName(factionA)
        String nameB = IntelEngine.GetFactionDisplayName(factionB)
        Debug.Notification(nameA + " forces engage " + nameB + " at " + battleLoc + "!")

        ; Start polling for player proximity (Battle script checks every 3s)
        If Battle
            Battle.StartPendingBattlePoll()
        EndIf

        Core.DebugMsg("Politics: Pending battle #" + pendingId + " created at " + battleLoc + " — " + factionA + " vs " + factionB)
    Else
        ; Location couldn't be resolved — fall back to immediate off-screen resolution
        Core.DebugMsg("Politics: Could not resolve location '" + battleLoc + "' — recording off-screen")
        String battleResult = IntelEngine.StoryResponseGetField(response, "battle_result")
        String victor = IntelEngine.StoryResponseGetField(response, "battle_victor")
        Int lossesA = IntelEngine.StoryResponseGetField(response, "attacker_losses") as Int
        Int lossesB = IntelEngine.StoryResponseGetField(response, "defender_losses") as Int

        If battleResult == ""
            battleResult = "draw"
        EndIf
        If lossesA < 0
            lossesA = 0
        ElseIf lossesA > 30
            lossesA = 30
        EndIf
        If lossesB < 0
            lossesB = 0
        ElseIf lossesB > 30
            lossesB = 30
        EndIf

        IntelEngine.RecordOffScreenBattle(factionA, factionB, battleLoc, battleResult, description, lossesA, lossesB, victor)
    EndIf
EndFunction

Function HandleBattleScheduled(String factionA, String factionB, Float gameTime)
    ; Find the active war ID for this faction pair
    ; Schedule battle 6-12 game hours from now
    Float delay = Utility.RandomFloat(6.0, 12.0) / 24.0  ; convert hours to game days
    Float battleTime = gameTime + delay

    If Battle
        Int warId = IntelEngine.GetActiveWarId(factionA, factionB)
        Battle.ScheduleBattle(factionA, factionB, warId, battleTime)
        Core.DebugMsg("Politics: Battle scheduled — " + factionA + " vs " + factionB + " in " + (delay * 24.0) + "h")
    Else
        Core.DebugMsg("Politics: Battle property not set — cannot schedule")
    EndIf
EndFunction

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
