Scriptname IntelEngine_NPCTasks extends Quest
{
    IntelEngine NPC Task System v1.0

    Handles complex NPC-to-NPC interactions:
    - Fetch NPC: Go find someone and bring them back
    - Deliver Message: Go tell someone something
    - Search: Help find someone

    All tasks use natural travel - NPCs walk/run, no teleporting.
    Targets follow the agent back naturally using follow packages.
}

; =============================================================================
; PROPERTIES
; =============================================================================

IntelEngine_Core Property Core Auto

IntelEngine_Travel Property Travel Auto
{Reference to travel script}

; =============================================================================
; CONSTANTS
; =============================================================================

Float Property TARGET_APPROACH_DISTANCE = 200.0 AutoReadOnly
{Distance to consider agent "arrived" at target NPC}

Float Property LEAD_PAUSE_DISTANCE = 1500.0 AutoReadOnly
{If player falls behind this far, NPC pauses to wait}

Float Property LEAD_RESUME_DISTANCE = 500.0 AutoReadOnly
{If player gets within this distance, NPC auto-resumes searching}

; =============================================================================
; STUCK DETECTION CONSTANTS
; =============================================================================

Float Property STUCK_DISTANCE_THRESHOLD = 50.0 AutoReadOnly
{If NPC moved less than this between checks, might be stuck.
Passed to C++ StuckDetector.CheckStuckStatus as threshold parameter.}

Float Property MIN_TASK_HOURS = 1.0 AutoReadOnly
{Minimum deadline in game hours (even for nearby targets)}

Float Property MAX_TASK_HOURS = 6.0 AutoReadOnly
{Maximum deadline in game hours (even for cross-map targets)}

; =============================================================================
; IMMERSIVE TASK CONSTANTS
; =============================================================================

; STATE_AT_TARGET moved to Core.STATE_AT_TARGET (=8)

Int Property INTERACT_CYCLES = 2 AutoReadOnly
{Update cycles to "converse" at target (~6s)}

Int Property DEPARTURE_CHECK_CYCLES = 5 AutoReadOnly
{Update cycles before checking if NPC actually departed (~15s at 3s interval).
If NPC hasn't moved from their starting position: teleport if player not
looking, or narrate failure if player is watching.}

Int Property MAX_TARGET_WAIT_CYCLES = 15 AutoReadOnly
{Max cycles to wait for the fetched target to walk to the player (~45s).
Progress-tracked: if target is getting closer, the counter resets.}

; STATE_TARGET_PRESENTING (9) and MAX_PRESENT_CYCLES removed.
; Target-first completion in CheckReturnArrival makes intermediate states unnecessary.

Float Property LINGER_PROXIMITY = 800.0 AutoReadOnly
{Phase 2: distance within which the player is considered "nearby".
When the player moves beyond this, the NPC is released.}

Float Property LINGER_APPROACH_DISTANCE = 100.0 AutoReadOnly
{NPC switches from approach (TravelPackage_Walk) to sandbox when within this distance of player}

Int Property LINGER_FAR_TICKS_LIMIT = 3 AutoReadOnly
{Consecutive far checks before the lingering NPC is released}

Float Property RETURN_POLL_INTERVAL = 0.5 AutoReadOnly
{Fast update interval when NPCs are in state 3 (returning). Catches arrival
within ~50 units of drift instead of ~300 at the normal 3s interval.}

Int Property MAX_LINGER_SLOTS = 5 AutoReadOnly
{Maximum concurrent lingering targets — matches MAX_SLOTS.}

; =============================================================================
; INITIALIZATION
; =============================================================================

