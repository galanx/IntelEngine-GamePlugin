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
Int Property SpawnDistance = 1000 Auto Hidden  ; units from center to each rally point
Float Property BattleSpawnDistance = 2000.0 Auto Hidden  ; units ahead of player toward battle location
Float Property PollInterval = 3.0 Auto Hidden  ; seconds between state polls
Float Property CenterSpawnDistance = 800.0 Auto Hidden  ; units ahead of player for battle center
Float Property MidBattleCasualtyRate = 2.0 Auto Hidden  ; game-minutes per casualty during off-screen
Float Property MidBattleMoraleRate = 5.0 Auto Hidden    ; morale loss per game-minute off-screen
Int Property MidBattleMoraleCap = 60 Auto Hidden        ; max morale loss from off-screen time
Int Property MidBattleMinSoldiers = 3 Auto Hidden       ; minimum soldiers per side for mid-battle

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

; Spawn tracking (FormList would be better but arrays work for actor cap of ~35)
Actor[] Property SideAActors Auto Hidden
Actor[] Property SideBActors Auto Hidden
Int Property SideACount = 0 Auto Hidden
Int Property SideBCount = 0 Auto Hidden

; Spawn anchor markers (placed dynamically, cleaned up after battle)
ObjectReference Property CenterMarker Auto Hidden
ObjectReference Property RallyMarkerA Auto Hidden
ObjectReference Property RallyMarkerB Auto Hidden

; Wave tracking
Int Property CurrentWave = 0 Auto Hidden

; Player participation
String Property PlayerBattleSide = "" Auto Hidden

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
    String xStr = IntelEngine.StoryResponseGetField(infoJson, "x")
    String yStr = IntelEngine.StoryResponseGetField(infoJson, "y")
    String zStr = IntelEngine.StoryResponseGetField(infoJson, "z")

    ; Validate coordinates — empty strings cast to 0.0 which would spawn at world origin
    If xStr == "" || yStr == "" || zStr == ""
        Core.DebugMsg("Battle: Pending battle " + pendingId + " has invalid coordinates — aborting")
        return
    EndIf

    ; Set up battle state
    BattleFactionA = factionA
    BattleFactionB = factionB
    BattleLocationName = locName

    ; Find the war ID for this faction pair
    BattleWarId = IntelEngine.GetActiveWarId(factionA, factionB)

    ; Parse coordinates — used to calculate direction from player to battle
    Float battleX = xStr as Float
    Float battleY = yStr as Float
    Float battleZ = zStr as Float

    ; Start battle in C++ BattleManager
    ActualBattleStartTime = Utility.GetCurrentGameTime()
    ActiveBattleId = IntelEngine.StartBattle(factionA, factionB, locName, BattleWarId)
    If ActiveBattleId < 0
        Core.DebugMsg("Battle: C++ StartBattle failed (another battle active?)")
        ResetState()
        return
    EndIf

    ; Initialize actor arrays
    SideAActors = new Actor[15]
    SideBActors = new Actor[15]
    SideACount = 0
    SideBCount = 0
    CurrentWave = 0
    BattleSpawned = true

    ; Ensure battle factions are hostile to each other
    Intel_BattleSideA.SetEnemy(Intel_BattleSideB)

    ; Place markers ahead of the player in the direction of the battle location.
    ; Spawning at the actual battle coordinates fails because SetPosition moves
    ; XMarkers outside the loaded cell grid, making PlaceObjectAtMe silently fail.
    PlaceMarkersTowardBattle(battleX, battleY)

    ShowBattleStartNotification(locName)

    ; Spawn vanguard wave
    SpawnWave(1)

    ; Check if player should auto-join based on faction standing
    EvaluatePlayerJoin()

    ; Start active battle polling
    RegisterForSingleUpdate(PollInterval)

    Core.DebugMsg("Battle: Triggered at " + locName + " (battle coords: " + battleX + ", " + battleY + \
        ", spawned near player) — " + factionA + " vs " + factionB)
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
    ActiveBattleId = IntelEngine.StartBattle(BattleFactionA, BattleFactionB, BattleLocationName, BattleWarId)
    If ActiveBattleId < 0
        Core.DebugMsg("Battle: C++ StartBattle failed (another battle active?)")
        ResetState()
        return
    EndIf

    ; Initialize actor arrays (size must match MaxSoldiersPerSide)
    SideAActors = new Actor[22]
    SideBActors = new Actor[22]
    SideACount = 0
    SideBCount = 0
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

    ; Calculate dynamic positions based on player
    CalculateAndPlaceMarkers()

    ShowBattleStartNotification(BattleLocationName)

    ; Spawn vanguard wave (wave 1) at rally points — soldiers march toward center
    SpawnWave(1)

    ; Check if player should auto-join based on faction standing
    EvaluatePlayerJoin()

    ; Start polling
    RegisterForSingleUpdate(PollInterval)
