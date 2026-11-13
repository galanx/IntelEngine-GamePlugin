Scriptname IntelEngine_Core extends Quest
{
    IntelEngine Core System

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

Float Property ACTOR_ARRIVAL_DISTANCE = 200.0 AutoReadOnly
{Actor-target arrival distance; marker destinations retain ARRIVAL_DISTANCE.}

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

Float Property LINGER_RELEASE_DISTANCE = 500.0 Auto Hidden
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
    RegisterDashboardEvents()

    Float now = Utility.GetCurrentRealTime()
    ; GetCurrentRealTime() resets each Skyrim launch, but LastMaintenanceRealTime
    ; is saved. A stale saved value from a prior session is always larger than
    ; `now`, making the duplicate-call guard fire on the first load of every
    ; new session — skipping RestartMonitoring and leaving C++ singletons unsynced.
    If now < LastMaintenanceRealTime
        LastMaintenanceRealTime = 0.0
    EndIf
    If !isFirstLoad && (now - LastMaintenanceRealTime) < 2.0 && LastMaintenanceRealTime > 0.0
        DebugMsg("IntelEngine Maintenance skipped (duplicate call within 2s)")
        return
    EndIf
    LastMaintenanceRealTime = now
    ; Real time restarts with the game: forget the pending tick, the popup request and the last sweep.
    _tickDueRealTime = 0.0
    _mlRequest = ""
    _lastSweepGameTime = 0.0
    ; Register once per load after the duplicate-bootstrap guard.
    RegisterStoryEventSchemas()
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
    If !SlotStates
        InitializeSlotArrays()
    ElseIf SlotStates.Length != MAX_SLOTS
        InitializeSlotArrays()
    EndIf

    LoadDatabases()

    ; Recover active tasks on subsequent loads (not first install)
    If !isFirstLoad
        If IntelEngine.HasCoSaveTaskData()
            ; Fast path: native co-save is authoritative for dispatch state.
            ; Rehydrate display metadata from actor StorageUtil fields, which are not in the native co-save.
            ; Do NOT reverse-sync the remaining slot fields; that would overwrite
            ; speed/deadline/offscreenArrival with zeroes (UpdateSlotState doesn't set those).
            IntelEngine.SyncArraysFromSlotTracker()
            SyncTaskMetadataToSlotTracker()
            DebugMsg("Task recovery: co-save dispatch state + StorageUtil metadata")
        Else
            ; Legacy fallback: pre-upgrade saves without co-save data.
            ; Reads StorageUtil keys to rebuild slot state.
            RecoverActiveTasks()
            DebugMsg("Task recovery: StorageUtil legacy path")
        EndIf
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
        DebugMsg(akAgent.GetDisplayName() + " task cancelled - skipping history")
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
    StorageUtil.SetStringValue(akAgent, "Intel_TaskHistoryRendered", IntelEngine.EncodeRenderedCache(rendered))

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
        ElseIf firstFree < 0 && SlotIsVacant(i)
            ; State 0 with the agent still in the alias is a task being finished (the handlers mark the slot
            ; and then wait while a line is narrated). Handing that slot out let the old handler wipe the new task.
            firstFree = i
        EndIf
        i += 1
    EndWhile

    If firstFree >= 0 && activeCount < maxAllowed
        Return firstFree
    EndIf
    Return -1
EndFunction

Bool Function SlotIsVacant(Int slot)
    ReferenceAlias slotAlias = GetAgentAlias(slot)
    Return slotAlias == None || slotAlias.GetActorReference() == None
EndFunction

Bool Function SlotHolds(Int slot, Actor npc)
    {Is this NPC (still) the agent in this slot? For code that comes back from a wait.}
    If slot < 0 || slot >= MAX_SLOTS || npc == None
        Return false
    EndIf
    ReferenceAlias slotAlias = GetAgentAlias(slot)
    Return slotAlias != None && slotAlias.GetActorReference() == npc
EndFunction

Actor[] _limboAgents

Function ValidateSlots()
    {Slots that nothing looks after any more: an active one whose agent is gone or dead, and one left in the
    "being finished" state (0 with the agent still in it) on two passes in a row. Called with the hourly sweep.}
    If !_limboAgents
        _limboAgents = new Actor[5]
    EndIf
    Int i = 0
    While i < MAX_SLOTS && i < 5
        ReferenceAlias slotAlias = GetAgentAlias(i)
        Actor agent = None
        If slotAlias
            agent = slotAlias.GetActorReference()
        EndIf
        If SlotStates[i] != 0
            _limboAgents[i] = None
            If agent == None || agent.IsDead()
                DebugMsg("Slot " + i + " was active without a living agent -> cleared")
                ClearSlot(i)
            EndIf
        ElseIf agent != None
            If _limboAgents[i] == agent
                DebugMsg("Slot " + i + " was left half finished with " + agent.GetDisplayName() + " in it -> cleared")
                _limboAgents[i] = None
                ClearSlot(i)
            Else
                _limboAgents[i] = agent
            EndIf
        Else
            _limboAgents[i] = None
        EndIf
        i += 1
    EndWhile
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

Function AllocateSlot(Int slot, Actor akAgent, String taskType, String targetName, Int speed, String taskOrigin = "SkyrimNet dialogue action", String taskReason = "")
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

    StorageUtil.SetStringValue(akAgent, "Intel_TaskOrigin", taskOrigin)
    StorageUtil.SetFloatValue(akAgent, "Intel_TaskAllocatedAt", Utility.GetCurrentGameTime())
    StorageUtil.SetStringValue(akAgent, "Intel_TaskReason", taskReason)

    ; Push to C++ SlotTracker for SkyrimNet decorators/eligibility + co-save persistence
    IntelEngine.UpdateSlotState(slot, akAgent, 1, taskType, targetName, taskOrigin, StorageUtil.GetFloatValue(akAgent, "Intel_TaskAllocatedAt", -1.0), taskReason)
    IntelEngine.SetSlotSpeed(slot, speed)

    DebugMsg("Allocated slot " + slot + " to " + akAgent.GetDisplayName() + " for " + taskType)
    PushDashboardState()
EndFunction

Function ReleaseAgent(Actor agent, Int slot)
    {Everything IntelEngine put on an NPC for a task comes off again: its packages, the linked refs, the task
    faction, the task keys, a courier's lowered aggression, the look-at; and a follower gets the teammate flag
    back. That last part used to happen on the success paths only, so a follower whose errand failed, timed
    out, was cancelled or was replaced by another task stopped being a teammate for good.
    slot is the slot they hold, or -1 when they hold none any more (the sweep, or a slot that changed hands
    while a handler was waiting): then there is no history entry and no per-slot tracker to reset.}
    If agent == None
        Return
    EndIf
    Bool wasFollower = StorageUtil.GetIntValue(agent, "Intel_WasFollower") as Bool
    If slot >= 0
        ; Save to task history before clearing
        String histType = SlotTaskTypes[slot]
        String histTarget = SlotTargetNames[slot]
        String histResult = StorageUtil.GetStringValue(agent, "Intel_Result")
        DebugMsg("Clearing slot " + slot + ": " + agent.GetDisplayName() + " [result='" + histResult + "']")
        String histMessage = StorageUtil.GetStringValue(agent, "Intel_Message")
        String histMeetLoc = StorageUtil.GetStringValue(agent, "Intel_DeliveryMeetLocation")
        If histType != ""
            SaveTaskToHistory(agent, histType, histTarget, histResult, histMessage, histMeetLoc)
        EndIf
    EndIf

    ; The task is over: only IntelEngine's own packages go. Wiping every mod's overrides here took a follow
    ; framework's wait or follow package and SkyrimNet's with it, and nothing put them back.
    RemoveIntelPackages(agent, false)
    agent.ClearLookAt()

    ; Clear linked refs
    ClearLinkedRefs(agent)

    ; Remove from task faction
    agent.RemoveFromFaction(IntelEngine_TaskFaction)

    ; Clear StorageUtil data
    StorageUtil.UnsetStringValue(agent, "Intel_TaskType")
    StorageUtil.UnsetStringValue(agent, "Intel_Target")
    StorageUtil.UnsetIntValue(agent, "Intel_Slot")
    StorageUtil.UnsetIntValue(agent, "Intel_State")
    StorageUtil.UnsetStringValue(agent, "Intel_TaskOrigin")
    StorageUtil.UnsetStringValue(agent, "Intel_TaskReason")
    StorageUtil.UnsetIntValue(agent, "Intel_Speed")
    StorageUtil.UnsetFormValue(agent, "Intel_TargetNPC")
    StorageUtil.UnsetStringValue(agent, "Intel_Message")
    StorageUtil.UnsetFloatValue(agent, "Intel_ScheduledTime")

    ; Clear travel/navigation data
    StorageUtil.UnsetFormValue(agent, "Intel_DestMarker")
    StorageUtil.UnsetFormValue(agent, "Intel_ReturnMarker")
    StorageUtil.UnsetFormValue(agent, "Intel_CurrentWaypoint")
    StorageUtil.UnsetFloatValue(agent, "Intel_TaskStartTime")
    StorageUtil.UnsetFloatValue(agent, "Intel_CapCheckX")
    StorageUtil.UnsetFloatValue(agent, "Intel_CapCheckY")
    StorageUtil.UnsetFloatValue(agent, "Intel_SettingOffUntil")
    StorageUtil.UnsetFloatValue(agent, "Intel_TargetWaitSince")
    StorageUtil.UnsetFloatValue(agent, "Intel_OffScreenSince")
    StorageUtil.UnsetFloatValue(agent, "Intel_TaskAllocatedAt")
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

    ; Reset C++ departure detector, off-screen tracker, and proximity monitor for this slot
    If slot >= 0
        IntelEngine.ResetDepartureSlot(slot, None)
        IntelEngine.ResetOffScreenSlot(slot)
        IntelEngine.DisarmProximityArrival(slot)
    EndIf
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
    StorageUtil.UnsetFloatValue(agent, "Intel_LingerLastDist")
    StorageUtil.UnsetIntValue(agent, "Intel_SocSceneHold")
    StorageUtil.UnsetFloatValue(agent, "Intel_MeetingLingerCap")
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
    StorageUtil.UnsetFloatValue(agent, "Intel_OffscreenDiagAt")

    ; Clean up unlock tracking key (vanilla handles re-locking)
    StorageUtil.UnsetIntValue(agent, "Intel_UnlockedHomeCellId")

    ; Clear task cooldown
    StorageUtil.UnsetFloatValue(agent, "Intel_TaskCooldown")

    ; Clear story engine dispatch keys
    StorageUtil.UnsetIntValue(agent, "Intel_IsStoryDispatch")
    StorageUtil.UnsetStringValue(agent, "Intel_StoryNarration")

    ; Restore courier aggression if it was modified
    Float origAggr = StorageUtil.GetFloatValue(agent, "Intel_OrigAggression", -1.0)
    If origAggr >= 0.0
        agent.SetActorValue("Aggression", origAggr)
        StorageUtil.UnsetFloatValue(agent, "Intel_OrigAggression")
    EndIf

    If wasFollower
        agent.SetPlayerTeammate(true)
    EndIf

    ; Re-evaluate AI
    agent.EvaluatePackage()
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
            ; A handler that comes back late may clear a slot whose NPC has meanwhile been given a new task in
            ; another slot. That task's packages and keys are on the NPC now: leave them.
            Int otherSlot = FindSlotByAgent(agent)
            If otherSlot >= 0 && otherSlot != slot
                DebugMsg("Clearing slot " + slot + ": " + agent.GetDisplayName() + " already has a new task in slot " + otherSlot + " -> NPC left as is")
            Else
                ReleaseAgent(agent, slot)
            EndIf
        EndIf
        agentAlias.Clear()
    EndIf

    ; Clean up target if any — use RemoveIntelPackages to preserve SkyrimNet packages
    If targetAlias
        Actor target = targetAlias.GetActorReference()
        If target
            RemoveIntelPackages(target)
            ClearLinkedRefs(target)
            target.ClearLookAt()
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
    PushDashboardState()
EndFunction

; =============================================================================
; TASK CONTROL (cancel, speed change — called by SkyrimNet actions)
; =============================================================================

Bool Function CancelCurrentTask(Actor akNPC, Bool force = false)
    {Cancel the NPC's current task entirely. SkyrimNet actions keep the nearby-player
    guard; manual Director cancellation bypasses only that guard.}
    If akNPC == None
        Return false
    EndIf
    Int slot = FindSlotByAgent(akNPC)
    If slot < 0
        Return false
    EndIf

    ; Block cancellation while player is nearby — prevents premature LLM task clearing.
    ; The linger release mechanism will clean up when the player walks away.
    If !force && !ShouldReleaseLinger(akNPC)
        DebugMsg(akNPC.GetDisplayName() + " cancel blocked: player nearby")
        Return false
    EndIf

    ; A meeting the player agreed to is not the NPC's to drop on a whim. The trip is narrated when it starts,
    ; the NPC gets a turn, and the LLM readily answers with CancelCurrentTask ("stop travelling, she has
    ; arrived"). That used to cancel the trip and delete the meeting from the schedule without a word, so the
    ; NPC never showed up. Only the player (dashboard, MCM, Director: force) ends a scheduled meeting early.
    If !force && StorageUtil.GetIntValue(akNPC, "Intel_IsScheduledMeeting") == 1
        DebugMsg(akNPC.GetDisplayName() + " cancel blocked: on a scheduled meeting")
        Return false
    EndIf

    StorageUtil.SetStringValue(akNPC, "Intel_Result", "cancelled")
    ClearSlotRestoreFollower(slot, akNPC)
    If StoryEngine && StoryEngine.IsActive && StoryEngine.ActiveStoryNPC == akNPC
        If StoryEngine.ActiveNarration != ""
            InjectFact(akNPC, "stopped before finishing: " + StoryEngine.ActiveNarration)
        EndIf
        StoryEngine.CleanupStoryDispatch()
    EndIf
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
    If akAgent != None && !SlotHolds(slot, akAgent)
        ; A handler coming back from a wait after the slot was cleared or re-used: it produced an active
        ; slot without agent, or changed another NPC's task.
        DebugMsg("SetSlotState ignored: slot " + slot + " does not hold " + akAgent.GetDisplayName())
        Return
    EndIf
    SlotStates[slot] = newState
    String taskOrigin = ""
    String taskReason = ""
    Float allocatedAt = -1.0
    If akAgent != None
        StorageUtil.SetIntValue(akAgent, "Intel_State", newState)
        taskOrigin = StorageUtil.GetStringValue(akAgent, "Intel_TaskOrigin")
        taskReason = StorageUtil.GetStringValue(akAgent, "Intel_TaskReason")
        allocatedAt = StorageUtil.GetFloatValue(akAgent, "Intel_TaskAllocatedAt", -1.0)
    EndIf
    IntelEngine.UpdateSlotState(slot, akAgent, newState, SlotTaskTypes[slot], SlotTargetNames[slot], taskOrigin, allocatedAt, taskReason)
EndFunction

Function SetSlotSpeed(Int slot, Actor akAgent, Int newSpeed)
    {Update travel speed — writes array, StorageUtil, and C++ SlotTracker.}
    If slot < 0 || slot >= MAX_SLOTS
        Return
    EndIf
    SlotSpeeds[slot] = newSpeed
    IntelEngine.SetSlotSpeed(slot, newSpeed)
    If akAgent != None
        StorageUtil.SetIntValue(akAgent, "Intel_Speed", newSpeed)
    EndIf
EndFunction

Function SetSlotDeadline(Int slot, Float deadline)
    {Update wait deadline — persisted via C++ co-save + StorageUtil legacy.}
    If slot < 0 || slot >= MAX_SLOTS
        Return
    EndIf
    SlotDeadlines[slot] = deadline
    IntelEngine.SetSlotDeadline(slot, deadline)
    ; Legacy StorageUtil persistence (for pre-upgrade saves)
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
    If akAgent != None && !SlotHolds(slot, akAgent)
        ; The slot was cleared or changed hands while this handler was waiting. A task in it now is somebody
        ; else's: clean up our own agent (unless they hold a new task themselves) and leave that slot alone.
        DebugMsg("Slot " + slot + " no longer holds " + akAgent.GetDisplayName() + " -> releasing the NPC only")
        If FindSlotByAgent(akAgent) < 0
            ReleaseAgent(akAgent, -1)
        EndIf
        If SlotIsVacant(slot)
            ClearSlot(slot)
        EndIf
        Return
    EndIf
    ; ReleaseAgent (in ClearSlot) gives a follower the teammate flag back.
    ClearSlot(slot)
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

Float Property LINGER_VISIT_MAX_HOURS = 6.0 AutoReadOnly
{No visit at the player's side lasts longer than this many game hours, whatever is being said.}

Bool Function IsTalkingWithPlayer(Actor npc)
    {Is this NPC in a conversation the player is part of: in dialogue with the player, or speaking with nobody
    in particular (a remark, a reaction)? A chat with somebody else does not count. The visits that are not
    to end "in the middle of a conversation" never ended in a busy inn, where the visitor always had someone
    to talk to (seen in game on 2026-11-13: a meeting NPC talked with the bard and stayed for hours).}
    If npc == None || !npc.Is3DLoaded()
        Return false
    EndIf
    Actor partner = npc.GetDialogueTarget()
    If partner != None
        Return partner == Game.GetPlayer()
    EndIf
    Return IntelEngine.IsActorTalking(npc)
EndFunction

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
    StorageUtil.UnsetStringValue(npc, "Intel_ArrivalPurpose")
    StorageUtil.UnsetStringValue(npc, "Intel_ArrivalTopic")
    DebugMsg("Linger release START: " + npc.GetDisplayName() + " [formID=" + npc.GetFormID() + ", 3Dloaded=" + npc.Is3DLoaded() + ", isTeammate=" + npc.IsPlayerTeammate() + "]")
    If FindSlotByActor(npc) >= 0
        ; A new IntelEngine task holds them, as its agent or as the person being fetched or escorted. Its
        ; packages and its travel target are in place; the sandbox of that task may be this same package.
        ; Nothing of theirs is touched: only the old linger is forgotten.
        DebugMsg("Linger release: " + npc.GetDisplayName() + " has a new task -> left to it")
        StorageUtil.UnsetIntValue(npc, "Intel_MeetingLingerApproaching")
        StorageUtil.UnsetIntValue(npc, "Intel_LingerFarTicks")
        Return
    EndIf
    ActorUtil.RemovePackageOverride(npc, SandboxNearPlayerPackage)
    DebugMsg("Linger release: removed sandbox from " + npc.GetDisplayName())
    ; Released while still on the approach (a rescued victim walking up to the player): the approach's walk
    ; override would stay behind with nothing to walk to.
    If StorageUtil.GetIntValue(npc, "Intel_MeetingLingerApproaching") == 1
        ActorUtil.RemovePackageOverride(npc, TravelPackage_Walk)
        StorageUtil.UnsetIntValue(npc, "Intel_MeetingLingerApproaching")
    EndIf
    npc.ClearLookAt()
    ; NPCs with schedule-based AI (eat, sleep, patrol, travel) can handle
    ; returning to their routine on their own. NPCs with ONLY sandbox AI
    ; (common for modded followers) will just sandbox wherever they are,
    ; which looks broken if they're displaced. Walk those home instead.
    If npc.IsPlayerTeammate()
        PO3_SKSEFunctions.SetLinkedRef(npc, None, IntelEngine_TravelTarget)
        DebugMsg("Linger release: " + npc.GetDisplayName() + " is teammate -> cleared linked ref")
    ElseIf IsFollowingPlayer(npc)
        ; Recruited through a follow system that does not set the teammate flag (SeverActions' casual follow,
        ; a follower framework). Sending them home here put a priority-100 walk override on top of the follow
        ; package: they walked off instead of following, and nothing ever took that override away again.
        PO3_SKSEFunctions.SetLinkedRef(npc, None, IntelEngine_TravelTarget)
        DebugMsg("Linger release: " + npc.GetDisplayName() + " is following the player -> cleared linked ref")
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
                ; This override belongs to no task slot, so remember it: SweepStalePackages takes it off again
                ; once they are home, out of sight, recruited, or WALK_HOME_MAX_HOURS have passed.
                TrackWalkHome(npc)
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
    StorageUtil.UnsetFloatValue(npc, "Intel_LingerLastDist")
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
    ; On the way to a meeting the player agreed to: no other task replaces that trip. The model starts one as
    ; easily as it cancels (it reacts to the "departed for ..." line); the meeting then never happened and its
    ; entry stayed in the schedule as "dispatched". The schedule's own dispatch clears the old slot first, and
    ; the Director has its own check, so neither comes through here with the meeting flag set.
    If StorageUtil.GetIntValue(npc, "Intel_IsScheduledMeeting") == 1 && FindSlotByAgent(npc) >= 0
        DebugMsg("New " + taskType + " task ignored: " + npc.GetDisplayName() + " is on a scheduled meeting")
        Return true
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
    ReleaseStoryClaims(npc)
    ; The same for a fetched or escorted NPC who still lingers and is now given a task of their own: the
    ; linger kept handling them and took the new task's walk package off again (see NPCTasks.ForgetLinger).
    ; Their packages stay until they set off (the task start clears them then).
    If NPCTasks
        NPCTasks.ForgetLinger(npc, false)
    EndIf
EndFunction

Function ReleaseStoryClaims(Actor npc)
    {The NPC is starting something else: let go of whatever the story engine still holds on them.
    Clearing the slot alone left a dispatched story marked active (it kept steering the NPC back to the player
    and blocked new stories until the 6-hour watchdog), and left a lingering visitor's sandbox on top of the
    new task.}
    If npc == None || StoryEngine == None
        Return
    EndIf
    If StoryEngine.IsActive && StoryEngine.ActiveStoryNPC == npc
        DebugMsg(npc.GetDisplayName() + " leaves the active story for a new task")
        StoryEngine.CleanupStoryDispatch()
    EndIf
    ; The same for an NPC-to-NPC visit they were walking to. Its bookkeeping went on naming them as the
    ; traveler: the visit's monitoring then worked on the new task's slot (stuck recovery, the teleport to
    ; the other NPC, and at the end clearing that slot), and no other visit could start meanwhile.
    If StoryEngine.IsNPCStoryActive && StoryEngine.NPCSocialTraveler == npc
        DebugMsg(npc.GetDisplayName() + " leaves the NPC-to-NPC visit for a new task")
        StoryEngine.ResetNPCSocialDispatchState()
    EndIf
    StoryEngine.ForgetLingerActor(npc)
EndFunction

; =============================================================================
; WHO MAY BE SENT, WHO IS FOLLOWING, AND THE STALE-OVERRIDE SWEEP
; =============================================================================

Float Property WALK_HOME_MAX_HOURS = 3.0 AutoReadOnly
; How long the "X wants to ..." choice waits before it counts as Deny (Silent) (real seconds, Magelight page only).
Float Property PROMPT_SECONDS_TASK = 20.0 AutoReadOnly
Faction _carriageSystemFaction
Faction _currentFollowerFaction
Faction _severFollowingFaction
Bool _softFormsResolved = false

Function ResolveSoftForms()
    {Forms of the base game and of other mods, looked up once per load. None when the mod is not installed.}
    _carriageSystemFaction = Game.GetFormFromFile(0x00017F04, "Skyrim.esm") as Faction      ; CarriageSystemFaction
    _currentFollowerFaction = Game.GetFormFromFile(0x0005C84E, "Skyrim.esm") as Faction     ; CurrentFollowerFaction
    _severFollowingFaction = None
    If Game.IsPluginInstalled("SeverActions.esp")
        _severFollowingFaction = Game.GetFormFromFile(0x000F0809, "SeverActions.esp") as Faction   ; SeverActions_ActivelyFollowing
    EndIf
    _softFormsResolved = true
EndFunction

Bool Function IsFollowingPlayer(Actor npc)
    {True when some follow system has this NPC with the player right now: the vanilla teammate flag, the vanilla
    follower faction, or SeverActions' follow (which sets neither).}
    If npc == None
        Return false
    EndIf
    If !_softFormsResolved
        ResolveSoftForms()
    EndIf
    If npc.IsPlayerTeammate()
        Return true
    EndIf
    If _currentFollowerFaction && npc.GetFactionRank(_currentFollowerFaction) >= 0
        Return true
    EndIf
    ; Rank -1 is what RemoveFromFaction leaves behind, so test the rank, not membership.
    If _severFollowingFaction && npc.GetFactionRank(_severFollowingFaction) >= 0
        Return true
    EndIf
    Return false
EndFunction

Bool Function IsUnsuitableTaskAgent(Actor npc)
    {NPCs that must never be given a travel, fetch, escort, search or delivery task.
    Carriage drivers: the LLM hears "let's go" in their own lines and fires a travel action; the travel override
    pulls them off the cart, the carriage service is broken from then on, and face to face the task could not
    even be cancelled. They carry CarriageSystemFaction in the base game and in Hearthfire and Dawnguard.}
    If npc == None
        Return true
    EndIf
    If !_softFormsResolved
        ResolveSoftForms()
    EndIf
    If _carriageSystemFaction && npc.IsInFaction(_carriageSystemFaction)
        Return true
    EndIf
    If npc.IsChild()
        Return true
    EndIf
    Return false
EndFunction

Float Property SPEECH_GRACE_SECONDS = 7.0 AutoReadOnly

Function LetFinishSpeaking(Actor npc)
    {A task that starts in conversation fires while the NPC is still answering ("Alright, I'll head to the
    Bannered Mare"). Putting the travel package on at that instant made them turn and walk off in the middle
    of the sentence. This waits until the line is over, SPEECH_GRACE_SECONDS at most. Nothing happens for an
    NPC who is not loaded (nobody would hear them). Latent: the caller re-checks its slot afterwards.}
    If npc == None || !npc.Is3DLoaded()
        Return
    EndIf
    ; The spoken reply usually begins a moment after the action has fired.
    Utility.Wait(0.7)
    Float waited = 0.7
    While waited < SPEECH_GRACE_SECONDS && npc.Is3DLoaded() && IntelEngine.IsActorTalking(npc)
        Utility.Wait(0.4)
        waited += 0.4
    EndWhile
EndFunction

Function TrackWalkHome(Actor npc)
    StorageUtil.SetFloatValue(npc, "Intel_WalkHomeUntil", Utility.GetCurrentGameTime() + WALK_HOME_MAX_HOURS / 24.0)
    ; Remember where home is: the linked ref can later belong to something else that took the NPC over.
    StorageUtil.SetFormValue(npc, "Intel_WalkHomeRef", npc.GetLinkedRef(IntelEngine_TravelTarget))
    StorageUtil.FormListAdd(self, "Intel_WalkHomeActors", npc as Form, false)
EndFunction

Function EndWalkHome(Actor npc, Bool removeOverride)
    If removeOverride
        ActorUtil.RemovePackageOverride(npc, TravelPackage_Walk)
        PO3_SKSEFunctions.SetLinkedRef(npc, None, IntelEngine_TravelTarget)
        npc.EvaluatePackage()
    EndIf
    StorageUtil.UnsetFloatValue(npc, "Intel_WalkHomeUntil")
    StorageUtil.UnsetFormValue(npc, "Intel_WalkHomeRef")
    StorageUtil.FormListRemove(self, "Intel_WalkHomeActors", npc as Form, true)
EndFunction

Function CheckWalkHomeActors()
    {Take the walk-home override off again: at home, out of sight, recruited, on a new task, or after the limit.}
    Int i = StorageUtil.FormListCount(self, "Intel_WalkHomeActors") - 1
    Float now = Utility.GetCurrentGameTime()
    While i >= 0
        Actor npc = StorageUtil.FormListGet(self, "Intel_WalkHomeActors", i) as Actor
        If npc == None || npc.IsDead() || npc.IsDisabled()
            StorageUtil.FormListRemoveAt(self, "Intel_WalkHomeActors", i)
        ElseIf FindSlotByActor(npc) >= 0 || TakenOverElsewhere(npc)
            ; A task (as agent or target), a story or a linger owns them now: its own package and linked ref
            ; are in place, leave both alone.
            EndWalkHome(npc, false)
        Else
            ObjectReference home = StorageUtil.GetFormValue(npc, "Intel_WalkHomeRef") as ObjectReference
            If home == None
                home = npc.GetLinkedRef(IntelEngine_TravelTarget)       ; tracked by an earlier version
            EndIf
            Bool done = home == None || !npc.Is3DLoaded() || IsFollowingPlayer(npc)
            If !done && now >= StorageUtil.GetFloatValue(npc, "Intel_WalkHomeUntil", 0.0)
                done = true
            EndIf
            If !done && npc.GetParentCell() == home.GetParentCell() && npc.GetDistance(home) < 400.0
                done = true
            EndIf
            If done
                If !npc.Is3DLoaded() && !IsFollowingPlayer(npc)
                    ; Nobody is watching: finish the walk where they belong. "Home" can be a location's map
                    ; marker when nothing better was known; their own editor spot is the real place.
                    npc.MoveToMyEditorLocation()
                EndIf
                DebugMsg("Walk home finished: " + npc.GetDisplayName())
                EndWalkHome(npc, true)
            EndIf
        EndIf
        i -= 1
    EndWhile
EndFunction

Bool Function TakenOverElsewhere(Actor npc)
    {Held by the story engine or by a lingering fetch or escort: things that hand out packages without a slot.}
    If StoryEngine && StoryEngine.HoldsActor(npc)
        Return true
    EndIf
    If NPCTasks && NPCTasks.HoldsActor(npc)
        Return true
    EndIf
    Return false
EndFunction

Bool Function OwnsPackagesOf(Actor npc)
    {Does any live IntelEngine state account for this NPC running one of our packages?}
    If FindSlotByActor(npc) >= 0
        Return true
    EndIf
    If StorageUtil.FormListFind(self, "Intel_WalkHomeActors", npc as Form) >= 0
        Return true
    EndIf
    If StoryEngine && StoryEngine.HoldsActor(npc)
        Return true
    EndIf
    If NPCTasks && NPCTasks.HoldsActor(npc)
        Return true
    EndIf
    Return false
EndFunction

Float _lastSweepGameTime = 0.0

Float _tickDueRealTime = 0.0

Function RequestTick(Float seconds)
    {Ask for the next monitoring tick. Every script of this quest shares ONE real-time update registration (it
    belongs to the quest, not to the script), and every OnUpdate fires in all of them. Each script used to call
    RegisterForSingleUpdate itself, so the last caller won: the story engine's 30-second idle poll, registered
    at the end of its handler, kept replacing the 3-second travel poll and the half-second return poll. Travelling
    NPCs were looked at every half minute. Here a request only re-registers when it is sooner than what is pending.}
    Float now = Utility.GetCurrentRealTime()
    If _tickDueRealTime > now + 0.25 && _tickDueRealTime <= now + seconds + 0.01 && _tickDueRealTime < now + 120.0
        Return
    EndIf
    _tickDueRealTime = now + seconds
    RegisterForSingleUpdate(seconds)
EndFunction

Function SweepIfDue()
    {Run the sweep once per game hour, whoever asks: the real-time monitoring loops and the game-time event.}
    Float now = Utility.GetCurrentGameTime()
    If now < _lastSweepGameTime || now - _lastSweepGameTime >= 1.0 / 24.0
        _lastSweepGameTime = now
        SweepStalePackages()
    EndIf
EndFunction

Function SweepStalePackages(Bool atOnce = false)
    {The dashboard lists NPCs who run an IntelEngine package without a task ("Other IE packages") and offers a
    Remove button. This does the same on its own, once per game hour and on load, for every such NPC that nothing
    in the mod accounts for any more. An NPC has to be found unaccounted for on two sweeps in a row, so a package
    that was just handed out between two bookkeeping steps is never taken away. atOnce (the manual reset)
    releases them on the first sighting.}
    CheckWalkHomeActors()
    ValidateSlots()
    Float nowGame = Utility.GetCurrentGameTime()
    Int[] ids = new Int[6]
    ids[0] = TravelPackage_Walk.GetFormID()
    ids[1] = TravelPackage_Jog.GetFormID()
    ids[2] = TravelPackage_Run.GetFormID()
    If TravelPackage_Stalk
        ids[3] = TravelPackage_Stalk.GetFormID()
    EndIf
    If SandboxPackage
        ids[4] = SandboxPackage.GetFormID()
    EndIf
    If SandboxNearPlayerPackage
        ids[5] = SandboxNearPlayerPackage.GetFormID()
    EndIf
    Actor[] holders = IntelEngine.GetActorsWithPackages(ids)
    If holders.Length > 0
        DebugMsg("Sweep: " + holders.Length + " NPC(s) currently run an IntelEngine package")
    EndIf
    Int i = 0
    While i < holders.Length
        Actor npc = holders[i]
        If npc != None
            Float seenAt = StorageUtil.GetFloatValue(npc, "Intel_StaleSeenAt", 0.0)
            If OwnsPackagesOf(npc)
                StorageUtil.UnsetFloatValue(npc, "Intel_StaleSeenAt")
            ElseIf !atOnce && (seenAt <= 0.0 || nowGame < seenAt || nowGame - seenAt > 0.25)
                ; First sighting, or the last one is more than six game hours old and counts no longer.
                StorageUtil.SetFloatValue(npc, "Intel_StaleSeenAt", nowGame)
            Else
                DebugMsg("Sweep: " + npc.GetDisplayName() + " still ran an IntelEngine package with no task behind it -> released")
                StorageUtil.UnsetFloatValue(npc, "Intel_StaleSeenAt")
                ; The whole release, not the packages alone: the task faction and the task keys kept the NPC
                ; "busy" for every later request.
                ReleaseAgent(npc, -1)
            EndIf
        EndIf
        i += 1
    EndWhile
EndFunction

Bool Function IsCarriageDriver(Actor npc)
    {A carriage driver must not be made the target of a fetch or an escort, or be moved to the player by a
    search, either: a travel package or a teleport takes them off the cart just like a task of their own
    would (see IsUnsuitableTaskAgent). Children, whom that function also refuses as agents, may be fetched
    and escorted.}
    If npc == None
        Return false
    EndIf
    If !_softFormsResolved
        ResolveSoftForms()
    EndIf
    Return _carriageSystemFaction != None && npc.IsInFaction(_carriageSystemFaction)
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

Int Function ShowTaskConfirmationForAction(Actor npc, String promptText, String actionName, String taskOrigin = "")
    {Per-action confirmation prompt. Returns: 0=allow, 1=deny (narrate), 2=deny silent.
    Mode per action: 0=disabled, 1=followers only, 2=everyone.}

    ; Per-action follower skip — checked BEFORE confirmation prompt
    If npc.IsPlayerTeammate() && actionName != "" && StoryEngine != None
        Bool skipFollower = false
        If actionName == "GoToLocation"
            skipFollower = StoryEngine.SkipFollowerGoToLocation
        ElseIf actionName == "DeliverMessage"
            skipFollower = StoryEngine.SkipFollowerDeliverMessage
        ElseIf actionName == "FetchPerson"
            skipFollower = StoryEngine.SkipFollowerFetchPerson
        ElseIf actionName == "EscortTarget"
            skipFollower = StoryEngine.SkipFollowerEscortTarget
        ElseIf actionName == "SearchForActor"
            skipFollower = StoryEngine.SkipFollowerSearchForActor
        ElseIf actionName == "ScheduleFetch"
            skipFollower = StoryEngine.SkipFollowerScheduleFetch
        ElseIf actionName == "ScheduleDelivery"
            skipFollower = StoryEngine.SkipFollowerScheduleDelivery
        ElseIf actionName == "ScheduleMeeting"
            skipFollower = StoryEngine.SkipFollowerScheduleMeeting
        EndIf
        If skipFollower
            DebugMsg("Skipping " + actionName + " for follower " + npc.GetDisplayName())
            Return 2  ; deny silent
        EndIf
    EndIf

    ; A scheduled fetch or delivery was agreed to when it was scheduled; asking again when it starts meant
    ; that not answering in time dropped it without a word.
    If StorageUtil.GetIntValue(npc, "Intel_ScheduledExecution") == 1
        StorageUtil.UnsetIntValue(npc, "Intel_ScheduledExecution")
        Return 0
    EndIf

    If taskOrigin == "Director"
        Return 0  ; Director-dispatched actions skip the confirmation prompt
    EndIf

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
    ; Unanswered, the request counts as Deny (Silent) once the time is up, so it never holds up the game.
    String result = ShowChoice(npc.GetDisplayName(), "Task permission", promptText, "Allow", "Deny", "Deny (Silent)", PROMPT_SECONDS_TASK)
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
    IntelEngine.SetSlotOffscreenArrival(slot, estimatedArrival)
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
    Float now = Utility.GetCurrentRealTime()
    Float lastDiag = StorageUtil.GetFloatValue(npc, "Intel_OffscreenDiagAt", -10.0)
    If now < lastDiag || now - lastDiag >= 10.0
        DebugMsg("[diag:offscreen] " + npc.GetDisplayName() + " status=" + status)
        StorageUtil.SetFloatValue(npc, "Intel_OffscreenDiagAt", now)
    EndIf
    If status == 1
        DebugMsg("[diag:arrival] " + npc.GetDisplayName() + " off-screen arrival " + IntelEngine.DescribeDistance(npc, dest))
        If PlaceForUnseenArrival(npc, dest)
            ; The destination is where the player is standing: the NPC was put at the way in and walks the
            ; rest with the package they already have. Arrival is noticed like any other.
            InitOffScreenTracking(slot, npc, dest)
            npc.EvaluatePackage()
            Return false
        EndIf
        npc.MoveTo(dest)
        Utility.Wait(0.3)
        npc.EvaluatePackage()
        Return true
    EndIf
    Return false
EndFunction

Bool Function PlaceForUnseenArrival(Actor npc, ObjectReference dest)
    {An NPC who travelled unseen has "arrived", but the destination is in front of the player (they are waiting
    at the meeting spot, or are the destination themselves). Appearing on the spot is a pop-in. Indoors the NPC is
    put at a door of the player's cell, as if they had just come in; outdoors a good way behind the player.
    False when the destination is not near the player: then it is simply the place to be.}
    Actor player = Game.GetPlayer()
    If dest == None || npc == None
        Return false
    EndIf
    Cell playerCell = player.GetParentCell()
    If playerCell != None && playerCell.IsInterior()
        If dest.GetParentCell() != playerCell
            Return false
        EndIf
        ObjectReference wayIn = WayIntoPlayerCell()
        If wayIn == None
            Return false
        EndIf
        npc.MoveTo(wayIn)
        DebugMsg(npc.GetDisplayName() + " placed at the door of the player's cell to walk in")
        Return true
    EndIf
    If !dest.Is3DLoaded() && dest != (player as ObjectReference)
        Return false
    EndIf
    If dest != (player as ObjectReference) && player.GetDistance(dest) > 3000.0
        Return false
    EndIf
    TeleportBehindPlayer(npc, 2500.0)
    Return true
EndFunction

Bool Function PlayerCanSee(Actor npc)
    {Would the player notice this NPC being moved? Loaded, not far off, and on screen (for the player, HasLOS
    is true only for what is in view). Used to keep recovery moves out of sight.}
    If npc == None || !npc.Is3DLoaded()
        Return false
    EndIf
    Actor player = Game.GetPlayer()
    If npc.GetDistance(player) > 6000.0
        Return false
    EndIf
    Return player.HasLOS(npc)
EndFunction

Package Function TravelPackageOn(Actor npc, Package fallback)
    {The travel package this NPC is running right now, else the one given. Recovery used to put the slot's
    nominal speed back on top of whatever was really applied (a walk for the return leg, the stalk package of
    a stalker), which left two travel overrides at the same priority: a walking NPC broke into a jog after one
    recovery, a stalker stood up.}
    Package running = npc.GetCurrentPackage()
    If running != None && (running == TravelPackage_Walk || running == TravelPackage_Jog || running == TravelPackage_Run || running == TravelPackage_Stalk)
        Return running
    EndIf
    Return fallback
EndFunction

Function SoftStuckRecovery(Actor npc, Int slot, ObjectReference dest)
    {Soft stuck recovery: random displacement + re-apply travel package.
    Shared by Travel and NPCTasks stuck handlers.
    While the player is looking at the NPC there is no displacement (it showed as a hop of a pace or two with
    a drop from knee height); the package is taken off and put back instead, which makes the AI plan a new path.}
    ; Standing still to talk is not being stuck (SkyrimNet conversations do not set a dialogue target).
    If IntelEngine.IsActorTalking(npc)
        IntelEngine.ResetStuckSlot(slot, npc)
        Return
    EndIf
    Package travelPkg = TravelPackageOn(npc, GetTravelPackage(SlotSpeeds[slot]))
    ; Not moving because a package from elsewhere is running on top of ours (told to follow or to stay by
    ; another mod in the middle of the trip). Nudging does nothing against that: the NPC stood there until
    ; the time limit. The other overrides are taken off, as they are when a task starts, and ours is put back.
    Package running = npc.GetCurrentPackage()
    If travelPkg && running != None && running != travelPkg && ActorUtil.CountPackageOverride(npc) > 1 \
        && npc.GetDialogueTarget() == None && !npc.IsInCombat()
        If running != TravelPackage_Walk && running != TravelPackage_Jog && running != TravelPackage_Run \
            && running != TravelPackage_Stalk && running != SandboxPackage && running != SandboxNearPlayerPackage
            DebugMsg(npc.GetDisplayName() + " is held by a package that is not ours -> other overrides cleared, travel package put back")
            ActorUtil.ClearPackageOverride(npc)
            ActorUtil.AddPackageOverride(npc, travelPkg, PRIORITY_TRAVEL, 1)
            npc.EvaluatePackage()
            Return
        EndIf
    EndIf
    If PlayerCanSee(npc)
        If travelPkg
            ActorUtil.RemovePackageOverride(npc, travelPkg)
            ActorUtil.AddPackageOverride(npc, travelPkg, PRIORITY_TRAVEL, 1)
        EndIf
        npc.EvaluatePackage()
        Return
    EndIf
    Float nudge = 100.0
    If !npc.Is3DLoaded()
        nudge = 200.0
    EndIf
    npc.MoveTo(npc, Utility.RandomFloat(-nudge, nudge), Utility.RandomFloat(-nudge, nudge), 50.0, false)
    If slot >= 0 && !SlotHolds(slot, npc)
        Return                    ; cancelled or replaced while the move was made: nothing of ours to put back
    EndIf

    If travelPkg
        ActorUtil.AddPackageOverride(npc, travelPkg, PRIORITY_TRAVEL, 1)
    EndIf
    npc.EvaluatePackage()

    If dest != None
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
    ; Indoors, "a good way behind the player" is on the far side of a wall or outside the building's shell:
    ; the NPC dropped through the void or stood sealed in, with the task still running. Anything farther
    ; than a few steps puts them at a door of the cell instead, as if they had just come in.
    If distance > 500.0 && player.IsInInterior()
        ObjectReference wayIn = WayIntoPlayerCell()
        If wayIn != None
            npc.MoveTo(wayIn)
            DebugMsg(npc.GetDisplayName() + " placed at a door of the player's cell (indoors, instead of " + distance + " units behind)")
            Return
        EndIf
        distance = 300.0
    EndIf
    Float[] offset = IntelEngine.GetOffsetBehind(player, distance)
    npc.MoveTo(player, offset[0], offset[1], 0.0, false)
    DebugMsg(npc.GetDisplayName() + " teleported behind player at " + distance + " units")
EndFunction

ObjectReference Function WayIntoPlayerCell()
    {A door of the interior the player is in, to make an NPC appear as if they had walked in: the door to
    the outside if there is one, else any door.}
    ObjectReference[] doors = IntelEngine.GetCellDoors(Game.GetPlayer())
    ObjectReference wayIn = None
    Int d = 0
    While d < doors.Length
        If doors[d] != None && (wayIn == None || IntelEngine.IsDoorExterior(doors[d]))
            wayIn = doors[d]
        EndIf
        d += 1
    EndWhile
    Return wayIn
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
        DebugMsg(agent.GetDisplayName() + " hasn't departed - nudging package evaluation")
        agent.EvaluatePackage()

        ; No PathToReference here any more: it is a forced run at full speed whatever the task's pace, it
        ; held this monitoring pass (and every other slot in it) until the NPC got there, and it kept the NPC
        ; running after the task had been called off.
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
                        DebugMsg("No saved deadline for slot " + i + " - set fallback 6h from now")
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
    Called after RecoverActiveTasks (legacy StorageUtil path) to re-sync on game load.}
    Int i = 0
    While i < MAX_SLOTS
        If SlotStates[i] != 0
            ReferenceAlias slotAlias = GetAgentAlias(i)
            If slotAlias
                Actor agent = slotAlias.GetActorReference()
                If agent
                    IntelEngine.UpdateSlotState(i, agent, SlotStates[i], SlotTaskTypes[i], SlotTargetNames[i], StorageUtil.GetStringValue(agent, "Intel_TaskOrigin"), StorageUtil.GetFloatValue(agent, "Intel_TaskAllocatedAt", -1.0), StorageUtil.GetStringValue(agent, "Intel_TaskReason"))
                    IntelEngine.SetSlotSpeed(i, SlotSpeeds[i])
                    IntelEngine.SetSlotDeadline(i, SlotDeadlines[i])
                EndIf
            EndIf
        Else
            IntelEngine.ClearSlotState(i)
        EndIf
        i += 1
    EndWhile
    DebugMsg("C++ SlotTracker synced from Papyrus arrays")
EndFunction

Function SyncTaskMetadataToSlotTracker()
    Int i = 0
    While i < MAX_SLOTS
        If SlotStates[i] != 0
            ReferenceAlias slotAlias = GetAgentAlias(i)
            If slotAlias
                Actor agent = slotAlias.GetActorReference()
                If agent
                    IntelEngine.UpdateSlotState(i, agent, SlotStates[i], SlotTaskTypes[i], SlotTargetNames[i], StorageUtil.GetStringValue(agent, "Intel_TaskOrigin"), StorageUtil.GetFloatValue(agent, "Intel_TaskAllocatedAt", -1.0), StorageUtil.GetStringValue(agent, "Intel_TaskReason"))
                EndIf
            EndIf
        EndIf
        i += 1
    EndWhile
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

Function RegisterStoryEventSchemas()
    String fields = "[{\"name\":\"line\",\"type\":0,\"required\":true,\"description\":\"Event content\"}]"
    String templates = "{\"recent_events\":\"*{{ line }}* ({{ time_desc }})\",\"raw\":\"*{{ line }}*\",\"compact\":\"*{{ line }}*\",\"verbose\":\"*{{ line }}*\"}"
    SkyrimNetApi.RegisterEventSchema("intel_social", "Intel Social", \
        "Executed NPC social interactions and gossip exchanges", fields, templates, false, 120000, true, false)
    SkyrimNetApi.RegisterEventSchema("intel_story", "Intel Story", \
        "Executed story, seek, and informant outcomes", fields, templates, false, 120000, true, false)
EndFunction

Function SendStoryEvent(String eventType, Actor akOriginator, Actor akTarget, String eventLine)
    If eventLine == ""
        Return
    EndIf
    SkyrimNetApi.RegisterEvent(eventType, "{\"line\":\"" + EscapeJson(eventLine) + "\"}", akOriginator, akTarget)
EndFunction

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
    StorageUtil.SetStringValue(akNPC, "Intel_FactsRendered", IntelEngine.EncodeRenderedCache(rendered))

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
    StorageUtil.SetStringValue(akReceiver, "Intel_GossipRendered", IntelEngine.EncodeRenderedCache(heardRendered + recvToldRendered))

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
    StorageUtil.SetStringValue(akGiver, "Intel_GossipRendered", IntelEngine.EncodeRenderedCache(giverHeardRendered + giverToldRendered))

    DebugMsg("Gossip: " + giverName + " told " + receiverName + ": " + gossipText)
    SendStoryEvent("intel_social", akGiver, akReceiver, giverName + " told " + receiverName + " a rumor: " + gossipText)
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
            ; Keep the timers: linger release, quest expiry and the other systems run on them. Only the
            ; story DM is gated by the switch.
            StoryEngine.StartScheduler()
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
    ; Minimum 300 — sandbox radius is 200 units, so anything less causes
    ; false releases when the NPC walks to a sandbox idle point.
    If val < 300.0
        val = 300.0
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
    ; Location markers are outdoor points: for an NPC held up inside a building the search compared interior
    ; coordinates with exterior markers and could pick, and then teleport to, an unrelated place.
    If npc.IsInInterior()
        Return false
    EndIf

    ObjectReference waypoint = IntelEngine.FindNearestWaypointToward(npc, dest, 5000.0)
    If waypoint == None
        Return false
    EndIf

    ObjectReference currentWP = StorageUtil.GetFormValue(npc, \
        "Intel_CurrentWaypoint") as ObjectReference

    If currentWP == waypoint && PlayerCanSee(npc)
        ; Still stuck on the way to the waypoint, with the player looking: no teleport now. The package is
        ; refreshed and the hop waits until they look away.
        SoftStuckRecovery(npc, slot, dest)
        Return true
    ElseIf currentWP == waypoint
        ; Already tried walking to this waypoint and still stuck —
        ; teleport to it (short hop to known-good navmesh position)
        DebugMsg(npc.GetDisplayName() + " stuck at waypoint - teleporting to it")
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

    If !SlotHolds(slot, npc)
        Return true               ; cancelled or replaced during the move
    EndIf
    Package travelPkg = TravelPackageOn(npc, GetTravelPackage(SlotSpeeds[slot]))
    If travelPkg
        ActorUtil.AddPackageOverride(npc, travelPkg, PRIORITY_TRAVEL, 1)
    EndIf
    npc.EvaluatePackage()
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

    ; This is what a player reaches for when an NPC is stuck, and clearing the task slots did nothing for an
    ; NPC that no slot knew about any more. Every IntelEngine package that nothing accounts for comes off
    ; now, without the hourly sweep's two-sightings rule. (A running story keeps its NPCs: it has its own cancel.)
    SweepStalePackages(true)

    NotifyPlayer("IntelEngine: All tasks reset")
EndFunction

; ===== CHOICE POPUP (Magelight page, SkyMessage fallback) =====
; Page: Data/Magelight/IntelEngineChoice/choice/. Not modId "IntelEngine": the C++ dashboard owns it and Magelight refuses a script RegisterMod of it.

String _mlRequest = ""
String _mlResult = ""
Int _mlView = 0
Int _mlCount = 0
Bool _mlTimed = False
Bool _mlDomReady = False
Bool _mlEntered = False

; Returns the clicked button label (like SkyMessage.Show), or "TIMED_OUT".
; Magelight page when available; otherwise (or if it fails before the player saw it) SkyMessage with the same buttons.
String Function ShowChoice(String asTitle, String asKind, String asBody, String asB1, String asB2, String asB3 = "", Float afTimeoutSecs = 0.0)
    Int n = 2
    If asB3 != ""
        n = 3
    EndIf
    String code = ShowMagelightChoice(asTitle, asKind, asBody, asB1, asB2, asB3, n, afTimeoutSecs)
    String r = ""
    String path = "magelight"
    If code == ""
        path = "fallback"
        ; No time limit on the classic box: it cannot take itself off the screen, so after a timeout it stayed
        ; up with buttons that no longer did anything. It waits for the player instead.
        r = SkyMessage.Show(asBody, asB1, asB2, asB3)
    ElseIf code == "t"
        r = "TIMED_OUT"
    ElseIf code == "0"
        r = asB1
    ElseIf code == "1"
        r = asB2
    Else
        r = asB3
    EndIf
    DebugMsg("ShowChoice (" + path + "): '" + asKind + "' -> " + r)
    Return r
EndFunction

; Returns "0".."2" (button index), "t" (timer ran out) or "" (Magelight unusable before the player saw it).
String Function ShowMagelightChoice(String asTitle, String asKind, String asBody, String asB1, String asB2, String asB3, Int aiCount, Float afTimeoutSecs)
    If SKSE.GetPluginVersion("Magelight") <= 0 || Magelight.GetVersion() == 0
        Return ""
    EndIf
    String token = "r" + Utility.RandomInt(1, 2147483647)
    ; Wait our turn instead of falling back: another IE choice is open, or any Magelight window
    ; (e.g. the IE dashboard) holds UI mode. No external call between the check and the claim.
    ; Both waits are bounded: a request left behind by an interrupted popup, or a window somebody keeps open,
    ; must not hold every later prompt (and the task behind it) for ever. After two minutes the message box is used.
    Float waitedForTurn = 0.0
    While _mlRequest != "" && waitedForTurn < 120.0
        Utility.WaitMenuMode(0.25)
        waitedForTurn += 0.25
    EndWhile
    If _mlRequest != ""
        DebugMsg("ShowChoice: an earlier popup is still open -> message box")
        Return ""
    EndIf
    _mlRequest = token
    While Magelight.IsReady() && Magelight.IsUIModeActive() && waitedForTurn < 120.0
        Utility.WaitMenuMode(0.25)
        waitedForTurn += 0.25
    EndWhile
    If Magelight.IsReady() && Magelight.IsUIModeActive()
        Return EndML(token, "")
    EndIf
    If !Magelight.IsReady()
        Return EndML(token, "")
    EndIf
    _mlResult = ""
    _mlCount = aiCount
    _mlTimed = afTimeoutSecs > 0.0
    _mlDomReady = False
    _mlEntered = False
    RegisterForModEvent("Magelight_ViewDomReady", "OnMLDomReady")
    RegisterForModEvent("Magelight_UIModeEntered", "OnMLEntered")
    RegisterForModEvent("Magelight_JS_ieChoice", "OnMLChoice")
    RegisterForModEvent("Magelight_UIModeExited", "OnMLFailure")
    ; RequestUIMode only queues the entry; a lost race is reported with this event. Without it the popup
    ; sat on screen, dead, for the five seconds of the wait below before the message box came.
    RegisterForModEvent("Magelight_UIModeRefused", "OnMLFailure")
    RegisterForModEvent("Magelight_ViewLoadFailed", "OnMLFailure")
    RegisterForModEvent("Magelight_ViewDestroyed", "OnMLFailure")
    RegisterForModEvent("Magelight_RenderDead", "OnMLFailure")

    If !Magelight.RegisterMod("IntelEngineChoice", "IntelEngine")
        Return EndML(token, "")
    EndIf
    _mlView = Magelight.FindView("IntelEngineChoice", "choice")
    If _mlView == 0
        _mlView = Magelight.CreateView("IntelEngineChoice", "choice", "choice/index.html", 0, 0, 0, 0, "popup")
        If _mlView == 0
            Return EndML(token, "")
        EndIf
        Float domDeadline = Utility.GetCurrentRealTime() + 10.0
        While _mlRequest == token && _mlResult == "" && !_mlDomReady && Utility.GetCurrentRealTime() < domDeadline
            Utility.WaitMenuMode(0.1)
        EndWhile
        If !_mlDomReady || _mlResult == "F"
            ; The page did not load (file missing or broken). The view is thrown away: kept, the next prompt
            ; found it, skipped this check and paused the game on a blank page.
            Magelight.DestroyView(_mlView)
            _mlView = 0
            Return EndML(token, "")
        EndIf
    EndIf
    If !Magelight.RegisterListener(_mlView, "ieChoice")
        Return EndML(token, "")
    EndIf
    ; The page answers to keys; with this a pad answers too (kept by the host across reloads, harmless to repeat).
    Int padKeys = IntelEngine.EnableMagelightGamepadKeys(_mlView)
    If padKeys != 1
        DebugMsg("ShowChoice: no pad for the popup (" + padKeys + ": 0 = no gamepad layer, -1 = refused)")
    EndIf

    String buttons = "\"" + EscapeJson(asB1) + "\",\"" + EscapeJson(asB2) + "\""
    If aiCount > 2
        buttons += ",\"" + EscapeJson(asB3) + "\""
    EndIf
    Int timeoutMs = (afTimeoutSecs * 1000.0) as Int
    Magelight.Call(_mlView, "ieChoiceShow", "{\"token\":\"" + token + "\",\"title\":\"" + EscapeJson(asTitle) + "\",\"kind\":\"" + EscapeJson(asKind) + "\",\"body\":\"" + EscapeJson(asBody) + "\",\"buttons\":[" + buttons + "],\"timeoutMs\":" + timeoutMs + "}")
    Magelight.ShowView(_mlView, True)
    If !Magelight.RequestUIMode(_mlView, True)          ; True = pause the game, like the message box
        Return EndML(token, "")
    EndIf
    Float enterDeadline = Utility.GetCurrentRealTime() + 5.0
    While _mlRequest == token && _mlResult == "" && !_mlEntered && Utility.GetCurrentRealTime() < enterDeadline
        Utility.WaitMenuMode(0.1)
    EndWhile
    If _mlResult == "F" || (!_mlEntered && _mlResult == "")
        Return EndML(token, "")
    EndIf

    ; The page owns the timer; this only fires if the page dies silently.
    Float hardDeadline = 0.0
    If _mlTimed
        hardDeadline = Utility.GetCurrentRealTime() + afTimeoutSecs + 3.0
    EndIf
    While _mlRequest == token && _mlResult == ""
        Utility.WaitMenuMode(0.1)
        If _mlResult == "" && (!Magelight.IsReady() || !Magelight.IsUIModeActive() || Magelight.GetUIModeView() != _mlView)
            _mlResult = (aiCount - 1) as String           ; closed (PageUp, host loss): the caller's do-nothing answer
        ElseIf _mlResult == "" && hardDeadline > 0.0 && Utility.GetCurrentRealTime() > hardDeadline
            _mlResult = "t"
        EndIf
    EndWhile
    Return EndML(token, _mlResult)
EndFunction

String Function EndML(String token, String result)
    If _mlRequest != token
        Return result
    EndIf
    If _mlView != 0
        If Magelight.IsUIModeActive() && Magelight.GetUIModeView() == _mlView
            Magelight.ReleaseUIMode("IntelEngineChoice")
        EndIf
        Magelight.ShowView(_mlView, False)
    EndIf
    _mlRequest = ""
    Return result
EndFunction

Event OnMLDomReady(String eventName, String strArg, Float numArg, Form sender)
    If _mlRequest != "" && strArg == "IntelEngineChoice" && numArg as Int == _mlView
        _mlDomReady = True
    EndIf
EndEvent

Event OnMLEntered(String eventName, String strArg, Float numArg, Form sender)
    ; strArg may be "IntelEngineChoice|switched"
    If _mlRequest != "" && numArg as Int == _mlView && StringUtil.Substring(strArg, 0, 17) == "IntelEngineChoice"
        _mlEntered = True
    ElseIf _mlRequest == "" && _mlView != 0 && numArg as Int == _mlView && StringUtil.Substring(strArg, 0, 17) == "IntelEngineChoice"
        ; The entry was queued but came after we stopped waiting for it (the message box has been used
        ; instead). Nobody would release it: the game stayed paused on a hidden page until Page Up.
        Magelight.ReleaseUIMode("IntelEngineChoice")
        Magelight.ShowView(_mlView, False)
    EndIf
EndEvent

Event OnMLChoice(String eventName, String strArg, Float numArg, Form sender)
    If _mlRequest == "" || _mlResult != "" || numArg as Int != _mlView
        Return
    EndIf
    String prefix = _mlRequest + "|"
    If StringUtil.Substring(strArg, 0, StringUtil.GetLength(prefix)) != prefix
        Return
    EndIf
    String tail = StringUtil.Substring(strArg, StringUtil.GetLength(prefix))
    If tail == "t" && _mlTimed
        _mlResult = "t"
    ElseIf (tail == "0" || tail == "1" || tail == "2") && (tail as Int) < _mlCount
        _mlResult = tail
    EndIf
EndEvent

Event OnMLFailure(String eventName, String strArg, Float numArg, Form sender)
    If _mlRequest == "" || _mlResult != "" || (numArg as Int != _mlView && eventName != "Magelight_RenderDead")
        Return
    EndIf
    If _mlEntered
        _mlResult = (_mlCount - 1) as String   ; seen and closed: the caller's do-nothing answer
    ElseIf eventName != "Magelight_UIModeExited"   ; an exit before entry may be the previous holder's
        _mlResult = "F"                            ; failed before the player saw it: fall back
    EndIf
EndEvent

; =============================================================================
; DASHBOARD STATE & EVENTS
; =============================================================================

Function RegisterDashboardEvents()
    RegisterForModEvent("IntelEngine_DashboardOpened", "OnDashboardOpened")
    RegisterForModEvent("IntelEngine_DashboardRefresh", "OnDashboardRefresh")
    RegisterForModEvent("IntelEngine_DashboardCancelTask", "OnDashboardCancelTask")
    RegisterForModEvent("IntelEngine_DashboardCancelQuest", "OnDashboardCancelQuest")
    RegisterForModEvent("IntelEngine_DashboardCancelSchedule", "OnDashboardCancelSchedule")
    RegisterForModEvent("IntelEngine_DashboardToggleStory", "OnDashboardToggleStory")
    RegisterForModEvent("IntelEngine_DashboardSetting", "OnDashboardSetting")
    RegisterForModEvent("IntelEngine_DashboardRemovePackages", "OnDashboardRemovePackages")
    RegisterForModEvent("IntelEngine_DashboardDispatchStory", "OnDashboardDispatchStory")
    RegisterForModEvent("IntelEngine_DashboardDispatchNpcSocial", "OnDashboardDispatchNpcSocial")
    RegisterForModEvent("IntelEngine_DashboardDispatchPolitics", "OnDashboardDispatchPolitics")
    RegisterForModEvent("IntelEngine_DashboardExecuteAction", "OnDashboardExecuteAction")
    RegisterForModEvent("IntelEngine_AutoBioUpdate", "OnAutoBioUpdate")
    RegisterForModEvent("IntelEngine_SaveBioCount", "OnSaveBioCount")
    RegisterForModEvent("SkyrimNet_OnPluginConfigSaved", "OnSkyrimNetPluginConfigSaved")
    DebugMsg("Dashboard ModEvent listeners registered")
EndFunction

Event OnSaveBioCount(String eventName, String strArg, Float numArg, Form sender)
    ; sender = Actor, strArg = count as string
    Actor npc = sender as Actor
    If npc == None || StoryEngine == None
        return
    EndIf
    Int count = strArg as Int
    StorageUtil.SetIntValue(npc, "Intel_BioLineCount", count)
    If !StorageUtil.FormListHas(StoryEngine, "Intel_BioTrackActors", npc)
        StorageUtil.FormListAdd(StoryEngine, "Intel_BioTrackActors", npc)
    EndIf
EndEvent

Event OnAutoBioUpdate(String eventName, String strArg, Float numArg, Form sender)
    ; sender = Actor — no FormID encoding needed, works for all actors including mod-added
    Actor npc = sender as Actor
    If npc == None
        DebugMsg("Auto Bio Update: sender is not a valid actor")
        return
    EndIf
    ; Persist the reset (C++ already reset to 0, mirror in StorageUtil)
    StorageUtil.SetIntValue(npc, "Intel_BioLineCount", 0)
    DebugMsg("Auto Bio Update: " + npc.GetDisplayName())
    String result = SkyrimNetApi.UpdateActorDynamicBio(npc)
    If result != ""
        DebugMsg("Auto Bio Update: " + npc.GetDisplayName() + " - " + result)
    Else
        DebugMsg("Auto Bio Update: " + npc.GetDisplayName() + " - failed or no changes")
    EndIf
EndEvent

Event OnDashboardOpened(String eventName, String strArg, Float numArg, Form sender)
    PushDashboardState()
EndEvent

Event OnDashboardRefresh(String eventName, String strArg, Float numArg, Form sender)
    PushDashboardState()
EndEvent

Event OnSkyrimNetPluginConfigSaved(String eventName, String strArg, Float numArg, Form sender)
    If strArg == "IntelEngine"
        IntelEngine.ReloadDashboardConfig()
    EndIf
EndEvent

Event OnDashboardCancelTask(String eventName, String strArg, Float numArg, Form sender)
    Int slot = numArg as Int
    If slot >= 0 && slot < MAX_SLOTS
        Actor agent = GetAgentAlias(slot).GetActorReference()
        If agent != None && CancelCurrentTask(agent, true)
            DebugMsg("Dashboard: Cancelling task in slot " + slot + " for " + agent.GetDisplayName())
            NotifyPlayer(agent.GetDisplayName() + "'s task cancelled.")
            PushDashboardState()
        EndIf
    EndIf
EndEvent

Event OnDashboardCancelQuest(String eventName, String strArg, Float numArg, Form sender)
    If StoryEngine != None && StoryEngine.QuestActive
        DebugMsg("Dashboard: Cancelling active quest")
        Actor courier = StoryEngine.ActiveStoryNPC
        If courier != None
            Int courierSlot = FindSlotByAgent(courier)
            If courierSlot >= 0
                ClearSlotRestoreFollower(courierSlot, courier)
            EndIf
        EndIf
        StoryEngine.CleanupQuest()
        StoryEngine.CleanupStoryDispatch()
        PushDashboardState()
    EndIf
EndEvent

Event OnDashboardRemovePackages(String eventName, String strArg, Float numArg, Form sender)
    Int formId = IntelEngine.ParseFormID(strArg)
    If formId == 0
        Return
    EndIf
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
    ElseIf strArg == "skipFollowerGoToLocation"
        If StoryEngine
            StoryEngine.SkipFollowerGoToLocation = numArg > 0.5
        EndIf
    ElseIf strArg == "skipFollowerDeliverMessage"
        If StoryEngine
            StoryEngine.SkipFollowerDeliverMessage = numArg > 0.5
        EndIf
    ElseIf strArg == "skipFollowerFetchPerson"
        If StoryEngine
            StoryEngine.SkipFollowerFetchPerson = numArg > 0.5
        EndIf
    ElseIf strArg == "skipFollowerEscortTarget"
        If StoryEngine
            StoryEngine.SkipFollowerEscortTarget = numArg > 0.5
        EndIf
    ElseIf strArg == "skipFollowerSearchForActor"
        If StoryEngine
            StoryEngine.SkipFollowerSearchForActor = numArg > 0.5
        EndIf
    ElseIf strArg == "skipFollowerScheduleFetch"
        If StoryEngine
            StoryEngine.SkipFollowerScheduleFetch = numArg > 0.5
        EndIf
    ElseIf strArg == "skipFollowerScheduleDelivery"
        If StoryEngine
            StoryEngine.SkipFollowerScheduleDelivery = numArg > 0.5
        EndIf
    ElseIf strArg == "skipFollowerScheduleMeeting"
        If StoryEngine
            StoryEngine.SkipFollowerScheduleMeeting = numArg > 0.5
        EndIf
    ElseIf strArg == "autoBioEnabled"
        If StoryEngine
            StoryEngine.AutoBioEnabled = numArg > 0.5
            IntelEngine.SetAutoBioEnabled(numArg > 0.5)
        EndIf
    ElseIf strArg == "autoBioThreshold"
        If StoryEngine
            StoryEngine.AutoBioThreshold = numArg as Int
            IntelEngine.SetAutoBioThreshold(numArg as Int)
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

Bool Function DirectorCanDispatch(Actor npc, Bool storyDispatch = false, Actor replacing = None)
    ; Include aliases retained during task completion, not just nonzero slot states.
    Int slot = 0
    While slot < MAX_SLOTS
        ReferenceAlias taskAlias = GetAgentAlias(slot)
        If taskAlias && taskAlias.GetActorReference() == npc && npc != replacing
            NotifyPlayer(npc.GetDisplayName() + " is already busy (" + IntelEngine.FriendlyKey(SlotTaskTypes[slot]) + "). Cancel it first.")
            Return false
        EndIf
        slot += 1
    EndWhile
    ; Also while an arrival is being handled (IsActive is already false then, the NPC still held): a dispatch
    ; from the dashboard in that moment started a second story on top of the one being finished.
    If storyDispatch && StoryEngine && (StoryEngine.IsActive || StoryEngine.ArrivalHandling) && (!replacing || StoryEngine.ActiveStoryNPC != replacing)
        Actor activeNPC = StoryEngine.ActiveStoryNPC
        String activeName = "an unknown NPC"
        If activeNPC
            activeName = activeNPC.GetDisplayName()
        EndIf
        NotifyPlayer("Story engine is busy with " + activeName + " (" + IntelEngine.FriendlyKey(StoryEngine.ActiveStoryType) + "). Cancel it first.")
        Return false
    EndIf
    Return true
EndFunction

; =============================================================================
; DIRECTOR MODE: Story Dispatch
; =============================================================================
String Function UntagName(String name)
    Int tagAt = StringUtil.Find(name, " [")
    If tagAt > 0
        Return StringUtil.Substring(name, 0, tagAt)
    EndIf
    Return name
EndFunction

String Function ReplaceText(String text, String what, String with)
    ; Whole-word, case-insensitive: "Ria" must not hit "Riften" or "Victoria".
    String result = ""
    Int len = StringUtil.GetLength(what)
    Int total = StringUtil.GetLength(text)
    Int copied = 0
    Int at = StringUtil.Find(text, what)
    While at >= 0 && len > 0
        Int rest = at + len
        If (at == 0 || !StringUtil.IsLetter(StringUtil.GetNthChar(text, at - 1))) && (rest >= total || !StringUtil.IsLetter(StringUtil.GetNthChar(text, rest)))
            If at > copied
                result += StringUtil.Substring(text, copied, at - copied)
            EndIf
            result += with
            copied = rest
        EndIf
        at = StringUtil.Find(text, what, at + 1)
    EndWhile
    If copied < total
        result += StringUtil.Substring(text, copied)
    EndIf
    Return result
EndFunction

String Function InformantRumor(String subject, String rumor, String gossip)
    {The checked rumor sentence. Legacy responses without "rumor" get subject + gossip phrase.}
    If rumor != "" || gossip == ""
        Return rumor
    EndIf
    ; Not without a subject: the gossip then began with a blank ("told X a rumor:  heard ..."), in the line
    ; and in what both NPCs remember (the repository's own typed-event check has failed on this since fix 84).
    If subject != "" && ReplaceText(gossip, UntagName(subject), "") == gossip ; fix96: whole-word, "Ria" is not in "Victoria" (live 17:27)
        gossip = subject + " " + gossip
    EndIf
    Return gossip
EndFunction

String Function DropLead(String text, String lead)
    ; Papyrus Find is case-insensitive.
    If StringUtil.Find(text, lead) == 0
        Return StringUtil.Substring(text, StringUtil.GetLength(lead))
    EndIf
    Return text
EndFunction

String Function InformantLead(String informant, String rumor, Bool wantSender)
    {Rumors are the gossip itself. Drops a leading "<informant> heard/overheard/saw/was told/learned that" and a
    trailing period. wantSender=false: the cleaned rumor; true: Y of "<informant> heard from Y that", else "".}
    String name = UntagName(informant) + " "
    Int sp = StringUtil.Find(name, " ")
    If StringUtil.Find(rumor, name) != 0 && sp < StringUtil.GetLength(name) - 1 ; first-name-only lead
        name = StringUtil.Substring(name, 0, sp + 1)
    EndIf
    String rest = rumor
    String teller = ""
    If StringUtil.Find(rumor, name) == 0
        rest = StringUtil.Substring(rumor, StringUtil.GetLength(name))
        String afterName = rest
        If StringUtil.Find(rest, "heard from ") == 0
            Int at = StringUtil.Find(rest, " that ")
            If at > 11
                teller = StringUtil.Substring(rest, 11, at - 11)
                rest = StringUtil.Substring(rest, at + 6)
            EndIf
        Else
            rest = DropLead(DropLead(DropLead(DropLead(DropLead(rest, "overheard that "), "heard that "), "saw that "), "was told that "), "learned that ")
        EndIf
        If rest == "" || rest == afterName ; no lead phrase matched: the name is part of the gossip
            rest = rumor
        EndIf
    EndIf
    Int last = StringUtil.GetLength(rest) - 1
    If last > 0 && StringUtil.GetNthChar(rest, last) == "."
        rest = StringUtil.Substring(rest, 0, last)
    EndIf
    If wantSender
        Return teller
    EndIf
    Return rest
EndFunction

String Function InformantRejection(String subject, String rumor)
    {Same checks as C++ InformantRumorRejection; "" = accepted.}
    String name = UntagName(subject)
    If rumor == ""
        Return "rumor is empty"
    ElseIf name == ""
        Return "subject is empty"
    ElseIf ReplaceText(rumor, name, "") == rumor ; whole-word, like the C++ check
        Return "rumor does not name the subject"
    EndIf
    Int sp = 0 ; first word ends at " ,.;:" like the C++ check
    While sp < StringUtil.GetLength(rumor) && StringUtil.Find(" ,.;:", StringUtil.GetNthChar(rumor, sp)) < 0
        sp += 1
    EndWhile
    String first = StringUtil.Substring(rumor, 0, sp)
    ; Ordinary openings that happen to end in "ing" pass (same list as the C++ check): the rule is for
    ; "Hearing that ...", and it also refused "During the feast, Nazeem ..." and "King Torygg ...".
    If sp > 3 && StringUtil.Substring(first, sp - 3) == "ing" && StringUtil.Find(name, first) != 0 \
        && StringUtil.Find("|during|something|nothing|anything|everything|king|morning|evening|spring|", "|" + first + "|") < 0
        Return "rumor starts with an -ing word"
    EndIf
    Return ""
EndFunction

String Function FormatInformantFact(String subject, String rumor, String sender, String informant)
    ; The informant's own name inside the rumor becomes "me"/"my"; a rumor about the informant themself is first person.
    String own = UntagName(informant) + " "
    If StringUtil.Find(rumor, own) == 0
        Return "I " + ReplaceText(ReplaceText(StringUtil.Substring(rumor, StringUtil.GetLength(own)), UntagName(informant) + "'s", "my"), UntagName(informant), "me")
    EndIf
    rumor = ReplaceText(ReplaceText(rumor, UntagName(informant) + "'s", "my"), UntagName(informant), "me")
    If sender == ""
        Return "saw that " + rumor
    ElseIf UntagName(sender) == UntagName(subject)
        Return sender + " told me that " + rumor
    EndIf
    Return "heard from " + sender + " that " + rumor
EndFunction

Function SetInformantTopic(Actor npc, String subject)
    {Short topic for Current Task ("speaking with X about <topic>"); none when the subject is empty or the informant; cleared by ReleaseLinger.}
    String subj = UntagName(subject)
    If subj == "" || subj == UntagName(npc.GetDisplayName())
        StorageUtil.UnsetStringValue(npc, "Intel_ArrivalTopic")
        Return
    EndIf
    StorageUtil.SetStringValue(npc, "Intel_ArrivalTopic", subj)
EndFunction

String Function InformantNarration(String npcName, String playerName, String sender, String rumor)
    If StringUtil.Find(rumor, UntagName(npcName) + " ") == 0
        Return npcName + " came to tell " + playerName + ": " + rumor
    EndIf
    If sender == ""
        Return npcName + " came to tell " + playerName + " what they saw: " + rumor
    EndIf
    Return npcName + " came to tell " + playerName + " what " + sender + " told them: " + rumor
EndFunction
Event OnDashboardDispatchStory(String eventName, String strArg, Float numArg, Form sender)
    ; strArg = full JSON payload (race-safe: no shared state between C++ and Papyrus)
    String storyType = IntelEngine.StoryResponseGetField(strArg, "storyType")
    String npcName = IntelEngine.StoryResponseGetField(strArg, "npcName")
    String narration = IntelEngine.StoryResponseGetField(strArg, "narration")
    String response = IntelEngine.StoryResponseGetField(strArg, "response")

    Actor npc = IntelEngine.ResolveDirectorActor(npcName)
    If !npc || npc.IsDead() || npc.IsDisabled()
        DebugMsg("Director: Could not find NPC '" + npcName + "' for story dispatch")
        NotifyPlayer(IntelEngine.GetDirectorFailureMessage(npcName))
        Return
    EndIf
    If narration == "" && storyType != "informant"
        DebugMsg("Director: Empty narration, aborting")
        NotifyPlayer("Story dispatch refused: narration is empty.")
        Return
    EndIf
    If !StoryEngine
        DebugMsg("Director: StoryEngine not available")
        NotifyPlayer("Story dispatch refused: StoryEngine is unavailable.")
        Return
    EndIf
    If storyType == "informant"
        String badSubject = StoryEngine.ExtractJsonField(response, "subject")
        String badWhy = InformantRejection(badSubject, InformantRumor(badSubject, StoryEngine.ExtractJsonField(response, "rumor"), StoryEngine.ExtractJsonField(response, "gossip")))
        If badWhy != ""
            DebugMsg("Director: informant refused (" + badWhy + "): subject='" + badSubject + "'")
            NotifyPlayer("Informant dispatch refused: " + badWhy + ".")
            Return
        EndIf
    EndIf
    Actor replacing = None
    If StoryEngine.IsActive && IntelEngine.StoryResponseGetField(strArg, "replaceGeneration") == StoryEngine.DispatchGeneration as String
        replacing = StoryEngine.ActiveStoryNPC
    EndIf
    If !DirectorCanDispatch(npc, true, replacing)
        Return
    EndIf
    If replacing
        If (storyType != "seek_player" && storyType != "informant" && storyType != "ambush" && storyType != "stalker" && storyType != "quest" && storyType != "message" && storyType != "road_encounter") || \
            (storyType == "message" && StoryEngine.ExtractJsonField(response, "msgContent") == "") || (storyType == "informant" && (StoryEngine.ExtractJsonField(response, "subject") == "" || InformantRumor(StoryEngine.ExtractJsonField(response, "subject"), StoryEngine.ExtractJsonField(response, "rumor"), StoryEngine.ExtractJsonField(response, "gossip")) == ""))
            NotifyPlayer("Story replacement refused: unknown type or missing message content / informant subject and gossip.")
            Return
        EndIf
        CancelCurrentTask(replacing, true)
        If StoryEngine.ActiveStoryNPC == replacing
            RemoveIntelPackages(replacing)
            ClearLinkedRefs(replacing)
            ClearSlotRestoreFollower(-1, replacing)
            StoryEngine.CleanupStoryDispatch()
        EndIf
        If StoryEngine.IsActive || FindSlotByAgent(replacing) >= 0
            NotifyPlayer("Story replacement refused: previous story or task is still active after cancellation.")
            Return
        EndIf
    EndIf

    DebugMsg("Director: Dispatching " + storyType + " with " + npc.GetDisplayName() + " - " + narration)


    ; Route through StoryEngine's actual type handlers (identical to automatic dispatch)
    ; Director skips cooldown/MCM checks intentionally — it's a manual DM override
    Int g = StoryEngine.DispatchGeneration
    If storyType == "seek_player"
        String seekFact = narration
        If StringUtil.Find(narration, Game.GetPlayer().GetDisplayName()) < 0
            seekFact = "set out to find " + Game.GetPlayer().GetDisplayName() + " -- " + narration
        EndIf
        InjectFact(npc, seekFact)
        StoryEngine.ActiveStoryType = storyType
        StoryEngine.DispatchToTarget(npc, Game.GetPlayer(), narration, "story", "Director")

    ElseIf storyType == "informant"
        String fSubject = StoryEngine.ExtractJsonField(response, "subject")
        String fRumor = InformantRumor(fSubject, StoryEngine.ExtractJsonField(response, "rumor"), StoryEngine.ExtractJsonField(response, "gossip"))
        String fSender = StoryEngine.ExtractJsonField(response, "sender")
        If fSubject != "" && fRumor != ""
            If fSender == ""
                fSender = InformantLead(npc.GetDisplayName(), fRumor, true)
            EndIf
            fRumor = InformantLead(npc.GetDisplayName(), fRumor, false)
            InjectFact(npc, FormatInformantFact(fSubject, fRumor, fSender, npc.GetDisplayName()))
            narration = InformantNarration(npc.GetDisplayName(), Game.GetPlayer().GetDisplayName(), fSender, fRumor)
        EndIf
        StoryEngine.ActiveStoryType = "informant"
        SetInformantTopic(npc, fSubject)
        StoryEngine.DispatchToTarget(npc, Game.GetPlayer(), narration, "story", "Director")

    ElseIf storyType == "ambush" || storyType == "stalker"
        StoryEngine.HandleAmbushStalkerDispatch(npc, narration, response, storyType, "Director")

    ElseIf storyType == "quest"
        StoryEngine.HandleQuestDispatch(npc, narration, response, true, "Director")

    ElseIf storyType == "message"
        StoryEngine.HandleMessageDispatch(npc, narration, response, "Director")

    ElseIf storyType == "road_encounter"
        InjectFact(npc, narration)
        StoryEngine.PlaceRoadEncounter(npc, narration, StoryEngine.ExtractJsonField(response, "destination"))

    Else
        DebugMsg("Director: unknown story type '" + storyType + "'")
    EndIf
    If StoryEngine.IsActive && StoryEngine.DispatchGeneration != g
        NotifyPlayer(StoryEngine.ActiveStoryNPC.GetDisplayName() + " sets out (" + IntelEngine.FriendlyKey(storyType) + ").")
    EndIf

    PushDashboardState()
EndEvent


; =============================================================================
; DIRECTOR MODE: NPC Social Dispatch
; =============================================================================
Event OnDashboardDispatchNpcSocial(String eventName, String strArg, Float numArg, Form sender)
    ; strArg = socialType (npc_interaction or npc_gossip)
    ; strArg = full JSON payload (race-safe: no shared state between C++ and Papyrus)
    String socialType = IntelEngine.StoryResponseGetField(strArg, "socialType")
    String npc1Name = IntelEngine.StoryResponseGetField(strArg, "npc1Name")
    String npc2Name = IntelEngine.StoryResponseGetField(strArg, "npc2Name")
    String narration = IntelEngine.StoryResponseGetField(strArg, "narration")
    String response = IntelEngine.StoryResponseGetField(strArg, "response")

    Actor npc1 = IntelEngine.ResolveDirectorActor(npc1Name)
    Actor npc2 = IntelEngine.ResolveDirectorActor(npc2Name)
    If !npc1 || npc1.IsDead() || npc1.IsDisabled()
        DebugMsg("Director: Could not find NPC 1 '" + npc1Name + "' for social dispatch")
        NotifyPlayer(IntelEngine.GetDirectorFailureMessage(npc1Name))
        Return
    EndIf
    If !npc2 || npc2.IsDead() || npc2.IsDisabled()
        DebugMsg("Director: Could not find NPC 2 '" + npc2Name + "' for social dispatch")
        NotifyPlayer(IntelEngine.GetDirectorFailureMessage(npc2Name))
        Return
    EndIf
    Actor replacing = None
    If StoryEngine && StoryEngine.IsNPCStoryActive && IntelEngine.StoryResponseGetField(strArg, "replaceGeneration") == StoryEngine.NPCSocialGeneration as String
        replacing = StoryEngine.NPCSocialTraveler
    EndIf
    If narration == "" || (socialType != "npc_interaction" && socialType != "npc_gossip") || npc1 == npc2 || !StoryEngine
        NotifyPlayer("Social dispatch refused: missing narration, invalid type, identical NPCs, or unavailable StoryEngine.")
        Return
    EndIf
    If !DirectorCanDispatch(npc1, false, replacing) || !DirectorCanDispatch(npc2, false, replacing)
        Return
    EndIf
    If StoryEngine.IsNPCStoryActive && !replacing
        NotifyPlayer("Social replacement refused: active trip changed; refresh and confirm replacement.")
        Return
    EndIf
    If replacing
        CancelCurrentTask(replacing, true)
        StoryEngine.CleanupNPCSocialDispatch()
        If StoryEngine.IsNPCStoryActive || FindSlotByAgent(replacing) >= 0
            NotifyPlayer("Social replacement refused: previous trip or task is still active after cancellation.")
            Return
        EndIf
    EndIf

    DebugMsg("Director: NPC Social " + socialType + " - " + npc1Name + " -> " + npc2Name + ": " + narration)

    String fact1 = ""
    String fact2 = ""
    String gossip = ""
    If socialType == "npc_interaction"
        fact1 = StoryEngine.ExtractJsonField(response, "fact1")
        fact2 = StoryEngine.ExtractJsonField(response, "fact2")
        String logDetail = ""
        If fact1 != ""
            logDetail = npc1Name + ": " + fact1
        EndIf
        If fact2 != ""
            If logDetail != ""
                logDetail += " | "
            EndIf
            logDetail += npc2Name + ": " + fact2
        EndIf
        StoryEngine.AddNPCSocialLog("npc_interaction", npc1Name, npc2Name, narration, npc1, logDetail)
        StoryEngine.AddRecentStoryEvent("npc_interaction: " + npc1Name + " and " + npc2Name + " - " + narration)
    ElseIf socialType == "npc_gossip"
        gossip = InformantRumor(StoryEngine.ExtractJsonField(response, "subject"), "", StoryEngine.ExtractJsonField(response, "gossip")) ; fix84: "<Subject> <gossip>"
        If gossip == ""
            StoryEngine.AddNPCSocialLog("npc_gossip", npc1Name, npc2Name, narration, npc1)
        Else
            StoryEngine.AddNPCSocialLog("npc_gossip", npc1Name, npc2Name, gossip, npc1) ; fix87: log the rumour
        EndIf
        StoryEngine.AddRecentStoryEvent("npc_gossip: " + npc1Name + " told " + npc2Name + " - " + narration)
    EndIf

    ; Dispatch physical travel for face-to-face when NPCs are close enough.
    Float dist = npc1.GetDistance(npc2)
    Bool ok = true
    If dist < 5000.0 && dist > 200.0
        ok = StoryEngine.DispatchNPCSocial(npc1, npc2, narration, socialType, npc1, npc2, fact1, fact2, gossip, "Director")
    Else
        ; fix 95c: loaded near the player, not same parent cell (outdoor grid cells split a few steps; live 16:55:11 dist=59 both cells False)
        If dist <= 200.0 && npc1.Is3DLoaded() && npc2.Is3DLoaded()
            ; fix 95: already together where the player is - play it there (in earshot) or hold until the player comes in range
            If StoryEngine.InNarrationRange(npc1)
                StoryEngine.PerformVisibleInteraction(npc1, npc2, narration, socialType)
                StoryEngine.CompleteNPCSocialOutcome(npc1, npc2, socialType, fact1, fact2, gossip)
            Else
                StoryEngine.HoldSocialScene(npc1, npc2, npc1, npc2, narration, socialType, fact1, fact2, gossip)
            EndIf
            DebugMsg("Director: NPCs already together near the player - scene played in place")
        Else
            ; Existing off-screen Director outcome: no travel is needed.
            StoryEngine.CompleteNPCSocialOutcome(npc1, npc2, socialType, fact1, fact2, gossip)
            DebugMsg("Director: NPCs too far apart or already close - applied off-screen (dist=" + dist + " npc1Loaded=" + npc1.Is3DLoaded() + " npc2Loaded=" + npc2.Is3DLoaded() + ")")
        EndIf
    EndIf
    If ok
        NotifyPlayer(npc1Name + " and " + npc2Name + ": " + IntelEngine.FriendlyKey(socialType) + " started.")
    EndIf

    PushDashboardState()
EndEvent

; =============================================================================
; DIRECTOR MODE: Political Event Dispatch
; =============================================================================
Event OnDashboardDispatchPolitics(String eventName, String strArg, Float numArg, Form sender)
    ; strArg = fake Political DM response JSON (built by C++ from UI fields)
    ; Feed it directly to ProcessPoliticalDMResponse — same path as a real DM response
    DebugMsg("Director: Political event received - eventName=" + eventName + " strArg length=" + StringUtil.GetLength(strArg))
    If Politics
        DebugMsg("Director: Forwarding to Politics.OnPoliticalDMResponse")
        ; Director bypasses manifestation cooldown — player is manually triggering events
        IntelEngine.ResetManifestationCooldown()
        If Politics.OnPoliticalDMResponse(strArg, 1)
            String eventLabel = IntelEngine.StoryResponseGetField(strArg, "event_label")
            If eventLabel == ""
                eventLabel = IntelEngine.FriendlyKey(IntelEngine.StoryResponseGetField(strArg, "event_type"))
            EndIf
            NotifyPlayer("Political event: " + eventLabel + " between " + IntelEngine.StoryResponseGetField(strArg, "faction_a_label") + " and " + IntelEngine.StoryResponseGetField(strArg, "faction_b_label") + ".")
        Else
            ; A refusal (a war the war_allowed setting does not permit, a surrender without a war, a repeat)
            ; showed nothing at all: the dashboard said "Sent" and cleared the form.
            NotifyPlayer("Political event refused: " + IntelEngine.FriendlyKey(IntelEngine.StoryResponseGetField(strArg, "event_type")) + " between " + IntelEngine.StoryResponseGetField(strArg, "faction_a_label") + " and " + IntelEngine.StoryResponseGetField(strArg, "faction_b_label") + ". The reason is in the IntelEngine log.")
        EndIf
        DebugMsg("Director: Politics.OnPoliticalDMResponse returned")
    Else
        DebugMsg("Director: Politics script not available (property is None)")
    EndIf
    PushDashboardState()
EndEvent

; =============================================================================
; DIRECTOR MODE: Action Execution
; =============================================================================
Event OnDashboardExecuteAction(String eventName, String strArg, Float numArg, Form sender)
    ; strArg = full JSON payload, including exact decimal npcFormId
    String actionName = IntelEngine.StoryResponseGetField(strArg, "actionName")
    String formIdString = IntelEngine.StoryResponseGetField(strArg, "npcFormId")
    Int formId = IntelEngine.ParseFormID(formIdString)
    If formId == 0
        Return
    EndIf
    Actor npc = Game.GetForm(formId) as Actor

    If !npc || npc.IsDead()
        DebugMsg("Director: Invalid or dead NPC for action execution")
        Return
    EndIf
    If actionName != "CancelCurrentTask" && actionName != "ChangeSpeed" && actionName != "ReportPlayerConduct" && \
        !DirectorCanDispatch(npc)
        Return
    EndIf

    DebugMsg("Director: Executing " + actionName + " on " + npc.GetDisplayName())
    String actionReason = IntelEngine.StoryResponseGetField(strArg, "reason")

    Bool ok = false
    Bool handled = false
    If actionName == "GoToLocation"
        String destination = IntelEngine.StoryResponseGetField(strArg, "destination")
        Int speed = IntelEngine.StoryResponseGetField(strArg, "speed") as Int
        Int waitFP = IntelEngine.StoryResponseGetField(strArg, "waitForPlayer") as Int
        ok = Travel.GoToLocation(npc, destination, speed, waitFP, false, "Director")

    ElseIf actionName == "FetchPerson"
        String targetName = IntelEngine.StoryResponseGetField(strArg, "targetName")
        String failReason = IntelEngine.StoryResponseGetField(strArg, "failReason")
        If failReason == ""
            failReason = "none"
        EndIf
        ok = NPCTasks.FetchNPC(npc, targetName, failReason, "Director")

    ElseIf actionName == "SearchForActor"
        String targetName = IntelEngine.StoryResponseGetField(strArg, "targetName")
        Int speed = IntelEngine.StoryResponseGetField(strArg, "speed") as Int
        ok = NPCTasks.SearchForActor(npc, targetName, speed, "Director")

    ElseIf actionName == "DeliverMessage"
        String targetName = IntelEngine.StoryResponseGetField(strArg, "targetName")
        String msgContent = IntelEngine.StoryResponseGetField(strArg, "msgContent")
        String meetLoc = IntelEngine.StoryResponseGetOptionalField(strArg, "meetLocation")
        String meetTime = IntelEngine.StoryResponseGetOptionalField(strArg, "meetTime")
        If meetLoc == ""
            meetLoc = "none"
        EndIf
        If meetTime == ""
            meetTime = "none"
        EndIf
        ok = NPCTasks.DeliverMessage(npc, targetName, msgContent, meetLoc, meetTime, "Director")

    ElseIf actionName == "ReportPlayerConduct"
        String factionId = IntelEngine.StoryResponseGetField(strArg, "factionId")
        String sentiment = IntelEngine.StoryResponseGetField(strArg, "sentiment")
        String reason = IntelEngine.StoryResponseGetField(strArg, "reason")
        ; Native shows its own feedback when it rejects the report.
        If Politics.ReportPlayerConduct(npc, factionId, sentiment, reason)
            InjectFact(npc, actionReason)
            NotifyPlayer(npc.GetDisplayName() + ": conduct reported.")
        EndIf
        handled = true

    ElseIf actionName == "EscortTarget"
        String targetName = IntelEngine.StoryResponseGetField(strArg, "targetName")
        String destination = IntelEngine.StoryResponseGetField(strArg, "destination")
        Int shouldWait = IntelEngine.StoryResponseGetField(strArg, "shouldWait") as Int
        If destination == ""
            destination = "home"
        EndIf
        ok = NPCTasks.EscortTarget(npc, targetName, destination, shouldWait, "Director")

    ElseIf actionName == "CancelCurrentTask"
        If CancelCurrentTask(npc, true)
            InjectFact(npc, actionReason)
            NotifyPlayer(npc.GetDisplayName() + "'s task was cancelled.")
        Else
            NotifyPlayer(npc.GetDisplayName() + " has no task to cancel.")
        EndIf
        handled = true

    ElseIf actionName == "ChangeSpeed"
        Int newSpeed = IntelEngine.StoryResponseGetField(strArg, "newSpeed") as Int
        ok = ChangeTaskSpeed(npc, newSpeed)

    ElseIf actionName == "ScheduleMeeting"
        String destination = IntelEngine.StoryResponseGetField(strArg, "destination")
        String timeCond = IntelEngine.StoryResponseGetField(strArg, "timeCondition")
        ok = Schedule.ScheduleMeeting(npc, destination, timeCond, "Director")

    ElseIf actionName == "ScheduleFetch"
        String targetName = IntelEngine.StoryResponseGetField(strArg, "targetName")
        String timeCond = IntelEngine.StoryResponseGetField(strArg, "timeCondition")
        ok = Schedule.ScheduleFetch(npc, targetName, timeCond, "Director")

    ElseIf actionName == "ScheduleDelivery"
        String targetName = IntelEngine.StoryResponseGetField(strArg, "targetName")
        String msgContent = IntelEngine.StoryResponseGetField(strArg, "msgContent")
        String timeCond = IntelEngine.StoryResponseGetField(strArg, "timeCondition")
        String meetLoc = IntelEngine.StoryResponseGetOptionalField(strArg, "meetLocation")
        String meetTime = IntelEngine.StoryResponseGetOptionalField(strArg, "meetTime")
        If meetLoc == ""
            meetLoc = "none"
        EndIf
        If meetTime == ""
            meetTime = "none"
        EndIf
        ok = Schedule.ScheduleDelivery(npc, targetName, msgContent, timeCond, meetLoc, meetTime, "Director")

    Else
        DebugMsg("Director: Unknown action " + actionName)
    EndIf
    If !handled
    If ok
        InjectFact(npc, actionReason)
        NotifyPlayer(npc.GetDisplayName() + ": " + actionName + " started.")
    Else
        NotifyPlayer(npc.GetDisplayName() + ": " + actionName + " failed.")
    EndIf
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
            json += ",\"origin\":\"" + EscapeJson(StorageUtil.GetStringValue(agent, "Intel_TaskOrigin")) + "\""
            Float allocatedAt = StorageUtil.GetFloatValue(agent, "Intel_TaskAllocatedAt", -1.0)
            If allocatedAt >= 0.0
                json += ",\"startTime\":" + allocatedAt
            EndIf
            String taskReason = StorageUtil.GetStringValue(agent, "Intel_TaskReason")
            If taskReason != ""
                json += ",\"reason\":\"" + EscapeJson(taskReason) + "\""
            EndIf
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
                Actor scheduledActor = Schedule.GetScheduleActor(i)
                json += "\"agent\":\"" + EscapeJson(schedAgent) + "\""
                json += ",\"destination\":\"" + EscapeJson(Schedule.GetScheduleDestination(i)) + "\""
                json += ",\"taskType\":\"" + Schedule.GetScheduleTaskType(i) + "\""
                json += ",\"targetName\":\"" + EscapeJson(Schedule.GetScheduleTargetName(i)) + "\""
                json += ",\"timeDesc\":\"" + EscapeJson(Schedule.GetScheduleDisplay(i)) + "\""
                json += ",\"schedStatus\":\"" + EscapeJson(Schedule.GetScheduleStatus(i)) + "\""
                If scheduledActor != None
                    json += ",\"origin\":\"" + EscapeJson(StorageUtil.GetStringValue(scheduledActor, "Intel_ScheduledOrigin", "Schedule")) + "\""
                    Float scheduledAt = StorageUtil.GetFloatValue(scheduledActor, "Intel_ScheduledStartTime", -1.0)
                    If scheduledAt >= 0.0
                        json += ",\"startTime\":" + scheduledAt
                    EndIf
                    String scheduledReason = StorageUtil.GetStringValue(scheduledActor, "Intel_ScheduledReason")
                    If scheduledReason != ""
                        json += ",\"reason\":\"" + EscapeJson(scheduledReason) + "\""
                    EndIf
                EndIf
                json += ",\"schedState\":" + Schedule.GetScheduleSlotState(i)
                ; The list skips empty slots, so the page needs the real slot number to cancel the right one.
                json += ",\"slot\":" + i
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
        json += ",\"generation\":" + StoryEngine.DispatchGeneration
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
        json += ",\"generation\":" + StoryEngine.NPCSocialGeneration
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
    Int logTimeCount = StorageUtil.FloatListCount(logPlayer, "Intel_SocialLog_Time")
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
        json += ",\"location\":\"" + EscapeJson(StorageUtil.StringListGet(logPlayer, "Intel_SocialLog_Location", li)) + "\""
        json += ",\"detail\":\"" + EscapeJson(StorageUtil.StringListGet(logPlayer, "Intel_SocialLog_Detail", li)) + "\""
        If li < logTimeCount
            Float socialTime = StorageUtil.FloatListGet(logPlayer, "Intel_SocialLog_Time", li)
            If socialTime >= 0.0
                json += ",\"time\":" + socialTime
            EndIf
        EndIf
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
        json += ",\"skipFollowerGoToLocation\":" + BoolToJson(StoryEngine.SkipFollowerGoToLocation)
        json += ",\"skipFollowerDeliverMessage\":" + BoolToJson(StoryEngine.SkipFollowerDeliverMessage)
        json += ",\"skipFollowerFetchPerson\":" + BoolToJson(StoryEngine.SkipFollowerFetchPerson)
        json += ",\"skipFollowerEscortTarget\":" + BoolToJson(StoryEngine.SkipFollowerEscortTarget)
        json += ",\"skipFollowerSearchForActor\":" + BoolToJson(StoryEngine.SkipFollowerSearchForActor)
        json += ",\"skipFollowerScheduleFetch\":" + BoolToJson(StoryEngine.SkipFollowerScheduleFetch)
        json += ",\"skipFollowerScheduleDelivery\":" + BoolToJson(StoryEngine.SkipFollowerScheduleDelivery)
        json += ",\"skipFollowerScheduleMeeting\":" + BoolToJson(StoryEngine.SkipFollowerScheduleMeeting)
        json += ",\"autoBioEnabled\":" + BoolToJson(StoryEngine.AutoBioEnabled)
        json += ",\"autoBioThreshold\":" + StoryEngine.AutoBioThreshold
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
        json += ",\"skipFollowerGoToLocation\":false,\"skipFollowerDeliverMessage\":false,\"skipFollowerFetchPerson\":false,\"skipFollowerEscortTarget\":false"
        json += ",\"skipFollowerSearchForActor\":false,\"skipFollowerScheduleFetch\":false,\"skipFollowerScheduleDelivery\":false,\"skipFollowerScheduleMeeting\":false"
        json += ",\"autoBioEnabled\":false,\"autoBioThreshold\":20"
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