Function EnsureMonitoringAlive()
    {Lightweight heartbeat: if active NPC tasks exist, re-register the update loop.
    Called by Schedule's game-time loop as a safety net against Papyrus VM stack dumps.}
    Int i = 0
    While i < Core.MAX_SLOTS
        String taskType = Core.SlotTaskTypes[i]
        If Core.SlotStates[i] != 0 && (taskType == "fetch_npc" || taskType == "deliver_message" || taskType == "search_for_actor")
            RegisterForSingleUpdate(Core.UPDATE_INTERVAL)
            Return
        EndIf
        i += 1
    EndWhile
EndFunction

Function RestartMonitoring()
    {Restart the update loop after game load. Called by Core.Maintenance().
    RegisterForSingleUpdate is per-script and doesn't survive save/load.
    Without this, tasks loaded from a save would never be monitored.
    Also re-applies AI packages which are runtime-only and don't persist.}
    Bool hasActive = false
    Int i = 0
    While i < Core.MAX_SLOTS
        String taskType = Core.SlotTaskTypes[i]
        If Core.SlotStates[i] != 0 && (taskType == "fetch_npc" || taskType == "deliver_message" || taskType == "search_for_actor")
            hasActive = true
            RecoverSlotPackages(i)
        EndIf
        i += 1
    EndWhile
    If hasActive
        RegisterForSingleUpdate(Core.UPDATE_INTERVAL)
        Core.DebugMsg("NPCTasks monitoring restarted")
    EndIf
EndFunction

Function RecoverSlotPackages(Int slot)
    {Re-apply AI packages after save/load. Runtime package overrides and
    linked references don't survive save/load — without this, agents
    would stand idle until stuck detection teleports them.}
    ReferenceAlias slotAlias = Core.GetAgentAlias(slot)
    If slotAlias == None
        Return
    EndIf
    Actor agent = slotAlias.GetActorReference()
    If agent == None || agent.IsDead()
        Return
    EndIf

    Int taskState = Core.SlotStates[slot]
    String taskType = Core.SlotTaskTypes[slot]
    Int speed = Core.SlotSpeeds[slot]
    Package travelPkg = Core.GetTravelPackage(speed)

    If taskState == 1
        ; Traveling to target — re-apply travel package
        ObjectReference dest = StorageUtil.GetFormValue(agent, "Intel_DestMarker") as ObjectReference
        If dest != None
            PO3_SKSEFunctions.SetLinkedRef(agent, dest, Core.IntelEngine_TravelTarget)
            ActorUtil.AddPackageOverride(agent, travelPkg, Core.PRIORITY_TRAVEL, 1)
            agent.EvaluatePackage()
            Core.DebugMsg("Recovered travel package for " + agent.GetDisplayName() + " (outbound)")
        EndIf

    ElseIf taskState == 3
        ; Returning — travel to player
        ObjectReference returnMarker = StorageUtil.GetFormValue(agent, "Intel_ReturnMarker") as ObjectReference
        If returnMarker == None
            returnMarker = Game.GetPlayer()
        EndIf
        PO3_SKSEFunctions.SetLinkedRef(agent, returnMarker, Core.IntelEngine_TravelTarget)
        ActorUtil.AddPackageOverride(agent, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
        agent.EvaluatePackage()

        ; Also recover target's travel package for fetch returns
        If taskType == "fetch_npc"
            Actor target = StorageUtil.GetFormValue(agent, "Intel_TargetNPC") as Actor
            String result = StorageUtil.GetStringValue(agent, "Intel_Result")
            If target != None && !target.IsDead() && result != "refused"
                PO3_SKSEFunctions.SetLinkedRef(target, returnMarker, Core.IntelEngine_TravelTarget)
                ActorUtil.AddPackageOverride(target, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
                target.EvaluatePackage()
            EndIf
        EndIf
        Core.DebugMsg("Recovered return package for " + agent.GetDisplayName())

    ElseIf taskState == 5 && taskType == "search_for_actor"
        ; Waiting for player to catch up — re-apply sandbox so agent stays put
        ActorUtil.AddPackageOverride(agent, Core.SandboxNearPlayerPackage, Core.PRIORITY_SANDBOX, 1)
        agent.EvaluatePackage()
        Core.DebugMsg("Recovered sandbox package for " + agent.GetDisplayName() + " (search wait)")
    EndIf

    ; Re-initialize stuck tracking so detection starts fresh
    Core.InitializeStuckTrackingForSlot(slot, agent)
EndFunction

; InitializeStuckTrackingForSlot moved to Core

; =============================================================================
; TARGET LINGERING — PROXIMITY-BASED
; After fetch completion the target lingers near the player using a tight
; sandbox (SandboxNearPlayerPackage, 200-unit radius). The NPC idles, sits,
; or uses furniture near the player without walking into their face.
; Released when the player leaves LINGER_PROXIMITY.
;
; Uses StorageUtil instead of script-level arrays to avoid save-compatibility
; issues when script variables change between builds. Linger state stored on
; each target actor; list of lingering targets stored on the quest form.
; =============================================================================

Function StartTargetLinger(Actor target, Actor agent)
    {Start lingering near the player. Phase 1: walk toward player using
    TravelPackage_Walk. Phase 2: sandbox within 200 units once close (100 units).
    Released when the player leaves LINGER_PROXIMITY (800 units).}

    ; Dedup — don't add the same target twice
    If StorageUtil.GetIntValue(target, "Intel_LingerPhase", 0) > 0
        Core.DebugMsg(target.GetDisplayName() + " already lingering, skipping")
        Return
    EndIf

    Actor player = Game.GetPlayer()

    ; Remove IntelEngine packages only — preserve SkyrimNet/other packages
    Core.RemoveIntelPackages(target, false)

    ; Phase 1: Walk toward the player
    PO3_SKSEFunctions.SetLinkedRef(target, player as ObjectReference, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(target, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
    Utility.Wait(0.1)
    target.EvaluatePackage()

    ; Store linger state — phase 1 = approaching player
    StorageUtil.SetIntValue(target, "Intel_LingerPhase", 1)
    StorageUtil.SetFormValue(target, "Intel_LingerAgent", agent)
    StorageUtil.FormListAdd(self, "Intel_LingeringTargets", target, false)

    Core.DebugMsg(target.GetDisplayName() + " approaching player (linger phase 1)")
    RegisterForSingleUpdate(Core.UPDATE_INTERVAL)
EndFunction

Function ClearLingerSlot(Actor target)
    {Remove all linger state from a target actor and remove from the list.}
    StorageUtil.UnsetIntValue(target, "Intel_LingerPhase")
    StorageUtil.UnsetFormValue(target, "Intel_LingerAgent")
    StorageUtil.UnsetIntValue(target, "Intel_LingerFarTicks")
    StorageUtil.FormListRemove(self, "Intel_LingeringTargets", target, true)
EndFunction

Function CheckLingeringTargets()
    {Check lingering targets. Phase 1: NPC walks toward player — switch to
    sandbox at 100 units. Phase 2: sandbox near player — release when player
    walks 800 units away.}
    Actor player = Game.GetPlayer()
    Int i = StorageUtil.FormListCount(self, "Intel_LingeringTargets") - 1
    While i >= 0
        Actor target = StorageUtil.FormListGet(self, "Intel_LingeringTargets", i) as Actor
        If target == None || target.IsDead() || target.IsDisabled()
            ; Invalid entry — clean up
            If target != None
                Core.DebugMsg(target.GetDisplayName() + " linger target invalid, clearing")
                Core.RemoveIntelPackages(target)
                ClearLingerSlot(target)
            Else
                StorageUtil.FormListRemoveAt(self, "Intel_LingeringTargets", i)
            EndIf
        Else
            Actor agent = StorageUtil.GetFormValue(target, "Intel_LingerAgent") as Actor
            Int phase = StorageUtil.GetIntValue(target, "Intel_LingerPhase", 0)

            If phase == 1
                ; Phase 1: NPC walking toward player.
                ; Switch to sandbox when within 100 units.
                Bool closeEnough = false
                Bool stillFar = true
                If target.Is3DLoaded() && player.Is3DLoaded()
                    Float targetDist = target.GetDistance(player)
                    closeEnough = targetDist <= LINGER_APPROACH_DISTANCE
                    stillFar = targetDist > LINGER_PROXIMITY
                ElseIf target.GetParentCell() == player.GetParentCell()
                    ; Same cell off-screen — close enough in interiors
                    Cell targetCell = target.GetParentCell()
                    stillFar = false
                    If targetCell != None && targetCell.IsInterior()
                        closeEnough = true
                    EndIf
                EndIf

                If closeEnough
                    ; Add sandbox BEFORE removing travel — no gap for default AI to kick in
                    PO3_SKSEFunctions.SetLinkedRef(target, player as ObjectReference, Core.IntelEngine_TravelTarget)
                    ActorUtil.AddPackageOverride(target, Core.SandboxNearPlayerPackage, Core.PRIORITY_TRAVEL, 1)
                    ActorUtil.RemovePackageOverride(target, Core.TravelPackage_Walk)
                    Utility.Wait(0.1)
                    target.EvaluatePackage()
                    StorageUtil.SetIntValue(target, "Intel_LingerPhase", 2)
                    Core.DebugMsg(target.GetDisplayName() + " reached player, sandboxing (phase 2)")
                ElseIf stillFar
                    ; Player still far during approach — keep incrementing far ticks
                    Int farTicks = StorageUtil.GetIntValue(target, "Intel_LingerFarTicks", 0) + 1
                    StorageUtil.SetIntValue(target, "Intel_LingerFarTicks", farTicks)
                    If farTicks >= LINGER_FAR_TICKS_LIMIT
                        ActorUtil.RemovePackageOverride(target, Core.TravelPackage_Walk)
                        Utility.Wait(0.1)
                        target.EvaluatePackage()
                        Core.SendTransientEvent(target, agent, target.GetDisplayName() + " is heading back.")
                        Core.DebugMsg(target.GetDisplayName() + " player left during approach, heading home")
                        ClearLingerSlot(target)
                    EndIf
                EndIf

            ElseIf phase == 2
                ; Phase 2: NPC sandboxing near player.
                ; Release when player leaves proximity.
                Float dist = LINGER_PROXIMITY + 1.0
                If target.Is3DLoaded() && player.Is3DLoaded() && target.GetParentCell() == player.GetParentCell()
                    dist = target.GetDistance(player)
                EndIf

                If dist > LINGER_PROXIMITY
                    ; Grace period with re-approach — NPC may have drifted from sandbox
                    Int farTicks = StorageUtil.GetIntValue(target, "Intel_LingerFarTicks", 0) + 1
                    StorageUtil.SetIntValue(target, "Intel_LingerFarTicks", farTicks)
                    If farTicks >= LINGER_FAR_TICKS_LIMIT
                        ; Player genuinely left — release
                        ActorUtil.RemovePackageOverride(target, Core.SandboxNearPlayerPackage)
                        ActorUtil.RemovePackageOverride(target, Core.TravelPackage_Walk)
                        Utility.Wait(0.1)
                        target.EvaluatePackage()

                        Core.SendTransientEvent(target, agent, target.GetDisplayName() + " is heading back.")
                        Core.DebugMsg(target.GetDisplayName() + " player left proximity, heading home")
                        ClearLingerSlot(target)
                    Else
                        ; NPC drifted — switch back to approach to walk back
                        Core.DebugMsg(target.GetDisplayName() + " linger: drifted (tick " + farTicks + "), re-approaching player")
                        PO3_SKSEFunctions.SetLinkedRef(target, player as ObjectReference, Core.IntelEngine_TravelTarget)
                        ActorUtil.AddPackageOverride(target, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
                        ActorUtil.RemovePackageOverride(target, Core.SandboxNearPlayerPackage)
                        Utility.Wait(0.1)
                        target.EvaluatePackage()
                        StorageUtil.SetIntValue(target, "Intel_LingerPhase", 1)
                    EndIf
                Else
                    ; Player nearby — reset far counter
                    StorageUtil.UnsetIntValue(target, "Intel_LingerFarTicks")
                EndIf
            EndIf
        EndIf
        i -= 1
    EndWhile
EndFunction

Bool Function HasLingeringTargets()
    Return StorageUtil.FormListCount(self, "Intel_LingeringTargets") > 0
EndFunction

; =============================================================================
; FETCH NPC API
; =============================================================================

Bool Function FetchNPC(Actor akAgent, String targetName, String failReason = "none")
    {
    Send an NPC to find another NPC and bring them back to the player.

    Parameters:
        akAgent - The NPC doing the fetching
        targetName - Name of NPC to fetch (fuzzy matched)
        failReason - "none" if target comes willingly, otherwise the refusal reason

    Returns:
        true if fetch task started successfully
    }

    ; Validate agent
    If akAgent == None
        Core.DebugMsg("FetchNPC: None agent")
        Return false
    EndIf

    If akAgent.IsDead() || akAgent.IsInCombat()
        Core.DebugMsg("FetchNPC: Agent dead or in combat")
        Return false
    EndIf

    ; Duplicate action guard
    If Core.IsDuplicateTask(akAgent, "fetch_npc", targetName)
        Return false
    EndIf

    ; MCM task confirmation prompt
    Int confirmResult = Core.ShowTaskConfirmation(akAgent, akAgent.GetDisplayName() + " wants to go fetch " + targetName + ".")
    If confirmResult == 1
        Core.SendTaskNarration(akAgent, Game.GetPlayer().GetDisplayName() + " told " + akAgent.GetDisplayName() + " not to go fetch " + targetName + ".")
        Return false
    ElseIf confirmResult == 2
        Return false
    EndIf

    ; Override existing task if any
    Core.OverrideExistingTask(akAgent)

    ; Cooldown — prevents narration-triggered re-selection loops.
    ; After a fetch completes, the completion narration can trigger a dialogue
    ; evaluation that re-selects FetchPerson before the NPC has time to rest.
    Float cooldown = StorageUtil.GetFloatValue(akAgent, "Intel_TaskCooldown")
    If cooldown > 0.0 && (Utility.GetCurrentRealTime() - cooldown) < 15.0
        Core.DebugMsg("FetchNPC: " + akAgent.GetDisplayName() + " on cooldown")
        Return false
    EndIf

    ; Find the target NPC using DLL fuzzy search
    Actor targetNPC = IntelEngine.FindNPCByName(targetName)
    If targetNPC == None
        ; NPC not found - describe the situation, let NPC decide their response
        String suggestion = GetNPCSuggestion(targetName)
        If suggestion != ""
            Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " was asked to find '" + targetName + "'. No one by that exact name could be located. The closest known name is " + suggestion + ".")
        Else
            Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " was asked to find someone named '" + targetName + "'. No one by that name could be located.")
        EndIf
        Return false
    EndIf

    ; Check if target is valid
    If targetNPC.IsDead()
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " was asked to find " + targetNPC.GetDisplayName() + ", who is dead.")
        Return false
    EndIf

    If targetNPC.IsDisabled()
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " could not find " + targetNPC.GetDisplayName() + ".")
        Return false
    EndIf

    If targetNPC == akAgent
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " was asked to fetch themselves.")
        Return false
    EndIf

    If targetNPC == Game.GetPlayer()
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " was asked to fetch " + Game.GetPlayer().GetDisplayName() + ", who is already right here.")
        Return false
    EndIf

    ; Cancel any existing task the target is involved in (as agent or target)
    Int existingSlot = Core.FindSlotByActor(targetNPC)
    If existingSlot >= 0
        Core.DebugMsg("FetchNPC: " + targetNPC.GetDisplayName() + " is in active slot " + existingSlot + " — cancelling")
        Core.ClearSlot(existingSlot, true)
    EndIf

    ; Also cancel any pending schedule for the target
    If Core.Schedule
        Int schedSlot = Core.Schedule.FindScheduleSlotByAgent(targetNPC)
        If schedSlot >= 0
            Core.DebugMsg("FetchNPC: " + targetNPC.GetDisplayName() + " has scheduled task — cancelling")
            Core.Schedule.ClearScheduleSlot(schedSlot)
        EndIf
    EndIf

    ; Find free slot
    Int slot = Core.FindFreeAgentSlot()
    If slot < 0
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " cannot take on this task right now.")
        Return false
    EndIf

    ; Destination is always the target actor directly
    ObjectReference destMarker = targetNPC

    ; Stop following if agent is follower
    Core.DismissFollowerForTask(akAgent)

    ; Allocate slot (defaults to state 1)
    Core.AllocateSlot(slot, akAgent, "fetch_npc", targetNPC.GetDisplayName(), 1)  ; Jog by default

    ; Store fetch-specific data
    StorageUtil.SetFormValue(akAgent, "Intel_TargetNPC", targetNPC)
    StorageUtil.SetFormValue(akAgent, "Intel_DestMarker", destMarker)
    ; Derive shouldFail from failReason (merged parameter)
    Int shouldFail = 0
    If failReason != "none" && failReason != ""
        shouldFail = 1
    EndIf
    StorageUtil.SetIntValue(akAgent, "Intel_ShouldFail", shouldFail)
    If shouldFail == 1
        StorageUtil.SetStringValue(akAgent, "Intel_FailReason", failReason)
    EndIf

    ; Assign target to target alias
    ReferenceAlias targetAlias = Core.GetTargetAlias(slot)
    If targetAlias
        targetAlias.ForceRefTo(targetNPC)
    EndIf

    ; Set up travel — agent pathfinds toward the target naturally.
    ; Works same-cell (player sees them walk) and cross-cell (engine AI handles it).
    ; Teleport is only a last-resort fallback via stuck recovery / game-time timeout.
    PO3_SKSEFunctions.SetLinkedRef(akAgent, destMarker, Core.IntelEngine_TravelTarget)
    ; Walk when player can see them, jog when off-screen
    Bool sameCell = (akAgent.GetParentCell() == Game.GetPlayer().GetParentCell())
    If sameCell
        ActorUtil.AddPackageOverride(akAgent, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
    Else
        ActorUtil.AddPackageOverride(akAgent, Core.TravelPackage_Jog, Core.PRIORITY_TRAVEL, 1)
    EndIf
    Utility.Wait(0.1)
    akAgent.EvaluatePackage()

    Core.DebugMsg("FetchNPC: Pathfinding to " + targetNPC.GetDisplayName())
    Core.NotifyPlayer(akAgent.GetDisplayName() + " went to find " + targetNPC.GetDisplayName())

    ; Initialize stuck tracking + departure detection + off-screen tracking
    Core.InitializeStuckTrackingForSlot(slot, akAgent)
    Core.InitializeDepartureTracking(slot, akAgent)
    Core.InitOffScreenTracking(slot, akAgent, targetNPC)

    ; Set distance-based deadline (round trip: go to target + return to player)
    SetDistanceBasedDeadline(slot, akAgent, targetNPC, true)

    ; Start monitoring
    RegisterForSingleUpdate(Core.UPDATE_INTERVAL)

    Return true
EndFunction

; =============================================================================
; DELIVER MESSAGE API
; =============================================================================

Bool Function DeliverMessage(Actor akAgent, String targetName, String msgContent, String meetLocation = "none", String meetTime = "none")
    {
    Send an NPC to deliver a message to another NPC.
    If meetLocation and meetTime are provided, the recipient will be
    scheduled to travel to that location at that time after receiving the message.

    Parameters:
        akAgent - The messenger
        targetName - Who to deliver message to (fuzzy matched)
        msgContent - The message to deliver
        meetLocation - Where the recipient should go (or "none")
        meetTime - When the recipient should go (or "none")

    Returns:
        true if delivery task started
    }

    ; Validate
    If akAgent == None || akAgent.IsDead()
        Return false
    EndIf

    If msgContent == ""
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " was asked to deliver a message but no message was provided.")
        Return false
    EndIf

    ; Duplicate action guard
    If Core.IsDuplicateTask(akAgent, "deliver_message", targetName)
        Return false
    EndIf

    ; MCM task confirmation prompt
    Int confirmResult = Core.ShowTaskConfirmation(akAgent, akAgent.GetDisplayName() + " wants to deliver a message to " + targetName + ".")
    If confirmResult == 1
        Core.SendTaskNarration(akAgent, Game.GetPlayer().GetDisplayName() + " told " + akAgent.GetDisplayName() + " not to deliver the message.")
        Return false
    ElseIf confirmResult == 2
        Return false
    EndIf

    ; Override existing task if any
    Core.OverrideExistingTask(akAgent)

    ; Cooldown — prevents narration-triggered re-selection loops
    Float cooldown = StorageUtil.GetFloatValue(akAgent, "Intel_TaskCooldown")
    If cooldown > 0.0 && (Utility.GetCurrentRealTime() - cooldown) < 15.0
        Core.DebugMsg("DeliverMessage: " + akAgent.GetDisplayName() + " on cooldown")
        Return false
    EndIf

    ; Find target
    Actor targetNPC = IntelEngine.FindNPCByName(targetName)
    If targetNPC == None
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " was asked to deliver a message to '" + targetName + "'. No one by that name could be located.")
        Return false
    EndIf

    If targetNPC.IsDead()
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " was asked to deliver a message to " + targetNPC.GetDisplayName() + ", who is dead.")
        Return false
    EndIf

    If targetNPC.IsDisabled()
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " could not find " + targetNPC.GetDisplayName() + " to deliver the message.")
        Return false
    EndIf

    ; Find slot
    Int slot = Core.FindFreeAgentSlot()
    If slot < 0
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " cannot take on this task right now.")
        Return false
    EndIf

    ; Destination is always the target actor directly.
    ; Skyrim's AI pathfinding handles cross-cell Actor targets natively.
    ObjectReference destMarker = targetNPC

    ; Stop following
    Core.DismissFollowerForTask(akAgent)

    ; Allocate
    Core.AllocateSlot(slot, akAgent, "deliver_message", targetNPC.GetDisplayName(), 1)

    ; Store message data
    StorageUtil.SetFormValue(akAgent, "Intel_TargetNPC", targetNPC)
    StorageUtil.SetFormValue(akAgent, "Intel_DestMarker", destMarker)
    StorageUtil.SetStringValue(akAgent, "Intel_Message", msgContent)

    ; Store meeting request data (if the message asks target to meet somewhere)
    StorageUtil.SetStringValue(akAgent, "Intel_DeliveryMeetLocation", meetLocation)
    StorageUtil.SetStringValue(akAgent, "Intel_DeliveryMeetTime", meetTime)

    ; Assign target alias
    ReferenceAlias targetAlias = Core.GetTargetAlias(slot)
    If targetAlias
        targetAlias.ForceRefTo(targetNPC)
    EndIf

    ; Set up travel — agent pathfinds toward the target naturally.
    PO3_SKSEFunctions.SetLinkedRef(akAgent, destMarker, Core.IntelEngine_TravelTarget)
    ; Walk when player can see them, jog when off-screen
    Bool sameCell = (akAgent.GetParentCell() == Game.GetPlayer().GetParentCell())
    If sameCell
        ActorUtil.AddPackageOverride(akAgent, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
    Else
        ActorUtil.AddPackageOverride(akAgent, Core.TravelPackage_Jog, Core.PRIORITY_TRAVEL, 1)
    EndIf
    Utility.Wait(0.1)
    akAgent.EvaluatePackage()

    Core.DebugMsg("DeliverMessage: Pathfinding to " + targetNPC.GetDisplayName())
    Core.NotifyPlayer(akAgent.GetDisplayName() + " went to deliver a message to " + targetNPC.GetDisplayName())

    ; Initialize stuck tracking + departure detection + off-screen tracking
    Core.InitializeStuckTrackingForSlot(slot, akAgent)
    Core.InitializeDepartureTracking(slot, akAgent)
    Core.InitOffScreenTracking(slot, akAgent, targetNPC)

    ; Set distance-based deadline. Round trip if report-back is enabled, one-way otherwise.
    Bool isRoundTrip = StorageUtil.GetIntValue(Game.GetPlayer(), "Intel_DeliveryReportBack") == 1
    SetDistanceBasedDeadline(slot, akAgent, targetNPC, isRoundTrip)

    RegisterForSingleUpdate(Core.UPDATE_INTERVAL)

    Return true
EndFunction

; =============================================================================
; SEARCH FOR ACTOR API
; =============================================================================

Bool Function SearchForActor(Actor akAgent, String targetName, Int speed = 0)
    {
    Search for a target NPC together.

    The agent walks toward the target NPC. If someone following falls behind,
    the agent pauses and waits. On arrival, task completes.

    Parameters:
        akAgent - The NPC helping search
        targetName - Name of NPC to search for (fuzzy matched)
        speed - Travel speed: 0=walk, 1=jog, 2=run

    Returns:
        true if search task started successfully
    }

    ; Validate agent
    If akAgent == None
        Core.DebugMsg("SearchForActor: None agent")
        Return false
    EndIf

    If akAgent.IsDead() || akAgent.IsInCombat()
        Core.DebugMsg("SearchForActor: Agent dead or in combat")
        Return false
    EndIf

    ; Duplicate action guard
    If Core.IsDuplicateTask(akAgent, "search_for_actor", targetName)
        Return false
    EndIf

    ; MCM task confirmation prompt
    Int confirmResult = Core.ShowTaskConfirmation(akAgent, akAgent.GetDisplayName() + " wants to help search for " + targetName + ".")
    If confirmResult == 1
        Core.SendTaskNarration(akAgent, Game.GetPlayer().GetDisplayName() + " told " + akAgent.GetDisplayName() + " not to search for " + targetName + ".")
        Return false
    ElseIf confirmResult == 2
        Return false
    EndIf

    ; Override existing task if any
    Core.OverrideExistingTask(akAgent)

    ; Find the target NPC
    Actor targetNPC = IntelEngine.FindNPCByName(targetName)
    If targetNPC == None
        String suggestion = GetNPCSuggestion(targetName)
        If suggestion != ""
            Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " was asked to help find '" + targetName + "'. No one by that exact name could be located. The closest known name is " + suggestion + ".")
        Else
            Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " was asked to help find someone named '" + targetName + "'. No one by that name could be located.")
        EndIf
        Return false
    EndIf

    If targetNPC.IsDead()
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " was asked to help find " + targetNPC.GetDisplayName() + ", who is dead.")
        Return false
    EndIf

    If targetNPC == akAgent
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " was asked to help find themselves.")
        Return false
    EndIf

    ; Find free slot
    Int slot = Core.FindFreeAgentSlot()
    If slot < 0
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " cannot take on this task right now.")
        Return false
    EndIf

    ; Destination is always the target actor directly.
    ; Skyrim's AI pathfinding handles cross-cell Actor targets natively.
    ObjectReference destMarker = targetNPC

    ; Stop following if agent is follower
    Core.DismissFollowerForTask(akAgent)

    ; Allocate slot
    Core.AllocateSlot(slot, akAgent, "search_for_actor", targetNPC.GetDisplayName(), speed)

    ; Store search-specific data
    StorageUtil.SetFormValue(akAgent, "Intel_TargetNPC", targetNPC)
    StorageUtil.SetFormValue(akAgent, "Intel_DestMarker", destMarker)

    ; Assign target alias
    ReferenceAlias targetAlias = Core.GetTargetAlias(slot)
    If targetAlias
        targetAlias.ForceRefTo(targetNPC)
    EndIf

    ; Set up travel
    PO3_SKSEFunctions.SetLinkedRef(akAgent, destMarker, Core.IntelEngine_TravelTarget)
    Package travelPkg = Core.GetTravelPackage(speed)
    ActorUtil.AddPackageOverride(akAgent, travelPkg, Core.PRIORITY_TRAVEL, 1)
    Utility.Wait(0.1)
    akAgent.EvaluatePackage()

    Core.NotifyPlayer(akAgent.GetDisplayName() + " is going to search for " + targetNPC.GetDisplayName())

    ; Initialize stuck tracking + departure detection + off-screen tracking
    Core.InitializeStuckTrackingForSlot(slot, akAgent)
    Core.InitializeDepartureTracking(slot, akAgent)
    Core.InitOffScreenTracking(slot, akAgent, targetNPC)

    ; Start monitoring
    RegisterForSingleUpdate(Core.UPDATE_INTERVAL)

    Return true
