Scriptname IntelEngine_NPCTasks extends Quest
{
    IntelEngine NPC Task System

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


Float Property LEAD_PAUSE_DISTANCE = 1500.0 AutoReadOnly
{If player falls behind this far, NPC pauses to wait}

Float Property LEAD_RESUME_DISTANCE = 500.0 AutoReadOnly
{If player gets within this distance, NPC auto-resumes searching}

; STUCK_DISTANCE_THRESHOLD, LINGER_APPROACH_DISTANCE, LINGER_FAR_TICKS_LIMIT,
; DEPARTURE_CHECK_CYCLES are defined on Core (single source of truth).

; =============================================================================
; TASK-SPECIFIC CONSTANTS
; =============================================================================

Float Property MIN_TASK_HOURS = 1.0 AutoReadOnly
{Minimum deadline in game hours (even for nearby targets)}

Float Property MAX_TASK_HOURS = 6.0 AutoReadOnly
{Maximum deadline in game hours (even for cross-map targets)}

; STATE_AT_TARGET moved to Core.STATE_AT_TARGET (=8)

Int Property MAX_TARGET_WAIT_CYCLES = 15 AutoReadOnly
{Max cycles to wait for the fetched target to walk to the player (~45s).
Progress-tracked: if target is getting closer, the counter resets.}

; STATE_TARGET_PRESENTING (9) and MAX_PRESENT_CYCLES removed.
; Target-first completion in CheckReturnArrival makes intermediate states unnecessary.

; LINGER_RELEASE_DISTANCE defined on Core (single source of truth).

Float Property RETURN_POLL_INTERVAL = 0.5 AutoReadOnly
{Fast update interval when NPCs are in state 3 (returning). Catches arrival
within ~50 units of drift instead of ~300 at the normal 3s interval.}

Int Property MAX_LINGER_SLOTS = 5 AutoReadOnly
{Maximum concurrent lingering targets — matches MAX_SLOTS.}

Float Property TARGET_WAIT_SECONDS = 45.0 AutoReadOnly
{Real seconds the agent waits at the player for a fetched NPC who is getting no closer. Was counted in
monitoring passes (MAX_TARGET_WAIT_CYCLES, "~45s"), but while anyone is returning the passes come every
half second: the wait was over after seven seconds.}

Float Property TARGET_NUDGE_SECONDS = 9.0 AutoReadOnly
{Real seconds between the nudges given to a fetched NPC who is getting no closer (three at most).}

Float Property LINGER_APPROACH_MAX_HOURS = 0.25 AutoReadOnly
{Game hours a fetched NPC keeps walking toward a player they cannot reach before settling where they are.}

Float Property LINGER_VISIT_HOURS = 2.0 AutoReadOnly
{Game hours a fetched NPC stays at the player's side when the player does not walk away.}

Float Property LINGER_AFTER_TALK_HOURS = 0.5 AutoReadOnly
{A fetched NPC stays at least this long (game hours) after their last spoken line: never sent off mid-conversation.}

Float Property ESCORT_HOLD_HOURS = 0.5 AutoReadOnly
{Game hours an escorted NPC is held at the destination when nobody asked them to wait there for the player.}

Float Property SEARCH_WAIT_MAX_HOURS = 2.0 AutoReadOnly
{Game hours a searching NPC waits for a player who has fallen behind before giving the search up.}

Float Property SEARCH_MAX_HOURS = 24.0 AutoReadOnly
{Game hours after which a search is ended whatever state it is in (a search had no time limit at all).}

; =============================================================================
; INITIALIZATION
; =============================================================================

Function EnsureMonitoringAlive()
    {Lightweight heartbeat: if active NPC tasks exist, re-register the update loop.
    Called by Schedule's game-time loop as a safety net against Papyrus VM stack dumps.}
    Int i = 0
    While i < Core.MAX_SLOTS
        String taskType = Core.SlotTaskTypes[i]
        If Core.SlotStates[i] != 0 && IsNPCTaskType(taskType)
            Core.RequestTick(Core.UPDATE_INTERVAL)
            Return
        EndIf
        i += 1
    EndWhile
    ; Lingering targets hold no slot, but only this loop ever releases them.
    If HasLingeringTargets()
        Core.RequestTick(Core.UPDATE_INTERVAL)
    EndIf
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
        If Core.SlotStates[i] != 0 && IsNPCTaskType(taskType)
            hasActive = true
            RecoverSlotPackages(i)
        EndIf
        i += 1
    EndWhile
    If hasActive
        Core.RequestTick(Core.UPDATE_INTERVAL)
        Core.DebugMsg("NPCTasks monitoring restarted")
    EndIf
    ; A fetched or escorted NPC who lingers holds no slot. With no task running nobody asked for a tick
    ; after a load: they kept their sandbox (or their walk toward the player) with nothing left to end it.
    If HasLingeringTargets()
        RelinkLingeringTargets()
        Core.RequestTick(Core.UPDATE_INTERVAL)
    EndIf
EndFunction

Function RelinkLingeringTargets()
    {The package overrides of a lingering target survive a save, the linked ref they work around does not.}
    Actor player = Game.GetPlayer()
    Int i = StorageUtil.FormListCount(self, "Intel_LingeringTargets") - 1
    While i >= 0
        Actor target = StorageUtil.FormListGet(self, "Intel_LingeringTargets", i) as Actor
        If target != None && !target.IsDead() && !target.IsDisabled()
            ObjectReference anchor = player
            If StorageUtil.GetIntValue(target, "Intel_LingerPhase", 0) == 3
                ; Waiting at the escort destination. (A sandbox around a marker that is not loaded crashes
                ; the engine, see Travel.OnArrival: then the place is where they stand.)
                anchor = StorageUtil.GetFormValue(target, "Intel_LingerDestRef") as ObjectReference
                If anchor == None || !target.Is3DLoaded()
                    anchor = target
                EndIf
            EndIf
            PO3_SKSEFunctions.SetLinkedRef(target, anchor, Core.IntelEngine_TravelTarget)
            target.EvaluatePackage()
        EndIf
        i -= 1
    EndWhile
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
            ; The linked ref is back on the real destination: a waypoint detour from before the load is void.
            StorageUtil.UnsetFormValue(agent, "Intel_CurrentWaypoint")
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
        ; The slot's speed is the package that was applied (walk, or jog for a delivery return).
        ActorUtil.AddPackageOverride(agent, travelPkg, Core.PRIORITY_TRAVEL, 1)
        agent.EvaluatePackage()

        ; Also recover target's travel package for fetch/escort returns
        If taskType == "fetch_npc" || taskType == "escort_target"
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
        ; Waiting for player to catch up — re-apply sandbox so agent stays put (around themselves: with no
        ; linked ref the sandbox has no place and they head for home, see HandleSearchState)
        PO3_SKSEFunctions.SetLinkedRef(agent, agent as ObjectReference, Core.IntelEngine_TravelTarget)
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
; Released when the player leaves Core.LINGER_RELEASE_DISTANCE.
;
; Uses StorageUtil instead of script-level arrays to avoid save-compatibility
; issues when script variables change between builds. Linger state stored on
; each target actor; list of lingering targets stored on the quest form.
; =============================================================================

Function StartTargetLinger(Actor target, Actor agent)
    {Start lingering near the player. Phase 1: walk toward player using
    TravelPackage_Walk. Phase 2: sandbox within 200 units once close (100 units).
    Released when the player leaves Core.LINGER_RELEASE_DISTANCE (800 units).}

    ; Already lingering (fetched a second time while still at the player's side): the visit starts over.
    ; This used to return here, with the walk package of the new fetch still on them and nothing left
    ; that would take it off: they kept walking into the player after the linger had ended.
    If StorageUtil.GetIntValue(target, "Intel_LingerPhase", 0) > 0
        Core.DebugMsg(target.GetDisplayName() + " already lingering, starting over")
        ClearLingerSlot(target)
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
    ; The approach has its own clock (see CheckLingeringTargets).
    StorageUtil.SetFloatValue(target, "Intel_LingerUntil", Utility.GetCurrentGameTime() + LINGER_APPROACH_MAX_HOURS / 24.0)
    StorageUtil.FormListAdd(self, "Intel_LingeringTargets", target, false)

    Core.DebugMsg(target.GetDisplayName() + " approaching player (linger phase 1)")
    Core.RequestTick(Core.UPDATE_INTERVAL)
EndFunction

Function ClearLingerSlot(Actor target)
    {Remove all linger state from a target actor and remove from the list.}
    StorageUtil.UnsetIntValue(target, "Intel_LingerPhase")
    StorageUtil.UnsetFormValue(target, "Intel_LingerAgent")
    StorageUtil.UnsetIntValue(target, "Intel_LingerFarTicks")
    StorageUtil.UnsetFloatValue(target, "Intel_LingerLastDist")
    StorageUtil.UnsetFloatValue(target, "Intel_LingerUntil")
    StorageUtil.UnsetFloatValue(target, "Intel_LingerCap")
    ; Escort-wait keys (safe to unset even if not present)
    StorageUtil.UnsetStringValue(target, "Intel_LingerDestName")
    StorageUtil.UnsetFloatValue(target, "Intel_LingerStart")
    StorageUtil.UnsetFormValue(target, "Intel_LingerDestRef")
    StorageUtil.UnsetIntValue(target, "Intel_LingerNoGreet")
    StorageUtil.FormListRemove(self, "Intel_LingeringTargets", target, true)
EndFunction

Function ForgetLinger(Actor npc, Bool removePackages = true)
    {The NPC is taken into a new task, as its agent or as the one being fetched or escorted: the old visit is
    over. Without this the linger went on handling them. On its next pass it took the new task's walk
    package off and pointed their travel target at the player ("reached player, sandboxing"), or, when an
    escort wait ran out, removed every package the new task had put on them.
    removePackages = false for an agent: the task start clears their packages itself, when they set off.}
    If npc == None
        Return
    EndIf
    If StorageUtil.GetIntValue(npc, "Intel_LingerPhase", 0) <= 0 && StorageUtil.FormListFind(self, "Intel_LingeringTargets", npc as Form) < 0
        Return
    EndIf
    Core.DebugMsg(npc.GetDisplayName() + " leaves the linger for a new task")
    If removePackages
        Core.RemoveIntelPackages(npc, false)
    EndIf
    ClearLingerSlot(npc)
EndFunction

Bool Function LingerVisitIsOver(Actor target)
    {The clock of a visit at the player's side. A fetched NPC used to stay for as long as the player did not
    walk away: for good, when the player was at home. The visit ends after LINGER_VISIT_HOURS, but never in
    the middle of a conversation: while they speak or are spoken to, it runs at least LINGER_AFTER_TALK_HOURS
    past the last line.}
    Float now = Utility.GetCurrentGameTime()
    Float until = StorageUtil.GetFloatValue(target, "Intel_LingerUntil", 0.0)
    If until <= 0.0
        ; A linger that began before this clock existed: it starts now.
        StorageUtil.SetFloatValue(target, "Intel_LingerUntil", now + LINGER_VISIT_HOURS / 24.0)
        Return false
    EndIf
    ; The longest a visit lasts, whatever is being said (set on the first look).
    Float visitCap = StorageUtil.GetFloatValue(target, "Intel_LingerCap", 0.0)
    If visitCap <= 0.0
        StorageUtil.SetFloatValue(target, "Intel_LingerCap", now + Core.LINGER_VISIT_MAX_HOURS / 24.0)
    ElseIf now > visitCap
        Return true
    EndIf
    ; Only a conversation the player is part of keeps them (Core.IsTalkingWithPlayer says why).
    If Core.IsTalkingWithPlayer(target)
        Float stayUntil = now + LINGER_AFTER_TALK_HOURS / 24.0
        If until < stayUntil
            StorageUtil.SetFloatValue(target, "Intel_LingerUntil", stayUntil)
        EndIf
        Return false
    EndIf
    Return now > until
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
        ElseIf Core.FindSlotByAgent(target) >= 0
            ; They run a task of their own now, started by something that did not come through ForgetLinger.
            ; Its packages are theirs: only the linger is dropped.
            Core.DebugMsg(target.GetDisplayName() + " has a task of their own, linger dropped")
            ClearLingerSlot(target)
        Else
            Actor agent = StorageUtil.GetFormValue(target, "Intel_LingerAgent") as Actor
            Int phase = StorageUtil.GetIntValue(target, "Intel_LingerPhase", 0)

            If phase == 1
                ; Phase 1: NPC walking toward player.
                ; Switch to sandbox when within 100 units.
                Bool closeEnough = false
                Bool stillFar = true
                Float targetDist = -1.0
                If target.Is3DLoaded() && player.Is3DLoaded()
                    targetDist = target.GetDistance(player)
                    closeEnough = targetDist <= Core.LINGER_APPROACH_DISTANCE
                    stillFar = targetDist > Core.LINGER_RELEASE_DISTANCE
                ElseIf target.GetParentCell() == player.GetParentCell()
                    ; Same cell off-screen — close enough in interiors
                    Cell targetCell = target.GetParentCell()
                    stillFar = false
                    If targetCell != None && targetCell.IsInterior()
                        closeEnough = true
                    EndIf
                EndIf

                ; Near the player but getting no closer (a ledge, a locked gate, a crowd): they kept walking
                ; at whatever was in the way for as long as the player stayed around. After
                ; LINGER_APPROACH_MAX_HOURS they settle where they are.
                If !closeEnough && !stillFar && Utility.GetCurrentGameTime() > StorageUtil.GetFloatValue(target, "Intel_LingerUntil", 999999.0)
                    Core.DebugMsg(target.GetDisplayName() + " cannot get closer to the player, settling here")
                    closeEnough = true
                EndIf

                If closeEnough
                    ; Add sandbox BEFORE removing travel — no gap for default AI to kick in
                    PO3_SKSEFunctions.SetLinkedRef(target, player as ObjectReference, Core.IntelEngine_TravelTarget)
                    ActorUtil.AddPackageOverride(target, Core.SandboxNearPlayerPackage, Core.PRIORITY_TRAVEL, 1)
                    ActorUtil.RemovePackageOverride(target, Core.TravelPackage_Walk)
                    Utility.Wait(0.1)
                    target.EvaluatePackage()
                    StorageUtil.SetIntValue(target, "Intel_LingerPhase", 2)
                    StorageUtil.SetFloatValue(target, "Intel_LingerUntil", Utility.GetCurrentGameTime() + LINGER_VISIT_HOURS / 24.0)
                    Core.DebugMsg(target.GetDisplayName() + " reached player, sandboxing (phase 2)")
                ElseIf stillFar
                    ; Player still far during approach — keep incrementing far ticks
                    Int farTicks = StorageUtil.GetIntValue(target, "Intel_LingerFarTicks", 0) + 1
                    Float lastDist = StorageUtil.GetFloatValue(target, "Intel_LingerLastDist", -1.0)
                    ; The distance to beat is the one at the last step forward, not the one of the last pass:
                    ; while a task is returning the passes come every half second, a walking NPC covers
                    ; less than 50 units in that time, and was sent "heading back" after three of them.
                    If targetDist >= 0.0 && targetDist < lastDist - 50.0
                        farTicks = 0
                    EndIf
                    StorageUtil.SetIntValue(target, "Intel_LingerFarTicks", farTicks)
                    If farTicks == 0 || lastDist < 0.0
                        StorageUtil.SetFloatValue(target, "Intel_LingerLastDist", targetDist)
                    EndIf
                    If farTicks >= Core.LINGER_FAR_TICKS_LIMIT
                        ; Through the shared release (it only took the walk package off): the look-at and the
                        ; linked ref are cleared, and one with no routine of their own is walked home.
                        ActorUtil.RemovePackageOverride(target, Core.TravelPackage_Walk)
                        Core.ReleaseLinger(target)
                        Core.SendTransientEvent(target, agent, target.GetDisplayName() + " is heading back.")
                        Core.DebugMsg(target.GetDisplayName() + " player left during approach, heading home")
                        ClearLingerSlot(target)
                    EndIf
                EndIf

            ElseIf phase == 2
                ; Phase 2: NPC sandboxing near player.
                ; Release when player leaves proximity (same as Travel/StoryEngine), or when the visit has
                ; run its time (see LingerVisitIsOver).
                If Core.ShouldReleaseLinger(target) || LingerVisitIsOver(target)
                    Core.ReleaseLinger(target)
                    Core.SendTransientEvent(target, agent, target.GetDisplayName() + " is heading back.")
                    Core.DebugMsg(target.GetDisplayName() + " visit over, heading home")
                    ClearLingerSlot(target)
                EndIf

            ElseIf phase == 3
                ; Phase 3: Escort target waiting at destination for player
                ; Timeout after 6 game hours, otherwise check player proximity.
                ; Escorted without being asked to wait for the player: a short hold only (it keeps them from
                ; being pulled straight back by their routine), and no greeting when the player comes by.
                ; They used to get the full wait as well: six hours, and a walk over to a player they were
                ; never told to expect.
                Bool waitsForPlayer = StorageUtil.GetIntValue(target, "Intel_LingerNoGreet") != 1
                Float holdHours = 6.0
                If !waitsForPlayer
                    holdHours = ESCORT_HOLD_HOURS
                EndIf
                Float lingerStart = StorageUtil.GetFloatValue(target, "Intel_LingerStart")
                If lingerStart > 0.0 && (Utility.GetCurrentGameTime() - lingerStart) * 24.0 > holdHours
                    Core.DebugMsg(target.GetDisplayName() + " escort wait timed out")
                    Core.RemoveIntelPackages(target)
                    PO3_SKSEFunctions.SetLinkedRef(target, None, Core.IntelEngine_TravelTarget)
                    target.EvaluatePackage()
                    ClearLingerSlot(target)
                ElseIf waitsForPlayer
                    ; Check if player arrived at the destination
                    Bool playerArrived = false
                    If target.Is3DLoaded() && player.Is3DLoaded()
                        playerArrived = target.GetDistance(player) <= Core.ARRIVAL_DISTANCE * 2.0
                    ElseIf target.GetParentCell() == player.GetParentCell()
                        Cell pCell = player.GetParentCell()
                        If pCell != None && pCell.IsInterior()
                            playerArrived = true
                        EndIf
                    EndIf

                    If playerArrived
                        OnPlayerArrivedAtEscortTarget(target)
                    EndIf
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

Bool Function FetchNPC(Actor akAgent, String targetName, String failReason = "none", String taskOrigin = "SkyrimNet dialogue action")
    {
    Send an NPC to find another NPC and bring them back to the player.

    Parameters:
        akAgent - The NPC doing the fetching
        targetName - Name of NPC to fetch (fuzzy matched)
        failReason - "none" if target comes willingly, otherwise the refusal reason

    Returns:
        true if fetch task started successfully
    }

    ; Carriage drivers and children are never sent on errands (see Core.IsUnsuitableTaskAgent).
    If Core.IsUnsuitableTaskAgent(akAgent)
        If akAgent != None
            Core.DebugMsg("FetchNPC: " + akAgent.GetDisplayName() + " is not sent on tasks (carriage driver or child)")
        EndIf
        Return false
    EndIf

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
    Int confirmResult = Core.ShowTaskConfirmationForAction(akAgent, akAgent.GetDisplayName() + " wants to go fetch " + targetName + ".", "FetchPerson", taskOrigin)
    If confirmResult == 1
        Core.SendTaskNarration(akAgent, Game.GetPlayer().GetDisplayName() + " told " + akAgent.GetDisplayName() + " not to go fetch " + targetName + ".")
        Return false
    ElseIf confirmResult == 2
        Return false
    EndIf

    ; (The departure event and the override of the agent's current task come further down, once the task
    ; is known to be possible.)

    ; Cooldown — prevents narration-triggered re-selection loops.
    ; After a fetch completes, the completion narration can trigger a dialogue
    ; evaluation that re-selects FetchPerson before the NPC has time to rest.
    Float cooldown = StorageUtil.GetFloatValue(akAgent, "Intel_TaskCooldown")
    If cooldown > 0.0 && cooldown <= Utility.GetCurrentRealTime() && (Utility.GetCurrentRealTime() - cooldown) < 15.0
        Core.DebugMsg("FetchNPC: " + akAgent.GetDisplayName() + " on cooldown")
        Return false
    EndIf

    ; Find the target NPC using DLL fuzzy search
    Actor targetNPC = IntelEngine.FindNPCByNameNear(targetName, akAgent)
    If targetNPC == None
        ; NPC not found - describe the situation, let NPC decide their response
        String suggestion = GetNPCSuggestion(targetName)
        If suggestion != ""
            Core.SendTaskNarration(akAgent, targetName + " could not be found. The closest known name is " + suggestion + ".")
        Else
            Core.SendTaskNarration(akAgent, targetName + " could not be found.")
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

    ; Don't interrupt if the target is actively doing their own task
    Int existingSlot = Core.FindSlotByAgent(targetNPC)
    If existingSlot >= 0
        Core.DebugMsg("FetchNPC: " + targetNPC.GetDisplayName() + " is busy in slot " + existingSlot + " - cannot fetch")
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " tried to fetch " + targetNPC.GetDisplayName() + " but they are busy with another task.")
        Return false
    EndIf

    ; A carriage driver is not walked away from the cart: the return package pulls them off it like a task
    ; of their own would, and the carriage service is broken from then on (see Core.IsUnsuitableTaskAgent).
    If Core.IsCarriageDriver(targetNPC)
        Core.DebugMsg("FetchNPC: " + targetNPC.GetDisplayName() + " is a carriage driver - not fetched")
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " was asked to fetch " + targetNPC.GetDisplayName() + ", who cannot leave the carriage.")
        Return false
    EndIf

    ; A slot has to be there: a free one, or the one this agent's current task gives up.
    If Core.FindFreeAgentSlot() < 0 && Core.FindSlotByAgent(akAgent) < 0
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " cannot take on this task right now.")
        Return false
    EndIf

    ; Only now, with everything checked that can make the task impossible, is the departure announced and
    ; the task the agent already has called off. Both used to come right after the confirmation: an unknown
    ; name, a dead or busy target or the cooldown cancelled the running task, announced "left to fetch ..."
    ; and then did nothing.
    ; Register event AFTER confirmation (not in YAML — prevents event on deny silent)
    SkyrimNetApi.RegisterEvent("intel_task_event", akAgent.GetDisplayName() + " left to fetch " + targetName + " (task in progress)", akAgent, None)

    ; Override existing task if any
    Core.OverrideExistingTask(akAgent)

    ; Also cancel any pending schedule for the target
    If Core.Schedule
        Int schedSlot = Core.Schedule.FindScheduleSlotByAgent(targetNPC)
        If schedSlot >= 0
            Core.DebugMsg("FetchNPC: " + targetNPC.GetDisplayName() + " has scheduled task - cancelling")
            Core.Schedule.ClearScheduleSlot(schedSlot)
        EndIf
    EndIf

    ; Find free slot
    Int slot = Core.FindFreeAgentSlot()
    If slot < 0
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " cannot take on this task right now.")
        Return false
    EndIf

    ; Anti-trespass: unlock target NPC's home door so agent can enter
    Core.UnlockHomeForTask(akAgent, targetNPC)

    ; Destination is always the target actor directly
    ObjectReference destMarker = targetNPC

    ; Walk when player can see them, jog when off-screen. Decided here so that the slot records the speed
    ; that is really applied: it said "jog" for an agent who walked, and stuck recovery and a speed change
    ; then worked on the wrong package (a second travel override on top of the first).
    Int speed = 1
    If akAgent.GetParentCell() == Game.GetPlayer().GetParentCell()
        speed = 0
    EndIf

    ; Allocate slot (defaults to state 1)
    Core.AllocateSlot(slot, akAgent, "fetch_npc", targetNPC.GetDisplayName(), speed, taskOrigin)

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

    ; Asked in conversation: let them finish the sentence before they turn and go.
    If !WaitToSetOff(slot, akAgent, "fetch_npc", targetNPC)
        Return true
    EndIf

    ; Stop following if agent is follower. Only now, after the wait: done before it, a follower stood
    ; there for the length of the sentence with every package taken away.
    Core.DismissFollowerForTask(akAgent)

    ; Set up travel — agent pathfinds toward the target naturally.
    ; Works same-cell (player sees them walk) and cross-cell (engine AI handles it).
    ; Teleport is only a last-resort fallback via stuck recovery / game-time timeout.
    PO3_SKSEFunctions.SetLinkedRef(akAgent, destMarker, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(akAgent, Core.GetTravelPackage(speed), Core.PRIORITY_TRAVEL, 1)
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

    ; Fast-path proximity arrival at the target NPC (C++ ticks every 150ms).
    ; Default 200u actor threshold for face-to-face detection.
    IntelEngine.ArmProximityArrival(slot, akAgent as ObjectReference, targetNPC as ObjectReference, Self, "IntelEngine_NPCTasks", "OnProximityArrived")

    ; Start monitoring
    SetOffDone(akAgent)

    Return true
EndFunction

; =============================================================================
; DELIVER MESSAGE API
; =============================================================================

Bool Function DeliverMessage(Actor akAgent, String targetName, String msgContent, String meetLocation = "none", String meetTime = "none", String taskOrigin = "SkyrimNet dialogue action")
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

    ; Carriage drivers and children are never sent on errands (see Core.IsUnsuitableTaskAgent).
    If Core.IsUnsuitableTaskAgent(akAgent)
        If akAgent != None
            Core.DebugMsg("DeliverMessage: " + akAgent.GetDisplayName() + " is not sent on tasks (carriage driver or child)")
        EndIf
        Return false
    EndIf

    ; Validate
    If akAgent == None || akAgent.IsDead() || akAgent.IsInCombat()
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
    Int confirmResult = Core.ShowTaskConfirmationForAction(akAgent, akAgent.GetDisplayName() + " wants to deliver a message to " + targetName + ".", "DeliverMessage", taskOrigin)
    If confirmResult == 1
        Core.SendTaskNarration(akAgent, Game.GetPlayer().GetDisplayName() + " told " + akAgent.GetDisplayName() + " not to deliver the message.")
        Return false
    ElseIf confirmResult == 2
        Return false
    EndIf

    ; Cooldown — prevents narration-triggered re-selection loops
    Float cooldown = StorageUtil.GetFloatValue(akAgent, "Intel_TaskCooldown")
    If cooldown > 0.0 && cooldown <= Utility.GetCurrentRealTime() && (Utility.GetCurrentRealTime() - cooldown) < 15.0
        Core.DebugMsg("DeliverMessage: " + akAgent.GetDisplayName() + " on cooldown")
        Return false
    EndIf

    ; Find target
    Actor targetNPC = IntelEngine.FindNPCByNameNear(targetName, akAgent)
    If targetNPC == None
        ; NPC not found - provide "did you mean?" suggestion if available
        String suggestion = GetNPCSuggestion(targetName)
        Core.DebugMsg("DeliverMessage: recipient '" + targetName + "' was not found")
        If suggestion != ""
            Core.NotifyPlayer(targetName + " could not be found. The closest known name is " + suggestion + ".")
        Else
            Core.NotifyPlayer(targetName + " could not be found.")
        EndIf
        Return false
    EndIf

    If targetNPC.IsDead()
        Core.NotifyPlayer(akAgent.GetDisplayName() + " cannot deliver a message to " + targetNPC.GetDisplayName() + ", who is dead.")
        Return false
    EndIf

    If targetNPC.IsDisabled()
        Core.NotifyPlayer(akAgent.GetDisplayName() + " could not find " + targetNPC.GetDisplayName() + " to deliver the message.")
        Return false
    EndIf

    If targetNPC == akAgent
        Core.NotifyPlayer(akAgent.GetDisplayName() + " cannot deliver a message to themselves.")
        Return false
    EndIf

    If targetNPC == Game.GetPlayer()
        Core.NotifyPlayer(Game.GetPlayer().GetDisplayName() + " is already right here; no delivery task started.")
        Return false
    EndIf

    ; A slot has to be there: a free one, or the one this agent's current task gives up. Checked before
    ; that task is called off: with no slot to be had it was cancelled for nothing.
    If Core.FindFreeAgentSlot() < 0 && Core.FindSlotByAgent(akAgent) < 0
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " cannot take on this task right now.")
        Return false
    EndIf

    ; Only replace an existing task once the requested recipient is valid.
    Core.OverrideExistingTask(akAgent)

    ; Find slot
    Int slot = Core.FindFreeAgentSlot()
    If slot < 0
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " cannot take on this task right now.")
        Return false
    EndIf

    ; Anti-trespass: unlock target NPC's home door so agent can enter
    Core.UnlockHomeForTask(akAgent, targetNPC)

    ; Destination is always the target actor directly.
    ; Skyrim's AI pathfinding handles cross-cell Actor targets natively.
    ObjectReference destMarker = targetNPC

    ; Walk when player can see them, jog when off-screen. Decided here so that the slot records the speed
    ; that is really applied (see FetchNPC).
    Int speed = 1
    If akAgent.GetParentCell() == Game.GetPlayer().GetParentCell()
        speed = 0
    EndIf

    ; Allocate
    Core.AllocateSlot(slot, akAgent, "deliver_message", targetNPC.GetDisplayName(), speed, taskOrigin)
    SkyrimNetApi.RegisterEvent("intel_task_event", akAgent.GetDisplayName() + " left to deliver a message to " + targetName + " (task in progress)", akAgent, None)

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

    ; Asked in conversation: let them finish the sentence before they turn and go.
    If !WaitToSetOff(slot, akAgent, "deliver_message", targetNPC)
        Return true
    EndIf

    ; Stop following. Only now, after the wait (see FetchNPC).
    Core.DismissFollowerForTask(akAgent)

    ; Set up travel — agent pathfinds toward the target naturally.
    PO3_SKSEFunctions.SetLinkedRef(akAgent, destMarker, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(akAgent, Core.GetTravelPackage(speed), Core.PRIORITY_TRAVEL, 1)
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

    ; Fast-path proximity arrival at the message recipient.
    IntelEngine.ArmProximityArrival(slot, akAgent as ObjectReference, targetNPC as ObjectReference, Self, "IntelEngine_NPCTasks", "OnProximityArrived")

    SetOffDone(akAgent)

    Return true
EndFunction

; =============================================================================
; SEARCH FOR ACTOR API
; =============================================================================

Bool Function SearchForActor(Actor akAgent, String targetName, Int speed = 0, String taskOrigin = "SkyrimNet dialogue action")
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

    ; Carriage drivers and children are never sent on errands (see Core.IsUnsuitableTaskAgent).
    If Core.IsUnsuitableTaskAgent(akAgent)
        If akAgent != None
            Core.DebugMsg("SearchForActor: " + akAgent.GetDisplayName() + " is not sent on tasks (carriage driver or child)")
        EndIf
        Return false
    EndIf

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
    Int confirmResult = Core.ShowTaskConfirmationForAction(akAgent, akAgent.GetDisplayName() + " wants to help search for " + targetName + ".", "SearchForActor", taskOrigin)
    If confirmResult == 1
        Core.SendTaskNarration(akAgent, Game.GetPlayer().GetDisplayName() + " told " + akAgent.GetDisplayName() + " not to search for " + targetName + ".")
        Return false
    ElseIf confirmResult == 2
        Return false
    EndIf

    ; (The event and the override of the agent's current task come further down, once the task is known to
    ; be possible: see FetchNPC.)

    ; Cooldown — prevents narration-triggered re-selection loops
    Float cooldown = StorageUtil.GetFloatValue(akAgent, "Intel_TaskCooldown")
    If cooldown > 0.0 && cooldown <= Utility.GetCurrentRealTime() && (Utility.GetCurrentRealTime() - cooldown) < 15.0
        Core.DebugMsg("SearchForActor: " + akAgent.GetDisplayName() + " on cooldown")
        Return false
    EndIf

    ; Find the target NPC
    Actor targetNPC = IntelEngine.FindNPCByNameNear(targetName, akAgent)
    If targetNPC == None
        String suggestion = GetNPCSuggestion(targetName)
        If suggestion != ""
            Core.SendTaskNarration(akAgent, targetName + " could not be found. The closest known name is " + suggestion + ".")
        Else
            Core.SendTaskNarration(akAgent, targetName + " could not be found.")
        EndIf
        Return false
    EndIf

    If targetNPC.IsDead()
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " was asked to help find " + targetNPC.GetDisplayName() + ", who is dead.")
        Return false
    EndIf

    If targetNPC.IsDisabled()
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " could not find " + targetNPC.GetDisplayName() + ".")
        Return false
    EndIf

    If targetNPC == akAgent
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " was asked to help find themselves.")
        Return false
    EndIf

    If targetNPC == Game.GetPlayer()
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " was asked to help find " + Game.GetPlayer().GetDisplayName() + ", who is already right here.")
        Return false
    EndIf

    ; A slot has to be there: a free one, or the one this agent's current task gives up.
    If Core.FindFreeAgentSlot() < 0 && Core.FindSlotByAgent(akAgent) < 0
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " cannot take on this task right now.")
        Return false
    EndIf

    ; Register event AFTER confirmation (not in YAML — prevents event on deny silent)
    SkyrimNetApi.RegisterEvent("intel_task_event", akAgent.GetDisplayName() + " is searching for " + targetName, akAgent, None)

    ; Override existing task if any
    Core.OverrideExistingTask(akAgent)

    ; Find free slot
    Int slot = Core.FindFreeAgentSlot()
    If slot < 0
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " cannot take on this task right now.")
        Return false
    EndIf

    ; Anti-trespass: unlock target NPC's home door so agent can enter
    Core.UnlockHomeForTask(akAgent, targetNPC)

    ; Destination is always the target actor directly.
    ; Skyrim's AI pathfinding handles cross-cell Actor targets natively.
    ObjectReference destMarker = targetNPC

    ; Allocate slot
    Core.AllocateSlot(slot, akAgent, "search_for_actor", targetNPC.GetDisplayName(), speed, taskOrigin)

    ; A search had no time limit at all (the distance-based deadline is not used: the pace is the
    ; player's). This one is only the last resort for a search that nothing else brings to an end.
    Core.SetSlotDeadline(slot, Utility.GetCurrentGameTime() + SEARCH_MAX_HOURS / 24.0)

    ; Store search-specific data
    StorageUtil.SetFormValue(akAgent, "Intel_TargetNPC", targetNPC)
    StorageUtil.SetFormValue(akAgent, "Intel_DestMarker", destMarker)

    ; Assign target alias
    ReferenceAlias targetAlias = Core.GetTargetAlias(slot)
    If targetAlias
        targetAlias.ForceRefTo(targetNPC)
    EndIf

    ; Asked in conversation: let them finish the sentence before they turn and go.
    If !WaitToSetOff(slot, akAgent, "search_for_actor", targetNPC)
        Return true
    EndIf

    ; Stop following if agent is follower. Only now, after the wait (see FetchNPC).
    Core.DismissFollowerForTask(akAgent)

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

    ; Fast-path proximity arrival at the search target.
    IntelEngine.ArmProximityArrival(slot, akAgent as ObjectReference, targetNPC as ObjectReference, Self, "IntelEngine_NPCTasks", "OnProximityArrived")

    ; Start monitoring
    SetOffDone(akAgent)

    Return true
EndFunction

; =============================================================================
; ESCORT TARGET — Walk target NPC to a destination
; =============================================================================

Bool Function EscortTarget(Actor akAgent, String targetName, String destination = "home", Int shouldWait = 0, String taskOrigin = "SkyrimNet dialogue action")
    {
    Send an NPC to escort another NPC to a destination.

    Parameters:
        akAgent - The NPC doing the escorting
        targetName - Name of NPC to escort (fuzzy matched)
        destination - Where to escort them ("home", or a location name like "Whiterun")
        shouldWait - 1 if the target should wait at destination for player arrival, 0 otherwise

    Returns:
        true if escort task started successfully
    }

    ; Carriage drivers and children are never sent on errands (see Core.IsUnsuitableTaskAgent).
    If Core.IsUnsuitableTaskAgent(akAgent)
        If akAgent != None
            Core.DebugMsg("EscortTarget: " + akAgent.GetDisplayName() + " is not sent on tasks (carriage driver or child)")
        EndIf
        Return false
    EndIf

    ; Normalize destination
    If destination == ""
        destination = "home"
    EndIf
    String destLabel = destination

    ; Validate agent
    If akAgent == None
        Core.DebugMsg("EscortTarget: None agent")
        Return false
    EndIf

    If akAgent.IsDead() || akAgent.IsInCombat()
        Core.DebugMsg("EscortTarget: Agent dead or in combat")
        Return false
    EndIf

    ; Duplicate action guard
    If Core.IsDuplicateTask(akAgent, "escort_target", targetName)
        Return false
    EndIf

    ; MCM task confirmation prompt
    Int confirmResult = Core.ShowTaskConfirmationForAction(akAgent, akAgent.GetDisplayName() + " wants to escort " + targetName + " to " + destLabel + ".", "EscortTarget", taskOrigin)
    If confirmResult == 1
        Core.SendTaskNarration(akAgent, Game.GetPlayer().GetDisplayName() + " told " + akAgent.GetDisplayName() + " not to escort " + targetName + ".")
        Return false
    ElseIf confirmResult == 2
        Return false
    EndIf

    ; (The departure event and the override of the agent's current task come further down, once the task
    ; is known to be possible: see FetchNPC.)

    ; Cooldown
    Float cooldown = StorageUtil.GetFloatValue(akAgent, "Intel_TaskCooldown")
    If cooldown > 0.0 && cooldown <= Utility.GetCurrentRealTime() && (Utility.GetCurrentRealTime() - cooldown) < 15.0
        Core.DebugMsg("EscortTarget: " + akAgent.GetDisplayName() + " on cooldown")
        Return false
    EndIf

    ; Find the target NPC using DLL fuzzy search
    Actor targetNPC = IntelEngine.FindNPCByNameNear(targetName, akAgent)
    If targetNPC == None
        String suggestion = GetNPCSuggestion(targetName)
        If suggestion != ""
            Core.SendTaskNarration(akAgent, targetName + " could not be found. The closest known name is " + suggestion + ".")
        Else
            Core.SendTaskNarration(akAgent, targetName + " could not be found.")
        EndIf
        Return false
    EndIf

    ; Check if target is valid
    If targetNPC.IsDead()
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " was asked to escort " + targetNPC.GetDisplayName() + " to " + destLabel + ", but they are dead.")
        Return false
    EndIf

    If targetNPC.IsDisabled()
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " could not find " + targetNPC.GetDisplayName() + ".")
        Return false
    EndIf

    If targetNPC == akAgent
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " was asked to escort themselves.")
        Return false
    EndIf

    If targetNPC == Game.GetPlayer()
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " was asked to escort " + Game.GetPlayer().GetDisplayName() + ".")
        Return false
    EndIf

    ; Cancel any existing task where the target is the AGENT — don't cancel if
    ; they're already doing their own task (e.g., escorting someone else).
    ; FindSlotByAgent checks if they're the primary actor in a slot.
    Int existingSlot = Core.FindSlotByAgent(targetNPC)
    If existingSlot >= 0
        ; Target is actively doing a task — don't interrupt, reject this escort instead
        Core.DebugMsg("EscortTarget: " + targetNPC.GetDisplayName() + " is busy in slot " + existingSlot + " - cannot escort")
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " tried to escort " + targetNPC.GetDisplayName() + " but they are busy with another task.")
        Return false
    EndIf

    ; A carriage driver is not walked away from the cart (see FetchNPC).
    If Core.IsCarriageDriver(targetNPC)
        Core.DebugMsg("EscortTarget: " + targetNPC.GetDisplayName() + " is a carriage driver - not escorted")
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " was asked to escort " + targetNPC.GetDisplayName() + ", who cannot leave the carriage.")
        Return false
    EndIf

    ; Resolve destination
    ObjectReference destMarkerRef
    If destination == "home"
        destMarkerRef = IntelEngine.ResolveAnyDestination(targetNPC, "home")
        If destMarkerRef == None
            Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " could not figure out where " + targetNPC.GetDisplayName() + " lives.")
            Return false
        EndIf
    Else
        destMarkerRef = IntelEngine.ResolveAnyDestination(akAgent, destination)
        If destMarkerRef == None
            Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " does not know where " + destination + " is.")
            Return false
        EndIf
    EndIf

    ; Check if target is already at destination
    If targetNPC.Is3DLoaded() && destMarkerRef.Is3DLoaded()
        If targetNPC.GetDistance(destMarkerRef) <= Core.ARRIVAL_DISTANCE
            Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " was asked to escort " + targetNPC.GetDisplayName() + " to " + destLabel + ", but they are already there.")
            Return false
        EndIf
    EndIf

    ; A slot has to be there: a free one, or the one this agent's current task gives up.
    If Core.FindFreeAgentSlot() < 0 && Core.FindSlotByAgent(akAgent) < 0
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " cannot take on this task right now.")
        Return false
    EndIf

    ; Only now is the departure announced, the agent's current task called off and the target's schedule
    ; cancelled (see FetchNPC). An unknown destination used to leave all three done and no escort.
    ; Register event AFTER confirmation (not in YAML — prevents event on deny silent)
    SkyrimNetApi.RegisterEvent("intel_task_event", akAgent.GetDisplayName() + " left to escort " + targetName + " to " + destLabel + " (task in progress)", akAgent, None)

    ; Override existing task if any
    Core.OverrideExistingTask(akAgent)

    ; Cancel pending schedule for the target
    If Core.Schedule
        Int schedSlot = Core.Schedule.FindScheduleSlotByAgent(targetNPC)
        If schedSlot >= 0
            Core.DebugMsg("EscortTarget: " + targetNPC.GetDisplayName() + " has scheduled task -- cancelling")
            Core.Schedule.ClearScheduleSlot(schedSlot)
        EndIf
    EndIf

    ; Find free slot
    Int slot = Core.FindFreeAgentSlot()
    If slot < 0
        Core.SendTaskNarration(akAgent, akAgent.GetDisplayName() + " cannot take on this task right now.")
        Return false
    EndIf

    ; Anti-trespass: unlock destination so both can enter
    If destination == "home"
        Core.UnlockHomeForTask(akAgent, targetNPC)
    EndIf

    ; Walk when player can see them, jog when off-screen. Decided here so that the slot records the speed
    ; that is really applied (see FetchNPC).
    Int speed = 1
    If akAgent.GetParentCell() == Game.GetPlayer().GetParentCell()
        speed = 0
    EndIf

    ; Allocate slot
    Core.AllocateSlot(slot, akAgent, "escort_target", targetNPC.GetDisplayName(), speed, taskOrigin)

    ; Store escort-specific data
    StorageUtil.SetFormValue(akAgent, "Intel_TargetNPC", targetNPC)
    StorageUtil.SetFormValue(akAgent, "Intel_DestMarker", targetNPC as ObjectReference)
    StorageUtil.SetFormValue(akAgent, "Intel_ReturnMarker", destMarkerRef)
    StorageUtil.SetStringValue(akAgent, "Intel_EscortDestName", destLabel)
    If shouldWait == 1
        StorageUtil.SetIntValue(akAgent, "Intel_EscortShouldWait", 1)
    EndIf

    ; Assign target alias
    ReferenceAlias targetAlias = Core.GetTargetAlias(slot)
    If targetAlias
        targetAlias.ForceRefTo(targetNPC)
    EndIf

    ; Asked in conversation: let them finish the sentence before they turn and go.
    If !WaitToSetOff(slot, akAgent, "escort_target", targetNPC)
        Return true
    EndIf

    ; Stop following if agent is follower. Only now, after the wait (see FetchNPC).
    Core.DismissFollowerForTask(akAgent)

    ; Set up travel to the target NPC (may be nearby, may be across town)
    PO3_SKSEFunctions.SetLinkedRef(akAgent, targetNPC as ObjectReference, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(akAgent, Core.GetTravelPackage(speed), Core.PRIORITY_TRAVEL, 1)
    Utility.Wait(0.1)
    akAgent.EvaluatePackage()

    Core.DebugMsg("EscortTarget: " + akAgent.GetDisplayName() + " going to " + targetNPC.GetDisplayName() + " to escort them to " + destLabel)
    Core.NotifyPlayer(akAgent.GetDisplayName() + " is going to escort " + targetNPC.GetDisplayName() + " to " + destLabel)

    ; Initialize tracking
    Core.InitializeStuckTrackingForSlot(slot, akAgent)
    Core.InitializeDepartureTracking(slot, akAgent)
    Core.InitOffScreenTracking(slot, akAgent, targetNPC)

    ; One-way deadline (not round trip)
    SetDistanceBasedDeadline(slot, akAgent, destMarkerRef, false)

    ; Fast-path proximity arrival at the target NPC (pickup phase).
    IntelEngine.ArmProximityArrival(slot, akAgent as ObjectReference, targetNPC as ObjectReference, Self, "IntelEngine_NPCTasks", "OnProximityArrived")

    ; Start monitoring
    SetOffDone(akAgent)

    Return true
EndFunction

Bool Function WaitToSetOff(Int slot, Actor akAgent, String taskType, Actor targetNPC)
    {A task given in conversation: let the agent finish the sentence before they turn and go (latent, see
    Core.LetFinishSpeaking). False when the task is no longer theirs afterwards: cancelled, replaced, or
    its slot handed to another task.
    The monitoring loop leaves the slot alone for the length of the wait (CheckNPCTaskSlot). It used to run
    on it: with the trackers of the slot's previous task still in place it could call the departure a
    failure, or find the agent already at the target and move the task on, after which the travel package
    put on here walked them away from it again. The mark is a real-time stamp, so one that is left behind
    (the game closed during the wait) runs out by itself. The caller takes it off (SetOffDone) once the
    package is on and the trackers are fresh.}
    StorageUtil.SetFloatValue(akAgent, "Intel_SettingOffUntil", Utility.GetCurrentRealTime() + Core.SPEECH_GRACE_SECONDS + 5.0)
    Core.LetFinishSpeaking(akAgent)
    If Core.FindSlotByAgent(akAgent) != slot || Core.SlotTaskTypes[slot] != taskType || Core.SlotStates[slot] != 1 \
        || StorageUtil.GetFormValue(akAgent, "Intel_TargetNPC") != (targetNPC as Form)
        ; The mark is left as it is: it may be the one of the task that replaced this one.
        Core.DebugMsg(akAgent.GetDisplayName() + ": task replaced or cancelled before setting off")
        Return false
    EndIf
    Return true
EndFunction

Function SetOffDone(Actor akAgent)
    {The agent is on the way: monitoring takes over (see WaitToSetOff).}
    StorageUtil.UnsetFloatValue(akAgent, "Intel_SettingOffUntil")
    Core.RequestTick(Core.UPDATE_INTERVAL)
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
        If Core.SlotStates[i] != 0 && IsNPCTaskType(taskType)
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
            Core.RequestTick(RETURN_POLL_INTERVAL)
        Else
            Core.RequestTick(Core.UPDATE_INTERVAL)
        EndIf
    EndIf

    ; Now process slots — if this errors out, the next update is already scheduled
    i = 0
    While i < Core.MAX_SLOTS
        String taskType = Core.SlotTaskTypes[i]
        If Core.SlotStates[i] != 0 && IsNPCTaskType(taskType)
            CheckNPCTaskSlot(i)
        EndIf
        i += 1
    EndWhile

    ; Check if any lingering targets should head home
    CheckLingeringTargets()
EndEvent

; Callback invoked by the C++ ProximityMonitor the instant the armed agent
; enters range of its current target. Hands off to CheckNPCTaskSlot so the
; same state machine as the 3s poll evaluates arrival — arming covers
; outbound-to-target (state 1) and returning-with-target (state 3).
Function OnProximityArrived(String slotStr)
    Int slot = slotStr as Int
    If slot < 0 || slot >= Core.MAX_SLOTS
        Return
    EndIf
    If Core.SlotStates[slot] == 0
        Return
    EndIf
    String tt = Core.SlotTaskTypes[slot]
    If !IsNPCTaskType(tt)
        Return
    EndIf
    CheckNPCTaskSlot(slot)
EndFunction

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

    ; Still finishing the sentence the task was given in (WaitToSetOff): nothing to monitor yet.
    Float settingOffUntil = StorageUtil.GetFloatValue(agent, "Intel_SettingOffUntil", 0.0)
    If settingOffUntil > 0.0
        Float nowReal = Utility.GetCurrentRealTime()
        If nowReal < settingOffUntil && settingOffUntil - nowReal < 30.0
            Return
        EndIf
        ; Run out, or from before the game was restarted (the real-time clock starts again at zero).
        StorageUtil.UnsetFloatValue(agent, "Intel_SettingOffUntil")
    EndIf

    ; Game-time timeout — distance-based deadline set at task start.
    ; Catches off-screen stuck NPCs that position-based detection can't reach.
    ; (A search has one too now: its overall limit, or the limit of a wait for the player.)
    Float deadline = Core.SlotDeadlines[slot]
    If deadline > 0.0 && Utility.GetCurrentGameTime() > deadline
        Float startTime = StorageUtil.GetFloatValue(agent, "Intel_TaskStartTime")
        Float elapsedHours = (Utility.GetCurrentGameTime() - startTime) * 24.0
        Core.DebugMsg("Task deadline reached (" + elapsedHours + "h) for " + agent.GetDisplayName() + " - force-completing")
        HandleTaskTimeout(slot, agent, taskType, taskState)
        Return
    EndIf

    If taskType == "fetch_npc"
        HandleFetchState(slot, agent, taskState)
    ElseIf taskType == "deliver_message"
        HandleMessageState(slot, agent, taskState)
    ElseIf taskType == "search_for_actor"
        HandleSearchState(slot, agent, taskState)
    ElseIf taskType == "escort_target"
        HandleEscortTargetState(slot, agent, taskState)
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

    ; A search that ran out of time (overall, or waiting for a player who never caught up) ends where the
    ; agent stands: there is nobody to be teleported to.
    If taskType == "search_for_actor"
        GiveUpSearch(slot, agent)
        Return
    EndIf

    ; Get destination and target based on task type + state
    ObjectReference dest
    Actor target = StorageUtil.GetFormValue(agent, "Intel_TargetNPC") as Actor

    If (taskType == "fetch_npc" && taskState == 3) || (taskType == "escort_target" && taskState == 3)
        dest = StorageUtil.GetFormValue(agent, "Intel_ReturnMarker") as ObjectReference
    Else
        dest = StorageUtil.GetFormValue(agent, "Intel_DestMarker") as ObjectReference
    EndIf

    ; If the player can see the agent, don't teleport.
    ; State 8 (at target): interaction cycles stuck — force-complete them.
    ; State 3 (returning): task nearly done — complete instead of canceling.
    ; Other states: narrate failure and cancel.
    If agent.Is3DLoaded()
        ; State 8: agent found the target but interaction cycles are stuck.
        ; Force-complete by zeroing cycles and calling the task handler directly.
        If taskState == Core.STATE_AT_TARGET && target != None && !target.IsDead()
            Core.DebugMsg(agent.GetDisplayName() + " interaction timed out while visible - force-completing")
            StorageUtil.SetIntValue(agent, "Intel_InteractCyclesRemaining", 0)
            If taskType == "fetch_npc"
                HandleAtTarget(slot, agent, target)
            ElseIf taskType == "deliver_message"
                HandleAtTarget_Message(slot, agent, target)
            ElseIf taskType == "escort_target"
                HandleAtTarget_Escort(slot, agent, target)
            EndIf
            ; The handler moved the task on to its next leg. This return used to skip the re-arming at the
            ; end of the function, so the rest of the task ran with no time limit at all.
            RearmDeadlineAfterTimeout(slot, agent)
            Return
        EndIf
        ; State 3: task nearly done — complete instead of canceling
        If taskState == 3 && target != None && !target.IsDead()
            If taskType == "fetch_npc"
                Core.DebugMsg(agent.GetDisplayName() + " fetch timed out while returning - completing")
                OnReturnedWithTarget(slot, agent, target)
                Return
            ElseIf taskType == "escort_target"
                Core.DebugMsg(agent.GetDisplayName() + " escort timed out while walking - completing")
                OnEscortComplete(slot, agent, target, false)
                Return
            EndIf
        EndIf
        Core.DebugMsg(agent.GetDisplayName() + " timed out while visible - narrating cancel")
        Actor player = Game.GetPlayer()
        Core.SendTaskNarration(agent, agent.GetDisplayName() + " " + IntelEngine.BuildStuckNarration(taskType), player)
        Core.RemoveIntelPackages(agent)
        Core.ClearSlot(slot, true)
        ; Wherever the errand had taken them: one with no routine of their own is walked home.
        Core.ReleaseLinger(agent)
        Return
    EndIf

    ; Off-screen — teleport silently to destination
    Bool isReturning = (taskState == 3 && (taskType == "fetch_npc" || taskType == "deliver_message"))
    If isReturning
        PlaceNearPlayerUnseen(agent)
    ElseIf taskType == "escort_target" && taskState == 3 && dest != None
        ; Escort: teleport both to destination (not to player)
        agent.MoveTo(dest)
        If target != None && !target.IsDead()
            target.MoveTo(dest)
        EndIf
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
    ElseIf taskType == "escort_target"
        If target == None || target.IsDead()
            Core.ClearSlot(slot, true)
            Return
        EndIf
        If taskState == 1 || taskState == Core.STATE_AT_TARGET
            OnArrivedAtTarget(slot, agent, target)
        ElseIf taskState == 3
            OnEscortComplete(slot, agent, target, dest != None)
        Else
            Core.ClearSlot(slot, true)
        EndIf
    Else
        Core.ClearSlot(slot, true)
    EndIf

    RearmDeadlineAfterTimeout(slot, agent)
EndFunction

Function RearmDeadlineAfterTimeout(Int slot, Actor agent)
    {If the handler transitioned to a non-terminal state (e.g. state 1 → 8
    or state 1 → 3), set a new deadline for the remaining work. The original
    deadline was cleared in HandleTaskTimeout to prevent re-triggering during
    interaction cycles, but the return trip still needs a safety net.}
    If Core.SlotStates[slot] != 0 && Core.SlotDeadlines[slot] == 0.0 && Core.SlotHolds(slot, agent)
        Float returnDeadline = Utility.GetCurrentGameTime() + (MAX_TASK_HOURS / 2.0 / 24.0)
        Core.SetSlotDeadline(slot, returnDeadline)
        Core.DebugMsg("Set return deadline for " + agent.GetDisplayName() + " (" + (MAX_TASK_HOURS / 2.0) + "h)")
    EndIf
EndFunction

Function PlaceNearPlayerUnseen(Actor npc, Float distance = 2000.0, Bool evenIfInside = false)
    {Last-resort placement of an NPC who is on the way to the player and is not getting there.
    Outdoors: behind the player, as before. Indoors a point behind the player is on the far side of a wall
    (at 2000 units, outside the building's shell, where the NPC stayed): they are put at the door of the
    player's cell instead, as if they had just come in. One who is in that cell already is left to walk the
    rest, unless evenIfInside says they are stuck in there.}
    Actor player = Game.GetPlayer()
    Cell playerCell = player.GetParentCell()
    If playerCell != None && playerCell.IsInterior()
        If evenIfInside || npc.GetParentCell() != playerCell
            Core.PlaceForUnseenArrival(npc, player as ObjectReference)
        EndIf
        Return
    EndIf
    Core.TeleportBehindPlayer(npc, distance)
EndFunction

Function GiveUpSearch(Int slot, Actor agent)
    {The search is over without the target: in character, and without moving anybody.}
    String agentName = agent.GetDisplayName()
    String targetName = Core.SlotTargetNames[slot]
    Actor player = Game.GetPlayer()
    Core.DebugMsg(agentName + " gave up the search for " + targetName)
    If agent.Is3DLoaded() && agent.GetParentCell() == player.GetParentCell()
        Core.SendTaskNarration(agent, agentName + " gave up the search for " + targetName + ".", player)
    Else
        Core.SendTransientEvent(agent, player, agentName + " gave up the search for " + targetName + ".")
    EndIf
    Core.NotifyPlayer(agentName + " gave up the search for " + targetName)
    StorageUtil.SetStringValue(agent, "Intel_Result", "gave_up")
    Core.ClearSlotRestoreFollower(slot, agent)
    ; Out on the road somewhere: one with no routine of their own is walked home.
    Core.ReleaseLinger(agent)
EndFunction

; =============================================================================
; FETCH NPC STATE MACHINE
; =============================================================================

Function HandleFetchState(Int slot, Actor agent, Int taskState)
    Actor target = StorageUtil.GetFormValue(agent, "Intel_TargetNPC") as Actor

    ; (Disabled counts as gone: a target switched off by a quest was "reached", given travel packages and,
    ; when it did not come, moved to the player while still disabled.)
    If target == None || target.IsDead() || target.IsDisabled()
        Core.NotifyPlayer(agent.GetDisplayName() + " could not find their target")
        Core.ClearSlot(slot, true)
        Core.ReleaseLinger(agent)
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
        If dist <= IntelEngine.GetArrivalThreshold(agent, target as ObjectReference)
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

    ; Off-screen: same INTERIOR cell means the agent pathfound to the target
    ; naturally. Exterior cells are too large — two actors in the same Tamriel
    ; cell can be 4000+ units apart. Let HandleOffScreenTravel estimate arrival.
    Cell agentCell = agent.GetParentCell()
    If agentCell != None && agentCell.IsInterior() && agentCell == target.GetParentCell()
        Core.DebugMsg("[diag:arrival] " + agent.GetDisplayName() + " reached target cell " + IntelEngine.DescribeDistance(agent, target))
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
        Core.DebugMsg(agent.GetDisplayName() + " OnArrivedAtTarget ignored - state " + currentState + " (expected 1 or 8)")
        Return
    EndIf

    Core.DebugMsg("[diag:arrival] " + agent.GetDisplayName() + " reached " + target.GetDisplayName() + " " + IntelEngine.DescribeDistance(agent, target))

    ; Remove travel package, apply sandbox near target to hold agent in place
    ; during interaction. Without this, NPCs with schedule AI (innkeepers, etc.)
    ; revert to default packages and walk home before interaction completes.
    If agent.Is3DLoaded() && target.Is3DLoaded()
        Core.RemoveIntelPackages(agent, false)
        PO3_SKSEFunctions.SetLinkedRef(agent, target as ObjectReference, Core.IntelEngine_TravelTarget)
        ActorUtil.AddPackageOverride(agent, Core.SandboxNearPlayerPackage, Core.PRIORITY_SANDBOX, 1)
        agent.EvaluatePackage()
        StorageUtil.UnsetIntValue(agent, "Intel_ArrivedUnseen")
    Else
        ; Arrived unseen: nothing is swapped and nothing is evaluated. The travel package they carry has the
        ; target as its goal, so it keeps them there for the moment the handover takes. Swapping it for a
        ; sandbox and evaluating an NPC who is not loaded sent them to their own routine on the spot (and a
        ; sandbox around a ref that is not loaded can crash the engine, see Travel.OnArrival).
        StorageUtil.SetIntValue(agent, "Intel_ArrivedUnseen", 1)
    EndIf

    ; Face the target for immersive conversation
    agent.SetLookAt(target)

    ; Single interaction cycle — just enough for a brief pause before
    ; the task handler fires the narration and transitions to the next phase.
    ; Multiple cycles cause noticeable delays because monitoring ticks run
    ; at 3.0s intervals and can be slower under VM load.
    StorageUtil.SetIntValue(agent, "Intel_InteractCyclesRemaining", 1)
    Core.SetSlotState(slot, agent, Core.STATE_AT_TARGET)

    Core.DebugMsg(agent.GetDisplayName() + " interacting with " + target.GetDisplayName() + " for 1 cycle")
EndFunction

; -----------------------------------------------------------------------------
; TELEPORT FALLBACK (last-resort for stuck recovery / timeout only)
; -----------------------------------------------------------------------------

Function TeleportAgentToTarget(Int slot, Actor agent, Actor target)
    ; Remove packages before teleport
    Core.RemoveIntelPackages(agent)
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

Bool Function LetLineFinish(Int slot, Actor agent, Actor speaker)
    {At the target, with the player looking on, after a line has been narrated: wait until it has been said
    before the next step puts the travel packages on. The step used to follow at once, and both turned and
    walked off in the middle of the sentence. Latent: the interaction counter is set high for the wait, so
    the monitoring pass that comes meanwhile does not run the same step a second time. False when the task
    ended or moved on during the wait.}
    StorageUtil.SetIntValue(agent, "Intel_InteractCyclesRemaining", 1000)
    ; A narrated line starts a moment after it was asked for.
    Utility.Wait(1.5)
    Core.LetFinishSpeaking(speaker)
    Return Core.SlotHolds(slot, agent) && Core.SlotStates[slot] == Core.STATE_AT_TARGET
EndFunction

Function HandleAtTarget(Int slot, Actor agent, Actor target)
    Int remaining = StorageUtil.GetIntValue(agent, "Intel_InteractCyclesRemaining")
    remaining -= 1
    StorageUtil.SetIntValue(agent, "Intel_InteractCyclesRemaining", remaining)

    If remaining > 0
        ; Still "conversing" — wait
        Return
    EndIf
    ; From here to the change of state there are waits. The counter is set high so that a monitoring pass
    ; arriving in one of them (they come every half second while another task is returning) does not run
    ; this step a second time.
    StorageUtil.SetIntValue(agent, "Intel_InteractCyclesRemaining", 1000)

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
        ; Let the line be said before the two of them turn and go.
        If !LetLineFinish(slot, agent, agent)
            Return
        EndIf
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
        ; Let the refusal be said before the agent turns and leaves.
        If !LetLineFinish(slot, agent, target)
            Return
        EndIf
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

    ; Remove sandbox from OnArrivedAtTarget before adding travel
    Core.RemoveIntelPackages(agent, false)

    ; Set up walk back to player
    ObjectReference returnMarker = player
    StorageUtil.SetFormValue(agent, "Intel_ReturnMarker", returnMarker)
    PO3_SKSEFunctions.SetLinkedRef(agent, returnMarker, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(agent, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
    Core.SetSlotSpeed(slot, agent, 0)   ; the slot's speed is the package that is on them (walk)
    Utility.Wait(0.1)
    agent.EvaluatePackage()

    Core.SetSlotState(slot, agent, 3)  ; returning (alone)
    Core.InitializeStuckTrackingForSlot(slot, agent)

    ; Re-arm proximity on agent→player (agent returns alone after refusal).
    IntelEngine.ArmProximityArrival(slot, agent as ObjectReference, player as ObjectReference, Self, "IntelEngine_NPCTasks", "OnProximityArrived")

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

    ; Remove sandbox from OnArrivedAtTarget before adding travel packages
    Core.RemoveIntelPackages(agent, false)

    ; A target who is still lingering from an earlier fetch or escort: that visit ends here (see ForgetLinger).
    ForgetLinger(target)

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
    Core.SetSlotSpeed(slot, agent, 0)   ; the slot's speed is the package that is on them (walk)
    Utility.Wait(0.1)
    agent.EvaluatePackage()

    StorageUtil.SetIntValue(agent, "Intel_ReturnCycles", 0)
    Core.SetSlotState(slot, agent, 3)  ; returning
    Core.InitializeStuckTrackingForSlot(slot, agent)

    ; Re-arm proximity: target-first completion means the fetched NPC
    ; reaching the player IS the completion event. Arming on target lets
    ; the C++ fast path fire completion the instant the target walks up,
    ; no matter where the agent is.
    IntelEngine.ArmProximityArrival(slot, target as ObjectReference, player as ObjectReference, Self, "IntelEngine_NPCTasks", "OnProximityArrived")

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
    ; No grace period — the target walking up IS the visible approach.
    ; Checking immediately prevents the "NPC on your face but not detected"
    ; problem caused by VM-throttled polling on heavy modlists.
    ; =========================================================================
    If waitForTarget && target != None && !target.IsDead()
        Actor player = Game.GetPlayer()
        Bool targetAtPlayer = false
        If target.Is3DLoaded() && player.Is3DLoaded()
            targetAtPlayer = (target.GetDistance(player) <= IntelEngine.GetArrivalThreshold(target, player as ObjectReference))
        ElseIf !target.Is3DLoaded() && target.GetParentCell() == player.GetParentCell()
            targetAtPlayer = true
        EndIf

        If targetAtPlayer
            Core.DebugMsg("[diag:arrival] " + target.GetDisplayName() + " reached player -- completing fetch " + IntelEngine.DescribeDistance(target, player))
            OnReturnedWithTarget(slot, agent, target)
            Return
        EndIf
    EndIf

    If agent.Is3DLoaded() && returnMarker.Is3DLoaded()
        ; Agent is on-screen — clear off-screen tracking
        StorageUtil.UnsetIntValue(agent, "Intel_OffScreenCycles")
        StorageUtil.UnsetFloatValue(agent, "Intel_OffScreenLastDist")
        StorageUtil.UnsetFloatValue(agent, "Intel_OffScreenSince")

        Float agentDist = agent.GetDistance(returnMarker)
        If agentDist <= IntelEngine.GetArrivalThreshold(agent, returnMarker)
            ; Agent arrived — also wait for target on success returns
            If waitForTarget && target != None
                Bool targetArrived = false
                If returnCycles > 3 && target.Is3DLoaded()
                    Float targetDist = target.GetDistance(returnMarker)
                    targetArrived = (targetDist <= IntelEngine.GetArrivalThreshold(target, returnMarker))
                ElseIf returnCycles > 3 && !target.Is3DLoaded() && target.GetParentCell() == returnMarker.GetParentCell()
                    targetArrived = true
                EndIf

                If !targetArrived
                    ; Target still walking to player. The wait is measured in real seconds since the target
                    ; last got closer. It was counted in monitoring passes ("15 cycles, ~45s"), but while
                    ; anyone is returning the passes come every half second: the wait was over after seven
                    ; seconds, and a walking target, who covers less than 50 units in half a second, never
                    ; counted as getting closer. Intel_TargetWaitCycles is 0 before the wait and, during
                    ; it, 1 + the number of nudges given.
                    Int waitCycles = StorageUtil.GetIntValue(agent, "Intel_TargetWaitCycles")
                    Float waitNow = Utility.GetCurrentRealTime()
                    Float waitSince = StorageUtil.GetFloatValue(agent, "Intel_TargetWaitSince", 0.0)
                    Float targetDist = target.GetDistance(returnMarker)

                    ; First cycle: agent just arrived — sandbox near player while waiting, notify player
                    If waitCycles == 0
                        Core.RemoveIntelPackages(agent, false)
                        PO3_SKSEFunctions.SetLinkedRef(agent, Game.GetPlayer() as ObjectReference, Core.IntelEngine_TravelTarget)
                        ActorUtil.AddPackageOverride(agent, Core.SandboxNearPlayerPackage, Core.PRIORITY_SANDBOX, 1)
                        agent.EvaluatePackage()
                        Core.NotifyPlayer(agent.GetDisplayName() + " arrived - " + target.GetDisplayName() + " is still on the way")
                        Core.SendTransientEvent(agent, target, agent.GetDisplayName() + " arrived but " + target.GetDisplayName() + " is still making their way here.")
                    EndIf

                    ; Track progress — the clock starts with the wait, starts again when the target has
                    ; come more than 50 units closer than at the last mark, and after a restart of the
                    ; game (the real-time clock begins at zero again).
                    Float lastTargetDist = StorageUtil.GetFloatValue(agent, "Intel_TargetLastDist", 0.0)
                    Bool closer = lastTargetDist > 0.0 && targetDist < lastTargetDist - 50.0
                    If waitCycles == 0 || closer || waitSince <= 0.0 || waitSince > waitNow
                        If closer && waitCycles > 0
                            Core.DebugMsg(target.GetDisplayName() + " making progress (" + targetDist + " from player)")
                        EndIf
                        waitCycles = 1
                        waitSince = waitNow
                        StorageUtil.SetIntValue(agent, "Intel_TargetWaitCycles", 1)
                        StorageUtil.SetFloatValue(agent, "Intel_TargetWaitSince", waitNow)
                        StorageUtil.SetFloatValue(agent, "Intel_TargetLastDist", targetDist)
                    EndIf

                    ; Soft recovery — nudge the target's AI, three times at most
                    If waitCycles <= 3 && waitNow - waitSince >= TARGET_NUDGE_SECONDS * waitCycles
                        Core.DebugMsg("Target soft recovery (" + waitCycles + ")")
                        ; The travel package is taken off and put back, which makes the AI plan the path
                        ; afresh. No PathToReference: it is a forced run at full speed, and it held this
                        ; monitoring pass (and every other slot in it) until the target got there or gave up.
                        Package targetPkg = Core.TravelPackageOn(target, Core.TravelPackage_Walk)
                        ActorUtil.RemovePackageOverride(target, Core.TravelPackage_Walk)
                        ActorUtil.RemovePackageOverride(target, Core.TravelPackage_Jog)
                        ActorUtil.AddPackageOverride(target, targetPkg, Core.PRIORITY_TRAVEL, 1)
                        target.EvaluatePackage()
                        waitCycles += 1
                        StorageUtil.SetIntValue(agent, "Intel_TargetWaitCycles", waitCycles)
                    EndIf

                    If waitNow - waitSince < TARGET_WAIT_SECONDS
                        Return  ; Keep waiting
                    EndIf

                    ; Exhausted. OnReturnedWithTarget places a target who is out of sight. One the player
                    ; is looking at is left to walk the rest: they used to be set down next to the agent,
                    ; in plain view.
                    Core.DebugMsg("Target wait exhausted (" + (waitNow - waitSince) + "s, dist=" + targetDist + ")")
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
        Core.DebugMsg("[diag:arrival] " + agent.GetDisplayName() + " returned to destination cell " + IntelEngine.DescribeDistance(agent, returnMarker))
        OnReturnedWithTarget(slot, agent, target)
        Return
    EndIf

    ; Success return: calculate distance using native C++ (works off-screen)
    Float dist = IntelEngine.GetDistance2D(agent, returnMarker)

    ; Close enough off-screen? Complete.
    If dist <= IntelEngine.GetArrivalThreshold(agent, returnMarker)
        Core.DebugMsg("[diag:arrival] " + agent.GetDisplayName() + " arrived off-screen " + IntelEngine.DescribeDistance(agent, returnMarker))
        OnReturnedWithTarget(slot, agent, target)
        Return
    EndIf

    ; Track off-screen return progress, in real seconds since the agent last got more than 100 units
    ; closer. It was counted in monitoring passes of an assumed three seconds, but while anyone is
    ; returning the passes come every half second: the time allowed was a sixth of what was meant, steady
    ; walking never counted as progress, and both were set down behind the player after a few seconds.
    Float offNow = Utility.GetCurrentRealTime()
    Float offSince = StorageUtil.GetFloatValue(agent, "Intel_OffScreenSince", 0.0)
    Float lastDist = StorageUtil.GetFloatValue(agent, "Intel_OffScreenLastDist")
    If offSince <= 0.0 || offSince > offNow || lastDist <= 0.0 || dist < lastDist - 100.0
        offSince = offNow
        StorageUtil.SetFloatValue(agent, "Intel_OffScreenSince", offNow)
        StorageUtil.SetFloatValue(agent, "Intel_OffScreenLastDist", dist)
    EndIf

    ; Time allowed: NPC walks ~100 units/sec; 50 units/sec is assumed (conservative, accounts for
    ; pathfinding detours), with a 2x safety margin on top. The same allowance as before, in seconds.
    Float maxSeconds = (dist / 50.0) * 2.0
    If maxSeconds < 15.0
        maxSeconds = 15.0
    EndIf

    If offNow - offSince >= maxSeconds
        ; Time's up — agent is stuck off-screen. Teleport both behind player.
        Core.DebugMsg(agent.GetDisplayName() + " off-screen return timed out (" + ((offNow - offSince) as Int) + "s, dist=" + dist + "). Teleporting both.")
        ; No more passes on this slot from here on: the moves and the wait below are latent, and the
        ; pass that came meanwhile ran the completion a second time.
        Core.MarkSlotProcessing(slot, agent)
        PlaceNearPlayerUnseen(agent, 300.0)
        If target != None && !target.IsDead()
            PlaceNearPlayerUnseen(target, 250.0)
        EndIf
        Utility.Wait(0.5)
        OnReturnedWithTarget(slot, agent, target)
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

    ; Ensure target is near the player.
    ; If not loaded or loaded but far, teleport behind the camera as a last resort.
    ; Loaded means same space as the player, so adjacent exterior cells are not
    ; "elsewhere". Otherwise TalkToPlayer (priority 1) pathfinds them in.
    ; Not indoors, where "behind the camera" at 2000 units is outside the building (the target stayed out
    ; there): see PlaceNearPlayerUnseen. And not a target the player is looking at: they were taken out of
    ; view and put further away than they had been. Such a target walks the rest (linger phase 1).
    If !target.Is3DLoaded()
        Core.DebugMsg(targetName + " not loaded - placing out of sight near the player")
        PlaceNearPlayerUnseen(target)
    ElseIf target.GetDistance(player) > Core.LINGER_RELEASE_DISTANCE && !player.IsInInterior() && !Core.PlayerCanSee(target)
        Core.DebugMsg(targetName + " far (" + target.GetDistance(player) + ") - teleporting behind camera")
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
    ; The errand is done at the player's side, not at home: an agent with no routine of their own (many
    ; mod-added NPCs only have a sandbox package) stayed there for good. They are walked home.
    Core.ReleaseLinger(agent)
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

    Core.NotifyPlayer(agentName + ": " + targetName + " refused - " + failReason)

    Core.ClearSlotRestoreFollower(slot, agent)
    Core.ReleaseLinger(agent)   ; see OnReturnedWithTarget: one with no routine of their own is walked home
    ; Cooldown prevents narration-triggered re-selection
    StorageUtil.SetFloatValue(agent, "Intel_TaskCooldown", Utility.GetCurrentRealTime())
EndFunction

; HandleTargetPresenting removed — target-first completion in CheckReturnArrival
; makes the intermediate presenting state unnecessary. The target speaks to the
; player as soon as they arrive, regardless of the agent's position.

; =============================================================================
; ESCORT HOME STATE MACHINE
; =============================================================================

Function HandleEscortTargetState(Int slot, Actor agent, Int taskState)
    Actor target = StorageUtil.GetFormValue(agent, "Intel_TargetNPC") as Actor

    ; (Disabled counts as gone, see HandleFetchState.)
    If target == None || target.IsDead() || target.IsDisabled()
        Core.NotifyPlayer(agent.GetDisplayName() + " lost their escort target")
        Core.ClearSlot(slot, true)
        Core.ReleaseLinger(agent)
        Return
    EndIf

    If taskState == 1
        ; Traveling to target
        If CheckDeparture(slot, agent)
            Return
        EndIf
        CheckArrivalAtTarget(slot, agent, target)

    ElseIf taskState == Core.STATE_AT_TARGET
        ; At target — brief interaction before escorting
        HandleAtTarget_Escort(slot, agent, target)

    ElseIf taskState == 3
        ; Escorting target to destination
        CheckEscortArrival(slot, agent, target)
    EndIf
EndFunction

Function HandleAtTarget_Escort(Int slot, Actor agent, Actor target)
    Int remaining = StorageUtil.GetIntValue(agent, "Intel_InteractCyclesRemaining")
    remaining -= 1
    StorageUtil.SetIntValue(agent, "Intel_InteractCyclesRemaining", remaining)

    If remaining > 0
        Return
    EndIf
    ; From here to the change of state there are waits (waking a sleeper takes a full second): the counter
    ; is set high so that a monitoring pass arriving in one of them does not start the escort a second time.
    StorageUtil.SetIntValue(agent, "Intel_InteractCyclesRemaining", 1000)

    ; Interaction complete — check success/failure
    Actor player = Game.GetPlayer()
    Bool playerPresent = (agent.GetParentCell() == player.GetParentCell())
    String agentName = agent.GetDisplayName()
    String targetName = target.GetDisplayName()
    String destName = StorageUtil.GetStringValue(agent, "Intel_EscortDestName")
    If destName == ""
        destName = "their destination"
    EndIf

    If playerPresent
        Core.SendTaskNarration(agent, agentName + " offered to walk " + targetName + " to " + destName + " safely.", target)
        ; Let the offer be said before the two of them turn and go.
        If !LetLineFinish(slot, agent, agent)
            Return
        EndIf
    Else
        Core.SendTransientEvent(agent, target, agentName + " offered to walk " + targetName + " to " + destName + ".")
    EndIf

    Core.NotifyPlayer(agentName + " is escorting " + targetName + " to " + destName)
    BeginEscortToDestination(slot, agent, target)
EndFunction

Function BeginEscortToDestination(Int slot, Actor agent, Actor target)
    ObjectReference destMarkerRef = StorageUtil.GetFormValue(agent, "Intel_ReturnMarker") as ObjectReference
    If destMarkerRef == None
        Core.DebugMsg("EscortTarget: lost destination marker -- aborting")
        Core.ClearSlot(slot, true)
        Return
    EndIf

    String destName = StorageUtil.GetStringValue(agent, "Intel_EscortDestName")
    If destName == ""
        destName = "their destination"
    EndIf

    ; Wake sleeping target — sleep packages override travel at priority 0-50,
    ; so the escort agent just stands at the bedside waiting forever.
    If target.GetSleepState() != 0
        Core.DebugMsg("EscortTarget: waking " + target.GetDisplayName() + " from sleep")
        target.EvaluatePackage()
        Utility.Wait(1.0)
    EndIf

    ; Cancel SkyrimNet's FollowPlayer package on the target — without this,
    ; the accompany package fights the escort travel package and pulls the
    ; target back to the player after escort completes.
    If SkyrimNetApi.HasPackage(target, "FollowPlayer") == 1
        SkyrimNetApi.UnregisterPackage(target, "FollowPlayer")
        StorageUtil.SetIntValue(target, "Intel_WasAccompanying", 1)
        Core.DebugMsg(target.GetDisplayName() + " FollowPlayer package removed for escort")
    EndIf

    ; Remove sandbox from OnArrivedAtTarget before adding travel packages
    Core.RemoveIntelPackages(agent, false)

    ; A target who is still lingering from an earlier fetch or escort: that visit ends here (see ForgetLinger).
    ForgetLinger(target)

    ; Both NPCs walk to destination together
    PO3_SKSEFunctions.SetLinkedRef(target, destMarkerRef, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(target, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
    Utility.Wait(0.1)
    target.EvaluatePackage()

    PO3_SKSEFunctions.SetLinkedRef(agent, destMarkerRef, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(agent, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
    Core.SetSlotSpeed(slot, agent, 0)   ; the slot's speed is the package that is on them (walk)
    Utility.Wait(0.1)
    agent.EvaluatePackage()

    Core.SetSlotState(slot, agent, 3)
    Core.InitializeStuckTrackingForSlot(slot, agent)

    ; Re-arm proximity on target→destination — escort completion fires the
    ; instant the target walks into range of the destination marker.
    IntelEngine.ArmProximityArrival(slot, target as ObjectReference, destMarkerRef, Self, "IntelEngine_NPCTasks", "OnProximityArrived")

    Core.SendTransientEvent(agent, target, agent.GetDisplayName() + " began walking " + target.GetDisplayName() + " to " + destName + ".")
EndFunction

Function CheckEscortArrival(Int slot, Actor agent, Actor target)
    ObjectReference destMarkerRef = StorageUtil.GetFormValue(agent, "Intel_ReturnMarker") as ObjectReference
    If destMarkerRef == None
        OnEscortComplete(slot, agent, target, false)
        Return
    EndIf

    ; Target arrived at destination = completion
    If target.Is3DLoaded() && destMarkerRef.Is3DLoaded()
        If target.GetDistance(destMarkerRef) <= Core.ARRIVAL_DISTANCE
            ; Check if destination is a door — teleport both NPCs through (same as GoToLocation)
            ObjectReference doorDest = IntelEngine.GetDoorDestinationRef(destMarkerRef)
            ; No more passes on this slot from here on. The moves and the wait below are latent: the pass
            ; that came meanwhile (every half second in this state) found the target at the door again and
            ; ran the completion a second time.
            Core.MarkSlotProcessing(slot, agent)
            If doorDest != None
                Core.DebugMsg("Escort: door reached, teleporting both through")
                agent.MoveTo(doorDest)
                target.MoveTo(doorDest)
                ; Update linked refs + ReturnMarker to interior target so sandbox uses correct ref
                PO3_SKSEFunctions.SetLinkedRef(agent, doorDest, Core.IntelEngine_TravelTarget)
                PO3_SKSEFunctions.SetLinkedRef(target, doorDest, Core.IntelEngine_TravelTarget)
                StorageUtil.SetFormValue(agent, "Intel_ReturnMarker", doorDest)
                Utility.Wait(0.5)
            EndIf
            OnEscortComplete(slot, agent, target, true)
            Return
        EndIf
    ElseIf !target.Is3DLoaded()
        Cell targetCell = target.GetParentCell()
        Cell destCell = destMarkerRef.GetParentCell()
        If targetCell != None && destCell != None && targetCell == destCell
            ; Off-screen arrival — teleport through door if destination is a door
            ObjectReference doorDest2 = IntelEngine.GetDoorDestinationRef(destMarkerRef)
            Core.MarkSlotProcessing(slot, agent)   ; as above: the moves are latent
            If doorDest2 != None
                agent.MoveTo(doorDest2)
                target.MoveTo(doorDest2)
                PO3_SKSEFunctions.SetLinkedRef(agent, doorDest2, Core.IntelEngine_TravelTarget)
                PO3_SKSEFunctions.SetLinkedRef(target, doorDest2, Core.IntelEngine_TravelTarget)
                StorageUtil.SetFormValue(agent, "Intel_ReturnMarker", doorDest2)
            EndIf
            OnEscortComplete(slot, agent, target, true)
            Return
        EndIf
    EndIf

    ; Agent stuck detection
    If agent.Is3DLoaded()
        Int stuckStatus = IntelEngine.CheckStuckStatus(agent, slot, Core.STUCK_DISTANCE_THRESHOLD)
        If stuckStatus == 1
            Core.SoftStuckRecovery(agent, slot, destMarkerRef)
        ElseIf stuckStatus >= 3 && (Core.PlayerCanSee(agent) || Core.PlayerCanSee(target))
            ; Not while the player is looking at either of them: both used to vanish from view to the
            ; destination. The package is refreshed instead; the move waits until they are out of sight,
            ; and the task's time limit stays the last resort.
            Core.SoftStuckRecovery(agent, slot, destMarkerRef)
        ElseIf stuckStatus >= 3
            ; Teleport both to destination — through door if applicable
            ObjectReference doorDest3 = IntelEngine.GetDoorDestinationRef(destMarkerRef)
            Core.MarkSlotProcessing(slot, agent)   ; as above: the moves are latent
            If doorDest3 != None
                agent.MoveTo(doorDest3)
                target.MoveTo(doorDest3)
                PO3_SKSEFunctions.SetLinkedRef(agent, doorDest3, Core.IntelEngine_TravelTarget)
                PO3_SKSEFunctions.SetLinkedRef(target, doorDest3, Core.IntelEngine_TravelTarget)
                StorageUtil.SetFormValue(agent, "Intel_ReturnMarker", doorDest3)
            Else
                agent.MoveTo(destMarkerRef)
                target.MoveTo(destMarkerRef)
            EndIf
            OnEscortComplete(slot, agent, target, true)
            Return
        EndIf
    EndIf

    ; Off-screen: estimated travel time
    If !agent.Is3DLoaded()
        If Core.HandleOffScreenTravel(slot, agent, destMarkerRef)
            Core.MarkSlotProcessing(slot, agent)   ; as above: the moves are latent
            agent.MoveTo(destMarkerRef)
            target.MoveTo(destMarkerRef)
            OnEscortComplete(slot, agent, target, true)
        EndIf
    EndIf
EndFunction

Function StartEscortTargetWait(Actor target, ObjectReference destRef, String destName, Bool waitsForPlayer = true)
    {Target sandboxes at destination after escort. Waits for player arrival, times out after 6h.
    waitsForPlayer = false: nobody asked them to wait. A short hold only, and no greeting (see phase 3 in
    CheckLingeringTargets).}

    ; Dedup — if already lingering, just release
    If StorageUtil.GetIntValue(target, "Intel_LingerPhase", 0) > 0
        Core.RemoveIntelPackages(target)
        target.EvaluatePackage()
        Return
    EndIf

    ; Sandbox at destination
    Core.RemoveIntelPackages(target, false)
    ; Arrived unseen (both are moved to the destination when the walk was not watched): the sandbox is
    ; anchored on the target themselves. A sandbox around a marker that is not loaded can crash the engine
    ; (see Travel.OnArrival, same package), and with no linked ref at all it has no place.
    ObjectReference anchor = destRef
    If anchor == None || !target.Is3DLoaded()
        anchor = target
    EndIf
    PO3_SKSEFunctions.SetLinkedRef(target, anchor, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(target, Core.SandboxNearPlayerPackage, Core.PRIORITY_SANDBOX, 1)
    Utility.Wait(0.1)
    target.EvaluatePackage()

    ; Store linger state — phase 3 = waiting at destination for player
    StorageUtil.SetIntValue(target, "Intel_LingerPhase", 3)
    StorageUtil.SetStringValue(target, "Intel_LingerDestName", destName)
    StorageUtil.SetFloatValue(target, "Intel_LingerStart", Utility.GetCurrentGameTime())
    ; For the re-link after a load (RelinkLingeringTargets).
    StorageUtil.SetFormValue(target, "Intel_LingerDestRef", destRef)
    If !waitsForPlayer
        StorageUtil.SetIntValue(target, "Intel_LingerNoGreet", 1)
    EndIf
    StorageUtil.FormListAdd(self, "Intel_LingeringTargets", target, false)

    Core.DebugMsg(target.GetDisplayName() + " waiting at " + destName + " for player (escort linger phase 3)")
    Core.RequestTick(Core.UPDATE_INTERVAL)
EndFunction

Function OnPlayerArrivedAtEscortTarget(Actor target)
    {Player arrived at destination where escort target is waiting. Narrate, then transition to normal linger.}
    String targetName = target.GetDisplayName()
    String destName = StorageUtil.GetStringValue(target, "Intel_LingerDestName")
    If destName == ""
        destName = "their destination"
    EndIf

    ; The phase is changed first. It used to change last, after the narration and a wait of a second: the
    ; monitoring pass that came in that second still found "waiting, player arrived" and greeted again.
    StorageUtil.SetIntValue(target, "Intel_LingerPhase", 1)
    StorageUtil.SetFloatValue(target, "Intel_LingerUntil", Utility.GetCurrentGameTime() + LINGER_APPROACH_MAX_HOURS / 24.0)
    ; Clean up escort-specific keys (phase 1/2 don't need them)
    StorageUtil.UnsetStringValue(target, "Intel_LingerDestName")
    StorageUtil.UnsetFloatValue(target, "Intel_LingerStart")
    StorageUtil.UnsetFormValue(target, "Intel_LingerDestRef")

    ; Narrate so SkyrimNet generates a greeting
    Core.SendTaskNarration(target, targetName + " noticed " + Game.GetPlayer().GetDisplayName() + " arrived at " + destName + ".", Game.GetPlayer())

    ; Transition to standard linger phase 1 (approach player → sandbox → release)
    Actor player = Game.GetPlayer()
    Core.RemoveIntelPackages(target, false)
    PO3_SKSEFunctions.SetLinkedRef(target, player as ObjectReference, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(target, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
    Utility.Wait(0.1)
    target.EvaluatePackage()

    Core.DebugMsg(targetName + " noticed player at " + destName + " -- switching to normal linger")
EndFunction

Function OnEscortComplete(Int slot, Actor agent, Actor target, Bool reachedDestination)
    Core.MarkSlotProcessing(slot, agent)
    If reachedDestination
        StorageUtil.SetStringValue(agent, "Intel_Result", "success")
    EndIf

    String agentName = agent.GetDisplayName()
    String targetName = target.GetDisplayName()
    String destName = StorageUtil.GetStringValue(agent, "Intel_EscortDestName")
    If destName == ""
        destName = "their destination"
    EndIf
    Core.DebugMsg(agentName + " escorted " + targetName + " to " + destName)

    Int shouldWaitVal = StorageUtil.GetIntValue(agent, "Intel_EscortShouldWait")

    ; Release target alias and clean up accompany tracking
    ReferenceAlias targetAlias = Core.GetTargetAlias(slot)
    If targetAlias
        targetAlias.Clear()
    EndIf
    StorageUtil.UnsetIntValue(target, "Intel_WasAccompanying")

    ; Check if player is already at the destination
    Actor player = Game.GetPlayer()
    Bool playerPresent = (target.GetParentCell() == player.GetParentCell())

    If shouldWaitVal == 1 && !playerPresent
        ; Player not here — target waits at destination for player arrival
        ObjectReference destRef = StorageUtil.GetFormValue(agent, "Intel_ReturnMarker") as ObjectReference
        StartEscortTargetWait(target, destRef, destName)
    Else
        ; Player already here or no wait requested — sandbox briefly before releasing.
        ; This prevents the target from instantly teleporting home (child NPC AI, follow-parent packages)
        ; by keeping the sandbox package active until the normal linger system releases them.
        ObjectReference destRef = StorageUtil.GetFormValue(agent, "Intel_ReturnMarker") as ObjectReference
        If destRef == None
            destRef = target  ; sandbox where they are
        EndIf
        ; No wait requested: the brief hold this comment speaks of, not the six-hour wait with a greeting
        ; for the player that everyone got.
        StartEscortTargetWait(target, destRef, destName, shouldWaitVal == 1)
    EndIf

    ; Narrate
    If agent.Is3DLoaded() && playerPresent
        Core.SendTaskNarration(agent, agentName + " escorted " + targetName + " to " + destName + " safely.", player)
    Else
        Core.SendTransientEvent(agent, target, agentName + " escorted " + targetName + " safely to " + destName + ".")
    EndIf

    Core.NotifyPlayer(agentName + " escorted " + targetName + " to " + destName)

    ; Clean up agent — resumes normal AI (no return to player needed)
    Core.ClearSlotRestoreFollower(slot, agent)
    ; "Normal AI" brings home whoever has a routine. One who has none (see OnReturnedWithTarget) stayed at
    ; the escort's destination for good: they are walked home.
    Core.ReleaseLinger(agent)
    StorageUtil.SetFloatValue(agent, "Intel_TaskCooldown", Utility.GetCurrentRealTime())
EndFunction

; =============================================================================
; MESSAGE DELIVERY STATE MACHINE
; =============================================================================

Function HandleMessageState(Int slot, Actor agent, Int taskState)
    Actor target = StorageUtil.GetFormValue(agent, "Intel_TargetNPC") as Actor

    ; (Disabled counts as gone, see HandleFetchState. Not on the way back: the message has been delivered,
    ; and the return only needs the agent.)
    If target == None || target.IsDead() || (target.IsDisabled() && taskState != 3)
        Core.NotifyPlayer(agent.GetDisplayName() + " could not find the recipient")
        Core.ClearSlot(slot, true)
        Core.ReleaseLinger(agent)
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
    Core.RemoveIntelPackages(agent)
    PO3_SKSEFunctions.SetLinkedRef(agent, None, Core.IntelEngine_TravelTarget)

    ; Store message on recipient so they remember it
    ; This makes the message appear in their prompt context via decorators
    Core.StoreReceivedMessage(target, agent, msgContent)

    ; Persistent memory — agent remembers delivering this message
    Core.SendPersistentMemory(agent, target, agent.GetDisplayName() + " delivered a message to " + target.GetDisplayName() + ": " + msgContent)

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
    ; The player saw it only if the recipient is where the player is, and the messenger got there in view.
    ; Asking only where the messenger is took "the messenger lives in this inn and is already back" for
    ; "the player saw the delivery": no way back, no report, and the handover narrated as if in the room.
    Bool playerPresent = (agent.GetParentCell() == player.GetParentCell()) && (target.GetParentCell() == player.GetParentCell())         && StorageUtil.GetIntValue(agent, "Intel_ArrivedUnseen") != 1
    StorageUtil.UnsetIntValue(agent, "Intel_ArrivedUnseen")
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
        ; Player absent — persistent event so both parties recall the delivery
        Core.SendPersistentMemory(target, agent, agentName + " came and told " + targetName + ": \"" + msgContent + "\"")
    EndIf

    StorageUtil.SetStringValue(agent, "Intel_Result", "delivered")

    If playerPresent
        ; Player witnessed the delivery — nothing to report. Wait for the scene
        ; to play out before clearing so the narration isn't cut short.
        Utility.Wait(3.0)
        Core.ClearSlotRestoreFollower(slot, agent)
        Core.ReleaseLinger(agent)   ; see OnReturnedWithTarget: one with no routine of their own is walked home
        StorageUtil.SetFloatValue(agent, "Intel_TaskCooldown", Utility.GetCurrentRealTime())
    Else
        ; Player absent — follower must walk back naturally.
        ; Instant ClearSlotRestoreFollower would trigger follower-framework teleport.
        Core.NotifyPlayer(agentName + " delivered a message to " + targetName + " and is heading back")
        BeginDeliveryReturn(slot, agent)
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
    Core.SetSlotSpeed(slot, agent, 1)   ; the slot's speed is the package that is on them (jog)
    Utility.Wait(0.1)
    agent.EvaluatePackage()

    Core.SetSlotState(slot, agent, 3)  ; returning
    Core.InitializeStuckTrackingForSlot(slot, agent)

    ; Re-arm proximity on agent→player for the delivery return trip.
    IntelEngine.ArmProximityArrival(slot, agent as ObjectReference, player as ObjectReference, Self, "IntelEngine_NPCTasks", "OnProximityArrived")

    ; The slot was marked "being processed" during the delivery. If this was the only task, the update loop
    ; saw nothing active meanwhile and did not ask for another tick: the way back was never monitored, and
    ; the agent stood at the player with the task still open.
    Core.RequestTick(Core.UPDATE_INTERVAL)

    Core.DebugMsg(agent.GetDisplayName() + " returning to player after delivery")
EndFunction

Function CheckDeliveryReturnArrival(Int slot, Actor agent)
    Actor player = Game.GetPlayer()

    If agent.Is3DLoaded() && player.Is3DLoaded()
        Float dist = agent.GetDistance(player)
        If dist <= IntelEngine.GetArrivalThreshold(agent, player as ObjectReference)
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

    If playerPresent && StorageUtil.GetIntValue(player, "Intel_DeliveryReportBack") == 1
        ; Stop travel and sandbox near player so agent doesn't walk away
        Core.RemoveIntelPackages(agent, false)
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
    Core.ReleaseLinger(agent)   ; see OnReturnedWithTarget: one with no routine of their own is walked home
    StorageUtil.SetFloatValue(agent, "Intel_TaskCooldown", Utility.GetCurrentRealTime())
EndFunction

; =============================================================================
; SEARCH FOR ACTOR STATE MACHINE
; =============================================================================

Function HandleSearchState(Int slot, Actor agent, Int taskState)
    Actor target = StorageUtil.GetFormValue(agent, "Intel_TargetNPC") as Actor

    ; (Disabled counts as gone, see HandleFetchState.)
    If target == None || target.IsDead() || target.IsDisabled()
        Core.NotifyPlayer(agent.GetDisplayName() + " could not find their target")
        Core.ClearSlot(slot, true)
        Core.ReleaseLinger(agent)
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
        ; Reached a waypoint the stuck recovery sent them to (Layer B): on to the target again. The other
        ; tasks check this in CheckArrivalAtTarget; a search did not, and the agent stood at the waypoint,
        ; for good when the player was watching (no teleport in view).
        If Core.CheckWaypointArrival(slot, agent, target as ObjectReference)
            Return
        EndIf
        If target.Is3DLoaded()
            Float distToTarget = agent.GetDistance(target)
            If distToTarget <= IntelEngine.GetArrivalThreshold(agent, target as ObjectReference)
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
                Core.RemoveIntelPackages(agent, false)
                ; The sandbox is anchored where they stand. With the linked ref cleared, as it was, the
                ; package has no place and they head for home instead of waiting (see Travel.OnArrival).
                PO3_SKSEFunctions.SetLinkedRef(agent, agent as ObjectReference, Core.IntelEngine_TravelTarget)
                StorageUtil.UnsetFormValue(agent, "Intel_CurrentWaypoint")
                ActorUtil.AddPackageOverride(agent, Core.SandboxNearPlayerPackage, Core.PRIORITY_SANDBOX, 1)
                agent.EvaluatePackage()

                Core.SetSlotState(slot, agent, 5)  ; waiting for player
                ; The wait had no end: with the player busy elsewhere in the same area the agent stood
                ; there for good. After SEARCH_WAIT_MAX_HOURS the search is given up (HandleTaskTimeout).
                Core.SetSlotDeadline(slot, Utility.GetCurrentGameTime() + SEARCH_WAIT_MAX_HOURS / 24.0)
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
                ; Standing still was the wait, not being stuck: the stuck counter starts afresh. And the
                ; search gets its overall time limit back in place of the limit of the wait.
                IntelEngine.ResetStuckSlot(slot, agent)
                Float searchBegan = StorageUtil.GetFloatValue(agent, "Intel_TaskAllocatedAt", 0.0)
                If searchBegan <= 0.0
                    searchBegan = Utility.GetCurrentGameTime()
                EndIf
                Float searchLimit = searchBegan + SEARCH_MAX_HOURS / 24.0
                If searchLimit < Utility.GetCurrentGameTime() + SEARCH_WAIT_MAX_HOURS / 24.0
                    searchLimit = Utility.GetCurrentGameTime() + SEARCH_WAIT_MAX_HOURS / 24.0
                EndIf
                Core.SetSlotDeadline(slot, searchLimit)
            EndIf
        EndIf
    EndIf
EndFunction

Function OnArrivedAtSearchTarget(Int slot, Actor agent, Actor target)
    Core.DebugMsg(agent.GetDisplayName() + " found target: " + target.GetDisplayName())
    Core.NotifyPlayer(agent.GetDisplayName() + " found " + target.GetDisplayName())

    ; Remove packages
    Core.RemoveIntelPackages(agent)
    PO3_SKSEFunctions.SetLinkedRef(agent, None, Core.IntelEngine_TravelTarget)

    ; Mark success
    StorageUtil.SetStringValue(agent, "Intel_Result", "success")

    Core.ClearSlotRestoreFollower(slot, agent)
    Core.ReleaseLinger(agent)   ; see OnReturnedWithTarget: one with no routine of their own is walked home

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
    ; Not leaving because they are fighting, being spoken to or in the middle of a sentence is not a failed
    ; departure: the count starts again when they are free. The task used to be called off ("was unable
    ; to carry out the task") fifteen seconds into a conversation that held them where they stood.
    If agent.IsInCombat() || agent.GetDialogueTarget() != None || IntelEngine.IsActorTalking(agent)
        Core.InitializeDepartureTracking(slot, agent)
        Return false
    EndIf
    Int status = Core.CheckDepartureProgress(slot, agent, Core.STUCK_DISTANCE_THRESHOLD)

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
            Core.DebugMsg(agentName + " failed to depart (off-screen) - teleporting to destination")
            ; (Not onto a spot in front of the player, see CheckIfStuck.)
            If !Core.PlaceForUnseenArrival(agent, dest)
                agent.MoveTo(dest, 0.0, 0.0, 50.0)
            EndIf
            agent.EvaluatePackage()
            Return
        EndIf
    EndIf

    ; Player is watching — narrate and cancel
    Core.DebugMsg(agentName + " failed to depart (visible) - narrating cancel")

    If agent.GetParentCell() == player.GetParentCell()
        Core.SendTaskNarration(agent, agentName + " " + IntelEngine.BuildStuckNarration(Core.SlotTaskTypes[slot]), player)
    Else
        Core.SendTransientEvent(agent, player, agentName + " was unable to carry out the task and stayed behind.")
    EndIf

    Core.RemoveIntelPackages(agent)
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
    ; Skip stuck detection while NPC is in dialogue or combat — stationary by design.
    ; The same while they are speaking: a SkyrimNet conversation sets no dialogue target, so an agent
    ; who stopped to answer was "stuck", narrated as stumbling and, further on, teleported.
    If npc.GetDialogueTarget() != None || npc.IsInCombat() || IntelEngine.IsActorTalking(npc)
        IntelEngine.ResetStuckSlot(slot, npc)
        Return
    EndIf
    ; Nor while the game has them doing something else (the bard's audience, a scene).
    If Core.HeldByAnotherPackage(slot, npc)
        Return
    EndIf

    Int status = IntelEngine.CheckStuckStatus(npc, slot, Core.STUCK_DISTANCE_THRESHOLD)

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
                Core.SendTaskNarration(npc, npcName + " felt their feet catch on something and couldn't move for a moment, stumbling on the way to " + target + ".")
            ElseIf taskType == "deliver_message"
                Core.SendTaskNarration(npc, npcName + " felt their feet catch on something and couldn't move for a moment, stumbling on the way to deliver a message to " + target + ".")
            ElseIf taskType == "search_for_actor"
                Core.SendTaskNarration(npc, npcName + " felt their feet catch on something and couldn't move for a moment, stumbling while searching.")
            ElseIf taskType == "escort_target"
                Core.SendTaskNarration(npc, npcName + " felt their feet catch on something and couldn't move for a moment, stumbling while escorting " + target + ".")
            Else
                Core.SendTaskNarration(npc, npcName + " felt their feet catch on something and couldn't move for a moment.")
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
            ; No waypoint found. After 4+ failed teleport cycles (~80s stuck),
            ; bring the search target to the player area as a last resort.
            ; Looks like the target wandered into range naturally.
            Float descDist = IntelEngine.GetTeleportDistance(slot)
            If descDist <= 250.0
                Actor searchTarget = StorageUtil.GetFormValue(npc, \
                    "Intel_TargetNPC") as Actor
                ; Not one the player is looking at, and not a carriage driver (moved off the cart, the
                ; carriage service is broken, see Core.IsUnsuitableTaskAgent).
                If searchTarget != None && !Core.PlayerCanSee(searchTarget) && !Core.IsCarriageDriver(searchTarget)
                    Core.DebugMsg("Search exhausted - bringing " + \
                        searchTarget.GetDisplayName() + " to player area")
                    PlaceNearPlayerUnseen(searchTarget, 500.0)
                    IntelEngine.ResetStuckSlot(slot, npc)
                EndIf
            EndIf
            Return
        EndIf

        ; What follows moves the agent by a teleport. Not while the player is looking at them: they
        ; vanished in plain view. The package is refreshed instead, the move waits until they are out of
        ; sight, and the task's time limit stays the last resort.
        If Core.PlayerCanSee(npc)
            Core.SoftStuckRecovery(npc, slot, dest)
            Return
        EndIf

        If isReturning
            ; Progressive distance from C++ StuckDetector
            Float distance = IntelEngine.GetTeleportDistance(slot)
            Core.DebugMsg("Teleport behind player at " + distance + " units for " + npc.GetDisplayName())
            PlaceNearPlayerUnseen(npc, distance, true)
            If !Core.SlotHolds(slot, npc)
                Return                    ; cancelled or replaced while the move was made
            EndIf
            ; Re-apply travel package — may have been dropped by engine. The one that is on them, not
            ; the slot's nominal speed on top of it.
            Int speed = Core.SlotSpeeds[slot]
            Package travelPkg = Core.TravelPackageOn(npc, Core.GetTravelPackage(speed))
            If travelPkg
                ActorUtil.AddPackageOverride(npc, travelPkg, Core.PRIORITY_TRAVEL, 1)
            EndIf
            npc.EvaluatePackage()
        ElseIf dest != None
            Core.DebugMsg("Task stuck recovery exhausted - teleporting " + npc.GetDisplayName())
            ; Not onto a spot in front of the player when the one they are going to stands there: then
            ; they are put at the way in (indoors) or well behind the player, and walk the rest.
            If !Core.PlaceForUnseenArrival(npc, dest)
                npc.MoveTo(dest, 0.0, 0.0, 50.0)
            EndIf
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
    If IsNPCTaskType(taskType)
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

Bool Function IsNPCTaskType(String taskType)
    {Check if a task type string is one of the NPC task types managed by this script.
    Single source of truth for the task type check — avoids repeating the 3-way
    string comparison in 6+ places throughout the script.}
    Return taskType == "fetch_npc" || taskType == "deliver_message" || taskType == "search_for_actor" || taskType == "escort_target"
EndFunction

Bool Function HoldsActor(Actor npc)
    {Used by Core's sweep of stale overrides: a fetched or escorted NPC who still lingers is accounted for.}
    Return npc != None && StorageUtil.FormListFind(self, "Intel_LingeringTargets", npc as Form) >= 0
EndFunction
