Scriptname IntelEngine_Battle extends Quest

; =============================================================================
; PLAYER-PRESENT BATTLE SYSTEM
;
; Two-phase architecture:
;
; Phase A — Pending battles (location-based):
;   1. Politics DM generates battle_result → HandleBattleResult creates a PendingBattle
;      at the named location's real world coordinates (via BGSLocation worldLocMarker)
;   2. This script polls every 3s: if player is within 5000 units of a pending
;      battle, soldiers spawn and active battle begins
;   3. If 3 game hours pass without player arrival, C++ auto-resolves off-screen
;
; Phase B — Active battle (spawned soldiers):
;   1. Soldiers spawn at the location coordinates with rally points
;   2. PollBattleState() every 3s drives events, morale, wave triggers
;   3. Battle ends when morale <= 20 or all actors dead on one side
;
; Requires ESP: Intel_BattleSideA, Intel_BattleSideB factions (hostile to each other)
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
String Property QuestAutoJoinFaction = "" Auto Hidden  ; Set by StoryEngine for quest-dispatched battles

; Deferred cleanup state (non-blocking, uses OnUpdate polling)
Bool Property DeferredCleanupActive = false Auto Hidden
Float Property DeferredCleanupStart = 0.0 Auto Hidden

; Pending battle polling
Bool Property PendingPollActive = false Auto Hidden

; Micro-encounter (political event manifestation) state
Actor[] Property ManifestActors Auto Hidden
Int Property ManifestCount = 0 Auto Hidden
Bool Property ManifestActive = false Auto Hidden
Float Property ManifestStartTime = 0.0 Auto Hidden
Float Property ManifestCleanupDelay = 90.0 Auto Hidden  ; real seconds before cleanup

; =============================================================================
; SCHEDULING (called by IntelEngine_Politics)
; =============================================================================

Function ScheduleBattle(String factionA, String factionB, Int warId, Float gameTime)
    If BattleScheduled || IntelEngine.IsBattleActive()
        Core.DebugMsg("Battle: Cannot schedule — already scheduled or active")
        return
    EndIf

    BattleFactionA = factionA
    BattleFactionB = factionB
    BattleWarId = warId
    ScheduledBattleTime = gameTime
    BattleScheduled = true
    BattleSpawned = false

    ; Register for game time update to check when battle time arrives
    Float hoursUntilBattle = (gameTime - Utility.GetCurrentGameTime()) * 24.0
    If hoursUntilBattle < 0.1
        hoursUntilBattle = 0.1
    EndIf
    RegisterForSingleUpdateGameTime(hoursUntilBattle)

    Core.DebugMsg("Battle: Scheduled " + factionA + " vs " + factionB + " in " + hoursUntilBattle + "h")
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
    RegisterForSingleUpdate(PollInterval)
    Core.DebugMsg("Battle: Started pending battle proximity polling")
EndFunction

Function HandlePendingBattleTriggered(Int pendingId)
    ; Get info THEN remove atomically — prevents TOCTOU re-trigger on next poll cycle.
    ; Remove MUST happen before any early return to avoid infinite re-trigger loop.
    String infoJson = IntelEngine.GetPendingBattleInfo(pendingId)
    IntelEngine.RemovePendingBattle(pendingId)
    PendingPollActive = IntelEngine.GetPendingBattleCount() > 0

    If infoJson == "{}"
        Core.DebugMsg("Battle: Pending battle " + pendingId + " info not found — already expired?")
        return
    EndIf

    ; Extract fields from pending battle info
    String factionA = IntelEngine.StoryResponseGetField(infoJson, "faction_a")
    String factionB = IntelEngine.StoryResponseGetField(infoJson, "faction_b")
    String locName = IntelEngine.StoryResponseGetField(infoJson, "location")

    If factionA == "" || factionB == ""
        Core.DebugMsg("Battle: Pending battle " + pendingId + " has empty factions — aborting")
        return
    EndIf

    ; Unified path: reuse StartBattleImmediate → StartBattleSequence → SpawnFullBattle
    ; This ensures pending battles get ALL the C++ fixes: anchor-based spawning,
    ; bounty prevention, leader selection, spawn validation, cleanup tracking.
    BattleWarId = IntelEngine.GetActiveWarId(factionA, factionB)

    ; Resolve the actual battle location as spawn anchor (soldiers should already be there)
    ; Pending battles trigger at 5000 units — soldiers spawn at the location, not at the player,
    ; so they're already fighting when the player walks up.
    Actor player = Game.GetPlayer()
    ObjectReference locRef = IntelEngine.ResolveAnyDestination(player, locName)
    If locRef != None
        BattleSpawnAnchor = locRef
    Else
        ; Fallback: spawn ahead of player if location can't be resolved
        Float playerAngle = player.GetAngleZ()
        Float spawnDist = 1500.0
        Form xmarkerBase = Game.GetFormFromFile(0x0000003B, "Skyrim.esm")
        If xmarkerBase
            ObjectReference marker = player.PlaceAtMe(xmarkerBase)
            Float anchorX = player.GetPositionX() + Math.Sin(playerAngle) * spawnDist
            Float anchorY = player.GetPositionY() + Math.Cos(playerAngle) * spawnDist
            marker.SetPosition(anchorX, anchorY, player.GetPositionZ())
            BattleSpawnAnchor = marker
        Else
            BattleSpawnAnchor = player as ObjectReference
        EndIf
    EndIf

    StartBattleImmediate(factionA, factionB, BattleWarId)

    Core.DebugMsg("Battle: Pending battle " + pendingId + " triggered at " + locName + \
        " — " + factionA + " vs " + factionB + " (unified spawn path)")
EndFunction

; =============================================================================
; TIMER EVENTS
; =============================================================================

Event OnUpdateGameTime()
    If !BattleScheduled
        return
    EndIf

    Float now = Utility.GetCurrentGameTime()
    If now >= ScheduledBattleTime
        StartBattleSequence()
    Else
        ; Not time yet, re-register
        Float hoursLeft = (ScheduledBattleTime - now) * 24.0
        RegisterForSingleUpdateGameTime(hoursLeft)
    EndIf
EndEvent