EndFunction

; =============================================================================
; UPDATE LOOP
; =============================================================================

Event OnUpdate()
    ; Register FIRST so the loop survives even if processing errors out.
    ; An extra tick after all tasks complete is harmless (finds nothing, stops).
    Bool hasActiveTasks = false
    Bool hasReturning = false
    Int i = 0
    While i < Core.MAX_SLOTS
        String taskType = Core.SlotTaskTypes[i]
        If Core.SlotStates[i] != 0 && (taskType == "fetch_npc" || taskType == "deliver_message" || taskType == "search_for_actor")
            hasActiveTasks = true
            If Core.SlotStates[i] == 3
                hasReturning = true
            EndIf
        EndIf
        i += 1
    EndWhile

    Bool hasLingering = HasLingeringTargets()

    If hasActiveTasks || hasLingering
        ; Fast poll when NPCs are returning — catches arrival within ~50 units
        ; of drift instead of ~300 at normal 3s interval.
        If hasReturning
            RegisterForSingleUpdate(RETURN_POLL_INTERVAL)
        Else
            RegisterForSingleUpdate(Core.UPDATE_INTERVAL)
        EndIf
    EndIf

    ; Now process slots — if this errors out, the next update is already scheduled
    i = 0
    While i < Core.MAX_SLOTS
        String taskType = Core.SlotTaskTypes[i]
        If Core.SlotStates[i] != 0 && (taskType == "fetch_npc" || taskType == "deliver_message" || taskType == "search_for_actor")
            CheckNPCTaskSlot(i)
        EndIf
        i += 1
    EndWhile

    ; Check if any lingering targets should head home
    CheckLingeringTargets()
