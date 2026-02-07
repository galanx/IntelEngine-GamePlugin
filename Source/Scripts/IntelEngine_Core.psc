Scriptname IntelEngine_Core extends Quest
{
    IntelEngine Core System v1.0

    Intelligent NPC Task Execution for SkyrimNet

    This script handles:
    - Initialization and database loading
    - Decorator registration with SkyrimNet
    - Alias slot management for concurrent tasks
    - Common utility functions

    Required CK Setup:
    - Create 5 AgentAliases (AgentAlias00-04) for task executors
    - Create 5 TargetAliases (TargetAlias00-04) for fetch targets
    - Attach travel/escort packages to aliases
    - Fill all properties in CK
}

; =============================================================================
; PROPERTIES - Aliases
; =============================================================================

ReferenceAlias Property AgentAlias00 Auto
ReferenceAlias Property AgentAlias01 Auto
ReferenceAlias Property AgentAlias02 Auto
ReferenceAlias Property AgentAlias03 Auto
ReferenceAlias Property AgentAlias04 Auto

ReferenceAlias Property TargetAlias00 Auto
ReferenceAlias Property TargetAlias01 Auto
ReferenceAlias Property TargetAlias02 Auto
ReferenceAlias Property TargetAlias03 Auto
ReferenceAlias Property TargetAlias04 Auto

IntelEngine_Travel Property Travel Auto
{Reference to travel script for monitoring restart on game load}

IntelEngine_NPCTasks Property NPCTasks Auto
{Reference to NPC tasks script for monitoring restart on game load}

IntelEngine_Schedule Property Schedule Auto
{Reference to schedule script for monitoring restart on game load}

; =============================================================================
; PROPERTIES - Keywords
; =============================================================================

Keyword Property IntelEngine_TravelTarget Auto
{Keyword for linking agent to travel destination}

Keyword Property IntelEngine_EscortTarget Auto
{Keyword for linking agent to escort target (NPC being brought back)}

Keyword Property IntelEngine_AgentLink Auto
{Keyword for linking target to agent (so target follows agent)}

Keyword Property IntelEngine_WaitLocation Auto
{Keyword for linking to wait/meeting location}

; =============================================================================
; PROPERTIES - Packages
; =============================================================================

Package Property TravelPackage_Walk Auto
{Travel package - walking speed}

Package Property TravelPackage_Jog Auto
{Travel package - jogging speed}

Package Property TravelPackage_Run Auto
{Travel package - running speed}

Package Property SandboxPackage Auto
{Sandbox package - idle at destination}

Package Property SandboxNearPlayerPackage Auto
{Tight 200-unit sandbox near linked ref — for meeting linger}

; =============================================================================
; PROPERTIES - Other
; =============================================================================

Faction Property IntelEngine_TaskFaction Auto
{Faction for tracking NPCs on active tasks}

GlobalVariable Property IntelEngine_DebugMode Auto
GlobalVariable Property IntelEngine_MaxConcurrentTasks Auto
GlobalVariable Property IntelEngine_DefaultWaitHours Auto

; =============================================================================
; CONSTANTS
; =============================================================================

Int Property MAX_SLOTS = 5 AutoReadOnly
{Maximum concurrent tasks. Must match number of aliases.}

Int Property PRIORITY_TRAVEL = 100 AutoReadOnly
{Package priority for active travel}

Int Property PRIORITY_SANDBOX = 90 AutoReadOnly
{Package priority for sandbox at destination}

Int Property STATE_AT_TARGET = 8 AutoReadOnly
{NPC has arrived at target and is interacting}

Float Property ARRIVAL_DISTANCE = 300.0 AutoReadOnly
{Distance to consider NPC "arrived" at destination}

Float Property UPDATE_INTERVAL = 3.0 AutoReadOnly
{Seconds between status checks}

; --- Shared constants (single source of truth for Travel + NPCTasks) ---

Float Property STUCK_DISTANCE_THRESHOLD = 50.0 AutoReadOnly
{If NPC moved less than this between stuck checks, might be stuck.
Passed to C++ StuckDetector.CheckStuckStatus as threshold parameter.}

Float Property LINGER_APPROACH_DISTANCE = 100.0 AutoReadOnly
{NPC switches from approach (TravelPackage_Walk) to sandbox when within this distance of player}

Int Property LINGER_FAR_TICKS_LIMIT = 3 AutoReadOnly
{Consecutive far checks before a lingering NPC is released}

Int Property DEPARTURE_CHECK_CYCLES = 5 AutoReadOnly
{Update cycles before checking if NPC actually departed (~15s at 3s interval)}

