Scriptname IntelEngine_Travel extends Quest
{
    IntelEngine Travel & Navigation System

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

Float Property MAX_TASK_HOURS = 7.0 AutoReadOnly
{Game hours before an off-screen travel task is force-completed. Safety net for
NPCs whose 3D never loads (player never visits their cell), so position-based
stuck detection never fires.}

Float Property MIN_WAIT_HOURS = 6.0 AutoReadOnly
Float Property MAX_WAIT_HOURS = 168.0 AutoReadOnly
Float Property DEFAULT_WAIT_HOURS = 48.0 AutoReadOnly
Float Property SELF_MOTIVATED_LINGER_HOURS = 3.0 AutoReadOnly

Float Property LINGER_AFTER_TALK_HOURS = 0.5 AutoReadOnly
{A lingering NPC stays at least this long (game hours) after their last spoken line, so a visit is never
ended in the middle of a conversation. Half a game hour is a minute and a half at the default timescale.}

Float Property STAY_AT_DEST_LINGER_HOURS = 2.0 AutoReadOnly
{How long (game hours) an NPC who was sent to wait in a room keeps the player company there.}

; LINGER_RELEASE_DISTANCE defined on Core (single source of truth).

Float Property MEETING_PLAYER_PROXIMITY = 2000.0 AutoReadOnly
{If player is within this distance of meeting destination, NPC starts walking toward them}

Float Property LEAPFROG_MAX_DISTANCE = 2000.0 AutoReadOnly
{Maximum leapfrog distance (last resort).}

Float Property LEAPFROG_NUDGE_DISTANCE = 200.0 AutoReadOnly
{First leapfrog attempt: minimal nudge straight toward destination.}

Float Property LEAPFROG_MEDIUM_DISTANCE = 500.0 AutoReadOnly
{Second attempt: medium leap with angle rotation to try alternate terrain.}

Float Property LEAPFROG_LARGE_DISTANCE = 1000.0 AutoReadOnly
{Third attempt: large leap with opposite angle to try other side of obstacle.}

Float Property LEAPFROG_ANGLE_CW = 30.0 AutoReadOnly
{Clockwise angle offset (degrees) for second leapfrog attempt.
Rotates movement vector to find passable terrain around mountains.}

Float Property LEAPFROG_ANGLE_CCW = -30.0 AutoReadOnly
{Counter-clockwise angle for third attempt. Alternation tries both sides.}

Function EnsureMonitoringAlive()
    {Lightweight heartbeat: if active travel tasks exist, re-register the update loop.
    Called by Schedule's game-time loop as a safety net against Papyrus VM stack dumps
    that can kill RegisterForSingleUpdate callbacks.
    Does NOT re-apply packages — just ensures the monitoring loop is alive.}
    Int i = 0
    While i < Core.MAX_SLOTS
        If Core.SlotStates[i] != 0 && (Core.SlotTaskTypes[i] == "travel" || Core.SlotTaskTypes[i] == "assassination")
            Core.RequestTick(Core.UPDATE_INTERVAL)
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
        If Core.SlotStates[i] != 0 && (Core.SlotTaskTypes[i] == "travel" || Core.SlotTaskTypes[i] == "assassination")
            hasActive = true
            RecoverTravelPackage(i)
        EndIf
        i += 1
    EndWhile
    If hasActive
        Core.RequestTick(Core.UPDATE_INTERVAL)
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
    If taskState == 2
        ; Arrived: waiting or lingering. The package overrides survive a save, the linked ref they work
        ; around does not. Without it the sandbox has no place (the NPC drifted off toward home while the
        ; slot still said "waiting at the destination") and a walk toward the player had nothing to walk to.
        RelinkAfterLoad(npc)
        Return
    EndIf
    If taskState != 1
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

    ; Re-initialize stuck tracking so detection starts fresh. The trip's own start time is kept: it was
    ; reset here, so every load gave the trip another full MAX_TASK_HOURS before the time limit applied.
    Float startedAt = StorageUtil.GetFloatValue(npc, "Intel_TaskStartTime", 0.0)
    Core.InitializeStuckTrackingForSlot(slot, npc)
    If startedAt > 0.0
        StorageUtil.SetFloatValue(npc, "Intel_TaskStartTime", startedAt)
    EndIf

    ; Re-init off-screen tracking from persisted data (only on legacy path;
    ; co-save path already initialized this in SyncArraysFromSlotTracker)
    If !IntelEngine.HasCoSaveTaskData()
        Float offscreenArrival = StorageUtil.GetFloatValue(npc, "Intel_OffscreenArrival", 0.0)
        If offscreenArrival > 0.0
            IntelEngine.InitOffScreenTravel(slot, offscreenArrival, npc)
        EndIf
    EndIf

    Core.DebugMsg("Recovered travel package for " + npc.GetDisplayName())
EndFunction

Function RelinkAfterLoad(Actor npc)
    {Give an arrived NPC the linked ref back that their package works around: the player while they approach
    or keep the player company, otherwise the place they are waiting at.}
    ObjectReference anchor = None
    Bool lingering = StorageUtil.GetIntValue(npc, "Intel_MeetingLingering") == 1 || StorageUtil.GetIntValue(npc, "Intel_TravelLingering") == 1
    Bool staysPut = StorageUtil.GetIntValue(npc, "Intel_StayAtDest") == 1 && StorageUtil.GetIntValue(npc, "Intel_WaitForPlayer") != 1
    If (lingering && !staysPut) || StorageUtil.GetIntValue(npc, "Intel_MeetingApproaching") == 1
        anchor = Game.GetPlayer()
    Else
        anchor = StorageUtil.GetFormValue(npc, "Intel_DestMarker") as ObjectReference
        ; Same rule as on arrival: a sandbox around a marker that is not loaded crashes the engine.
        If anchor == None || !npc.Is3DLoaded() || !anchor.Is3DLoaded()
            anchor = npc
        EndIf
    EndIf
    PO3_SKSEFunctions.SetLinkedRef(npc, anchor, Core.IntelEngine_TravelTarget)
    npc.EvaluatePackage()
    Core.DebugMsg("Re-linked " + npc.GetDisplayName() + " after load (waiting at the destination)")
EndFunction

; =============================================================================
; MAIN API - GoToLocation
; =============================================================================

Bool Function GoToLocation(Actor akNPC, String destination, Int speed = 0, Int waitForPlayer = 1, Bool isScheduled = false, String taskOrigin = "SkyrimNet dialogue action")
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

    ; Carriage drivers and children are never sent travelling (see Core.IsUnsuitableTaskAgent).
    If Core.IsUnsuitableTaskAgent(akNPC)
        Core.DebugMsg("GoToLocation: " + akNPC.GetDisplayName() + " is not sent on tasks (carriage driver or child)")
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

    ; Block GoToLocation while NPC is on a multi-step task (fetch, escort, search).
    ; These tasks have their own travel logic — GoToLocation would interrupt mid-task.
    If !isScheduled
        String currentTaskType = Core.GetNPCTaskType(akNPC)
        If currentTaskType == "fetch_npc" || currentTaskType == "escort_target" || currentTaskType == "search_for_actor"
            Core.DebugMsg("GoToLocation: Blocked - " + akNPC.GetDisplayName() + " is busy with " + currentTaskType)
            Return false
        EndIf
    EndIf

    ; Everything that can make the trip impossible is checked before the player is asked and before the
    ; task the NPC already has is called off. It used to come after: an unknown place name, or no free
    ; slot, cancelled the running task, announced "departed for ..." and then did nothing.
    ; Resolve destination - try semantic first, then named
    ObjectReference destMarker = ResolveDestination(akNPC, destination)
    If destMarker == None
        ; Couldn't resolve - describe the situation factually
        Core.SendTaskNarration(akNPC, akNPC.GetDisplayName() + " was asked to travel to '" + destination + "' but a route could not be determined.")
        Return false
    EndIf
    ; Read at once: the next resolution (for any NPC) replaces it, and the prompt below can take a while.
    Int homeCellId = IntelEngine.GetLastResolvedHomeCellId()

    ; A slot has to be there: a free one, or the one this NPC's current task gives up.
    If Core.FindFreeAgentSlot() < 0 && Core.FindSlotByAgent(akNPC) < 0
        Core.DebugMsg("GoToLocation: No free slots")
        Core.SendTaskNarration(akNPC, akNPC.GetDisplayName() + " cannot take on another task right now.")
        Return false
    EndIf

    ; MCM task confirmation prompt (skip for scheduled meetings - player already agreed)
    If !isScheduled
        Int confirmResult = Core.ShowTaskConfirmationForAction(akNPC, akNPC.GetDisplayName() + " wants to travel to " + destination + ".", "GoToLocation", taskOrigin)
        If confirmResult == 1
            Core.SendTaskNarration(akNPC, Game.GetPlayer().GetDisplayName() + " told " + akNPC.GetDisplayName() + " they cannot go to " + destination + ".")
            Return false
        ElseIf confirmResult == 2
            Return false
        EndIf
    EndIf

    ; Register event AFTER confirmation (not in YAML — prevents event on deny silent)
    SkyrimNetApi.RegisterEvent("intel_task_event", akNPC.GetDisplayName() + " departed for " + destination + " (task in progress)", akNPC, None)

    ; Override existing task if any
    Core.OverrideExistingTask(akNPC)

    ; Find free slot
    Int slot = Core.FindFreeAgentSlot()
    If slot < 0
        Core.DebugMsg("GoToLocation: No free slots")
        Core.SendTaskNarration(akNPC, akNPC.GetDisplayName() + " cannot take on another task right now.")
        Return false
    EndIf

    ; Anti-trespass: unlock home door if destination is a home
    If homeCellId != 0
        IntelEngine.SetHomeDoorAccessForCell(homeCellId, true)
        StorageUtil.SetIntValue(akNPC, "Intel_UnlockedHomeCellId", homeCellId)
        Core.DebugMsg("Unlocked home door for " + destination)
    EndIf

    ; Calculate wait deadline from MCM setting
    Float waitHours = Core.GetDefaultWaitHours()
    waitHours = ClampFloat(waitHours, MIN_WAIT_HOURS, MAX_WAIT_HOURS)

    ; Allocate slot
    Core.AllocateSlot(slot, akNPC, "travel", destination, speed, taskOrigin)

    ; Store wait hours - deadline will be calculated on arrival, not now
    StorageUtil.SetFloatValue(akNPC, "Intel_WaitHours", waitHours)

    ; Self-motivated flag: NPC went on their own, no player expectation
    StorageUtil.SetIntValue(akNPC, "Intel_WaitForPlayer", waitForPlayer)

    ; Store destination marker
    StorageUtil.SetFormValue(akNPC, "Intel_DestMarker", destMarker)

    ; Asked in conversation: let them finish the sentence before they turn and go. A scheduled trip starts
    ; on the clock, not on a spoken line, so it sets off at once.
    If !isScheduled
        ; The monitoring loop already sees this slot: give it fresh trackers, or it reads the previous
        ; occupant's and counts the pause as standing still.
        Core.InitializeStuckTrackingForSlot(slot, akNPC)
        Core.InitOffScreenTracking(slot, akNPC, destMarker)
        Core.LetFinishSpeaking(akNPC)
        ; Back from the wait. The trip may have been cancelled or replaced, or the monitoring loop may have
        ; found them at the destination already (state 2): putting the travel package on then walked an
        ; "arrived" NPC back out to the door.
        If Core.FindSlotByAgent(akNPC) != slot || Core.SlotTaskTypes[slot] != "travel" || Core.SlotStates[slot] != 1 \
            || StorageUtil.GetFormValue(akNPC, "Intel_DestMarker") != destMarker
            Core.DebugMsg(akNPC.GetDisplayName() + ": trip replaced, cancelled or already over before setting off")
            Return true
        EndIf
    EndIf

    Core.NotifyPlayer(akNPC.GetDisplayName() + " headed off to " + destination)

    ; Stop following — traveling implies leaving the player. Only now, after the wait: done before it, a
    ; follower stood there for the length of the sentence with every package taken away.
    Core.DismissFollowerForTask(akNPC)

    ; Already inside the place they are asked to go to: arrived, without a false start toward its outside door.
    If ArrivedByBeingInside(slot, akNPC)
        Core.RequestTick(Core.UPDATE_INTERVAL)
        Return true
    EndIf

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

    ; Fast-path arrival detection. C++ polls every 150ms and fires
    ; OnProximityArrived the instant the NPC enters range — eliminates
    ; face-bumping caused by the 3s Papyrus poll.
    IntelEngine.ArmProximityArrival(slot, akNPC as ObjectReference, destMarker, Self, "IntelEngine_Travel", "OnProximityArrived")

    ; Start monitoring
    Core.RequestTick(Core.UPDATE_INTERVAL)

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
        If Core.SlotStates[i] != 0 && (Core.SlotTaskTypes[i] == "travel" || Core.SlotTaskTypes[i] == "assassination")
            hasActiveTravelers = true
        EndIf
        i += 1
    EndWhile

    If hasActiveTravelers
        Core.RequestTick(Core.UPDATE_INTERVAL)
    EndIf

    ; Now process slots — if this errors out, the next update is already scheduled
    i = 0
    While i < Core.MAX_SLOTS
        If Core.SlotStates[i] != 0 && (Core.SlotTaskTypes[i] == "travel" || Core.SlotTaskTypes[i] == "assassination")
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

    If npc.IsDisabled()
        ; Switched off by a quest or another mod: no package runs, they would "travel" until the time limit
        ; and then be moved to the destination while still disabled.
        Core.DebugMsg("Slot " + slot + ": " + npc.GetDisplayName() + " is disabled -> trip ended")
        If StorageUtil.GetIntValue(npc, "Intel_IsScheduledMeeting") == 1
            String offDest = StorageUtil.GetStringValue(npc, "Intel_MeetingDest")
            If offDest == ""
                offDest = Core.SlotTargetNames[slot]
            EndIf
            Core.NotifyPlayer(npc.GetDisplayName() + " could not come to the meeting at " + offDest + ". It is off.")
            Core.ClearSlot(slot)
            If Core.Schedule
                Core.Schedule.ClearScheduleSlotByAgent(npc)
            EndIf
        Else
            Core.ClearSlot(slot)
        EndIf
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
                            Core.DebugMsg(npcName2 + " is " + hoursLate + "h late for meeting - cancelling")
                            Core.StoreMeetingOutcome(npc, "npc_late", meetDest)
                            Core.NotifyPlayer(npcName2 + " never made it to the meeting at " + meetDest)
                            Core.ClearSlotRestoreFollower(slot, npc)
                            If Core.Schedule
                                Core.Schedule.ClearScheduleSlotByAgent(npc)
                            EndIf
                            ; Somewhere on the road: one with no routine of their own is sent home.
                            Core.ReleaseLinger(npc)
                            Return
                        EndIf
                    EndIf
                EndIf
                If !Core.PlayerCanSee(npc)
                    Core.DebugMsg("Travel timeout (" + elapsedHours + "h) for " + npc.GetDisplayName() + " - force-arriving")
                    ObjectReference dest = StorageUtil.GetFormValue(npc, "Intel_DestMarker") as ObjectReference
                    If dest != None
                        npc.MoveTo(dest)
                    EndIf
                    OnArrival(slot, npc)
                    Return
                EndIf
                ; In plain view after all this time. Vanishing in front of the player is worse than not arriving.
                ; If they are still covering ground (a long road, walked together with the player) the trip
                ; simply goes on and is looked at again in an hour; the limit is for those who got nowhere.
                Float capX = StorageUtil.GetFloatValue(npc, "Intel_CapCheckX", 0.0)
                Float capY = StorageUtil.GetFloatValue(npc, "Intel_CapCheckY", 0.0)
                Float capDX = npc.GetPositionX() - capX
                Float capDY = npc.GetPositionY() - capY
                If (capX == 0.0 && capY == 0.0) || capDX * capDX + capDY * capDY > 1000000.0
                    StorageUtil.SetFloatValue(npc, "Intel_CapCheckX", npc.GetPositionX())
                    StorageUtil.SetFloatValue(npc, "Intel_CapCheckY", npc.GetPositionY())
                    StorageUtil.SetFloatValue(npc, "Intel_TaskStartTime", startTime + 1.0 / 24.0)
                    Core.DebugMsg("Travel time limit for " + npc.GetDisplayName() + " in view and still moving - another hour")
                Else
                    ; No further in an hour: the trip ends in character and the NPC goes back to their own day.
                    Core.DebugMsg("Travel timeout (" + elapsedHours + "h) for " + npc.GetDisplayName() + " in view - giving up instead of teleporting")
                    If StorageUtil.GetIntValue(npc, "Intel_IsScheduledMeeting") == 1
                        HandleMeetingDepartureFailure(slot, npc)
                    Else
                        Core.SendTaskNarration(npc, npc.GetDisplayName() + " " + IntelEngine.BuildStuckNarration("travel"), Game.GetPlayer())
                        StorageUtil.SetStringValue(npc, "Intel_Result", "gave_up")
                        Core.ClearSlotRestoreFollower(slot, npc)
                        Core.ReleaseLinger(npc)
                    EndIf
                    Return
                EndIf
            EndIf
        EndIf
    EndIf

    If taskState == 1
        ; Already inside the place they are headed for: nothing to walk, and nothing to "fail to depart" from.
        If ArrivedByBeingInside(slot, npc)
            Return
        EndIf
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

Bool Function ArrivedByBeingInside(Int slot, Actor npc)
    {A named interior ("The Bannered Mare") resolves to its outside door. An NPC who is inside that very place
    when the trip starts (they live or work there, or the meeting was arranged on the spot) has arrived.
    Without this they were sent to the outside door, usually never left, and a scheduled meeting was then
    called off as a failed departure, so the NPC "never showed up" at the place both were standing in.}
    ObjectReference dest = StorageUtil.GetFormValue(npc, "Intel_DestMarker") as ObjectReference
    If dest == None
        Return false
    EndIf
    Cell npcCell = npc.GetParentCell()
    If npcCell == None || !npcCell.IsInterior()
        Return false
    EndIf
    ObjectReference inside = IntelEngine.GetDoorDestinationRef(dest)
    If inside == None || inside.GetParentCell() != npcCell
        Return false
    EndIf
    Core.DebugMsg(npc.GetDisplayName() + " is already inside the destination -> arrived")
    ; Same bookkeeping as walking through the door: the anchor for waiting is the door on this side.
    PO3_SKSEFunctions.SetLinkedRef(npc, inside, Core.IntelEngine_TravelTarget)
    StorageUtil.SetFormValue(npc, "Intel_DestMarker", inside)
    OnArrival(slot, npc)
    Return true
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

    ; Max Z difference to consider NPC on the same floor as a non-door target.
    ; Matches C++ FindFurnitureAbove minZDiff — one floor is typically 200-400 units.
    Float floorZTolerance = 150.0

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

                ; Update refs to the door in the new cell so post-arrival sandbox
                ; and approach-proximity checks work in the correct cell.
                PO3_SKSEFunctions.SetLinkedRef(npc, doorDest, Core.IntelEngine_TravelTarget)
                StorageUtil.SetFormValue(npc, "Intel_DestMarker", doorDest)

                ; Multi-hop: if target was "outside" but the door led to another
                ; interior (e.g. upstairs -> main floor), find the exterior door
                ; in the new cell and teleport through that too.
                If !IntelEngine.IsDoorExterior(dest)
                    String targetName = Core.SlotTargetNames[slot]
                    If IntelEngine.StringContains(IntelEngine.StringToLower(targetName), "outside")
                        TeleportToExterior(npc)
                    EndIf
                EndIf
                OnArrival(slot, npc)
            Else
                ; Non-door target (furniture/marker): verify NPC is on the same
                ; floor. Prevents false arrival when NPC stands below upper-floor
                ; furniture in same-cell interiors (e.g. Bannered Mare).
                Float zDiff = Math.Abs(dest.GetPositionZ() - npc.GetPositionZ())
                If zDiff <= floorZTolerance
                    OnArrival(slot, npc)
                Else
                    Core.DebugMsg(npc.GetDisplayName() + " within range but wrong floor (Z diff " + zDiff as Int + ")")
                    CheckIfStuck(slot, npc)
                EndIf
            EndIf
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
        ; Z-height check: same-cell multi-floor interiors (e.g. Bannered Mare)
        ; need Z proximity to confirm NPC is on the correct floor.
        Float zDiff = Math.Abs(dest.GetPositionZ() - npc.GetPositionZ())
        If zDiff <= floorZTolerance
            Core.DebugMsg(npc.GetDisplayName() + " reached destination cell (off-screen)")
            OnArrival(slot, npc)
            Return
        EndIf
        ; Wrong floor — fall through to HandleOffScreenTravel which will
        ; eventually MoveTo(dest), placing the NPC on the correct floor.
    EndIf

    ; NPC is on-screen — normal stuck detection + leapfrog recovery.
    ; Stuck detection only needs the NPC's position, not the destination 3D.
    If npc.Is3DLoaded()
        CheckIfStuck(slot, npc)
        Return
    EndIf

    ; NPC is off-screen — check estimated travel time and teleport if stationary
    If Core.HandleOffScreenTravel(slot, npc, dest)
        StepInside(slot, npc, dest)
        OnArrival(slot, npc)
    EndIf
EndFunction

Function StepInside(Int slot, Actor npc, ObjectReference dest)
    {A named building resolves to its outside door. Someone who walks there in view goes in through it (see
    CheckForArrival above); someone who got there unseen was left standing outside it, at Dragonsreach on the
    doorstep above the pond. Puts them on the far side of that door and makes it the place they wait at, the
    same bookkeeping as walking through. Nothing happens when the destination is not a door.}
    ObjectReference doorDest = IntelEngine.GetDoorDestinationRef(dest)
    If doorDest == None
        Return
    EndIf
    npc.MoveTo(doorDest)
    PO3_SKSEFunctions.SetLinkedRef(npc, doorDest, Core.IntelEngine_TravelTarget)
    StorageUtil.SetFormValue(npc, "Intel_DestMarker", doorDest)
    Core.DebugMsg(npc.GetDisplayName() + " arrived unseen -> through the door, as on foot")
    If !IntelEngine.IsDoorExterior(dest)
        String targetName = Core.SlotTargetNames[slot]
        If IntelEngine.StringContains(IntelEngine.StringToLower(targetName), "outside")
            TeleportToExterior(npc)
        EndIf
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
                PO3_SKSEFunctions.SetLinkedRef(npc, extDest, Core.IntelEngine_TravelTarget)
                StorageUtil.SetFormValue(npc, "Intel_DestMarker", extDest)
                Return
            EndIf
        EndIf
        d += 1
    EndWhile
    Core.DebugMsg(npc.GetDisplayName() + " multi-hop: no exterior door found in cell")
EndFunction

Bool Function LeaveInteriorUnseen(Actor npc)
    {Put the NPC outside this building's door, as if they had walked out. The trip's destination and its
    linked ref are left alone (TeleportToExterior makes the door the destination).}
    ObjectReference[] doors = IntelEngine.GetCellDoors(npc)
    Int d = 0
    While d < doors.Length
        If IntelEngine.IsDoorExterior(doors[d])
            ObjectReference outside = IntelEngine.GetDoorDestinationRef(doors[d])
            If outside != None
                npc.MoveTo(outside)
                Return true
            EndIf
        EndIf
        d += 1
    EndWhile
    Return false
EndFunction

; Callback invoked by the C++ ProximityMonitor the instant the NPC enters
; arrival range. Routes through the normal CheckForArrival path so door
; teleporting, floor-Z verification, and state transitions all behave
; identically to the 3s poll's arrival branch.
Function OnProximityArrived(String slotStr)
    Int slot = slotStr as Int
    If slot < 0 || slot >= Core.MAX_SLOTS
        Return
    EndIf
    ; Only act for travel/assassination tasks still in the traveling state.
    Int taskState = Core.SlotStates[slot]
    String taskTypeStr = Core.SlotTaskTypes[slot]
    If taskState != 1 || (taskTypeStr != "travel" && taskTypeStr != "assassination")
        Return
    EndIf
    ReferenceAlias agentAlias = Core.GetAgentAlias(slot)
    If agentAlias == None
        Return
    EndIf
    Actor npc = agentAlias.GetActorReference()
    If npc == None || npc.IsDead()
        Return
    EndIf
    CheckForArrival(slot, npc)
EndFunction

Function OnArrival(Int slot, Actor npc)
    ; Idempotency guard — C++ proximity fast path and Papyrus 3s poll can race.
    ; Only the first caller should run the arrival logic.
    If Core.SlotStates[slot] != 1
        Core.DebugMsg(npc.GetDisplayName() + " OnArrival skipped (state=" + Core.SlotStates[slot] + ")")
        Return
    EndIf
    ; Several callers get here after a wait or a teleport. If the slot changed hands meanwhile, state 1 is
    ; the new task's: running the arrival then gave this NPC a sandbox nothing would ever take away again
    ; and marked the other NPC's trip as arrived.
    If !Core.SlotHolds(slot, npc)
        Core.DebugMsg(npc.GetDisplayName() + " OnArrival skipped (slot " + slot + " is no longer theirs)")
        Return
    EndIf

    ; Proximity watch is no longer needed once we are past state 1.
    IntelEngine.DisarmProximityArrival(slot)

    String destination = Core.SlotTargetNames[slot]
    String taskType = Core.SlotTaskTypes[slot]

    ; Assassination: assassin reached the leader — hand off to Battle for attack sequence
    ; Note: HandleAssassinArrival contains Utility.Wait (yields), so clear slot BEFORE
    ; calling it. CleanupManifestation handles remaining cleanup after the attack.
    If taskType == "assassination"
        Core.DebugMsg(npc.GetDisplayName() + " reached assassination target " + destination)
        Core.RemoveAllPackages(npc, true)
        npc.RemoveFromFaction(Core.IntelEngine_TaskFaction)
        Core.ClearSlot(slot, false)  ; free slot immediately — assassin is disposable
        Core.Battle.HandleAssassinArrival(npc, destination)
        return
    EndIf

    Core.DebugMsg(npc.GetDisplayName() + " arrived at " + destination)
    Bool isMeetingArrival = StorageUtil.GetIntValue(npc, "Intel_IsScheduledMeeting") == 1
    If !isMeetingArrival
        Core.NotifyPlayer(npc.GetDisplayName() + " arrived at " + destination)
    EndIf

    ; Remove travel package — don't evaluate yet (sandbox applied immediately after,
    ; avoids a brief gap where NPC reverts to default AI)
    Core.RemoveIntelPackages(npc, false)

    ; Keep travel linked ref — points to the destination marker (or doorDest
    ; after door teleportation, updated in CheckForArrival/TeleportToExterior).
    ; SandboxNearPlayerPackage uses this ref for its sandbox location (200-unit radius).
    ; Clearing it here causes the NPC to fall back to their home location.
    ; The ref is cleaned up later in ClearSlot → ClearLinkedRefs.

    ; Apply tight sandbox at destination (linked ref = destination marker)
    ActorUtil.AddPackageOverride(npc, Core.SandboxNearPlayerPackage, Core.PRIORITY_SANDBOX, 1)

    ; Off-screen: redirect linked ref to NPC itself before evaluating. The
    ; destination marker may be in an unloaded cell — the engine's sandbox
    ; procedure can't resolve that location, causing a null vtable crash
    ; (BGSProcedureSandbox, call [rax+0x4B8]). The NPC is already at the
    ; destination so self-ref gives an equivalent 200-unit sandbox radius.
    If !npc.Is3DLoaded()
        PO3_SKSEFunctions.SetLinkedRef(npc, npc as ObjectReference, Core.IntelEngine_TravelTarget)
    EndIf
    npc.EvaluatePackage()

    ; Ensure building access: if NPC is inside an interior, unlock door + remove trespass
    Core.EnsureBuildingAccess(npc)

    ; Calculate wait deadline NOW (at arrival, not at task creation)
    Bool isSelfMotivated = StorageUtil.GetIntValue(npc, "Intel_WaitForPlayer") != 1

    If isMeetingArrival
        ; Meetings: deadline is always meetingTime + timeout.
        ; If NPC arrives late and the deadline already passed, OnWaitTimeout
        ; fires on the next CheckWaiting cycle.
        Float meetingTime = StorageUtil.GetFloatValue(npc, "Intel_MeetingTime", 0.0)
        Float meetTimeout = StorageUtil.GetFloatValue(Game.GetPlayer(), "Intel_MeetingTimeoutHours", 5.0)
        Core.SetSlotDeadline(slot, meetingTime + (meetTimeout / 24.0))
    ElseIf isSelfMotivated
        ; Self-motivated: short linger at destination, no player expectation
        Core.SetSlotDeadline(slot, Utility.GetCurrentGameTime() + (SELF_MOTIVATED_LINGER_HOURS / 24.0))
    Else
        Float waitHours = StorageUtil.GetFloatValue(npc, "Intel_WaitHours")
        If waitHours <= 0.0
            waitHours = Core.GetDefaultWaitHours()
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
    ElseIf isSelfMotivated
        ; Self-motivated: NPC went here for their own reasons, no wait tracking
        Core.DebugMsg(npc.GetDisplayName() + " arrived at " + destination + " (self-motivated)")
    Else
        ; Player-directed GoToLocation: store arrival time for wait duration tracking.
        ; OnPlayerArrived uses this to narrate context-aware greetings.
        StorageUtil.SetFloatValue(npc, "Intel_TravelArrivalTime", Utility.GetCurrentGameTime())
        Core.DebugMsg(npc.GetDisplayName() + " arrived at " + destination + " (waiting)")
    EndIf

    ; If NPC arrived at an exterior door but the player is inside that building,
    ; unlock the door and redirect the NPC toward the player so they walk through
    ; the door naturally (no teleport — preserves immersion and approach flow).
    Actor player = Game.GetPlayer()
    Cell playerCell = player.GetParentCell()
    If playerCell != None && playerCell.IsInterior() && npc.GetParentCell() != playerCell
        ObjectReference destRef = StorageUtil.GetFormValue(npc, "Intel_DestMarker") as ObjectReference
        If destRef != None
            ObjectReference doorDest = IntelEngine.GetDoorDestinationRef(destRef)
            If doorDest != None && doorDest.GetParentCell() == playerCell
                ; Unlock the door so the NPC can walk through it
                IntelEngine.SetHomeDoorAccessForCell(playerCell.GetFormID(), true)
                StorageUtil.SetIntValue(npc, "Intel_UnlockedHomeCellId", playerCell.GetFormID())
                ; Redirect sandbox/travel anchor to player — NPC will pathfind through the door
                ComeThroughDoor(npc)
                Core.DebugMsg(npc.GetDisplayName() + " redirected through door into " + destination + " (player is inside)")
            EndIf
        EndIf
    EndIf

    ; If player is already in the same cell, handle immediately
    If npc.GetParentCell() == player.GetParentCell()
        If npc.Is3DLoaded() && player.Is3DLoaded() && npc.GetDistance(player) < 1000.0
            If StorageUtil.GetIntValue(npc, "Intel_IsScheduledMeeting") == 1
                ; Scheduled meeting — run the meeting flow (lateness, linger, etc.)
                OnPlayerArrived(slot, npc)
            ElseIf StorageUtil.GetIntValue(npc, "Intel_WaitForPlayer") == 1
                ; Player-directed travel — arrived with player nearby (traveled together)
                Core.SendTaskNarration(npc, npc.GetDisplayName() + " arrived at " \
                    + destination + " together with " + player.GetDisplayName() + ".", player)
                If IsStayAtDestination(destination)
                    StartStayAtDestLinger(slot, npc)
                Else
                    StartTravelLinger(slot, npc)
                EndIf
            Else
                ; Self-motivated — player just happens to be here, sandbox quietly
                StartStayAtDestLinger(slot, npc)
            EndIf
            Return
        EndIf
    EndIf