EndEvent

Function CheckNPCTaskSlot(Int slot)
    ReferenceAlias agentAlias = Core.GetAgentAlias(slot)
    If agentAlias == None
        Core.ClearSlot(slot)
        Return
    EndIf

    Actor agent = agentAlias.GetActorReference()
    If agent == None || agent.IsDead()
        Core.ClearSlot(slot)
        Return
    EndIf

    String taskType = Core.SlotTaskTypes[slot]
    Int taskState = Core.SlotStates[slot]

    ; Game-time timeout — distance-based deadline set at task start.
    ; Catches off-screen stuck NPCs that position-based detection can't reach.
    If taskType != "search_for_actor"
        Float deadline = Core.SlotDeadlines[slot]
        If deadline > 0.0 && Utility.GetCurrentGameTime() > deadline
            Float startTime = StorageUtil.GetFloatValue(agent, "Intel_TaskStartTime")
            Float elapsedHours = (Utility.GetCurrentGameTime() - startTime) * 24.0
            Core.DebugMsg("Task deadline reached (" + elapsedHours + "h) for " + agent.GetDisplayName() + " — force-completing")
            HandleTaskTimeout(slot, agent, taskType, taskState)
            Return
        EndIf
    EndIf

    If taskType == "fetch_npc"
        HandleFetchState(slot, agent, taskState)
    ElseIf taskType == "deliver_message"
        HandleMessageState(slot, agent, taskState)
    ElseIf taskType == "search_for_actor"
        HandleSearchState(slot, agent, taskState)
    EndIf
EndFunction

Function HandleTaskTimeout(Int slot, Actor agent, String taskType, Int taskState)
    {Force-complete a task that exceeded MAX_TASK_HOURS.
    If off-screen: teleport silently.
    If visible: narrate failure and cancel — player has been watching too long.}

    Core.DebugMsg("Task timeout for " + agent.GetDisplayName() + " (" + taskType + " state " + taskState + ")")

    ; Clear deadline — it has served its purpose. Prevents re-triggering
    ; on the next tick if the handler transitions to a non-terminal state
    ; (e.g. OnArrivedAtTarget → state 8 interaction cycles).
    Core.SetSlotDeadline(slot, 0.0)

    ; Get destination and target based on task type + state
    ObjectReference dest
    Actor target = StorageUtil.GetFormValue(agent, "Intel_TargetNPC") as Actor

    If taskType == "fetch_npc" && taskState == 3
        dest = StorageUtil.GetFormValue(agent, "Intel_ReturnMarker") as ObjectReference
    Else
        dest = StorageUtil.GetFormValue(agent, "Intel_DestMarker") as ObjectReference
    EndIf

    ; If the player can see the agent, don't teleport — narrate and cancel.
    ; The player has been watching the NPC fail for too long.
    If agent.Is3DLoaded()
        Core.DebugMsg(agent.GetDisplayName() + " timed out while visible — narrating cancel")
        Actor player = Game.GetPlayer()
        Core.SendTaskNarration(agent, agent.GetDisplayName() + " tried to carry out the task but couldn't get going and gave up.", player)
        Core.RemoveAllPackages(agent)
        Core.ClearSlot(slot, true)
        Return
    EndIf

    ; Off-screen — teleport silently to destination
    Bool isReturning = (taskState == 3 && (taskType == "fetch_npc" || taskType == "deliver_message"))
    If isReturning
        Core.TeleportBehindPlayer(agent)
    ElseIf dest != None
        agent.MoveTo(dest)
    ElseIf target != None
        agent.MoveTo(target)
    EndIf

    ; Trigger the appropriate completion handler
    If taskType == "fetch_npc"
        If target == None || target.IsDead()
            Core.ClearSlot(slot, true)
            Return
        EndIf
        If taskState == 1 || taskState == Core.STATE_AT_TARGET
            ; Outbound states — treat as arrived at target
            OnArrivedAtTarget(slot, agent, target)
        ElseIf taskState == 3
            OnReturnedWithTarget(slot, agent, target)
        Else
            Core.ClearSlot(slot, true)
        EndIf
    ElseIf taskType == "deliver_message"
        If target == None || target.IsDead()
            Core.ClearSlot(slot, true)
            Return
        EndIf
        If taskState == 1
            ; Still traveling to target — force arrival
            OnArrivedAtTarget(slot, agent, target)
        ElseIf taskState == 3
            ; Returning to player — force complete
            OnReturnedFromDelivery(slot, agent)
        Else
            ; At target (state 8) — deliver then return
            OnArrivedToDeliver(slot, agent, target)
        EndIf
    Else
        Core.ClearSlot(slot, true)
    EndIf

    ; If the handler transitioned to a non-terminal state (e.g. state 1 → 8
    ; or state 1 → 3), set a new deadline for the remaining work. The original
    ; deadline was cleared above to prevent re-triggering during interaction
    ; cycles, but the return trip still needs a safety net.
    If Core.SlotStates[slot] != 0 && Core.SlotDeadlines[slot] == 0.0
        Float returnDeadline = Utility.GetCurrentGameTime() + (MAX_TASK_HOURS / 2.0 / 24.0)
        Core.SetSlotDeadline(slot, returnDeadline)
        Core.DebugMsg("Set return deadline for " + agent.GetDisplayName() + " (" + (MAX_TASK_HOURS / 2.0) + "h)")
    EndIf
EndFunction

; =============================================================================
; FETCH NPC STATE MACHINE
; =============================================================================

Function HandleFetchState(Int slot, Actor agent, Int taskState)
    Actor target = StorageUtil.GetFormValue(agent, "Intel_TargetNPC") as Actor

    If target == None || target.IsDead()
        Core.NotifyPlayer(agent.GetDisplayName() + " could not find their target")
        Core.ClearSlot(slot, true)
        Return
    EndIf

    If taskState == 1
        ; Traveling to target — natural pathfinding (same-cell and cross-cell)
        If CheckDeparture(slot, agent)
            Return
        EndIf
        CheckArrivalAtTarget(slot, agent, target)

    ElseIf taskState == Core.STATE_AT_TARGET
        ; At target — conversing before returning
        HandleAtTarget(slot, agent, target)

    ElseIf taskState == 3
        ; Returning with target (or alone after failure)
        CheckReturnArrival(slot, agent, target)

    ElseIf taskState == 9
        ; Legacy: STATE_TARGET_PRESENTING removed. Complete immediately
        ; in case a save was made during this state.
        OnReturnedWithTarget(slot, agent, target)
    EndIf
EndFunction

Function CheckArrivalAtTarget(Int slot, Actor agent, Actor target)
    ; Check if agent reached an intermediate waypoint (Layer B redirect)
    ObjectReference agentDest = StorageUtil.GetFormValue(agent, "Intel_DestMarker") as ObjectReference
    If agentDest != None && Core.CheckWaypointArrival(slot, agent, agentDest)
        Return
    EndIf

    If agent.Is3DLoaded() && target.Is3DLoaded()
        ; Both loaded — use precise distance check
        Float dist = agent.GetDistance(target)
        If dist <= TARGET_APPROACH_DISTANCE
            OnArrivedAtTarget(slot, agent, target)
        Else
            CheckIfStuck(slot, agent)
        EndIf
        Return
    EndIf

    ; Agent on-screen but target off-screen — stuck detection only
    If agent.Is3DLoaded()
        CheckIfStuck(slot, agent)
        Return
    EndIf

    ; Off-screen: same cell means the agent pathfound to the target naturally
    Cell agentCell = agent.GetParentCell()
    If agentCell != None && agentCell == target.GetParentCell()
        Core.DebugMsg(agent.GetDisplayName() + " reached " + target.GetDisplayName() + "'s cell (off-screen)")
        OnArrivedAtTarget(slot, agent, target)
        Return
    EndIf

    ; Off-screen: check estimated travel time and teleport if stationary
    If Core.HandleOffScreenTravel(slot, agent, target)
        OnArrivedAtTarget(slot, agent, target)
    EndIf
EndFunction

