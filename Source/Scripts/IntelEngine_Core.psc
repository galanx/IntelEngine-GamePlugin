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

IntelEngine_StoryEngine Property StoryEngine Auto
{Reference to story engine script for monitoring restart on game load}

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

Package Property TravelPackage_Stalk Auto
{Travel package - walk speed with Always Sneak flag, 800-unit arrive radius, for stalkers}

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

Float Property LINGER_RELEASE_DISTANCE = 800.0 Auto Hidden
{Distance (game units) the player must walk away before a lingering NPC loses interest.
Configurable via MCM. Shared between Travel, NPCTasks, and StoryEngine linger systems.}

Float Property MeetingGracePeriod = 0.5 Auto
{Grace period for meeting arrival tolerance (in game hours).
Default 0.5 hours (30 minutes). Configurable via MCM.
Handles timescale variations from Dynamic Time Scaling mods.}

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

Float LastMaintenanceRealTime = 0.0

Function Maintenance(Bool isFirstLoad = false)
    {
        Called by PlayerAlias on every game load AND by C++ bootstrap.
        Guard: skip if already ran within 2 real seconds (both paths fire on load).
        isFirstLoad = true when mod is first installed (OnInit on alias)
        isFirstLoad = false on subsequent loads (OnPlayerLoadGame on alias)
    }
    Float now = Utility.GetCurrentRealTime()
    If !isFirstLoad && (now - LastMaintenanceRealTime) < 2.0 && LastMaintenanceRealTime > 0.0
        DebugMsg("IntelEngine Maintenance skipped (duplicate call within 2s)")
        return
    EndIf
    LastMaintenanceRealTime = now
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
        StorageUtil.SetFloatValue(player, "Intel_MeetingTimeoutHours", 5.0)
    EndIf

    ; Initialize arrays if needed (split check — Papyrus doesn't short-circuit ||)
    If SlotStates == None
        InitializeSlotArrays()
    ElseIf SlotStates.Length != MAX_SLOTS
        InitializeSlotArrays()
    EndIf

    LoadDatabases()

    ; Only recover tasks on subsequent loads, not first install
    If !isFirstLoad
        RecoverActiveTasks()
    EndIf

    ; Self-heal script references if CK properties were lost (e.g. after
    ; console stopquest/startquest). All scripts live on the same quest,
    ; so casting via Quest base type recovers them.
    Quest q = self as Quest
    If !Travel
        Travel = q as IntelEngine_Travel
        If Travel
            DebugMsg("WARNING: Travel property was None, recovered via cast")
        EndIf
    EndIf
    If !NPCTasks
        NPCTasks = q as IntelEngine_NPCTasks
        If NPCTasks
            DebugMsg("WARNING: NPCTasks property was None, recovered via cast")
        EndIf
    EndIf
    If !Schedule
        Schedule = q as IntelEngine_Schedule
        If Schedule
            DebugMsg("WARNING: Schedule property was None, recovered via cast")
        EndIf
    EndIf
    If !StoryEngine
        StoryEngine = q as IntelEngine_StoryEngine
        If StoryEngine
            DebugMsg("WARNING: StoryEngine property was None, recovered via cast")
        EndIf
    EndIf
    If !Politics
        Politics = q as IntelEngine_Politics
        If Politics
            DebugMsg("WARNING: Politics property was None, recovered via cast")
        EndIf
    EndIf
    If !Battle
        Battle = q as IntelEngine_Battle
        If Battle
            DebugMsg("WARNING: Battle property was None, recovered via cast")
        Else
            DebugMsg("ERROR: Battle cast FAILED - IntelEngine_Battle script not found on quest")
        EndIf
    EndIf

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
    If StoryEngine
        StoryEngine.RestartMonitoring()
        StoryEngine.StartScheduler()
    EndIf
    If Politics
        Politics.Maintenance()
    EndIf
    If Battle
        Battle.OnGameReload()
    EndIf

    ; Clean expired facts on subsequent loads
    If !isFirstLoad
        CleanExpiredFactsGlobal()
    EndIf

    ; Register dashboard event listeners
    RegisterDashboardEvents()
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

    ; C++ builds the description string (stale-bytecode-safe, extensible)
    String desc = IntelEngine.BuildTaskHistoryDesc(taskType, target, result, msgContent, meetLocation)

    ; Append to history lists
    StorageUtil.StringListAdd(akAgent, "Intel_TaskHistory", desc)
    StorageUtil.FloatListAdd(akAgent, "Intel_TaskHistoryTime", Utility.GetCurrentGameTime())

    ; Cap at 10 entries (remove oldest)
    While StorageUtil.StringListCount(akAgent, "Intel_TaskHistory") > 10
        StorageUtil.StringListRemoveAt(akAgent, "Intel_TaskHistory", 0)
        StorageUtil.FloatListRemoveAt(akAgent, "Intel_TaskHistoryTime", 0)
    EndWhile

    ; Pre-render task history section for immediate template visibility
    Float currentTime = Utility.GetCurrentGameTime()
    String[] histArr = StorageUtil.StringListToArray(akAgent, "Intel_TaskHistory")
    Float[] histTimes = StorageUtil.FloatListToArray(akAgent, "Intel_TaskHistoryTime")
    String rendered = IntelEngine.RenderTaskHistorySection(histArr, histTimes, currentTime)
    StorageUtil.SetStringValue(akAgent, "Intel_TaskHistoryRendered", rendered)

    ; Track NPC in interacted list for Story Engine weighted selection
    Actor player = Game.GetPlayer()
    Int npcFormId = akAgent.GetFormID()
    If StorageUtil.IntListFind(player, "Intel_InteractedNPCs", npcFormId) < 0
        StorageUtil.IntListAdd(player, "Intel_InteractedNPCs", npcFormId)
    EndIf

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
    Int maxAllowed = GetMaxConcurrentTasks()
    If maxAllowed > MAX_SLOTS
        maxAllowed = MAX_SLOTS
    ElseIf maxAllowed < 1
        maxAllowed = 1
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
            StorageUtil.UnsetIntValue(agent, "Intel_WaitForPlayer")
            StorageUtil.UnsetFloatValue(agent, "Intel_Deadline")
            StorageUtil.UnsetIntValue(agent, "Intel_WasFollower")

            ; Clear fetch/deliver/escort task data
            StorageUtil.UnsetIntValue(agent, "Intel_InteractCyclesRemaining")
            StorageUtil.UnsetIntValue(agent, "Intel_ShouldFail")
            StorageUtil.UnsetStringValue(agent, "Intel_FailReason")
            StorageUtil.UnsetStringValue(agent, "Intel_Result")
            StorageUtil.UnsetStringValue(agent, "Intel_EscortDestName")
            StorageUtil.UnsetIntValue(agent, "Intel_EscortShouldWait")
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

            ; Clear current meeting flag (always — this task is done)
            StorageUtil.UnsetIntValue(agent, "Intel_IsScheduledMeeting")

            ; Only clear schedule arrays + keys if the NPC has no FUTURE schedule.
            ; A new schedule (e.g., "meet me tomorrow" during linger) must survive.
            Bool hasFutureSchedule = false
            If Schedule
                hasFutureSchedule = Schedule.HasFutureScheduleForAgent(agent)
                If !hasFutureSchedule
                    Schedule.ClearScheduleSlotByAgent(agent)
                EndIf
            EndIf
            If !hasFutureSchedule
                StorageUtil.UnsetIntValue(agent, "Intel_ScheduledState")
                StorageUtil.UnsetFloatValue(agent, "Intel_ScheduledDepartureHours")
            EndIf

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
            StorageUtil.UnsetIntValue(agent, "Intel_SelfMotivatedLogged")

            ; Clear travel linger flags
            StorageUtil.UnsetIntValue(agent, "Intel_TravelLingering")
            StorageUtil.UnsetIntValue(agent, "Intel_StayAtDest")

            ; Clear off-screen return tracking
            StorageUtil.UnsetIntValue(agent, "Intel_OffScreenCycles")
            StorageUtil.UnsetFloatValue(agent, "Intel_OffScreenLastDist")

            ; Clean up unlock tracking key (vanilla handles re-locking)
            StorageUtil.UnsetIntValue(agent, "Intel_UnlockedHomeCellId")

            ; Clear task cooldown
            StorageUtil.UnsetFloatValue(agent, "Intel_TaskCooldown")

            ; Clear story engine dispatch keys
            StorageUtil.UnsetIntValue(agent, "Intel_IsStoryDispatch")
            StorageUtil.UnsetStringValue(agent, "Intel_StoryNarration")

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
            StorageUtil.UnsetIntValue(target, "Intel_WasAccompanying")
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
    {Cancel the NPC's current task entirely. Called by CancelCurrentTask action.
    Blocked while the player is within LINGER_RELEASE_DISTANCE — the linger
    system handles task cleanup when the player walks away.}
    If akNPC == None
        Return false
    EndIf
    Int slot = FindSlotByAgent(akNPC)
    If slot < 0
        Return false
    EndIf

    ; Block cancellation while player is nearby — prevents premature LLM task clearing.
    ; The linger release mechanism will clean up when the player walks away.
    If !ShouldReleaseLinger(akNPC)
        DebugMsg(akNPC.GetDisplayName() + " cancel blocked: player nearby")
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
; SHARED LINGER PROXIMITY (DRY — called by Travel + StoryEngine)
;
; Single source of truth for linger release. Uses LINGER_RELEASE_DISTANCE.
; =============================================================================

Bool Function ShouldReleaseLinger(Actor npc)
    {Single source of truth: should a lingering NPC be released?
    Returns true when the player is far enough away (or NPC unloaded).}
    If !npc.Is3DLoaded()
        return true
    EndIf

    Actor player = Game.GetPlayer()
    If player.Is3DLoaded()
        Float dist = npc.GetDistance(player)
        If dist > 0.0
            return dist > LINGER_RELEASE_DISTANCE
        Else
            ; GetDistance returns 0 for cross-worldspace — fall back to cell check
            return npc.GetParentCell() != player.GetParentCell()
        EndIf
    EndIf
    ; Player not loaded — release unless same cell
    return npc.GetParentCell() != player.GetParentCell()
EndFunction

Function ReleaseLinger(Actor npc)
    {Remove sandbox override and send NPC back where they belong.
    NPCs with schedule AI (eat, sleep, patrol) are trusted to handle themselves.
    NPCs with only sandbox AI or no AI get a walk-home fallback so they don't
    stand frozen at the linger location forever.
    Shared by Travel, StoryEngine, and NPCTasks.}
    DebugMsg("Linger release START: " + npc.GetDisplayName() + " [formID=" + npc.GetFormID() + ", 3Dloaded=" + npc.Is3DLoaded() + ", isTeammate=" + npc.IsPlayerTeammate() + "]")
    ActorUtil.RemovePackageOverride(npc, SandboxNearPlayerPackage)
    DebugMsg("Linger release: removed sandbox from " + npc.GetDisplayName())
    ; NPCs with schedule-based AI (eat, sleep, patrol, travel) can handle
    ; returning to their routine on their own. NPCs with ONLY sandbox AI
    ; (common for modded followers) will just sandbox wherever they are,
    ; which looks broken if they're displaced. Walk those home instead.
    If npc.IsPlayerTeammate()
        PO3_SKSEFunctions.SetLinkedRef(npc, None, IntelEngine_TravelTarget)
        DebugMsg("Linger release: " + npc.GetDisplayName() + " is teammate -> cleared linked ref")
    ElseIf IntelEngine.HasNonSandboxAI(npc)
        PO3_SKSEFunctions.SetLinkedRef(npc, None, IntelEngine_TravelTarget)
        DebugMsg("Linger release: " + npc.GetDisplayName() + " has schedule AI -> relying on base packages")
    Else
        ; Sandbox-only or no AI: send them back where they belong.
        ; If player can't see them, teleport instantly. Otherwise walk naturally.
        ObjectReference destRef = IntelEngine.ResolveAnyDestination(npc, "home")
        If destRef == None
            destRef = IntelEngine.GetEditorLocationRef(npc)
        EndIf
        If destRef != None
            If !npc.Is3DLoaded()
                ; Player can't see: teleport silently, no override needed
                npc.MoveTo(destRef)
                PO3_SKSEFunctions.SetLinkedRef(npc, None, IntelEngine_TravelTarget)
                DebugMsg("Linger release: " + npc.GetDisplayName() + " sandbox-only AI, not loaded -> teleported home")
            Else
                ; Player can see: walk naturally
                PO3_SKSEFunctions.SetLinkedRef(npc, destRef, IntelEngine_TravelTarget)
                ActorUtil.AddPackageOverride(npc, TravelPackage_Walk, PRIORITY_TRAVEL, 1)
                DebugMsg("Linger release: " + npc.GetDisplayName() + " sandbox-only AI, 3D loaded -> walking home")
            EndIf
        Else
            PO3_SKSEFunctions.SetLinkedRef(npc, None, IntelEngine_TravelTarget)
            DebugMsg("Linger release: " + npc.GetDisplayName() + " sandbox-only AI, no home/editor location -> sandbox in place")
        EndIf
    EndIf
    npc.EvaluatePackage()
    DebugMsg("Linger release DONE: " + npc.GetDisplayName() + " EvaluatePackage called")
    StorageUtil.UnsetIntValue(npc, "Intel_LingerFarTicks")
    ; Clean up unlock tracking key (vanilla handles re-locking)
    StorageUtil.UnsetIntValue(npc, "Intel_UnlockedHomeCellId")
EndFunction

; =============================================================================
; SHARED TASK HELPERS (DRY — called by Travel, NPCTasks, Schedule)
; =============================================================================

String Function GetNPCTaskType(Actor npc)
    {Returns the current task type for an NPC, or "" if not on a task.}
    If !npc || !npc.IsInFaction(IntelEngine_TaskFaction)
        Return ""
    EndIf
    Return StorageUtil.GetStringValue(npc, "Intel_TaskType")
EndFunction

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
    {Legacy wrapper — calls per-action version with empty action (uses old global toggle).}
    return ShowTaskConfirmationForAction(npc, promptText, "")
EndFunction

Int Function ShowTaskConfirmationForAction(Actor npc, String promptText, String actionName)
    {Per-action confirmation prompt. Returns: 0=allow, 1=deny (narrate), 2=deny silent.
    Mode per action: 0=disabled, 1=followers only, 2=everyone.}
    Int mode = 0
    If actionName != "" && StoryEngine != None
        If actionName == "GoToLocation"
            mode = StoryEngine.ConfirmGoToLocation
        ElseIf actionName == "DeliverMessage"
            mode = StoryEngine.ConfirmDeliverMessage
        ElseIf actionName == "FetchPerson"
            mode = StoryEngine.ConfirmFetchPerson
        ElseIf actionName == "EscortTarget"
            mode = StoryEngine.ConfirmEscortTarget
        ElseIf actionName == "SearchForActor"
            mode = StoryEngine.ConfirmSearchForActor
        ElseIf actionName == "ScheduleFetch"
            mode = StoryEngine.ConfirmScheduleFetch
        ElseIf actionName == "ScheduleDelivery"
            mode = StoryEngine.ConfirmScheduleDelivery
        ElseIf actionName == "ScheduleMeeting"
            mode = StoryEngine.ConfirmScheduleMeeting
        EndIf
    Else
        ; Legacy fallback: old global toggle
        mode = StorageUtil.GetIntValue(Game.GetPlayer(), "Intel_TaskConfirmPrompt")
        If mode == 1
            mode = 2  ; old toggle was binary (on=everyone), map to mode 2
        EndIf
    EndIf

    If mode == 0
        Return 0  ; disabled
    EndIf

    If mode == 1
        ; Followers only — skip if NPC is not the player's active follower
        If !npc.IsPlayerTeammate()
            Return 0
        EndIf
    EndIf

    ; mode 1 (follower matched) or mode 2 (everyone) — show prompt
    String result = SkyMessage.Show(promptText, "Allow", "Deny", "Deny (Silent)")
    If result == "Deny"
        Return 1
    ElseIf result == "Allow"
        Return 0
    EndIf
    Return 2
EndFunction

String Function DetermineLatenessOutcome(Float actualGameTime, Float deadlineGameTime)
    ; C++ handles the comparison logic (stale-bytecode-safe)
    return IntelEngine.DetermineLatenessOutcome(deadlineGameTime, actualGameTime, MeetingGracePeriod)
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

Function EnsureBuildingAccess(Actor npc)
    {Single source of truth: if NPC is inside an interior cell, unlock the door
    and remove trespass so the player can enter. Called at all arrival points
    (Travel, StoryEngine, NPC Social). ClearSlot re-locks via Intel_UnlockedHomeCellId.}
    If npc == None
        return
    EndIf
    Cell npcCell = npc.GetParentCell()
    If npcCell == None || !npcCell.IsInterior()
        return
    EndIf
    Int cellId = npcCell.GetFormID()
    If cellId == 0
        return
    EndIf
    ; Already unlocked this cell for this NPC?
    Int existingCellId = StorageUtil.GetIntValue(npc, "Intel_UnlockedHomeCellId")
    If existingCellId == cellId
        return
    EndIf
    ; Previous cell left as-is — vanilla handles re-locking
    ; Unlock the NPC's current building (door + trespass removal)
    IntelEngine.SetHomeDoorAccessForCell(cellId, true)
    StorageUtil.SetIntValue(npc, "Intel_UnlockedHomeCellId", cellId)
    DebugMsg("Building access: unlocked cell " + cellId + " for " + npc.GetDisplayName())
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
    If TravelPackage_Stalk
        ActorUtil.RemovePackageOverride(akActor, TravelPackage_Stalk)
    EndIf
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

; =============================================================================
; NARRATION HELPERS
; =============================================================================

Function SendTaskNarration(Actor akActor, String msgText, Actor akTarget = None)
    ; Use SkyrimNet native DirectNarration instead of ModEvent
    ; This ensures proper integration with SkyrimNet's dialogue system
    SkyrimNetApi.DirectNarration(msgText, akActor, akTarget)
EndFunction

Function SendPersistentMemory(Actor akOriginator, Actor akTarget, String msgText)
    ; Registers a persistent event in SkyrimNet's event system.
    ; Writes to both in-memory cache (NPC dialogue prompts) and event DB
    ; (queryable by GetRecentEventsForActor, visible to Story DM).
    SkyrimNetApi.RegisterPersistentEvent(msgText, akOriginator, akTarget)
EndFunction

Function SendTransientEvent(Actor akOriginator, Actor akTarget, String msgText)
    ; Registers a historical event — NPC remembers for upcoming conversations
    ; but it does NOT persist in their prompt context permanently.
    ; Use for task outcomes, delivery confirmations, etc. that should fade over time.
    SkyrimNetApi.RegisterEvent("intel_task_event", msgText, akOriginator, akTarget)
EndFunction

; =============================================================================
; FACT INJECTION API
; Injects narrative facts into NPC bios via StorageUtil.
; Facts appear in the character bio submodule (0497_intel_facts.prompt)
; and expire after a configurable number of game days.
; =============================================================================

Function InjectFact(Actor akNPC, String factText)
    {Inject a narrative fact into an NPC's bio context. Pure FIFO: oldest
    facts are evicted when the cap is reached, no time-based expiry.
    factText: Past-tense verb phrase WITHOUT subject prefix,
    e.g., "got into a brawl with Uthgerd near the market"}
    If akNPC == None || factText == ""
        Return
    EndIf

    Float currentTime = Utility.GetCurrentGameTime()

    ; Cap at 10 facts per NPC — remove oldest if full (FIFO)
    Int count = StorageUtil.StringListCount(akNPC, "Intel_Facts")
    While count >= 10
        StorageUtil.StringListRemoveAt(akNPC, "Intel_Facts", 0)
        StorageUtil.FloatListRemoveAt(akNPC, "Intel_FactTimes", 0)
        count -= 1
    EndWhile

    StorageUtil.StringListAdd(akNPC, "Intel_Facts", factText)
    StorageUtil.FloatListAdd(akNPC, "Intel_FactTimes", currentTime)

    ; Pre-render facts section for immediate template visibility.
    ; papyrus_util("GetStringList") can't see newly created lists during current session,
    ; but papyrus_util("GetStringValue") can see SetStringValue immediately.
    String[] factsArr = StorageUtil.StringListToArray(akNPC, "Intel_Facts")
    Float[] timesArr = StorageUtil.FloatListToArray(akNPC, "Intel_FactTimes")
    String rendered = IntelEngine.RenderFactsSection(factsArr, timesArr, currentTime)
    StorageUtil.SetStringValue(akNPC, "Intel_FactsRendered", rendered)

    ; Track NPC in global fact registry for Maintenance sweep
    Actor player = Game.GetPlayer()
    Int formId = akNPC.GetFormID()
    If StorageUtil.IntListFind(player, "Intel_FactNPCs", formId) < 0
        StorageUtil.IntListAdd(player, "Intel_FactNPCs", formId)
    EndIf

    DebugMsg("Fact injected into " + akNPC.GetDisplayName() + ": " + factText)
EndFunction

; =============================================================================
; GOSSIP INJECTION API
; NPCs share rumors with each other. Both parties track what was shared.
; Gossip renders in its own bio section (0195_intel_gossip.prompt), separate from facts.
; =============================================================================

Function InjectGossip(Actor akGiver, Actor akReceiver, String gossipText)
    {Inject a gossip rumor between two NPCs.
    gossipText: Past-tense verb phrase, e.g., "heard that the Jarl is raising taxes"
    Both NPCs track who told/received the gossip (5-entry rolling cap).
    Renders in "Rumors I've Heard" bio section, separate from personal facts.}
    If akGiver == None || akReceiver == None || gossipText == ""
        Return
    EndIf

    Float currentTime = Utility.GetCurrentGameTime()
    String giverName = akGiver.GetDisplayName()
    String receiverName = akReceiver.GetDisplayName()

    ; --- Receiver side: what I've been told ---
    Int heardCount = StorageUtil.StringListCount(akReceiver, "Intel_GossipHeard")
    While heardCount >= 5
        StorageUtil.StringListRemoveAt(akReceiver, "Intel_GossipHeard", 0)
        StorageUtil.StringListRemoveAt(akReceiver, "Intel_GossipHeardFrom", 0)
        StorageUtil.FloatListRemoveAt(akReceiver, "Intel_GossipHeardTimes", 0)
        heardCount -= 1
    EndWhile
    StorageUtil.StringListAdd(akReceiver, "Intel_GossipHeard", gossipText)
    StorageUtil.StringListAdd(akReceiver, "Intel_GossipHeardFrom", giverName)
    StorageUtil.FloatListAdd(akReceiver, "Intel_GossipHeardTimes", currentTime)

    ; --- Giver side: what I've told others ---
    Int toldCount = StorageUtil.StringListCount(akGiver, "Intel_GossipTold")
    While toldCount >= 5
        StorageUtil.StringListRemoveAt(akGiver, "Intel_GossipTold", 0)
        StorageUtil.StringListRemoveAt(akGiver, "Intel_GossipToldTo", 0)
        StorageUtil.FloatListRemoveAt(akGiver, "Intel_GossipToldTimes", 0)
        toldCount -= 1
    EndWhile
    StorageUtil.StringListAdd(akGiver, "Intel_GossipTold", gossipText)
    StorageUtil.StringListAdd(akGiver, "Intel_GossipToldTo", receiverName)
    StorageUtil.FloatListAdd(akGiver, "Intel_GossipToldTimes", currentTime)

    ; Pre-render gossip sections for immediate template visibility.
    ; Receiver's heard section changed:
    String[] heardTexts = StorageUtil.StringListToArray(akReceiver, "Intel_GossipHeard")
    String[] heardFrom = StorageUtil.StringListToArray(akReceiver, "Intel_GossipHeardFrom")
    Float[] heardTimes = StorageUtil.FloatListToArray(akReceiver, "Intel_GossipHeardTimes")
    String heardRendered = IntelEngine.RenderGossipHeardSection(heardTexts, heardFrom, heardTimes, currentTime)
    ; Also get receiver's existing told section:
    String[] recvToldTexts = StorageUtil.StringListToArray(akReceiver, "Intel_GossipTold")
    String[] recvToldTo = StorageUtil.StringListToArray(akReceiver, "Intel_GossipToldTo")
    Float[] recvToldTimes = StorageUtil.FloatListToArray(akReceiver, "Intel_GossipToldTimes")
    String recvToldRendered = IntelEngine.RenderGossipToldSection(recvToldTexts, recvToldTo, recvToldTimes, currentTime)
    StorageUtil.SetStringValue(akReceiver, "Intel_GossipRendered", heardRendered + recvToldRendered)

    ; Giver's told section changed:
    String[] giverToldTexts = StorageUtil.StringListToArray(akGiver, "Intel_GossipTold")
    String[] giverToldTo = StorageUtil.StringListToArray(akGiver, "Intel_GossipToldTo")
    Float[] giverToldTimes = StorageUtil.FloatListToArray(akGiver, "Intel_GossipToldTimes")
    String giverToldRendered = IntelEngine.RenderGossipToldSection(giverToldTexts, giverToldTo, giverToldTimes, currentTime)
    ; Also get giver's existing heard section:
    String[] giverHeardTexts = StorageUtil.StringListToArray(akGiver, "Intel_GossipHeard")
    String[] giverHeardFrom = StorageUtil.StringListToArray(akGiver, "Intel_GossipHeardFrom")
    Float[] giverHeardTimes = StorageUtil.FloatListToArray(akGiver, "Intel_GossipHeardTimes")
    String giverHeardRendered = IntelEngine.RenderGossipHeardSection(giverHeardTexts, giverHeardFrom, giverHeardTimes, currentTime)
    StorageUtil.SetStringValue(akGiver, "Intel_GossipRendered", giverHeardRendered + giverToldRendered)

    DebugMsg("Gossip: " + giverName + " told " + receiverName + ": " + gossipText)
EndFunction

Function CleanExpiredFacts(Actor akNPC)
    {Legacy cleanup: remove Intel_FactExpiry lists from old saves.
    Fact system is now pure FIFO with no time-based expiry.}
    If akNPC == None
        Return
    EndIf
    ; Remove legacy expiry list if present (one-time migration)
    StorageUtil.FloatListClear(akNPC, "Intel_FactExpiry")

    ; If no facts remain, remove from global registry
    If StorageUtil.StringListCount(akNPC, "Intel_Facts") == 0
        Actor player = Game.GetPlayer()
        Int formId = akNPC.GetFormID()
        Int idx = StorageUtil.IntListFind(player, "Intel_FactNPCs", formId)
        If idx >= 0
            StorageUtil.IntListRemoveAt(player, "Intel_FactNPCs", idx)
        EndIf
    EndIf
EndFunction

Function CleanExpiredFactsGlobal()
    {Sweep all NPCs with facts and remove expired entries.
    Called from Maintenance() on every game load.}
    Actor player = Game.GetPlayer()
    Int count = StorageUtil.IntListCount(player, "Intel_FactNPCs")
    Int i = count - 1
    While i >= 0
        Int formId = StorageUtil.IntListGet(player, "Intel_FactNPCs", i)
        Actor npc = Game.GetForm(formId) as Actor
        If npc != None
            CleanExpiredFacts(npc)
        Else
            ; NPC no longer valid — remove from registry
            StorageUtil.IntListRemoveAt(player, "Intel_FactNPCs", i)
        EndIf
        i -= 1
    EndWhile
EndFunction

Function NotifyPlayer(String msgText)
    Debug.Notification(msgText)
    Debug.Trace("IntelEngine: " + msgText)
EndFunction


; =============================================================================
; MCM SETTINGS (StorageUtil-backed, survives ESP redeployment)
; =============================================================================

; StorageUtil keys for MCM settings (on player actor)
; Fallback to GlobalVariable ESP defaults on first access.

Bool Function GetSettingBool(String settingKey, Bool defaultVal)
    Actor player = Game.GetPlayer()
    If StorageUtil.HasIntValue(player, settingKey)
        return StorageUtil.GetIntValue(player, settingKey) > 0
    EndIf
    return defaultVal
EndFunction

Function SetSettingBool(String settingKey, Bool val)
    Actor player = Game.GetPlayer()
    If val
        StorageUtil.SetIntValue(player, settingKey, 1)
    Else
        StorageUtil.SetIntValue(player, settingKey, 0)
    EndIf
EndFunction

Float Function GetSettingFloat(String settingKey, Float defaultVal)
    Actor player = Game.GetPlayer()
    If StorageUtil.HasFloatValue(player, settingKey)
        return StorageUtil.GetFloatValue(player, settingKey)
    EndIf
    return defaultVal
EndFunction

Function SetSettingFloat(String settingKey, Float val)
    StorageUtil.SetFloatValue(Game.GetPlayer(), settingKey, val)
EndFunction

; Convenience accessors for commonly used settings
Bool Function IsDebugMode()
    return GetSettingBool("Intel_MCM_DebugMode", false)
EndFunction

Int Function GetMaxConcurrentTasks()
    return GetSettingFloat("Intel_MCM_MaxTasks", 5.0) as Int
EndFunction

Float Function GetDefaultWaitHours()
    return GetSettingFloat("Intel_MCM_DefaultWaitHours", 48.0)
EndFunction

Bool Function IsStoryEngineEnabled()
    return GetSettingBool("Intel_MCM_StoryEnabled", true)
EndFunction

Float Function GetStoryEngineInterval()
    return GetSettingFloat("Intel_MCM_StoryInterval", 3.0)
EndFunction

Float Function GetStoryEngineCooldown()
    return GetSettingFloat("Intel_MCM_StoryCooldown", 24.0)
EndFunction

; Unified setters — single source of truth for both MCM and Dashboard.
; Each setter writes to ALL storage locations (StorageUtil + GlobalVariable/property).

Function SetStoryEnabled(Bool val)
    SetSettingBool("Intel_MCM_StoryEnabled", val)
    If StoryEngine
        If val
            StoryEngine.IntelEngine_StoryEngineEnabled.SetValue(1.0)
            StoryEngine.StartScheduler()
        Else
            StoryEngine.IntelEngine_StoryEngineEnabled.SetValue(0.0)
            StoryEngine.StopScheduler()
        EndIf
    EndIf
EndFunction

Function SetStoryInterval(Float val)
    SetSettingFloat("Intel_MCM_StoryInterval", val)
    If StoryEngine
        StoryEngine.IntelEngine_StoryEngineInterval.SetValue(val)
        StoryEngine.StartScheduler()
    EndIf
EndFunction

Function SetStoryCooldown(Float val)
    SetSettingFloat("Intel_MCM_StoryCooldown", val)
    If StoryEngine
        StoryEngine.IntelEngine_StoryEngineCooldown.SetValue(val)
    EndIf
EndFunction

Function SetMaxTasks(Int val)
    SetSettingFloat("Intel_MCM_MaxTasks", val as Float)
    IntelEngine_MaxConcurrentTasks.SetValue(val as Float)
EndFunction

Function SetReleaseDistance(Float val)
    ; Minimum 400 — sandbox radius is 200 units, so anything less causes
    ; false releases when the NPC walks to a sandbox idle point.
    If val < 400.0
        val = 400.0
    EndIf
    LINGER_RELEASE_DISTANCE = val
EndFunction

Function SetDangerZonePolicy(Int val)
    If StoryEngine
        StoryEngine.DangerZonePolicy = val
    EndIf
    IntelEngine.SetDangerZonePolicy(val)
EndFunction

Function SetPlayerHomePolicy(Int val)
    If StoryEngine
        StoryEngine.PlayerHomePolicy = val
    EndIf
    IntelEngine.SetPlayerHomePolicy(val)
EndFunction

Function SetHoldRestrictionPolicy(String storyType, Int val)
    If StoryEngine
        If storyType == "seek_player"
            StoryEngine.HoldPolicySeekPlayer = val
        ElseIf storyType == "informant"
            StoryEngine.HoldPolicyInformant = val
        ElseIf storyType == "road_encounter"
            StoryEngine.HoldPolicyRoadEncounter = val
        ElseIf storyType == "ambush"
            StoryEngine.HoldPolicyAmbush = val
        ElseIf storyType == "stalker"
            StoryEngine.HoldPolicyStalker = val
        ElseIf storyType == "message"
            StoryEngine.HoldPolicyMessage = val
        ElseIf storyType == "quest"
            StoryEngine.HoldPolicyQuest = val
        EndIf
    EndIf
    IntelEngine.SetHoldRestrictionPolicy(storyType, val)
EndFunction

; =============================================================================
; DEBUG
; =============================================================================

Function DebugMsg(String msg)
    Debug.Trace("IntelEngine: " + msg)
    If IsDebugMode()
        Debug.Notification("Intel: " + msg)
    EndIf
EndFunction

; =============================================================================
; STATUS API (for MCM/debugging)
; =============================================================================

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

            ; C++ builds the description (stale-bytecode-safe)
            String cellName = ""
            If agent.IsInCombat()
                cellName = "[IN COMBAT]"
            Else
                Cell agentCell = agent.GetParentCell()
                If agentCell
                    cellName = agentCell.GetName()
                EndIf
            EndIf
            String desc = IntelEngine.GetSlotStatusNative(taskType, taskState, target, cellName)
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

; =============================================================================
; DASHBOARD STATE & EVENTS
; =============================================================================

Function RegisterDashboardEvents()
    RegisterForModEvent("IntelEngine_DashboardOpened", "OnDashboardOpened")
    RegisterForModEvent("IntelEngine_DashboardRefresh", "OnDashboardRefresh")
    RegisterForModEvent("IntelEngine_DashboardCancelTask", "OnDashboardCancelTask")
    RegisterForModEvent("IntelEngine_DashboardCancelSchedule", "OnDashboardCancelSchedule")
    RegisterForModEvent("IntelEngine_DashboardToggleStory", "OnDashboardToggleStory")
    RegisterForModEvent("IntelEngine_DashboardSetting", "OnDashboardSetting")
    RegisterForModEvent("IntelEngine_DashboardRemovePackages", "OnDashboardRemovePackages")
    RegisterForModEvent("IntelEngine_DashboardDispatchStory", "OnDashboardDispatchStory")
    RegisterForModEvent("IntelEngine_DashboardDispatchNpcSocial", "OnDashboardDispatchNpcSocial")
    RegisterForModEvent("IntelEngine_DashboardExecuteAction", "OnDashboardExecuteAction")
    DebugMsg("Dashboard ModEvent listeners registered")
EndFunction

Event OnDashboardOpened(String eventName, String strArg, Float numArg, Form sender)
    PushDashboardState()
EndEvent

Event OnDashboardRefresh(String eventName, String strArg, Float numArg, Form sender)
    PushDashboardState()
EndEvent

Event OnDashboardCancelTask(String eventName, String strArg, Float numArg, Form sender)
    Int slot = numArg as Int
    If slot >= 0 && slot < MAX_SLOTS
        Actor agent = GetAgentAlias(slot).GetActorReference()
        If agent != None
            DebugMsg("Dashboard: Cancelling task in slot " + slot + " for " + agent.GetDisplayName())
            StorageUtil.SetStringValue(agent, "Intel_Result", "cancelled")
            ClearSlotRestoreFollower(slot, agent)
            PushDashboardState()
        EndIf
    EndIf
EndEvent

Event OnDashboardRemovePackages(String eventName, String strArg, Float numArg, Form sender)
    Int formId = numArg as Int
    Actor npc = Game.GetForm(formId) as Actor
    If npc != None
        DebugMsg("Dashboard: Removing packages from " + npc.GetDisplayName())
        ; Clear slot if NPC is in one (prevents orphaned "Travelling" entries)
        Int slot = FindSlotByAgent(npc)
        If slot >= 0
            ClearSlot(slot)
        Else
            RemoveIntelPackages(npc)
        EndIf
        ; Clean up story/social dispatch if this NPC was the active dispatch target
        If StoryEngine.ActiveStoryNPC == npc
            StoryEngine.CleanupStoryDispatch()
        EndIf
        If StoryEngine.NPCSocialTraveler == npc
            StoryEngine.CleanupNPCSocialDispatch()
        EndIf
        ; Also clear linked ref in case it's driving a sandbox location
        PO3_SKSEFunctions.SetLinkedRef(npc, None, IntelEngine_TravelTarget)
        ; Wait for engine to process the package removal before re-scanning
        Utility.Wait(0.5)
        PushDashboardState()
    EndIf
EndEvent

Event OnDashboardCancelSchedule(String eventName, String strArg, Float numArg, Form sender)
    Int slot = numArg as Int
    If Schedule
        Schedule.ClearScheduleSlot(slot)
        DebugMsg("Dashboard: Cancelled scheduled task in slot " + slot)
        PushDashboardState()
    EndIf
EndEvent

Event OnDashboardToggleStory(String eventName, String strArg, Float numArg, Form sender)
    If !StoryEngine
        Return
    EndIf
    Bool enabled = numArg > 0.5
    DebugMsg("Dashboard: Toggle story type " + strArg + " = " + enabled)
    If strArg == "seek_player"
        StoryEngine.TypeSeekPlayerEnabled = enabled
    ElseIf strArg == "informant"
        StoryEngine.TypeInformantEnabled = enabled
    ElseIf strArg == "road_encounter"
        StoryEngine.TypeRoadEncounterEnabled = enabled
    ElseIf strArg == "ambush"
        StoryEngine.TypeAmbushEnabled = enabled
    ElseIf strArg == "faction_ambush"
        StoryEngine.TypeFactionAmbushEnabled = enabled
    ElseIf strArg == "stalker"
        StoryEngine.TypeStalkerEnabled = enabled
    ElseIf strArg == "message"
        StoryEngine.TypeMessageEnabled = enabled
    ElseIf strArg == "quest"
        StoryEngine.TypeQuestEnabled = enabled
    ElseIf strArg == "npc_interaction"
        StoryEngine.TypeNPCInteractionEnabled = enabled
    ElseIf strArg == "npc_gossip"
        StoryEngine.TypeNPCGossipEnabled = enabled
    EndIf
    PushDashboardState()
EndEvent

Event OnDashboardSetting(String eventName, String strArg, Float numArg, Form sender)
    DebugMsg("Dashboard: Setting " + strArg + " = " + numArg)

    ; Use centralized setters (same ones MCM calls) for single source of truth
    If strArg == "debugMode"
        SetSettingBool("Intel_MCM_DebugMode", numArg > 0.5)
    ElseIf strArg == "storyEnabled"
        SetStoryEnabled(numArg > 0.5)
    ElseIf strArg == "storyInterval"
        SetStoryInterval(numArg)
    ElseIf strArg == "storyCooldown"
        SetStoryCooldown(numArg)
    ElseIf strArg == "maxTasks"
        SetMaxTasks(numArg as Int)
    ElseIf strArg == "releaseDistance"
        SetReleaseDistance(numArg)
    ElseIf strArg == "longAbsenceDays"
        If StoryEngine
            StoryEngine.LongAbsenceDaysConfig = numArg
        EndIf
    ElseIf strArg == "maxTravelDays"
        If StoryEngine
            StoryEngine.MaxTravelDaysConfig = numArg
        EndIf
    ElseIf strArg == "allowStuckTeleport"
        If StoryEngine
            StoryEngine.AllowStuckTeleport = numArg > 0.5
        EndIf
    ElseIf strArg == "dangerZonePolicy"
        SetDangerZonePolicy(numArg as Int)
    ElseIf strArg == "playerHomePolicy"
        SetPlayerHomePolicy(numArg as Int)
    ElseIf strArg == "holdPolicySeekPlayer"
        SetHoldRestrictionPolicy("seek_player", numArg as Int)
    ElseIf strArg == "holdPolicyInformant"
        SetHoldRestrictionPolicy("informant", numArg as Int)
    ElseIf strArg == "holdPolicyRoadEncounter"
        SetHoldRestrictionPolicy("road_encounter", numArg as Int)
    ElseIf strArg == "holdPolicyAmbush"
        SetHoldRestrictionPolicy("ambush", numArg as Int)
    ElseIf strArg == "holdPolicyStalker"
        SetHoldRestrictionPolicy("stalker", numArg as Int)
    ElseIf strArg == "holdPolicyMessage"
        SetHoldRestrictionPolicy("message", numArg as Int)
    ElseIf strArg == "holdPolicyQuest"
        SetHoldRestrictionPolicy("quest", numArg as Int)
    ElseIf strArg == "npc_interaction"
        If StoryEngine
            StoryEngine.TypeNPCInteractionEnabled = numArg > 0.5
        EndIf
    ElseIf strArg == "npc_gossip"
        If StoryEngine
            StoryEngine.TypeNPCGossipEnabled = numArg > 0.5
        EndIf
    ElseIf strArg == "npcTickEnabled"
        If StoryEngine
            StoryEngine.NPCTickEnabled = numArg > 0.5
        EndIf
    ElseIf strArg == "npcTickInterval"
        If StoryEngine
            StoryEngine.NPCTickIntervalHours = numArg
        EndIf
    ElseIf strArg == "npcSocialCooldown"
        If StoryEngine
            StoryEngine.NPCSocialCooldownHours = numArg
        EndIf
    ElseIf strArg == "reportBack"
        StorageUtil.SetIntValue(Game.GetPlayer(), "Intel_DeliveryReportBack", numArg as Int)
    ElseIf strArg == "questCombat"
        If StoryEngine
            StoryEngine.QuestSubTypeCombatEnabled = numArg > 0.5
        EndIf
    ElseIf strArg == "questRescue"
        If StoryEngine
            StoryEngine.QuestSubTypeRescueEnabled = numArg > 0.5
        EndIf
    ElseIf strArg == "questFindItem"
        If StoryEngine
            StoryEngine.QuestSubTypeFindItemEnabled = numArg > 0.5
        EndIf
    ElseIf strArg == "questFactionCombat"
        If StoryEngine
            StoryEngine.QuestSubTypeFactionCombatEnabled = numArg > 0.5
        EndIf
    ElseIf strArg == "questFactionRescue"
        If StoryEngine
            StoryEngine.QuestSubTypeFactionRescueEnabled = numArg > 0.5
        EndIf
    ElseIf strArg == "questFactionBattle"
        If StoryEngine
            StoryEngine.QuestSubTypeFactionBattleEnabled = numArg > 0.5
        EndIf
    ElseIf strArg == "taskConfirmPrompt"
        StorageUtil.SetIntValue(Game.GetPlayer(), "Intel_TaskConfirmPrompt", numArg as Int)
    ElseIf strArg == "confirmGoToLocation"
        If StoryEngine
            StoryEngine.ConfirmGoToLocation = numArg as Int
        EndIf
    ElseIf strArg == "confirmDeliverMessage"
        If StoryEngine
            StoryEngine.ConfirmDeliverMessage = numArg as Int
        EndIf
    ElseIf strArg == "confirmFetchPerson"
        If StoryEngine
            StoryEngine.ConfirmFetchPerson = numArg as Int
        EndIf
    ElseIf strArg == "confirmEscortTarget"
        If StoryEngine
            StoryEngine.ConfirmEscortTarget = numArg as Int
        EndIf
    ElseIf strArg == "confirmSearchForActor"
        If StoryEngine
            StoryEngine.ConfirmSearchForActor = numArg as Int
        EndIf
    ElseIf strArg == "confirmScheduleMeeting"
        If StoryEngine
            StoryEngine.ConfirmScheduleMeeting = numArg as Int
        EndIf
    ElseIf strArg == "confirmScheduleFetch"
        If StoryEngine
            StoryEngine.ConfirmScheduleFetch = numArg as Int
        EndIf
    ElseIf strArg == "confirmScheduleDelivery"
        If StoryEngine
            StoryEngine.ConfirmScheduleDelivery = numArg as Int
        EndIf
    ElseIf strArg == "defaultWaitHours"
        SetSettingFloat("Intel_MCM_DefaultWaitHours", numArg)
    ElseIf strArg == "meetingTimeoutHours"
        StorageUtil.SetFloatValue(Game.GetPlayer(), "Intel_MeetingTimeoutHours", numArg)
    ElseIf strArg == "meetingGracePeriod"
        MeetingGracePeriod = numArg
    ElseIf strArg == "questTimeoutDays"
        If StoryEngine
            StoryEngine.QUEST_EXPIRY_DAYS = numArg
        EndIf
    ElseIf strArg == "questAllowVictimDeath"
        If StoryEngine
            StoryEngine.QuestAllowVictimDeath = numArg > 0.5
        EndIf
    EndIf
    ; No PushDashboardState() — React updates optimistically
EndEvent

; =============================================================================
; DIRECTOR MODE: Story Dispatch
; =============================================================================
Event OnDashboardDispatchStory(String eventName, String strArg, Float numArg, Form sender)
    ; strArg = storyType
    ; All fields stored in C++ pending params (type-specific fields included)
    String storyType = strArg
    String npcName = IntelEngine.GetPendingDirectorParam("npcName")
    String narration = IntelEngine.GetPendingDirectorParam("narration")

    ; Response JSON built in C++ with proper escaping (nlohmann::json)
    ; All type-specific fields extracted from response via ExtractJsonField (single source of truth)
    String response = IntelEngine.GetPendingDirectorParam("response")
    IntelEngine.ClearPendingDirectorParams()

    Actor npc = IntelEngine.ResolveStoryCandidate(npcName)
    If !npc || npc.IsDead()
        DebugMsg("Director: Could not find NPC '" + npcName + "' for story dispatch")
        Return
    EndIf
    If narration == ""
        DebugMsg("Director: Empty narration, aborting")
        Return
    EndIf
    If !StoryEngine
        DebugMsg("Director: StoryEngine not available")
        Return
    EndIf

    DebugMsg("Director: Dispatching " + storyType + " with " + npc.GetDisplayName() + " - " + narration)

    ; Record persistent memory (same as automatic dispatch — skipped for message type)
    If storyType != "message"
        SendPersistentMemory(npc, Game.GetPlayer(), npc.GetDisplayName() + " set out to find " + Game.GetPlayer().GetDisplayName())
    EndIf

    ; Route through StoryEngine's actual type handlers (identical to automatic dispatch)
    ; Director skips cooldown/MCM checks intentionally — it's a manual DM override
    If storyType == "seek_player"
        InjectFact(npc, "set out to find " + Game.GetPlayer().GetDisplayName() + " -- " + narration)
        StoryEngine.ActiveStoryType = storyType
        StoryEngine.DispatchToTarget(npc, Game.GetPlayer(), narration, "story")

    ElseIf storyType == "informant"
        String fSubject = StoryEngine.ExtractJsonField(response, "subject")
        String fGossip = StoryEngine.ExtractJsonField(response, "gossip")
        If fSubject != "" && fGossip != ""
            Actor subjectNPC = IntelEngine.FindNPCByName(fSubject)
            If subjectNPC
                InjectFact(subjectNPC, fGossip)
            EndIf
            String fSender = StoryEngine.ExtractJsonField(response, "sender")
            If fSender != ""
                InjectFact(npc, "heard from " + fSender + " that " + fSubject + " " + fGossip)
            Else
                InjectFact(npc, "witnessed that " + fSubject + " " + fGossip)
            EndIf
        EndIf
        StoryEngine.ActiveStoryType = "informant"
        StoryEngine.DispatchToTarget(npc, Game.GetPlayer(), narration, "story")

    ElseIf storyType == "ambush" || storyType == "stalker"
        StoryEngine.HandleAmbushStalkerDispatch(npc, narration, response, storyType)

    ElseIf storyType == "quest"
        StoryEngine.HandleQuestDispatch(npc, narration, response)

    ElseIf storyType == "message"
        StoryEngine.HandleMessageDispatch(npc, narration, response)

    ElseIf storyType == "road_encounter"
        InjectFact(npc, narration)
        StoryEngine.PlaceRoadEncounter(npc, narration, StoryEngine.ExtractJsonField(response, "destination"))

    Else
        DebugMsg("Director: unknown story type '" + storyType + "'")
    EndIf

    PushDashboardState()
EndEvent


; =============================================================================
; DIRECTOR MODE: NPC Social Dispatch
; =============================================================================
Event OnDashboardDispatchNpcSocial(String eventName, String strArg, Float numArg, Form sender)
    ; strArg = socialType (npc_interaction or npc_gossip)
    String socialType = strArg
    String npc1Name = IntelEngine.GetPendingDirectorParam("npc1Name")
    String npc2Name = IntelEngine.GetPendingDirectorParam("npc2Name")
    String narration = IntelEngine.GetPendingDirectorParam("narration")
    String response = IntelEngine.GetPendingDirectorParam("response")
    IntelEngine.ClearPendingDirectorParams()

    Actor npc1 = IntelEngine.FindNPCByName(npc1Name)
    Actor npc2 = IntelEngine.FindNPCByName(npc2Name)
    If !npc1 || npc1.IsDead()
        DebugMsg("Director: Could not find NPC 1 '" + npc1Name + "' for social dispatch")
        Return
    EndIf
    If !npc2 || npc2.IsDead()
        DebugMsg("Director: Could not find NPC 2 '" + npc2Name + "' for social dispatch")
        Return
    EndIf

    DebugMsg("Director: NPC Social " + socialType + " — " + npc1Name + " -> " + npc2Name + ": " + narration)

    If socialType == "npc_interaction"
        String fact1 = StoryEngine.ExtractJsonField(response, "fact1")
        String fact2 = StoryEngine.ExtractJsonField(response, "fact2")
        If fact1 != ""
            InjectFact(npc1, fact1)
        EndIf
        If fact2 != ""
            InjectFact(npc2, fact2)
        EndIf
        StoryEngine.AddNPCSocialLog("npc_interaction", npc1Name, npc2Name, narration, npc1)
        StoryEngine.AddRecentStoryEvent("npc_interaction: " + npc1Name + " and " + npc2Name + " — " + narration)

    ElseIf socialType == "npc_gossip"
        String gossip = StoryEngine.ExtractJsonField(response, "gossip")
        If gossip != ""
            InjectFact(npc1, "told " + npc2Name + " that someone " + gossip)
            InjectFact(npc2, "heard from " + npc1Name + " that someone " + gossip)
        EndIf
        StoryEngine.AddNPCSocialLog("npc_gossip", npc1Name, npc2Name, narration, npc1)
        StoryEngine.AddRecentStoryEvent("npc_gossip: " + npc1Name + " told " + npc2Name + " — " + narration)
    EndIf

    ; If NPCs are close enough, dispatch physical travel for face-to-face
    Float dist = npc1.GetDistance(npc2)
    If dist < 5000.0 && dist > 200.0
        StoryEngine.DispatchNPCSocial(npc1, npc2, narration, socialType)
    Else
        DebugMsg("Director: NPCs too far apart or already close — applied off-screen")
    EndIf

    PushDashboardState()
EndEvent

; =============================================================================
; DIRECTOR MODE: Action Execution
; =============================================================================
Event OnDashboardExecuteAction(String eventName, String strArg, Float numArg, Form sender)
    ; strArg = actionName, numArg = npcFormId
    ; Action params stored in C++ pending params
    String actionName = strArg
    Actor npc = Game.GetForm(numArg as Int) as Actor

    If !npc || npc.IsDead()
        IntelEngine.ClearPendingDirectorParams()
        DebugMsg("Director: Invalid or dead NPC for action execution")
        Return
    EndIf

    DebugMsg("Director: Executing " + actionName + " on " + npc.GetDisplayName())

    If actionName == "GoToLocation"
        String destination = IntelEngine.GetPendingDirectorParam("destination")
        Int speed = IntelEngine.GetPendingDirectorParam("speed") as Int
        Int waitFP = IntelEngine.GetPendingDirectorParam("waitForPlayer") as Int
        IntelEngine.ClearPendingDirectorParams()
        Travel.GoToLocation(npc, destination, speed, waitFP, false)

    ElseIf actionName == "FetchPerson"
        String targetName = IntelEngine.GetPendingDirectorParam("targetName")
        String failReason = IntelEngine.GetPendingDirectorParam("failReason")
        IntelEngine.ClearPendingDirectorParams()
        If failReason == ""
            failReason = "none"
        EndIf
        NPCTasks.FetchNPC(npc, targetName, failReason)

    ElseIf actionName == "SearchForActor"
        String targetName = IntelEngine.GetPendingDirectorParam("targetName")
        Int speed = IntelEngine.GetPendingDirectorParam("speed") as Int
        IntelEngine.ClearPendingDirectorParams()
        NPCTasks.SearchForActor(npc, targetName, speed)

    ElseIf actionName == "DeliverMessage"
        String targetName = IntelEngine.GetPendingDirectorParam("targetName")
        String msgContent = IntelEngine.GetPendingDirectorParam("msgContent")
        String meetLoc = IntelEngine.GetPendingDirectorParam("meetLocation")
        String meetTime = IntelEngine.GetPendingDirectorParam("meetTime")
        IntelEngine.ClearPendingDirectorParams()
        If meetLoc == ""
            meetLoc = "none"
        EndIf
        If meetTime == ""
            meetTime = "none"
        EndIf
        NPCTasks.DeliverMessage(npc, targetName, msgContent, meetLoc, meetTime)

    ElseIf actionName == "EscortTarget"
        String targetName = IntelEngine.GetPendingDirectorParam("targetName")
        String destination = IntelEngine.GetPendingDirectorParam("destination")
        Int shouldWait = IntelEngine.GetPendingDirectorParam("shouldWait") as Int
        IntelEngine.ClearPendingDirectorParams()
        If destination == ""
            destination = "home"
        EndIf
        NPCTasks.EscortTarget(npc, targetName, destination, shouldWait)

    ElseIf actionName == "CancelCurrentTask"
        IntelEngine.ClearPendingDirectorParams()
        CancelCurrentTask(npc)

    ElseIf actionName == "ChangeSpeed"
        Int newSpeed = IntelEngine.GetPendingDirectorParam("newSpeed") as Int
        IntelEngine.ClearPendingDirectorParams()
        ChangeTaskSpeed(npc, newSpeed)

    ElseIf actionName == "ScheduleMeeting"
        String destination = IntelEngine.GetPendingDirectorParam("destination")
        String timeCond = IntelEngine.GetPendingDirectorParam("timeCondition")
        IntelEngine.ClearPendingDirectorParams()
        Schedule.ScheduleMeeting(npc, destination, timeCond)

    ElseIf actionName == "ScheduleFetch"
        String targetName = IntelEngine.GetPendingDirectorParam("targetName")
        String timeCond = IntelEngine.GetPendingDirectorParam("timeCondition")
        IntelEngine.ClearPendingDirectorParams()
        Schedule.ScheduleFetch(npc, targetName, timeCond)

    ElseIf actionName == "ScheduleDelivery"
        String targetName = IntelEngine.GetPendingDirectorParam("targetName")
        String msgContent = IntelEngine.GetPendingDirectorParam("msgContent")
        String timeCond = IntelEngine.GetPendingDirectorParam("timeCondition")
        String meetLoc = IntelEngine.GetPendingDirectorParam("meetLocation")
        String meetTime = IntelEngine.GetPendingDirectorParam("meetTime")
        IntelEngine.ClearPendingDirectorParams()
        If meetLoc == ""
            meetLoc = "none"
        EndIf
        If meetTime == ""
            meetTime = "none"
        EndIf
        Schedule.ScheduleDelivery(npc, targetName, msgContent, timeCond, meetLoc, meetTime)

    Else
        IntelEngine.ClearPendingDirectorParams()
        DebugMsg("Director: Unknown action " + actionName)
    EndIf

    Utility.Wait(0.5)
    PushDashboardState()
EndEvent

Function PushDashboardState()
    If !IntelEngine.IsDashboardOpen()
        Return
    EndIf

    String json = BuildDashboardStateJson()
    IntelEngine.PushDashboardFullState(json)
EndFunction

String Function BuildDashboardStateJson()
    ; Build comprehensive state JSON for the dashboard UI.
    ; Uses string concatenation (no JContainers dependency).
    String json = "{"

    ; ── Active Tasks ──
    json += "\"tasks\":["
    Int i = 0
    While i < MAX_SLOTS
        If i > 0
            json += ","
        EndIf
        json += "{"
        json += "\"index\":" + i
        json += ",\"state\":" + SlotStates[i]
        json += ",\"taskType\":\"" + SlotTaskTypes[i] + "\""
        json += ",\"targetName\":\"" + EscapeJson(SlotTargetNames[i]) + "\""

        Actor agent = GetAgentAlias(i).GetActorReference()
        If agent != None && SlotStates[i] != 0
            json += ",\"agentName\":\"" + EscapeJson(agent.GetDisplayName()) + "\""
            json += ",\"agentFormId\":" + agent.GetFormID()
        Else
            json += ",\"agentName\":\"\",\"agentFormId\":0"
        EndIf
        json += ",\"cooldownRemaining\":0"
        json += ",\"speed\":" + SlotSpeeds[i]
        json += "}"
        i += 1
    EndWhile
    json += "]"

    ; ── Scheduled Tasks ──
    json += ",\"scheduled\":["
    If Schedule
        i = 0
        Bool first = true
        While i < Schedule.MAX_SCHEDULED
            String schedAgent = Schedule.GetScheduleAgentName(i)
            If schedAgent != ""
                If !first
                    json += ","
                EndIf
                first = false
                json += "{"
                json += "\"agent\":\"" + EscapeJson(schedAgent) + "\""
                json += ",\"destination\":\"" + EscapeJson(Schedule.GetScheduleDestination(i)) + "\""
                json += ",\"taskType\":\"" + Schedule.GetScheduleTaskType(i) + "\""
                json += ",\"targetName\":\"" + EscapeJson(Schedule.GetScheduleTargetName(i)) + "\""
                json += ",\"timeDesc\":\"" + EscapeJson(Schedule.GetScheduleDisplay(i)) + "\""
                json += ",\"schedStatus\":\"" + EscapeJson(Schedule.GetScheduleStatus(i)) + "\""
                json += ",\"schedState\":" + Schedule.GetScheduleSlotState(i)
                json += "}"
            EndIf
            i += 1
        EndWhile
    EndIf
    json += "]"

    ; ── Story Engine ──
    json += ",\"story\":{"
    If StoryEngine
        json += "\"enabled\":" + BoolToJson(IsStoryEngineEnabled())
        json += ",\"isActive\":" + BoolToJson(StoryEngine.IsActive)
        json += ",\"activeNPC\":\"" + EscapeJson(GetActorName(StoryEngine.ActiveStoryNPC)) + "\""
        json += ",\"activeType\":\"" + StoryEngine.ActiveStoryType + "\""
        json += ",\"activeNarration\":\"" + EscapeJson(StoryEngine.ActiveNarration) + "\""
        Float storyInterval = GetStoryEngineInterval()
        json += ",\"interval\":" + storyInterval
        json += ",\"cooldown\":" + GetStoryEngineCooldown()
        ; Next story check-in (hours until next DM tick)
        Float nextCheck = 0.0
        If StoryEngine.LastStoryTickTime > 0.0
            Float intervalDays = storyInterval / 24.0
            nextCheck = ((StoryEngine.LastStoryTickTime + intervalDays) - Utility.GetCurrentGameTime()) * 24.0
            If nextCheck < 0.0
                nextCheck = 0.0
            EndIf
        EndIf
        json += ",\"nextCheckIn\":" + nextCheck

        ; Story type toggles
        json += ",\"types\":{"
        json += "\"seek_player\":" + BoolToJson(StoryEngine.TypeSeekPlayerEnabled)
        json += ",\"informant\":" + BoolToJson(StoryEngine.TypeInformantEnabled)
        json += ",\"road_encounter\":" + BoolToJson(StoryEngine.TypeRoadEncounterEnabled)
        json += ",\"ambush\":" + BoolToJson(StoryEngine.TypeAmbushEnabled)
        json += ",\"faction_ambush\":" + BoolToJson(StoryEngine.TypeFactionAmbushEnabled)
        json += ",\"stalker\":" + BoolToJson(StoryEngine.TypeStalkerEnabled)
        json += ",\"message\":" + BoolToJson(StoryEngine.TypeMessageEnabled)
        json += ",\"quest\":" + BoolToJson(StoryEngine.TypeQuestEnabled)
        json += ",\"npc_interaction\":" + BoolToJson(StoryEngine.TypeNPCInteractionEnabled)
        json += ",\"npc_gossip\":" + BoolToJson(StoryEngine.TypeNPCGossipEnabled)
        json += "}"
    Else
        json += "\"enabled\":false,\"isActive\":false,\"activeNPC\":\"\",\"activeType\":\"\""
        json += ",\"interval\":3,\"cooldown\":24,\"types\":{}"
    EndIf
    json += "}"

    ; ── Quest ──
    json += ",\"quest\":{"
    If StoryEngine && StoryEngine.QuestActive
        json += "\"active\":true"
        json += ",\"giver\":\"" + EscapeJson(GetActorName(StoryEngine.QuestGiver)) + "\""
        json += ",\"location\":\"" + EscapeJson(StoryEngine.QuestLocationName) + "\""
        json += ",\"subType\":\"" + StoryEngine.QuestSubType + "\""
        json += ",\"enemyType\":\"" + StoryEngine.QuestEnemyType + "\""
        json += ",\"enemiesSpawned\":" + BoolToJson(StoryEngine.QuestEnemiesSpawned)
        json += ",\"victimName\":\"" + EscapeJson(StoryEngine.QuestVictimName) + "\""
        json += ",\"victimFreed\":" + BoolToJson(StoryEngine.QuestVictimFreed)
        json += ",\"itemName\":\"" + EscapeJson(StoryEngine.QuestItemName) + "\""
        json += ",\"guideActive\":" + BoolToJson(StoryEngine.QuestGuideActive)
    Else
        json += "\"active\":false"
    EndIf
    json += "}"

    ; ── NPC Social ──
    json += ",\"social\":{"
    If StoryEngine
        json += "\"enabled\":" + BoolToJson(StoryEngine.NPCTickEnabled)
        json += ",\"isActive\":" + BoolToJson(StoryEngine.IsNPCStoryActive)
        json += ",\"traveler\":\"" + EscapeJson(GetActorName(StoryEngine.NPCSocialTraveler)) + "\""
        json += ",\"target\":\"" + EscapeJson(GetActorName(StoryEngine.NPCSocialTarget)) + "\""
        json += ",\"type\":\"" + StoryEngine.NPCSocialType + "\""
        json += ",\"narration\":\"" + EscapeJson(StoryEngine.NPCSocialNarration) + "\""
    Else
        json += "\"enabled\":false,\"isActive\":false,\"traveler\":\"\",\"target\":\"\",\"type\":\"\""
    EndIf
    json += "}"

    ; ── NPC Social Log (last 5 interactions/gossip) ──
    Actor logPlayer = Game.GetPlayer()
    Int logCount = StorageUtil.StringListCount(logPlayer, "Intel_SocialLog_Type")
    json += ",\"npcSocialLog\":["
    ; Show newest first (reverse order)
    Int li = logCount - 1
    Bool logFirst = true
    While li >= 0
        If !logFirst
            json += ","
        EndIf
        logFirst = false
        json += "{"
        json += "\"type\":\"" + StorageUtil.StringListGet(logPlayer, "Intel_SocialLog_Type", li) + "\""
        json += ",\"npc1\":\"" + EscapeJson(StorageUtil.StringListGet(logPlayer, "Intel_SocialLog_NPC1", li)) + "\""
        json += ",\"npc2\":\"" + EscapeJson(StorageUtil.StringListGet(logPlayer, "Intel_SocialLog_NPC2", li)) + "\""
        json += ",\"text\":\"" + EscapeJson(StorageUtil.StringListGet(logPlayer, "Intel_SocialLog_Text", li)) + "\""
        json += "}"
        li -= 1
    EndWhile
    json += "]"

    ; ── Active Packages (scan loaded actors for IntelEngine package overrides) ──
    Int[] pkgFormIDs = new Int[6]
    pkgFormIDs[0] = TravelPackage_Walk.GetFormID()
    pkgFormIDs[1] = TravelPackage_Jog.GetFormID()
    pkgFormIDs[2] = TravelPackage_Run.GetFormID()
    If TravelPackage_Stalk
        pkgFormIDs[3] = TravelPackage_Stalk.GetFormID()
    EndIf
    If SandboxPackage
        pkgFormIDs[4] = SandboxPackage.GetFormID()
    EndIf
    If SandboxNearPlayerPackage
        pkgFormIDs[5] = SandboxNearPlayerPackage.GetFormID()
    EndIf
    json += ",\"packages\":" + IntelEngine.ScanActorsWithPackages(pkgFormIDs)

    ; ── Politics (from C++ PoliticalDB) ──
    If IntelEngine.IsPoliticsEnabled()
        json += ",\"politics\":" + IntelEngine.BuildPoliticalDashboardJson()
    EndIf

    ; ── Config ──
    ; Read from centralized getters — same source MCM uses (single source of truth)
    json += ",\"config\":{"
    json += "\"debugMode\":" + BoolToJson(IsDebugMode())
    json += ",\"storyEnabled\":" + BoolToJson(IsStoryEngineEnabled())
    json += ",\"storyInterval\":" + GetStoryEngineInterval()
    json += ",\"storyCooldown\":" + GetStoryEngineCooldown()
    json += ",\"maxTasks\":" + GetMaxConcurrentTasks()
    json += ",\"releaseDistance\":" + LINGER_RELEASE_DISTANCE
    json += ",\"reportBack\":" + BoolToJson(StorageUtil.GetIntValue(Game.GetPlayer(), "Intel_DeliveryReportBack") > 0)
    json += ",\"taskConfirmPrompt\":" + BoolToJson(StorageUtil.GetIntValue(Game.GetPlayer(), "Intel_TaskConfirmPrompt") > 0)
    json += ",\"defaultWaitHours\":" + GetDefaultWaitHours()
    json += ",\"meetingTimeoutHours\":" + StorageUtil.GetFloatValue(Game.GetPlayer(), "Intel_MeetingTimeoutHours", 5.0)
    json += ",\"meetingGracePeriod\":" + MeetingGracePeriod

    If StoryEngine
        json += ",\"longAbsenceDays\":" + StoryEngine.LongAbsenceDaysConfig
        json += ",\"maxTravelDays\":" + StoryEngine.MaxTravelDaysConfig
        json += ",\"allowStuckTeleport\":" + BoolToJson(StoryEngine.AllowStuckTeleport)
        json += ",\"dangerZonePolicy\":" + StoryEngine.DangerZonePolicy
        json += ",\"playerHomePolicy\":" + StoryEngine.PlayerHomePolicy
        json += ",\"holdPolicySeekPlayer\":" + StoryEngine.HoldPolicySeekPlayer
        json += ",\"holdPolicyInformant\":" + StoryEngine.HoldPolicyInformant
        json += ",\"holdPolicyRoadEncounter\":" + StoryEngine.HoldPolicyRoadEncounter
        json += ",\"holdPolicyAmbush\":" + StoryEngine.HoldPolicyAmbush
        json += ",\"holdPolicyStalker\":" + StoryEngine.HoldPolicyStalker
        json += ",\"holdPolicyMessage\":" + StoryEngine.HoldPolicyMessage
        json += ",\"holdPolicyQuest\":" + StoryEngine.HoldPolicyQuest
        json += ",\"confirmGoToLocation\":" + StoryEngine.ConfirmGoToLocation
        json += ",\"confirmDeliverMessage\":" + StoryEngine.ConfirmDeliverMessage
        json += ",\"confirmFetchPerson\":" + StoryEngine.ConfirmFetchPerson
        json += ",\"confirmEscortTarget\":" + StoryEngine.ConfirmEscortTarget
        json += ",\"confirmSearchForActor\":" + StoryEngine.ConfirmSearchForActor
        json += ",\"confirmScheduleMeeting\":" + StoryEngine.ConfirmScheduleMeeting
        json += ",\"confirmScheduleFetch\":" + StoryEngine.ConfirmScheduleFetch
        json += ",\"confirmScheduleDelivery\":" + StoryEngine.ConfirmScheduleDelivery
        json += ",\"npcTickEnabled\":" + BoolToJson(StoryEngine.NPCTickEnabled)
        json += ",\"npcTickInterval\":" + StoryEngine.NPCTickIntervalHours
        json += ",\"npcSocialCooldown\":" + StoryEngine.NPCSocialCooldownHours
        json += ",\"questCombat\":" + BoolToJson(StoryEngine.QuestSubTypeCombatEnabled)
        json += ",\"questRescue\":" + BoolToJson(StoryEngine.QuestSubTypeRescueEnabled)
        json += ",\"questFindItem\":" + BoolToJson(StoryEngine.QuestSubTypeFindItemEnabled)
        json += ",\"questFactionCombat\":" + BoolToJson(StoryEngine.QuestSubTypeFactionCombatEnabled)
        json += ",\"questFactionRescue\":" + BoolToJson(StoryEngine.QuestSubTypeFactionRescueEnabled)
        json += ",\"questFactionBattle\":" + BoolToJson(StoryEngine.QuestSubTypeFactionBattleEnabled)
        json += ",\"questTimeoutDays\":" + StoryEngine.QUEST_EXPIRY_DAYS
        json += ",\"questAllowVictimDeath\":" + BoolToJson(StoryEngine.QuestAllowVictimDeath)
    Else
        json += ",\"longAbsenceDays\":3,\"maxTravelDays\":1,\"allowStuckTeleport\":true"
        json += ",\"dangerZonePolicy\":1,\"playerHomePolicy\":0"
        json += ",\"holdPolicySeekPlayer\":1,\"holdPolicyInformant\":1,\"holdPolicyRoadEncounter\":1"
        json += ",\"holdPolicyAmbush\":1,\"holdPolicyStalker\":1,\"holdPolicyMessage\":1,\"holdPolicyQuest\":1"
        json += ",\"confirmGoToLocation\":1,\"confirmDeliverMessage\":1,\"confirmFetchPerson\":1,\"confirmEscortTarget\":1"
        json += ",\"confirmSearchForActor\":1,\"confirmScheduleMeeting\":1,\"confirmScheduleFetch\":1,\"confirmScheduleDelivery\":1"
        json += ",\"npcTickEnabled\":true,\"npcTickInterval\":1.5,\"npcSocialCooldown\":24"
        json += ",\"questCombat\":true,\"questRescue\":true,\"questFindItem\":true,\"questFactionCombat\":true,\"questFactionRescue\":true,\"questFactionBattle\":true"
        json += ",\"questTimeoutDays\":7,\"questAllowVictimDeath\":false"
    EndIf
    json += "}"

    json += "}"
    Return json
EndFunction

String Function EscapeJson(String text)
    ; Use C++ native for reliable JSON string escaping
    Return IntelEngine.StringEscapeJson(text)
EndFunction

String Function BoolToJson(Bool val)
    If val
        Return "true"
    EndIf
    Return "false"
EndFunction

String Function GetActorName(Actor akActor)
    If akActor != None
        Return akActor.GetDisplayName()
    EndIf
    Return ""
EndFunction

IntelEngine_Politics Property Politics  Auto
IntelEngine_Battle Property Battle Auto