EndFunction

Function ComeThroughDoor(Actor npc)
    {The NPC stands at the outside door of the building the player is in: walk to the player, through the
    door. Applied once. It used to be applied again on every monitoring pass (packages cleared, walk package
    added, re-evaluated every three seconds), so the walk was restarted before it got anywhere.}
    If StorageUtil.GetIntValue(npc, "Intel_MeetingApproaching") == 1
        Return
    EndIf
    PO3_SKSEFunctions.SetLinkedRef(npc, Game.GetPlayer() as ObjectReference, Core.IntelEngine_TravelTarget)
    Core.RemoveIntelPackages(npc, false)
    ActorUtil.AddPackageOverride(npc, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
    npc.EvaluatePackage()
    ; Same bookkeeping as the approach inside one cell, so the same code ends it.
    StorageUtil.SetIntValue(npc, "Intel_MeetingApproaching", 1)
    StorageUtil.SetFloatValue(npc, "Intel_ApproachStartX", npc.GetPositionX())
    StorageUtil.SetFloatValue(npc, "Intel_ApproachStartY", npc.GetPositionY())
    StorageUtil.SetIntValue(npc, "Intel_ApproachTick", 0)
EndFunction

Bool Function LingerTimeIsUp(Actor npc, Float currentTime)
    {The linger's own clock. It ends the visit after a wait or sleep, and when the player stays around
    without another word. It never ends it in the middle of a conversation: the NPC used to walk off one
    game hour after the meeting began (three minutes at the default timescale), whatever was being said.}
    Float lingerDeadline = StorageUtil.GetFloatValue(npc, "Intel_MeetingLingerDeadline", 999999.0)
    ; The longest a visit lasts, whatever is being said (set on the first look, so every kind of linger has it).
    Float lingerCap = StorageUtil.GetFloatValue(npc, "Intel_MeetingLingerCap", 0.0)
    If lingerCap <= 0.0
        lingerCap = currentTime + Core.LINGER_VISIT_MAX_HOURS / 24.0
        StorageUtil.SetFloatValue(npc, "Intel_MeetingLingerCap", lingerCap)
    ElseIf currentTime > lingerCap
        Return true
    EndIf
    ; Only a conversation the player is part of keeps them (Core.IsTalkingWithPlayer says why).
    If Core.IsTalkingWithPlayer(npc)
        Float stayUntil = currentTime + LINGER_AFTER_TALK_HOURS / 24.0
        If lingerDeadline < stayUntil
            StorageUtil.SetFloatValue(npc, "Intel_MeetingLingerDeadline", stayUntil)
        EndIf
        Return false
    EndIf
    Return currentTime > lingerDeadline
EndFunction

Function CheckWaiting(Int slot, Actor npc)
    Actor player = Game.GetPlayer()
    Float currentTime = Utility.GetCurrentGameTime()
    Float deadline = Core.SlotDeadlines[slot]
    ; Phase: Post-meeting linger (player already met NPC, NPC hanging around)
    If StorageUtil.GetIntValue(npc, "Intel_MeetingLingering") == 1
        If ProcessLingerProximity(slot, npc)
            CompleteMeeting(slot, npc)
        ElseIf LingerTimeIsUp(npc, currentTime)
            CompleteMeeting(slot, npc, false)
        EndIf
        Return
    EndIf

    ; Phase: Travel linger (GoToLocation — NPC arrived, player nearby, sandboxing near player)
    If StorageUtil.GetIntValue(npc, "Intel_TravelLingering") == 1
        If ProcessLingerProximity(slot, npc) || LingerTimeIsUp(npc, currentTime)
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
    ; walk toward them. Self-motivated NPCs stay put (they're here for themselves, not the player).
    Bool isWaitingForPlayer = StorageUtil.GetIntValue(npc, "Intel_WaitForPlayer") == 1 || StorageUtil.GetIntValue(npc, "Intel_IsScheduledMeeting") == 1
    If !isWaitingForPlayer
        ; Log once per NPC so we know if waitForPlayer=0 is the reason approach/narration doesn't fire
        If StorageUtil.GetIntValue(npc, "Intel_SelfMotivatedLogged") != 1
            StorageUtil.SetIntValue(npc, "Intel_SelfMotivatedLogged", 1)
            Core.DebugMsg(npc.GetDisplayName() + " at destination (self-motivated, waitForPlayer=0) - no approach/narration")
        EndIf
    EndIf
    If isWaitingForPlayer
        ObjectReference destMarker = StorageUtil.GetFormValue(npc, "Intel_DestMarker") as ObjectReference
        Bool playerNearDest = false
        Bool comingThroughDoor = false

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
            Else
                ; Player might be inside a building whose exterior door is the destination.
                ; NPC is outside at the exterior door, player is inside.
                ; Unlock door and redirect NPC to walk through naturally.
                Cell pCell = player.GetParentCell()
                If pCell != None && pCell.IsInterior()
                    ObjectReference doorDest = IntelEngine.GetDoorDestinationRef(destMarker)
                    If doorDest != None && doorDest.GetParentCell() == pCell
                        If npc.GetParentCell() != pCell && StorageUtil.GetIntValue(npc, "Intel_MeetingApproaching") != 1
                            IntelEngine.SetHomeDoorAccessForCell(pCell.GetFormID(), true)
                            StorageUtil.SetIntValue(npc, "Intel_UnlockedHomeCellId", pCell.GetFormID())
                            ; Redirect toward player — NPC will pathfind through unlocked door
                            ComeThroughDoor(npc)
                            Core.DebugMsg(npc.GetDisplayName() + " redirected through door into " + Core.SlotTargetNames[slot] + " (player entered building)")
                        EndIf
                        ; Still outside and on the way in, or already through the door and walking up to the
                        ; player: either way the walk goes on (the branch below would call it off).
                        comingThroughDoor = true
                        ; Don't set playerNearDest — NPC is still outside walking through door.
                        ; CheckWaiting will detect proximity once NPC enters the cell.
                    EndIf
                EndIf
            EndIf
        EndIf

        If playerNearDest
            ; Player is near the destination — NPC should walk toward them
            ; (skip for stay-at-dest — NPC stays put, playerNearby handles arrival)
            ; GUARD: Never approach across cell boundaries (loading screens).
            ; NPC stays put until the player enters their cell — playerNearby handles that.
            Bool sameCell = npc.GetParentCell() == player.GetParentCell()
            If sameCell && !IsStayAtDestination(Core.SlotTargetNames[slot])
                If StorageUtil.GetIntValue(npc, "Intel_MeetingApproaching") != 1
                    ; Only start approach if NPC is visible — avoids ghost notifications
                    If npc.Is3DLoaded()
                        StartApproachingPlayer(slot, npc)
                    EndIf
                Else
                    CheckMeetingApproach(slot, npc)
                EndIf
            EndIf
            Return  ; Don't timeout while player is nearby
        ElseIf !comingThroughDoor
            ; Player left the area — stop approaching and return to destination sandbox
            If StorageUtil.GetIntValue(npc, "Intel_MeetingApproaching") == 1
                StopApproachingPlayer(npc)
                ; Restore sandbox at destination (not player)
                ObjectReference destMarker2 = StorageUtil.GetFormValue(npc, "Intel_DestMarker") as ObjectReference
                ; A sandbox around a marker that is not loaded crashes the engine (see OnArrival).
                If destMarker2 == None || !npc.Is3DLoaded() || !destMarker2.Is3DLoaded()
                    destMarker2 = npc
                EndIf
                PO3_SKSEFunctions.SetLinkedRef(npc, destMarker2, Core.IntelEngine_TravelTarget)
                ActorUtil.AddPackageOverride(npc, Core.SandboxNearPlayerPackage, Core.PRIORITY_SANDBOX, 1)
                npc.EvaluatePackage()
            EndIf
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

        ; Determine outcome using grace period tolerance (DRY)
        String outcome = "success"
        String npcLateness = "on_time"
        If npcArrivalTime > 0.0
            npcLateness = Core.DetermineLatenessOutcome(npcArrivalTime, meetingGameTime)
        EndIf
        String playerLateness = Core.DetermineLatenessOutcome(currentGameTime, meetingGameTime)

        If npcLateness == "late"
            ; NPC was significantly late getting to the meeting spot
            outcome = "npc_arrived_late"
            StorageUtil.SetFloatValue(npc, "Intel_MeetingLateHours", npcHoursLate)
            Core.SendTaskNarration(npc, npcName + " arrived at " + meetDest + " about " + (npcHoursLate as Int) + " hours late. " + playerName + " was already waiting.", player)
            Core.DebugMsg(npcName + ": NPC was " + (npcHoursLate as Int) + "h late to meeting")
        ElseIf playerLateness == "late"
            ; Player is significantly late (beyond grace period)
            outcome = "player_late"
            StorageUtil.SetFloatValue(npc, "Intel_MeetingLateHours", playerHoursLate)
            Core.SendTaskNarration(npc, npcName + " waited at " + meetDest + " for " + playerName + " who arrived about " + (playerHoursLate as Int) + " hours late.", player)
            Core.DebugMsg(npcName + ": Player " + (playerHoursLate as Int) + "h late to meeting")
        ElseIf playerHoursLate > 0.25
            ; Player is slightly late (within grace period but >15 min) - minor note
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
        ; === Regular travel ===
        npc.SetLookAt(player)

        If StorageUtil.GetIntValue(npc, "Intel_WaitForPlayer") == 1
            ; Player-directed: context-aware arrival narration with wait tracking
            Float arrivalTime = StorageUtil.GetFloatValue(npc, "Intel_TravelArrivalTime", 0.0)
            Float waitHours = 0.0
            If arrivalTime > 0.0
                waitHours = (Utility.GetCurrentGameTime() - arrivalTime) * 24.0
            EndIf

            If waitHours > 2.0
                Core.SendTaskNarration(npc, playerName + " finally arrived at " \
                    + destination + ". " + npcName + " had been waiting for a long time.", player)
            Else
                Core.SendTaskNarration(npc, playerName + " arrived at " + destination \
                    + " where " + npcName + " was waiting.", player)
            EndIf

            If IsStayAtDestination(destination)
                StartStayAtDestLinger(slot, npc)
            Else
                StartTravelLinger(slot, npc)
            EndIf
        Else
            ; Self-motivated: NPC is here for their own reasons, no waiting narration
            ; SkyrimNet handles natural dialogue via the NPC's travel fact in their bio
            StartStayAtDestLinger(slot, npc)
        EndIf
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

        ; Distinguish: NPC arrived after the timeout window, NPC was late but waited,
        ; or NPC was on time and player never showed up.
        Float meetingTime = StorageUtil.GetFloatValue(npc, "Intel_MeetingTime", 0.0)
        Float npcArrivalTime = StorageUtil.GetFloatValue(npc, "Intel_MeetingNpcArrivalTime", 0.0)
        Float meetTimeout = StorageUtil.GetFloatValue(Game.GetPlayer(), "Intel_MeetingTimeoutHours", 5.0)
        Float meetDeadline = meetingTime + (meetTimeout / 24.0)

        If npcArrivalTime > meetDeadline
            ; NPC arrived after the window expired — NPC was too late
            Core.StoreMeetingOutcome(npc, "npc_late", meetDest)
            Core.NotifyPlayer(npcName + " arrived too late for the meeting at " + meetDest)
        Else
            ; NPC arrived within timeout — check if NPC was late to the meeting time itself
            Float npcLateHours = 0.0
            If npcArrivalTime > 0.0
                npcLateHours = (npcArrivalTime - meetingTime) * 24.0
            EndIf

            If npcLateHours > Core.MeetingGracePeriod
                ; NPC was late to the meeting time but within timeout window — waited for player
                StorageUtil.SetFloatValue(npc, "Intel_MeetingLateHours", npcLateHours)
                Core.StoreMeetingOutcome(npc, "npc_late_player_no_show", meetDest)
                Core.NotifyPlayer(npcName + " arrived late to " + meetDest + " and eventually gave up waiting for you")
            Else
                ; NPC was there on time, player never showed
                Core.StoreMeetingOutcome(npc, "player_no_show", meetDest)
                Core.NotifyPlayer(npcName + " got tired of waiting for you at " + meetDest)
            EndIf
        EndIf
    Else
        Core.NotifyPlayer(npcName + " left " + destination)
    EndIf

    ; Mark as timeout
    StorageUtil.SetStringValue(npc, "Intel_Result", "timeout")

    ; Clear slot but don't restore follower (they gave up)
    ; ClearSlot handles schedule cleanup (preserving future schedules)
    Core.ClearSlot(slot, false)
    ; See CompleteMeeting: one with no routine of their own is walked home instead of staying for good.
    Core.ReleaseLinger(npc)
EndFunction

; =============================================================================
; STUCK DETECTION & RECOVERY
; =============================================================================

Function CheckIfStuck(Int slot, Actor npc)
    {Stuck detection dispatcher. Delegates to recovery strategies by severity.
    Status 0: moving normally. Status 1: soft recovery (nudge). Status 3: escalate
    (waypoint nav → multi-angle leapfrog → direct teleport).}

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
    ; Nor while the game has them doing something else (the bard's audience, a scene).
    If Core.HeldByAnotherPackage(slot, npc)
        Return
    EndIf

    Int status = IntelEngine.CheckStuckStatus(npc, slot, Core.STUCK_DISTANCE_THRESHOLD)
    If status == 0
        Return
    EndIf

    ObjectReference dest = StorageUtil.GetFormValue(npc, "Intel_DestMarker") as ObjectReference

    If status == 1
        HandleSoftStuckRecovery(slot, npc, dest)
    ElseIf status == 3 && dest != None
        HandleLeapfrogRecovery(slot, npc, dest)
    EndIf
EndFunction

Function HandleSoftStuckRecovery(Int slot, Actor npc, ObjectReference dest)
    {Status 1: NPC hasn't moved enough. Nudge + re-pathfind.
    First occurrence narrates so NPC reacts in-character.}
    Int attempts = IntelEngine.GetStuckRecoveryAttempts(slot)
    Core.DebugMsg("Soft recovery " + attempts + " for " + npc.GetDisplayName())

    ; Not while they are standing there talking: that is a conversation, not a stumble, and the line about
    ; their feet went into the middle of it.
    If attempts == 1 && !IntelEngine.IsActorTalking(npc)
        Core.SendTaskNarration(npc, npc.GetDisplayName() + " felt their feet catch on something and couldn't move for a moment, stumbling on the path.")
    EndIf

    Core.SoftStuckRecovery(npc, slot, dest)
EndFunction

Function HandleLeapfrogRecovery(Int slot, Actor npc, ObjectReference dest)
    {Status 3: Escalated stuck. Layer B: waypoint nav. Layer C: multi-angle leapfrog.
    Progressive distance (200→500→1000→2000) keeps NPC visible to player.
    Consecutive attempts rotate ±30° to find passable terrain around mountains.}

    ; Layer B: Try location marker navigation (on-screen only).
    If Core.TryWaypointNavigation(slot, npc, dest)
        Return
    EndIf

    ; Layer C moves the NPC by a teleport. Not while the player is looking: the hop waits until they look
    ; away (this recovery step is not used up), and the travel time limit stays the last resort.
    If Core.PlayerCanSee(npc)
        Core.SoftStuckRecovery(npc, slot, dest)
        Return
    EndIf

    ; Indoors a leap of up to 2000 units in a straight line, two metres up, ends inside a wall or outside
    ; the building's shell. Out of sight, the NPC is put at the destination if it is in this cell, else
    ; outside the building's door, from where the road is open.
    If npc.IsInInterior()
        If dest.GetParentCell() == npc.GetParentCell()
            Core.DebugMsg(npc.GetDisplayName() + " stuck indoors, out of sight - placed at the destination")
            npc.MoveTo(dest)
        ElseIf LeaveInteriorUnseen(npc)
            Core.DebugMsg(npc.GetDisplayName() + " stuck indoors, out of sight - placed outside the door")
        EndIf
        If Core.SlotHolds(slot, npc)
            Package indoorPkg = Core.TravelPackageOn(npc, Core.GetTravelPackage(Core.SlotSpeeds[slot]))
            If indoorPkg
                ActorUtil.AddPackageOverride(npc, indoorPkg, Core.PRIORITY_TRAVEL, 1)
            EndIf
            npc.EvaluatePackage()
            IntelEngine.ResetStuckSlot(slot, npc)
        EndIf
        Return
    EndIf

    ; Layer C: Multi-angle leapfrog.
    ; C++ GetTeleportDistance returns descending values per attempt.
    ; We invert for Travel: ascending keeps NPC visible to player.
    Float descDist = IntelEngine.GetTeleportDistance(slot)

    ; First leapfrog — narrate so NPC tells player to go ahead
    If descDist >= 2000.0
        String destination = Core.SlotTargetNames[slot]
        Core.SendTaskNarration(npc, npc.GetDisplayName() + " had trouble getting through and urged " \
            + Game.GetPlayer().GetDisplayName() + " to go on ahead to " + destination \
            + " while trying to find a way around.", Game.GetPlayer())
    EndIf

    ; Pick distance + angle based on attempt progression
    Float leapDist
    Float angle = 0.0
    If descDist >= 2000.0
        leapDist = LEAPFROG_NUDGE_DISTANCE
    ElseIf descDist >= 1000.0
        leapDist = LEAPFROG_MEDIUM_DISTANCE
        angle = LEAPFROG_ANGLE_CW
    ElseIf descDist >= 500.0
        leapDist = LEAPFROG_LARGE_DISTANCE
        angle = LEAPFROG_ANGLE_CCW
    Else
        leapDist = LEAPFROG_MAX_DISTANCE
    EndIf

    ; Calculate vector toward destination
    Float dx = dest.GetPositionX() - npc.GetPositionX()
    Float dy = dest.GetPositionY() - npc.GetPositionY()
    Float totalDist = Math.sqrt(dx * dx + dy * dy)

    If totalDist <= leapDist + Core.ARRIVAL_DISTANCE
        ; Close enough — teleport directly and arrive
        Core.DebugMsg("Stuck recovery: " + npc.GetDisplayName() + " close enough (" + totalDist + "u) - teleporting to dest")
        Core.DebugMsg(npc.GetDisplayName() + " arrived (placed at the destination by stuck recovery)")
        npc.MoveTo(dest, 0.0, 0.0, 50.0)
        npc.EvaluatePackage()
        OnArrival(slot, npc)
    Else
        ; Leapfrog toward destination with optional angle rotation
        Float ratio = leapDist / totalDist
        Float offsetX = dx * ratio
        Float offsetY = dy * ratio

        If angle != 0.0
            Float cosA = Math.cos(angle)
            Float sinA = Math.sin(angle)
            Float rotX = offsetX * cosA - offsetY * sinA
            Float rotY = offsetX * sinA + offsetY * cosA
            offsetX = rotX
            offsetY = rotY
        EndIf

        ; Z offset prevents sinking into terrain at mountain passes
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
    ; Not leaving because they are fighting, being spoken to or in the middle of a sentence is not a failed
    ; departure: the count starts again when they are free. It used to call the meeting off ("could not set
    ; out") fifteen seconds into a conversation that was going on when the hour came.
    If npc.IsInCombat() || npc.GetDialogueTarget() != None || IntelEngine.IsActorTalking(npc)
        Core.InitializeDepartureTracking(slot, npc)
        Return false
    EndIf
    ; Away from the player the position is only updated now and then. Their progress is the business of
    ; the off-screen estimate (HandleOffScreenTravel), which lets them arrive when the walk would be over,
    ; not fifteen seconds after they were sent.
    If !npc.Is3DLoaded()
        Return false
    EndIf
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
    ; (Unseen by the player, not merely unloaded: see Core.OutOfPlayersSight.)
    If Core.OutOfPlayersSight(npc)
        ; Player isn't looking — teleport silently to destination
        ObjectReference dest = StorageUtil.GetFormValue(npc, "Intel_DestMarker") as ObjectReference
        If dest != None
            Core.DebugMsg(npcName + " failed to depart for meeting (off-screen) - teleporting to destination")
            npc.MoveTo(dest, 0.0, 0.0, 50.0)
            StepInside(slot, npc, dest)
            npc.EvaluatePackage()
            OnArrival(slot, npc)
            Return
        EndIf
    EndIf

    ; Player is watching — narrate failure in past tense
    Core.DebugMsg(npcName + " failed to depart for meeting (visible) - narrating failure")
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

    Core.RemoveIntelPackages(npc)
    Core.ClearSlot(slot, true)
    ; Never drop a meeting the player agreed to without telling them.
    Core.NotifyPlayer(npcName + " could not set out for the meeting at " + meetDest + ". It is off.")

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

    ; Switch from sandbox to travel-toward-player (no evaluation in between: with nothing of ours on them
    ; for a moment, they turned toward their everyday routine first)
    Core.RemoveIntelPackages(npc, false)
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
        Core.DebugMsg(npc.GetDisplayName() + " stuck approaching player (off-screen) - teleporting behind")
        Core.TeleportBehindPlayer(npc)
        StopApproachingPlayer(npc)
        OnPlayerArrived(slot, npc)
    Else
        ; Visible — soft recovery: nudge + PathToReference
        Core.DebugMsg(npc.GetDisplayName() + " stuck approaching player (visible) - nudging")

        ; Narrate once so NPC can react to being stuck near the player
        If StorageUtil.GetIntValue(npc, "Intel_ApproachStuckNarrated") != 1
            StorageUtil.SetIntValue(npc, "Intel_ApproachStuckNarrated", 1)
            Core.SendTaskNarration(npc, npc.GetDisplayName() + " tried to reach " + player.GetDisplayName() + " but seemed unable to get past something.", player)
        EndIf

        ; The walk package is taken off and put back, which makes the AI plan the path afresh. No
        ; PathToReference: it is a forced run at full speed, and it held this monitoring pass (and every
        ; other slot in it) until the NPC got there or gave up.
        ActorUtil.RemovePackageOverride(npc, Core.TravelPackage_Walk)
        ActorUtil.AddPackageOverride(npc, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
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
    Core.RemoveIntelPackages(npc, false)

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
; Released when the player walks Core.LINGER_RELEASE_DISTANCE away.
; =============================================================================

Bool Function ProcessLingerProximity(Int slot, Actor npc)
    {Shared approach/sandbox/release logic for both meeting and travel linger.
    Returns true when linger should end (player walked away).}
    Actor player = Game.GetPlayer()

    ; Sub-phase: approaching player — walk until close, then sandbox
    If StorageUtil.GetIntValue(npc, "Intel_MeetingLingerApproaching") == 1
        Bool closeEnough = false
        Bool stillFar = true
        Float dist = -1.0
        If npc.Is3DLoaded() && player.Is3DLoaded()
            dist = npc.GetDistance(player)
            closeEnough = dist <= Core.LINGER_APPROACH_DISTANCE
            stillFar = dist > Core.LINGER_RELEASE_DISTANCE
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
            If dist >= 0.0 && dist < StorageUtil.GetFloatValue(npc, "Intel_LingerLastDist", -1.0) - 50.0
                farTicks = 0
            EndIf
            StorageUtil.SetIntValue(npc, "Intel_LingerFarTicks", farTicks)
            StorageUtil.SetFloatValue(npc, "Intel_LingerLastDist", dist)
            If farTicks >= Core.LINGER_FAR_TICKS_LIMIT
                Return true
            EndIf
        EndIf
        Return false  ; Still approaching or just switched — check again next cycle
    EndIf

    ; Sub-phase: sandboxing — release when player walks away
    Return Core.ShouldReleaseLinger(npc)
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
    Core.RemoveIntelPackages(npc, false)
    PO3_SKSEFunctions.SetLinkedRef(npc, player as ObjectReference, Core.IntelEngine_TravelTarget)

    ; Phase 1: Walk toward player first — sandbox kicks in at 100 units
    ActorUtil.AddPackageOverride(npc, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
    npc.EvaluatePackage()

    StorageUtil.SetIntValue(npc, "Intel_MeetingLingering", 1)
    StorageUtil.SetIntValue(npc, "Intel_MeetingLingerApproaching", 1)
    ; Waiting/sleeping ends the linger after 1 game hour.
    StorageUtil.SetFloatValue(npc, "Intel_MeetingLingerDeadline", Utility.GetCurrentGameTime() + 1.0 / 24.0)

    ; Update schedule slot to meeting_active
    If Core.Schedule
        Int schedSlot = Core.Schedule.FindScheduleSlotByAgent(npc)
        ; Only the row of this meeting: a travel row that has been dispatched. The first row found for the
        ; NPC can be a later appointment that is still pending; marked "meeting active" it was never started.
        If schedSlot >= 0 && Core.Schedule.GetScheduleTaskType(schedSlot) == "travel" && Core.Schedule.GetScheduleSlotState(schedSlot) == 1
            Core.Schedule.SetScheduleState(schedSlot, 2)
        EndIf
    EndIf
EndFunction

Function CompleteMeeting(Int slot, Actor npc, Bool playerLeft = true)
    {Meeting complete, release the NPC: the player walked away, or (playerLeft = false) the visit ran its
    time with the player still around.}
    String npcName = npc.GetDisplayName()

    ; Narrate what happened — past tense, factual only (no emotion, no future intent)
    String playerName = Game.GetPlayer().GetDisplayName()
    If playerLeft
        Core.DebugMsg(npcName + " meeting complete (player left)")
        Core.SendTaskNarration(npc, playerName + " walked away.", Game.GetPlayer())
    Else
        ; "walked away" was sent here too, with the player standing next to them.
        Core.DebugMsg(npcName + " meeting complete (visit over)")
        Core.SendTaskNarration(npc, npcName + " had stayed a while after meeting " + playerName + " and went back to their own business.", Game.GetPlayer())
    EndIf
    Core.NotifyPlayer(npcName + " headed off after the meeting")

    ; Mark as complete
    StorageUtil.SetStringValue(npc, "Intel_Result", "player_arrived")

    ; Clear the slot and restore follower status
    ; ClearSlot handles schedule cleanup (preserving future schedules)
    Core.ClearSlotRestoreFollower(slot, npc)
    ; Someone with a routine of their own goes back to it. Someone without one (many mod-added NPCs only
    ; have a sandbox package) stayed at the meeting place for good: they are walked home.
    Core.ReleaseLinger(npc)
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
    Core.RemoveIntelPackages(npc, false)
    PO3_SKSEFunctions.SetLinkedRef(npc, player as ObjectReference, Core.IntelEngine_TravelTarget)

    ; Phase 1: Walk toward player first — sandbox kicks in at LINGER_APPROACH_DISTANCE
    ActorUtil.AddPackageOverride(npc, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
    npc.EvaluatePackage()

    StorageUtil.SetIntValue(npc, "Intel_TravelLingering", 1)
    StorageUtil.SetIntValue(npc, "Intel_MeetingLingerApproaching", 1)
    ; Waiting/sleeping ends the linger after 1 game hour.
    StorageUtil.SetFloatValue(npc, "Intel_MeetingLingerDeadline", Utility.GetCurrentGameTime() + 1.0 / 24.0)
    StorageUtil.SetStringValue(npc, "Intel_Result", "arrived")
EndFunction

Function StartStayAtDestLinger(Int slot, Actor npc)
    {Gentle linger for interior semantic destinations (upstairs, bedroom, etc.).
    Keeps SandboxNearPlayerPackage — just switches linked ref to the player so
    the NPC drifts within 200 units instead of aggressively walking over.}
    Actor player = Game.GetPlayer()
    Core.DebugMsg(npc.GetDisplayName() + " starting stay-at-dest linger (sandbox only)")

    ; This used to assume the sandbox was on. An NPC who was on the way to the player (through the door, or
    ; the approach inside) carries the walk package instead: with it left on they walked into the player,
    ; radius 0, for as long as the player stayed. The sandbox goes on first, so there is no gap.
    ActorUtil.AddPackageOverride(npc, Core.SandboxNearPlayerPackage, Core.PRIORITY_SANDBOX, 1)
    ActorUtil.RemovePackageOverride(npc, Core.TravelPackage_Walk)
    ActorUtil.RemovePackageOverride(npc, Core.TravelPackage_Jog)
    ActorUtil.RemovePackageOverride(npc, Core.TravelPackage_Run)
    StorageUtil.UnsetIntValue(npc, "Intel_MeetingApproaching")
    If StorageUtil.GetIntValue(npc, "Intel_WaitForPlayer") == 1
        ; Sent here to wait for the player: drifts over to them.
        PO3_SKSEFunctions.SetLinkedRef(npc, player as ObjectReference, Core.IntelEngine_TravelTarget)
    Else
        ; Here on their own business: stays where they went ("sandbox quietly"), not at the player's side.
        ; (A sandbox around a marker that is not loaded crashes the engine, see OnArrival.)
        ObjectReference place = StorageUtil.GetFormValue(npc, "Intel_DestMarker") as ObjectReference
        If place == None || !npc.Is3DLoaded() || !place.Is3DLoaded()
            place = npc
        EndIf
        PO3_SKSEFunctions.SetLinkedRef(npc, place, Core.IntelEngine_TravelTarget)
    EndIf
    npc.EvaluatePackage()

    StorageUtil.SetIntValue(npc, "Intel_TravelLingering", 1)
    StorageUtil.SetIntValue(npc, "Intel_StayAtDest", 1)
    ; It had no clock at all: a player who waited or slept next to them kept them there.
    StorageUtil.SetFloatValue(npc, "Intel_MeetingLingerDeadline", Utility.GetCurrentGameTime() + STAY_AT_DEST_LINGER_HOURS / 24.0)
    StorageUtil.SetStringValue(npc, "Intel_Result", "arrived")
EndFunction

Function CompleteTravelLinger(Int slot, Actor npc)
    {Player walked away — travel linger complete, release the NPC.}
    String npcName = npc.GetDisplayName()
    Core.DebugMsg(npcName + " travel linger complete (player left)")
    StorageUtil.SetStringValue(npc, "Intel_Result", "arrived")
    Core.ClearSlotRestoreFollower(slot, npc)
    ; See CompleteMeeting: one with no routine of their own is walked home instead of staying for good.
    Core.ReleaseLinger(npc)
EndFunction

Bool Function IsStayAtDestination(String destination)
    {Returns true for interior semantic destinations where the NPC should
    sandbox at the location rather than approach the player.}
    String dest = IntelEngine.StringToLower(destination)
    If IntelEngine.StringContains(dest, "upstairs") || IntelEngine.StringContains(dest, "downstairs")
        Return true
    EndIf
    If IntelEngine.StringContains(dest, "bedroom") || IntelEngine.StringContains(dest, "cellar")
        Return true
    EndIf
    If IntelEngine.StringContains(dest, "basement") || IntelEngine.StringContains(dest, "attic")
        Return true
    EndIf
    Return false
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