Function OnArrivedAtTarget(Int slot, Actor agent, Actor target)
    ; State guard: only valid in state 1 (traveling to target) or state 8
    ; (timeout retry). Prevents re-entry from state 3 (returning) or
    ; state 9 (presenting) if a duplicate task fires mid-completion.
    Int currentState = Core.SlotStates[slot]
    If currentState != 1 && currentState != Core.STATE_AT_TARGET
        Core.DebugMsg(agent.GetDisplayName() + " OnArrivedAtTarget ignored — state " + currentState + " (expected 1 or 8)")
        Return
    EndIf

    Core.DebugMsg(agent.GetDisplayName() + " reached " + target.GetDisplayName())

    ; Remove travel package — agent will sandbox near target during interaction
    Core.RemoveAllPackages(agent)
    PO3_SKSEFunctions.SetLinkedRef(agent, None, Core.IntelEngine_TravelTarget)

    ; Face the target for immersive conversation
    agent.SetLookAt(target)

    ; Set interact counter and transition to AT_TARGET
    StorageUtil.SetIntValue(agent, "Intel_InteractCyclesRemaining", INTERACT_CYCLES)
    Core.SetSlotState(slot, agent, Core.STATE_AT_TARGET)

    Core.DebugMsg(agent.GetDisplayName() + " interacting with " + target.GetDisplayName() + " for " + INTERACT_CYCLES + " cycles")
EndFunction

; -----------------------------------------------------------------------------
; TELEPORT FALLBACK (last-resort for stuck recovery / timeout only)
; -----------------------------------------------------------------------------

Function TeleportAgentToTarget(Int slot, Actor agent, Actor target)
    ; Remove packages before teleport
    Core.RemoveAllPackages(agent)
    PO3_SKSEFunctions.SetLinkedRef(agent, None, Core.IntelEngine_TravelTarget)

    ; Teleport (debug-only log, player never notified)
    agent.MoveTo(target)
    Core.DebugMsg(agent.GetDisplayName() + " teleported to " + target.GetDisplayName() + " (off-screen)")

    ; Reset stuck tracking and transition to AT_TARGET
    Core.InitializeStuckTrackingForSlot(slot, agent)
    OnArrivedAtTarget(slot, agent, target)
EndFunction

; -----------------------------------------------------------------------------
; AT TARGET STATE (converged: both same-cell and off-screen arrive here)
; -----------------------------------------------------------------------------

Function HandleAtTarget(Int slot, Actor agent, Actor target)
    Int remaining = StorageUtil.GetIntValue(agent, "Intel_InteractCyclesRemaining")
    remaining -= 1
    StorageUtil.SetIntValue(agent, "Intel_InteractCyclesRemaining", remaining)

    If remaining > 0
        ; Still "conversing" — wait
        Return
    EndIf

    ; Interaction complete — narrate and decide success/failure
    Actor player = Game.GetPlayer()
    Bool playerPresent = (agent.GetParentCell() == player.GetParentCell())

    String agentName = agent.GetDisplayName()
    String targetName = target.GetDisplayName()
    String playerName = player.GetDisplayName()

    If playerPresent
        ; Player is in the same cell — let them overhear the conversation.
        ; Agent is in IntelEngine_TaskFaction so the action LLM can't re-select
        ; FetchPerson during this cycle. Safe to use narration here.
        Core.SendTaskNarration(agent, agentName + " told " + targetName + " that " + playerName + " needs to speak with them and asked them to come along.", target)
    Else
        ; Off-screen — silent transient event, no dialogue evaluation needed
        Core.SendTransientEvent(agent, target, agentName + " told " + targetName + " that they are needed by " + playerName + ".")
    EndIf

    ; Check fail flag
    Int shouldFail = StorageUtil.GetIntValue(agent, "Intel_ShouldFail")
    If shouldFail == 1
        HandleFetchFailure(slot, agent, target)
    Else
        Core.NotifyPlayer(agentName + " found " + targetName)
        BeginReturn(slot, agent, target, player)
    EndIf
EndFunction

; -----------------------------------------------------------------------------
; FETCH FAILURE (target refuses)
; -----------------------------------------------------------------------------