EndFunction

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
    Int count = GetWaveSoldierCount(waveNum)
    Core.DebugMsg("Battle: Spawning wave " + waveNum + " — " + count + " soldiers per side")

    ; Spawn at rally points — soldiers will march toward center
    SpawnSoldiersAtMarker(BattleFactionA, RallyMarkerA, count, true)
    SpawnSoldiersAtMarker(BattleFactionB, RallyMarkerB, count, false)

    CurrentWave = waveNum
    IntelEngine.AdvanceBattleWave()

    ; Wave notification (non-LLM — visual feedback only, randomized for replay variety)
    Utility.Wait(1.5 + Utility.RandomFloat(0.0, 1.5))
    Int variant = Utility.RandomInt(0, 2)
    If waveNum == 1
        If variant == 0
            Debug.Notification("The vanguard charges forward.")
        ElseIf variant == 1
            Debug.Notification("The first wave advances into position.")
        Else
            Debug.Notification("Soldiers pour onto the battlefield.")
        EndIf
    ElseIf waveNum == 2
        If variant == 0
            Debug.Notification("Reinforcements arrive from the flanks.")
        ElseIf variant == 1
            Debug.Notification("Fresh soldiers pour into the fray.")
        Else
            Debug.Notification("A horn sounds — more troops advance.")
        EndIf
    ElseIf waveNum == 3
        If variant == 0
            Debug.Notification("The reserves commit to the final push.")
        ElseIf variant == 1
            Debug.Notification("The last of the reserves march forward.")
        Else
            Debug.Notification("Every remaining soldier enters the battle.")
        EndIf
    EndIf
EndFunction

Int Function GetWaveSoldierCount(Int waveNum)
    ; Total across all waves MUST NOT exceed MaxSoldiersPerSide (22) / Actor array size.
    ; 10+7+5 = 22.
    If waveNum == 1
        return 10  ; vanguard
    ElseIf waveNum == 2
        return 7   ; reinforcements
    ElseIf waveNum == 3
        return 5   ; reserves + leader
    EndIf
    return 5
EndFunction

Function SpawnSoldiersAtMarker(String factionId, ObjectReference marker, Int count, Bool isSideA)
    If !marker
        Core.DebugMsg("Battle: SpawnSoldiersAtMarker — marker is None!")
        return
    EndIf

    ; Cap total soldiers per side
    Int currentCount = 0
    If isSideA
        currentCount = SideACount
    Else
        currentCount = SideBCount
    EndIf
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

            ; Spread offset from spawn point so they don't stack
            Float offsetX = Utility.RandomFloat(-200.0, 200.0)
            Float offsetY = Utility.RandomFloat(-200.0, 200.0)
            soldier.MoveTo(marker, offsetX, offsetY, 0.0)

            ; Add to battle faction for hostility
            soldier.AddToFaction(battleFaction)
            soldier.SetActorValue("Aggression", 1.0)
            soldier.SetActorValue("Confidence", 3.0)

            ; Register with C++ BattleManager (tier 0 = generic soldier)
            IntelEngine.RegisterBattleActor(soldier, factionId, 0)

            ; Store reference for cleanup
            If isSideA
                If SideACount < SideAActors.Length
                    SideAActors[SideACount] = soldier
                    SideACount += 1
                EndIf
            Else
                If SideBCount < SideBActors.Length
                    SideBActors[SideBCount] = soldier
                    SideBCount += 1
                EndIf
            EndIf

            ; March toward center (combat AI takes over when they detect enemies)
            If CenterMarker
                soldier.PathToReference(CenterMarker, 1)
            EndIf

            ; Stagger spawns so soldiers stream in rather than all popping at once
            If i > 0 && i % 2 == 0
                Utility.Wait(0.3)
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
    ; Check player standing with both factions to determine if they auto-join
    ; Standing >= 20 with exactly ONE side: auto-join that side
    ; Standing >= 20 with both: remain spectator (Phase 4 dialogue prompt decides)
    ; Standing < 20 with both: spectator

    Int standingA = IntelEngine.GetPlayerFactionStanding(BattleFactionA)
    Int standingB = IntelEngine.GetPlayerFactionStanding(BattleFactionB)

    Core.DebugMsg("Battle: Player standing — " + BattleFactionA + "=" + standingA + ", " + BattleFactionB + "=" + standingB)

    String joinSide = ""
    If standingA >= AutoJoinStandingThreshold && standingB >= AutoJoinStandingThreshold
        ; Positive with both — stay neutral, Phase 4 lets factions ask the player via dialogue
        Core.DebugMsg("Battle: Player has standing with both sides — remaining spectator until asked")
    ElseIf standingA >= AutoJoinStandingThreshold
        joinSide = BattleFactionA
    ElseIf standingB >= AutoJoinStandingThreshold
        joinSide = BattleFactionB
    EndIf

    If joinSide != ""
        ; Recognition beat — let the player process before committing
        String displayName = IntelEngine.GetFactionDisplayName(joinSide)
        Debug.Notification("The " + displayName + " soldiers recognize you as an ally.")
        Utility.Wait(2.0)
        JoinBattleSide(joinSide)
    Else
        Core.DebugMsg("Battle: Player is a spectator")
    EndIf
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

    ; Add player to the correct ESP battle faction for hostility
    Actor player = Game.GetPlayer()
    If factionId == BattleFactionA
        player.AddToFaction(Intel_BattleSideA)
        ; Player is now allied with side A, hostile to side B (factions are enemies)
    Else
        player.AddToFaction(Intel_BattleSideB)
    EndIf

    String displayName = IntelEngine.GetFactionDisplayName(factionId)
    Debug.Notification("You fight alongside the " + displayName + ".")
    Core.DebugMsg("Battle: Player joined " + factionId + " (morale boosted)")
