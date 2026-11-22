Scriptname IntelEngine_Battle extends Quest

; =============================================================================
; BATTLES
;
; A battle of a war is first a gathering: the political DM names two armies and a place, word of it goes
; round, and for some hours the armies face each other there (a pending battle, kept by the DLL).
;
;   - The player comes near the place, out of doors: the DLL looks for a field (Battlefield.h: never where the
;     player stands, never where people live or stand about, on ground that is there, dry and not across a cliff)
;     and the two lines are drawn up on it, each with its commander in front. They stand.
;   - The player comes up to a line: its commander calls them over, and they choose a side, or none. They can also
;     simply tell a soldier (SkyrimNet action JoinBattle), or strike one.
;   - Then the lines charge. More come up behind each line as it thins. An army breaks when its heart is gone
;     and runs; the winners walk off; the dead stay where they fell for some hours.
;   - One who fought in the winning line is thanked and paid by one of it, in person.
;   - Nobody came: it is decided unseen when its time is up, and told then.
;
; A faction's quest ("come and fight for us at X") begins the same battle when the player gets there.
;
; Requires ESP: Intel_BattleSideA, Intel_BattleSideB factions (hostile to each other).
; Side A is always the battle's first faction, side B the second.
; =============================================================================

; === Properties ===
IntelEngine_Core Property Core Auto
Faction Property Intel_BattleSideA Auto
Faction Property Intel_BattleSideB Auto

; === Settings ===
Int Property MaxSoldiersPerSide = 22 Auto Hidden
Int Property SpawnDistance = 150 Auto Hidden  ; units from center to each side (300 apart = guaranteed LoS)
Float Property BattleSpawnDistance = 600.0 Auto Hidden  ; units ahead of player toward battle location
Float Property PollInterval = 3.0 Auto Hidden  ; seconds between state polls
Float Property CenterSpawnDistance = 500.0 Auto Hidden  ; units ahead of player for battle center
Float Property MidBattleCasualtyRate = 2.0 Auto Hidden  ; game-minutes per casualty during off-screen
Float Property MidBattleMoraleRate = 5.0 Auto Hidden    ; morale loss per game-minute off-screen
Int Property MidBattleMoraleCap = 60 Auto Hidden        ; max morale loss from off-screen time
Int Property MidBattleMinSoldiers = 3 Auto Hidden       ; minimum soldiers per side for mid-battle
Float Property BattleHardTimeout = 1800.0 Auto Hidden   ; seconds — force-end battle if stuck (30 min real time)

; === Standing Tuning ===
Int Property AutoJoinStandingThreshold = 20 Auto Hidden   ; auto-join if standing >= this with ONE side
Int Property SpectatorPenaltyThreshold = 10 Auto Hidden   ; spectator penalty if standing >= this
Int Property SpectatorPenalty = -5 Auto Hidden             ; standing loss per faction for spectating
Int Property VictoryAllyBonus = 15 Auto Hidden             ; standing gain with allied faction on win
Int Property VictoryEnemyPenalty = -10 Auto Hidden         ; standing loss with enemy faction on win
Int Property DefeatAllyBonus = 5 Auto Hidden               ; standing gain with allied faction on loss
Int Property DefeatEnemyPenalty = -5 Auto Hidden           ; standing loss with enemy faction on loss
Int Property KillStandingPenaltyPerSoldier = -2 Auto Hidden  ; standing loss per soldier killed by player

; === Battle State ===
String Property BattleFactionA = "" Auto Hidden
String Property BattleFactionB = "" Auto Hidden
Int Property BattleWarId = 0 Auto Hidden
Float Property ScheduledBattleTime = 0.0 Auto Hidden
Bool Property BattleScheduled = false Auto Hidden
Bool Property BattleSpawned = false Auto Hidden
Int Property ActiveBattleId = -1 Auto Hidden
String Property BattleLocationName = "" Auto Hidden
Float Property ActualBattleStartTime = 0.0 Auto Hidden
Float Property BattleStartRealTime = 0.0 Auto Hidden  ; Utility.GetCurrentRealTime() at spawn
Actor Property BattleLeader Auto Hidden               ; Allied soldier with quest marker + Essential
Bool Property BattleLeaderWasEssential = false Auto Hidden
ObjectReference Property BattleSpawnAnchor Auto Hidden  ; Where to spawn soldiers (quest location marker)

; Spawn anchor markers (placed dynamically, cleaned up after battle)
ObjectReference Property CenterMarker Auto Hidden
ObjectReference Property RallyMarkerA Auto Hidden
ObjectReference Property RallyMarkerB Auto Hidden

; Wave tracking
Int Property CurrentWave = 0 Auto Hidden

; Player participation
String Property PlayerBattleSide = "" Auto Hidden
; The call to the line: the gathering a faction has called the player to (-1: none), whose call it is, where, and
; whether that gathering became a battle.
Int Property CallBattleId = -1 Auto Hidden
String Property CallFaction = "" Auto Hidden
String Property CallPlace = "" Auto Hidden
Bool Property CallFought = false Auto Hidden
; How a call ends in the journal (the stages of IntelEngine_Call).
Int Property CALL_OPEN = 10 AutoReadOnly
Int Property CALL_STOOD = 100 AutoReadOnly       ; stood in the line
Int Property CALL_AGAINST = 150 AutoReadOnly     ; stood with the other side
Int Property CALL_WATCHED = 160 AutoReadOnly     ; came and took no side
Int Property CALL_LEFT = 170 AutoReadOnly        ; stood in the line and walked away
Int Property CALL_MISSED = 200 AutoReadOnly      ; it was decided without the player
Int Property CALL_PARTED = 210 AutoReadOnly      ; the armies parted with nothing decided
String Property QuestAutoJoinFaction = "" Auto Hidden  ; Set by StoryEngine for quest-dispatched battles

; Deferred cleanup state (non-blocking, uses OnUpdate polling)
Bool Property DeferredCleanupActive = false Auto Hidden
Float Property DeferredCleanupStart = 0.0 Auto Hidden

; Pending battle polling
Bool Property PendingPollActive = false Auto Hidden

; The battle on its field
Int Property BattlePhase = 0 Auto Hidden                ; 0: none. 1: the lines are drawn up. 2: they fight.
Float Property MusterStartRealTime = 0.0 Auto Hidden    ; when the lines were drawn up
Float Property MusterSeenRealTime = 0.0 Auto Hidden     ; when the player first came near enough to watch them
Actor Property CommanderA Auto Hidden
Actor Property CommanderB Auto Hidden
Bool Property PlayerWasHailed = false Auto Hidden       ; a commander has called the player over (once a battle)

Float Property MusterPoll = 1.0 AutoReadOnly            ; seconds between looks while the lines stand
Float Property MusterWatched = 45.0 AutoReadOnly        ; the lines stand this long once the player watches, then charge
Float Property MusterLongest = 150.0 AutoReadOnly       ; and this long at most, watched or not
Float Property WatchDistance = 3200.0 AutoReadOnly      ; near enough to the field to watch
Float Property HailDistance = 1500.0 AutoReadOnly       ; near enough to a commander to be called over
Float Property HailInFightDistance = 900.0 AutoReadOnly ; the same once the fighting has begun
Float Property GoneDistance = 9000.0 AutoReadOnly       ; the player has left the field
Float Property GoneSeconds = 25.0 AutoReadOnly          ; for this long: it is decided without them
Float Property BattleLongest = 600.0 AutoReadOnly       ; a fight that is not over by now is called off (3.8: half an hour)
Int Property HostileStanding = -40 AutoReadOnly         ; Battlefield::kHostileStanding
Int Property FriendStanding = 20 AutoReadOnly           ; Battlefield::kFriendStanding