Function HandleFetchFailure(Int slot, Actor agent, Actor target)
    String agentName = agent.GetDisplayName()
    String targetName = target.GetDisplayName()
    String failReason = StorageUtil.GetStringValue(agent, "Intel_FailReason")
    If failReason == "" || failReason == "none"
        failReason = "was busy"
    EndIf

    Actor player = Game.GetPlayer()
    Bool playerPresent = (agent.GetParentCell() == player.GetParentCell())

    ; Narrate the refusal
    If playerPresent
        Core.SendTaskNarration(target, targetName + " tells " + agentName + ": \"" + failReason + "\"", agent)
    Else
        Core.SendTransientEvent(target, agent, targetName + " refused when " + agentName + " asked them to come: " + failReason)
    EndIf

    ; Both NPCs get transient events
    Core.SendTransientEvent(agent, target, agentName + " tried to fetch " + targetName + " but they refused: " + failReason)
    Core.SendTransientEvent(target, agent, agentName + " came to fetch " + targetName + " for " + Game.GetPlayer().GetDisplayName() + ", but " + targetName + " refused: " + failReason)

    ; Mark failure
    StorageUtil.SetStringValue(agent, "Intel_Result", "refused")

    ; Agent returns alone — no MakeNPCFollowAgent
    ; Natural pathfinding back to player. No teleporting.

    ; Set up walk back to player
    ObjectReference returnMarker = player
    StorageUtil.SetFormValue(agent, "Intel_ReturnMarker", returnMarker)
    PO3_SKSEFunctions.SetLinkedRef(agent, returnMarker, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(agent, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
    Utility.Wait(0.1)
    agent.EvaluatePackage()

    Core.SetSlotState(slot, agent, 3)  ; returning (alone)
    Core.InitializeStuckTrackingForSlot(slot, agent)
    Core.DebugMsg(agentName + " returning alone after " + targetName + " refused")
EndFunction

; -----------------------------------------------------------------------------
; BEGIN RETURN (success path — agent brings target back)
; -----------------------------------------------------------------------------

Function BeginReturn(Int slot, Actor agent, Actor target, Actor player)
    Bool sameCell = (agent.GetParentCell() == player.GetParentCell())

    ; Off-screen shortcut: if all three are in the same cell but NOT loaded,
    ; skip pathfinding since the player can't see it anyway.
    ; When on-screen, ALWAYS let NPCs walk for immersion — even in small interiors.
    If !agent.Is3DLoaded() && agent.GetParentCell() == player.GetParentCell() && target.GetParentCell() == player.GetParentCell()
        Core.DebugMsg(agent.GetDisplayName() + ": all off-screen same cell, completing fetch")
        OnReturnedWithTarget(slot, agent, target)
        Return
    EndIf

    ; Target pathfinds to player independently — same priority as agent.
    ; Must use PRIORITY_TRAVEL to override sandbox and other ambient packages.
    PO3_SKSEFunctions.SetLinkedRef(target, player, Core.IntelEngine_TravelTarget)
    If sameCell
        ActorUtil.AddPackageOverride(target, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
    Else
        ActorUtil.AddPackageOverride(target, Core.TravelPackage_Jog, Core.PRIORITY_TRAVEL, 1)
    EndIf

    Utility.Wait(0.1)
    target.EvaluatePackage()
    Core.DebugMsg(target.GetDisplayName() + " pathfinding to " + player.GetDisplayName())

    ; Agent walks back to player
    ObjectReference returnMarker = player
    StorageUtil.SetFormValue(agent, "Intel_ReturnMarker", returnMarker)
    PO3_SKSEFunctions.SetLinkedRef(agent, returnMarker, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(agent, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
    Utility.Wait(0.1)
    agent.EvaluatePackage()

    StorageUtil.SetIntValue(agent, "Intel_ReturnCycles", 0)
    Core.SetSlotState(slot, agent, 3)  ; returning
    Core.InitializeStuckTrackingForSlot(slot, agent)
    Core.SendTransientEvent(agent, target, agent.GetDisplayName() + " found " + target.GetDisplayName() + " and began heading back.")
EndFunction

Function CheckReturnArrival(Int slot, Actor agent, Actor target)
    ObjectReference returnMarker = StorageUtil.GetFormValue(agent, "Intel_ReturnMarker") as ObjectReference
    If returnMarker == None
        returnMarker = Game.GetPlayer()
    EndIf

    ; Grace period: let NPCs walk for at least 3 cycles (~9s) before allowing completion
    Int returnCycles = StorageUtil.GetIntValue(agent, "Intel_ReturnCycles", 0) + 1
    StorageUtil.SetIntValue(agent, "Intel_ReturnCycles", returnCycles)

    ; Failure returns: agent comes back alone, no need to wait for target
    Bool waitForTarget = (StorageUtil.GetStringValue(agent, "Intel_Result") != "refused")

    ; =========================================================================
    ; TARGET-FIRST COMPLETION (success returns only)
    ; The target arriving at the player IS the completion event. The agent's
    ; position doesn't matter — their job was to convince the target to come.
    ; Grace period: skip for first 3 cycles so NPCs have time to walk visibly.
    ; =========================================================================
    If returnCycles > 3 && waitForTarget && target != None && !target.IsDead()
        Actor player = Game.GetPlayer()
        Bool targetAtPlayer = false
        If target.Is3DLoaded() && player.Is3DLoaded()
            targetAtPlayer = (target.GetDistance(player) <= Core.ARRIVAL_DISTANCE)
        ElseIf !target.Is3DLoaded() && target.GetParentCell() == player.GetParentCell()
            targetAtPlayer = true
        EndIf

        If targetAtPlayer
            Core.DebugMsg(target.GetDisplayName() + " reached player — completing fetch")
            OnReturnedWithTarget(slot, agent, target)
            Return
        EndIf
    EndIf

    If agent.Is3DLoaded() && returnMarker.Is3DLoaded()
        ; Agent is on-screen — clear off-screen tracking
        StorageUtil.UnsetIntValue(agent, "Intel_OffScreenCycles")
        StorageUtil.UnsetFloatValue(agent, "Intel_OffScreenLastDist")

        Float agentDist = agent.GetDistance(returnMarker)
        If agentDist <= Core.ARRIVAL_DISTANCE
            ; Agent arrived — also wait for target on success returns
            If waitForTarget && target != None
                Bool targetArrived = false
                If returnCycles > 3 && target.Is3DLoaded()
                    Float targetDist = target.GetDistance(returnMarker)
                    targetArrived = (targetDist <= Core.ARRIVAL_DISTANCE)
                ElseIf returnCycles > 3 && !target.Is3DLoaded() && target.GetParentCell() == returnMarker.GetParentCell()
                    targetArrived = true
                EndIf

                If !targetArrived
                    ; Target still walking to player — count wait cycles
                    Int waitCycles = StorageUtil.GetIntValue(agent, "Intel_TargetWaitCycles") + 1
                    StorageUtil.SetIntValue(agent, "Intel_TargetWaitCycles", waitCycles)

                    ; First cycle: agent just arrived — sandbox near player while waiting, notify player
                    If waitCycles == 1
                        Core.RemoveAllPackages(agent, false)
                        PO3_SKSEFunctions.SetLinkedRef(agent, Game.GetPlayer() as ObjectReference, Core.IntelEngine_TravelTarget)
                        ActorUtil.AddPackageOverride(agent, Core.SandboxNearPlayerPackage, Core.PRIORITY_SANDBOX, 1)
                        agent.EvaluatePackage()
                        Core.NotifyPlayer(agent.GetDisplayName() + " arrived — " + target.GetDisplayName() + " is still on the way")
                        Core.SendTransientEvent(agent, target, agent.GetDisplayName() + " arrived but " + target.GetDisplayName() + " is still making their way here.")
                    EndIf

                    ; Track progress — if target is getting closer, reset stuck counter
                    Float targetDist = target.GetDistance(returnMarker)
                    Float lastTargetDist = StorageUtil.GetFloatValue(agent, "Intel_TargetLastDist", 0.0)
                    If lastTargetDist > 0.0 && targetDist < lastTargetDist - 50.0
                        ; Making progress (moved >50 units closer) — reset wait counter
                        Core.DebugMsg(target.GetDisplayName() + " making progress (" + targetDist + " from player)")
                        StorageUtil.SetIntValue(agent, "Intel_TargetWaitCycles", 1)
                        waitCycles = 1
                    EndIf
                    StorageUtil.SetFloatValue(agent, "Intel_TargetLastDist", targetDist)

                    ; Soft recovery every 3 cycles — nudge the target's AI
                    If waitCycles == 3 || waitCycles == 6 || waitCycles == 9
                        Core.DebugMsg("Target soft recovery (cycle " + waitCycles + ")")
                        target.EvaluatePackage()
                        ObjectReference playerRef = returnMarker
                        target.PathToReference(playerRef, 1.0)
                        target.EvaluatePackage()
                    EndIf

                    If waitCycles < MAX_TARGET_WAIT_CYCLES
                        Return  ; Keep waiting
                    EndIf

                    ; Exhausted — teleport target now
                    Core.DebugMsg("Target wait exhausted (" + waitCycles + " cycles, dist=" + targetDist + ")")
                    If !target.Is3DLoaded()
                        ; Off-screen — teleport silently behind camera
                        Core.TeleportBehindPlayer(target)
                    Else
                        ; On-screen — place near agent (who is near player)
                        target.MoveTo(agent, 100.0, 0.0, 0.0, false)
                    EndIf
                EndIf
            EndIf
            OnReturnedWithTarget(slot, agent, target)
        Else
            CheckIfStuck(slot, agent)
        EndIf
        Return
    EndIf

    ; Off-screen: use raw positions to calculate distance (works off-screen)
    Cell agentCell = agent.GetParentCell()
    Cell returnCell = returnMarker.GetParentCell()
    If agentCell == None || agentCell != returnCell
        ; Different cell — agent is still cross-cell pathfinding, let it continue
        Return
    EndIf

    ; Same cell off-screen — failure returns can complete immediately
    If !waitForTarget || target == None
        Core.DebugMsg(agent.GetDisplayName() + " returned to destination cell (off-screen)")
        OnReturnedWithTarget(slot, agent, target)
        Return
    EndIf

    ; Success return: calculate distance using native C++ (works off-screen)
    Float dist = IntelEngine.GetDistance2D(agent, returnMarker)

    ; Close enough off-screen? Complete.
    If dist <= Core.ARRIVAL_DISTANCE
        Core.DebugMsg(agent.GetDisplayName() + " arrived off-screen (dist=" + dist + ")")
        OnReturnedWithTarget(slot, agent, target)
        Return
    EndIf

    ; Track off-screen return progress
    Int cycles = StorageUtil.GetIntValue(agent, "Intel_OffScreenCycles") + 1
    Float lastDist = StorageUtil.GetFloatValue(agent, "Intel_OffScreenLastDist")

    ; If agent is making progress (distance decreased by >100 units), reset timer
    If lastDist > 0.0 && dist < lastDist - 100.0
        cycles = 1
    EndIf
    StorageUtil.SetIntValue(agent, "Intel_OffScreenCycles", cycles)
    StorageUtil.SetFloatValue(agent, "Intel_OffScreenLastDist", dist)

    ; Estimate max cycles: NPC walks ~100 units/sec, UPDATE_INTERVAL=3s → ~300 units/cycle
    ; Use 150 units/cycle (conservative, accounts for pathfinding detours)
    ; 2x safety margin on top
    Float maxCycles = (dist / 150.0) * 2.0
    If maxCycles < 5.0
        maxCycles = 5.0  ; minimum ~15 seconds
    EndIf

    If cycles as Float >= maxCycles
        ; Time's up — agent is stuck off-screen. Teleport both behind player.
        Core.DebugMsg(agent.GetDisplayName() + " off-screen return timed out (" + cycles + " cycles, dist=" + dist + "). Teleporting both.")
        Core.TeleportBehindPlayer(agent, 300.0)
        If target != None && !target.IsDead()
            Core.TeleportBehindPlayer(target, 250.0)
        EndIf
        Utility.Wait(0.5)
        OnReturnedWithTarget(slot, agent, target)
    Else
        Core.DebugMsg(agent.GetDisplayName() + " off-screen return: cycle " + cycles + "/" + (maxCycles as Int) + " dist=" + (dist as Int))
    EndIf
EndFunction

Function OnReturnedWithTarget(Int slot, Actor agent, Actor target)
    ; Immediately mark slot inactive so the 0.5s monitoring loop doesn't re-enter
    Core.MarkSlotProcessing(slot, agent)

    ; Branch: failure return (agent alone) vs success return (with target)
    String result = StorageUtil.GetStringValue(agent, "Intel_Result")
    If result == "refused"
        OnReturnedAfterFailure(slot, agent)
        Return
    EndIf

    Actor player = Game.GetPlayer()
    String agentName = agent.GetDisplayName()
    String targetName = target.GetDisplayName()
    Core.DebugMsg(agentName + " returned with " + targetName)

    ; Ensure target is at least in the same cell as the player.
    ; If not loaded or in a different cell, teleport behind the camera as a
    ; last resort. Otherwise let the NPC stand where they are — TalkToPlayer
    ; (priority 1) will naturally pathfind them to the player for conversation.
    If !target.Is3DLoaded()
        Core.DebugMsg(targetName + " not loaded — teleporting behind camera")
        Core.TeleportBehindPlayer(target)
    ElseIf target.GetParentCell() != player.GetParentCell()
        Core.DebugMsg(targetName + " different cell — teleporting behind camera")
        Core.TeleportBehindPlayer(target)
    EndIf

    ; Mark success
    StorageUtil.SetStringValue(agent, "Intel_Result", "success")

    ; Detach target alias BEFORE ClearSlot so ClearSlot won't touch the target.
    ReferenceAlias targetAlias = Core.GetTargetAlias(slot)
    If targetAlias
        targetAlias.Clear()
    EndIf

    ; =========================================================================
    ; LINGER: Switch from travel to tight sandbox near player.
    ;
    ; StartTargetLinger removes travel packages and applies
    ; SandboxNearPlayerPackage (200-unit radius) so the NPC stays at
    ; conversational distance without walking into the player's face.
    ; =========================================================================
    PO3_SKSEFunctions.SetLinkedRef(target, None, Core.IntelEngine_AgentLink)
    StartTargetLinger(target, agent)

    ; Narration: NPC was brought here and wants to know why.
    Bool targetVisible = target.Is3DLoaded() && target.GetParentCell() == player.GetParentCell()
    If targetVisible
        target.SetLookAt(player)
        Core.SendTaskNarration(target, targetName + " was brought to " + player.GetDisplayName() + " by " + agentName + " and wants to know why they were summoned.", player)
    Else
        Core.SendTransientEvent(agent, target, agentName + " found " + targetName + " and brought them over.")
    EndIf

    Core.NotifyPlayer(agentName + " brought " + targetName)

    ; Free the agent — target is lingering (sandbox near player).
    Core.ClearSlotRestoreFollower(slot, agent)
    StorageUtil.SetFloatValue(agent, "Intel_TaskCooldown", Utility.GetCurrentRealTime())
EndFunction

Function OnReturnedAfterFailure(Int slot, Actor agent)
    String targetName = StorageUtil.GetStringValue(agent, "Intel_Target")
    String failReason = StorageUtil.GetStringValue(agent, "Intel_FailReason")
    If failReason == "" || failReason == "none"
        failReason = "was busy"
    EndIf

    String agentName = agent.GetDisplayName()
    Core.DebugMsg(agentName + " returned after " + targetName + " refused")

    ; Agent reports failure to player
    Actor player = Game.GetPlayer()
    If agent.GetParentCell() == player.GetParentCell()
        agent.SetLookAt(player)
        Core.SendTaskNarration(agent, agentName + " tells " + player.GetDisplayName() + " that " + targetName + " refused to come: " + failReason, player)
    Else
        Core.SendTransientEvent(agent, player, agentName + " returned to report that " + targetName + " refused: " + failReason)
    EndIf

    Core.NotifyPlayer(agentName + ": " + targetName + " refused — " + failReason)

    Core.ClearSlotRestoreFollower(slot, agent)
    ; Cooldown prevents narration-triggered re-selection
    StorageUtil.SetFloatValue(agent, "Intel_TaskCooldown", Utility.GetCurrentRealTime())
EndFunction

; HandleTargetPresenting removed — target-first completion in CheckReturnArrival
; makes the intermediate presenting state unnecessary. The target speaks to the
; player as soon as they arrive, regardless of the agent's position.

; =============================================================================
; MESSAGE DELIVERY STATE MACHINE
; =============================================================================

Function HandleMessageState(Int slot, Actor agent, Int taskState)
    Actor target = StorageUtil.GetFormValue(agent, "Intel_TargetNPC") as Actor

    If target == None || target.IsDead()
        Core.NotifyPlayer(agent.GetDisplayName() + " could not find the recipient")
        Core.ClearSlot(slot, true)
        Return
    EndIf

    If taskState == 1
        ; Traveling to target — natural pathfinding
        If CheckDeparture(slot, agent)
            Return
        EndIf
        CheckArrivalAtTarget(slot, agent, target)

    ElseIf taskState == Core.STATE_AT_TARGET
        ; At target — brief interaction before delivering
        HandleAtTarget_Message(slot, agent, target)

    ElseIf taskState == 3
        ; Returning to player after delivering
        CheckDeliveryReturnArrival(slot, agent)
    EndIf
EndFunction

Function HandleAtTarget_Message(Int slot, Actor agent, Actor target)
    Int remaining = StorageUtil.GetIntValue(agent, "Intel_InteractCyclesRemaining")
    remaining -= 1
    StorageUtil.SetIntValue(agent, "Intel_InteractCyclesRemaining", remaining)

    If remaining > 0
        ; Still in conversation — wait
        Return
    EndIf

    ; Interaction done — deliver the message
    OnArrivedToDeliver(slot, agent, target)
EndFunction

Function OnArrivedToDeliver(Int slot, Actor agent, Actor target)
    ; Immediately mark slot inactive so the 0.5s monitoring loop doesn't re-enter
    ; during waits below. BeginDeliveryReturn or ClearSlotRestoreFollower does full cleanup.
    Core.MarkSlotProcessing(slot, agent)

    String msgContent = StorageUtil.GetStringValue(agent, "Intel_Message")

    Core.DebugMsg(agent.GetDisplayName() + " delivering message to " + target.GetDisplayName())

    ; Remove travel packages (done traveling to target)
    Core.RemoveAllPackages(agent)
    PO3_SKSEFunctions.SetLinkedRef(agent, None, Core.IntelEngine_TravelTarget)

    ; Store message on recipient so they remember it
    ; This makes the message appear in their prompt context via decorators
    Core.StoreReceivedMessage(target, agent, msgContent)

    ; If the message included a meeting request, schedule it now
    String meetLoc = StorageUtil.GetStringValue(agent, "Intel_DeliveryMeetLocation")
    String meetTimeStr = StorageUtil.GetStringValue(agent, "Intel_DeliveryMeetTime")
    Core.DebugMsg("Delivery meet check: loc='" + meetLoc + "' time='" + meetTimeStr + "'")
    If meetLoc != "none" && meetLoc != "" && meetTimeStr != "none" && meetTimeStr != ""
        If Core.Schedule != None
            Core.DebugMsg("Scheduling meeting for " + target.GetDisplayName() + " at " + meetLoc + " " + meetTimeStr)
            Bool scheduled = Core.Schedule.ScheduleMeeting(target, meetLoc, meetTimeStr)
            If scheduled
                Core.DebugMsg("Scheduled meeting for " + target.GetDisplayName() + " at " + meetLoc + " " + meetTimeStr)
            Else
                Core.DebugMsg("Failed to schedule meeting for " + target.GetDisplayName())
            EndIf
        Else
            Core.DebugMsg("Delivery meet: Core.Schedule is None!")
        EndIf
    Else
        Core.DebugMsg("Delivery meet: skipped (loc='" + meetLoc + "' time='" + meetTimeStr + "')")
    EndIf

    ; Clean up meeting data
    StorageUtil.UnsetStringValue(agent, "Intel_DeliveryMeetLocation")
    StorageUtil.UnsetStringValue(agent, "Intel_DeliveryMeetTime")

    ; Deliver the message — narration depends on player proximity
    Actor player = Game.GetPlayer()
    Bool playerPresent = (agent.GetParentCell() == player.GetParentCell())
    String agentName = agent.GetDisplayName()
    String targetName = target.GetDisplayName()

    If playerPresent
        ; Player is here — full narration to target
        Core.NotifyPlayer(agentName + " delivered the message")
        agent.SetLookAt(target)
        target.SetLookAt(agent)
        Utility.Wait(0.5)
        Core.SendTaskNarration(target, agentName + " found " + targetName + " and delivered a message: \"" + msgContent + "\"", agent)
    Else
        ; Player absent — transient event for target's conversational context.
        ; Long-term persistence is via StoreReceivedMessage (decorators).
        Core.SendTransientEvent(target, agent, agentName + " came and told " + targetName + ": \"" + msgContent + "\"")
    EndIf

    StorageUtil.SetStringValue(agent, "Intel_Result", "delivered")

    ; Report-back only when player was off-screen — if the player witnessed the
    ; delivery in person there's nothing to report.
    If !playerPresent && StorageUtil.GetIntValue(Game.GetPlayer(), "Intel_DeliveryReportBack") == 1
        ; Travel back to player to report
        Core.NotifyPlayer(agentName + " delivered a message to " + targetName + " and is heading back")
        BeginDeliveryReturn(slot, agent)
    Else
        ; Player saw it, or report-back disabled — done
        If !playerPresent
            Core.NotifyPlayer(agentName + " delivered a message to " + targetName)
        EndIf
        Core.ClearSlotRestoreFollower(slot, agent)
    EndIf
EndFunction

; -----------------------------------------------------------------------------
; DELIVERY RETURN (agent returns to player after delivering)
; -----------------------------------------------------------------------------

Function BeginDeliveryReturn(Int slot, Actor agent)
    Actor player = Game.GetPlayer()
    ObjectReference returnMarker = player
    StorageUtil.SetFormValue(agent, "Intel_ReturnMarker", returnMarker)

    PO3_SKSEFunctions.SetLinkedRef(agent, returnMarker, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(agent, Core.TravelPackage_Jog, Core.PRIORITY_TRAVEL, 1)
    Utility.Wait(0.1)
    agent.EvaluatePackage()

    Core.SetSlotState(slot, agent, 3)  ; returning
    Core.InitializeStuckTrackingForSlot(slot, agent)
    Core.DebugMsg(agent.GetDisplayName() + " returning to player after delivery")
EndFunction

Function CheckDeliveryReturnArrival(Int slot, Actor agent)
    Actor player = Game.GetPlayer()

    If agent.Is3DLoaded() && player.Is3DLoaded()
        Float dist = agent.GetDistance(player)
        If dist <= Core.ARRIVAL_DISTANCE
            OnReturnedFromDelivery(slot, agent)
        Else
            CheckIfStuck(slot, agent)
        EndIf
        Return
    EndIf

    ; Off-screen: same cell as player = arrived
    If agent.GetParentCell() == player.GetParentCell()
        OnReturnedFromDelivery(slot, agent)
    EndIf
EndFunction

Function OnReturnedFromDelivery(Int slot, Actor agent)
    ; Immediately mark slot inactive so the 0.5s monitoring loop doesn't re-enter
    ; during the Utility.Wait below. ClearSlotRestoreFollower does the full cleanup.
    Core.MarkSlotProcessing(slot, agent)

    String targetName = Core.SlotTargetNames[slot]
    String agentName = agent.GetDisplayName()
    Actor player = Game.GetPlayer()
    Bool playerPresent = (agent.GetParentCell() == player.GetParentCell())

    Core.DebugMsg(agentName + " returned from delivering message to " + targetName)

    If playerPresent
        ; Stop travel and sandbox near player so agent doesn't walk away
        Core.RemoveAllPackages(agent, false)
        PO3_SKSEFunctions.SetLinkedRef(agent, player as ObjectReference, Core.IntelEngine_TravelTarget)
        ActorUtil.AddPackageOverride(agent, Core.SandboxNearPlayerPackage, Core.PRIORITY_SANDBOX, 1)
        agent.EvaluatePackage()

        agent.SetLookAt(player)
        Utility.Wait(0.5)
        Core.SendTaskNarration(agent, agentName + " returned after delivering a message to " + targetName + " and wants to report back.", player)
        ; Give SkyrimNet time to process the narration before clearing packages
        Utility.Wait(2.0)
    EndIf

    Core.NotifyPlayer(agentName + " returned from delivering message to " + targetName)

    Core.ClearSlotRestoreFollower(slot, agent)
EndFunction

; =============================================================================
; SEARCH FOR ACTOR STATE MACHINE
; =============================================================================

Function HandleSearchState(Int slot, Actor agent, Int taskState)
    Actor target = StorageUtil.GetFormValue(agent, "Intel_TargetNPC") as Actor

    If target == None || target.IsDead()
        Core.NotifyPlayer(agent.GetDisplayName() + " could not find their target")
        Core.ClearSlot(slot, true)
        Return
    EndIf

    ; Agent off-screen — check estimated travel time for teleport
    If !agent.Is3DLoaded()
        If Core.HandleOffScreenTravel(slot, agent, target)
            OnArrivedAtSearchTarget(slot, agent, target)
        EndIf
        Return
    EndIf

    If taskState == 1
        ; Searching - check departure, arrival, and player distance
        If CheckDeparture(slot, agent)
            Return
        EndIf
        If target.Is3DLoaded()
            Float distToTarget = agent.GetDistance(target)
            If distToTarget <= TARGET_APPROACH_DISTANCE
                ; Arrived at target!
                OnArrivedAtSearchTarget(slot, agent, target)
                Return
            EndIf
        EndIf

        ; Check if stuck (agent can get stuck at obstacles while searching)
        CheckIfStuck(slot, agent)

        ; Check if player fell behind
        Actor player = Game.GetPlayer()
        If player.Is3DLoaded()
            Float distToPlayer = agent.GetDistance(player)
            If distToPlayer > LEAD_PAUSE_DISTANCE
                ; Player fell behind - pause and wait
                Core.DebugMsg(agent.GetDisplayName() + " pausing to wait for player (dist=" + distToPlayer + ")")
                Core.RemoveAllPackages(agent)
                PO3_SKSEFunctions.SetLinkedRef(agent, None, Core.IntelEngine_TravelTarget)
                ActorUtil.AddPackageOverride(agent, Core.SandboxNearPlayerPackage, Core.PRIORITY_SANDBOX, 1)
                agent.EvaluatePackage()

                Core.SetSlotState(slot, agent, 5)  ; waiting for player
            EndIf
        EndIf

    ElseIf taskState == 5
        ; Waiting for player to catch up — auto-resume when close
        Actor player = Game.GetPlayer()
        If player.Is3DLoaded()
            Float distToPlayer = agent.GetDistance(player)
            If distToPlayer <= LEAD_RESUME_DISTANCE
                ; Player caught up — resume search
                Core.DebugMsg(agent.GetDisplayName() + " resuming search, player caught up")
                ActorUtil.RemovePackageOverride(agent, Core.SandboxNearPlayerPackage)
                Package travelPkg = Core.GetTravelPackage(Core.SlotSpeeds[slot])
                PO3_SKSEFunctions.SetLinkedRef(agent, target, Core.IntelEngine_TravelTarget)
                ActorUtil.AddPackageOverride(agent, travelPkg, Core.PRIORITY_TRAVEL, 1)
                agent.EvaluatePackage()
                Core.SetSlotState(slot, agent, 1)  ; back to searching
            EndIf
        EndIf
    EndIf
EndFunction

Function OnArrivedAtSearchTarget(Int slot, Actor agent, Actor target)
    Core.DebugMsg(agent.GetDisplayName() + " found target: " + target.GetDisplayName())
    Core.NotifyPlayer(agent.GetDisplayName() + " found " + target.GetDisplayName())

    ; Remove packages
    Core.RemoveAllPackages(agent)
    PO3_SKSEFunctions.SetLinkedRef(agent, None, Core.IntelEngine_TravelTarget)

    ; Mark success
    StorageUtil.SetStringValue(agent, "Intel_Result", "success")

    Core.ClearSlotRestoreFollower(slot, agent)

    ; Narration — player should be here (they were being led), but check anyway
    Actor player = Game.GetPlayer()
    If agent.GetParentCell() == player.GetParentCell()
        Core.SendTaskNarration(agent, agent.GetDisplayName() + " arrived with " + player.GetDisplayName() + " at " + target.GetDisplayName() + "'s location.")
    Else
        Core.SendTransientEvent(agent, target, agent.GetDisplayName() + " found " + target.GetDisplayName() + ".")
    EndIf
EndFunction

; =============================================================================
; DEPARTURE DETECTION
;
; Early check: if the NPC hasn't moved from their starting position after
; DEPARTURE_CHECK_CYCLES (~9s), they're likely blocked by another package,
; a scene, or dialogue. Cancel the task with an immersive response instead
; of letting them stand idle for minutes.
; =============================================================================

; Returns true if the task was cancelled (caller should return immediately).
Bool Function CheckDeparture(Int slot, Actor agent)
    {Check if NPC departed. Uses Core.CheckDepartureProgress for shared logic.
    Returns true if departure failed and slot was handled (caller should return).}
    Int status = Core.CheckDepartureProgress(slot, agent, STUCK_DISTANCE_THRESHOLD)

    If status <= 2
        ; 0=too early, 1=departed, 2=soft recovery applied — all OK
        Return false
    EndIf

    ; status == 3: escalate
    HandleDepartureFailure(slot, agent)
    Return true
EndFunction

Function HandleDepartureFailure(Int slot, Actor agent)
    String agentName = agent.GetDisplayName()
    Actor player = Game.GetPlayer()

    If !agent.Is3DLoaded()
        ; Player isn't looking — teleport silently to destination instead of cancelling
        ObjectReference dest = StorageUtil.GetFormValue(agent, "Intel_DestMarker") as ObjectReference
        If dest != None
            Core.DebugMsg(agentName + " failed to depart (off-screen) — teleporting to destination")
            agent.MoveTo(dest, 0.0, 0.0, 50.0)
            agent.EvaluatePackage()
            Return
        EndIf
    EndIf

    ; Player is watching — narrate and cancel
    Core.DebugMsg(agentName + " failed to depart (visible) — narrating cancel")

    If agent.GetParentCell() == player.GetParentCell()
        Core.SendTaskNarration(agent, agentName + " tried to leave but was unable to and gave up on the task.", player)
    Else
        Core.SendTransientEvent(agent, player, agentName + " was unable to carry out the task and stayed behind.")
    EndIf

    Core.RemoveAllPackages(agent)
    Core.ClearSlot(slot, true)
EndFunction

; =============================================================================
; STUCK DETECTION & RECOVERY
;
; Position tracking and counter management handled by C++ StuckDetector.
; Papyrus handles only engine-specific responses (EvaluatePackage, MoveTo,
; PathToReference) that require the Papyrus VM.
; =============================================================================

Function CheckIfStuck(Int slot, Actor npc)
    ; Skip stuck detection while NPC is in dialogue or combat — stationary by design
    If npc.GetDialogueTarget() != None || npc.IsInCombat()
        IntelEngine.ResetStuckSlot(slot, npc)
        Return
    EndIf

    Int status = IntelEngine.CheckStuckStatus(npc, slot, STUCK_DISTANCE_THRESHOLD)

    If status == 0
        ; Moving normally — nothing to do
        Return
    EndIf

    String taskType = Core.SlotTaskTypes[slot]
    Int taskState = Core.SlotStates[slot]

    ; Get appropriate destination based on state
    ObjectReference dest
    Bool isReturning = (taskState == 3 && (taskType == "fetch_npc" || taskType == "deliver_message"))
    If isReturning
        dest = StorageUtil.GetFormValue(npc, "Intel_ReturnMarker") as ObjectReference
    Else
        dest = StorageUtil.GetFormValue(npc, "Intel_DestMarker") as ObjectReference
    EndIf

    If status == 1
        ; First stuck attempt + on-screen — narrate once so the NPC reacts in-character
        ; Double guard: C++ counter == 1 AND StorageUtil flag to prevent any repeat
        If npc.Is3DLoaded() && IntelEngine.GetStuckRecoveryAttempts(slot) == 1 \
                && StorageUtil.GetIntValue(npc, "Intel_TaskStuckNarrated") != 1
            StorageUtil.SetIntValue(npc, "Intel_TaskStuckNarrated", 1)
            String npcName = npc.GetDisplayName()
            String target = Core.SlotTargetNames[slot]
            If taskType == "fetch_npc"
                Core.SendTaskNarration(npc, npcName + " is stuck and can't seem to find a way to reach " + target + ".")
            ElseIf taskType == "deliver_message"
                Core.SendTaskNarration(npc, npcName + " is stuck trying to get to " + target + " to deliver a message.")
            ElseIf taskType == "search_for_actor"
                Core.SendTaskNarration(npc, npcName + " is stuck and unable to continue the search.")
            Else
                Core.SendTaskNarration(npc, npcName + " seems stuck and unable to continue.")
            EndIf
        EndIf

        Core.SoftStuckRecovery(npc, slot, dest)

    ElseIf status == 3
        ; Teleport — recovery exhausted
        Core.DebugMsg("Stuck teleport for " + npc.GetDisplayName() + " (slot " + slot + ")")

        ; Layer B: Try location marker navigation (on-screen, outbound only).
        ; Applies to all task types including search_for_actor — the search
        ; target could be far away and the NPC needs to navigate through
        ; mountain passes. Walking to a nearby location marker is immersive.
        If !isReturning && dest != None && Core.TryWaypointNavigation(slot, npc, dest)
            Return
        EndIf

        If taskType == "search_for_actor"
            ; No waypoint found — don't blind-teleport search NPC, just keep retrying
            Return
        EndIf

        If isReturning
            ; Progressive distance from C++ StuckDetector
            Float distance = IntelEngine.GetTeleportDistance(slot)
            Core.DebugMsg("Teleport behind player at " + distance + " units for " + npc.GetDisplayName())
            Core.TeleportBehindPlayer(npc, distance)
            ; Re-apply travel package — may have been dropped by engine
            Int speed = Core.SlotSpeeds[slot]
            Package travelPkg = Core.GetTravelPackage(speed)
            If travelPkg
                ActorUtil.AddPackageOverride(npc, travelPkg, Core.PRIORITY_TRAVEL, 1)
            EndIf
            npc.EvaluatePackage()
        ElseIf dest != None
            Core.DebugMsg("Task stuck recovery exhausted — teleporting " + npc.GetDisplayName())
            npc.MoveTo(dest, 0.0, 0.0, 50.0)
            npc.EvaluatePackage()
        EndIf
    EndIf
EndFunction

; =============================================================================
; HELPER FUNCTIONS
; =============================================================================

Function SetDistanceBasedDeadline(Int slot, Actor agent, ObjectReference target, Bool isRoundTrip)
    {Calculate a game-time deadline based on distance to target.
    All math (distance, pathfinding multiplier, safety margin, clamping) is in C++.}
    Float deadline = IntelEngine.CalculateDeadlineFromDistance(agent, target, isRoundTrip, MIN_TASK_HOURS, MAX_TASK_HOURS)
    Core.SetSlotDeadline(slot, deadline)
EndFunction

String Function GetNPCSuggestion(String searchedName)
    {Get suggestion for mistyped NPC name via DLL fuzzy matching.}
    Return IntelEngine.GetNPCNameSuggestion(searchedName)
EndFunction

; =============================================================================
; CANCEL API
; =============================================================================

Function CancelNPCTask(Actor agent)
    {Cancel any NPC task for this agent}

    If agent == None
        Return
    EndIf

    Int slot = Core.FindSlotByAgent(agent)
    If slot < 0
        Return
    EndIf

    String taskType = Core.SlotTaskTypes[slot]
    If taskType == "fetch_npc" || taskType == "deliver_message" || taskType == "search_for_actor"
        Core.DebugMsg("Canceling " + taskType + " for " + agent.GetDisplayName())

        ; Also release target if escorting or lingering — use targeted removal
        ; to preserve SkyrimNet packages on the target NPC
        ReferenceAlias targetAlias = Core.GetTargetAlias(slot)
        If targetAlias
            Actor target = targetAlias.GetActorReference()
            If target
                Core.RemoveIntelPackages(target)
                ClearLingerSlot(target)
                PO3_SKSEFunctions.SetLinkedRef(target, None, Core.IntelEngine_AgentLink)
            EndIf
        EndIf

        Core.ClearSlot(slot, true)
        Core.NotifyPlayer(agent.GetDisplayName() + "'s task was cancelled")
    EndIf
EndFunction

; =============================================================================
; STATUS API
; =============================================================================

Bool Function IsOnNPCTask(Actor agent)
    Int slot = Core.FindSlotByAgent(agent)
    If slot < 0
        Return false
    EndIf
    String taskType = Core.SlotTaskTypes[slot]
    Return taskType == "fetch_npc" || taskType == "deliver_message" || taskType == "search_for_actor"
EndFunction

String Function GetNPCTaskStatus(Actor agent)
    Int slot = Core.FindSlotByAgent(agent)
    If slot < 0
        Return ""
    EndIf

    String taskType = Core.SlotTaskTypes[slot]
    String target = Core.SlotTargetNames[slot]
    Int taskState = Core.SlotStates[slot]

    If taskType == "fetch_npc"
        If taskState == 1
            Return "going to find " + target
        ElseIf taskState == Core.STATE_AT_TARGET
            Return "talking to " + target
        ElseIf taskState == 3
            Return "returning with " + target
        EndIf
    ElseIf taskType == "deliver_message"
        If taskState == 1
            Return "delivering message to " + target
        ElseIf taskState == Core.STATE_AT_TARGET
            Return "speaking with " + target
        EndIf
    ElseIf taskType == "search_for_actor"
        If taskState == 1
            Return "searching for " + target
        ElseIf taskState == 5
            Return "waiting for instructions (searching for " + target + ")"
        EndIf
    EndIf

    Return ""
EndFunction