EndFunction

Function RemovePlayerFromBattle()
    ; Remove player from battle factions — called on battle end and cleanup
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
        If (shouldSpawnA || shouldSpawnB) && cppWave < 3
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

    ; Capture player side before it's cleared
    String playerSideWas = PlayerBattleSide

    ; Apply kill-based standing penalties (player killed soldiers from a faction)
    Int playerKillsA = IntelEngine.StoryResponseGetField(stateJson, "player_kills_a") as Int
    Int playerKillsB = IntelEngine.StoryResponseGetField(stateJson, "player_kills_b") as Int
    ApplyPlayerKillStanding(playerKillsA, playerKillsB)

    ; Apply player standing changes BEFORE ending battle (so IsBattleFaction still works)
    ApplyPostBattleStanding(victor)

    ; Remove player from battle factions
    RemovePlayerFromBattle()

    ; End in C++
    IntelEngine.EndBattle(ActiveBattleId, result, victor)

    ; Record as off-screen battle in DB for political consequences
    String victorName = IntelEngine.GetFactionDisplayName(victor)
    String loser = BattleFactionA
    If victor == BattleFactionA
        loser = BattleFactionB
    EndIf
    String loserName = IntelEngine.GetFactionDisplayName(loser)

    ; Count casualties
    Int lossesA = CountDeadInArray(SideAActors, SideACount)
    Int lossesB = CountDeadInArray(SideBActors, SideBCount)

    ; Record in political DB (plain text narrative — display names are from factions.yaml, safe for concat)
    String playerName = Game.GetPlayer().GetDisplayName()
    String narrative = victorName + " defeated " + loserName + " at " + BattleLocationName
    If playerSideWas != ""
        narrative += ". " + playerName + " fought for " + IntelEngine.GetFactionDisplayName(playerSideWas)
        Int playerTotalKills = playerKillsA + playerKillsB
        If playerTotalKills > 0
            narrative += ", personally killing " + playerTotalKills + " soldiers"
        EndIf
    EndIf
    IntelEngine.RecordOffScreenBattle(BattleFactionA, BattleFactionB, BattleLocationName, \
        result, narrative, lossesA, lossesB, victor)

    ; Record player kill events as political events so factions track what the player did.
    ; Delta is 0 — standing was already adjusted by ApplyPlayerKillStanding above.
    ; This event is purely for visibility in the political event log and NPC awareness.
    Float gameTime = Utility.GetCurrentGameTime()
    If playerKillsA > 0
        String killDescA = playerName + " killed " + playerKillsA + " " + IntelEngine.GetFactionDisplayName(BattleFactionA) + " soldiers during the battle at " + BattleLocationName
        IntelEngine.RecordPoliticalEvent(BattleFactionA, "", "player_combat", killDescA, 0, gameTime)
    EndIf
    If playerKillsB > 0
        String killDescB = playerName + " killed " + playerKillsB + " " + IntelEngine.GetFactionDisplayName(BattleFactionB) + " soldiers during the battle at " + BattleLocationName
        IntelEngine.RecordPoliticalEvent(BattleFactionB, "", "player_combat", killDescB, 0, gameTime)
    EndIf

    ; Inject battle memories into nearby named NPCs who witnessed the fight
    InjectBattleWitnessMemories(victorName, loserName, lossesA + lossesB, playerSideWas, playerKillsA + playerKillsB)

    ; Victory/defeat notification (non-LLM — avoids triggering evaluation cycle)
    If playerSideWas == victor
        Debug.Notification("The " + victorName + " banner stands over " + BattleLocationName + ". The battle is yours.")
    ElseIf playerSideWas != ""
        Debug.Notification("The field is lost. " + victorName + " forces hold " + BattleLocationName + ".")
    Else
        Debug.Notification("The fighting ends. " + victorName + " banners now fly over " + BattleLocationName + ".")
    EndIf

    ; Cleanup all remaining actors after a randomized delay (avoids mechanical feel)
    Utility.Wait(8.0 + Utility.RandomFloat(0.0, 5.0))
    CleanupAllActors()
    CleanupMarkers()
    ResetState()