; =============================================================================
; SLOT STATE TRACKING
;
; DUAL STATE DESIGN: State is stored in two places:
; 1. Arrays (below): Fast runtime access for update-loop tick checks.
; 2. StorageUtil on Actor: Persists across save/load (arrays don't).
;
; AllocateSlot/ClearSlot write both on create/destroy.
; SetSlotState/SetSlotSpeed/SetSlotDeadline write both for mid-task updates.
; No other code should write to these arrays or StorageUtil state fields directly.
; On game load, RecoverActiveTasks rebuilds arrays from StorageUtil.
; This is intentional — reading StorageUtil every 3-second tick would be
; too slow; rebuilding arrays once on load is acceptable.
; =============================================================================

; Each index corresponds to an alias slot (0-4)
; State: 0=empty/processing, 1=traveling, 2=at_destination, 3=returning, 5=search_wait, 8=at_target
Int[] Property SlotStates Auto
String[] Property SlotTaskTypes Auto      ; "travel", "fetch_npc", "deliver_message", "fetch_item", "scheduled"
String[] Property SlotTargetNames Auto    ; Target NPC/item/location name
Float[] Property SlotDeadlines Auto       ; Wait deadline (game time)
Int[] Property SlotSpeeds Auto            ; 0=walk, 1=jog, 2=run

; Track if databases are loaded
Bool databaseLoaded = false

; =============================================================================
; INITIALIZATION
; =============================================================================

; NOTE: Quest scripts do NOT receive OnPlayerLoadGame events.
; The PlayerAlias (with IntelEngine_MCM script) calls Maintenance() on load.
; This is the modern approach that avoids needing SEQ files.

Event OnInit()
    ; OnInit fires when the quest first starts (either via Start Game Enabled + SEQ,
    ; or when manually started by the player alias script)
    DebugMsg("IntelEngine Quest OnInit")
EndEvent

Function Maintenance(Bool isFirstLoad = false)
    {
        Called by PlayerAlias on every game load.
        isFirstLoad = true when mod is first installed (OnInit on alias)
        isFirstLoad = false on subsequent loads (OnPlayerLoadGame on alias)
    }
    DebugMsg("IntelEngine Maintenance (firstLoad=" + isFirstLoad + ")")

    ; On first install (new game), clear all StorageUtil data from previous sessions.
    ; StorageUtil persists outside the save system, so stale data from other saves
    ; would otherwise bleed into the new game.
    If isFirstLoad
        Int cleared = StorageUtil.ClearAllPrefix("Intel_")
        DebugMsg("Cleared " + cleared + " stale StorageUtil keys")

        ; MCM defaults — enabled by default on fresh install
        Actor player = Game.GetPlayer()
        StorageUtil.SetIntValue(player, "Intel_TaskConfirmPrompt", 1)
        StorageUtil.SetIntValue(player, "Intel_DeliveryReportBack", 1)
        StorageUtil.SetFloatValue(player, "Intel_MeetingTimeoutHours", 3.0)
    EndIf

    ; Initialize arrays if needed
    If SlotStates == None || SlotStates.Length != MAX_SLOTS
        InitializeSlotArrays()
    EndIf

    LoadDatabases()

    ; Only recover tasks on subsequent loads, not first install
    If !isFirstLoad
        RecoverActiveTasks()
    EndIf

    ; Register SkyrimNet tag for action eligibility filtering.
    ; This allows SkyrimNet to filter out NPCs with active tasks.
    RegisterSkyrimNetTag()

    ; Restart monitoring loops on all task scripts.
    ; RegisterForSingleUpdate is per-script and does NOT survive save/load,
    ; so we must explicitly restart each script's update loop here.
    If Travel
        Travel.RestartMonitoring()
    EndIf
    If NPCTasks
        NPCTasks.RestartMonitoring()
    EndIf
    If Schedule
        Schedule.RestartMonitoring()
    EndIf
EndFunction

Function InitializeSlotArrays()
    SlotStates = new Int[5]
    SlotTaskTypes = new String[5]
    SlotTargetNames = new String[5]
    SlotDeadlines = new Float[5]
    SlotSpeeds = new Int[5]

    Int i = 0
    While i < MAX_SLOTS
        SlotStates[i] = 0
        SlotTaskTypes[i] = ""
        SlotTargetNames[i] = ""
        SlotDeadlines[i] = 0.0
        SlotSpeeds[i] = 0
        i += 1
    EndWhile

    DebugMsg("Slot arrays initialized")
EndFunction

; =============================================================================
; INDEX VERIFICATION
; =============================================================================

Function LoadDatabases()
    ; Indexes are built automatically by the DLL from game data at startup
    ; This function just verifies they're ready

    If databaseLoaded && IntelEngine.IsIndexLoaded()
        Return
    EndIf

    DebugMsg("Verifying indexes...")

    If IntelEngine.IsIndexLoaded()
        databaseLoaded = true
        String stats = IntelEngine.GetIndexStats()
        DebugMsg("Indexes loaded: " + stats)
    Else
        DebugMsg("WARNING: Indexes not yet loaded - DLL may not be installed")
    EndIf
EndFunction

; =============================================================================
; TASK HISTORY
; =============================================================================

Function SaveTaskToHistory(Actor akAgent, String taskType, String target, String result, String msgContent, String meetLocation)
    {
        Saves a completed task to the NPC's rolling history (max 10 entries).
        Called from ClearSlot before task data is wiped.
    }
    If akAgent == None || taskType == ""
        Return
    EndIf

    ; Skip cancelled tasks — they shouldn't appear in history
    If result == "cancelled"
        DebugMsg(akAgent.GetDisplayName() + " task cancelled — skipping history")
        Return
    EndIf

    ; Build past-tense description based on task type and result
    String desc = ""

    If taskType == "travel"
        If result == "timeout"
            desc = "Went to " + target + " but gave up waiting"
        Else
            desc = "Traveled to " + target
        EndIf
    ElseIf taskType == "fetch_npc"
        If result == "success"
            desc = "Found " + target + " and brought them back"
        Else
            desc = "Looked for " + target + " but couldn't bring them"
        EndIf
    ElseIf taskType == "deliver_message"
        If result == "delivered"
            desc = "Delivered a message to " + target
            If msgContent != ""
                ; Truncate long messages
                If StringUtil.GetLength(msgContent) > 80
                    msgContent = StringUtil.Substring(msgContent, 0, 80) + "..."
                EndIf
                desc = desc + ": '" + msgContent + "'"
            EndIf
            If meetLocation != ""
                desc = desc + " (meeting at " + meetLocation + ")"
            EndIf
        Else
            desc = "Tried to deliver a message to " + target
        EndIf
    ElseIf taskType == "search_for_actor"
        desc = "Searched for " + target
    Else
        desc = "Completed a task involving " + target
    EndIf

    ; Append to history lists
    StorageUtil.StringListAdd(akAgent, "Intel_TaskHistory", desc)
    StorageUtil.FloatListAdd(akAgent, "Intel_TaskHistoryTime", Utility.GetCurrentGameTime())

    ; Cap at 10 entries (remove oldest)
    While StorageUtil.StringListCount(akAgent, "Intel_TaskHistory") > 10
        StorageUtil.StringListRemoveAt(akAgent, "Intel_TaskHistory", 0)
        StorageUtil.FloatListRemoveAt(akAgent, "Intel_TaskHistoryTime", 0)
    EndWhile

    DebugMsg(akAgent.GetDisplayName() + " task history saved: " + desc)
EndFunction

; =============================================================================
; MESSAGE PERSISTENCE API
; =============================================================================

Function StoreReceivedMessage(Actor akRecipient, Actor akSender, String msgContent)
    {
        Stores a message on the recipient NPC so they remember receiving it.
        Called by IntelEngine_NPCTasks when a message is delivered.
    }
    If akRecipient == None || msgContent == ""
        Return
    EndIf

    String senderName = "someone"
    If akSender
        senderName = akSender.GetDisplayName()
    EndIf

    StorageUtil.SetStringValue(akRecipient, "Intel_ReceivedMessage", msgContent)
    StorageUtil.SetStringValue(akRecipient, "Intel_MessageSender", senderName)
    StorageUtil.SetFloatValue(akRecipient, "Intel_MessageTime", Utility.GetCurrentGameTime())

    DebugMsg(akRecipient.GetDisplayName() + " received message from " + senderName)
EndFunction

Function ClearReceivedMessage(Actor akNPC)
    {
        Clears the stored message from an NPC.
        Call this when the NPC acknowledges or forgets the message.
    }
    If akNPC == None
        Return
    EndIf

    StorageUtil.UnsetStringValue(akNPC, "Intel_ReceivedMessage")
    StorageUtil.UnsetStringValue(akNPC, "Intel_MessageSender")
    StorageUtil.UnsetFloatValue(akNPC, "Intel_MessageTime")
EndFunction

; =============================================================================
; MEETING OUTCOME API
; =============================================================================

Function StoreMeetingOutcome(Actor akNPC, String outcome, String dest)
    {
        Stores meeting outcome on the NPC for prompt display.
        Called by Travel after meeting completes or times out.
        Outcomes: "success", "player_late", "player_slightly_late", "player_no_show"
    }
    If akNPC == None
        Return
    EndIf

    StorageUtil.SetStringValue(akNPC, "Intel_MeetingOutcome", outcome)
    StorageUtil.SetStringValue(akNPC, "Intel_MeetingOutcomeDest", dest)
    StorageUtil.SetFloatValue(akNPC, "Intel_MeetingOutcomeTime", Utility.GetCurrentGameTime())

    DebugMsg(akNPC.GetDisplayName() + " meeting outcome: " + outcome + " at " + dest)
EndFunction

Function ClearMeetingOutcome(Actor akNPC)
    {
        Clears meeting outcome from an NPC.
        Call when the outcome has been acknowledged or is no longer relevant.
    }
    If akNPC == None
        Return
    EndIf

    StorageUtil.UnsetStringValue(akNPC, "Intel_MeetingOutcome")
    StorageUtil.UnsetStringValue(akNPC, "Intel_MeetingOutcomeDest")
    StorageUtil.UnsetFloatValue(akNPC, "Intel_MeetingOutcomeTime")
    StorageUtil.UnsetFloatValue(akNPC, "Intel_MeetingLateHours")
EndFunction

; =============================================================================
; SLOT MANAGEMENT
; =============================================================================

ReferenceAlias Function GetAgentAlias(Int slot)
    If slot == 0
        Return AgentAlias00
    ElseIf slot == 1
        Return AgentAlias01
    ElseIf slot == 2
        Return AgentAlias02
    ElseIf slot == 3
        Return AgentAlias03
    ElseIf slot == 4
        Return AgentAlias04
    EndIf
    Return None
EndFunction

ReferenceAlias Function GetTargetAlias(Int slot)
    If slot == 0
        Return TargetAlias00
    ElseIf slot == 1
        Return TargetAlias01
    ElseIf slot == 2
        Return TargetAlias02
    ElseIf slot == 3
        Return TargetAlias03
    ElseIf slot == 4
        Return TargetAlias04
    EndIf
    Return None
EndFunction

Int Function FindFreeAgentSlot()
    ; Respect user-configured max concurrent tasks
    Int maxAllowed = MAX_SLOTS
    If IntelEngine_MaxConcurrentTasks != None
        maxAllowed = IntelEngine_MaxConcurrentTasks.GetValue() as Int
        If maxAllowed > MAX_SLOTS
            maxAllowed = MAX_SLOTS
        ElseIf maxAllowed < 1
            maxAllowed = 1
        EndIf
    EndIf

    Int activeCount = 0
    Int firstFree = -1
    Int i = 0
    While i < MAX_SLOTS
        If SlotStates[i] != 0
            activeCount += 1
        ElseIf firstFree < 0
            firstFree = i
        EndIf
        i += 1
    EndWhile

    If firstFree >= 0 && activeCount < maxAllowed
        Return firstFree
    EndIf
    Return -1
EndFunction

Int Function FindSlotByAgent(Actor akAgent)
    If akAgent == None
        Return -1
    EndIf

    Int i = 0
    While i < MAX_SLOTS
        If SlotStates[i] != 0
            ReferenceAlias slotAlias = GetAgentAlias(i)
            If slotAlias && slotAlias.GetActorReference() == akAgent
                Return i
            EndIf
        EndIf
        i += 1
    EndWhile
    Return -1
EndFunction

Int Function FindSlotByActor(Actor akActor)
    {Find slot where akActor is either the agent OR the target. Returns -1 if not found.}
    If akActor == None
        Return -1
    EndIf

    Int i = 0
    While i < MAX_SLOTS
        If SlotStates[i] != 0
            ReferenceAlias agentAlias = GetAgentAlias(i)
            If agentAlias && agentAlias.GetActorReference() == akActor
                Return i
            EndIf
            ReferenceAlias targetAlias = GetTargetAlias(i)
            If targetAlias && targetAlias.GetActorReference() == akActor
                Return i
            EndIf
        EndIf
        i += 1
    EndWhile
    Return -1
EndFunction

Function AllocateSlot(Int slot, Actor akAgent, String taskType, String targetName, Int speed)
    ; Assign agent to alias
    ReferenceAlias slotAlias = GetAgentAlias(slot)
    slotAlias.ForceRefTo(akAgent)

    ; Add to task faction
    akAgent.AddToFaction(IntelEngine_TaskFaction)

    ; Update slot tracking
    SlotStates[slot] = 1  ; traveling
    SlotTaskTypes[slot] = taskType
    SlotTargetNames[slot] = targetName
    SlotSpeeds[slot] = speed
    SlotDeadlines[slot] = 0.0

    ; Store on actor for persistence
    StorageUtil.SetStringValue(akAgent, "Intel_TaskType", taskType)
    StorageUtil.SetStringValue(akAgent, "Intel_Target", targetName)
    StorageUtil.SetIntValue(akAgent, "Intel_Slot", slot)
    StorageUtil.SetIntValue(akAgent, "Intel_State", 1)
    StorageUtil.SetIntValue(akAgent, "Intel_Speed", speed)

    ; Push to C++ SlotTracker for SkyrimNet decorators/eligibility
    IntelEngine.UpdateSlotState(slot, akAgent, 1, taskType, targetName)

    DebugMsg("Allocated slot " + slot + " to " + akAgent.GetDisplayName() + " for " + taskType)
EndFunction

Function ClearSlot(Int slot, Bool restoreNPC = true, Bool intelPackagesOnly = false)
    If slot < 0 || slot >= MAX_SLOTS
        Return
    EndIf

    ReferenceAlias agentAlias = GetAgentAlias(slot)
    ReferenceAlias targetAlias = GetTargetAlias(slot)

    ; Clean up agent
    If agentAlias
        Actor agent = agentAlias.GetActorReference()
        If agent
            DebugMsg("Clearing slot " + slot + ": " + agent.GetDisplayName())

            ; Save to task history before clearing
            String histType = SlotTaskTypes[slot]
            String histTarget = SlotTargetNames[slot]
            String histResult = StorageUtil.GetStringValue(agent, "Intel_Result")
            String histMessage = StorageUtil.GetStringValue(agent, "Intel_Message")
            String histMeetLoc = StorageUtil.GetStringValue(agent, "Intel_DeliveryMeetLocation")
            If histType != ""
                SaveTaskToHistory(agent, histType, histTarget, histResult, histMessage, histMeetLoc)
            EndIf

            ; Remove packages — for followers, only remove IntelEngine packages
            ; to preserve NFF/SkyrimNet follow packages
            If intelPackagesOnly
                RemoveIntelPackages(agent)
            Else
                RemoveAllPackages(agent)
            EndIf

            ; Clear linked refs
            ClearLinkedRefs(agent)

            ; Remove from task faction
            agent.RemoveFromFaction(IntelEngine_TaskFaction)

            ; Clear StorageUtil data
            StorageUtil.UnsetStringValue(agent, "Intel_TaskType")
            StorageUtil.UnsetStringValue(agent, "Intel_Target")
            StorageUtil.UnsetIntValue(agent, "Intel_Slot")
            StorageUtil.UnsetIntValue(agent, "Intel_State")
            StorageUtil.UnsetIntValue(agent, "Intel_Speed")
            StorageUtil.UnsetFormValue(agent, "Intel_TargetNPC")
            StorageUtil.UnsetStringValue(agent, "Intel_Message")
            StorageUtil.UnsetFloatValue(agent, "Intel_ScheduledTime")

            ; Clear travel/navigation data
            StorageUtil.UnsetFormValue(agent, "Intel_DestMarker")
            StorageUtil.UnsetFormValue(agent, "Intel_ReturnMarker")
            StorageUtil.UnsetFormValue(agent, "Intel_CurrentWaypoint")
            StorageUtil.UnsetFloatValue(agent, "Intel_TaskStartTime")
            StorageUtil.UnsetFloatValue(agent, "Intel_TravelArrivalTime")
            StorageUtil.UnsetFloatValue(agent, "Intel_WaitHours")
            StorageUtil.UnsetFloatValue(agent, "Intel_Deadline")
            StorageUtil.UnsetIntValue(agent, "Intel_WasFollower")

            ; Clear fetch/deliver task data
            StorageUtil.UnsetIntValue(agent, "Intel_InteractCyclesRemaining")
            StorageUtil.UnsetIntValue(agent, "Intel_ShouldFail")
            StorageUtil.UnsetStringValue(agent, "Intel_FailReason")
            StorageUtil.UnsetStringValue(agent, "Intel_Result")
            StorageUtil.UnsetIntValue(agent, "Intel_TargetWaitCycles")
            StorageUtil.UnsetFloatValue(agent, "Intel_TargetLastDist")
            StorageUtil.UnsetIntValue(agent, "Intel_ReturnCycles")

            ; Clear delivery meeting data
            StorageUtil.UnsetStringValue(agent, "Intel_DeliveryMeetLocation")
            StorageUtil.UnsetStringValue(agent, "Intel_DeliveryMeetTime")

            ; Reset C++ departure detector and off-screen tracker for this slot
            IntelEngine.ResetDepartureSlot(slot, None)
            IntelEngine.ResetOffScreenSlot(slot)
            StorageUtil.UnsetFloatValue(agent, "Intel_OffscreenArrival")

            ; Clear scheduled meeting flag + schedule slot arrays
            ; Without clearing the arrays, OnUpdateGameTime can re-dispatch
            ; the same meeting if Intel_ScheduledState gets reset to 0 here.
            StorageUtil.UnsetIntValue(agent, "Intel_IsScheduledMeeting")
            If Schedule
                Schedule.ClearScheduleSlotByAgent(agent)
            EndIf
            StorageUtil.UnsetIntValue(agent, "Intel_ScheduledState")
            StorageUtil.UnsetFloatValue(agent, "Intel_ScheduledDepartureHours")

            ; Clear meeting tracking data (NOT outcome data — that persists for prompts)
            ; Intel_MeetingPlayerName is kept — outcome prompt (0199) needs it after slot cleanup
            StorageUtil.UnsetFloatValue(agent, "Intel_MeetingTime")
            StorageUtil.UnsetStringValue(agent, "Intel_MeetingDest")
            StorageUtil.UnsetFloatValue(agent, "Intel_MeetingNpcArrivalTime")
            StorageUtil.UnsetIntValue(agent, "Intel_MeetingLingering")
            StorageUtil.UnsetIntValue(agent, "Intel_MeetingLingerApproaching")
            StorageUtil.UnsetFloatValue(agent, "Intel_MeetingLingerDeadline")
            StorageUtil.UnsetIntValue(agent, "Intel_MeetingApproaching")
            StorageUtil.UnsetIntValue(agent, "Intel_LingerFarTicks")
            StorageUtil.UnsetFloatValue(agent, "Intel_ApproachStartX")
            StorageUtil.UnsetFloatValue(agent, "Intel_ApproachStartY")
            StorageUtil.UnsetIntValue(agent, "Intel_ApproachTick")
            StorageUtil.UnsetIntValue(agent, "Intel_ApproachStuckNarrated")
            StorageUtil.UnsetIntValue(agent, "Intel_TaskStuckNarrated")

            ; Clear travel linger flag
            StorageUtil.UnsetIntValue(agent, "Intel_TravelLingering")

            ; Clear off-screen return tracking
            StorageUtil.UnsetIntValue(agent, "Intel_OffScreenCycles")
            StorageUtil.UnsetFloatValue(agent, "Intel_OffScreenLastDist")

            ; Re-lock home door if we unlocked one (anti-trespass cleanup)
            Int unlockedCellId = StorageUtil.GetIntValue(agent, "Intel_UnlockedHomeCellId")
            If unlockedCellId != 0
                IntelEngine.SetHomeDoorAccessForCell(unlockedCellId, false)
                StorageUtil.UnsetIntValue(agent, "Intel_UnlockedHomeCellId")
                DebugMsg("Re-locked home door for cell " + unlockedCellId)
            EndIf

            ; Clear task cooldown
            StorageUtil.UnsetFloatValue(agent, "Intel_TaskCooldown")

            ; Re-evaluate AI
            agent.EvaluatePackage()
        EndIf
        agentAlias.Clear()
    EndIf

    ; Clean up target if any — use RemoveIntelPackages to preserve SkyrimNet packages
    If targetAlias
        Actor target = targetAlias.GetActorReference()
        If target
            RemoveIntelPackages(target)
            ClearLinkedRefs(target)
            target.EvaluatePackage()
        EndIf
        targetAlias.Clear()
    EndIf

    ; Reset slot arrays
    SlotStates[slot] = 0
    SlotTaskTypes[slot] = ""
    SlotTargetNames[slot] = ""
    SlotDeadlines[slot] = 0.0
    SlotSpeeds[slot] = 0

    ; Push to C++ SlotTracker for SkyrimNet decorators/eligibility
    IntelEngine.ClearSlotState(slot)
EndFunction

; =============================================================================
; TASK CONTROL (cancel, speed change — called by SkyrimNet actions)
; =============================================================================

Bool Function CancelCurrentTask(Actor akNPC)
    {Cancel the NPC's current task entirely. Called by CancelCurrentTask action.}
    If akNPC == None
        Return false
    EndIf
    Int slot = FindSlotByAgent(akNPC)
    If slot < 0
        Return false
    EndIf

    StorageUtil.SetStringValue(akNPC, "Intel_Result", "cancelled")
    ClearSlotRestoreFollower(slot, akNPC)
    Return true
EndFunction

Bool Function ChangeTaskSpeed(Actor akNPC, Int newSpeed)
    {Change travel speed mid-task. Called by ChangeSpeed action.}
    If akNPC == None
        Return false
    EndIf
    Int slot = FindSlotByAgent(akNPC)
    If slot < 0
        Return false
    EndIf
    ; Only change speed while actively traveling (states 1, 3)
    Int taskState = SlotStates[slot]
    If taskState != 1 && taskState != 3
        Return false
    EndIf
    ; Clamp speed to valid range (0=walk, 1=jog, 2=run)
    If newSpeed < 0
        newSpeed = 0
    ElseIf newSpeed > 2
        newSpeed = 2
    EndIf
    Int oldSpeed = SlotSpeeds[slot]
    If oldSpeed == newSpeed
        Return true
    EndIf
    ; Swap travel package
    Package oldPkg = GetTravelPackage(oldSpeed)
    Package newPkg = GetTravelPackage(newSpeed)
    ActorUtil.RemovePackageOverride(akNPC, oldPkg)
    ActorUtil.AddPackageOverride(akNPC, newPkg, PRIORITY_TRAVEL, 1)
    akNPC.EvaluatePackage()
    SetSlotSpeed(slot, akNPC, newSpeed)
    DebugMsg(akNPC.GetDisplayName() + " speed changed: " + oldSpeed + " -> " + newSpeed)
    Return true
EndFunction

; =============================================================================
; SLOT STATE UPDATES (single source of truth for mid-task state changes)
;
; These functions ensure both arrays and StorageUtil stay in sync.
; All state/speed/deadline changes outside AllocateSlot/ClearSlot MUST
; use these functions instead of writing to arrays or StorageUtil directly.
; =============================================================================

Function SetSlotState(Int slot, Actor akAgent, Int newState)
    {Update task state — writes both array, StorageUtil, and C++ SlotTracker.}
    If slot < 0 || slot >= MAX_SLOTS
        Return
    EndIf
    SlotStates[slot] = newState
    If akAgent != None
        StorageUtil.SetIntValue(akAgent, "Intel_State", newState)
    EndIf

    ; Push to C++ SlotTracker for SkyrimNet decorators/eligibility
    IntelEngine.UpdateSlotState(slot, akAgent, newState, SlotTaskTypes[slot], SlotTargetNames[slot])
EndFunction

Function SetSlotSpeed(Int slot, Actor akAgent, Int newSpeed)
    {Update travel speed — writes both array and StorageUtil.}
    If slot < 0 || slot >= MAX_SLOTS
        Return
    EndIf
    SlotSpeeds[slot] = newSpeed
    If akAgent != None
        StorageUtil.SetIntValue(akAgent, "Intel_Speed", newSpeed)
    EndIf
EndFunction

Function SetSlotDeadline(Int slot, Float deadline)
    {Update wait deadline — persisted to StorageUtil so it survives save/load.}
    If slot < 0 || slot >= MAX_SLOTS
        Return
    EndIf
    SlotDeadlines[slot] = deadline
    ; Persist to agent so RecoverActiveTasks can restore it
    ReferenceAlias agentAlias = GetAgentAlias(slot)
    If agentAlias
        Actor agent = agentAlias.GetActorReference()
        If agent
            StorageUtil.SetFloatValue(agent, "Intel_Deadline", deadline)
        EndIf
    EndIf
EndFunction

Function ClearSlotRestoreFollower(Int slot, Actor akAgent)
    {Clear a task slot and restore follower status if the agent was a follower.
    Reads Intel_WasFollower BEFORE ClearSlot wipes it, then restores teammate.
    For followers: only removes IntelEngine packages, preserving NFF/SkyrimNet
    follow packages so the NPC resumes following without needing a re-kick.}
    Bool wasFollower = StorageUtil.GetIntValue(akAgent, "Intel_WasFollower") as Bool
    ClearSlot(slot, true, wasFollower)
    If wasFollower
        akAgent.SetPlayerTeammate(true)
        akAgent.EvaluatePackage()
    EndIf
EndFunction

Function MarkSlotProcessing(Int slot, Actor akAgent)
    {Mark slot as being processed — prevents re-entry from monitoring loops.
    Unlike direct SlotStates[slot]=0, this also updates StorageUtil to prevent
    stale state surviving a save/load between here and ClearSlot.}
    If slot < 0 || slot >= MAX_SLOTS
        Return
    EndIf
    SlotStates[slot] = 0
    If akAgent != None
        StorageUtil.SetIntValue(akAgent, "Intel_State", 0)
    EndIf
EndFunction

; =============================================================================
; SHARED TASK HELPERS (DRY — called by Travel, NPCTasks, Schedule)
; =============================================================================

Bool Function IsDuplicateTask(Actor npc, String taskType, String target)
    {Returns true if NPC is already doing the exact same task. Caller should return false.}
    If !npc.IsInFaction(IntelEngine_TaskFaction)
        Return false
    EndIf
    String currentTask = StorageUtil.GetStringValue(npc, "Intel_TaskType")
    String currentTarget = StorageUtil.GetStringValue(npc, "Intel_Target")
    If currentTask == taskType && currentTarget == target
        DebugMsg("Duplicate task ignored: " + npc.GetDisplayName() + " already on " + taskType + " → " + target)
        Return true
    EndIf
    Return false
EndFunction

Function OverrideExistingTask(Actor npc)
    {If NPC is already on a task, clear it to make room for the new one.}
    If npc.IsInFaction(IntelEngine_TaskFaction)
        Int existingSlot = FindSlotByAgent(npc)
        If existingSlot >= 0
            DebugMsg(npc.GetDisplayName() + " overriding active task in slot " + existingSlot)
            ClearSlot(existingSlot, true)
        EndIf
    EndIf
EndFunction

Function DismissFollowerForTask(Actor npc)
    {Prepare NPC for a new IntelEngine task by clearing ALL package overrides.

    Uses ActorUtil.ClearPackageOverride to remove overrides from ALL sources —
    IntelEngine, SkyrimNet (companion follow, TalkToPlayer), and any other mod.
    IntelEngine's task functions (GoToLocation, FetchNPC, etc.) immediately apply
    their own packages after this call, so the NPC is never left without overrides.

    Why blanket clear instead of removing specific packages:
    SkyrimNet's companion follow system uses its own package overrides that are
    invisible to IntelEngine. SetPlayerTeammate(false) only clears the vanilla
    follower flag — SkyrimNet's follow package stays active and overrides the
    travel package, causing the NPC to follow the player instead of traveling.
    Diagnosed via Ingrid's Western Watchtower trip where she followed the player
    for 1.5 hours instead of walking to the destination, with no stuck detection
    (she was moving, just not toward the destination).

    Note: EvaluatePackage is NOT called here — callers apply their own packages
    first, then evaluate. This prevents a brief gap where the NPC has no overrides
    and reverts to default AI.}

    ; Clear ALL package overrides from all sources
    ActorUtil.ClearPackageOverride(npc)
    DebugMsg("Cleared all package overrides for " + npc.GetDisplayName())

    ; Also clear vanilla follower state so the engine doesn't re-apply follow AI
    If npc.IsPlayerTeammate()
        StorageUtil.SetIntValue(npc, "Intel_WasFollower", 1)
        npc.SetPlayerTeammate(false)
        DebugMsg("Dismissed follower: " + npc.GetDisplayName())
    EndIf
EndFunction

Int Function ShowTaskConfirmation(Actor npc, String promptText)
    {Show MCM task confirmation if enabled. Returns: 0=allow, 1=deny (narrate), 2=deny silent.}
    If StorageUtil.GetIntValue(Game.GetPlayer(), "Intel_TaskConfirmPrompt") != 1
        Return 0
    EndIf
    String result = SkyMessage.Show(promptText, "Allow", "Deny", "Deny (Silent)")
    If result == "Deny"
        Return 1
    ElseIf result == "Allow"
        Return 0
    EndIf
    Return 2
EndFunction

Function InitializeStuckTrackingForSlot(Int slot, Actor npc)
    {Reset C++ StuckDetector and record task start time.}
    IntelEngine.ResetStuckSlot(slot, npc)
    StorageUtil.SetFloatValue(npc, "Intel_TaskStartTime", Utility.GetCurrentGameTime())
EndFunction

Function InitializeDepartureTracking(Int slot, Actor npc)
    {Reset departure tracking for a slot via C++ DepartureDetector.
    Stores NPC's current XY position as baseline. All position math
    and tick counting happens in native code — no StorageUtil overhead.}
    IntelEngine.ResetDepartureSlot(slot, npc)
EndFunction

Function InitOffScreenTracking(Int slot, Actor npc, ObjectReference dest)
    {Calculate estimated arrival time from distance and initialize C++ tracker.
    Shared by Travel, NPCTasks, and any future task that involves traveling.
    Uses CalculateDeadlineFromDistance for consistent speed estimation.}
    If npc == None || dest == None
        Return
    EndIf
    Float estimatedArrival = IntelEngine.CalculateDeadlineFromDistance(npc, dest, false, 0.5, 18.0)
    IntelEngine.InitOffScreenTravel(slot, estimatedArrival, npc)
    StorageUtil.SetFloatValue(npc, "Intel_OffscreenArrival", estimatedArrival)
    DebugMsg(npc.GetDisplayName() + " off-screen tracking: est. arrival in " + ((estimatedArrival - Utility.GetCurrentGameTime()) * 24.0) + "h")
EndFunction

Function UnlockHomeForTask(Actor akAgent, Actor targetNPC)
    {Anti-trespass: unlock target NPC's home door so agent can enter.
    Stores cell ID on agent for re-locking in ClearSlot.
    Shared by FetchNPC, DeliverMessage, SearchForActor — all have an Actor target.
    Travel uses SetHomeDoorAccessForCell directly (has cell ID from ResolveAnyDestination).}
    ObjectReference homeDoor = IntelEngine.SetHomeDoorAccess(targetNPC, true)
    If homeDoor != None
        Int homeCellId = IntelEngine.GetLastResolvedHomeCellId()
        If homeCellId != 0
            StorageUtil.SetIntValue(akAgent, "Intel_UnlockedHomeCellId", homeCellId)
        EndIf
        DebugMsg("Unlocked " + targetNPC.GetDisplayName() + "'s home door for task")
    EndIf
EndFunction

Bool Function HandleOffScreenTravel(Int slot, Actor npc, ObjectReference dest)
    {Check if off-screen NPC should be teleported to destination.
    Returns true if teleported (caller should handle arrival).
    Returns false if still in transit (do nothing).}
    Int status = IntelEngine.CheckOffScreenProgress(slot, npc, Utility.GetCurrentGameTime())
    If status == 1
        DebugMsg(npc.GetDisplayName() + " off-screen arrival (estimated time elapsed)")
        npc.MoveTo(dest)
        Utility.Wait(0.3)
        npc.EvaluatePackage()
        Return true
    EndIf
    Return false
EndFunction

Function SoftStuckRecovery(Actor npc, Int slot, ObjectReference dest)
    {Soft stuck recovery: random displacement + re-apply travel + pathfinding nudge.
    Shared by Travel and NPCTasks stuck handlers.}
    Float nudge = 100.0
    If !npc.Is3DLoaded()
        nudge = 200.0
    EndIf
    npc.MoveTo(npc, Utility.RandomFloat(-nudge, nudge), Utility.RandomFloat(-nudge, nudge), 50.0, false)

    Int speed = SlotSpeeds[slot]
    Package travelPkg = GetTravelPackage(speed)
    If travelPkg
        ActorUtil.AddPackageOverride(npc, travelPkg, PRIORITY_TRAVEL, 1)
    EndIf
    npc.EvaluatePackage()

    If dest != None
        Utility.Wait(0.5)
        npc.PathToReference(dest, 1.0)
        npc.EvaluatePackage()
    EndIf
EndFunction

Function RemoveAllPackages(Actor akActor, Bool evaluate = true)
    ; Clear ALL package overrides from any source (IntelEngine, SkyrimNet, etc.)
    ; WARNING: This strips packages from ALL mods. Only use on task agents that
    ; IntelEngine fully owns. For targets (fetched/escorted NPCs), use
    ; RemoveIntelPackages() instead to preserve SkyrimNet packages.
    ; Pass evaluate=false when adding a new package immediately after (prevents brief base-AI gap)
    ActorUtil.ClearPackageOverride(akActor)
    If evaluate
        akActor.EvaluatePackage()
    EndIf
EndFunction

Function RemoveIntelPackages(Actor akActor, Bool evaluate = true)
    {Remove only IntelEngine package overrides, preserving packages from other
    mods (SkyrimNet FollowPlayer, SeverAction, etc.). Use this for target NPCs
    that IntelEngine doesn't fully own via a task slot.
    Pass evaluate=false when adding a new package immediately after.}
    ActorUtil.RemovePackageOverride(akActor, TravelPackage_Walk)
    ActorUtil.RemovePackageOverride(akActor, TravelPackage_Jog)
    ActorUtil.RemovePackageOverride(akActor, TravelPackage_Run)
    If SandboxPackage
        ActorUtil.RemovePackageOverride(akActor, SandboxPackage)
    EndIf
    If SandboxNearPlayerPackage
        ActorUtil.RemovePackageOverride(akActor, SandboxNearPlayerPackage)
    EndIf
    If evaluate
        akActor.EvaluatePackage()
    EndIf
EndFunction

Function ClearLinkedRefs(Actor akActor)
    If IntelEngine_TravelTarget
        PO3_SKSEFunctions.SetLinkedRef(akActor, None, IntelEngine_TravelTarget)
    EndIf
    If IntelEngine_EscortTarget
        PO3_SKSEFunctions.SetLinkedRef(akActor, None, IntelEngine_EscortTarget)
    EndIf
    If IntelEngine_AgentLink
        PO3_SKSEFunctions.SetLinkedRef(akActor, None, IntelEngine_AgentLink)
    EndIf
    If IntelEngine_WaitLocation
        PO3_SKSEFunctions.SetLinkedRef(akActor, None, IntelEngine_WaitLocation)
    EndIf
EndFunction

Function TeleportBehindPlayer(Actor npc, Float distance = 2000.0)
    {Teleport an NPC behind the player's camera so they don't pop into view.
    Used by stuck recovery fallbacks in Travel and NPCTasks.
    Distance can be reduced on retry if the NPC lands behind a wall.}
    Actor player = Game.GetPlayer()
    Float[] offset = IntelEngine.GetOffsetBehind(player, distance)
    npc.MoveTo(player, offset[0], offset[1], 0.0, false)
    DebugMsg(npc.GetDisplayName() + " teleported behind player at " + distance + " units")
EndFunction


; =============================================================================
; DEPARTURE DETECTION
;
; Delegates position tracking and tick counting to the C++ DepartureDetector
; singleton. Only the Papyrus engine responses (EvaluatePackage, PathTo)
; remain here. Eliminates 5-8 StorageUtil reads/writes per check cycle.
;
; Returns: 0=too_early, 1=departed, 2=soft_recovery_done, 3=escalate
; =============================================================================

Int Function CheckDepartureProgress(Int slot, Actor agent, Float threshold)
    {Check if an NPC has departed from their starting position.
    Position tracking and tick counting done in C++ DepartureDetector.
    Returns: 0=too early, 1=departed, 2=soft recovery applied, 3=escalate.}
    Int status = IntelEngine.CheckDepartureStatus(agent, slot, threshold)

    If status == 2
        ; Soft recovery — nudge AI packages to get NPC moving
        DebugMsg(agent.GetDisplayName() + " hasn't departed — nudging package evaluation")
        agent.EvaluatePackage()

        ObjectReference dest = StorageUtil.GetFormValue(agent, "Intel_DestMarker") as ObjectReference
        If dest != None
            agent.PathToReference(dest, 1.0)
            agent.EvaluatePackage()
        EndIf
    EndIf

    Return status
EndFunction

; =============================================================================
; TASK RECOVERY (on game load)
; =============================================================================

Function RecoverActiveTasks()
    DebugMsg("Recovering active tasks...")

    Int i = 0
    While i < MAX_SLOTS
        ReferenceAlias slotAlias = GetAgentAlias(i)
        If slotAlias
            Actor agent = slotAlias.GetActorReference()
            If agent && !agent.IsDead()
                ; Recover state from StorageUtil
                String taskType = StorageUtil.GetStringValue(agent, "Intel_TaskType")
                If taskType != ""
                    Int savedState = StorageUtil.GetIntValue(agent, "Intel_State")
                    String target = StorageUtil.GetStringValue(agent, "Intel_Target")
                    Int speed = StorageUtil.GetIntValue(agent, "Intel_Speed")

                    SlotStates[i] = savedState
                    SlotTaskTypes[i] = taskType
                    SlotTargetNames[i] = target
                    SlotSpeeds[i] = speed

                    ; Recover deadline — if persisted value exists, use it.
                    ; If not (old save), set a fallback deadline of MAX_TASK_HOURS from now.
                    Float savedDeadline = StorageUtil.GetFloatValue(agent, "Intel_Deadline")
                    If savedDeadline > 0.0
                        SlotDeadlines[i] = savedDeadline
                    Else
                        ; No saved deadline — set a fresh one so the task can't stall forever
                        SlotDeadlines[i] = Utility.GetCurrentGameTime() + (6.0 / 24.0)
                        DebugMsg("No saved deadline for slot " + i + " — set fallback 6h from now")
                    EndIf

                    ; Re-init off-screen tracker from persisted arrival estimate
                    Float offscreenArrival = StorageUtil.GetFloatValue(agent, "Intel_OffscreenArrival", 0.0)
                    If offscreenArrival > 0.0
                        IntelEngine.InitOffScreenTravel(i, offscreenArrival, agent)
                    EndIf

                    DebugMsg("Recovered task in slot " + i + ": " + taskType + " → " + target)
                Else
                    ; No task data, clear slot
                    ClearSlot(i)
                EndIf
            Else
                ; Empty or dead, clear slot
                ClearSlot(i)
            EndIf
        EndIf
        i += 1
    EndWhile

    ; Re-sync C++ SlotTracker from recovered arrays (save-safe)
    ; On game load, C++ SlotTracker is empty (cleared in kPostLoadGame).
    ; This pushes ALL recovered slot state in a single native call so
    ; SkyrimNet decorators and eligibility tags reflect the loaded state.
    SyncSlotTrackerFromArrays()
EndFunction

Function SyncSlotTrackerFromArrays()
    {Push current Papyrus slot state to C++ SlotTracker per-slot.
    Called after RecoverActiveTasks to re-sync on game load.}
    Int i = 0
    While i < MAX_SLOTS
        If SlotStates[i] != 0
            ReferenceAlias slotAlias = GetAgentAlias(i)
            If slotAlias
                Actor agent = slotAlias.GetActorReference()
                If agent
                    IntelEngine.UpdateSlotState(i, agent, SlotStates[i], SlotTaskTypes[i], SlotTargetNames[i])
                EndIf
            EndIf
        Else
            IntelEngine.ClearSlotState(i)
        EndIf
        i += 1
    EndWhile
    DebugMsg("C++ SlotTracker synced from Papyrus arrays")
EndFunction

Function RegisterSkyrimNetTag()
    {Register the intel_available tag with SkyrimNet for action eligibility filtering.
    Called on every game load to ensure the tag is available for action evaluation.}

    Int result = SkyrimNetApi.RegisterTag("intel_available", "IntelEngine_Core", "IntelAvailable_Eligibility")

    If result == 0
        DebugMsg("Registered SkyrimNet tag: intel_available")
    Else
        DebugMsg("WARNING: Failed to register SkyrimNet tag intel_available (error " + result + ")")
    EndIf
EndFunction

; NOTE: No OnUpdate here. IntelEngine_Travel and IntelEngine_NPCTasks each
; run their own update loops and handle their own slot monitoring. Core
; only provides shared slot/package infrastructure.

; =============================================================================
; PACKAGE HELPERS
; =============================================================================

Package Function GetTravelPackage(Int speed)
    If speed == 2 && TravelPackage_Run
        Return TravelPackage_Run
    ElseIf speed == 1 && TravelPackage_Jog
        Return TravelPackage_Jog
    ElseIf TravelPackage_Walk
        Return TravelPackage_Walk
    EndIf
    Return TravelPackage_Walk
EndFunction

Int Function ParseSpeed(String speedText)
    String lower = IntelEngine.StringToLower(speedText)

    If IntelEngine.StringContains(lower, "run") || \
       IntelEngine.StringContains(lower, "hurry") || \
       IntelEngine.StringContains(lower, "quick") || \
       IntelEngine.StringContains(lower, "fast") || \
       IntelEngine.StringContains(lower, "urgent")
        Return 2
    ElseIf IntelEngine.StringContains(lower, "jog") || \
           IntelEngine.StringContains(lower, "brisk")
        Return 1
    EndIf

    Return 0  ; Default walk
EndFunction

; =============================================================================
; NARRATION HELPERS
; =============================================================================

Function SendTaskNarration(Actor akActor, String msgText, Actor akTarget = None)
    ; Use SkyrimNet native DirectNarration instead of ModEvent
    ; This ensures proper integration with SkyrimNet's dialogue system
    SkyrimNetApi.DirectNarration(msgText, akActor, akTarget)
EndFunction

Function SendPersistentMemory(Actor akOriginator, Actor akTarget, String msgText)
    ; Adds a persistent event to SkyrimNet's context without triggering dialogue.
    ; Both actors will recall this in future conversations.
    ; Uses RegisterPersistentEvent (context-aware) instead of RegisterEvent (historical only).
    SkyrimNetApi.RegisterPersistentEvent(msgText, akOriginator, akTarget)
EndFunction

Function SendTransientEvent(Actor akOriginator, Actor akTarget, String msgText)
    ; Registers a historical event — NPC remembers for upcoming conversations
    ; but it does NOT persist in their prompt context permanently.
    ; Use for task outcomes, delivery confirmations, etc. that should fade over time.
    SkyrimNetApi.RegisterEvent("intel_task_event", msgText, akOriginator, akTarget)
EndFunction

Function NotifyPlayer(String msgText)
    Debug.Notification(msgText)
    Debug.Trace("IntelEngine: " + msgText)
EndFunction

; =============================================================================
; SKYRIMNET TAG ELIGIBILITY (for action filtering)
; =============================================================================

Bool Function IntelAvailable_Eligibility(Actor akActor, String contextJson, String paramsJson) Global
    {SkyrimNet tag eligibility function for intel_available tag.
    Returns true if actor can accept new tasks (no active task + no cooldown).
    Registered via SkyrimNetApi.RegisterTag() during init.

    Parameters:
    - akActor: The actor being checked for eligibility
    - contextJson: Context information from SkyrimNet (unused)
    - paramsJson: Parameters from SkyrimNet (unused)}
    Return IntelEngine.IsActorAvailable(akActor)
EndFunction

; =============================================================================
; DEBUG
; =============================================================================

Function DebugMsg(String msg)
    Debug.Trace("IntelEngine: " + msg)
    If IntelEngine_DebugMode && IntelEngine_DebugMode.GetValue() > 0
        Debug.Notification("Intel: " + msg)
    EndIf
EndFunction

; =============================================================================
; STATUS API (for MCM/debugging)
; =============================================================================

Int Function GetActiveTaskCount()
    Int count = 0
    Int i = 0
    While i < MAX_SLOTS
        If SlotStates[i] != 0
            count += 1
        EndIf
        i += 1
    EndWhile
    Return count
EndFunction

String Function GetSlotStatus(Int slot)
    If slot < 0 || slot >= MAX_SLOTS
        Return "Invalid"
    EndIf

    If SlotStates[slot] == 0
        Return "Empty"
    EndIf

    ReferenceAlias slotAlias = GetAgentAlias(slot)
    If slotAlias
        Actor agent = slotAlias.GetActorReference()
        If agent
            String agentName = agent.GetDisplayName()
            String taskType = SlotTaskTypes[slot]
            String target = SlotTargetNames[slot]
            Int taskState = SlotStates[slot]

            ; Build human-readable task description
            String desc = ""
            If taskType == "fetch_npc"
                If taskState == 1
                    desc = "fetching " + target
                ElseIf taskState == 8
                    desc = "talking to " + target
                ElseIf taskState == 3
                    desc = "returning with " + target
                Else
                    desc = "fetching " + target
                EndIf
            ElseIf taskType == "deliver_message"
                If taskState == 1
                    desc = "delivering message to " + target
                ElseIf taskState == 8
                    desc = "speaking with " + target
                Else
                    desc = "delivering message to " + target
                EndIf
            ElseIf taskType == "search_for_actor"
                If taskState == 1
                    desc = "searching for " + target
                ElseIf taskState == 5
                    desc = "waiting (searching for " + target + ")"
                Else
                    desc = "searching for " + target
                EndIf
            ElseIf taskType == "travel"
                If taskState == 1
                    desc = "traveling to " + target
                ElseIf taskState == 2
                    desc = "waiting at " + target
                Else
                    desc = "traveling to " + target
                EndIf
            Else
                desc = "on a task"
            EndIf

            ; Append location or combat flag
            If agent.IsInCombat()
                desc += " [IN COMBAT]"
            Else
                Cell agentCell = agent.GetParentCell()
                If agentCell
                    String cellName = agentCell.GetName()
                    If cellName != ""
                        desc += " @ " + cellName
                    EndIf
                EndIf
            EndIf

            Return agentName + ": " + desc
        EndIf
    EndIf

    Return "Unknown"
EndFunction

Bool Function TryWaypointNavigation(Int slot, Actor npc, ObjectReference dest)
    {Attempt waypoint redirect for on-screen stuck NPC.
    Finds nearest BGSLocation worldLocMarker toward dest and redirects
    the travel package. If NPC was already targeting this waypoint and
    is still stuck, teleports to it instead (known-good navmesh position).
    Returns true if handled (caller should return).}
    If !npc.Is3DLoaded()
        Return false
    EndIf

    ObjectReference waypoint = IntelEngine.FindNearestWaypointToward(npc, dest, 5000.0)
    If waypoint == None
        Return false
    EndIf

    ObjectReference currentWP = StorageUtil.GetFormValue(npc, \
        "Intel_CurrentWaypoint") as ObjectReference

    If currentWP == waypoint
        ; Already tried walking to this waypoint and still stuck —
        ; teleport to it (short hop to known-good navmesh position)
        DebugMsg(npc.GetDisplayName() + " stuck at waypoint — teleporting to it")
        npc.MoveTo(waypoint, 0.0, 0.0, 50.0)
        StorageUtil.UnsetFormValue(npc, "Intel_CurrentWaypoint")
        PO3_SKSEFunctions.SetLinkedRef(npc, dest, IntelEngine_TravelTarget)
        IntelEngine.ResetStuckSlot(slot, npc)
    Else
        ; New waypoint — redirect travel package (NPC walks there naturally)
        DebugMsg(npc.GetDisplayName() + " redirecting to nearby location marker")
        PO3_SKSEFunctions.SetLinkedRef(npc, waypoint, IntelEngine_TravelTarget)
        StorageUtil.SetFormValue(npc, "Intel_CurrentWaypoint", waypoint)
        IntelEngine.ResetStuckSlot(slot, npc)
    EndIf

    Int speed = SlotSpeeds[slot]
    Package travelPkg = GetTravelPackage(speed)
    If travelPkg
        ActorUtil.AddPackageOverride(npc, travelPkg, PRIORITY_TRAVEL, 1)
    EndIf
    npc.EvaluatePackage()
    NotifyPlayer(npc.GetDisplayName() + " finding alternate route")
    Return true
EndFunction

Bool Function CheckWaypointArrival(Int slot, Actor npc, ObjectReference dest)
    {Check if NPC reached their intermediate waypoint. If so, restore real
    destination and resume normal travel. Called at top of monitoring loops.
    Returns true if waypoint was reached (caller should skip normal checks).}
    ObjectReference currentWaypoint = StorageUtil.GetFormValue(npc, \
        "Intel_CurrentWaypoint") as ObjectReference
    If currentWaypoint == None
        Return false
    EndIf

    If npc.GetDistance(currentWaypoint) < ARRIVAL_DISTANCE
        DebugMsg(npc.GetDisplayName() + " reached waypoint, resuming to dest")
        PO3_SKSEFunctions.SetLinkedRef(npc, dest, IntelEngine_TravelTarget)
        StorageUtil.UnsetFormValue(npc, "Intel_CurrentWaypoint")
        IntelEngine.ResetStuckSlot(slot, npc)
        npc.EvaluatePackage()
        Return true
    EndIf

    Return false
EndFunction

Function ForceResetAllSlots()
    DebugMsg("Force resetting all slots")
    NotifyPlayer("IntelEngine: Resetting all tasks...")

    Int i = 0
    While i < MAX_SLOTS
        ClearSlot(i, true)
        i += 1
    EndWhile

    NotifyPlayer("IntelEngine: All tasks reset")
EndFunction