Event OnUpdate()
    ; Manifestation cleanup check (micro-encounters from political events)
    If ManifestActive
        Float elapsed = Utility.GetCurrentRealTime() - ManifestStartTime
        Bool combatOver = !IsAnyManifestActorInCombat()

        ; Cleanup when combat has ended OR hard cap of 90s reached
        If (combatOver && elapsed >= 15.0) || elapsed >= ManifestCleanupDelay
            CleanupManifestation()
        Else
            RegisterForSingleUpdate(PollInterval)
            return  ; Don't start pending battles while manifestation is active
        EndIf
    EndIf

    ; Phase 0: Deferred cleanup — proximity-based per-actor cleanup.
    ; Actors behind the player and >2000 units away (or unloaded) get cleaned.
    ; 180s hard timeout as safety net to prevent stale actors cluttering the world.
    If DeferredCleanupActive
        Float elapsed = Utility.GetCurrentRealTime() - DeferredCleanupStart
        Bool forceAll = elapsed >= 180.0
        Actor player = Game.GetPlayer()

        ; Clean soldiers via C++ (no Papyrus arrays — immune to stale bytecode)
        Int remaining = IntelEngine.CleanupBattleSoldiers(player.GetPositionX(), \
            player.GetPositionY(), player.GetPositionZ(), player.GetAngleZ(), forceAll)

        If remaining == 0 || forceAll
            If forceAll && remaining > 0
                Core.DebugMsg("Battle: Hard timeout cleanup — " + remaining + " actors remaining")
            EndIf
            ; NOW remove player from battle factions — all soldiers are disabled/gone
            RemovePlayerFromBattle()
            CleanupMarkers()
            DeferredCleanupActive = false
            Bool hadPendingPolls = PendingPollActive && IntelEngine.GetPendingBattleCount() > 0
            ResetState()
            If hadPendingPolls
                PendingPollActive = true
                RegisterForSingleUpdate(PollInterval)
                Core.DebugMsg("Battle: Resumed pending battle polling after cleanup")
            EndIf
            return
        EndIf
    EndIf

    ; Dual-phase polling: pending battles (proximity check) and active battles (combat state)

    ; Phase A: Pending battle proximity polling
    If PendingPollActive && !IntelEngine.IsBattleActive()
        Int triggeredId = IntelEngine.PollPendingBattles()
        If triggeredId >= 0
            ; Player is near a pending battle — spawn it!
            HandlePendingBattleTriggered(triggeredId)
            ; If battle started, HandlePendingBattleTriggered registered active polling.
            ; If it failed (another battle active), re-register pending poll if battles remain.
            If !IntelEngine.IsBattleActive() && IntelEngine.GetPendingBattleCount() > 0
                RegisterForSingleUpdate(PollInterval)
            EndIf
            return
        EndIf

        ; Check for expired battle results — show RESULT notification
        String expiredResult = IntelEngine.GetLastExpiredBattleResult()
        If expiredResult != ""
            String victorId = IntelEngine.StoryResponseGetField(expiredResult, "victor")
            String locName = IntelEngine.StoryResponseGetField(expiredResult, "location")
            If victorId != ""
                String victorName = IntelEngine.GetFactionDisplayName(victorId)
                Debug.Notification("Word reaches you: " + victorName + " forces prevailed at " + locName + ".")
            Else
                Debug.Notification("Word reaches you: neither side held the field at " + locName + ".")
            EndIf
        EndIf

        ; Check if any pending battles remain
        If IntelEngine.GetPendingBattleCount() <= 0
            PendingPollActive = false
            Core.DebugMsg("Battle: No pending battles remain — stopping proximity poll")
            return
        EndIf

        RegisterForSingleUpdate(PollInterval)
        return
    EndIf

    ; Phase B: Active battle combat polling
    If !IntelEngine.IsBattleActive()
        ; Battle ended (C++ detected all soldiers dead or timeout).
        ; Clean up immediately — don't wait for next story tick.
        If BattleSpawned
            Core.DebugMsg("Battle: Poll detected battle ended — cleaning up Papyrus state")
            BattleSpawned = false  ; prevent re-entrant cleanup on next poll
            ; Don't RemovePlayerFromBattle here — deferred cleanup keeps soldiers alive.
            ; Player stays in battle faction until cleanup finishes (OnUpdate Phase 0).
            ; Notify StoryEngine directly so quest completes NOW (not on next story tick)
            If Core.StoryEngine != None
                Core.StoryEngine.CheckQuestProximity()
            EndIf
            DeferredCleanupActive = true
            DeferredCleanupStart = Utility.GetCurrentRealTime()
            RegisterForSingleUpdate(PollInterval)
        EndIf
        return
    EndIf

    ; If battle is active but not spawned (player was elsewhere), check if they're in exterior now
    If !BattleSpawned
        If IsPlayerInExterior()
            SpawnMidBattle()
        Else
            ; Still indoors, keep polling
            RegisterForSingleUpdate(PollInterval)
            return
        EndIf
    EndIf

    ; Hard timeout — force-end if battle is stuck (soldiers behind geometry, pathfinding broken)
    ; This prevents the player from being stuck in a battle faction forever.
    If BattleStartRealTime > 0.0
        Float battleAge = Utility.GetCurrentRealTime() - BattleStartRealTime
        If battleAge > BattleHardTimeout
            Core.DebugMsg("Battle: HARD TIMEOUT (" + battleAge + "s) — force-ending battle")
            Int timeoutMsg = Utility.RandomInt(0, 2)
            If timeoutMsg == 0
                Debug.Notification("Both sides withdraw, exhausted.")
            ElseIf timeoutMsg == 1
                Debug.Notification("The surviving soldiers disengage.")
            Else
                Debug.Notification("The fighting dies down. Neither side holds the field.")
            EndIf
            RemovePlayerFromBattle()
            CleanupBattle()
            return
        EndIf
    EndIf

    ; Continuous bounty suppression during active battle.
    ; Spawned soldiers have crime factions removed, but nearby unspawned guards
    ; still detect "assault" when the player accidentally hits a friendly.
    ; Clear any bounty every poll cycle so it never sticks during combat.
    IntelEngine.ClearAllHoldBounties()

    ; Poll C++ BattleManager for state updates
    String stateJson = IntelEngine.PollBattleState()
    If stateJson == "{}"
        ; Battle ended externally or error
        CleanupBattle()
        return
    EndIf

    HandlePollResult(stateJson)
    RegisterForSingleUpdate(PollInterval)
EndEvent

; =============================================================================
; BATTLE START
; =============================================================================

; Start a battle immediately (no schedule delay). Used by quest-dispatched
; faction_battle where the player has already traveled to the location.
Function StartBattleImmediate(String factionA, String factionB, Int warId)
    If IntelEngine.IsBattleActive()
        Core.DebugMsg("Battle: Cannot start immediate — already active")
        return
    EndIf
    BattleFactionA = factionA
    BattleFactionB = factionB
    BattleWarId = warId
    BattleScheduled = false
    BattleSpawned = false
    Core.DebugMsg("Battle: Starting immediate — " + factionA + " vs " + factionB)
    StartBattleSequence()