EndFunction

Function ApplyPlayerKillStanding(Int killsA, Int killsB)
    ; Penalize standing with factions whose soldiers the player killed.
    ; Killing your OWN side's soldiers still penalizes — friendly fire isn't free.
    If killsA > 0
        Int penaltyA = killsA * KillStandingPenaltyPerSoldier
        IntelEngine.AdjustPlayerFactionStanding(BattleFactionA, penaltyA)
        Core.DebugMsg("Battle: Player killed " + killsA + " " + BattleFactionA + " soldiers (" + penaltyA + " standing)")
    EndIf
    If killsB > 0
        Int penaltyB = killsB * KillStandingPenaltyPerSoldier
        IntelEngine.AdjustPlayerFactionStanding(BattleFactionB, penaltyB)
        Core.DebugMsg("Battle: Player killed " + killsB + " " + BattleFactionB + " soldiers (" + penaltyB + " standing)")
    EndIf
EndFunction

Function ApplyPostBattleStanding(String victor)
    If victor == ""
        return
    EndIf

    ; Spectator consequences — player was present but chose not to fight
    If PlayerBattleSide == ""
        ApplySpectatorConsequences(victor)
        return
    EndIf

    String enemy = GetEnemyFaction()
    Bool playerWon = (PlayerBattleSide == victor)

    If playerWon
        IntelEngine.AdjustPlayerFactionStanding(PlayerBattleSide, VictoryAllyBonus)
        IntelEngine.AdjustPlayerFactionStanding(enemy, VictoryEnemyPenalty)
        Debug.Notification("The " + IntelEngine.GetFactionDisplayName(PlayerBattleSide) + " honored your valor on the battlefield.")
        Core.DebugMsg("Battle: Player victory — +" + VictoryAllyBonus + " " + PlayerBattleSide + ", " + VictoryEnemyPenalty + " " + enemy)
    Else
        IntelEngine.AdjustPlayerFactionStanding(PlayerBattleSide, DefeatAllyBonus)
        IntelEngine.AdjustPlayerFactionStanding(enemy, DefeatEnemyPenalty)
        Core.DebugMsg("Battle: Player defeat — +" + DefeatAllyBonus + " " + PlayerBattleSide + ", " + DefeatEnemyPenalty + " " + enemy)
    EndIf

    ; Update political state file so NPCs see new standings
    IntelEngine.WritePoliticalStateFile()
EndFunction

Function ApplySpectatorConsequences(String victor)
    ; Player watched the battle without joining — both sides notice
    ; Only penalize factions the player has meaningful standing with
    ; If standing >= join threshold with BOTH sides, no penalty — player was correctly
    ; held as neutral (Phase 4 dialogue decides). Penalizing before being asked is unfair.

    Int standingA = IntelEngine.GetPlayerFactionStanding(BattleFactionA)
    Int standingB = IntelEngine.GetPlayerFactionStanding(BattleFactionB)

    ; Skip penalty when player was deliberately neutral (high standing with both)
    If standingA >= AutoJoinStandingThreshold && standingB >= AutoJoinStandingThreshold
        Core.DebugMsg("Battle: Spectator — no penalty (standing with both sides, awaiting Phase 4 recruitment)")
        return
    EndIf

    Bool penalized = false

    If standingA >= SpectatorPenaltyThreshold
        IntelEngine.AdjustPlayerFactionStanding(BattleFactionA, SpectatorPenalty)
        Core.DebugMsg("Battle: Spectator penalty — " + SpectatorPenalty + " " + BattleFactionA + " (had standing " + standingA + ")")
        penalized = true
    EndIf

    If standingB >= SpectatorPenaltyThreshold
        IntelEngine.AdjustPlayerFactionStanding(BattleFactionB, SpectatorPenalty)
        Core.DebugMsg("Battle: Spectator penalty — " + SpectatorPenalty + " " + BattleFactionB + " (had standing " + standingB + ")")
        penalized = true
    EndIf

    If penalized
        Debug.Notification("Your inaction has not gone unnoticed.")
        IntelEngine.WritePoliticalStateFile()
    EndIf