Float _noFieldUntil = 0.0       ; no ground for a pending battle where the player was: not tried again before this
Float _goneSince = 0.0          ; since when the player has been away from the field
Bool _waveBusy = false          ; reinforcements are being brought up (one wave at a time)
Float _noReserveUntilA = 0.0    ; nowhere for side A's reserves to come from unseen: not asked again before this
Float _noReserveUntilB = 0.0
String _flankWaiting = ""       ; the side whose hidden force is to break cover as soon as the wave now coming is up
String _championWaiting = ""    ; the side(s) whose champion is to come up as soon as the wave now coming is up
Bool _fileAssigned = false      ; the player's file of soldiers has been told off (once a battle)
Bool _wordGiven = false         ; the player has been asked for the word to charge (once a battle)
Bool _tending = false           ; the muster is being looked after (the commander's call waits for an answer)
Bool _warnedOff = false         ; a commander has shouted at the player as at an officer of the other army (once a battle)
Bool _endedUnseen = false       ; the battle is decided with the player gone: nothing is announced
String _markedEnemyOf = ""      ; the side that took the player for an enemy in this battle

; A skirmish (a brawl, a border skirmish): a small battle
Bool Property BattleSkirmish = false Auto Hidden
Int Property BattleLineSize = 8 Auto Hidden             ; how many of a side are drawn up

; An attempt on a leader's life
Bool _assassinReported = false          ; how it ended has been recorded and told
String _assassinTargetFaction = ""
String _assassinAttackerFaction = ""
String _assassinLeaderName = ""

; Micro-encounter (political event manifestation) state
Actor[] Property ManifestActors Auto Hidden
Int Property ManifestCount = 0 Auto Hidden
Bool Property ManifestActive = false Auto Hidden
Float Property ManifestStartTime = 0.0 Auto Hidden
Actor Property ManifestLeaderTarget = None Auto Hidden  ; Leader added to BattleSideA during assassination — must be cleaned up
Bool Property ManifestAssassinAttacked = false Auto Hidden  ; true after assassination attack triggers — gates cleanup
Bool Property ManifestAssassinStruck = false Auto Hidden    ; true once the assassin has really been set on the leader (after the pause)
Float Property ManifestAssassinArrivedAt = 0.0 Auto Hidden  ; real time the assassin arrived, to bound the pause before the strike
Float Property ManifestCleanupDelay = 90.0 Auto Hidden  ; real seconds before cleanup

; =============================================================================
; SCHEDULING (called by IntelEngine_Politics)
; =============================================================================

Function ScheduleBattle(String factionA, String factionB, Int warId, Float gameTime)
    {Does nothing any more. An announced battle used to be fought when its hour came on the spot the player stood
    on, wherever that was. It is a gathering at a place now, like every battle of a war (see the top of this file).}
    Core.DebugMsg("Battle: ScheduleBattle is no longer used (" + factionA + " vs " + factionB + ")")
EndFunction

; =============================================================================
; PENDING BATTLE POLLING (called by IntelEngine_Politics when battle_result fires)
; =============================================================================

Function StartPendingBattlePoll()
    If PendingPollActive
        ; Already polling — new pending battle will be picked up by existing loop
        return
    EndIf

    PendingPollActive = true
    Core.RequestTick(PollInterval)
    Core.DebugMsg("Battle: Started pending battle proximity polling")
EndFunction

Function HandlePendingBattleTriggered(Int pendingId)
    {The player has come near a place where two armies are gathered. If there is ground for it they are drawn
    up; if not (the player is among houses, people are about) the gathering stays what it was and is tried again.}
    String infoJson = IntelEngine.GetPendingBattleInfo(pendingId)
    If infoJson == "{}"
        Core.DebugMsg("Battle: Pending battle " + pendingId + " info not found - already expired?")
        return
    EndIf
    String factionA = IntelEngine.StoryResponseGetField(infoJson, "faction_a")
    String factionB = IntelEngine.StoryResponseGetField(infoJson, "faction_b")
    String locName = IntelEngine.StoryResponseGetField(infoJson, "location")
    Int warId = IntelEngine.GetActiveWarId(factionA, factionB)
    If factionA == "" || factionB == "" || warId <= 0
        ; Their war is over: nobody fights.
        Core.DebugMsg("Battle: Pending battle " + pendingId + " is no longer a battle of a war - dropped")
        ; Whoever was called to it finds the armies gone: they parted with nothing decided. (The journal said the
        ; battle had been decided without them, of a battle that was never fought.)
        If CallBattleId == pendingId
            EndCall(CALL_PARTED)
        EndIf
        IntelEngine.RemovePendingBattle(pendingId)
        PendingPollActive = IntelEngine.GetPendingBattleCount() > 0
        return
    EndIf

    Actor player = Game.GetPlayer()
    BattleFactionA = factionA
    BattleFactionB = factionB
    BattleWarId = warId
    BattleLocationName = locName
    BattleSpawnAnchor = IntelEngine.ResolveAnyDestination(player, locName)
    QuestAutoJoinFaction = ""
    BattleSkirmish = false
    BattleLineSize = GetWaveSoldierCount(1)
    If StartBattleSequence()
        If pendingId == CallBattleId
            CallFought = true           ; the battle the player was called to: how the call ends is how they fought it
        ElseIf CallBattleId < 0
            CallAtMuster(pendingId, locName)
        EndIf
        IntelEngine.RemovePendingBattle(pendingId)
        PendingPollActive = IntelEngine.GetPendingBattleCount() > 0
        Core.DebugMsg("Battle: the armies gathered at " + locName + " are drawn up - " + factionA + " vs " + factionB)
    Else
        _noFieldUntil = Utility.GetCurrentRealTime() + 15.0
        ForgetBattleNames()
    EndIf
EndFunction

Quest Function CallQuest()
    Return Quest.GetQuest("IntelEngine_Call")
EndFunction

Function CallAtMuster(Int pendingId, String place)
    {The armies are drawn up near a player who was never called: they were already close by when the armies
    gathered, so the gathering became a battle before anybody sent for them (played 2026-11-21: a Captain of the
    Legion a few fields away, and nothing in the journal). Whoever holds a rank with one of the two is called
    now, by the same rule (the side they stand higher with; equal ranks, neither), and the journal points at
    that side's commander: the one who will hail them.}
    Int rankA = IntelEngine.PlayerFactionRank(BattleFactionA)
    Int rankB = IntelEngine.PlayerFactionRank(BattleFactionB)
    String caller = ""
    Actor commander = None
    If rankA > rankB && rankA >= 1
        caller = BattleFactionA
        commander = CommanderA
    ElseIf rankB > rankA && rankB >= 1
        caller = BattleFactionB
        commander = CommanderB
    EndIf
    Quest jq = CallQuest()
    If caller == "" || commander == None || commander.IsDead() || jq == None
        Return
    EndIf
    If jq.IsRunning()
        jq.Stop()
    EndIf
    jq.Reset()
    If !jq.Start()
        Core.DebugMsg("Battle: the journal entry of the call did not start")
        Return
    EndIf
    CallBattleId = pendingId
    CallFaction = caller
    CallPlace = place
    CallFought = true
    IntelEngine.BattleCallText(CallFaction, CallPlace)
    ReferenceAlias markAlias = jq.GetAlias(0) as ReferenceAlias
    If markAlias != None
        markAlias.ForceRefTo(commander)
    EndIf
    jq.SetStage(CALL_OPEN)
    jq.SetObjectiveDisplayed(0, true, true)
    jq.SetActive(true)
    Core.DebugMsg("Battle: " + CallFaction + " calls the player to its line near " + CallPlace + " (the armies are drawn up already)")
EndFunction

Function TendCall()
    {When armies gather, a faction the player holds a rank with calls its own: a journal entry with the place marked
    (of two such factions the one they stand higher with; equal ranks, neither). The call ends with the battle: stood
    in the line, stood against it, only watched, walked away, or never came.}
    If CallBattleId >= 0
        If !CallFought && !IntelEngine.IsBattleActive() && IntelEngine.GetPendingBattleInfo(CallBattleId) == "{}"
            EndCall(CALL_MISSED)
        EndIf
        Return
    EndIf
    String call = IntelEngine.BattleCall()
    If call == "" || call == "{}"
        Return
    EndIf
    Quest jq = CallQuest()
    ObjectReference mark = Game.GetFormEx(IntelEngine.GetJsonArrayInt(call, "marker", 0)) as ObjectReference
    If jq == None || mark == None
        Return
    EndIf
    If jq.IsRunning()
        jq.Stop()
    EndIf
    jq.Reset()
    If !jq.Start()
        Core.DebugMsg("Battle: the journal entry of the call did not start")
        Return
    EndIf
    CallBattleId = IntelEngine.StoryResponseGetField(call, "id") as Int
    CallFaction = IntelEngine.StoryResponseGetField(call, "faction")
    CallPlace = IntelEngine.StoryResponseGetField(call, "place")
    CallFought = false
    IntelEngine.BattleCallText(CallFaction, CallPlace)
    ReferenceAlias markAlias = jq.GetAlias(0) as ReferenceAlias
    If markAlias != None
        markAlias.ForceRefTo(mark)
    EndIf
    Location place = Game.GetFormEx(IntelEngine.GetJsonArrayInt(call, "location", 0)) as Location
    LocationAlias placeAlias = jq.GetAlias(1) as LocationAlias
    If placeAlias != None && place != None
        placeAlias.ForceLocationTo(place)
    EndIf
    jq.SetStage(CALL_OPEN)
    jq.SetObjectiveDisplayed(0, true, true)
    jq.SetActive(true)
    Core.DebugMsg("Battle: " + CallFaction + " calls the player to its line near " + CallPlace + " (gathering " + CallBattleId + ")")
EndFunction

Function EndCall(Int stage)
    {The call is over: its objective is done or failed and the journal says how it went.}
    Quest jq = CallQuest()
    If jq != None && jq.IsRunning()
        If stage == CALL_STOOD
            jq.SetObjectiveCompleted(0, true)
        Else
            jq.SetObjectiveFailed(0, true)
        EndIf
        jq.SetStage(stage)
    EndIf
    Core.DebugMsg("Battle: the call of " + CallFaction + " is over (" + stage + ")")
    CallBattleId = -1
    CallFaction = ""
    CallPlace = ""
    CallFought = false
EndFunction

Function ForgetBattleNames()
    {A battle that did not begin leaves nothing behind.}
    BattleFactionA = ""
    BattleFactionB = ""
    BattleWarId = 0
    BattleLocationName = ""
    BattleSpawnAnchor = None
    QuestAutoJoinFaction = ""
    ActiveBattleId = -1
    BattleSpawned = false
    BattlePhase = 0
    BattleSkirmish = false
    BattleLineSize = GetWaveSoldierCount(1)
EndFunction

; =============================================================================
; TIMER EVENTS
; =============================================================================

Event OnUpdateGameTime()
    ; (No battle waits for an hour any more: see ScheduleBattle.)
    BattleScheduled = false
EndEvent

Event OnUpdate()
    If _retiredCount > 0
        DeleteRetiredMarkers()
    EndIf
    ; Manifestation cleanup check (micro-encounters from political events)
    If ManifestActive
        Float elapsed = Utility.GetCurrentRealTime() - ManifestStartTime
        Bool combatOver = !IsAnyManifestActorInCombat()

        ; Assassination: don't clean up until attack has actually triggered
        If ManifestLeaderTarget != None && !ManifestAssassinAttacked
            Actor hardAssassin = ManifestActors[0]

            ; The killer is dead before the blow: the cleanup says by whose hand, and tells it
            If hardAssassin == None || hardAssassin.IsDead()
                Core.DebugMsg("Battle: the killer is dead before the blow")
                CleanupManifestation()
                Core.RequestTick(PollInterval)
                return
            EndIf

            ; Hard timeout — force-trigger attack if assassin and leader are nearby
            If elapsed >= ManifestCleanupDelay
                If ManifestLeaderTarget != None && !ManifestLeaderTarget.IsDead()
                    Float distToLeader = hardAssassin.GetDistance(ManifestLeaderTarget)
                    If distToLeader < 3000.0
                        Core.DebugMsg("Battle: Assassination hard timeout - force-attacking (dist=" + distToLeader + ")")
                        ; Put on top of the leader only when the player sees neither of them: otherwise the
                        ; attack starts from where the assassin stands (they run the rest).
                        If !Core.PlayerCanSee(hardAssassin) && !Core.PlayerCanSee(ManifestLeaderTarget)
                            hardAssassin.MoveTo(ManifestLeaderTarget, 0.0, 0.0, 0.0)
                        EndIf
                        Int hardSlot = Core.FindSlotByAgent(hardAssassin)
                        String hardTarget = ManifestLeaderTarget.GetDisplayName()
                        If hardSlot >= 0
                            hardTarget = Core.SlotTargetNames[hardSlot]
                        EndIf
                        HandleAssassinArrival(hardAssassin, hardTarget)
                        ; The attack has just begun (HandleAssassinArrival restarts the manifest clock). Without
                        ; this return the code below went on with the elapsed time measured before it, found
                        ; the time limit passed and cleaned the manifestation up: the assassin was deleted
                        ; in the moment of striking.
                        Core.RequestTick(PollInterval)
                        return
                    Else
                        Core.DebugMsg("Battle: Assassination hard timeout - leader too far, aborting")
                        CleanupManifestation()
                    EndIf
                Else
                    Core.DebugMsg("Battle: Assassination hard timeout - cleaning up")
                    CleanupManifestation()
                EndIf
            Else
                Core.RequestTick(PollInterval)
                return
            EndIf
        EndIf

        ; Assassination, between arriving and striking (HandleAssassinArrival is in its pause). Nobody is
        ; fighting yet and the clock still counts from the spawn, so the cleanup below used to run here
        ; whenever the walk had taken fifteen seconds: it untracked the assassin, and the strike then went
        ; ahead with an attacker nothing removed any more, hostile to everyone in reach.
        If ManifestLeaderTarget != None && ManifestAssassinAttacked && !ManifestAssassinStruck
            Float pending = Utility.GetCurrentRealTime() - ManifestAssassinArrivedAt
            If pending >= 0.0 && pending < 30.0
                Core.RequestTick(PollInterval)
                return
            EndIf
            Core.DebugMsg("Battle: Assassination never struck - cleaning up")
            CleanupManifestation()
            Core.RequestTick(PollInterval)
            return
        EndIf

        ; Assassination under way: the assassin stays on the leader, and stops once it is decided.
        If ManifestLeaderTarget != None && ManifestAssassinStruck
            If AssassinAttemptIsOver()
                combatOver = true
            EndIf
        EndIf

        ; Cleanup when combat has ended OR hard cap reached
        If (combatOver && elapsed >= 15.0) || elapsed >= ManifestCleanupDelay
            CleanupManifestation()
        Else
            Core.RequestTick(PollInterval)
            return  ; Don't start pending battles while manifestation is active
        EndIf
    EndIf

    ; Stragglers of a battle that is already wound up: each one leaves the world once the player does not see it.
    If SoldiersLeaving && !DeferredCleanupActive
        If SweepDue(StragglerInterval) && SweepSoldiers(false) == 0
            SoldiersLeaving = false
            ClearExitMarkers()
            Core.DebugMsg("Battle: the last soldiers of the battle are gone")
        Else
            Core.RequestTick(StragglerInterval)
        EndIf
    EndIf

    ; Phase 0: the aftermath. The survivors are walking off (DisperseSoldiers); each soldier and each body leaves
    ; the world once the player does not see it. After 180 s the battle is wound up whatever is left, so that the
    ; player is out of the battle sides and another battle may start; those still in view stay on the list as
    ; stragglers. (This used to switch off everyone who was left, in front of the player.)
    If DeferredCleanupActive
        IntelEngine.BattleTendBounty()
        Float elapsed = Utility.GetCurrentRealTime() - DeferredCleanupStart
        Int remaining = SpawnedSoldierCount
        If SweepDue(AftermathInterval) || elapsed >= 180.0
            CeaseFire(true)         ; nobody of the battle is still at another's throat
            remaining = SweepSoldiers(false)
        EndIf
        If remaining == 0 || elapsed >= 180.0
            IntelEngine.ForgetBattleSoldiers()
            RemovePlayerFromBattle()
            DeferredCleanupActive = false
            Bool hadPendingPolls = PendingPollActive && IntelEngine.GetPendingBattleCount() > 0
            If remaining > 0
                Core.DebugMsg("Battle: wound up with " + remaining + " soldiers or bodies still on the field")
                LeaveBattleSides()
                CleanupMarkers(true)          ; the exit markers stay: the stragglers are still walking to them
            Else
                CleanupMarkers()
            EndIf
            ResetState()
            If remaining > 0
                SoldiersLeaving = true
                Core.RequestTick(StragglerInterval)
            EndIf
            If hadPendingPolls
                PendingPollActive = true
                Core.RequestTick(PollInterval)
                Core.DebugMsg("Battle: Resumed pending battle polling after cleanup")
            EndIf
            return
        EndIf
        Core.RequestTick(PollInterval)
    EndIf

    ; Dual-phase polling: pending battles (proximity check) and active battles (combat state)

    ; Phase A: armies gathered somewhere, waiting
    If PendingPollActive && !IntelEngine.IsBattleActive()
        Int triggeredId = IntelEngine.PollPendingBattles()
        If triggeredId >= 0 && Utility.GetCurrentRealTime() >= _noFieldUntil
            HandlePendingBattleTriggered(triggeredId)
            If IntelEngine.IsBattleActive()
                return          ; drawn up: the muster asks for its own ticks
            EndIf
        EndIf

        ; A battle that was decided with nobody there. Word of it reaches a player who is in that hold; everyone
        ; else hears it as talk (it used to be announced to the player wherever they were, the moment it happened).
        String expiredResult = IntelEngine.GetLastExpiredBattleResult()
        If expiredResult != "" && IntelEngine.StoryResponseGetField(expiredResult, "heard") == "true"
            String victorId = IntelEngine.StoryResponseGetField(expiredResult, "victor")
            String locName = IntelEngine.StoryResponseGetField(expiredResult, "location")
            If victorId != ""
                Debug.Notification(IntelEngine.L(IntelEngine.BattleSay("word_won", victorId, "", locName)))
            Else
                Debug.Notification(IntelEngine.L(IntelEngine.BattleSay("word_nobody", "", "", locName)))
            EndIf
        EndIf

        ; A faction the player holds a rank with calls its own to the line; a call whose battle was decided without
        ; them ends.
        TendCall()

        ; Check if any pending battles remain
        If IntelEngine.GetPendingBattleCount() <= 0
            PendingPollActive = false
            Core.DebugMsg("Battle: No pending battles remain - stopping proximity poll")
            return
        EndIf

        Core.RequestTick(PollInterval)
        return
    EndIf

    ; Phase B: the battle on its field
    If !IntelEngine.IsBattleActive()
        ; Battle ended (C++ detected all soldiers dead or timeout).
        ; Clean up immediately — don't wait for next story tick.
        If BattleSpawned
            Core.DebugMsg("Battle: Poll detected battle ended - cleaning up Papyrus state")
            BattleSpawned = false  ; prevent re-entrant cleanup on next poll
            BattlePhase = 0
            ; Don't RemovePlayerFromBattle here — deferred cleanup keeps soldiers alive.
            ; Player stays in battle faction until cleanup finishes (OnUpdate Phase 0).
            ; Notify StoryEngine directly so quest completes NOW (not on next story tick)
            If Core.StoryEngine != None
                Core.StoryEngine.CheckQuestProximity()
            EndIf
            DisperseSoldiers(0, false)
            DeferredCleanupActive = true
            DeferredCleanupStart = Utility.GetCurrentRealTime()
            Core.RequestTick(PollInterval)
        EndIf
        return
    EndIf

    If BattlePhase == 1
        TendMuster()
        If BattlePhase == 1
            Core.RequestTick(MusterPoll)
        EndIf
        return
    EndIf
    If BattlePhase == 0 && FindingField()
        Core.RequestTick(MusterPoll)        ; the field is still being looked for: nothing to tend yet
        return
    EndIf
    If BattlePhase != 2
        ; A battle this script did not begin (one left by an older version): closed.
        Core.DebugMsg("Battle: a battle is active that was never drawn up - closing it")
        CleanupBattle()
        return
    EndIf

    If TendFight()
        return          ; it ended here
    EndIf

    ; Poll C++ BattleManager for state updates
    String stateJson = IntelEngine.PollBattleState()
    If stateJson == "{}"
        ; Battle ended externally or error
        CleanupBattle()
        return
    EndIf

    HandlePollResult(stateJson)
    If BattlePhase == 2 && IntelEngine.IsBattleActive()
        RouseIdleHands()
    EndIf
    Core.RequestTick(PollInterval)
EndEvent

Function RouseIdleHands()
    {Whoever stands about while the battle is on goes for the enemy nearest to them. Everyone who came up after the
    lines had met (reserves, a hidden force, a champion) was sent to the middle of the field, one spot for all of
    them: with the fighting moved on they stood there shoulder to shoulder, whole and idle, while their side lost
    (seen 2026-11-21). So did anyone whose opponent had fallen with nobody else in reach. Six at a look.}
    String hands = IntelEngine.BattleIdleHands(6)
    Int count = IntelEngine.StoryResponseGetField(hands, "count") as Int
    Int i = 0
    While i < count
        Actor hand = SoldierFromId(IntelEngine.GetJsonArrayInt(hands, "idle", i))
        Actor foe = SoldierFromId(IntelEngine.GetJsonArrayInt(hands, "foe", i))
        If hand != None && foe != None && !hand.IsDead() && !foe.IsDead()
            hand.StartCombat(foe)
        EndIf
        i += 1
    EndWhile
    If count > 0
        Core.DebugMsg("Battle: " + count + " who stood about go for the nearest enemy")
    EndIf
EndFunction

; =============================================================================
; BATTLE START
; =============================================================================

; A battle here and now, if there is ground for it: a faction's quest when the player reaches the place, and the
; test hook. The battles of a war come through HandlePendingBattleTriggered.
Function StartBattleImmediate(String factionA, String factionB, Int warId)
    ; Politics switched off means nothing political happens: this ran on (a battle set before the switch, a
    ; skirmish, an ambush of a faction's men) and people met soldiers and assassins "with politics off".
    If !IntelEngine.IsPoliticsEnabled()
        Core.DebugMsg("Battle: not started: politics is switched off")
        return
    EndIf
    If IntelEngine.IsBattleActive() || BattlePhase != 0
        Core.DebugMsg("Battle: Cannot start immediate - already active")
        return
    EndIf
    BattleFactionA = factionA
    BattleFactionB = factionB
    BattleWarId = warId
    BattleLocationName = ""
    BattleScheduled = false
    BattleSpawned = false
    BattleSkirmish = false
    BattleLineSize = GetWaveSoldierCount(1)
    Core.DebugMsg("Battle: Starting immediate - " + factionA + " vs " + factionB)
    If !StartBattleSequence()
        ForgetBattleNames()
    EndIf
EndFunction

Float _fieldSearchSince = -1.0      ; real time at which the search for a field began; below 0: no search

Bool Function FindingField()
    {Is the DLL being asked for a field right now? (By the clock: a search cut off by a load is not one.)}
    If _fieldSearchSince < 0.0
        Return false
    EndIf
    Float since = Utility.GetCurrentRealTime() - _fieldSearchSince
    Return since >= 0.0 && since < 15.0
EndFunction

Bool Function StartBattleSequence()
    {The two armies are drawn up against each other on a field near the player, if there is one. False: no ground
    for it here and now. Nothing has begun then, and whoever asked may ask again later. (A battle used to "begin"
    with the player indoors and wait for them to come out, for as long as they stayed in: it blocked every other
    battle and never ran out.)}
    BattleScheduled = false
    Actor player = Game.GetPlayer()
    If !IsPlayerInExterior()
        Core.DebugMsg("Battle: no battle is drawn up for a player who is indoors")
        Return false
    EndIf
    If BattleLocationName == ""
        BattleLocationName = IntelEngine.GetActorParentLocationName(player)
    EndIf
    If BattleLocationName == ""
        BattleLocationName = "the wilds"
    EndIf

    ActualBattleStartTime = Utility.GetCurrentGameTime()
    BattleStartRealTime = Utility.GetCurrentRealTime()
    ActiveBattleId = IntelEngine.StartBattle(BattleFactionA, BattleFactionB, BattleLocationName, BattleWarId)
    If ActiveBattleId < 0
        Core.DebugMsg("Battle: C++ StartBattle failed (another battle active?)")
        Return false
    EndIf

    ; The DLL looks a quarter of a millisecond at a time and says "looking" until it is through: asked again each
    ; frame. (In one go the search took 1.5 ms of a frame on a big mod list.) The poll leaves the battle alone
    ; meanwhile: it would take a battle that has no lines yet for one left over, and close it.
    _fieldSearchSince = Utility.GetCurrentRealTime()
    String field = IntelEngine.BattlePickField(player, BattleSpawnAnchor)
    Int looks = 0
    While looks < 150 && IntelEngine.StoryResponseGetField(field, "reason") == "looking"
        Utility.Wait(0.02)
        field = IntelEngine.BattlePickField(player, BattleSpawnAnchor)
        looks += 1
    EndWhile
    _fieldSearchSince = -1.0
    If IntelEngine.StoryResponseGetField(field, "ok") != "true"
        Core.DebugMsg("Battle: no field here for " + BattleFactionA + " vs " + BattleFactionB + " (" + \
            IntelEngine.StoryResponseGetField(field, "reason") + ")")
        IntelEngine.EndBattle(ActiveBattleId, "nofield", "")
        IntelEngine.ResetBattleState()
        ActiveBattleId = -1
        Return false
    EndIf

    CurrentWave = 0
    ; Ensure battle factions are hostile to each other (in case CK setup missed)
    Intel_BattleSideA.SetEnemy(Intel_BattleSideB)
    Return DrawUpArmies(field)
EndFunction

; =============================================================================
; THE MUSTER
; =============================================================================

Bool Function DrawUpArmies(String field)
    {Both lines on the field the DLL found, each with its commander in front, facing the other. They are made
    where they stand, switched off, and fade into view the way people in the distance do. They start nothing.}
    Actor player = Game.GetPlayer()
    BattleSpawned = true
    BattlePhase = 1
    MusterStartRealTime = Utility.GetCurrentRealTime()
    MusterSeenRealTime = 0.0
    PlayerWasHailed = false
    _warnedOff = false
    _goneSince = 0.0
    _markedEnemyOf = ""
    _endedUnseen = false
    _waveBusy = false
    _tending = false
    _flankWaiting = ""
    _championWaiting = ""
    _fileAssigned = false
    _wordGiven = false
    ReleaseOldSoldiers()
    If PlayerBattleSide == ""
        player.RemoveFromFaction(Intel_BattleSideA)
        player.RemoveFromFaction(Intel_BattleSideB)
    EndIf

    ; The middle of the field: where those who come later run to, and what the player's distance is measured from.
    CleanupMarkers()
    Form xmarkerBase = Game.GetFormFromFile(0x0000003B, "Skyrim.esm")
    If xmarkerBase
        CenterMarker = player.PlaceAtMe(xmarkerBase)
        CenterMarker.SetPosition(IntelEngine.StoryResponseGetField(field, "x") as Float, \
            IntelEngine.StoryResponseGetField(field, "y") as Float, IntelEngine.StoryResponseGetField(field, "z") as Float)
    EndIf

    CommanderA = None
    CommanderB = None
    If BattleSkirmish
        IntelEngine.BattleSetSkirmish(BattleLineSize)
    EndIf
    Int drawnA = DrawUpLine("A", player)
    Int drawnB = DrawUpLine("B", player)
    RememberBattleSoldiers()
    If drawnA <= 0 || drawnB <= 0 || !IntelEngine.IsBattleActive()
        Core.DebugMsg("Battle: the armies could not be drawn up (" + drawnA + " and " + drawnB + ")")
        CleanupBattle()
        Return false
    EndIf
    If !BattleSkirmish
        NameCommander(CommanderA, BattleFactionA)
        NameCommander(CommanderB, BattleFactionB)
    EndIf

    Int i = 0
    While i < SpawnedSoldierCount && i < SpawnedSoldiers.Length
        Actor soldier = SpawnedSoldiers[i]
        If soldier != None
            soldier.EnableNoWait(true)
            soldier.SetDontMove(true)
        EndIf
        i += 1
    EndWhile

    MusterStartRealTime = Utility.GetCurrentRealTime()      ; they stand from now
    CurrentWave = 1
    IntelEngine.AdvanceBattleWaveOf("A")
    IntelEngine.AdvanceBattleWaveOf("B")
    _noReserveUntilA = 0.0
    _noReserveUntilB = 0.0

    ; A faction's quest: the player has given their word already, and stands with that side.
    If QuestAutoJoinFaction != ""
        String promised = QuestAutoJoinFaction
        QuestAutoJoinFaction = ""
        PlayerWasHailed = true
        JoinBattleSide(promised)
        If promised == BattleFactionB
            PointQuestAt(CommanderB)
        Else
            PointQuestAt(CommanderA)
        EndIf
    EndIf

    Core.DebugMsg("Battle: " + BattleFactionA + " and " + BattleFactionB + " are drawn up near " + BattleLocationName + \
        " - " + drawnA + " and " + drawnB + ", " + player.GetDistance(CenterMarker) + " units from the player")
    Core.RequestTick(MusterPoll)
    Return true
EndFunction

Function SettleSoldiers()
    {The second half of making a soldier, in a frame of its own (the caller has waited one since the making): whoever
    was made is set down where they are to stand and given their side and their orders. Making and settling in one
    call cost 0.51 to 0.57 ms of the game's frame (measured 2026-11-22, the rule being half a millisecond); the game's
    own making is 0.4 ms of that and cannot be cut up, so it has a frame to itself.}
    String left = IntelEngine.BattleSettle()
    If left != ""
        DropOrphans(left)       ; the battle ended between the two halves, or their ground was unloaded: never seen
    EndIf
    Utility.WaitMenuMode(0.03)
EndFunction

Int Function DrawUpLine(String side, Actor player)
    {One army's line, one soldier at a time, each over two frames (made, then settled) with a breath between: a whole
    line at once was a hitch (1.5 ms, measured). Returns how many were made.}
    Int total = BattleLineSize
    Int made = 0
    Int first = 0
    ; Who they are is rolled first, in a frame of its own (on a large load order the roll of a line and the making of
    ; its first soldier in one frame took 1.1 ms).
    IntelEngine.BattlePrepareGroup(side, 3, player)
    Utility.WaitMenuMode(0.03)
    While first < total
        String part = IntelEngine.BattleMusterLine(side, first, 1, player)
        ; The frame a soldier is made in holds nothing else: what the call answered is read in the next one.
        ; (WaitMenuMode: a choice window somebody else put up must not stop an army in the middle of drawing up.
        ; With Wait it did: three soldiers stood in a field for two minutes until a quest offer was answered.)
        Utility.WaitMenuMode(0.03)
        If IntelEngine.StoryResponseGetField(part, "success") != "true"
            Core.DebugMsg("Battle: line " + side + " - " + IntelEngine.StoryResponseGetOptionalField(part, "error"))
            Return made
        EndIf
        made += IntelEngine.StoryResponseGetField(part, "count") as Int
        If first == 0
            Actor leads = SoldierFromId(IntelEngine.GetJsonArrayInt(part, "commander", 0))
            If side == "A"
                CommanderA = leads
            Else
                CommanderB = leads
            EndIf
        EndIf
        first += 1
        SettleSoldiers()
    EndWhile
    Return made
EndFunction

Int Function BringUp(String side, Int count, Actor player)
    {More soldiers for one side, made behind its line one at a time (see DrawUpLine). Returns how many came.}
    Int made = 0
    Int first = 0
    ; Where they come from and who they are is chosen first, in a frame of its own.
    If IntelEngine.BattlePrepareGroup(side, 0, player) <= 0
        Return 0            ; nowhere for them to come from unseen
    EndIf
    Utility.WaitMenuMode(0.03)
    While first < count
        String part = IntelEngine.BattleReinforceLine(side, first, 1, player)
        Utility.WaitMenuMode(0.03)          ; the frame of the making holds nothing else
        If IntelEngine.StoryResponseGetField(part, "success") != "true"
            ; Made in the moment the battle ended: they are not of it, and go.
            DropOrphans(part)
            Return made
        EndIf
        Int came = IntelEngine.StoryResponseGetField(part, "count") as Int
        If came <= 0 && first == 0
            Return 0        ; nowhere for them to come from unseen, or the side has everybody on the field
        EndIf
        made += came
        first += 1
        SettleSoldiers()
    EndWhile
    Return made
EndFunction

Function NameCommander(Actor commander, String factionId)
    {The one who leads an army is known as that: "Imperial Legion Captain".}
    If commander != None
        commander.SetDisplayName(IntelEngine.BattleSay("commander_name", factionId), true)
    EndIf
EndFunction

Function PointQuestAt(Actor leader)
    {A faction's quest: its marker moves from the place to the one who leads the player's side.}
    If leader == None || Core.StoryEngine == None || !Core.StoryEngine.IsObjectiveDisplayed(Core.StoryEngine.QUEST_OBJECTIVE_ID)
        Return
    EndIf
    ReferenceAlias targetAlias = Core.StoryEngine.QuestTargetAlias
    ; Runtime recovery: property may be None on old saves
    ; Uses same recovery pattern as StoryEngine.PlaceQuestMarker
    If targetAlias == None
        Int aliasCount = Core.StoryEngine.GetNumAliases()
        Int ai = aliasCount - 1
        While ai >= 1 && targetAlias == None
            ReferenceAlias ra = Core.StoryEngine.GetAlias(ai) as ReferenceAlias
            If ra != None \
                && ra != Core.AgentAlias00 && ra != Core.AgentAlias01 \
                && ra != Core.AgentAlias02 && ra != Core.AgentAlias03 \
                && ra != Core.AgentAlias04 \
                && ra != Core.TargetAlias00 && ra != Core.TargetAlias01 \
                && ra != Core.TargetAlias02 && ra != Core.TargetAlias03 \
                && ra != Core.TargetAlias04
                targetAlias = ra
                Core.StoryEngine.QuestTargetAlias = targetAlias
                Core.DebugMsg("Battle: recovered QuestTargetAlias from alias scan")
            EndIf
            ai -= 1
        EndWhile
    EndIf
    If targetAlias != None
        targetAlias.ForceRefTo(leader)
        Core.StoryEngine.SetObjectiveDisplayed(Core.StoryEngine.QUEST_OBJECTIVE_ID, false)
        Utility.Wait(0.1)
        Core.StoryEngine.SetObjectiveDisplayed(Core.StoryEngine.QUEST_OBJECTIVE_ID, true)
        Core.DebugMsg("Battle: Quest marker moved to " + leader.GetDisplayName())
    Else
        Core.DebugMsg("Battle: WARNING - QuestTargetAlias is None, cannot place marker on the commander")
    EndIf
EndFunction

Function TendMuster()
    {The lines stand. They charge when the player has been called over and has answered, or has watched for a
    while, or nobody came, or somebody has struck a blow.}
    If _tending
        Return
    EndIf
    _tending = true
    Actor player = Game.GetPlayer()
    Float now = Utility.GetCurrentRealTime()
    Bool near = PlayerOnField(WatchDistance)
    If near && MusterSeenRealTime <= 0.0
        MusterSeenRealTime = now
        ShowBattleStartNotification(BattleLocationName)
    EndIf

    Bool charge = false
    If AnySoldierFighting()
        charge = true
    ElseIf near && !PlayerWasHailed && PlayerBattleSide == ""
        Actor caller = CommanderWhoCalls(player, HailDistance)
        If caller != None
            PlayerWasHailed = true
            HailPlayer(caller)
            charge = true           ; answered or not: it begins
        ElseIf !_warnedOff
            WarnOff(player)
        EndIf
    EndIf
    now = Utility.GetCurrentRealTime()
    Float watched = MusterWatched
    Float longest = MusterLongest
    If BattleSkirmish
        watched = 15.0          ; a handful does not stand and stare for long
        longest = 60.0
    EndIf
    If !charge && MusterSeenRealTime > 0.0 && now - MusterSeenRealTime >= watched
        charge = true
    EndIf
    If !charge && now - MusterStartRealTime >= longest
        charge = true
    EndIf
    ; From Captain on, the line the player stands in waits for their word (unless blows have fallen already).
    If charge && !_wordGiven && PlayerBattleSide != "" && near && !AnySoldierFighting() && IntelEngine.PlayerFactionRank(PlayerBattleSide) >= 4
        _wordGiven = true
        If !AskForTheWord()
            MusterSeenRealTime = Utility.GetCurrentRealTime()       ; they hold: as long again as they have stood
            charge = false
        EndIf
    EndIf
    _tending = false
    If charge && BattlePhase == 1 && IntelEngine.IsBattleActive()
        BeginCharge()
    EndIf
EndFunction

Bool Function PlayerOnField(Float within)
    {Is the player out of doors, in the world the field lies in, and within this distance of its middle?}
    If CenterMarker == None || !IsPlayerInExterior()
        Return false
    EndIf
    Actor player = Game.GetPlayer()
    If player.GetWorldSpace() != CenterMarker.GetWorldSpace()
        Return false
    EndIf
    Return player.GetDistance(CenterMarker) <= within
EndFunction

Bool Function AnySoldierFighting()
    If !SpawnedSoldiers
        Return false
    EndIf
    Int i = 0
    While i < SpawnedSoldierCount && i < SpawnedSoldiers.Length
        Actor soldier = SpawnedSoldiers[i]
        If soldier != None && !soldier.IsDead() && soldier.IsInCombat()
            Return true
        EndIf
        i += 1
    EndWhile
    Return false
EndFunction

Actor Function CommanderWhoCalls(Actor player, Float within)
    {The nearer of the two commanders who would have the player in their line, if one is this near.}
    Actor best = None
    Float nearest = within
    If CommanderA != None && !CommanderA.IsDead() && WouldHave(BattleFactionA, BattleFactionB)
        Float distanceA = player.GetDistance(CommanderA)
        If distanceA <= nearest
            nearest = distanceA
            best = CommanderA
        EndIf
    EndIf
    If CommanderB != None && !CommanderB.IsDead() && WouldHave(BattleFactionB, BattleFactionA)
        If player.GetDistance(CommanderB) <= nearest
            best = CommanderB
        EndIf
    EndIf
    Return best
EndFunction

Bool Function KnownOfficerOf(String theirs, String others)
    {Does the army of "theirs" know the player as an officer of the other one? From the third rank a name is known
    beyond the faction itself (Ranks::Famous); whoever stands as high or higher with "theirs" is their own first.}
    Int withOthers = IntelEngine.PlayerFactionRank(others)
    Return withOthers >= 3 && withOthers > IntelEngine.PlayerFactionRank(theirs)
EndFunction

Bool Function WouldHave(String theirs, String others)
    {Would this army call the player into its line? Not one that takes them for an enemy, and not one that knows
    them as an officer of the army across the field. (Played 2026-11-21: a Captain of the Legion walked past the
    Stormcloaks' line on the way to their own, and the Stormcloak captain greeted them as a stranger whose blade
    was welcome, with "stand with the Stormcloaks" as the first answer.)}
    Return IntelEngine.GetPlayerFactionStanding(theirs) > HostileStanding && !KnownOfficerOf(theirs, others)
EndFunction

Function WarnOff(Actor player)
    {A commander who knows the player as an officer of the other army does not call them over: he shouts at them,
    once, when they come near his line before the fight. No answer is asked for and nothing begins by it.}
    Actor foe = None
    String theirs = ""
    String others = ""
    If CommanderA != None && !CommanderA.IsDead() && KnownOfficerOf(BattleFactionA, BattleFactionB) && player.GetDistance(CommanderA) <= HailDistance
        foe = CommanderA
        theirs = BattleFactionA
        others = BattleFactionB
    ElseIf CommanderB != None && !CommanderB.IsDead() && KnownOfficerOf(BattleFactionB, BattleFactionA) && player.GetDistance(CommanderB) <= HailDistance
        foe = CommanderB
        theirs = BattleFactionB
        others = BattleFactionA
    EndIf
    If foe == None
        Return
    EndIf
    _warnedOff = true
    foe.SetLookAt(player)
    Core.SendTaskNarration(foe, IntelEngine.BattleSay("warn_off", theirs, others, player.GetDisplayName()), player)
    Core.DebugMsg("Battle: " + foe.GetDisplayName() + " knows the player as an officer of " + others + " and shouts at them")
EndFunction

Function HailPlayer(Actor caller)
    {A commander calls the player to their line, in their own words, and the player answers: this side, the other
    (if it would have them), or neither. Every sentence comes whole from the DLL (IntelEngine.BattleSay).}
    Actor player = Game.GetPlayer()
    String theirs = BattleFactionA
    String others = BattleFactionB
    If caller == CommanderB
        theirs = BattleFactionB
        others = BattleFactionA
    EndIf
    ; The other side is theirs to choose if it does not take them for an enemy: going over to it is the player's own
    ; decision, whatever they are known as (only who calls them over depends on that).
    Bool othersWouldHave = IntelEngine.GetPlayerFactionStanding(others) > HostileStanding
    Int friend = 0
    If IntelEngine.GetPlayerFactionStanding(theirs) >= FriendStanding
        friend = 1
    EndIf
    caller.SetLookAt(player)
    Core.SendTaskNarration(caller, IntelEngine.BattleSay("hail", theirs, others, player.GetDisplayName(), friend), player)
    Core.DebugMsg("Battle: " + caller.GetDisplayName() + " calls the player to the line of " + theirs)
    Utility.Wait(2.0)
    IntelEngine_Quests quests = Quest.GetQuest("IntelEngine_QuestKeeper") as IntelEngine_Quests
    If quests != None
        quests.WaitForTheirSay(caller, 10.0)
    EndIf

    String joinTheirs = IntelEngine.BattleSay("choice_join", theirs)
    String joinOthers = IntelEngine.BattleSay("choice_join", others)
    String stayOut = IntelEngine.BattleSay("choice_out")
    String body = IntelEngine.BattleSay("choice_body", theirs, others, caller.GetDisplayName())
    String choice = ""
    If othersWouldHave
        choice = Core.ShowChoice(caller.GetDisplayName(), "Battle", body, joinTheirs, joinOthers, stayOut, 30.0)
    Else
        choice = Core.ShowChoice(caller.GetDisplayName(), "Battle", body, joinTheirs, stayOut, "", 30.0)
    EndIf
    caller.ClearLookAt()
    If !IntelEngine.IsBattleActive() || PlayerBattleSide != ""
        Return          ; it is over, or they took a side by word in the meantime
    EndIf
    If choice == joinTheirs
        JoinBattleSide(theirs)
    ElseIf othersWouldHave && choice == joinOthers
        IntelEngine.BattleNoteTurnedDown(theirs)
        JoinBattleSide(others)
    Else
        IntelEngine.BattleNoteTurnedDown(theirs)
        Core.DebugMsg("Battle: the player stays out of it")
    EndIf
EndFunction

Function BeginCharge()
    {The word is given and the lines go at each other.}
    If BattlePhase != 1
        Return
    EndIf
    BattlePhase = 2
    BattleStartRealTime = Utility.GetCurrentRealTime()
    Actor player = Game.GetPlayer()
    ; The commander the player can hear gives the word, in their own voice. Nobody waits for it.
    If PlayerOnField(WatchDistance)
        Actor crier = CommanderA
        String own = BattleFactionA
        String foe = BattleFactionB
        If CommanderA == None || CommanderA.IsDead() || (CommanderB != None && !CommanderB.IsDead() && player.GetDistance(CommanderB) < player.GetDistance(CommanderA))
            crier = CommanderB
            own = BattleFactionB
            foe = BattleFactionA
        EndIf
        If crier != None && !crier.IsDead()
            Core.SendTaskNarration(crier, IntelEngine.BattleSay("cry", own, foe), None)
        EndIf
        Utility.Wait(1.5)
    EndIf
    If PlayerBattleSide == ""
        MarkPlayerEnemy(player)
    EndIf
    Int i = 0
    While i < SpawnedSoldierCount && i < SpawnedSoldiers.Length
        Actor soldier = SpawnedSoldiers[i]
        If soldier != None && !soldier.IsDead()
            soldier.SetDontMove(false)
            soldier.SetActorValue("Aggression", 1.0)        ; they fight the other line, and nobody else
        EndIf
        i += 1
    EndWhile
    IntelEngine.BattleBeginFight()
    ForceInitialEngagement()
    AssignFile()
    If MusterSeenRealTime <= 0.0 && PlayerOnField(GoneDistance)
        Debug.Notification(IntelEngine.L(IntelEngine.BattleSay("broke_out")))
    EndIf
    Core.DebugMsg("Battle: the lines meet")
    Core.RequestTick(PollInterval)
EndFunction

Function MarkPlayerEnemy(Actor player)
    {A side that takes the player for an enemy treats them as one of the other army (the worse of two that do).
    Taken back when the battle is over, whatever its end: it used to stay.}
    Int standingA = IntelEngine.GetPlayerFactionStanding(BattleFactionA)
    Int standingB = IntelEngine.GetPlayerFactionStanding(BattleFactionB)
    If standingA <= HostileStanding && standingA <= standingB
        player.AddToFaction(Intel_BattleSideB)
        _markedEnemyOf = BattleFactionA
    ElseIf standingB <= HostileStanding
        player.AddToFaction(Intel_BattleSideA)
        _markedEnemyOf = BattleFactionB
    EndIf
    If _markedEnemyOf != ""
        Core.DebugMsg("Battle: " + _markedEnemyOf + " takes the player for an enemy")
    EndIf
EndFunction

; =============================================================================
; THE FIGHT
; =============================================================================

Bool Function TendFight()
    {Looked at on every poll of the fight. True: the battle was ended here (the player has gone, or it has gone on
    for too long).}
    Actor player = Game.GetPlayer()
    Float now = Utility.GetCurrentRealTime()
    If !PlayerOnField(GoneDistance)
        If _goneSince <= 0.0
            _goneSince = now
        ElseIf now - _goneSince >= GoneSeconds
            ; Armies do not wait for one traveller. (They used to: with the player gone nobody died, the battle
            ; ran its half hour, and whoever had taken a side stayed in it all that time.)
            Core.DebugMsg("Battle: the player has left the field - it is decided without them")
            IntelEngine.BattleNotePlayerLeft()
            _endedUnseen = true
            EndByVerdict()
            Return true
        EndIf
    Else
        _goneSince = 0.0
    EndIf
    If BattleStartRealTime > 0.0 && now - BattleStartRealTime > BattleLongest
        Core.DebugMsg("Battle: " + (now - BattleStartRealTime) + " s and not decided - both sides draw off")
        EndByVerdict()
        Return true
    EndIf
    ; One more chance to take a side for someone who walks into the fight unasked.
    If !PlayerWasHailed && PlayerBattleSide == "" && !_tending
        Actor caller = CommanderWhoCalls(player, HailInFightDistance)
        If caller != None
            PlayerWasHailed = true
            _tending = true
            HailPlayer(caller)
            _tending = false
        EndIf
    EndIf
    Return false
EndFunction

Function EndByVerdict()
    {A battle that is not fought out: whoever has the better of it holds the field, or nobody does.}
    String verdict = IntelEngine.BattleVerdict()
    HandleBattleEnd(IntelEngine.StoryResponseGetField(verdict, "result"), IntelEngine.StoryResponseGetOptionalField(verdict, "victor"), "")
EndFunction

Function SpawnWave(String side)
    {More of one army come up behind its line and run to the fight: the army that needs them (it has lost two men
    in five since its last wave came). They are made out of the player's way and fade in.}
    If _waveBusy
        Return          ; the poll came round again while the last wave was still being brought up
    EndIf
    Float now = Utility.GetCurrentRealTime()
    If (side == "A" && now < _noReserveUntilA) || (side == "B" && now < _noReserveUntilB)
        Return          ; nowhere for them to come from unseen a moment ago: not asked again at once
    EndIf
    _waveBusy = true
    Actor player = Game.GetPlayer()
    Int waveNum = IntelEngine.GetBattleWaveOf(side) + 1
    Int count = GetWaveSoldierCount(waveNum)
    Int before = SpawnedSoldierCount
    Int more = BringUp(side, count, player)
    RememberBattleSoldiers()
    Int arrived = SendToTheFight(before)
    If more <= 0 && arrived <= 0
        If side == "A"
            _noReserveUntilA = now + 12.0
        Else
            _noReserveUntilB = now + 12.0
        EndIf
        _waveBusy = false
        Return
    EndIf
    IntelEngine.AdvanceBattleWaveOf(side)
    If waveNum > CurrentWave
        CurrentWave = waveNum
    EndIf
    String own = BattleFactionA
    If side == "B"
        own = BattleFactionB
    EndIf
    Core.DebugMsg("Battle: " + more + " more of " + own + " come up (its wave " + waveNum + ")")
    If PlayerOnField(WatchDistance + 1500.0)
        If waveNum >= 5
            Debug.Notification(IntelEngine.L(IntelEngine.BattleSay("last_come", own)))
        Else
            Debug.Notification(IntelEngine.L(IntelEngine.BattleSay("more_come", own)))
        EndIf
    EndIf
    _waveBusy = false
    ; A champion or a hidden force was to come while this wave was being brought up.
    If _championWaiting != "" && IntelEngine.IsBattleActive()
        String due = _championWaiting
        _championWaiting = ""
        If StringUtil.Find(due, "A") >= 0
            BringChampion("A")
        EndIf
        If StringUtil.Find(due, "B") >= 0 && IntelEngine.IsBattleActive()
            BringChampion("B")
        EndIf
    EndIf
    If _flankWaiting != "" && IntelEngine.IsBattleActive()
        SpringFlank(_flankWaiting)
    EndIf
EndFunction

Int Function SendToTheFight(Int first)
    {Everyone on the list from this place on has just been made behind their line: they fade in and run to the
    middle of the field, where they meet the enemy.}
    Int sent = 0
    Int i = first
    ; Decided while they were being made: nobody has seen them, and they do not come. (Switched off as they are, the
    ; aftermath's next look takes them out of the world.) They used to fade in and run to the middle of a field
    ; whose battle was over, ready to fight.
    Bool over = !IntelEngine.IsBattleActive()
    While i < SpawnedSoldierCount && i < SpawnedSoldiers.Length
        Actor soldier = SpawnedSoldiers[i]
        If soldier != None && !over
            soldier.EnableNoWait(true)
            If CenterMarker != None
                PO3_SKSEFunctions.SetLinkedRef(soldier, CenterMarker, Core.IntelEngine_TravelTarget)
                ActorUtil.AddPackageOverride(soldier, Core.TravelPackage_Jog, Core.PRIORITY_TRAVEL, 1)
                soldier.EvaluatePackage()
            EndIf
            sent += 1
        EndIf
        i += 1
    EndWhile
    If over && i > first
        Core.DebugMsg("Battle: " + (i - first) + " made as the battle was decided do not come")
    EndIf
    Return sent
EndFunction

Function DropOrphans(String lineJson)
    Int count = IntelEngine.StoryResponseGetField(lineJson, "count") as Int
    Int i = 0
    While i < count
        Actor orphan = SoldierFromId(IntelEngine.GetJsonArrayInt(lineJson, "formIds", i))
        If orphan != None
            orphan.Delete()
        EndIf
        i += 1
    EndWhile
EndFunction

Int Function GetWaveSoldierCount(Int waveNum)
    ; Battlefield::WaveSize: 8+5+4+3+2 = 22 a side, the lines that draw up being the bigger part.
    If waveNum == 1
        return 8
    ElseIf waveNum == 2
        return 5
    ElseIf waveNum == 3
        return 4
    ElseIf waveNum == 4
        return 3
    ElseIf waveNum == 5
        return 2
    EndIf
    return 0
EndFunction

; =============================================================================
; WHAT A BATTLE HAS IN STORE (Battlefield.h, Plan): a champion, a hidden force, turncoats
; =============================================================================

Function WelcomeChampion(Actor champion, String side)
    {A side's champion has come up with its second wave: three times a soldier's measure, striking with full force.
    Known as that by name and by size; seen coming; and when the player stands with the other side, it is the
    player the champion comes for.}
    If champion == None
        Return
    EndIf
    String own = BattleFactionA
    String foe = BattleFactionB
    If side == "B"
        own = BattleFactionB
        foe = BattleFactionA
    EndIf
    Actor player = Game.GetPlayer()
    champion.SetDisplayName(IntelEngine.BattleSay("champion_name", own), true)
    champion.SetScale(1.12)
    Bool near = PlayerOnField(WatchDistance + 1500.0)
    If near
        Debug.Notification(IntelEngine.L(IntelEngine.BattleSay("champion_comes", own)))
    EndIf
    Bool forPlayer = PlayerBattleSide != "" && PlayerBattleSide != own
    Core.DebugMsg("Battle: a champion of " + own + " takes the field (for the player: " + forPlayer + ")")
    Utility.Wait(2.5)       ; until they are there to be seen and to act
    If champion.IsDead() || !IntelEngine.IsBattleActive()
        Return
    EndIf
    If forPlayer
        champion.StartCombat(player)
        If near
            Core.SendTaskNarration(champion, IntelEngine.BattleSay("champion_cry", own, foe, player.GetDisplayName()), player)
        EndIf
    ElseIf near
        Core.SendTaskNarration(champion, IntelEngine.BattleSay("champion_cry", own, foe), None)
    EndIf
EndFunction

Function BringChampion(String side)
    {A side's champion comes up from behind its line, alone, when the fighting has gone on a while.}
    If _waveBusy
        _championWaiting += side     ; a wave is being brought up just now: right after it
        Return
    EndIf
    _waveBusy = true
    Actor player = Game.GetPlayer()
    Int before = SpawnedSoldierCount
    String part = ""
    If IntelEngine.BattlePrepareGroup(side, 2, player) > 0
        Utility.WaitMenuMode(0.03)
        part = IntelEngine.BattleChampionLine(side, player)
        Utility.WaitMenuMode(0.03)          ; the frame of the making holds nothing else
    EndIf
    Actor champion = None
    If part == ""
        ; nowhere to come up unseen
    ElseIf IntelEngine.StoryResponseGetField(part, "success") != "true"
        DropOrphans(part)
    Else
        champion = SoldierFromId(IntelEngine.GetJsonArrayInt(part, "champion", 0))
        SettleSoldiers()
    EndIf
    RememberBattleSoldiers()
    SendToTheFight(before)
    _waveBusy = false
    If champion != None
        WelcomeChampion(champion, side)
    Else
        Core.DebugMsg("Battle: the champion of side " + side + " could not come up unseen")
    EndIf
EndFunction

Function SpringFlank(String side)
    {A side's hidden force breaks cover out to one side of the other's line and falls on it. The DLL says when
    (some half a minute into the fighting) and makes them where the player does not see them appear.}
    If _waveBusy
        _flankWaiting = side     ; a wave is being brought up just now: right after it
        Return
    EndIf
    _waveBusy = true
    _flankWaiting = ""
    Actor player = Game.GetPlayer()
    Int before = SpawnedSoldierCount
    Int made = 0
    Int first = 0
    If IntelEngine.BattlePrepareGroup(side, 1, player) <= 0
        first = 4               ; nowhere to break cover unseen: they stay hidden
    Else
        Utility.WaitMenuMode(0.03)
    EndIf
    While first < 4
        String part = IntelEngine.BattleFlankLine(side, first, 1, player)
        Utility.WaitMenuMode(0.03)          ; the frame of the making holds nothing else
        If IntelEngine.StoryResponseGetField(part, "success") != "true"
            DropOrphans(part)
            first = 4
        Else
            Int came = IntelEngine.StoryResponseGetField(part, "count") as Int
            If came <= 0 && first == 0
                first = 4           ; nowhere to break cover unseen: they stay hidden
            Else
                made += came
                first += 1
                SettleSoldiers()
            EndIf
        EndIf
    EndWhile
    RememberBattleSoldiers()
    SendToTheFight(before)
    String own = BattleFactionA
    If side == "B"
        own = BattleFactionB
    EndIf
    Core.DebugMsg("Battle: a hidden force of " + own + " breaks cover on the flank - " + made)
    If made > 0 && PlayerOnField(WatchDistance + 1500.0)
        Debug.Notification(IntelEngine.L(IntelEngine.BattleSay("flank", own)))
    EndIf
    _waveBusy = false
EndFunction

Function TurnCoats(String side)
    {Some of one side's men turn their coats: the DLL says who (and counts them for the other side from now on); here
    they change their battle side and go for their old comrades.}
    String turned = IntelEngine.BattleTurnCoats(side)
    Int count = IntelEngine.StoryResponseGetField(turned, "count") as Int
    If count <= 0
        Return
    EndIf
    Faction was = Intel_BattleSideA
    Faction now = Intel_BattleSideB
    String own = BattleFactionA
    String other = BattleFactionB
    If side == "B"
        was = Intel_BattleSideB
        now = Intel_BattleSideA
        own = BattleFactionB
        other = BattleFactionA
    EndIf
    ; Somebody of their old side to go for.
    Actor comrade = None
    Int i = 0
    While i < SpawnedSoldierCount && i < SpawnedSoldiers.Length && comrade == None
        Actor soldier = SpawnedSoldiers[i]
        If soldier != None && !soldier.IsDead() && soldier.IsInFaction(was)
            comrade = soldier
        EndIf
        i += 1
    EndWhile
    Actor first = None
    i = 0
    While i < count
        Actor coat = SoldierFromId(IntelEngine.GetJsonArrayInt(turned, "formIds", i))
        If coat != None && !coat.IsDead()
            coat.RemoveFromFaction(was)
            coat.AddToFaction(now)
            coat.SetDisplayName(IntelEngine.BattleSay("turncoat_name", own), true)
            coat.IgnoreFriendlyHits(false)
            coat.StopCombat()
            If comrade != None && comrade != coat
                coat.StartCombat(comrade)
            EndIf
            If first == None
                first = coat
            EndIf
        EndIf
        i += 1
    EndWhile
    Core.DebugMsg("Battle: " + count + " of " + own + " turn their coats")
    If PlayerOnField(WatchDistance + 1500.0)
        Debug.Notification(IntelEngine.L(IntelEngine.BattleSay("treachery", own)))
        If first != None
            Core.SendTaskNarration(first, IntelEngine.BattleSay("turncoat_cry", own, other), None)
        EndIf
    EndIf
EndFunction

; =============================================================================
; THE LADDER IN THE FIELD (Ranks.h): soldiers at the player's side, the line waiting for a captain's word
; =============================================================================

Function AssignFile()
    {From the second rank on the player has a file of their own in a battle of their side: two soldiers (four from
    Captain on) who keep by them, fight where they fight and come back to them between.}
    If PlayerBattleSide == "" || _fileAssigned
        Return
    EndIf
    _fileAssigned = true
    Int rank = IntelEngine.PlayerFactionRank(PlayerBattleSide)
    Int wanted = 0
    If rank >= 4
        wanted = 4
    ElseIf rank >= 2
        wanted = 2
    EndIf
    If wanted <= 0
        Return
    EndIf
    Faction own = Intel_BattleSideA
    If PlayerBattleSide == BattleFactionB
        own = Intel_BattleSideB
    EndIf
    Actor player = Game.GetPlayer()
    Int given = 0
    Int i = SpawnedSoldierCount - 1
    While i >= 0 && given < wanted
        If i < SpawnedSoldiers.Length
            Actor soldier = SpawnedSoldiers[i]
            If soldier != None && !soldier.IsDead() && soldier.IsInFaction(own) && soldier != CommanderA && soldier != CommanderB
                ; They follow, the way a companion does: a few steps off. (They were sent to the player on the travel
                ; package, whose place is the very spot its target stands on: soldiers walking into the player for
                ; as long as the battle lasted.)
                TakeBackTravelOrder(soldier)
                Package follow = FollowPackage()
                If follow != None
                    ActorUtil.AddPackageOverride(soldier, follow, Core.PRIORITY_TRAVEL, 1)
                EndIf
                soldier.EvaluatePackage()
                given += 1
            EndIf
        EndIf
        i -= 1
    EndWhile
    If given >= 2
        Debug.Notification(IntelEngine.L(IntelEngine.BattleSay("file", PlayerBattleSide, "", "", given)))
    EndIf
    Core.DebugMsg("Battle: " + given + " soldiers keep by the player (rank " + rank + ")")
EndFunction

Bool Function AskForTheWord()
    {From Captain on the line the player stands in waits for the player's word. True: charge now. False: they hold a
    little longer (asked once; after that it goes as it would have).}
    Actor captain = CommanderA
    If PlayerBattleSide == BattleFactionB
        captain = CommanderB
    EndIf
    String who = IntelEngine.PlayerRankTitle(PlayerBattleSide)
    If captain != None && !captain.IsDead()
        who = captain.GetDisplayName()
    EndIf
    String charge = IntelEngine.BattleSay("word_charge")
    String choice = Core.ShowChoice(who, "Battle", IntelEngine.BattleSay("word_body", PlayerBattleSide, "", IntelEngine.PlayerRankTitle(PlayerBattleSide)), \
        charge, IntelEngine.BattleSay("word_hold"), "", 40.0)
    Core.DebugMsg("Battle: the line waits for the player's word - " + choice)
    Return choice != IntelEngine.BattleSay("word_hold")
EndFunction

; =============================================================================
; PLAYER PARTICIPATION
; =============================================================================

Function JoinBattleSide(String factionId)
    {The player takes a side: asked by its commander, by telling one of its soldiers (JoinBattleByWord), or because
    a faction's quest brought them. Once taken it stands for the battle.}
    If factionId == "" || PlayerBattleSide == factionId
        return
    EndIf
    If PlayerBattleSide != ""
        Core.DebugMsg("Battle: Cannot switch sides mid-battle (already on " + PlayerBattleSide + ")")
        return
    EndIf
    ; Tell C++: the side takes heart, the other loses some
    If !IntelEngine.SetPlayerBattleSide(factionId)
        Core.DebugMsg("Battle: JoinBattleSide failed for " + factionId)
        return
    EndIf
    PlayerBattleSide = factionId
    _markedEnemyOf = ""

    Actor player = Game.GetPlayer()
    player.RemoveFromFaction(Intel_BattleSideA)
    player.RemoveFromFaction(Intel_BattleSideB)
    If IntelEngine.GetFactionBattleSide(factionId) == "A"
        player.AddToFaction(Intel_BattleSideA)
    Else
        player.AddToFaction(Intel_BattleSideB)
    EndIf
    Debug.Notification(IntelEngine.L(IntelEngine.BattleSay("stand_with", factionId)))
    Core.DebugMsg("Battle: Player joined " + factionId + " (rank " + IntelEngine.PlayerFactionRank(factionId) + " " + IntelEngine.PlayerRankTitle(factionId) + ")")
    TrustOwnSide()
    If BattlePhase == 2
        AssignFile()            ; joined with the fight already on: their file falls in now
    EndIf
EndFunction

Function TrustOwnSide()
    {The soldiers of the side the player stands with take a stray blow of theirs for what it is. In a press of
    forty people a swung blade finds a comrade now and then; each such blow used to be an assault, and the
    soldier struck turned on the player with his whole line (2026-11-21). The battle sides are allied to
    themselves in the plugin file as well; this mark makes a comrade ignore such a blow altogether. Those who
    come up later get it in RememberBattleSoldiers.}
    If PlayerBattleSide == "" || !SpawnedSoldiers
        Return
    EndIf
    Faction own = Intel_BattleSideA
    If IntelEngine.GetFactionBattleSide(PlayerBattleSide) != "A"
        own = Intel_BattleSideB
    EndIf
    Int i = 0
    While i < SpawnedSoldierCount && i < SpawnedSoldiers.Length
        Actor soldier = SpawnedSoldiers[i]
        If soldier != None && !soldier.IsDead() && soldier.IsInFaction(own)
            soldier.IgnoreFriendlyHits(true)
        EndIf
        i += 1
    EndWhile
EndFunction

Bool Function JoinBattleByWord(Actor akSpeaker)
    {SkyrimNet action JoinBattle: the player has told a soldier of one of the two armies that they will fight on
    that soldier's side.}
    If akSpeaker == None || akSpeaker.IsDead() || !IntelEngine.IsBattleActive() || PlayerBattleSide != "" || !IsRemembered(akSpeaker)
        Return false
    EndIf
    String side = BattleFactionA
    If akSpeaker.IsInFaction(Intel_BattleSideB)
        side = BattleFactionB
    EndIf
    If IntelEngine.GetPlayerFactionStanding(side) <= HostileStanding
        Return false
    EndIf
    PlayerWasHailed = true
    JoinBattleSide(side)
    Return PlayerBattleSide == side
EndFunction

Function RemovePlayerFromBattle()
    {The player belongs to no side any more. Always, whatever brought them into one: a side taken, or a side that
    took them for an enemy (that one used to stay, and every later brawl and skirmish turned on the player).}
    Actor player = Game.GetPlayer()
    player.RemoveFromFaction(Intel_BattleSideA)
    player.RemoveFromFaction(Intel_BattleSideB)
    If PlayerBattleSide != ""
        IntelEngine.SetPlayerBattleSide("")
        Core.DebugMsg("Battle: Player removed from battle factions")
    EndIf
    PlayerBattleSide = ""
    _markedEnemyOf = ""
EndFunction

; =============================================================================
; COMBAT ENGAGEMENT
; =============================================================================

Function ForceInitialEngagement()
    ; Query C++ for actor FormIDs — NO Papyrus arrays needed (immune to stale bytecode)
    String jsonA = IntelEngine.GetBattleSoldierFormIds("A")
    String jsonB = IntelEngine.GetBattleSoldierFormIds("B")
    Int countA = IntelEngine.StoryResponseGetField(jsonA, "count") as Int
    Int countB = IntelEngine.StoryResponseGetField(jsonB, "count") as Int

    Int engageCount = countA
    If countB < engageCount
        engageCount = countB
    EndIf

    Int paired = 0
    Int i = 0
    While i < engageCount
        Int formIdA = IntelEngine.GetJsonArrayInt(jsonA, "formIds", i)
        Int formIdB = IntelEngine.GetJsonArrayInt(jsonB, "formIds", i)
        Actor soldierA = SoldierFromId(formIdA)
        Actor soldierB = SoldierFromId(formIdB)
        If soldierA && soldierB && !soldierA.IsDead() && !soldierB.IsDead()
            soldierA.StartCombat(soldierB)
            soldierB.StartCombat(soldierA)
            paired += 1
        EndIf
        i += 1
    EndWhile
    Core.DebugMsg("Battle: Kick-started " + paired + "/" + engageCount + " combat pairs, " + countA + " vs " + countB)
EndFunction

; =============================================================================
; BOUNTY SUPPRESSION
; =============================================================================

; CacheCrimeFactions — REMOVED. Bounty management moved entirely to C++.
; C++ SnapshotBounties() is called from ExecuteFullBattleSpawn automatically.

; ClearBattleBounty — REMOVED. Bounty prevention handled at spawn time by C++ crime faction removal.
; RestorePreBattleBounties — REMOVED. No-op since crime faction removal is permanent on spawned soldiers.

; =============================================================================
; POST-BATTLE
; =============================================================================


Function PostBattleSoldierMoment(Actor survivor, Int alliesLeft, String ownSide, String otherSide, Bool playerWon, Bool drawn, Int reward, Int enemyKills)
    {One of the player's side comes over and has a word, in their own voice: thanks and the pay after a victory,
    a warning after a defeat. Then they follow the others. (This was a line of English in the corner of the
    screen, between quotation marks.)}
    If alliesLeft <= 0
        If playerWon
            Debug.Notification(IntelEngine.L("The field is yours, though none of your side is left standing to share it."))
            PaySentOn(ownSide, reward)
        Else
            Debug.Notification(IntelEngine.L("You stand alone among the fallen."))
        EndIf
        return
    EndIf
    If !survivor || survivor.IsDead()
        Core.DebugMsg("Battle: allies live, but none is anywhere near - no word")
        If playerWon
            PaySentOn(ownSide, reward)
        EndIf
        return
    EndIf
    ; Comes over: at a run while they are far, at a weary pace for the last stretch. A travel order, not a scripted
    ; path: that one cannot be given up.
    Actor player = Game.GetPlayer()
    Float from = survivor.GetDistance(player)
    ; He comes the way a companion follows: on the follow order of the soldiers at the player's side, which has no
    ; place to get to and so nothing to go wrong about it. (He used to be sent on the travel order with the player
    ; as its place. Fresh out of the fight that did not take: twice on the full mod list the one who was to bring
    ; the pay walked on with the march, past the player at 900 units and off toward Riverwood, and a battle won paid
    ; nothing. Told to follow, the same man turned at once. 2026-11-21.)
    _speaker = survivor
    Package gait = FollowPackage()
    Bool following = gait != None
    If !following
        gait = PaceFor(survivor, Core.TravelPackage_Jog, Core.TravelPackage_Run)
    EndIf
    Core.DebugMsg("Battle: " + survivor + " is to come over from " + from + " units (on " + \
        PaceName(survivor.GetCurrentPackage()) + ", told to " + PaceName(gait) + ", fighting " + survivor.IsInCombat() + ")")
    CalmSoldier(survivor)
    TakeBackTravelOrder(survivor)
    If !following
        PO3_SKSEFunctions.SetLinkedRef(survivor, player, Core.IntelEngine_TravelTarget)
    EndIf
    ActorUtil.AddPackageOverride(survivor, gait, Core.PRIORITY_TRAVEL, 1)
    survivor.EvaluatePackage()
    ; As long as the way is: half a minute for somebody near, close to two for somebody across the field. By the
    ; clock, not by counting waits: with many scripts at work a quarter of a second's wait takes far longer, and
    ; "45 seconds" were 67.
    Float began = Utility.GetCurrentRealTime()
    Float most = 25.0 + from / 60.0
    If most > 110.0
        most = 110.0
    EndIf
    Float waited = 0.0
    Float told = 0.0
    Float best = from           ; the nearest he has been, and when: one who follows stops at his own few steps off
    Float bestAt = 0.0
    Bool settled = false
    Int tries = 0
    Bool weary = false
    While waited < most && !settled && survivor.GetDistance(player) > AllyStopsDistance && !survivor.IsDead()
        Float off = survivor.GetDistance(player)
        If !weary && off < 900.0
            weary = true
            survivor.SetActorValue("SpeedMult", 70.0)
        EndIf
        Utility.Wait(0.25)
        waited = Utility.GetCurrentRealTime() - began
        off = survivor.GetDistance(player)
        If off < best - 15.0
            best = off
            bestAt = waited
        ElseIf off <= AllySpeaksDistance && waited - bestAt >= 1.5
            settled = true      ; near enough to speak, and he has come no nearer for a moment: this is where he stands
        EndIf
        ; The order has to take. If he goes on with what he was doing, he is told again, another way each time: on
        ; the travel order at a run, then with his wits shaken awake and told to follow once more, then at the other
        ; pace.
        If !settled && tries < 3 && waited >= 4.0 * (tries + 1) && (survivor.GetCurrentPackage() != gait || off > from + 150.0)
            tries += 1
            Core.DebugMsg("Battle: the order to come over has not taken (" + off + " units after " + waited + " s, on " + \
                PaceName(survivor.GetCurrentPackage()) + ", fighting " + survivor.IsInCombat() + ") - told again, way " + tries)
            CalmSoldier(survivor)
            TakeBackTravelOrder(survivor)
            If tries == 2 && FollowPackage() != None
                survivor.EnableAI(false)
                survivor.EnableAI(true)
                gait = FollowPackage()
            Else
                gait = PaceFor(survivor, Core.TravelPackage_Run, Core.TravelPackage_Jog)
                PO3_SKSEFunctions.SetLinkedRef(survivor, player, Core.IntelEngine_TravelTarget)
            EndIf
            ActorUtil.AddPackageOverride(survivor, gait, Core.PRIORITY_TRAVEL, 1)
            survivor.EvaluatePackage()
            from = off
            best = off
            bestAt = waited
        EndIf
        If waited - told >= 5.0
            told = waited
            Core.DebugMsg("Battle: comes over - " + off + " units after " + waited + " s, on " + \
                PaceName(survivor.GetCurrentPackage()) + ", fighting " + survivor.IsInCombat())
        EndIf
    EndWhile
    ; He stops there, a few steps off, and stands while he speaks. (His order to come to the player stayed on him
    ; until he had spoken, and the words take their time to come: he walked into the player, was pushed off, and
    ; walked into them again, for as long as that took. Seen by the user, 2026-11-21.)
    Bool stopped = false
    If !survivor.IsDead() && survivor.GetDistance(player) <= AllySpeaksDistance
        TakeBackTravelOrder(survivor)
        survivor.EvaluatePackage()
        TurnTo(survivor, player)
        survivor.SetDontMove(true)
        survivor.SetLookAt(player)
        stopped = true
    EndIf
    If stopped
        String who = player.GetDisplayName()
        String what = "after_lost"
        If playerWon
            what = "after_won"
        ElseIf drawn
            what = "after_drawn"
        EndIf
        Core.SendTaskNarration(survivor, IntelEngine.BattleSay(what, ownSide, otherSide, who, enemyKills, reward), player)
        Core.DebugMsg("Battle: " + survivor.GetDisplayName() + " has a word with the player after " + waited + " s")
        Utility.Wait(2.0)
        ; (Half a minute for the words to come: after a battle they took twenty-five seconds, and the gold was in
        ; the player's purse a quarter of a minute before the soldier opened his mouth.)
        IntelEngine_Quests quests = Quest.GetQuest("IntelEngine_QuestKeeper") as IntelEngine_Quests
        If quests != None
            quests.WaitForTheirSay(survivor, 30.0)
        EndIf
        ; The pay, handed over by the one who came, there and then.
        If playerWon && reward > 0
            If !survivor.IsDead()
                player.AddItem(Game.GetFormFromFile(0x0000000F, "Skyrim.esm"), reward)
                Core.DebugMsg("Battle: " + reward + " gold paid to the player")
            Else
                PaySentOn(ownSide, reward)
            EndIf
        EndIf
    Else
        Core.DebugMsg("Battle: " + survivor.GetDisplayName() + " did not reach the player in time, no word (" + \
            survivor.GetDistance(player) + " units off after " + waited + " s)")
        If playerWon
            PaySentOn(ownSide, reward)
        EndIf
    EndIf
    survivor.SetActorValue("SpeedMult", 100.0)
    If stopped
        survivor.SetDontMove(false)
        survivor.ClearLookAt()
    EndIf
    _speaker = None
    If !survivor.IsDead()
        ObjectReference way = ExitFor(survivor.IsInFaction(Intel_BattleSideB))
        If way != None
            SendSoldierOff(survivor, way, !playerWon && !drawn)
        EndIf
    EndIf
EndFunction

; =============================================================================
; POLL HANDLING
; =============================================================================

Function HandlePollResult(String stateJson)
    ; Parse key fields from poll JSON
    Bool battleOver = IntelEngine.StoryResponseGetField(stateJson, "battle_over") == "true"
    String result = IntelEngine.StoryResponseGetOptionalField(stateJson, "result")
    String victor = IntelEngine.StoryResponseGetOptionalField(stateJson, "victor")

    ; An army's commander has fallen: its men see it (and lose heart: the DLL has counted that).
    String fallen = IntelEngine.StoryResponseGetOptionalField(stateJson, "commander_down")
    If fallen != "" && !battleOver && PlayerOnField(WatchDistance + 1500.0)
        Debug.Notification(IntelEngine.L(IntelEngine.BattleSay("captain_fell", fallen)))
    EndIf

    String championFell = IntelEngine.StoryResponseGetOptionalField(stateJson, "champion_down")
    If championFell != "" && !battleOver && PlayerOnField(WatchDistance + 1500.0)
        Debug.Notification(IntelEngine.L(IntelEngine.BattleSay("champion_fell", championFell)))
    EndIf
    If !battleOver
        String championOf = IntelEngine.StoryResponseGetOptionalField(stateJson, "do_champion")
        If StringUtil.Find(championOf, "A") >= 0
            BringChampion("A")
        EndIf
        If StringUtil.Find(championOf, "B") >= 0 && IntelEngine.IsBattleActive()
            BringChampion("B")
        EndIf
        String flankOf = IntelEngine.StoryResponseGetOptionalField(stateJson, "do_flank")
        If flankOf != ""
            SpringFlank(flankOf)
        EndIf
        String turnOf = IntelEngine.StoryResponseGetOptionalField(stateJson, "do_turn")
        If turnOf != "" && IntelEngine.IsBattleActive()
            TurnCoats(turnOf)
        EndIf
    EndIf

    ; Check wave spawn triggers
    If !battleOver
        Bool shouldSpawnA = IntelEngine.StoryResponseGetField(stateJson, "should_spawn_wave_a") == "true"
        Bool shouldSpawnB = IntelEngine.StoryResponseGetField(stateJson, "should_spawn_wave_b") == "true"

        If shouldSpawnA
            SpawnWave("A")
        EndIf
        If shouldSpawnB && IntelEngine.IsBattleActive()
            SpawnWave("B")
        EndIf
    EndIf

    ; Handle battle end
    If battleOver
        HandleBattleEnd(result, victor, stateJson)
    EndIf
EndFunction

; =============================================================================
; BATTLE END
; =============================================================================

Function CeaseFire(Bool amongThemselves)
    {The battle is decided: from this moment nobody of it fights on. The two sides are enemies no longer (they
    stayed enemies until the battle was wound up, minutes later), and every soldier's fight is called off, a few a
    frame. Before, each soldier was calmed in turn while the sides stayed enemies: with fifteen soldiers that takes
    five to eight seconds on a large load order, and whoever had not been reached yet went on striking those who
    had, who then defended themselves. The fight went on for minutes after the verdict, and a beaten side's fresh
    reserves cut the winners down (the user saw it, 2026-11-22). StartBattle makes the sides enemies again.
    amongThemselves: only those still fighting another soldier of the battle (the looks of the aftermath; somebody
    fighting a wolf is left to it).}
    Intel_BattleSideA.SetAlly(Intel_BattleSideB)
    Int first = 0
    Int left = 1
    While left > 0 && first < 96
        ; Two a frame: ending one soldier's fight costs up to 0.17 ms on a large load order (six took 0.87 ms).
        left = IntelEngine.BattleCeaseFire(first, 2, amongThemselves)
        first += 2
        If left > 0
            Utility.WaitMenuMode(0.01)
        EndIf
    EndWhile
EndFunction

Function HandleBattleEnd(String result, String victor, String stateJson)
    Core.DebugMsg("Battle: Ended - result=" + result + ", victor=" + victor)
    ; Decided: the two sides are enemies no longer, from this frame on (the rest of the cease-fire follows in
    ; DisperseSoldiers, once the battle's books are closed).
    Intel_BattleSideA.SetAlly(Intel_BattleSideB)

    ; (No UnregisterForUpdate here: the real-time timer is shared by every script of the quest, and
    ; unregistering it stopped travel, task and schedule monitoring too. OnUpdate checks the state.)

    ; Count casualties via C++ (no Papyrus arrays needed)
    Int lossesA = IntelEngine.CountDeadBattleSoldiers("A")
    Int lossesB = IntelEngine.CountDeadBattleSoldiers("B")

    ; C++ handles ALL game logic: standings, narrative, political events, witness facts, end battle
    ; MUST run BEFORE RemovePlayerFromBattle — FinalizeBattle reads playerSide to award standing.
    String resultJson = IntelEngine.FinalizeBattle(ActiveBattleId, result, victor, \
        lossesA, lossesB, BattleLocationName, Utility.GetCurrentGameTime())
    ; The battle is closed on the native side from here on. The poll must not take that for a battle that ended
    ; behind the script's back while this function is still waiting below (it then sent everybody off a second time).
    BattleSpawned = false
    BattlePhase = 0
    If BattleSkirmish
        IntelEngine.ManifestationDone()         ; the event that was held back for it is what was just recorded
    EndIf

    ; Do NOT remove player from battle factions here — soldiers are still alive during
    ; deferred cleanup. Removing the player from the faction makes stray-hit soldiers
    ; hostile again. RemovePlayerFromBattle is called when cleanup finishes (OnUpdate Phase 0).

    ; Parse C++ result for engine-only operations (notifications, soldier moment, cleanup)
    String playerSideWas = IntelEngine.StoryResponseGetField(resultJson, "playerSideWas")
    Bool playerWon = IntelEngine.StoryResponseGetField(resultJson, "playerWon") == "true"
    ; The battle the player was called to: how they fought it is how the call ends.
    If CallBattleId >= 0 && CallFought
        If playerSideWas == ""
            EndCall(CALL_WATCHED)
        ElseIf playerSideWas != CallFaction
            EndCall(CALL_AGAINST)
        ElseIf IntelEngine.StoryResponseGetField(resultJson, "playerLeft") == "true"
            EndCall(CALL_LEFT)
        Else
            EndCall(CALL_STOOD)
        EndIf
    EndIf
    Bool drawn = IntelEngine.StoryResponseGetField(resultJson, "drawn") == "true"
    String notification = IntelEngine.StoryResponseGetField(resultJson, "notification")
    String spectatorNotif = IntelEngine.StoryResponseGetOptionalField(resultJson, "spectatorNotification")
    String witnessFact = IntelEngine.StoryResponseGetField(resultJson, "witnessFact")
    Int reward = IntelEngine.StoryResponseGetField(resultJson, "reward") as Int
    Int enemyKills = IntelEngine.StoryResponseGetField(resultJson, "enemyKills") as Int
    Bool unseen = _endedUnseen

    ; The field empties, before anything is announced: the fighting stops, the beaten run, the winners walk off.
    ; Whoever is out of sight is removed as the polls come round. (The fighting used to go on through the pause
    ; and the announcement below.)
    DisperseSoldiers(WinningSide(victor), playerSideWas != "" && !unseen)
    Actor speaker = _allyNear
    Int alliesLeft = _alliesLeft
    _allyNear = None
    ; The one who leads the player's side has the word, when they live and are near.
    Actor own = CommanderA
    If playerSideWas == BattleFactionB
        own = CommanderB
    EndIf
    If playerSideWas != "" && own != None && !own.IsDead() && own.Is3DLoaded() && own.GetDistance(Game.GetPlayer()) <= AllyComesOverDistance
        speaker = own
    EndIf
    DeferredCleanupActive = true
    DeferredCleanupStart = Utility.GetCurrentRealTime()
    Core.RequestTick(PollInterval)
    If unseen
        return          ; the player is not there: nothing to see, hear or be told
    EndIf

    ; Inject witness memories (requires Papyrus Actor handles for SkyrimNet API)
    If witnessFact != ""
        Actor player = Game.GetPlayer()
        Actor[] witnesses = IntelEngine.GetNearbyWitnessNPCs(player, 5000.0)
        Int i = 0
        While i < witnesses.Length
            If witnesses[i] != None
                Core.InjectFact(witnesses[i], witnessFact)
            EndIf
            i += 1
        EndWhile
    EndIf

    ; Brief silence between last sword strike and announcement
    Utility.Wait(2.0 + Utility.RandomFloat(0.0, 1.5))

    ; Notifications (engine-only: Debug.Notification)
    If notification != ""
        Debug.Notification(IntelEngine.L(notification))
    EndIf
    If spectatorNotif != ""
        Utility.Wait(1.5)
        Debug.Notification(IntelEngine.L(spectatorNotif))
    EndIf
    ; What the battle did for the player's name with the side they fought for.
    String promoted = IntelEngine.StoryResponseGetOptionalField(resultJson, "promoted")
    If promoted != "" && playerSideWas != ""
        Utility.Wait(1.5)
        Debug.Notification(IntelEngine.L(IntelEngine.BattleSay("promoted", playerSideWas, "", promoted)))
        Core.DebugMsg("Battle: the player rises to " + promoted + " with " + playerSideWas)
    EndIf

    ; One of the player's side comes over, and follows the others afterwards.
    If playerSideWas != ""
        String otherSide = IntelEngine.StoryResponseGetField(resultJson, "factionA")
        If playerSideWas == otherSide
            otherSide = IntelEngine.StoryResponseGetField(resultJson, "factionB")
        EndIf
        PostBattleSoldierMoment(speaker, alliesLeft, playerSideWas, otherSide, playerWon, drawn, reward, enemyKills)
    EndIf
EndFunction

; ApplyPlayerKillStanding, ApplyPostBattleStanding, ApplySpectatorConsequences,
; InjectBattleWitnessMemories — ALL moved to C++ FinalizeBattle. Deleted.

; CountDeadInArray — REMOVED. Superseded by C++ IntelEngine.CountDeadBattleSoldiers()
; CleanupActorsByProximity — REMOVED. Superseded by C++ IntelEngine.CleanupBattleSoldiers()

; =============================================================================
; CLEANUP
; =============================================================================

Function CleanupAllActors()
    {A battle that is cut short (a load, an error, its time limit): the soldiers stop fighting and walk off, and
    each one is removed where the player does not see it. This used to switch every one of them off on the spot.}
    DisperseSoldiers(0, false)
    IntelEngine.ForgetBattleSoldiers()
    If SweepSoldiers(false) > 0
        LeaveBattleSides()
        SoldiersLeaving = true
        Core.RequestTick(StragglerInterval)
    EndIf
EndFunction

Function ReleaseOldSoldiers()
    {Another battle begins while soldiers or bodies of the last one are still on the list: out of sight they go
    now, in view they are let go (no travel order, no side) and leave the game with the area.
    The last battle's aftermath ends here as well. Its wind-up, three minutes after that battle, resets the
    battle state: left running, it reset whichever battle had begun in the meantime.}
    If DeferredCleanupActive
        DeferredCleanupActive = false
        IntelEngine.ForgetBattleSoldiers()
        RemovePlayerFromBattle()
        Core.DebugMsg("Battle: the last battle's aftermath ends early, another battle begins")
    EndIf
    If SpawnedSoldierCount > 0
        SweepSoldiers(true)
    EndIf
    SoldiersLeaving = false
EndFunction

Actor[] Property SpawnedSoldiers Auto Hidden       ; every soldier spawned for the current battle (kept in the save)
Int Property SpawnedSoldierCount = 0 Auto Hidden

Actor Function SoldierFromId(Int formId)
    {A spawned actor by the id the DLL reports (created references: their ids start with FF). GetFormEx finds
    them, seen 2026-11-14 ("Kick-started 4/4 combat pairs"). Until then no id ever reached this function: the DLL
    was asked for "formIds" under another spelling and answered 0 (see JsonKeys.h), so the kick-start of the
    fighting found nobody ("Kick-started 0/6 combat pairs").}
    If formId == 0
        Return None
    EndIf
    Return Game.GetFormEx(formId) as Actor
EndFunction

Function RememberBattleSoldiers()
    {Everybody the DLL has spawned for this battle goes onto the script's own list. Only the soldiers of one rare
    path (the player arriving in the middle of a battle) used to be on it; the others were known to the DLL alone,
    so the script could neither send them off when the battle was over nor find them after the game was closed.}
    String side = "A"
    Int pass = 0
    Int missing = 0
    String ownSide = ""             ; the side the player stands with, if any: its newcomers take their stray blows too
    If PlayerBattleSide != ""
        ownSide = IntelEngine.GetFactionBattleSide(PlayerBattleSide)
    EndIf
    While pass < 2
        String json = IntelEngine.GetBattleSoldierFormIds(side)
        Int count = IntelEngine.StoryResponseGetField(json, "count") as Int
        Int i = 0
        While i < count
            Actor soldier = SoldierFromId(IntelEngine.GetJsonArrayInt(json, "formIds", i))
            If soldier == None
                missing += 1
            ElseIf !IsRemembered(soldier)
                RememberSoldier(soldier)
                If side == ownSide
                    soldier.IgnoreFriendlyHits(true)
                EndIf
            EndIf
            i += 1
        EndWhile
        side = "B"
        pass += 1
    EndWhile
    If missing > 0
        Core.DebugMsg("Battle: WARNING - " + missing + " soldiers of the battle could not be found by their id")
    EndIf
EndFunction

Bool Function IsRemembered(Actor soldier)
    If !SpawnedSoldiers
        Return false
    EndIf
    Int i = 0
    While i < SpawnedSoldierCount && i < SpawnedSoldiers.Length
        If SpawnedSoldiers[i] == soldier
            Return true
        EndIf
        i += 1
    EndWhile
    Return false
EndFunction

Bool Function HoldsActor(Actor npc)
    {Does a battle account for this NPC running one of IntelEngine's travel packages? Asked by Core's sweep of stale
    overrides. Soldiers come up to the fight and leave the field on travel orders that belong to no task slot; the
    sweep took those orders for leftovers and released them. Whoever it caught on two rounds (a game hour apart: three
    minutes of play) stopped where they stood: the beaten, who were to run, stood about among the winners and the
    dead, next to the player they had just fought (seen 2026-11-21, four Stormcloaks, all of them reserves).}
    If npc == None
        Return false
    EndIf
    If SpawnedSoldiers && SpawnedSoldiers.Find(npc) >= 0
        Return true
    EndIf
    Return ManifestActors && ManifestActors.Find(npc) >= 0
EndFunction

; ── When it is over: the field empties ──

ObjectReference Property ExitMarkerA Auto Hidden
ObjectReference Property ExitMarkerB Auto Hidden
; The towns the two armies march off toward (IntelEngine.BattleWayHome): markers of the game, never removed here.
; None: no town to march to; the exit marker above is used.
ObjectReference Property WayOffA Auto Hidden
ObjectReference Property WayOffB Auto Hidden

ObjectReference Function ExitFor(Bool sideB)
    {Where a soldier of this side goes when it is over.}
    If sideB
        If WayOffB != None
            Return WayOffB
        EndIf
        Return ExitMarkerB
    EndIf
    If WayOffA != None
        Return WayOffA
    EndIf
    Return ExitMarkerA
EndFunction
Float Property ExitDistance = 14000.0 AutoReadOnly      ; beyond the loaded area: whoever gets there is out of the world
Float Property BodyOutOfSightDistance = 5000.0 AutoReadOnly     ; nearer than this a body is not removed even off screen
Float Property WalkerOutOfSightDistance = 7000.0 AutoReadOnly   ; and a living soldier not nearer than this
Float Property AftermathInterval = 6.0 AutoReadOnly     ; seconds between sweeps while a battle's aftermath runs
Float Property StragglerInterval = 15.0 AutoReadOnly    ; and between looks at what a wound-up battle left behind
Float Property BodiesStayHours = 6.0 AutoReadOnly       ; game hours the dead stay on the field, wherever the player goes
Float Property AllyComesOverDistance = 7000.0 AutoReadOnly  ; an ally farther off than this does not come over after the battle (the whole field: at 2,500 a fight that had moved on left the player unthanked and unpaid)
Float Property AllySpeaksDistance = 350.0 AutoReadOnly  ; how near the ally has to get before the word is said
Float Property AllyStopsDistance = 220.0 AutoReadOnly   ; where he stops: a few steps off, not in the player's face
Float Property BattleEndedGameTime = 0.0 Auto Hidden    ; when the last battle's soldiers were sent off (game days)
Bool Property SoldiersLeaving = false Auto Hidden       ; a wound-up battle still has soldiers or bodies in the player's view

Int Function WinningSide(String victor)
    {1: the soldiers in battle side A won (the battle's first faction), 2: those in side B, 0: nobody.}
    If victor == ""
        Return 0
    EndIf
    If victor == BattleFactionA
        Return 1
    ElseIf victor == BattleFactionB
        Return 2
    EndIf
    Return 0
EndFunction

Actor _allyNear = None      ; the living soldier of the player's side nearest to the player, when asked for
Int _alliesLeft = 0         ; living soldiers of the player's side, when the player took one

Function DisperseSoldiers(Int winningSide, Bool findAlly)
    {The battle is over and the field empties the way a field does: the beaten run for it, the winners put their
    weapons away and walk off, each side in the direction it stands from the other. They used to be given nothing
    to do: they stood where the fighting had stopped, and three minutes later every soldier and every body was
    removed in one stroke, in front of the player. Where they are going lies beyond the loaded area, so whoever
    gets there has left the world; SweepSoldiers deals with the rest. findAlly: note the ally nearest to the
    player on the way (_allyNear, within AllyComesOverDistance), for the word after the battle.}
    Float began = Utility.GetCurrentRealTime()
    _allyNear = None
    _alliesLeft = 0
    BattleEndedGameTime = Utility.GetCurrentGameTime()
    ; First of all the fighting stops, for everybody, within a few frames; then each is sent on their way.
    CeaseFire(false)
    RememberBattleSoldiers()
    If !SpawnedSoldiers || SpawnedSoldierCount <= 0
        Return
    EndIf
    ; One living soldier of each side tells where the sides stand.
    Actor oneA = None
    Actor oneB = None
    Int i = 0
    While i < SpawnedSoldierCount && i < SpawnedSoldiers.Length && (oneA == None || oneB == None)
        Actor candidate = SpawnedSoldiers[i]
        If candidate != None && !candidate.IsDead()
            If candidate.IsInFaction(Intel_BattleSideB)
                If oneB == None
                    oneB = candidate
                EndIf
            ElseIf oneA == None
                oneA = candidate
            EndIf
        EndIf
        i += 1
    EndWhile
    If oneA == None && oneB == None
        Return
    EndIf
    ; The middle of the field, and the direction side A leaves in; side B takes the opposite one.
    Actor player = Game.GetPlayer()
    Float cx = 0.0
    Float cy = 0.0
    Float z = 0.0
    Float dx = 0.0
    Float dy = 0.0
    If oneA != None && oneB != None
        cx = (oneA.GetPositionX() + oneB.GetPositionX()) / 2.0
        cy = (oneA.GetPositionY() + oneB.GetPositionY()) / 2.0
        z = oneA.GetPositionZ()
        dx = oneA.GetPositionX() - oneB.GetPositionX()
        dy = oneA.GetPositionY() - oneB.GetPositionY()
    ElseIf oneA != None
        cx = oneA.GetPositionX()
        cy = oneA.GetPositionY()
        z = oneA.GetPositionZ()
        dx = cx - player.GetPositionX()          ; one side left: away from the player
        dy = cy - player.GetPositionY()
    Else
        cx = oneB.GetPositionX()
        cy = oneB.GetPositionY()
        z = oneB.GetPositionZ()
        dx = player.GetPositionX() - cx
        dy = player.GetPositionY() - cy
    EndIf
    Float span = Math.sqrt(dx * dx + dy * dy)
    If span < 50.0
        dx = Math.Sin(player.GetAngleZ())        ; on top of each other: the way the player is facing, and its opposite
        dy = Math.Cos(player.GetAngleZ())
        span = 1.0
    EndIf
    dx = dx / span
    dy = dy / span

    Form xmarkerBase = Game.GetFormFromFile(0x0000003B, "Skyrim.esm")
    If !xmarkerBase
        Return
    EndIf
    ClearExitMarkers()
    ExitMarkerA = player.PlaceAtMe(xmarkerBase)
    ExitMarkerA.SetPosition(cx + dx * ExitDistance, cy + dy * ExitDistance, z)
    ExitMarkerB = player.PlaceAtMe(xmarkerBase)
    ExitMarkerB.SetPosition(cx - dx * ExitDistance, cy - dy * ExitDistance, z)
    ; Each army marches off toward a town, by the roads: a point in a straight line may lie in a mountain, and then
    ; nobody took a step (the exit markers stay for where there is no town to march to).
    WayOffA = IntelEngine.BattleWayHome(BattleFactionA, cx, cy, dx, dy, winningSide == 2, None)
    WayOffB = IntelEngine.BattleWayHome(BattleFactionB, cx, cy, -dx, -dy, winningSide == 1, WayOffA)

    Int leavingA = 0
    Int leavingB = 0
    Float nearest = AllyComesOverDistance
    Bool playerOnB = PlayerBattleSide != "" && PlayerBattleSide == BattleFactionB
    i = 0
    While i < SpawnedSoldierCount && i < SpawnedSoldiers.Length
        Actor soldier = SpawnedSoldiers[i]
        If soldier != None && !soldier.IsDead()
            Bool sideB = soldier.IsInFaction(Intel_BattleSideB)
            Bool beaten = (winningSide == 1 && sideB) || (winningSide == 2 && !sideB)
            ; Whoever was held in line at the muster may move again.
            soldier.SetDontMove(false)
            If sideB
                SendSoldierOff(soldier, ExitFor(true), beaten)
                leavingB += 1
            Else
                SendSoldierOff(soldier, ExitFor(false), beaten)
                leavingA += 1
            EndIf
            If findAlly && sideB == playerOnB
                Float distance = soldier.GetDistance(player)
                If distance < nearest
                    nearest = distance
                    _allyNear = soldier
                EndIf
            EndIf
        EndIf
        i += 1
    EndWhile
    _alliesLeft = leavingA
    If playerOnB
        _alliesLeft = leavingB
    EndIf
    ; Whoever took a blow while the orders went round and turned on the one who dealt it.
    CeaseFire(true)
    Core.DebugMsg("Battle: the field empties - " + leavingA + " soldiers leave one way, " + leavingB + " the other (" + \
        (Utility.GetCurrentRealTime() - began) + " s)")
EndFunction

Function CalmSoldier(Actor soldier)
    {No more fighting for this one: weapon away. Not in the middle of a killing blow, dealt or taken (the two are held
    in one animation, and whoever is taken out of it leaves the other hanging in the air), and not somebody who is
    down and bleeding. The next look of the aftermath finds them.}
    If soldier.IsInKillMove() || soldier.IsBleedingOut()
        Return
    EndIf
    soldier.SetActorValue("Aggression", 0.0)
    soldier.StopCombat()
    soldier.StopCombatAlarm()
    soldier.SheatheWeapon()
EndFunction

Function SendSoldierOff(Actor soldier, ObjectReference exit, Bool running)
    {Weapon away, and off they go. The beaten run. Sending somebody off a second time leaves one travel order.
    Somebody who is down and bleeding, or in the middle of a killing blow, gets no order now: the wounded were sent
    off with everybody else and slid away over the ground as they lay ("Why are dead bodies floating? Are they trying
    to run away too?", the user, 2026-11-22). They stand when they are up again, and StandingAbout sends them.}
    If soldier.IsInKillMove() || soldier.IsBleedingOut()
        Return
    EndIf
    CalmSoldier(soldier)
    TakeBackTravelOrder(soldier)
    Package pace = Core.TravelPackage_Walk
    If running
        pace = Core.TravelPackage_Run
    EndIf
    pace = PaceFor(soldier, pace, Core.TravelPackage_Jog)
    PO3_SKSEFunctions.SetLinkedRef(soldier, exit, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(soldier, pace, Core.PRIORITY_TRAVEL, 1)
    soldier.EvaluatePackage()
EndFunction

Function PaySentOn(String side, Int reward)
    {The pay of a battle won when nobody of the player's side can bring it over: none left standing, none near, or
    the one who set out did not get there. It is sent on, and the player is told so. (It used to be lost without a
    word: a battle won, fought in from the back of the field, and nothing for it.)}
    If reward <= 0
        Return
    EndIf
    Game.GetPlayer().AddItem(Game.GetFormFromFile(0x0000000F, "Skyrim.esm"), reward, true)
    Debug.Notification(IntelEngine.L(IntelEngine.BattleSay("pay_sent", side, "", "", reward)))
    Core.DebugMsg("Battle: nobody could bring the pay over - " + reward + " gold sent on to the player")
EndFunction

String Function PaceName(Package order)
    {What somebody is doing, for the log: which of our own orders, or another package altogether.}
    If order == None
        Return "nothing"
    ElseIf order == Core.TravelPackage_Walk
        Return "walk"
    ElseIf order == Core.TravelPackage_Jog
        Return "jog"
    ElseIf order == Core.TravelPackage_Run
        Return "run"
    ElseIf order == FollowPackage()
        Return "follow"
    EndIf
    Return "another package " + order
EndFunction

Package Function PaceFor(Actor soldier, Package wanted, Package instead)
    {The travel package to give somebody a new order with. The game does not begin a package anew for somebody who is
    on it already: with the old order taken back and the same one given again, to another place, they went on to
    where the old one led and stood there. That is what the reserves did who had run up on the run package and were
    told to run for it: the last to come stood about on the field of a lost battle (seen 2026-11-21, twice). So
    whoever comes, comes at a jog, whoever leaves, at a walk or a run, and nobody is ever given the package they
    are on: they get the other one.}
    If soldier.GetCurrentPackage() == wanted
        Return instead
    EndIf
    Return wanted
EndFunction

Function TurnTo(Actor who, ObjectReference whom)
    {Somebody turns to face another where they stand, at the pace a man turns. (One who was already beside the
    player when it was over spoke his word side-on, looking past them: seen 2026-11-21.)}
    Float off = who.GetHeadingAngle(whom)
    If off > -25.0 && off < 25.0
        Return
    EndIf
    Float turn = off
    If turn < 0.0
        turn = -turn
    EndIf
    ; A step's breadth toward them while turning: a translation that goes nowhere may turn all at once.
    Float facing = who.GetAngleZ() + off
    who.TranslateTo(who.GetPositionX() + 3.0 * Math.Sin(facing), who.GetPositionY() + 3.0 * Math.Cos(facing), who.GetPositionZ(), \
        0.0, 0.0, facing, 3.0 / (turn / 240.0 + 0.1), 240.0)
    Utility.Wait(turn / 240.0 + 0.15)
    who.StopTranslation()
EndFunction

Package _followPackage = None

Package Function FollowPackage()
    {IntelEngine's own follow-the-player package (IntelEngine_FollowPlayerTaskPackage): for the soldiers who keep by
    the player in a battle.}
    If _followPackage == None
        _followPackage = Game.GetFormFromFile(0x00001836, "IntelEngine.esp") as Package
    EndIf
    Return _followPackage
EndFunction

Function TakeBackTravelOrder(Actor soldier)
    {The travel order is stored under the soldier's id, outside the soldier. It has to be gone before the soldier
    is: the id of a deleted reference is handed out again, and whoever gets it would walk off with the order.}
    ActorUtil.RemovePackageOverride(soldier, Core.TravelPackage_Walk)
    ActorUtil.RemovePackageOverride(soldier, Core.TravelPackage_Jog)
    ActorUtil.RemovePackageOverride(soldier, Core.TravelPackage_Run)
    Package follow = FollowPackage()
    If follow != None
        ActorUtil.RemovePackageOverride(soldier, follow)
    EndIf
EndFunction

Int Function OutOfSight(Actor soldier, Actor player, Bool bodiesStay)
    {May this soldier, alive or dead, leave the world without the player noticing? 0: no. 1: yes, not loaded (the
    player went indoors or away, or the soldier walked out of the loaded area). 2: yes, far off and not on screen
    (for the player, HasLOS is true only for what is in view). Far off is farther for the living: somebody the
    player watched walking away should still be there after a glance to the side.
    bodiesStay: the battle is not long over, and the dead stay where they fell whatever the player does. Half a
    minute inside a house used to be enough to come back to a field without a single body.}
    If bodiesStay && soldier.IsDead()
        Return 0
    EndIf
    If !soldier.Is3DLoaded()
        Return 1
    EndIf
    Float distance = soldier.GetDistance(player)
    If distance <= BodyOutOfSightDistance
        Return 0
    EndIf
    If distance <= WalkerOutOfSightDistance && !soldier.IsDead()
        Return 0
    EndIf
    If player.HasLOS(soldier)
        Return 0
    EndIf
    Return 2
EndFunction

Float _sweepDueAt = 0.0
Bool _sweeping = false
Actor _speaker = None       ; the one who has come over for a word: he stands because he is speaking


Int Function StandingAbout(Actor soldier, Actor player)
    {Somebody who was sent off and stands. Each look of the aftermath notes where he is; if he has not moved since
    the last one he is told again, another way each time (the order had not taken, or the way to the town cannot be
    walked from where he got to); if nothing gets him moving he rests where he is, and leaves the game with
    everybody else once the player has gone from there. Always returns 0: nobody loaded is taken away.
    (Three stood on a field at two and at five minutes after a battle on the full mod list, 2026-11-21: one on the
    travel order without taking a step, one whose order had not taken, one held by a talk.)}
    If soldier == _speaker || soldier.IsInCombat() || soldier.IsBleedingOut()
        Return 0
    EndIf
    Float x = soldier.GetPositionX()
    Float y = soldier.GetPositionY()
    Float wasX = StorageUtil.GetFloatValue(soldier, "Intel_BattleAtX", -90000000.0)
    Float wasY = StorageUtil.GetFloatValue(soldier, "Intel_BattleAtY", -90000000.0)
    StorageUtil.SetFloatValue(soldier, "Intel_BattleAtX", x)
    StorageUtil.SetFloatValue(soldier, "Intel_BattleAtY", y)
    If wasX < -80000000.0
        Return 0                ; the first look at him
    EndIf
    If Math.sqrt((x - wasX) * (x - wasX) + (y - wasY) * (y - wasY)) >= 150.0
        StorageUtil.UnsetIntValue(soldier, "Intel_BattleStood")
        Return 0
    EndIf
    Int stood = StorageUtil.GetIntValue(soldier, "Intel_BattleStood") + 1
    StorageUtil.SetIntValue(soldier, "Intel_BattleStood", stood)
    If stood == 5
        ; Two ways off tried and he has not taken a step: there is no way out of where he got to (a fenced garden, a
        ; ledge). He stops trying and rests there, as a man does after a battle, until nobody looks.
        TakeBackTravelOrder(soldier)
        If Core.SandboxPackage != None
            ActorUtil.AddPackageOverride(soldier, Core.SandboxPackage, Core.PRIORITY_SANDBOX, 1)
        EndIf
        soldier.EvaluatePackage()
        Core.DebugMsg("Battle: " + soldier + " cannot get away from where he is - he rests there")
    EndIf
    If stood == 2 || stood == 4
        Bool sideB = soldier.IsInFaction(Intel_BattleSideB)
        ObjectReference way = ExitFor(sideB)
        If stood == 4 && !player.HasLOS(soldier)
            ; Caught on something (a fence's corner, a rock): a step aside while nobody looks sets him free. (The one in
            ; the cabbage patch walked off as soon as somebody brushed against him.)
            soldier.MoveTo(soldier, Utility.RandomFloat(-120.0, 120.0), Utility.RandomFloat(-120.0, 120.0), 40.0, false)
        EndIf
        If stood != 2
            ; The way to the town cannot be walked from here: straight off the field instead, or the other way round.
            ObjectReference straight = ExitMarkerA
            If sideB
                straight = ExitMarkerB
            EndIf
            If straight != None && (stood == 4 || way == None)
                way = straight
            EndIf
        EndIf
        If way != None
            Core.DebugMsg("Battle: " + soldier + " stands (" + stood + " looks, on " + PaceName(soldier.GetCurrentPackage()) + \
                ") - sent off again")
            SendSoldierOff(soldier, way, false)
        EndIf
    EndIf
    Return 0
EndFunction

Function ForgetStanding(Actor soldier)
    {What was noted about where a soldier stood goes with him: the id of a deleted reference is handed out again.}
    StorageUtil.UnsetFloatValue(soldier, "Intel_BattleAtX")
    StorageUtil.UnsetFloatValue(soldier, "Intel_BattleAtY")
    StorageUtil.UnsetIntValue(soldier, "Intel_BattleStood")
    If Core.SandboxPackage != None
        ActorUtil.RemovePackageOverride(soldier, Core.SandboxPackage)
    EndIf
EndFunction

Bool Function SweepDue(Float interval)
    {Is it time for the next sweep? (The update timer is shared by every script of the quest, so this handler
    runs far more often than the battle asks for.)}
    Float now = Utility.GetCurrentRealTime()
    If now < _sweepDueAt && _sweepDueAt - now <= interval       ; a stamp from an earlier session lies far ahead
        Return false
    EndIf
    _sweepDueAt = now + interval
    Return true
EndFunction

Function LeaveBattleSides()
    {The battle is wound up with soldiers still in view: they belong to no side any more, so nobody of theirs
    turns on the player, who has just left the battle sides too.}
    If !SpawnedSoldiers
        Return
    EndIf
    Int i = 0
    While i < SpawnedSoldierCount && i < SpawnedSoldiers.Length
        Actor soldier = SpawnedSoldiers[i]
        If soldier != None && !soldier.IsDead()
            soldier.RemoveFromFaction(Intel_BattleSideA)
            soldier.RemoveFromFaction(Intel_BattleSideB)
        EndIf
        i += 1
    EndWhile
EndFunction

Function ClearExitMarkers()
    WayOffA = None          ; the game's own markers: forgotten, never removed
    WayOffB = None
    RetireMarker(ExitMarkerA)
    ExitMarkerA = None
    RetireMarker(ExitMarkerB)
    ExitMarkerB = None
EndFunction

Function RememberSoldier(Actor soldier)
    {The native side keeps the list of spawned soldiers in memory only. After the game was closed and a
    save from the middle of a battle (or of its aftermath) is loaded, that list is empty: the cleanup on
    load then found nobody, and up to 44 soldiers stayed in the world for good, still in the two battle
    factions. This copy is stored with the save.}
    If !SpawnedSoldiers || SpawnedSoldiers.Length != 64
        SpawnedSoldiers = new Actor[64]
        SpawnedSoldierCount = 0
    EndIf
    If soldier != None && SpawnedSoldierCount < 64
        SpawnedSoldiers[SpawnedSoldierCount] = soldier
        SpawnedSoldierCount += 1
    EndIf
EndFunction

Int Function SweepSoldiers(Bool letGo)
    {Every soldier and every body of the battle that the player does not see leaves the game; the others stay on
    the list for the next round. Returns how many are still on it. Nobody is taken away in view: this used to
    switch all of them off at once, three minutes after the battle, wherever the player was looking. The dead
    are not taken away at all for BodiesStayHours.
    letGo: the list is needed for another battle. Whoever is in view is released instead: no travel order, no
    side, marked for removal, which the game carries out when the area unloads.}
    If !SpawnedSoldiers
        SpawnedSoldierCount = 0
        Return 0
    EndIf
    If _sweeping
        Return SpawnedSoldierCount           ; one sweep at a time: the calls below let other events in
    EndIf
    _sweeping = true
    Float began = Utility.GetCurrentRealTime()
    Actor player = Game.GetPlayer()
    Float hoursSince = (Utility.GetCurrentGameTime() - BattleEndedGameTime) * 24.0
    Bool bodiesStay = !letGo && hoursSince >= 0.0 && hoursSince < BodiesStayHours
    Int listed = SpawnedSoldierCount
    Int unloaded = 0
    Int released = 0
    Int kept = 0
    Int i = 0
    While i < listed && i < SpawnedSoldiers.Length
        Actor soldier = SpawnedSoldiers[i]
        SpawnedSoldiers[i] = None
        If soldier != None && !soldier.IsDeleted()
            Int unseen = OutOfSight(soldier, player, bodiesStay)
            If unseen != 1 && !letGo && !soldier.IsDead()
                StandingAbout(soldier, player)
            EndIf
            ; Only what is out of the loaded area is taken away. Somebody whose body the game still holds, however far
            ; off and unseen, is left to walk out of it: switching a loaded body off and deleting it takes its
            ; skeleton apart under the hands of whatever else is working on it. On a big mod list that crashed the
            ; game inside the hair-and-cloth physics eighteen seconds after a soldier 2,500 units off was removed
            ; (2026-11-21; it had been done from 7,000 units since 3.8.1).
            If unseen == 1
                TakeBackTravelOrder(soldier)
                ForgetStanding(soldier)
                soldier.DisableNoWait()
                soldier.Delete()
                unloaded += 1
            ElseIf letGo
                TakeBackTravelOrder(soldier)
                ForgetStanding(soldier)
                If !soldier.IsDead()
                    soldier.SetActorValue("Aggression", 0.0)
                    soldier.StopCombat()
                    soldier.RemoveFromFaction(Intel_BattleSideA)
                    soldier.RemoveFromFaction(Intel_BattleSideB)
                    soldier.EvaluatePackage()
                EndIf
                soldier.Delete()
                released += 1
            Else
                SpawnedSoldiers[kept] = soldier
                kept += 1
            EndIf
        EndIf
        i += 1
    EndWhile
    ; Soldiers remembered while this was running (another battle spawning) sit behind the old end of the list.
    While i < SpawnedSoldierCount && i < SpawnedSoldiers.Length
        Actor late = SpawnedSoldiers[i]
        SpawnedSoldiers[i] = None
        If late != None
            SpawnedSoldiers[kept] = late
            kept += 1
        EndIf
        i += 1
    EndWhile
    SpawnedSoldierCount = kept
    _sweeping = false
    If unloaded + released > 0
        Core.DebugMsg("Battle: removed - " + unloaded + " that had left the loaded area; " + released + " let go; " + kept + \
            " stay (" + (Utility.GetCurrentRealTime() - began) + " s)")
    EndIf
    Return kept
EndFunction

; CleanupActorArray — REMOVED. C++ ForceCleanupAllSoldiers handles all cleanup.

Function CleanupMarkers(Bool keepExits = false)
    RetireMarker(CenterMarker)
    CenterMarker = None
    RetireMarker(RallyMarkerA)
    RallyMarkerA = None
    RetireMarker(RallyMarkerB)
    RallyMarkerB = None
    If !keepExits
        ClearExitMarkers()
    EndIf
EndFunction

; Markers that are out of use. A travel order holds the marker it leads to by a bare pointer: deleting a marker under
; a soldier still walking to it crashed the game twice at the end of a skirmish (2026-11-18; found and first mended
; by Gerkinfeltser, pull request #29: the old exit markers were deleted before the soldiers of an earlier fight had
; been sent to the new ones). Here no marker of a battle is deleted when it goes out of use. It is put aside, and
; deleted once it has rested a while (a soldier whose order was just taken back is still on it until the game has
; given him something else to do) and no soldier on the list is linked to it any more.
ObjectReference[] _retired
Float[] _retiredAt
Int _retiredCount = 0
Float _retiredLooked = 0.0
Float Property MarkerRestSeconds = 10.0 AutoReadOnly

Function RetireMarker(ObjectReference marker)
    If marker == None
        Return
    EndIf
    If !_retired || _retired.Length != 16
        _retired = new ObjectReference[16]
        _retiredAt = new Float[16]
        _retiredCount = 0
    EndIf
    If _retired.Find(marker) >= 0
        Return
    EndIf
    Float now = Utility.GetCurrentRealTime()
    Int slot = _retired.Find(None)
    If slot < 0
        ; Sixteen waiting (never seen): the one that has waited longest goes, after everybody was taken off it.
        slot = 0
        Int k = 1
        While k < _retired.Length
            If _retiredAt[k] < _retiredAt[slot]
                slot = k
            EndIf
            k += 1
        EndWhile
        TakeEverybodyOff(_retired[slot])
        _retired[slot].DisableNoWait()
        _retired[slot].Delete()
        _retiredCount -= 1
    EndIf
    _retired[slot] = marker
    _retiredAt[slot] = now
    _retiredCount += 1
    Core.RequestTick(MarkerRestSeconds + 1.0)
EndFunction

Function DeleteRetiredMarkers()
    {Called from every update while markers wait: deletes those that have rested and that nobody walks to.}
    If !_retired || _retiredCount <= 0
        _retiredCount = 0
        Return
    EndIf
    Float now = Utility.GetCurrentRealTime()
    If now >= _retiredLooked && now - _retiredLooked < 3.0
        Return
    EndIf
    _retiredLooked = now
    Int waiting = 0
    Int removed = 0
    Int i = 0
    While i < _retired.Length
        ObjectReference marker = _retired[i]
        If marker != None
            ; (The real-time clock starts again with the game: a marker put aside before a load has rested.)
            Float rested = now - _retiredAt[i]
            If (rested >= MarkerRestSeconds || rested < 0.0) && !SomebodyOnTheWayTo(marker)
                _retired[i] = None
                marker.DisableNoWait()
                marker.Delete()
                removed += 1
            Else
                waiting += 1
            EndIf
        EndIf
        i += 1
    EndWhile
    _retiredCount = waiting
    If removed > 0
        Core.DebugMsg("Battle: " + removed + " markers nobody walks to any more are removed; " + waiting + " still wait")
    EndIf
    If waiting > 0
        Core.RequestTick(MarkerRestSeconds)
    EndIf
EndFunction

Bool Function SomebodyOnTheWayTo(ObjectReference marker)
    If !SpawnedSoldiers || marker == None
        Return false
    EndIf
    Int i = 0
    While i < SpawnedSoldierCount && i < SpawnedSoldiers.Length
        Actor soldier = SpawnedSoldiers[i]
        If soldier != None && !soldier.IsDead() && soldier.GetLinkedRef(Core.IntelEngine_TravelTarget) == marker
            Return true
        EndIf
        i += 1
    EndWhile
    Return false
EndFunction

Function TakeEverybodyOff(ObjectReference marker)
    If !SpawnedSoldiers || marker == None
        Return
    EndIf
    Int i = 0
    While i < SpawnedSoldierCount && i < SpawnedSoldiers.Length
        Actor soldier = SpawnedSoldiers[i]
        If soldier != None && soldier.GetLinkedRef(Core.IntelEngine_TravelTarget) == marker
            TakeBackTravelOrder(soldier)
            PO3_SKSEFunctions.SetLinkedRef(soldier, None, Core.IntelEngine_TravelTarget)
            If !soldier.IsDead()
                soldier.EvaluatePackage()
            EndIf
        EndIf
        i += 1
    EndWhile
EndFunction

Function ResetState()
    ; Always reset C++ state first — prevents "battle system busy" blocking all systems
    IntelEngine.ResetBattleState()

    BattleFactionA = ""
    BattleFactionB = ""
    BattleWarId = 0
    ScheduledBattleTime = 0.0
    BattleScheduled = false
    BattleSpawned = false
    ActiveBattleId = -1
    BattleLocationName = ""
    BattleSpawnAnchor = None
    CurrentWave = 0
    ActualBattleStartTime = 0.0
    BattleStartRealTime = 0.0
    PlayerBattleSide = ""
    QuestAutoJoinFaction = ""
    BattlePhase = 0
    MusterStartRealTime = 0.0
    MusterSeenRealTime = 0.0
    CommanderA = None
    CommanderB = None
    PlayerWasHailed = false
    _warnedOff = false
    _goneSince = 0.0
    _waveBusy = false
    _tending = false
    _endedUnseen = false
    _markedEnemyOf = ""
    BattleSkirmish = false
    BattleLineSize = GetWaveSoldierCount(1)
    ; Revert battle leader's Protected flag and SpeedMult
    If BattleLeader != None
        BattleLeader.SetActorValue("SpeedMult", 100.0)
        If !BattleLeaderWasEssential
            IntelEngine.SetActorProtected(BattleLeader, false)
        EndIf
        BattleLeader = None
        BattleLeaderWasEssential = false
    EndIf
    DeferredCleanupActive = false
    DeferredCleanupStart = 0.0
    ; No Unregister here: update timers are per-quest and shared by every IntelEngine script,
    ; so unregistering stopped Story/NPC/Politics ticks after a battle. Battle only uses
    ; single updates, and its handlers return when nothing is active.
EndFunction

; =============================================================================
; POLITICAL EVENT MANIFESTATION (micro-encounters)
; =============================================================================

Function ManifestEvent(String manifestJson)
    {A political event that can be seen near the player: an attempt on a leader's life, or a skirmish (a brawl is a
    small one). The DLL holds the event back, unrecorded, until this says how it went; whatever cannot be shown
    after all is told as it was written (ManifestationFailed).}
    If !IntelEngine.IsPoliticsEnabled()
        Core.DebugMsg("Battle: no event shown: politics is switched off")
        IntelEngine.ManifestationFailed()
        return
    EndIf
    ; Safety: if ManifestActive is stuck for > 2 minutes (stale save state), force-clear it
    If ManifestActive
        Float stuckTime = Utility.GetCurrentRealTime() - ManifestStartTime
        If stuckTime > 120.0
            Core.DebugMsg("Battle: ManifestActive stuck for " + stuckTime + "s - force-clearing")
            CleanupManifestation(false)
        Else
            Core.DebugMsg("Battle: Cannot manifest - manifestation already active (" + stuckTime + "s)")
            IntelEngine.ManifestationFailed()
            return
        EndIf
    EndIf
    If IntelEngine.IsBattleActive() || BattlePhase != 0
        Core.DebugMsg("Battle: Cannot manifest - battle active")
        IntelEngine.ManifestationFailed()
        return
    EndIf
    If Core != None && Core.StoryEngine != None && Core.StoryEngine.FactionAmbushActive
        Core.DebugMsg("Battle: Cannot manifest - faction ambush already active")
        IntelEngine.ManifestationFailed()
        return
    EndIf

    String eventType = IntelEngine.StoryResponseGetField(manifestJson, "event_type")
    String attackerFaction = IntelEngine.StoryResponseGetField(manifestJson, "attacker_faction")
    String targetFaction = IntelEngine.StoryResponseGetField(manifestJson, "target_faction")
    Int spawnCount = IntelEngine.StoryResponseGetField(manifestJson, "spawn_count") as Int
    If attackerFaction == "" || targetFaction == ""
        IntelEngine.ManifestationFailed()
        return
    EndIf

    ; A skirmish, or a brawl: a small battle. A handful of each side meet on a field out of the player's way and go
    ; at each other. (They used to be made around the player: one band 800 units in front of their eyes, the other
    ; behind their back.)
    If eventType != "assassination_attempt"
        If StartSkirmish(attackerFaction, targetFaction, spawnCount)
            IntelEngine.ConfirmManifestationCooldown()
        Else
            Core.DebugMsg("Battle: no ground here for a skirmish between " + attackerFaction + " and " + targetFaction)
            IntelEngine.ManifestationFailed()
        EndIf
        return
    EndIf

    ; An attempt on a leader's life.
    Actor player = Game.GetPlayer()
    ManifestActors = new Actor[12]
    ManifestCount = 0
    ManifestLeaderTarget = None
    ManifestAssassinAttacked = false
    ManifestAssassinStruck = false
    _assassinReported = false
    If PlayerBattleSide == ""
        player.RemoveFromFaction(Intel_BattleSideA)
        player.RemoveFromFaction(Intel_BattleSideB)
    EndIf

    ; The DLL picks the leader and makes the killer where the player does not see them appear: beyond a door of the
    ; room, or out of sight out of doors.
    Actor assassin = IntelEngine.ExecuteAssassination(targetFaction, attackerFaction)
    If assassin == None
        Core.DebugMsg("Battle: no attempt on a leader of " + targetFaction + " can be shown here")
        IntelEngine.ManifestationFailed()
        return
    EndIf
    ; Made in one frame, set down where they come from in the next (see SettleSoldiers). Nothing is left when it went
    ; well; the killer's own id when the ground they were to start from is no longer there.
    Utility.WaitMenuMode(0.03)
    String unsettled = IntelEngine.BattleSettle()
    If unsettled != ""
        DropOrphans(unsettled)
        Core.DebugMsg("Battle: the killer could not be set down where they were to come from")
        IntelEngine.ManifestationFailed()
        return
    EndIf
    Actor assTarget = IntelEngine.GetAssassinationTarget()
    String leaderName = IntelEngine.GetAssassinationLeaderName()
    Int slot = -1
    If assTarget != None
        slot = Core.ClaimFreeAgentSlot()
    EndIf
    If assTarget == None || slot < 0
        Core.DebugMsg("Battle: the attempt cannot go ahead (target " + assTarget + ", slot " + slot + ")")
        assassin.DisableNoWait()
        assassin.Delete()
        IntelEngine.ManifestationFailed()
        return
    EndIf

    ManifestLeaderTarget = assTarget
    _assassinTargetFaction = targetFaction
    _assassinAttackerFaction = attackerFaction
    _assassinLeaderName = leaderName
    ManifestActors[0] = assassin
    ManifestCount = 1
    ; Nobody knows who this is. (They carried the name of what they were made from: a "Bandit" walked into Jorrvaskr.)
    assassin.SetDisplayName(IntelEngine.BattleSay("stranger"), true)
    assassin.EnableNoWait(true)

    ; Allocate slot — assigns quest alias + task faction (makes travel packages work)
    Core.AllocateSlot(slot, assassin, "assassination", leaderName, 0, "Politics")
    ; Intel_DestMarker is required for Travel.CheckForArrival to detect proximity
    StorageUtil.SetFormValue(assassin, "Intel_DestMarker", assTarget as ObjectReference)
    PO3_SKSEFunctions.SetLinkedRef(assassin, assTarget, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(assassin, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
    Utility.Wait(0.1)
    assassin.EvaluatePackage()
    Core.DebugMsg("Battle: a killer (" + assassin.GetDisplayName() + ") is on the way to " + leaderName + " (slot " + slot + ", " + \
        assassin.GetDistance(assTarget) + " units)")
    ; Travel system monitors arrival → calls OnArrival → HandleAssassinArrival

    ManifestActive = true
    ManifestStartTime = Utility.GetCurrentRealTime()
    Core.RequestTick(PollInterval)
EndFunction

Bool Function StartSkirmish(String attacker, String target, Int size)
    {A handful of two factions meet on a field near the player. False: no ground for it here and now.}
    If IntelEngine.IsBattleActive() || BattlePhase != 0
        Return false
    EndIf
    If size < 2
        size = 2
    ElseIf size > 6
        size = 6
    EndIf
    BattleFactionA = attacker
    BattleFactionB = target
    BattleWarId = IntelEngine.GetActiveWarId(attacker, target)
    BattleLocationName = ""
    BattleSpawnAnchor = None
    QuestAutoJoinFaction = ""
    BattleScheduled = false
    BattleSpawned = false
    BattleSkirmish = true
    BattleLineSize = size
    If !StartBattleSequence()
        ForgetBattleNames()
        Return false
    EndIf
    Return true
EndFunction

String Function AssassinationResult()
    {How the attempt on the leader's life ended, as it is to be seen now.}
    Actor striker = ManifestActors[0]
    Actor leader = ManifestLeaderTarget
    Actor player = Game.GetPlayer()
    If leader != None && leader.IsDead()
        If leader.GetKiller() == player
            Return "slain_by_player"
        EndIf
        Return "killed"
    EndIf
    If striker == None || striker.IsDead()
        If striker != None && striker.GetKiller() == player
            If ManifestAssassinStruck
                Return "saved"
            EndIf
            Return "foiled"
        EndIf
        Return "failed"
    EndIf
    Return "escaped"
EndFunction

ObjectReference Function PlaceSpawnMarker(Actor player, Float angle, Float dist)
    {A throw-away XMarker at this bearing and distance from the player, for soldiers to be created at.
    None when it cannot be made: the caller then spawns at the player, as before. The caller deletes it.}
    Form xmarkerBase = Game.GetFormFromFile(0x0000003B, "Skyrim.esm")
    If !xmarkerBase
        return None
    EndIf
    ObjectReference marker = player.PlaceAtMe(xmarkerBase)
    If marker
        marker.MoveTo(player, Math.Sin(angle) * dist, Math.Cos(angle) * dist, 0.0)
    EndIf
    return marker
EndFunction

; Called by Travel.OnArrival when an assassination task NPC reaches their target.
; The assassin walked there via the task system — now trigger the attack.
Function HandleAssassinArrival(Actor assassin, String targetName)
    ; Re-entrancy guard — prevents double-fire from Travel.OnArrival + OnUpdate hard timeout
    If ManifestAssassinAttacked
        return
    EndIf
    ManifestAssassinAttacked = true
    ManifestAssassinStruck = false
    ManifestAssassinArrivedAt = Utility.GetCurrentRealTime()

    Core.DebugMsg("Battle: Assassin " + assassin.GetDisplayName() + " reached " + targetName + " - beginning buildup")

    Actor player = Game.GetPlayer()
    Actor target = ManifestLeaderTarget

    ; Phase 1: Assassin lingers near the leader (tailing). A nearby NPC senses something off.
    If target != None
        Actor[] nearbyNPCs = IntelEngine.GetNearbyWitnessNPCs(player, 2000.0)
        Actor witness = None
        Int ni = 0
        While ni < nearbyNPCs.Length && witness == None
            If nearbyNPCs[ni] != None && nearbyNPCs[ni] != target && nearbyNPCs[ni] != assassin
                witness = nearbyNPCs[ni]
            EndIf
            ni += 1
        EndWhile
        If witness != None
            SkyrimNetApi.DirectNarration("spotted a suspicious stranger lingering near " + targetName + " and grew uneasy", witness, player)
        EndIf
    EndIf

    ; Phase 2: Dramatic pause — assassin keeps tailing, tension builds
    Utility.Wait(Utility.RandomFloat(5.0, 8.0))

    ; Cleaned up during the pause (a reload, the reset button, the stale-state guard): the assassin is no
    ; longer tracked, and a strike now would leave an attacker that nothing ever removes.
    If !ManifestActive || ManifestActors[0] != assassin
        Core.DebugMsg("Battle: Assassination dropped - the manifestation was cleaned up during the pause")
        return
    EndIf

    ; Phase 3: Attack
    If assassin.IsDead() || target == None || target.IsDead()
        Core.DebugMsg("Battle: Assassination aborted - assassin or target dead")
        CleanupManifestation()
        return
    EndIf
    ; The leader may have left during the walk and the pause (gone to bed behind a door, disabled by a
    ; quest). An attack on somebody who is not there left an armed stranger with nobody to fight.
    If !AssassinCanReach(assassin, target)
        Core.DebugMsg("Battle: Assassination aborted - " + targetName + " is out of reach")
        CleanupManifestation()
        return
    EndIf

    ; C++ sets aggression + combat target; Papyrus StartCombat initiates AI
    IntelEngine.TriggerAssassinationAttack()
    assassin.StartCombat(target)
    ManifestAssassinStruck = true

    ; The blow, as an event of the game for SkyrimNet. What people remember of it is given when it is over, with
    ; how it ended (CleanupManifestation): at this point they used to be given "witnessed an assassination attempt"
    ; and nothing of the outcome. The witness is somebody near the victim (not near the player: someone two rooms
    ; from the attack "witnessed" it because the player stood by them, Jorrvaskr, 2026-11-13).
    String infiltrationFact = "witnessed an assassination attempt on " + targetName
    Actor[] witnesses = IntelEngine.GetNearbyWitnessNPCs(target, 2000.0)
    Actor eventWitness = player
    Int wi = 0
    While wi < witnesses.Length
        If witnesses[wi] != None && witnesses[wi] != target
            eventWitness = witnesses[wi]
            wi = witnesses.Length
        EndIf
        wi += 1
    EndWhile
    SkyrimNetApi.RegisterEvent("political_assassination", infiltrationFact, target, eventWitness)

    ; Reset manifest timer so cleanup doesn't fire immediately
    ManifestStartTime = Utility.GetCurrentRealTime()
    Debug.Notification(IntelEngine.L("An assassin strikes at " + targetName + "!"))
    IntelEngine.ConfirmManifestationCooldown()
    Core.DebugMsg("Battle: Assassination attack triggered on " + targetName)
EndFunction

; The target is here to be attacked: loaded, enabled, and on the same side of every door as the assassin.
Bool Function AssassinCanReach(Actor assassin, Actor target)
    If assassin == None || target == None
        Return false
    EndIf
    If target.IsDisabled() || !target.Is3DLoaded() || !assassin.Is3DLoaded()
        Return false
    EndIf
    If assassin.IsInInterior() != target.IsInInterior()
        Return false
    EndIf
    If assassin.IsInInterior() && assassin.GetParentCell() != target.GetParentCell()
        Return false
    EndIf
    Return true
EndFunction

; Keeps a striking assassin on the leader and nobody else. Returns true when the attempt is over: the
; leader is dead, down (an essential leader only goes to their knees) or gone, or the assassin is.
Bool Function AssassinAttemptIsOver()
    Actor striker = ManifestActors[0]
    If striker == None || striker.IsDead()
        Return true
    EndIf
    Actor leader = ManifestLeaderTarget
    If leader == None || leader.IsDead() || leader.IsBleedingOut() || !AssassinCanReach(striker, leader)
        CalmManifestActor(striker)
        Return true
    EndIf
    ; Still at it. The engine picks its own target once the first exchange is over (a guard who stepped
    ; in, then whoever stands nearest): point the assassin back at the leader when the fight has lapsed.
    If !striker.IsInCombat()
        striker.StartCombat(leader)
    EndIf
    Return false
EndFunction

; A spawned fighter whose event is over stops fighting: without this a survivor kept the aggression of
; its template and its last target until the area unloaded.
Function CalmManifestActor(Actor fighter)
    If fighter == None || fighter.IsDead()
        Return
    EndIf
    fighter.SetActorValue("Aggression", 0)
    fighter.StopCombat()
    fighter.StopCombatAlarm()
    fighter.EvaluatePackage()
EndFunction

Bool _manifestCleaning = false

Function CleanupManifestation(Bool report = true)
    ; One at a time (Gerkinfeltser, pull request #29: OnUpdate ran it twice two seconds apart, 15:46:57/59 and
    ; 17:42:25/26). The calls below let other events in, and a second pass would report and pay a second time.
    If _manifestCleaning
        Return
    EndIf
    _manifestCleaning = true
    Core.DebugMsg("Battle: Cleaning up manifestation (" + ManifestCount + " actors)")

    ; An attempt on a leader's life: how it ended is recorded and told as it was seen (it used to be told beforehand,
    ; as the DM had written it, whatever then happened). One that never came to it is told as written.
    Actor thanked = None
    String thanks = ""
    Int reward = 0
    If ManifestLeaderTarget != None && !_assassinReported
        _assassinReported = true
        Actor striker = ManifestActors[0]
        If report && (ManifestAssassinStruck || (striker != None && striker.IsDead()))
            String outcome = AssassinationResult()
            String told = IntelEngine.AssassinationOutcome(_assassinTargetFaction, _assassinAttackerFaction, _assassinLeaderName, outcome)
            Core.DebugMsg("Battle: the attempt on " + _assassinLeaderName + " ended - " + outcome)
            String note = IntelEngine.StoryResponseGetOptionalField(told, "notification")
            If note != ""
                Debug.Notification(IntelEngine.L(note))
            EndIf
            String risen = IntelEngine.StoryResponseGetOptionalField(told, "promoted")
            If risen != ""
                Debug.Notification(IntelEngine.L(IntelEngine.BattleSay("promoted", _assassinTargetFaction, "", risen)))
            EndIf
            Actor leader = ManifestLeaderTarget
            String witnessFact = IntelEngine.StoryResponseGetOptionalField(told, "witnessFact")
            String targetFact = IntelEngine.StoryResponseGetOptionalField(told, "targetFact")
            If leader != None && leader.Is3DLoaded()
                If targetFact != "" && !leader.IsDead()
                    Core.InjectFact(leader, targetFact)
                EndIf
                If witnessFact != ""
                    Actor[] witnesses = IntelEngine.GetNearbyWitnessNPCs(leader, 2000.0)
                    Int wi = 0
                    While wi < witnesses.Length
                        If witnesses[wi] != None && witnesses[wi] != leader
                            Core.InjectFact(witnesses[wi], witnessFact)
                        EndIf
                        wi += 1
                    EndWhile
                EndIf
                thanks = IntelEngine.StoryResponseGetOptionalField(told, "thanks")
                reward = IntelEngine.StoryResponseGetField(told, "reward") as Int
                If thanks != "" && !leader.IsDead() && !leader.IsBleedingOut() && leader.GetDistance(Game.GetPlayer()) <= 2000.0
                    thanked = leader
                EndIf
            EndIf
        ElseIf report
            IntelEngine.ManifestationFailed()
        EndIf
    EndIf

    ; Clear assassination task slot to prevent permanent slot leak
    If ManifestLeaderTarget != None && ManifestActors[0] != None
        Int assSlot = Core.FindSlotByAgent(ManifestActors[0])
        If assSlot >= 0
            Core.ClearSlot(assSlot, false)
        EndIf
    EndIf

    Int i = 0
    While i < ManifestCount
        If ManifestActors[i] != None
            If ManifestActors[i].IsDead()
                ; A body the player is looking at is not blinked away (this runs fifteen seconds after the
                ; fight): it is only flagged for deletion, like the survivors below, and goes with the area.
                If !Core.PlayerCanSee(ManifestActors[i])
                    ManifestActors[i].DisableNoWait()
                EndIf
                ManifestActors[i].Delete()
            Else
                ManifestActors[i].RemoveFromFaction(Intel_BattleSideA)
                ManifestActors[i].RemoveFromFaction(Intel_BattleSideB)
                ; Delete only flags a living actor: it stays until the area unloads. It must not stay armed
                ; and looking for a fight, and where nobody is watching it can go at once.
                CalmManifestActor(ManifestActors[i])
                If !Core.PlayerCanSee(ManifestActors[i])
                    ManifestActors[i].DisableNoWait()
                EndIf
                ManifestActors[i].Delete() ; fix98: spawned survivors used to stay forever (live 2026-11-12)
            EndIf
            ManifestActors[i] = None
        EndIf
        i += 1
    EndWhile
    ManifestCount = 0
    ManifestActive = false
    ManifestAssassinAttacked = false
    ManifestAssassinStruck = false
    ManifestLeaderTarget = None
    _manifestCleaning = false

    ; The one whose life was saved thanks the one who saved it, in their own words, and pays them in person.
    If thanked != None
        Actor player = Game.GetPlayer()
        thanked.SetLookAt(player)
        Core.SendTaskNarration(thanked, thanks, player)
        Utility.Wait(2.0)
        IntelEngine_Quests quests = Quest.GetQuest("IntelEngine_QuestKeeper") as IntelEngine_Quests
        If quests != None
            quests.WaitForTheirSay(thanked, 12.0)
        EndIf
        If reward > 0 && !thanked.IsDead()
            player.AddItem(Game.GetFormFromFile(0x0000000F, "Skyrim.esm"), reward)
            Core.DebugMsg("Battle: " + reward + " gold from " + thanked.GetDisplayName() + " for their life")
        EndIf
        thanked.ClearLookAt()
    EndIf
EndFunction

Bool Function IsAnyManifestActorInCombat()
    Int i = 0
    While i < ManifestCount
        If ManifestActors[i] != None && !ManifestActors[i].IsDead() && ManifestActors[i].IsInCombat()
            return true
        EndIf
        i += 1
    EndWhile
    return false
EndFunction

; =============================================================================
; UTILITY
; =============================================================================

; GetEnemyFaction — moved to C++ BattleManager. Deleted.

Bool Function IsPlayerInExterior()
    ; GetParentCell is safe for the player — they're always in a loaded cell
    Actor player = Game.GetPlayer()
    Cell playerCell = player.GetParentCell()
    If !playerCell
        return false
    EndIf
    return !playerCell.IsInterior()
EndFunction

Function ShowBattleStartNotification(String locationName)
    {What the player sees as they come near: two armies facing each other. (It used to say that soldiers "clash",
    with the lines still standing, or with nobody in sight.)}
    If BattleSkirmish
        Debug.Notification(IntelEngine.L(IntelEngine.BattleSay("skirmish_met", BattleFactionA, BattleFactionB)))
    Else
        Debug.Notification(IntelEngine.L(IntelEngine.BattleSay("drawn_up", BattleFactionA, BattleFactionB)))
    EndIf
EndFunction

Function DebugBodies()
    {Test hook: where the battle's dead lie and who is held in a killing blow, into IntelEngine.log.}
    IntelEngine.BattleDebugBodies()
EndFunction

Function DebugSkirmish(String attacker, String target, Int size)
    {Test hook: a skirmish between two factions near the player, as a political event would bring it.}
    Core.DebugMsg("Battle: [debug] skirmish " + attacker + " / " + target + " -> " + StartSkirmish(attacker, target, size))
EndFunction

Function DebugAssassination(String targetFaction, String attackerFaction)
    {Test hook: an attempt on a leader of the target faction who is near the player, as a political event would bring it.}
    ManifestEvent("{" + Quote("event_type") + ":" + Quote("assassination_attempt") + "," + Quote("attacker_faction") + ":" + Quote(attackerFaction) +         "," + Quote("target_faction") + ":" + Quote(targetFaction) + "," + Quote("spawn_count") + ":1}")
EndFunction

String Function Quote(String text)
    Return "\"" + text + "\""
EndFunction

Function DebugGathering(String place, String attacker, String target)
    {Test hook: two armies gather near a place, as when the political dungeon master announces a battle.}
    Int id = IntelEngine.AddPendingBattle(place, attacker, target, "{}")
    Core.DebugMsg("Battle: [debug] gathering " + id + " near " + place + ": " + attacker + " against " + target)
    If id >= 0
        StartPendingBattlePoll()
    EndIf
EndFunction

Function DebugTwists(Int champion, Int flank, Int turncoat)
    {Test hook: what the battle now drawn up has in store, said outright (champion: 0 none, 1 side A, 2 side B, 3 both;
    flank and turncoat: 0, 1 or 2).}
    IntelEngine.BattleSetTwists(champion, flank, turncoat)
EndFunction

Function DebugDidFor(String factionId, Int times)
    {Test hook: the player has done this many things at a faction's asking (eight renown each): for trying the ranks.}
    Int i = 0
    While i < times
        IntelEngine.PlayerDidFor(factionId, "quest")
        i += 1
    EndWhile
    Core.DebugMsg("Battle: [debug] with " + factionId + " the player is now rank " + IntelEngine.PlayerFactionRank(factionId) + " " + IntelEngine.PlayerRankTitle(factionId))
EndFunction

Function DebugBattle()
    {Test hook: where the battle stands, into the log.}
    Core.DebugMsg("Battle: [debug] phase " + BattlePhase + ", side '" + PlayerBattleSide + "', commanders " + CommanderA + " / " + CommanderB + \
        ", hailed " + PlayerWasHailed + ", soldiers " + SpawnedSoldierCount + ", field " + IntelEngine.BattleFieldInfo())
    String a = ""
    String b = ""
    Int i = 0
    While i < SpawnedSoldierCount && i < SpawnedSoldiers.Length
        Actor soldier = SpawnedSoldiers[i]
        If soldier != None && !soldier.IsDead()
            If soldier.IsInFaction(Intel_BattleSideB)
                b += " " + soldier
            Else
                a += " " + soldier
            EndIf
        EndIf
        i += 1
    EndWhile
    Core.DebugMsg("Battle: [debug] side A living:" + a)
    Core.DebugMsg("Battle: [debug] side B living:" + b)
EndFunction

Function CleanupBattle()
    ; Called when battle ended unexpectedly (e.g., PollBattleState returned "{}")
    Core.DebugMsg("Battle: Unexpected end - cleaning up")
    RemovePlayerFromBattle()
    CleanupAllActors()
    CleanupMarkers(SoldiersLeaving)
    ResetState()
EndFunction

; =============================================================================
; SAVE/LOAD SAFETY
; =============================================================================

Function OnGameReload()
    ; Session rollover: Utility.GetCurrentRealTime() resets each Skyrim launch
    ; but these properties are saved. A stale saved value (> current real time)
    ; comes from a prior session and would break timeout/elapsed checks (the
    ; elapsed diff goes negative, so "stuck" watchdogs never trip). Snap stale
    ; stamps forward to `now` so the countdown restarts from load.
    Float now = Utility.GetCurrentRealTime()
    If BattleStartRealTime > now
        BattleStartRealTime = now
    EndIf
    If DeferredCleanupStart > now
        DeferredCleanupStart = now
    EndIf
    If ManifestStartTime > now
        ManifestStartTime = now
    EndIf
    _retiredLooked = 0.0
    If _retiredCount > 0
        Core.RequestTick(MarkerRestSeconds)
    EndIf

    ; Clean up any active manifestation from pre-reload (nothing is recorded of it: who knows how it would have gone)
    _manifestCleaning = false   ; a save made in the middle of a cleanup would otherwise block every later one
    If ManifestActive
        CleanupManifestation(false)
    EndIf

    ; If a battle was in progress when the game was saved, clean up
    ; Battle state is not save-persistent in C++ (BattleManager resets on load)
    ; ActiveBattleId >= 0 catches battles that started but never spawned (player was indoors)
    If BattleSpawned || BattleScheduled || ActiveBattleId >= 0 || BattlePhase != 0
        ; The load handler can run twice at once (seen 2026-11-14: two Maintenance passes three seconds apart).
        ; The second one sent every soldier off again after the first had taken them out of their sides, all in
        ; one direction. The flags go down before the first call that lets another event in.
        Int endedBattleId = ActiveBattleId
        BattleSpawned = false
        BattleScheduled = false
        ActiveBattleId = -1
        BattlePhase = 0
        Core.DebugMsg("Battle: Game reloaded during active battle - cleaning up")
        ; Clear C++ active battle BEFORE Papyrus ResetState
        IntelEngine.EndBattle(endedBattleId, "reload", "")
        RemovePlayerFromBattle()
        CleanupAllActors()
        CleanupMarkers(SoldiersLeaving)
        ResetState()
    EndIf
    If SoldiersLeaving
        Core.RequestTick(StragglerInterval)      ; stragglers of a battle that was over when the game was saved
    EndIf

    ; The armies gathered somewhere come back with the save (they used to be thrown away here: word of a battle had
    ; gone round, and it never came). Whoever is still gathered is watched again.
    PendingPollActive = IntelEngine.GetPendingBattleCount() > 0
    If PendingPollActive
        Core.RequestTick(PollInterval)
    EndIf
    ; A call that was open when the game was saved: its words are said again (the game does not keep them); one whose
    ; battle was being fought ends with nothing decided (a battle does not come back with a save), one whose
    ; gathering is gone was decided without the player.
    If CallBattleId >= 0
        IntelEngine.BattleCallText(CallFaction, CallPlace)
        If CallFought
            EndCall(CALL_PARTED)
        ElseIf IntelEngine.GetPendingBattleInfo(CallBattleId) == "{}"
            EndCall(CALL_MISSED)
        EndIf
    EndIf
EndFunction