EndFunction

Function StartBattleSequence()
    BattleScheduled = false

    ; Determine location name from player's current area
    Actor player = Game.GetPlayer()
    String locName = IntelEngine.GetActorParentLocationName(player)
    If locName == ""
        locName = "the wilderness"
    EndIf
    BattleLocationName = locName

    ; Start battle in C++ BattleManager
    ActualBattleStartTime = Utility.GetCurrentGameTime()
    BattleStartRealTime = Utility.GetCurrentRealTime()
    ActiveBattleId = IntelEngine.StartBattle(BattleFactionA, BattleFactionB, BattleLocationName, BattleWarId)
    If ActiveBattleId < 0
        Core.DebugMsg("Battle: C++ StartBattle failed (another battle active?)")
        ResetState()
        return
    EndIf

    CurrentWave = 0

    ; Ensure battle factions are hostile to each other (in case CK setup missed)
    Intel_BattleSideA.SetEnemy(Intel_BattleSideB)

    If IsPlayerInExterior()
        ; Player is here — full spawn with march-in
        SpawnFullBattle()
    Else
        ; Player is indoors — battle proceeds virtually
        ; Start polling so we detect when player exits
        Core.DebugMsg("Battle: Started off-screen at " + BattleLocationName + ", waiting for player")
        RegisterForSingleUpdate(PollInterval)
    EndIf
EndFunction

; =============================================================================
; SPAWNING — FULL BATTLE (player present from start)
; =============================================================================

Function SpawnFullBattle()
    Core.DebugMsg("Battle: Spawning full battle — " + BattleFactionA + " vs " + BattleFactionB)
    BattleSpawned = true

    ; Snapshot current bounty so battle-accumulated bounty can be reverted without losing pre-existing bounty
    IntelEngine.ClearAllHoldBounties()  ; first call = snapshot

    ; === ALL spawn logic is in C++ — no Papyrus arrays needed ===
    ; C++ handles: spawn at anchor, faction assignment, positioning, leader selection,
    ; Protected flag, bounty snapshot. Returns JSON with FormIDs for Papyrus-only ops.
    Actor player = Game.GetPlayer()
    ObjectReference spawnAnchor = BattleSpawnAnchor
    If spawnAnchor == None
        spawnAnchor = player as ObjectReference
    EndIf

    String resultJson = IntelEngine.ExecuteFullBattleSpawn(QuestAutoJoinFaction, player, player.GetAngleZ(), spawnAnchor)
    QuestAutoJoinFaction = ""

    Bool success = IntelEngine.StoryResponseGetField(resultJson, "success") == "true"
    If !success
        String err = IntelEngine.StoryResponseGetField(resultJson, "error")
        Core.DebugMsg("Battle: ExecuteFullBattleSpawn FAILED: " + err)
        CleanupBattle()
        return
    EndIf

    Int sideASpawned = IntelEngine.StoryResponseGetField(resultJson, "sideACount") as Int
    Int sideBSpawned = IntelEngine.StoryResponseGetField(resultJson, "sideBCount") as Int
    Int paired = IntelEngine.StoryResponseGetField(resultJson, "paired") as Int
    Bool playerJoined = IntelEngine.StoryResponseGetField(resultJson, "playerJoined") == "true"
    String joinFaction = IntelEngine.StoryResponseGetField(resultJson, "joinFaction")
    String notification = IntelEngine.StoryResponseGetField(resultJson, "notification")

    ; === Papyrus-only operations: quest marker ===
    ; SetPlayerTeammate is now handled entirely in C++ (SetActorPlayerTeammate)
    ; which adds to CurrentFollowerFaction + sets boolBit. The old Papyrus loop
    ; failed 100% due to FormID overflow (0xFF prefix → negative int → Game.GetForm returns None).

    If playerJoined
        PlayerBattleSide = joinFaction
        Core.DebugMsg("Battle: Player joined " + joinFaction + " — teammates set by C++ (" + sideASpawned + " vs " + sideBSpawned + ")")
    Else
        Core.DebugMsg("Battle: Player did NOT auto-join (playerJoined=false, joinFaction=" + joinFaction + ")")
    EndIf

    ; Quest marker on leader (C++ already made leader Protected + SpeedMult 115)
    Int leaderFormId = IntelEngine.GetJsonArrayInt(resultJson, "leaderFormId", 0)
    If leaderFormId != 0
        Actor leader = Game.GetForm(leaderFormId) as Actor
        If leader
            BattleLeader = leader
            BattleLeaderWasEssential = leader.IsEssential()
            ; Move quest marker from location to leader's head
            If Core.StoryEngine != None
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
                    Core.DebugMsg("Battle: Quest marker moved to leader — " + leader.GetDisplayName())
                Else
                    Core.DebugMsg("Battle: WARNING — QuestTargetAlias is None, cannot place marker on leader")
                EndIf
            EndIf
        EndIf
    EndIf

    ; Show notifications
    If playerJoined && notification != ""
        Debug.Notification(notification)
    EndIf

    CurrentWave = 1
    IntelEngine.AdvanceBattleWave()

    Core.DebugMsg("Battle: C++ spawned " + sideASpawned + " vs " + sideBSpawned + ", " + paired + " combat pairs")

    ; Kick-start combat — soldiers need StartCombat to engage immediately
    ForceInitialEngagement()

    ShowBattleStartNotification(BattleLocationName)

    ; Start polling for state updates / wave spawns
    RegisterForSingleUpdate(PollInterval)
EndFunction

; (ApplyBattleFactions removed — C++ handles faction assignment, Papyrus soldier loop handles positioning)

; =============================================================================
; SPAWNING — MID-BATTLE (player arrived late)
; =============================================================================

