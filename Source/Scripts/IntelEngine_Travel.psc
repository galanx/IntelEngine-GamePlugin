Scriptname IntelEngine_Travel extends Quest
{
    IntelEngine Travel & Navigation System v1.0

    Intelligent navigation supporting:
    - Named locations (Whiterun, Bannered Mare)
    - Semantic locations (upstairs, outside, the back room)
    - Fuzzy matching (whiterun, white run, the cloud district)

    NPCs travel naturally on foot.
    MoveTo used as last resort after repeated stuck recovery failures.

    Follows SeverActions patterns for reliability.
}

; =============================================================================
; PROPERTIES - From Core
; =============================================================================

IntelEngine_Core Property Core Auto
{Reference to core script for slot management}

; =============================================================================
; CONSTANTS
; =============================================================================

; STUCK_DISTANCE_THRESHOLD, LINGER_APPROACH_DISTANCE, LINGER_FAR_TICKS_LIMIT,
; DEPARTURE_CHECK_CYCLES are defined on Core (single source of truth).

Float Property MAX_TASK_HOURS = 24.0 AutoReadOnly
{Game hours before an off-screen travel task is force-completed. Safety net for
NPCs whose 3D never loads (player never visits their cell), so position-based
stuck detection never fires. Travel uses 24h (longer than NPCTasks' 6h) because
cross-worldspace travel legitimately takes longer.}

Float Property MIN_WAIT_HOURS = 6.0 AutoReadOnly
Float Property MAX_WAIT_HOURS = 168.0 AutoReadOnly
Float Property DEFAULT_WAIT_HOURS = 48.0 AutoReadOnly

Float Property MEETING_LINGER_RELEASE_DISTANCE = 800.0 AutoReadOnly
{Player must walk this far from NPC to end the meeting linger}

Float Property MEETING_PLAYER_PROXIMITY = 2000.0 AutoReadOnly
{If player is within this distance of meeting destination, NPC starts walking toward them}

Float Property LEAPFROG_MAX_DISTANCE = 2000.0 AutoReadOnly
{Maximum leapfrog distance (last resort). Actual distance is progressive:
500u first attempt, 1000u second, 2000u third+. Keeps NPC visible to the
player while still clearing pathfinding dead zones at cell boundaries.}

Function EnsureMonitoringAlive()
    {Lightweight heartbeat: if active travel tasks exist, re-register the update loop.
    Called by Schedule's game-time loop as a safety net against Papyrus VM stack dumps
    that can kill RegisterForSingleUpdate callbacks.
    Does NOT re-apply packages — just ensures the monitoring loop is alive.}
    Int i = 0
    While i < Core.MAX_SLOTS
        If Core.SlotStates[i] != 0 && Core.SlotTaskTypes[i] == "travel"
            RegisterForSingleUpdate(Core.UPDATE_INTERVAL)
            Return
        EndIf
        i += 1
    EndWhile
EndFunction

Function RestartMonitoring()
    {Restart the update loop after game load. Called by Core.Maintenance().
    RegisterForSingleUpdate is per-script and doesn't survive save/load.
    Without this, travel tasks loaded from a save would never be monitored.
    Also re-applies AI packages which are runtime-only and don't persist.}
    Bool hasActive = false
    Int i = 0
    While i < Core.MAX_SLOTS
        If Core.SlotStates[i] != 0 && Core.SlotTaskTypes[i] == "travel"
            hasActive = true
            RecoverTravelPackage(i)
        EndIf
        i += 1
    EndWhile
    If hasActive
        RegisterForSingleUpdate(Core.UPDATE_INTERVAL)
        Core.DebugMsg("Travel monitoring restarted")
    EndIf
EndFunction

Function RecoverTravelPackage(Int slot)
    {Re-apply travel package after save/load. Runtime package overrides and
    linked references don't survive — without this, NPCs would stand idle.}
    ReferenceAlias slotAlias = Core.GetAgentAlias(slot)
    If slotAlias == None
        Return
    EndIf
    Actor npc = slotAlias.GetActorReference()
    If npc == None || npc.IsDead()
        Return
    EndIf

    Int taskState = Core.SlotStates[slot]
    If taskState != 1
        ; Only state 1 (traveling) needs a package. State 2 (arrived) uses sandbox
        ; which is handled by the arrival logic on the next update tick.
        Return
    EndIf

    ObjectReference dest = StorageUtil.GetFormValue(npc, "Intel_DestMarker") as ObjectReference
    If dest == None
        Return
    EndIf

    Int speed = Core.SlotSpeeds[slot]
    Package travelPkg = Core.GetTravelPackage(speed)
    ; Clear any intermediate waypoint — linked refs don't survive save/load,
    ; so the waypoint redirect is invalid. Fresh start with real destination.
    StorageUtil.UnsetFormValue(npc, "Intel_CurrentWaypoint")

    PO3_SKSEFunctions.SetLinkedRef(npc, dest, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(npc, travelPkg, Core.PRIORITY_TRAVEL, 1)
    npc.EvaluatePackage()

    ; Re-initialize stuck tracking so detection starts fresh
    Core.InitializeStuckTrackingForSlot(slot, npc)

    ; Re-init off-screen tracking from persisted data
    Float offscreenArrival = StorageUtil.GetFloatValue(npc, "Intel_OffscreenArrival", 0.0)
    If offscreenArrival > 0.0
        IntelEngine.InitOffScreenTravel(slot, offscreenArrival, npc)
    EndIf

    Core.DebugMsg("Recovered travel package for " + npc.GetDisplayName())
EndFunction

; =============================================================================
; MAIN API - GoToLocation
; =============================================================================

Bool Function GoToLocation(Actor akNPC, String destination, Int speed = 0, Bool isScheduled = false)
    {
    Send an NPC to a destination. Supports both named and semantic locations.

    Parameters:
        akNPC - The NPC to send
        destination - Named location OR semantic term (upstairs, outside, etc.)
        speed - 0=walk, 1=jog, 2=run
        isScheduled - If true, skip MCM confirmation (player already agreed)

    Returns:
        true if travel started successfully
    }

    ; Validate inputs
    If akNPC == None
        Core.DebugMsg("GoToLocation: None actor")
        Return false
    EndIf

    If akNPC.IsDead()
        Core.DebugMsg("GoToLocation: Dead actor")
        Return false
    EndIf

    If destination == ""
        Core.DebugMsg("GoToLocation: Empty destination")
        Return false
    EndIf

    ; Duplicate action guard
    If Core.IsDuplicateTask(akNPC, "travel", destination)
        Return false
    EndIf

    ; MCM task confirmation prompt (skip for scheduled meetings - player already agreed)
    If !isScheduled
        Int confirmResult = Core.ShowTaskConfirmation(akNPC, akNPC.GetDisplayName() + " wants to travel to " + destination + ".")
        If confirmResult == 1
            Core.SendTaskNarration(akNPC, Game.GetPlayer().GetDisplayName() + " told " + akNPC.GetDisplayName() + " they cannot go to " + destination + ".")
            Return false
        ElseIf confirmResult == 2
            Return false
        EndIf
    EndIf

    ; Override existing task if any
    Core.OverrideExistingTask(akNPC)

    ; Find free slot
    Int slot = Core.FindFreeAgentSlot()
    If slot < 0
        Core.DebugMsg("GoToLocation: No free slots")
        Core.SendTaskNarration(akNPC, akNPC.GetDisplayName() + " cannot take on another task right now.")
        Return false
    EndIf

    ; Resolve destination - try semantic first, then named
    ObjectReference destMarker = ResolveDestination(akNPC, destination)
    If destMarker == None
        ; Couldn't resolve - describe the situation factually
        Core.SendTaskNarration(akNPC, akNPC.GetDisplayName() + " was asked to travel to '" + destination + "' but a route could not be determined.")
        Return false
    EndIf

    ; Anti-trespass: unlock home door if destination is a home
    Int homeCellId = IntelEngine.GetLastResolvedHomeCellId()
    If homeCellId != 0
        IntelEngine.SetHomeDoorAccessForCell(homeCellId, true)
        StorageUtil.SetIntValue(akNPC, "Intel_UnlockedHomeCellId", homeCellId)
        Core.DebugMsg("Unlocked home door for " + destination)
    EndIf

    Core.NotifyPlayer(akNPC.GetDisplayName() + " headed off to " + destination)

    ; Stop following — traveling implies leaving the player
    Core.DismissFollowerForTask(akNPC)

    ; Calculate wait deadline from MCM setting
    Float waitHours = 0.0
    If Core.IntelEngine_DefaultWaitHours != None
        waitHours = Core.IntelEngine_DefaultWaitHours.GetValue()
    EndIf
    If waitHours <= 0.0
        waitHours = DEFAULT_WAIT_HOURS
    EndIf
    waitHours = ClampFloat(waitHours, MIN_WAIT_HOURS, MAX_WAIT_HOURS)

    ; Allocate slot
    Core.AllocateSlot(slot, akNPC, "travel", destination, speed)

    ; Store wait hours - deadline will be calculated on arrival, not now
    StorageUtil.SetFloatValue(akNPC, "Intel_WaitHours", waitHours)

    ; Store destination marker
    StorageUtil.SetFormValue(akNPC, "Intel_DestMarker", destMarker)

    ; Set up linked ref for travel package
    PO3_SKSEFunctions.SetLinkedRef(akNPC, destMarker, Core.IntelEngine_TravelTarget)

    ; Apply travel package
    Package travelPkg = Core.GetTravelPackage(speed)
    ActorUtil.AddPackageOverride(akNPC, travelPkg, Core.PRIORITY_TRAVEL, 1)

    ; Small delay for linked ref processing
    Utility.Wait(0.1)

    ; Force package evaluation
    akNPC.EvaluatePackage()

    ; Initialize stuck tracking
    Core.InitializeStuckTrackingForSlot(slot, akNPC)

    ; Initialize off-screen travel tracking (distance-based estimated arrival)
    Core.InitOffScreenTracking(slot, akNPC, destMarker)

    ; For scheduled meetings, also track departure position
    If StorageUtil.GetIntValue(akNPC, "Intel_IsScheduledMeeting") == 1
        Core.InitializeDepartureTracking(slot, akNPC)
    EndIf

    ; Start monitoring
    RegisterForSingleUpdate(Core.UPDATE_INTERVAL)

    Core.DebugMsg(akNPC.GetDisplayName() + " traveling to " + destination)
    Return true
EndFunction



; =============================================================================
; DESTINATION RESOLUTION
; =============================================================================

ObjectReference Function ResolveDestination(Actor akNPC, String destination)
    {Resolve any destination string to a travel target. All intelligence is in C++.}

    Core.DebugMsg("Resolving: " + destination)
    ObjectReference result = IntelEngine.ResolveAnyDestination(akNPC, destination)
    If result != None
        Core.DebugMsg("Resolved to: " + result)
    Else
        Core.DebugMsg("Could not resolve: " + destination)
    EndIf
    Return result
EndFunction

; =============================================================================
; UPDATE LOOP - Arrival Detection
; =============================================================================

Event OnUpdate()
    ; Register FIRST so the loop survives even if processing errors out.
    Bool hasActiveTravelers = false
    Int i = 0
    While i < Core.MAX_SLOTS
        If Core.SlotStates[i] != 0 && Core.SlotTaskTypes[i] == "travel"
            hasActiveTravelers = true
        EndIf
        i += 1
    EndWhile

    If hasActiveTravelers
        RegisterForSingleUpdate(Core.UPDATE_INTERVAL)
    EndIf

    ; Now process slots — if this errors out, the next update is already scheduled
    i = 0
    While i < Core.MAX_SLOTS
        If Core.SlotStates[i] != 0 && Core.SlotTaskTypes[i] == "travel"
            CheckTravelSlot(i)
        EndIf
        i += 1
    EndWhile
EndEvent

Function CheckTravelSlot(Int slot)
    ReferenceAlias slotAlias = Core.GetAgentAlias(slot)
    If slotAlias == None
        Core.ClearSlot(slot)
        Return
    EndIf

    Actor npc = slotAlias.GetActorReference()
    If npc == None || npc.IsDead()
        Core.DebugMsg("Slot " + slot + ": NPC is None or dead")
        Core.ClearSlot(slot)
        Return
    EndIf

    Int taskState = Core.SlotStates[slot]

    ; Game-time timeout — if traveling too long, force-arrive.
    ; Catches off-screen NPCs whose 3D never loads, so position-based
    ; stuck detection never fires. Only applies to traveling state.
    If taskState == 1
        Float startTime = StorageUtil.GetFloatValue(npc, "Intel_TaskStartTime")
        If startTime > 0.0
            Float elapsedHours = (Utility.GetCurrentGameTime() - startTime) * 24.0
            If elapsedHours > MAX_TASK_HOURS
                ; For scheduled meetings: if extremely late, cancel instead of force-arriving
                If StorageUtil.GetIntValue(npc, "Intel_IsScheduledMeeting") == 1
                    Float meetingTime = StorageUtil.GetFloatValue(npc, "Intel_MeetingTime", 0.0)
                    If meetingTime > 0.0
                        Float hoursLate = (Utility.GetCurrentGameTime() - meetingTime) * 24.0
                        If hoursLate > 6.0
                            String npcName2 = npc.GetDisplayName()
                            String meetDest = StorageUtil.GetStringValue(npc, "Intel_MeetingDest")
                            Core.DebugMsg(npcName2 + " is " + hoursLate + "h late for meeting — cancelling")
                            Core.StoreMeetingOutcome(npc, "npc_late", meetDest)
                            Core.NotifyPlayer(npcName2 + " never made it to the meeting at " + meetDest)
                            Core.ClearSlotRestoreFollower(slot, npc)
                            If Core.Schedule
                                Core.Schedule.ClearScheduleSlotByAgent(npc)
                            EndIf
                            Return
                        EndIf
                    EndIf
                EndIf
                Core.DebugMsg("Travel timeout (" + elapsedHours + "h) for " + npc.GetDisplayName() + " — force-arriving")
                Core.NotifyPlayer(npc.GetDisplayName() + " took too long — teleporting to destination")
                ObjectReference dest = StorageUtil.GetFormValue(npc, "Intel_DestMarker") as ObjectReference
                If dest != None
                    npc.MoveTo(dest)
                EndIf
                OnArrival(slot, npc)
                Return
            EndIf
        EndIf
    EndIf

    If taskState == 1
        ; For scheduled meetings, check departure first (did NPC actually start moving?)
        If StorageUtil.GetIntValue(npc, "Intel_IsScheduledMeeting") == 1
            If CheckMeetingDeparture(slot, npc)
                Return  ; Departure failed — slot was handled
            EndIf
        EndIf
        ; Traveling - check for arrival
        CheckForArrival(slot, npc)
    ElseIf taskState == 2
        ; At destination - check for player arrival or timeout
        CheckWaiting(slot, npc)
    EndIf
EndFunction

Function CheckForArrival(Int slot, Actor npc)
    ObjectReference dest = StorageUtil.GetFormValue(npc, "Intel_DestMarker") as ObjectReference
    If dest == None
        Core.DebugMsg("Slot " + slot + ": No destination marker")
        Return
    EndIf

    ; Check if NPC reached an intermediate waypoint (Layer B redirect)
    If Core.CheckWaypointArrival(slot, npc, dest)
        Return
    EndIf

    If npc.Is3DLoaded() && dest.Is3DLoaded()
        ; Both loaded — use precise distance check
        Float dist = npc.GetDistance(dest)
        If dist <= Core.ARRIVAL_DISTANCE
            ; Check if destination is a door with teleport data (semantic travel
            ; like "outside", "upstairs", "downstairs"). AI packages don't auto-
            ; activate doors, so we teleport the NPC through.
            ObjectReference doorDest = IntelEngine.GetDoorDestinationRef(dest)
            If doorDest != None
                Core.DebugMsg(npc.GetDisplayName() + " reached door, teleporting through")
                npc.MoveTo(doorDest)

                ; Multi-hop: if target was "outside" but the door led to another
                ; interior (e.g. upstairs -> main floor), find the exterior door
                ; in the new cell and teleport through that too.
                If !IntelEngine.IsDoorExterior(dest)
                    String targetName = Core.SlotTargetNames[slot]
                    If IntelEngine.StringContains(IntelEngine.StringToLower(targetName), "outside")
                        TeleportToExterior(npc)
                    EndIf
                EndIf
            EndIf

            OnArrival(slot, npc)
        Else
            CheckIfStuck(slot, npc)
        EndIf
        Return
    EndIf

    ; Off-screen: if both in the same interior cell, consider arrived.
    ; Interior cells are small enough that same-cell == close proximity.
    ; Without this check, off-screen NPCs that reach the correct cell
    ; would never be detected as arrived (3D never loads → distance
    ; check never runs). The game-time timeout is the final safety net.
    Cell npcCell = npc.GetParentCell()
    If npcCell != None && npcCell == dest.GetParentCell() && npcCell.IsInterior()
        Core.DebugMsg(npc.GetDisplayName() + " reached destination cell (off-screen)")
        OnArrival(slot, npc)
        Return
    EndIf

    ; NPC is on-screen — normal stuck detection + leapfrog recovery.
    ; Stuck detection only needs the NPC's position, not the destination 3D.
    If npc.Is3DLoaded()
        CheckIfStuck(slot, npc)
        Return
    EndIf

    ; NPC is off-screen — check estimated travel time and teleport if stationary
    If Core.HandleOffScreenTravel(slot, npc, dest)
        OnArrival(slot, npc)
    EndIf
EndFunction

Function TeleportToExterior(Actor npc)
    {Scan current cell for an exterior door and teleport the NPC through it.
    Used for multi-hop "outside" travel when the first door led to an intermediate interior.}
    ObjectReference[] doors = IntelEngine.GetCellDoors(npc)
    Int d = 0
    While d < doors.Length
        If IntelEngine.IsDoorExterior(doors[d])
            ObjectReference extDest = IntelEngine.GetDoorDestinationRef(doors[d])
            If extDest != None
                Core.DebugMsg(npc.GetDisplayName() + " multi-hop: teleporting to exterior")
                npc.MoveTo(extDest)
                Return
            EndIf
        EndIf
        d += 1
    EndWhile
    Core.DebugMsg(npc.GetDisplayName() + " multi-hop: no exterior door found in cell")
EndFunction

Function OnArrival(Int slot, Actor npc)
    String destination = Core.SlotTargetNames[slot]

    Core.DebugMsg(npc.GetDisplayName() + " arrived at " + destination)
    Bool isMeetingArrival = StorageUtil.GetIntValue(npc, "Intel_IsScheduledMeeting") == 1
    If !isMeetingArrival
        Core.NotifyPlayer(npc.GetDisplayName() + " arrived at " + destination)
    EndIf

    ; Remove travel package, apply sandbox
    Core.RemoveAllPackages(npc)

    ; Keep travel linked ref — it points to the destination marker.
    ; SandboxNearPlayerPackage uses this ref for its sandbox location (200-unit radius).
    ; Clearing it here causes the NPC to fall back to their home location.
    ; The ref is cleaned up later in ClearSlot → ClearLinkedRefs.

    ; Apply tight sandbox at destination (linked ref = destination marker)
    ActorUtil.AddPackageOverride(npc, Core.SandboxNearPlayerPackage, Core.PRIORITY_SANDBOX, 1)
    npc.EvaluatePackage()

    ; Calculate wait deadline NOW (at arrival, not at task creation)
    If isMeetingArrival
        ; Meetings: deadline is always meetingTime + timeout.
        ; If NPC arrives late and the deadline already passed, OnWaitTimeout
        ; fires on the next CheckWaiting cycle.
        Float meetingTime = StorageUtil.GetFloatValue(npc, "Intel_MeetingTime", 0.0)
        Float meetTimeout = StorageUtil.GetFloatValue(Game.GetPlayer(), "Intel_MeetingTimeoutHours", 3.0)
        Core.SetSlotDeadline(slot, meetingTime + (meetTimeout / 24.0))
    Else
        Float waitHours = StorageUtil.GetFloatValue(npc, "Intel_WaitHours")
        If waitHours <= 0.0
            If Core.IntelEngine_DefaultWaitHours != None
                waitHours = Core.IntelEngine_DefaultWaitHours.GetValue()
            EndIf
            If waitHours <= 0.0
                waitHours = DEFAULT_WAIT_HOURS
            EndIf
        EndIf
        Core.SetSlotDeadline(slot, Utility.GetCurrentGameTime() + (waitHours / 24.0))
    EndIf

    ; Update state
    Core.SetSlotState(slot, npc, 2)  ; at_destination

    If isMeetingArrival
        ; Scheduled meeting: NPC arrived at meeting spot to wait — no narration
        ; (avoids premature "arrived at" when player hasn't shown up yet)
        StorageUtil.SetFloatValue(npc, "Intel_MeetingNpcArrivalTime", Utility.GetCurrentGameTime())
        Core.DebugMsg(npc.GetDisplayName() + " arrived at meeting spot " + destination + " (waiting for player)")
    Else
        ; GoToLocation: store arrival time for wait duration tracking.
        ; OnPlayerArrived uses this to narrate context-aware greetings.
        StorageUtil.SetFloatValue(npc, "Intel_TravelArrivalTime", Utility.GetCurrentGameTime())
        Core.DebugMsg(npc.GetDisplayName() + " arrived at " + destination + " (waiting)")
    EndIf

    ; If player is already in the same cell, handle immediately
    Actor player = Game.GetPlayer()
    If npc.GetParentCell() == player.GetParentCell()
        If npc.Is3DLoaded() && player.Is3DLoaded() && npc.GetDistance(player) < 1000.0
            If StorageUtil.GetIntValue(npc, "Intel_IsScheduledMeeting") == 1
                ; Scheduled meeting — run the meeting flow (lateness, linger, etc.)
                OnPlayerArrived(slot, npc)
            Else
                ; Regular travel — arrived with player nearby (traveled together)
                Core.SendTaskNarration(npc, npc.GetDisplayName() + " arrived at " \
                    + destination + " together with " + player.GetDisplayName() + ".", player)
                StartTravelLinger(slot, npc)
            EndIf
            Return
        EndIf
    EndIf
EndFunction

Function CheckWaiting(Int slot, Actor npc)
    Actor player = Game.GetPlayer()
    Float currentTime = Utility.GetCurrentGameTime()
    Float deadline = Core.SlotDeadlines[slot]
    ; Phase: Post-meeting linger (player already met NPC, NPC hanging around)
    If StorageUtil.GetIntValue(npc, "Intel_MeetingLingering") == 1
        If ProcessLingerProximity(slot, npc)
            CompleteMeeting(slot, npc)
        EndIf
        Return
    EndIf

    ; Phase: Travel linger (GoToLocation — NPC arrived, player nearby, sandboxing near player)
    If StorageUtil.GetIntValue(npc, "Intel_TravelLingering") == 1
        If ProcessLingerProximity(slot, npc)
            CompleteTravelLinger(slot, npc)
        EndIf
        Return
    EndIf

    ; Check if player is right next to NPC
    Bool playerNearby = false
    If npc.Is3DLoaded() && player.Is3DLoaded()
        If npc.GetDistance(player) < 1000.0
            playerNearby = true
        EndIf
    ElseIf npc.GetParentCell() == player.GetParentCell()
        ; Both off-screen in same interior cell — treat as nearby
        If npc.GetParentCell().IsInterior()
            playerNearby = true
        EndIf
    EndIf

    If playerNearby
        ; Stop approaching if we were
        If StorageUtil.GetIntValue(npc, "Intel_MeetingApproaching") == 1
            StopApproachingPlayer(npc)
        EndIf
        OnPlayerArrived(slot, npc)
        Return
    EndIf

    ; Smart approach — if player is near the destination but not right next to NPC,
    ; walk toward them. Works for both scheduled meetings and GoToLocation.
    ObjectReference destMarker = StorageUtil.GetFormValue(npc, "Intel_DestMarker") as ObjectReference
    Bool playerNearDest = false

    If destMarker != None
        If player.GetParentCell() == destMarker.GetParentCell()
            If player.Is3DLoaded() && destMarker.Is3DLoaded()
                playerNearDest = player.GetDistance(destMarker) < MEETING_PLAYER_PROXIMITY
            Else
                ; Same cell but 3D not loaded — only trust for interior cells
                Cell destCell = destMarker.GetParentCell()
                If destCell != None && destCell.IsInterior()
                    playerNearDest = true
                EndIf
            EndIf
        EndIf
    EndIf

    If playerNearDest
        ; Player is near the destination — NPC should walk toward them
        If StorageUtil.GetIntValue(npc, "Intel_MeetingApproaching") != 1
            ; Only start approach if NPC is visible — avoids ghost notifications
            If npc.Is3DLoaded()
                StartApproachingPlayer(slot, npc)
            EndIf
        Else
            CheckMeetingApproach(slot, npc)
        EndIf
        Return  ; Don't timeout while player is nearby
    Else
        ; Player left the area — stop approaching and return to destination sandbox
        If StorageUtil.GetIntValue(npc, "Intel_MeetingApproaching") == 1
            StopApproachingPlayer(npc)
            ; Restore sandbox at destination (not player)
            ObjectReference destMarker2 = StorageUtil.GetFormValue(npc, "Intel_DestMarker") as ObjectReference
            If destMarker2 != None
                PO3_SKSEFunctions.SetLinkedRef(npc, destMarker2, Core.IntelEngine_TravelTarget)
            EndIf
            ActorUtil.AddPackageOverride(npc, Core.SandboxNearPlayerPackage, Core.PRIORITY_SANDBOX, 1)
            npc.EvaluatePackage()
        EndIf
    EndIf

    ; Check deadline
    If currentTime >= deadline
        OnWaitTimeout(slot, npc)
    EndIf
EndFunction

Function OnPlayerArrived(Int slot, Actor npc)
    Actor player = Game.GetPlayer()
    String npcName = npc.GetDisplayName()
    String playerName = player.GetDisplayName()
    String destination = Core.SlotTargetNames[slot]

    Core.DebugMsg(npcName + ": Player arrived")

    If StorageUtil.GetIntValue(npc, "Intel_IsScheduledMeeting") == 1
        ; === Scheduled meeting: lateness awareness + linger ===
        Float meetingGameTime = StorageUtil.GetFloatValue(npc, "Intel_MeetingTime")
        Float currentGameTime = Utility.GetCurrentGameTime()
        Float npcArrivalTime = StorageUtil.GetFloatValue(npc, "Intel_MeetingNpcArrivalTime", 0.0)
        String meetDest = StorageUtil.GetStringValue(npc, "Intel_MeetingDest")
        If meetDest == ""
            meetDest = destination
        EndIf

        npc.SetLookAt(player)

        ; Calculate lateness for both parties
        Float playerHoursLate = (currentGameTime - meetingGameTime) * 24.0
        Float npcHoursLate = 0.0
        If npcArrivalTime > 0.0
            npcHoursLate = (npcArrivalTime - meetingGameTime) * 24.0
        EndIf

        ; Determine outcome — check NPC lateness first, then player
        String outcome = "success"
        If npcHoursLate > 1.0
            ; NPC was significantly late getting to the meeting spot
            outcome = "npc_arrived_late"
            StorageUtil.SetFloatValue(npc, "Intel_MeetingLateHours", npcHoursLate)
            Core.SendTaskNarration(npc, npcName + " arrived at " + meetDest + " about " + (npcHoursLate as Int) + " hours late. " + playerName + " was already waiting.", player)
            Core.DebugMsg(npcName + ": NPC was " + (npcHoursLate as Int) + "h late to meeting")
        ElseIf playerHoursLate > 1.0
            ; Player is significantly late
            outcome = "player_late"
            StorageUtil.SetFloatValue(npc, "Intel_MeetingLateHours", playerHoursLate)
            Core.SendTaskNarration(npc, npcName + " waited at " + meetDest + " for " + playerName + " who arrived about " + (playerHoursLate as Int) + " hours late.", player)
            Core.DebugMsg(npcName + ": Player " + (playerHoursLate as Int) + "h late to meeting")
        ElseIf playerHoursLate > 0.25
            ; Player is slightly late (>15 min)
            outcome = "player_slightly_late"
            Core.SendTaskNarration(npc, npcName + " was waiting at " + meetDest + " for " + playerName + " who arrived a bit late, but they met as planned.", player)
            Core.DebugMsg(npcName + ": Player slightly late to meeting")
        Else
            ; On time or early
            Core.SendTaskNarration(npc, npcName + " met " + playerName + " at " + meetDest + " as agreed.", player)
            Core.DebugMsg(npcName + ": Player on time to meeting")
        EndIf

        ; Store structured outcome for prompts
        Core.StoreMeetingOutcome(npc, outcome, meetDest)

        Core.NotifyPlayer(npcName + " met you at " + meetDest)

        ; Start linger — NPC stays nearby for a while instead of leaving immediately
        StartMeetingLinger(slot, npc)
    Else
        ; === Regular travel: context-aware arrival narration ===
        Float arrivalTime = StorageUtil.GetFloatValue(npc, "Intel_TravelArrivalTime", 0.0)
        Float waitHours = 0.0
        If arrivalTime > 0.0
            waitHours = (Utility.GetCurrentGameTime() - arrivalTime) * 24.0
        EndIf

        npc.SetLookAt(player)

        If waitHours > 2.0
            ; Long wait — NPC notices player finally showing up
            Core.SendTaskNarration(npc, playerName + " finally arrived at " \
                + destination + ". " + npcName + " had been waiting for a long time.", player)
        Else
            ; Normal wait — player showed up
            Core.SendTaskNarration(npc, playerName + " arrived at " + destination \
                + " where " + npcName + " was waiting.", player)
        EndIf

        StartTravelLinger(slot, npc)
    EndIf
EndFunction

Function OnWaitTimeout(Int slot, Actor npc)
    String destination = Core.SlotTargetNames[slot]
    Actor player = Game.GetPlayer()
    String npcName = npc.GetDisplayName()

    Core.DebugMsg(npcName + ": Wait timeout at " + destination)

    If StorageUtil.GetIntValue(npc, "Intel_IsScheduledMeeting") == 1
        ; === Scheduled meeting: store structured outcome for prompts ===
        String meetDest = StorageUtil.GetStringValue(npc, "Intel_MeetingDest")
        If meetDest == ""
            meetDest = destination
        EndIf

        ; Distinguish: NPC arrived after the timeout window vs player never showed up
        Float meetingTime = StorageUtil.GetFloatValue(npc, "Intel_MeetingTime", 0.0)
        Float npcArrivalTime = StorageUtil.GetFloatValue(npc, "Intel_MeetingNpcArrivalTime", 0.0)
        Float meetTimeout = StorageUtil.GetFloatValue(Game.GetPlayer(), "Intel_MeetingTimeoutHours", 3.0)
        Float meetDeadline = meetingTime + (meetTimeout / 24.0)

        If npcArrivalTime > meetDeadline
            ; NPC arrived after the window expired — NPC was too late
            Core.StoreMeetingOutcome(npc, "npc_late", meetDest)
            Core.NotifyPlayer(npcName + " arrived too late for the meeting at " + meetDest)
        Else
            ; NPC was there on time, player never showed
            Core.StoreMeetingOutcome(npc, "player_no_show", meetDest)
            Core.NotifyPlayer(npcName + " got tired of waiting for you at " + meetDest)
        EndIf
    Else
        Core.NotifyPlayer(npcName + " left " + destination)
    EndIf

    ; Mark as timeout
    StorageUtil.SetStringValue(npc, "Intel_Result", "timeout")

    ; Clear slot but don't restore follower (they gave up)
    Core.ClearSlot(slot, false)

    ; Clear schedule slot — meeting is over (player no-show)
    If Core.Schedule
        Core.Schedule.ClearScheduleSlotByAgent(npc)
    EndIf
EndFunction

; =============================================================================
; STUCK DETECTION & RECOVERY
; =============================================================================

Function CheckIfStuck(Int slot, Actor npc)
    {Stuck detection using native C++ StuckDetector singleton.
    Soft recovery is shared via Core.SoftStuckRecovery.
    Teleport behavior is Travel-specific (direct to dest + OnArrival).}

    If !npc.Is3DLoaded()
        Return
    EndIf

    ; Skip stuck detection while NPC is in dialogue or combat — stationary
    ; by design, not actually stuck. Reset the C++ counter so time spent
    ; talking/fighting doesn't accumulate toward a false stuck trigger.
    If npc.GetDialogueTarget() != None || npc.IsInCombat()
        IntelEngine.ResetStuckSlot(slot, npc)
        Return
    EndIf

    Int status = IntelEngine.CheckStuckStatus(npc, slot, Core.STUCK_DISTANCE_THRESHOLD)

    If status == 0
        Return
    EndIf

    ObjectReference dest = StorageUtil.GetFormValue(npc, "Intel_DestMarker") as ObjectReference

    If status == 1
        Int attempts = IntelEngine.GetStuckRecoveryAttempts(slot)
        Core.DebugMsg("Soft recovery " + attempts + " for " + npc.GetDisplayName())

        ; First stuck — let NPC react in-character while player is nearby
        If attempts == 1
            Core.SendTaskNarration(npc, npc.GetDisplayName() + " felt their feet catch on something and couldn't move for a moment, stumbling on the path.")
        EndIf

        Core.SoftStuckRecovery(npc, slot, dest)
        Return
    EndIf

    If status == 3
        If dest == None
            Return
        EndIf

        ; Layer B: Try location marker navigation (on-screen only).
        ; Finds nearest BGSLocation worldLocMarker toward dest and redirects
        ; travel package — NPC walks there naturally on navmesh.
        If Core.TryWaypointNavigation(slot, npc, dest)
            Return
        EndIf

        ; Layer C: Multi-angle leapfrog with progressive distance.
        ; C++ GetTeleportDistance returns descending (2000→1000→500→250) for
        ; NPCTasks return-to-player. We invert it for Travel: ascending
        ; (200→500→1000→2000) keeps the NPC visible to the player.
        ; On consecutive attempts, rotate direction ±30° to find passable
        ; terrain around mountains instead of always aiming straight at dest.
        Float descDist = IntelEngine.GetTeleportDistance(slot)

        ; First leapfrog attempt — tell player to go ahead while NPC tries to get unstuck.
        ; Resets naturally if NPC moves (teleportAttempts resets), so it re-fires on new episodes.
        If descDist >= 2000.0
            String destination = Core.SlotTargetNames[slot]
            Core.SendTaskNarration(npc, npc.GetDisplayName() + " is having trouble getting through and urged " \
                + Game.GetPlayer().GetDisplayName() + " to go on ahead to " + destination \
                + " while they try to find a way around.", Game.GetPlayer())
        EndIf

        Float leapDist
        Float angle = 0.0
        If descDist >= 2000.0
            leapDist = 200.0     ; First attempt — minimal nudge, straight
        ElseIf descDist >= 1000.0
            leapDist = 500.0     ; Second attempt — try +30°
            angle = 30.0
        ElseIf descDist >= 500.0
            leapDist = 1000.0    ; Third attempt — try -30°
            angle = -30.0
        Else
            leapDist = LEAPFROG_MAX_DISTANCE  ; Fourth+ — full distance, straight
        EndIf

        ; Calculate distance to destination using world positions
        ; (works even when dest 3D isn't loaded — positions are persistent)
        Float dx = dest.GetPositionX() - npc.GetPositionX()
        Float dy = dest.GetPositionY() - npc.GetPositionY()
        Float totalDist = Math.sqrt(dx * dx + dy * dy)

        If totalDist <= leapDist + Core.ARRIVAL_DISTANCE
            ; Close enough — teleport directly and arrive
            Core.DebugMsg("Stuck recovery: " + npc.GetDisplayName() + " close enough (" + totalDist + "u) — teleporting to dest")
            Core.NotifyPlayer(npc.GetDisplayName() + " arrived (teleported)")
            npc.MoveTo(dest, 0.0, 0.0, 50.0)
            npc.EvaluatePackage()
            OnArrival(slot, npc)
        Else
            ; Too far — leapfrog toward destination, then resume pathfinding.
            Float ratio = leapDist / totalDist
            Float offsetX = dx * ratio
            Float offsetY = dy * ratio

            ; Rotate offset to try alternate paths around obstacles
            If angle != 0.0
                Float cosA = Math.cos(angle)
                Float sinA = Math.sin(angle)
                Float rotX = offsetX * cosA - offsetY * sinA
                Float rotY = offsetX * sinA + offsetY * cosA
                offsetX = rotX
                offsetY = rotY
            EndIf

            ; Layer A: Z offset prevents sinking into terrain at mountain passes
            npc.MoveTo(npc, offsetX, offsetY, 200.0, false)

            ; Re-apply travel package from new position
            Int speed = Core.SlotSpeeds[slot]
            Package travelPkg = Core.GetTravelPackage(speed)
            If travelPkg
                ActorUtil.AddPackageOverride(npc, travelPkg, Core.PRIORITY_TRAVEL, 1)
            EndIf
            Utility.Wait(0.5)
            npc.EvaluatePackage()

            Core.DebugMsg(npc.GetDisplayName() + " leapfrogged " + leapDist + "u at " + angle + "° toward dest (" + (totalDist - leapDist) + "u remaining)")
            Core.NotifyPlayer(npc.GetDisplayName() + " making progress toward destination")
        EndIf
    EndIf
EndFunction

; =============================================================================
; SCHEDULED MEETING — DEPARTURE DETECTION
;
; Ported from NPCTasks pattern. When a scheduled meeting NPC is dispatched,
; we track their starting position. After DEPARTURE_CHECK_CYCLES (~15s),
; we check if they actually moved. If not, soft recovery first, then escalate.
; =============================================================================

Bool Function CheckMeetingDeparture(Int slot, Actor npc)
    {Returns true if departure failed and slot was handled (caller should return).
    Uses Core.CheckDepartureProgress for shared tick/position logic.}
    Int status = Core.CheckDepartureProgress(slot, npc, Core.STUCK_DISTANCE_THRESHOLD)

    If status <= 2
        ; 0=too early, 1=departed, 2=soft recovery applied — all OK
        Return false
    EndIf

    ; status == 3: escalate
    HandleMeetingDepartureFailure(slot, npc)
    Return true
EndFunction

Function HandleMeetingDepartureFailure(Int slot, Actor npc)
    {Handle NPC that can't leave for a scheduled meeting.
    Phase 1: Off-screen teleport. Phase 2: On-screen narrate failure.}
    String npcName = npc.GetDisplayName()
    Actor player = Game.GetPlayer()

    ; Off-screen teleport / On-screen narrate failure
    If !npc.Is3DLoaded()
        ; Player isn't looking — teleport silently to destination
        ObjectReference dest = StorageUtil.GetFormValue(npc, "Intel_DestMarker") as ObjectReference
        If dest != None
            Core.DebugMsg(npcName + " failed to depart for meeting (off-screen) — teleporting to destination")
            npc.MoveTo(dest, 0.0, 0.0, 50.0)
            npc.EvaluatePackage()
            OnArrival(slot, npc)
            Return
        EndIf
    EndIf

    ; Player is watching — narrate failure in past tense
    Core.DebugMsg(npcName + " failed to depart for meeting (visible) — narrating failure")
    String meetDest = StorageUtil.GetStringValue(npc, "Intel_MeetingDest")
    If meetDest == ""
        meetDest = Core.SlotTargetNames[slot]
    EndIf

    If npc.GetParentCell() == player.GetParentCell()
        Core.SendTaskNarration(npc, npcName + " tried to leave for " + meetDest + " but was unable to and gave up.", player)
    Else
        Core.SendTransientEvent(npc, player, npcName + " was unable to leave for " + meetDest + " and gave up on the meeting.")
    EndIf

    ; No outcome stored — NPC never reached the meeting spot, so "player_no_show"
    ; would be factually wrong. The narration already covers what happened.

    Core.RemoveAllPackages(npc)
    Core.ClearSlot(slot, true)

    ; Clear schedule slot — departure failed
    If Core.Schedule
        Core.Schedule.ClearScheduleSlotByAgent(npc)
    EndIf
EndFunction

; =============================================================================
; SCHEDULED MEETING — SMART APPROACH
;
; When the player is near the meeting spot (~2000 units of destination) but
; not right next to the NPC, the NPC walks toward the player for immersion.
; If the NPC gets stuck AND is not visible, teleport behind the player.
; If player leaves the area, NPC returns to sandbox at the meeting spot.
; =============================================================================

Function StartApproachingPlayer(Int slot, Actor npc)
    {Switch NPC from sandbox to walking toward the player.}
    Actor player = Game.GetPlayer()

    Core.DebugMsg(npc.GetDisplayName() + " starting to approach player at meeting spot")

    ; Switch from sandbox to travel-toward-player
    Core.RemoveAllPackages(npc)
    PO3_SKSEFunctions.SetLinkedRef(npc, player as ObjectReference, Core.IntelEngine_TravelTarget)
    Package travelPkg = Core.GetTravelPackage(0)  ; walk
    ActorUtil.AddPackageOverride(npc, travelPkg, Core.PRIORITY_TRAVEL, 1)
    npc.EvaluatePackage()

    ; Track approach for stuck detection
    StorageUtil.SetIntValue(npc, "Intel_MeetingApproaching", 1)
    StorageUtil.SetFloatValue(npc, "Intel_ApproachStartX", npc.GetPositionX())
    StorageUtil.SetFloatValue(npc, "Intel_ApproachStartY", npc.GetPositionY())
    StorageUtil.SetIntValue(npc, "Intel_ApproachTick", 0)
EndFunction

Function CheckMeetingApproach(Int slot, Actor npc)
    {Check if NPC is making progress walking toward the player, with stuck recovery.}
    Actor player = Game.GetPlayer()

    ; Already close enough?
    If npc.Is3DLoaded() && player.Is3DLoaded() && npc.GetDistance(player) < 1000.0
        StopApproachingPlayer(npc)
        OnPlayerArrived(slot, npc)
        Return
    EndIf

    ; Tick the approach counter
    Int tick = StorageUtil.GetIntValue(npc, "Intel_ApproachTick") + 1
    StorageUtil.SetIntValue(npc, "Intel_ApproachTick", tick)

    If tick < Core.DEPARTURE_CHECK_CYCLES
        ; Too early to check — give NPC time to walk
        Return
    EndIf

    ; Check movement since last reset
    Float dx = npc.GetPositionX() - StorageUtil.GetFloatValue(npc, "Intel_ApproachStartX")
    Float dy = npc.GetPositionY() - StorageUtil.GetFloatValue(npc, "Intel_ApproachStartY")
    Float dist = Math.sqrt(dx * dx + dy * dy)

    If dist >= Core.STUCK_DISTANCE_THRESHOLD
        ; Moving — reset tracking
        StorageUtil.SetFloatValue(npc, "Intel_ApproachStartX", npc.GetPositionX())
        StorageUtil.SetFloatValue(npc, "Intel_ApproachStartY", npc.GetPositionY())
        StorageUtil.SetIntValue(npc, "Intel_ApproachTick", 0)
        Return
    EndIf

    ; Stuck while approaching player
    If !npc.Is3DLoaded()
        ; Not visible — teleport behind player
        Core.DebugMsg(npc.GetDisplayName() + " stuck approaching player (off-screen) — teleporting behind")
        Core.TeleportBehindPlayer(npc)
        StopApproachingPlayer(npc)
        OnPlayerArrived(slot, npc)
    Else
        ; Visible — soft recovery: nudge + PathToReference
        Core.DebugMsg(npc.GetDisplayName() + " stuck approaching player (visible) — nudging")

        ; Narrate once so NPC can react to being stuck near the player
        If StorageUtil.GetIntValue(npc, "Intel_ApproachStuckNarrated") != 1
            StorageUtil.SetIntValue(npc, "Intel_ApproachStuckNarrated", 1)
            Core.SendTaskNarration(npc, npc.GetDisplayName() + " is trying to reach " + player.GetDisplayName() + " but seems unable to get past something.", player)
        EndIf

        npc.EvaluatePackage()
        npc.PathToReference(player as ObjectReference, 1.0)
        npc.EvaluatePackage()

        ; Reset tracking for another round
        StorageUtil.SetFloatValue(npc, "Intel_ApproachStartX", npc.GetPositionX())
        StorageUtil.SetFloatValue(npc, "Intel_ApproachStartY", npc.GetPositionY())
        StorageUtil.SetIntValue(npc, "Intel_ApproachTick", 0)
    EndIf
EndFunction

Function StopApproachingPlayer(Actor npc)
    {Stop approach mode — clean up state only. Does NOT apply a replacement
    package or evaluate. Caller is responsible for the next package.}
    If StorageUtil.GetIntValue(npc, "Intel_MeetingApproaching") != 1
        Return
    EndIf

    Core.DebugMsg(npc.GetDisplayName() + " stopping approach")
    Core.RemoveAllPackages(npc, false)

    StorageUtil.UnsetIntValue(npc, "Intel_MeetingApproaching")
    StorageUtil.UnsetFloatValue(npc, "Intel_ApproachStartX")
    StorageUtil.UnsetFloatValue(npc, "Intel_ApproachStartY")
    StorageUtil.UnsetIntValue(npc, "Intel_ApproachTick")
    StorageUtil.UnsetIntValue(npc, "Intel_ApproachStuckNarrated")
EndFunction

; =============================================================================
; SHARED LINGER PROXIMITY — used by both meeting and travel linger
;
; Phase 1: Walk toward player (approach).
; Phase 2: Sandbox within 200 units once close.
; Released when the player walks MEETING_LINGER_RELEASE_DISTANCE away.
; =============================================================================

Bool Function ProcessLingerProximity(Int slot, Actor npc)
    {Shared approach/sandbox/release logic for both meeting and travel linger.
    Returns true when linger should end (player walked away).}
    Actor player = Game.GetPlayer()

    ; Sub-phase: approaching player — walk until close, then sandbox
    If StorageUtil.GetIntValue(npc, "Intel_MeetingLingerApproaching") == 1
        Bool closeEnough = false
        Bool stillFar = true
        If npc.Is3DLoaded() && player.Is3DLoaded()
            Float dist = npc.GetDistance(player)
            closeEnough = dist <= Core.LINGER_APPROACH_DISTANCE
            stillFar = dist > MEETING_LINGER_RELEASE_DISTANCE
        ElseIf npc.GetParentCell() == player.GetParentCell()
            Cell npcCell = npc.GetParentCell()
            stillFar = false
            If npcCell != None && npcCell.IsInterior()
                closeEnough = true
            EndIf
        EndIf

        If closeEnough
            ; Add sandbox BEFORE removing travel — no gap for default AI to kick in
            PO3_SKSEFunctions.SetLinkedRef(npc, player as ObjectReference, Core.IntelEngine_TravelTarget)
            ActorUtil.AddPackageOverride(npc, Core.SandboxNearPlayerPackage, Core.PRIORITY_TRAVEL, 1)
            ActorUtil.RemovePackageOverride(npc, Core.TravelPackage_Walk)
            Utility.Wait(0.1)
            npc.EvaluatePackage()
            StorageUtil.UnsetIntValue(npc, "Intel_MeetingLingerApproaching")
            Core.DebugMsg(npc.GetDisplayName() + " reached player, sandboxing")
        ElseIf stillFar
            ; Player still far during approach — increment far ticks
            Int farTicks = StorageUtil.GetIntValue(npc, "Intel_LingerFarTicks", 0) + 1
            StorageUtil.SetIntValue(npc, "Intel_LingerFarTicks", farTicks)
            If farTicks >= Core.LINGER_FAR_TICKS_LIMIT
                Return true
            EndIf
        EndIf
        Return false  ; Still approaching or just switched — check again next cycle
    EndIf

    ; Sub-phase: sandboxing — release when player walks away
    Bool playerFar = true
    If npc.Is3DLoaded() && player.Is3DLoaded()
        playerFar = npc.GetDistance(player) > MEETING_LINGER_RELEASE_DISTANCE
    ElseIf npc.GetParentCell() == player.GetParentCell()
        playerFar = false  ; same interior cell = still nearby
    EndIf

    If playerFar
        ; Grace period — don't end on first "far" check
        Int farTicks = StorageUtil.GetIntValue(npc, "Intel_LingerFarTicks", 0) + 1
        StorageUtil.SetIntValue(npc, "Intel_LingerFarTicks", farTicks)
        If farTicks >= Core.LINGER_FAR_TICKS_LIMIT
            Return true
        Else
            ; NPC drifted — sandbox can't pull them back, switch to approach
            Core.DebugMsg(npc.GetDisplayName() + " linger: drifted (tick " + farTicks + "), re-approaching player")
            PO3_SKSEFunctions.SetLinkedRef(npc, player as ObjectReference, Core.IntelEngine_TravelTarget)
            ActorUtil.AddPackageOverride(npc, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
            ActorUtil.RemovePackageOverride(npc, Core.SandboxNearPlayerPackage)
            Utility.Wait(0.1)
            npc.EvaluatePackage()
            StorageUtil.SetIntValue(npc, "Intel_MeetingLingerApproaching", 1)
        EndIf
    Else
        ; Player is nearby — reset far counter
        StorageUtil.UnsetIntValue(npc, "Intel_LingerFarTicks")
    EndIf
    Return false
EndFunction

; =============================================================================
; SCHEDULED MEETING — LINGER
;
; After the player arrives at a meeting, the NPC walks toward the player,
; then sandboxes nearby. Released when the player walks away.
; =============================================================================

Function StartMeetingLinger(Int slot, Actor npc)
    {Start the post-meeting linger phase. Phase 1: walk toward player.
    Phase 2: sandbox within 200 units once close (100 units).
    Released when the player walks 800 units away.}
    Actor player = Game.GetPlayer()
    Core.DebugMsg(npc.GetDisplayName() + " starting meeting linger (approach first)")

    ; Clear overrides WITHOUT evaluating — prevents NPC briefly reverting to base AI
    Core.RemoveAllPackages(npc, false)
    PO3_SKSEFunctions.SetLinkedRef(npc, player as ObjectReference, Core.IntelEngine_TravelTarget)

    ; Phase 1: Walk toward player first — sandbox kicks in at 100 units
    ActorUtil.AddPackageOverride(npc, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
    npc.EvaluatePackage()

    StorageUtil.SetIntValue(npc, "Intel_MeetingLingering", 1)
    StorageUtil.SetIntValue(npc, "Intel_MeetingLingerApproaching", 1)

    ; Update schedule slot to meeting_active
    If Core.Schedule
        Int schedSlot = Core.Schedule.FindScheduleSlotByAgent(npc)
        If schedSlot >= 0
            Core.Schedule.SetScheduleState(schedSlot, 2)
        EndIf
    EndIf
EndFunction

Function CompleteMeeting(Int slot, Actor npc)
    {Player walked away — meeting complete, release the NPC.}
    String npcName = npc.GetDisplayName()
    Core.DebugMsg(npcName + " meeting complete (player left)")

    ; Narrate player departure — past tense, factual only (no emotion, no future intent)
    String playerName = Game.GetPlayer().GetDisplayName()
    Core.SendTaskNarration(npc, playerName + " walked away.", Game.GetPlayer())
    Core.NotifyPlayer(npcName + " headed off after the meeting")

    ; Mark as complete
    StorageUtil.SetStringValue(npc, "Intel_Result", "player_arrived")

    ; Clear the slot and restore follower status
    Core.ClearSlotRestoreFollower(slot, npc)

    ; Clear schedule slot — meeting truly complete
    If Core.Schedule
        Core.Schedule.ClearScheduleSlotByAgent(npc)
    EndIf
EndFunction

; =============================================================================
; TRAVEL LINGER (GoToLocation — NPC arrived, hangs out, leaves when player walks away)
; =============================================================================

Function StartTravelLinger(Int slot, Actor npc)
    {NPC arrived at GoToLocation destination and player is nearby.
    Same approach-then-sandbox pattern as meeting linger:
    Phase 1: Walk toward player. Phase 2: Sandbox within 200 units.
    Released when the player walks away.}
    Actor player = Game.GetPlayer()
    Core.DebugMsg(npc.GetDisplayName() + " starting travel linger (approach first)")

    ; Clear overrides WITHOUT evaluating — prevents NPC briefly reverting to base AI
    Core.RemoveAllPackages(npc, false)
    PO3_SKSEFunctions.SetLinkedRef(npc, player as ObjectReference, Core.IntelEngine_TravelTarget)

    ; Phase 1: Walk toward player first — sandbox kicks in at LINGER_APPROACH_DISTANCE
    ActorUtil.AddPackageOverride(npc, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
    npc.EvaluatePackage()

    StorageUtil.SetIntValue(npc, "Intel_TravelLingering", 1)
    StorageUtil.SetIntValue(npc, "Intel_MeetingLingerApproaching", 1)
    StorageUtil.SetStringValue(npc, "Intel_Result", "arrived")
EndFunction

Function CompleteTravelLinger(Int slot, Actor npc)
    {Player walked away — travel linger complete, release the NPC.}
    String npcName = npc.GetDisplayName()
    Core.DebugMsg(npcName + " travel linger complete (player left)")
    StorageUtil.SetStringValue(npc, "Intel_Result", "arrived")
    Core.ClearSlotRestoreFollower(slot, npc)
EndFunction

; =============================================================================
; CANCEL API
; =============================================================================

Function CancelTravel(Actor npc)
    {Cancel active travel for an NPC}

    If npc == None
        Return
    EndIf

    Int slot = Core.FindSlotByAgent(npc)
    If slot >= 0 && Core.SlotTaskTypes[slot] == "travel"
        Core.DebugMsg("Canceling travel for " + npc.GetDisplayName())
        Core.NotifyPlayer(npc.GetDisplayName() + " stopped traveling")
        StorageUtil.SetStringValue(npc, "Intel_Result", "cancelled")
        Core.ClearSlot(slot, true)
    EndIf
EndFunction

; =============================================================================
; UTILITY
; =============================================================================

Float Function ClampFloat(Float value, Float minVal, Float maxVal)
    If value < minVal
        Return minVal
    ElseIf value > maxVal
        Return maxVal
    EndIf
    Return value
EndFunction

; =============================================================================
; STATUS QUERIES
; =============================================================================

Bool Function IsNPCTraveling(Actor npc)
    Int slot = Core.FindSlotByAgent(npc)
    Return slot >= 0 && Core.SlotTaskTypes[slot] == "travel"
EndFunction

String Function GetTravelStatus(Actor npc)
    Int slot = Core.FindSlotByAgent(npc)
    If slot < 0 || Core.SlotTaskTypes[slot] != "travel"
        Return ""
    EndIf

    Int taskState = Core.SlotStates[slot]
    String dest = Core.SlotTargetNames[slot]

    If taskState == 1
        Return "traveling to " + dest
    ElseIf taskState == 2
        Return "waiting at " + dest
    EndIf

    Return "on travel task"
EndFunction

String Function GetDestination(Actor npc)
    Int slot = Core.FindSlotByAgent(npc)
    If slot < 0 || Core.SlotTaskTypes[slot] != "travel"
        Return ""
    EndIf
    Return Core.SlotTargetNames[slot]
EndFunction