EndFunction

Function InjectBattleWitnessMemories(String victorName, String loserName, Int totalCasualties, String playerSide, Int playerKills)
    ; Find named NPCs near the battle who witnessed the fighting
    Actor player = Game.GetPlayer()
    Actor[] witnesses = IntelEngine.GetNearbyWitnessNPCs(player, 5000.0)

    If witnesses.Length == 0
        Core.DebugMsg("Battle: No nearby witness NPCs found for memory injection")
        return
    EndIf

    ; Build fact text — past tense, factual, no emotion (let LLM decide feelings)
    String fact = "witnessed a battle between " + victorName + " and " + loserName + " forces at " + BattleLocationName + ". " + victorName + " prevailed"
    If totalCasualties > 0
        fact += " with " + totalCasualties + " casualties"
    EndIf
    String playerName = player.GetDisplayName()
    If playerSide != ""
        fact += ". " + playerName + " fought for " + IntelEngine.GetFactionDisplayName(playerSide)
        If playerKills > 0
            fact += " and killed " + playerKills + " enemy soldiers"
        EndIf
    EndIf

    Int injected = 0
    Int i = 0
    While i < witnesses.Length
        If witnesses[i] != None
            Core.InjectFact(witnesses[i], fact)
            injected += 1
        EndIf
        i += 1
    EndWhile

    Core.DebugMsg("Battle: Injected battle witness memories into " + injected + " nearby NPCs")
EndFunction

Int Function CountDeadInArray(Actor[] arr, Int count)
    Int dead = 0
    Int i = 0
    While i < count
        If !arr[i] || arr[i].IsDead()
            dead += 1
        EndIf
        i += 1
    EndWhile
    return dead
EndFunction

; =============================================================================
; CLEANUP
; =============================================================================

Function CleanupAllActors()
    CleanupActorArray(SideAActors, SideACount)
    CleanupActorArray(SideBActors, SideBCount)
EndFunction

Function CleanupActorArray(Actor[] arr, Int count)
    Int i = 0
    While i < count
        If arr[i]
            arr[i].DisableNoWait()
            arr[i].Delete()
            arr[i] = None
        EndIf
        ; Stagger cleanup so bodies fade in a wave, not all at once
        If i % 3 == 2
            Utility.Wait(0.3)
        EndIf
        i += 1
    EndWhile
EndFunction

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
    BattleFactionA = ""
    BattleFactionB = ""
    BattleWarId = 0
    ScheduledBattleTime = 0.0
    BattleScheduled = false
    BattleSpawned = false
    ActiveBattleId = -1
    BattleLocationName = ""
    SideACount = 0
    SideBCount = 0
    CurrentWave = 0
    ActualBattleStartTime = 0.0
    PlayerBattleSide = ""
    UnregisterForUpdate()
    UnregisterForUpdateGameTime()
EndFunction

; =============================================================================
; POLITICAL EVENT MANIFESTATION (micro-encounters)
; =============================================================================

Function ManifestEvent(String manifestJson)
    ; Guard: no active battle or manifestation, player must be in exterior
    If IntelEngine.IsBattleActive() || ManifestActive
        Core.DebugMsg("Battle: Cannot manifest — battle or manifestation already active")
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

String Function GetEnemyFaction()
    ; Returns the faction opposing the player's battle side
    If PlayerBattleSide == BattleFactionA
        return BattleFactionB
    EndIf
    return BattleFactionA
EndFunction

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
        Debug.Notification("War drums echo across " + locationName + ". Two armies approach.")
    ElseIf startMsg == 1
        Debug.Notification("The clash of arms erupts near " + locationName + ".")
    Else
        Debug.Notification("Battle standards are raised at " + locationName + ".")
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