Function SpawnMidBattle()
    Core.DebugMsg("Battle: Player arrived — spawning mid-battle")
    BattleSpawned = true

    ; Calculate how long battle has been running (use actual start, not scheduled)
    Float now = Utility.GetCurrentGameTime()
    Float elapsedDays = now - ActualBattleStartTime
    If elapsedDays < 0.0
        elapsedDays = 0.0
    EndIf
    Float elapsedMinutes = elapsedDays * 24.0 * 60.0  ; game minutes

    ; Calculate positions — spawn closer to center since they've been fighting
    CalculateAndPlaceMarkers()

    ; Determine how many casualties have already occurred
    Int casualtiesPerSide = (elapsedMinutes / MidBattleCasualtyRate) as Int
    If casualtiesPerSide < 0
        casualtiesPerSide = 0
    EndIf

    ; Apply morale loss for elapsed time
    Int moraleLoss = (elapsedMinutes * MidBattleMoraleRate) as Int
    If moraleLoss > MidBattleMoraleCap
        moraleLoss = MidBattleMoraleCap  ; cap — if beyond this, battle would have ended
    EndIf

    ; Late arrival notification (non-LLM, randomized variants)
    String nameA = IntelEngine.GetFactionDisplayName(BattleFactionA)
    String nameB = IntelEngine.GetFactionDisplayName(BattleFactionB)
    Int arrivalVar = Utility.RandomInt(0, 2)
    If arrivalVar == 0
        Debug.Notification("A battle rages between " + nameA + " and " + nameB + " forces.")
    ElseIf arrivalVar == 1
        Debug.Notification("You arrive to find " + nameA + " and " + nameB + " forces locked in combat.")
    Else
        Debug.Notification("Sounds of battle carry across the field — " + nameA + " and " + nameB + " clash ahead.")
    EndIf

    ; Spawn reduced forces near center (they've already marched and engaged)
    Int soldiersPerSide = GetWaveSoldierCount(1) - casualtiesPerSide
    If soldiersPerSide < MidBattleMinSoldiers
        soldiersPerSide = MidBattleMinSoldiers
    EndIf

    ; Spawn near center instead of at rally — they've already marched
    SpawnSoldiersAtMarker(BattleFactionA, CenterMarker, soldiersPerSide, true)
    SpawnSoldiersAtMarker(BattleFactionB, CenterMarker, soldiersPerSide, false)

    ; Kick-start combat — soldiers are at the same marker, need StartCombat to engage
    ForceInitialEngagement()

    ; Apply simulated morale loss
    IntelEngine.AdjustBattleMorale(BattleFactionA, -moraleLoss)
    IntelEngine.AdjustBattleMorale(BattleFactionB, -moraleLoss)

    ; Sync wave state: C++ starts at 0 after StartBattle, but mid-battle is wave 2.
    ; Two AdvanceBattleWave calls bring C++ from 0→1→2 to match Papyrus CurrentWave.
    ; This bypasses SpawnWave intentionally (waves 1+2 already "happened" off-screen).
    CurrentWave = 2
    IntelEngine.AdvanceBattleWave()
    IntelEngine.AdvanceBattleWave()

    ; Check if player should auto-join based on faction standing
    EvaluatePlayerJoin()

    Core.DebugMsg("Battle: Mid-battle spawn — " + soldiersPerSide + " per side, " + moraleLoss + " morale lost")
EndFunction

; =============================================================================
; POSITION CALCULATION
; =============================================================================

Function CalculateMarkersAtLocation(Float centerX, Float centerY, Float centerZ)
    ; Place markers at the actual battle location coordinates (from BGSLocation worldLocMarker).
    ; Rally points are offset along a random axis for variety.

    ; Random angle for rally point axis — each battle looks different
    Float axisAngle = Utility.RandomFloat(0.0, 360.0)

    Float rallyAX = centerX + Math.Sin(axisAngle) * SpawnDistance
    Float rallyAY = centerY + Math.Cos(axisAngle) * SpawnDistance
    Float rallyBX = centerX - Math.Sin(axisAngle) * SpawnDistance
    Float rallyBY = centerY - Math.Cos(axisAngle) * SpawnDistance

    ; Place XMarker references at calculated positions
    Form xmarkerBase = Game.GetFormFromFile(0x0000003B, "Skyrim.esm")
    If !xmarkerBase
        Core.DebugMsg("Battle: FATAL — XMarker base not found, aborting spawn")
        return
    EndIf

    Actor player = Game.GetPlayer()
    CenterMarker = player.PlaceAtMe(xmarkerBase)
    CenterMarker.SetPosition(centerX, centerY, centerZ)

    RallyMarkerA = player.PlaceAtMe(xmarkerBase)
    RallyMarkerA.SetPosition(rallyAX, rallyAY, centerZ)

    RallyMarkerB = player.PlaceAtMe(xmarkerBase)
    RallyMarkerB.SetPosition(rallyBX, rallyBY, centerZ)

    Core.DebugMsg("Battle: Markers placed — center (" + centerX + ", " + centerY + \
        "), rally A (" + rallyAX + ", " + rallyAY + "), rally B (" + rallyBX + ", " + rallyBY + ")")
EndFunction

Function PlaceMarkersTowardBattle(Float battleX, Float battleY)
    ; Place markers ahead of the player in the direction of the battle location.
    ; This keeps soldiers within the loaded cell grid (PlaceAtMe + small SetPosition)
    ; while the battle appears in the correct compass direction for immersion.
    ; Uses playerZ because soldiers spawn near the player, not at the distant battle site.
    Actor player = Game.GetPlayer()
    Float playerX = player.GetPositionX()
    Float playerY = player.GetPositionY()
    Float playerZ = player.GetPositionZ()

    ; Calculate angle from player toward battle location
    Float dx = battleX - playerX
    Float dy = battleY - playerY
    Float dist = Math.sqrt(dx * dx + dy * dy)

    Float centerX
    Float centerY
    If dist > 1.0
        ; Normalize direction and place center ahead toward the battle
        Float dirX = dx / dist
        Float dirY = dy / dist
        centerX = playerX + dirX * BattleSpawnDistance
        centerY = playerY + dirY * BattleSpawnDistance
    Else
        ; Player is on top of the battle coords — fall back to facing direction
        Float playerAngle = player.GetAngleZ()
        centerX = playerX + Math.Sin(playerAngle) * BattleSpawnDistance
        centerY = playerY + Math.Cos(playerAngle) * BattleSpawnDistance
    EndIf

    CalculateMarkersAtLocation(centerX, centerY, playerZ)
EndFunction

Function CalculateAndPlaceMarkers()
    ; Legacy: player-relative positioning for ScheduleBattle flow
    Actor player = Game.GetPlayer()
    Float playerX = player.GetPositionX()
    Float playerY = player.GetPositionY()
    Float playerZ = player.GetPositionZ()
    Float playerAngle = player.GetAngleZ()

    Float centerX = playerX + Math.Sin(playerAngle) * CenterSpawnDistance
    Float centerY = playerY + Math.Cos(playerAngle) * CenterSpawnDistance

    CalculateMarkersAtLocation(centerX, centerY, playerZ)
EndFunction

; =============================================================================
; WAVE SPAWNING
; =============================================================================

Function SpawnWave(Int waveNum)
    ; Fully C++ wave spawning — handles factions, aggression, combat pairs, crime factions
    Actor player = Game.GetPlayer()
    Int count = GetWaveSoldierCount(waveNum)

    Core.DebugMsg("Battle: Spawning wave " + waveNum + " — " + count + " soldiers per side (C++)")

    ; Reinforcements: announce BEFORE spawn so player looks around
    If waveNum > 1
        String waveType = "wave" + waveNum
        Debug.Notification(IntelEngine.GetBattleNotification(waveType, "", "", false))
    EndIf

    ; C++ handles everything: spawn, faction, aggression, combat pairs, crime faction removal
    ; Spawn at battle anchor (quest location) so reinforcements arrive at the fight, not the player
    ObjectReference anchor = BattleSpawnAnchor
    If anchor == None
        anchor = CenterMarker
    EndIf
    String resultJson = IntelEngine.SpawnReinforcements(count, player, anchor)
    Bool success = IntelEngine.StoryResponseGetField(resultJson, "success") == "true"

    If !success
        Core.DebugMsg("Battle: SpawnReinforcements FAILED: " + IntelEngine.StoryResponseGetField(resultJson, "error"))
        CurrentWave = waveNum
        IntelEngine.AdvanceBattleWave()
        return
    EndIf

    Int sideASpawned = IntelEngine.StoryResponseGetField(resultJson, "sideACount") as Int
    Int sideBSpawned = IntelEngine.StoryResponseGetField(resultJson, "sideBCount") as Int
    String playerSide = IntelEngine.StoryResponseGetField(resultJson, "playerSide")

    ; SetPlayerTeammate handled by C++ SpawnReinforcements (SetActorPlayerTeammate).
    ; Old Papyrus loop removed — Game.GetForm() fails for 0xFF-prefix FormIDs.
    Core.DebugMsg("Battle: Wave " + waveNum + " — " + sideASpawned + " vs " + sideBSpawned + " (teammates set by C++)")

    CurrentWave = waveNum
    IntelEngine.AdvanceBattleWave()

    ; Wave 1 notification fires AFTER spawn
    If waveNum == 1
        Utility.Wait(1.5 + Utility.RandomFloat(0.0, 1.5))
        Debug.Notification(IntelEngine.GetBattleNotification("wave1", "", "", false))
    EndIf
EndFunction

Int Function GetWaveSoldierCount(Int waveNum)
    ; Total across all waves MUST NOT exceed MaxSoldiersPerSide (22) / Actor array size.
    ; 6+5+4+4+3 = 22. Five waves for a prolonged war-like battle.
    If waveNum == 1
        return 6   ; vanguard
    ElseIf waveNum == 2
        return 5   ; first reinforcements
    ElseIf waveNum == 3
        return 4   ; second reinforcements
    ElseIf waveNum == 4
        return 4   ; reserves
    ElseIf waveNum == 5
        return 3   ; last stand
    EndIf
    return 3
EndFunction

Function SpawnSoldiersAtMarker(String factionId, ObjectReference marker, Int count, Bool isSideA)
    If !marker
        Core.DebugMsg("Battle: SpawnSoldiersAtMarker — marker is None!")
        return
    EndIf

    ; Cap total soldiers per side (query C++ for current count)
    String sideKey = "A"
    If !isSideA
        sideKey = "B"
    EndIf
    String sideJson = IntelEngine.GetBattleSoldierFormIds(sideKey)
    Int currentCount = IntelEngine.StoryResponseGetField(sideJson, "count") as Int
    If currentCount + count > MaxSoldiersPerSide
        count = MaxSoldiersPerSide - currentCount
    EndIf
    If count <= 0
        return
    EndIf

    Faction battleFaction = Intel_BattleSideA
    If !isSideA
        battleFaction = Intel_BattleSideB
    EndIf

    ; Batch spawn in C++ at the marker (not the player — avoids pop-in at player's feet)
    Actor[] soldiers = IntelEngine.SpawnBattleSoldiers(factionId + ":" + count, marker)

    Int i = 0
    While i < soldiers.Length
        Actor soldier = soldiers[i]
        If soldier

            ; Spread soldiers around the rally marker — MoveTo snaps Z to terrain
            Float offsetX = Utility.RandomFloat(-150.0, 150.0)
            Float offsetY = Utility.RandomFloat(-150.0, 150.0)
            soldier.MoveTo(marker, offsetX, offsetY, 0.0)

            ; Aggressive + Foolhardy — only attacks faction enemies (not civilians/guards).
            ; At 300 units apart (SpawnDistance=150 per side), StartCombat on ALL pairs
            ; in ForceInitialEngagement guarantees immediate engagement without needing
            ; Very Aggressive (which would attack civilians).
            soldier.AddToFaction(battleFaction)
            soldier.SetActorValue("Aggression", 1.0)  ; Aggressive — attacks faction enemies only
            soldier.SetActorValue("Confidence", 4.0)  ; Foolhardy — never flees

            ; Register with C++ BattleManager (tier 0 = generic soldier)
            ; C++ tracks all actors for cleanup — no Papyrus arrays needed
            IntelEngine.RegisterBattleActor(soldier, factionId, 0)

            ; kPlayerTeammate NOT set — causes cascade (allies defend player against
            ; retaliating ally → infighting → guards join). Battle faction handles it.

            ; Charge toward center marker (500 units ahead of player, on navmesh).
            ; Soldiers spawn 600 units BEHIND the player, so they run ~1100 units
            ; forward past the player toward the fight. StartCombat in
            ; ForceInitialEngagement ensures they engage when they meet.
            If CenterMarker
                soldier.PathToReference(CenterMarker, 0)  ; 0 = run, not walk
            EndIf

            ; Stagger every 2 soldiers with variance for natural stream-in
            If i > 0 && i % 2 == 0
                Utility.Wait(0.15 + Utility.RandomFloat(0.0, 0.15))
            EndIf
        EndIf
        i += 1
    EndWhile

    Core.DebugMsg("Battle: Spawned " + soldiers.Length + "/" + count + " soldiers for " + factionId + " at rally marker")
EndFunction

; =============================================================================
; PLAYER PARTICIPATION
; =============================================================================

Function EvaluatePlayerJoin()
    ; C++ handles all standing logic and join decision
    String resultJson = IntelEngine.EvaluatePlayerJoinBattle(QuestAutoJoinFaction)
    QuestAutoJoinFaction = ""

    Bool shouldJoin = IntelEngine.StoryResponseGetField(resultJson, "shouldJoin") == "true"
    If !shouldJoin
        Core.DebugMsg("Battle: Player is a spectator")
        return
    EndIf

    String joinFaction = IntelEngine.StoryResponseGetField(resultJson, "joinFaction")
    String displayName = IntelEngine.StoryResponseGetField(resultJson, "displayName")
    Bool isQuestJoin = IntelEngine.StoryResponseGetField(resultJson, "isQuestJoin") == "true"

    If isQuestJoin
        Debug.Notification("You join the " + displayName + " on the field.")
        Utility.Wait(1.0)
    Else
        Debug.Notification("The " + displayName + " soldiers recognize you as an ally.")
        Utility.Wait(2.0)
    EndIf

    JoinBattleSide(joinFaction)
EndFunction

Function JoinBattleSide(String factionId)
    ; Public entry point — can be called by EvaluatePlayerJoin (auto) or by
    ; Phase 4 SkyrimNet actions (intel_join_battle, intel_accept_recruitment)

    If PlayerBattleSide == factionId
        return  ; Already on this side
    EndIf

    ; Disallow side-switching — once committed, you're in for the battle
    If PlayerBattleSide != ""
        Core.DebugMsg("Battle: Cannot switch sides mid-battle (already on " + PlayerBattleSide + ")")
        return
    EndIf

    ; Tell C++ — applies morale boost (+15 ally, -5 enemy)
    Bool success = IntelEngine.SetPlayerBattleSide(factionId)
    If !success
        Core.DebugMsg("Battle: JoinBattleSide failed for " + factionId)
        return
    EndIf

    PlayerBattleSide = factionId

    ; Add player to the correct ESP battle faction using C++ normalization
    ; (ally faction is always SideA — don't assume DM ordering matches ESP sides)
    Actor player = Game.GetPlayer()
    String side = IntelEngine.GetFactionBattleSide(factionId)
    If side == "A"
        player.AddToFaction(Intel_BattleSideA)
    Else
        player.AddToFaction(Intel_BattleSideB)
    EndIf

    ; SetPlayerTeammate on existing soldiers is handled by C++ SetActorPlayerTeammate.
    ; The old Papyrus loop failed for 0xFF-prefix FormIDs (Game.GetForm overflow).
    ; C++ SetPlayerSide already sets teammates when called.
    IntelEngine.SetBattleSoldiersAsTeammates(side)

    String displayName = IntelEngine.GetFactionDisplayName(factionId)
    Debug.Notification("You fight alongside the " + displayName + ".")
    Core.DebugMsg("Battle: Player joined " + factionId + " (morale boosted)")
EndFunction

Function RemovePlayerFromBattle()
    ; Remove player from battle factions only.
    ; Crime faction removal/restoration is now quest-level (StoryEngine),
    ; not battle-level — covers the entire quest duration.
    If PlayerBattleSide == ""
        return
    EndIf

    Actor player = Game.GetPlayer()
    player.RemoveFromFaction(Intel_BattleSideA)
    player.RemoveFromFaction(Intel_BattleSideB)

    ; Clear C++ side
    IntelEngine.SetPlayerBattleSide("")

    Core.DebugMsg("Battle: Player removed from battle factions")
    PlayerBattleSide = ""
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
        Actor soldierA = Game.GetForm(formIdA) as Actor
        Actor soldierB = Game.GetForm(formIdB) as Actor
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

Function PostBattleSoldierMoment(String playerFaction, String victorName, Bool playerWon)
    ; Find a surviving ally via C++ actor list (no Papyrus arrays)
    String side = "A"
    If playerFaction != BattleFactionA
        side = "B"
    EndIf
    String json = IntelEngine.GetBattleSoldierFormIds(side)
    Int count = IntelEngine.StoryResponseGetField(json, "count") as Int
    Actor survivor = None
    Int i = 0
    While i < count && !survivor
        Int formId = IntelEngine.GetJsonArrayInt(json, "formIds", i)
        Actor soldier = Game.GetForm(formId) as Actor
        If soldier && !soldier.IsDead()
            survivor = soldier
        EndIf
        i += 1
    EndWhile
    If !survivor
        ; C++ generates the no-survivor notification text
        String noSurvivorType = "no_survivor_win"
        If !playerWon
            noSurvivorType = "no_survivor_loss"
        EndIf
        Debug.Notification(IntelEngine.GetBattleNotification(noSurvivorType, "", "", false))
        return
    EndIf
    ; Survivor walks toward player — weary pace (engine operations)
    Actor player = Game.GetPlayer()
    survivor.SetActorValue("SpeedMult", 70.0)
    survivor.PathToReference(player, 1)
    Float waitTime = 0.0
    While waitTime < 8.0 && survivor.GetDistance(player) > 200.0
        Utility.Wait(1.0)
        waitTime += 1.0
    EndWhile
    ; C++ generates the soldier dialogue text
    String dialogueType = "soldier_victory"
    If !playerWon
        dialogueType = "soldier_defeat"
    EndIf
    Debug.Notification("\"" + IntelEngine.GetBattleNotification(dialogueType, "", victorName, playerWon) + "\"")
    survivor.SetActorValue("SpeedMult", 100.0)
    Core.DebugMsg("Battle: Post-battle soldier moment — " + survivor.GetDisplayName())
EndFunction

; =============================================================================
; POLL HANDLING
; =============================================================================

Function HandlePollResult(String stateJson)
    ; Parse key fields from poll JSON
    Bool battleOver = IntelEngine.StoryResponseGetField(stateJson, "battle_over") == "true"
    String result = IntelEngine.StoryResponseGetField(stateJson, "result")
    String victor = IntelEngine.StoryResponseGetField(stateJson, "victor")

    ; Check wave spawn triggers
    If !battleOver
        Bool shouldSpawnA = IntelEngine.StoryResponseGetField(stateJson, "should_spawn_wave_a") == "true"
        Bool shouldSpawnB = IntelEngine.StoryResponseGetField(stateJson, "should_spawn_wave_b") == "true"

        Int cppWave = IntelEngine.GetBattleCurrentWave()
        If (shouldSpawnA || shouldSpawnB) && cppWave < 5
            SpawnWave(cppWave + 1)
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

Function HandleBattleEnd(String result, String victor, String stateJson)
    Core.DebugMsg("Battle: Ended — result=" + result + ", victor=" + victor)

    ; Stop polling immediately to prevent race with OnUpdate
    UnregisterForUpdate()

    ; Count casualties via C++ (no Papyrus arrays needed)
    Int lossesA = IntelEngine.CountDeadBattleSoldiers("A")
    Int lossesB = IntelEngine.CountDeadBattleSoldiers("B")

    ; C++ handles ALL game logic: standings, narrative, political events, witness facts, end battle
    ; MUST run BEFORE RemovePlayerFromBattle — FinalizeBattle reads playerSide to award standing.
    String resultJson = IntelEngine.FinalizeBattle(ActiveBattleId, result, victor, \
        lossesA, lossesB, BattleLocationName, Utility.GetCurrentGameTime())

    ; Do NOT remove player from battle factions here — soldiers are still alive during
    ; deferred cleanup. Removing the player from the faction makes stray-hit soldiers
    ; hostile again. RemovePlayerFromBattle is called when cleanup finishes (OnUpdate Phase 0).

    ; Parse C++ result for engine-only operations (notifications, soldier moment, cleanup)
    String playerSideWas = IntelEngine.StoryResponseGetField(resultJson, "playerSideWas")
    Bool playerWon = IntelEngine.StoryResponseGetField(resultJson, "playerWon") == "true"
    String notification = IntelEngine.StoryResponseGetField(resultJson, "notification")
    String spectatorNotif = IntelEngine.StoryResponseGetField(resultJson, "spectatorNotification")
    String witnessFact = IntelEngine.StoryResponseGetField(resultJson, "witnessFact")

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
        Debug.Notification(notification)
    EndIf
    If spectatorNotif != ""
        Utility.Wait(1.5)
        Debug.Notification(spectatorNotif)
    EndIf

    ; Post-battle soldier moment (engine-only: PathToReference, GetDistance)
    If playerSideWas != ""
        String victorName = IntelEngine.StoryResponseGetField(resultJson, "victorName")
        PostBattleSoldierMoment(playerSideWas, victorName, playerWon)
    EndIf

    ; Deferred cleanup — soldiers stay until player leaves
    DeferredCleanupActive = true
    DeferredCleanupStart = Utility.GetCurrentRealTime()
    RegisterForSingleUpdate(PollInterval)
EndFunction

; ApplyPlayerKillStanding, ApplyPostBattleStanding, ApplySpectatorConsequences,
; InjectBattleWitnessMemories — ALL moved to C++ FinalizeBattle. Deleted.

; CountDeadInArray — REMOVED. Superseded by C++ IntelEngine.CountDeadBattleSoldiers()
; CleanupActorsByProximity — REMOVED. Superseded by C++ IntelEngine.CleanupBattleSoldiers()

; =============================================================================
; CLEANUP
; =============================================================================

Function CleanupAllActors()
    ; Delegated entirely to C++ — no Papyrus arrays needed
    IntelEngine.ForceCleanupAllSoldiers()
EndFunction

; CleanupActorArray — REMOVED. C++ ForceCleanupAllSoldiers handles all cleanup.

Function CleanupMarkers()
    If CenterMarker
        CenterMarker.DisableNoWait()
        CenterMarker.Delete()
        CenterMarker = None
    EndIf
    If RallyMarkerA
        RallyMarkerA.DisableNoWait()
        RallyMarkerA.Delete()
        RallyMarkerA = None
    EndIf
    If RallyMarkerB
        RallyMarkerB.DisableNoWait()
        RallyMarkerB.Delete()
        RallyMarkerB = None
    EndIf
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
    UnregisterForUpdate()
    UnregisterForUpdateGameTime()
EndFunction

; =============================================================================
; POLITICAL EVENT MANIFESTATION (micro-encounters)
; =============================================================================

Function ManifestEvent(String manifestJson)
    ; Guard: no active battle, manifestation, or faction ambush; player must be in exterior
    If IntelEngine.IsBattleActive() || ManifestActive
        Core.DebugMsg("Battle: Cannot manifest — battle or manifestation already active")
        return
    EndIf
    If Core != None && Core.StoryEngine != None && Core.StoryEngine.FactionAmbushActive
        Core.DebugMsg("Battle: Cannot manifest — faction ambush already active")
        return
    EndIf
    If !IsPlayerInExterior()
        Core.DebugMsg("Battle: Cannot manifest — player is indoors")
        return
    EndIf

    ; Parse manifest JSON
    String eventType = IntelEngine.StoryResponseGetField(manifestJson, "event_type")
    String attackerFaction = IntelEngine.StoryResponseGetField(manifestJson, "attacker_faction")
    String targetFaction = IntelEngine.StoryResponseGetField(manifestJson, "target_faction")
    Int spawnCount = IntelEngine.StoryResponseGetField(manifestJson, "spawn_count") as Int
    Bool spawnDefenders = IntelEngine.StoryResponseGetField(manifestJson, "spawn_defenders") == "true"
    Int defenderCount = IntelEngine.StoryResponseGetField(manifestJson, "defender_count") as Int

    If attackerFaction == "" || spawnCount <= 0
        return
    EndIf

    Actor player = Game.GetPlayer()
    ManifestActors = new Actor[12]
    ManifestCount = 0

    ; Pre-calculate spawn offset — actors spawn at offset, not at player position
    Float playerAngle = player.GetAngleZ()

    ; Batch spawn attackers in C++, then position from Papyrus
    Int attackCap = 12 - ManifestCount
    If spawnCount < attackCap
        attackCap = spawnCount
    EndIf
    Actor[] attackers = IntelEngine.SpawnBattleSoldiers(attackerFaction + ":" + attackCap, player)

    Int i = 0
    While i < attackers.Length
        If attackers[i]
            ; Position behind player at distance so they approach naturally
            Float angle = playerAngle + 180.0 + Utility.RandomFloat(-60.0, 60.0)
            Float dist = Utility.RandomFloat(1500.0, 2500.0)
            Float offsetX = Math.Sin(angle) * dist
            Float offsetY = Math.Cos(angle) * dist
            attackers[i].MoveTo(player, offsetX, offsetY, 0.0)
            attackers[i].AddToFaction(Intel_BattleSideA)
            ManifestActors[ManifestCount] = attackers[i]
            ManifestCount += 1
        EndIf
        i += 1
    EndWhile

    ; Guard: if no attackers spawned, abort entirely
    If ManifestCount == 0
        Core.DebugMsg("Battle: Manifest failed — no attackers spawned")
        return
    EndIf

    ; Handle combat targeting based on event type
    ; Note: ConfirmManifestationCooldown is called AFTER verifying combat can start,
    ; not here — assassination may abort if leader isn't loaded
    If eventType == "assassination_attempt"
        ; Find target faction leader near player
        Actor[] leaders = IntelEngine.GetFactionLeaderActors(targetFaction)
        Actor target = None
        Int j = 0
        While j < leaders.Length && target == None
            If leaders[j] != None
                target = leaders[j]
            EndIf
            j += 1
        EndWhile

        If target != None
            ; Assassins attack the leader
            i = 0
            While i < ManifestCount
                If ManifestActors[i] != None
                    ManifestActors[i].StartCombat(target)
                EndIf
                i += 1
            EndWhile
            IntelEngine.ConfirmManifestationCooldown()
            Core.DebugMsg("Battle: Manifest assassination — " + ManifestCount + " assassins targeting leader")
        Else
            ; Leader not loaded — abort manifestation, let it be an off-screen event
            ; Player will hear about it through NPC gossip instead
            Core.DebugMsg("Battle: Manifest assassination — leader not loaded, aborting")
            i = 0
            While i < ManifestCount
                If ManifestActors[i] != None
                    ManifestActors[i].DisableNoWait()
                    ManifestActors[i].Delete()
                    ManifestActors[i] = None
                EndIf
                i += 1
            EndWhile
            ManifestCount = 0
            ManifestActive = false
            return
        EndIf

    ElseIf spawnDefenders && defenderCount > 0
        ; Brawl / border skirmish — batch spawn defenders, then position
        Int defStart = ManifestCount
        Int defCap = 12 - ManifestCount
        If defenderCount < defCap
            defCap = defenderCount
        EndIf
        Actor[] defenders = IntelEngine.SpawnBattleSoldiers(targetFaction + ":" + defCap, player)

        i = 0
        While i < defenders.Length
            If defenders[i]
                ; Position offset from attackers (opposite side of player)
                Float angle = playerAngle + Utility.RandomFloat(-45.0, 45.0)
                Float dist = Utility.RandomFloat(800.0, 1200.0)
                Float offsetX = Math.Sin(angle) * dist
                Float offsetY = Math.Cos(angle) * dist
                defenders[i].MoveTo(player, offsetX, offsetY, 0.0)
                defenders[i].AddToFaction(Intel_BattleSideB)
                ManifestActors[ManifestCount] = defenders[i]
                ManifestCount += 1
            EndIf
            i += 1
        EndWhile

        ; Only start combat if we have defenders
        If ManifestCount > defStart
            ; Make attackers fight defenders
            i = 0
            While i < defStart
                If ManifestActors[i] != None
                    Int k = defStart
                    While k < ManifestCount
                        If ManifestActors[k] != None
                            ManifestActors[i].StartCombat(ManifestActors[k])
                        EndIf
                        k += 1
                    EndWhile
                EndIf
                i += 1
            EndWhile
            IntelEngine.ConfirmManifestationCooldown()
            Core.DebugMsg("Battle: Manifest " + eventType + " — " + defStart + " vs " + (ManifestCount - defStart))
        Else
            ; No defenders — abort manifestation (attackers with no targets is immersion-breaking)
            Core.DebugMsg("Battle: Manifest " + eventType + " — no defenders spawned, aborting")
            i = 0
            While i < ManifestCount
                If ManifestActors[i] != None
                    ManifestActors[i].DisableNoWait()
                    ManifestActors[i].Delete()
                    ManifestActors[i] = None
                EndIf
                i += 1
            EndWhile
            ManifestCount = 0
            ManifestActive = false
            return
        EndIf
    EndIf

    ; Show notification
    String nameA = IntelEngine.GetFactionDisplayName(attackerFaction)
    String nameB = IntelEngine.GetFactionDisplayName(targetFaction)
    If eventType == "assassination_attempt"
        Debug.Notification(nameA + " assassins strike!")
    ElseIf eventType == "brawl"
        Debug.Notification("A brawl erupts between " + nameA + " and " + nameB + "!")
    ElseIf eventType == "border_skirmish"
        Debug.Notification(nameA + " skirmishers clash with " + nameB + " forces!")
    EndIf

    ManifestActive = true
    ManifestStartTime = Utility.GetCurrentRealTime()
    RegisterForSingleUpdate(PollInterval)
EndFunction

Function CleanupManifestation()
    Core.DebugMsg("Battle: Cleaning up manifestation (" + ManifestCount + " actors)")
    Int i = 0
    While i < ManifestCount
        If ManifestActors[i] != None
            If ManifestActors[i].IsDead()
                ManifestActors[i].DisableNoWait()
                ManifestActors[i].Delete()
            Else
                ; Living actors: remove from battle factions, let them wander off
                ManifestActors[i].RemoveFromFaction(Intel_BattleSideA)
                ManifestActors[i].RemoveFromFaction(Intel_BattleSideB)
            EndIf
            ManifestActors[i] = None
        EndIf
        i += 1
    EndWhile
    ManifestCount = 0
    ManifestActive = false
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
    Int startMsg = Utility.RandomInt(0, 2)
    If startMsg == 0
        Debug.Notification("Soldiers clash near " + locationName + ".")
    ElseIf startMsg == 1
        Debug.Notification("A skirmish breaks out at " + locationName + ".")
    Else
        Debug.Notification("Armed men trade blows near " + locationName + ".")
    EndIf
EndFunction

Function CleanupBattle()
    ; Called when battle ended unexpectedly (e.g., PollBattleState returned "{}")
    Core.DebugMsg("Battle: Unexpected end — cleaning up")
    RemovePlayerFromBattle()
    CleanupAllActors()
    CleanupMarkers()
    ResetState()
EndFunction

; =============================================================================
; SAVE/LOAD SAFETY
; =============================================================================

Function OnGameReload()
    ; Clean up any active manifestation from pre-reload
    If ManifestActive
        CleanupManifestation()
    EndIf

    ; If a battle was in progress when the game was saved, clean up
    ; Battle state is not save-persistent in C++ (BattleManager resets on load)
    ; ActiveBattleId >= 0 catches battles that started but never spawned (player was indoors)
    If BattleSpawned || BattleScheduled || ActiveBattleId >= 0
        Core.DebugMsg("Battle: Game reloaded during active battle — cleaning up")
        ; Clear C++ active battle BEFORE Papyrus ResetState (which sets ActiveBattleId = -1)
        IntelEngine.EndBattle(ActiveBattleId, "reload", "")
        RemovePlayerFromBattle()
        CleanupAllActors()
        CleanupMarkers()
        ResetState()
    EndIf

    ; Clear stale pending battles from C++ singleton (persists across reloads)
    IntelEngine.ClearPendingBattles()
    PendingPollActive = false
EndFunction
