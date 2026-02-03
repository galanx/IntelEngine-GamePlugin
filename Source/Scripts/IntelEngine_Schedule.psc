Scriptname IntelEngine_Schedule extends Quest
{
    IntelEngine Scheduling System v1.0

    Handles time-based task scheduling:
    - "Meet me after sunset"
    - "Come to my room at dawn"
    - "Wait for me until midnight"

    NPCs wait until the scheduled time, then execute their task.
}

; =============================================================================
; PROPERTIES
; =============================================================================

IntelEngine_Core Property Core Auto
IntelEngine_Travel Property Travel Auto
IntelEngine_NPCTasks Property NPCTasks Auto

; =============================================================================
; CONSTANTS - Game Time Hours
; =============================================================================

Float Property HOUR_DAWN = 5.0 AutoReadOnly
Float Property HOUR_SUNRISE = 6.0 AutoReadOnly
Float Property HOUR_MORNING = 8.0 AutoReadOnly
Float Property HOUR_MIDDAY = 12.0 AutoReadOnly
Float Property HOUR_AFTERNOON = 14.0 AutoReadOnly
Float Property HOUR_EVENING = 18.0 AutoReadOnly
Float Property HOUR_SUNSET = 19.0 AutoReadOnly
Float Property HOUR_DUSK = 20.0 AutoReadOnly
Float Property HOUR_NIGHT = 22.0 AutoReadOnly
Float Property HOUR_MIDNIGHT = 0.0 AutoReadOnly

; How many hours before meeting time the NPC departs
; Gives pathfinding time to navigate across the map
Float Property DEPARTURE_BUFFER_HOURS = 2.0 AutoReadOnly

; =============================================================================
; SCHEDULED TASK TRACKING
; =============================================================================

; Separate from main slots - scheduled tasks wait before using a slot
Actor[] ScheduledAgents
String[] ScheduledDestinations
Float[] ScheduledTimes           ; When the NPC should be at the destination
String[] ScheduledTaskTypes
String[] ScheduledTargetNames    ; Target NPC name for fetch/deliver tasks
String[] ScheduledMessages       ; Message content for deliver tasks
String[] ScheduledMeetLocations  ; Meeting location for delivery-with-meeting
String[] ScheduledMeetTimes      ; Meeting time condition for delivery-with-meeting
; Schedule states (0=pending, 1=dispatched, 2=meeting_active) are stored via
; StorageUtil.GetIntValue(npc, "Intel_ScheduledState", 0) instead of a script
; array. This avoids a Papyrus VM limitation where new array variables added
; to recompiled scripts cannot be initialized on old saves ("Cannot create an
; array into a non-array variable").
Int ScheduledCount = 0
Int Property MAX_SCHEDULED = 10 AutoReadOnly

; =============================================================================
; INITIALIZATION
; =============================================================================

Event OnInit()
    InitializeScheduleArrays()
    RegisterForSingleUpdateGameTime(1.0)  ; Check every game hour
EndEvent

; NOTE: Quest scripts do NOT receive OnPlayerLoadGame events.
; Core.Maintenance() calls RestartMonitoring() on every game load instead.

Function RestartMonitoring()
    {Restart the schedule update loop after game load. Called by Core.Maintenance().
    Quest scripts don't receive OnPlayerLoadGame — this is the equivalent.
    Script-level arrays survive save/load, so scheduled tasks are still intact.}
    If ScheduledAgents == None
        InitializeScheduleArrays()
    EndIf

    ; Re-register the game-time update loop
    If ScheduledCount > 0
        RegisterForSingleUpdateGameTime(0.5)
        Core.DebugMsg("Schedule monitoring restarted (" + ScheduledCount + " tasks pending)")
    Else
        RegisterForSingleUpdateGameTime(1.0)
        Core.DebugMsg("Schedule monitoring restarted (idle)")
    EndIf
EndFunction

Function InitializeScheduleArrays()
    ScheduledAgents = new Actor[10]
    ScheduledDestinations = new String[10]
    ScheduledTimes = new Float[10]
    ScheduledTaskTypes = new String[10]
    ScheduledTargetNames = new String[10]
    ScheduledMessages = new String[10]
    ScheduledMeetLocations = new String[10]
    ScheduledMeetTimes = new String[10]
    ScheduledCount = 0
EndFunction

; =============================================================================
; MAIN API - Schedule Meeting
; =============================================================================

Bool Function ScheduleMeeting(Actor akNPC, String destination, String timeCondition)
    {
    Schedule NPC to travel to destination at a specific time.

    Parameters:
        akNPC - The NPC to schedule
        destination - Where to go
        timeCondition - When to go ("after sunset", "at dawn", "tonight", etc.)

    Returns:
        true if scheduled successfully
    }

    If akNPC == None
        Core.DebugMsg("ScheduleMeeting: None actor")
        Return false
    EndIf

    If akNPC.IsDead()
        Return false
    EndIf

    If destination == ""
        Core.SendTaskNarration(akNPC, akNPC.GetDisplayName() + " was asked to schedule a meeting but no destination was provided.")
        Return false
    EndIf

    ; Parse the time condition (C++ native — single call replaces 30+ StringContains)
    Float targetHour = IntelEngine.ParseTimeCondition(timeCondition)
    If targetHour < 0.0
        targetHour = HOUR_EVENING
    EndIf
    Float currentHour = GetCurrentGameHour()

    ; Calculate when the NPC should be at the destination
    Float meetingGameTime = IntelEngine.CalculateTargetGameTime(targetHour, currentHour)

    ; MCM confirmation prompt — BEFORE clearing any existing schedules
    If StorageUtil.GetIntValue(Game.GetPlayer(), "Intel_TaskConfirmPrompt") == 1
        String npcName = akNPC.GetDisplayName()
        Float hoursPreview = (meetingGameTime - Utility.GetCurrentGameTime()) * 24.0
        String timePreview = GetPreciseTimeDescription(targetHour, hoursPreview)
        String promptText = npcName + " wants to meet at " + destination + " " + timePreview + "."
        String confirmResult = SkyMessage.Show(promptText, "Allow", "Deny", "Deny (Silent)")
        If confirmResult == "Deny"
            Core.SendTaskNarration(akNPC, Game.GetPlayer().GetDisplayName() + " told " + npcName + " not to schedule the meeting.")
            Return false
        ElseIf confirmResult != "Allow"
            Return false
        EndIf
    EndIf

    ; Override any existing schedule for this NPC (after confirmation)
    Int existingSchedule = FindScheduleSlotByAgent(akNPC)
    If existingSchedule >= 0
        Core.DebugMsg("ScheduleMeeting: " + akNPC.GetDisplayName() + " already scheduled — overriding")
        ClearScheduleSlot(existingSchedule)
    EndIf

    ; Also cancel any active meeting task
    If StorageUtil.GetIntValue(akNPC, "Intel_IsScheduledMeeting") == 1
        Int activeSlot = Core.FindSlotByAgent(akNPC)
        If activeSlot >= 0
            Core.ClearSlot(activeSlot, true)
        EndIf
    EndIf

    ; Find a schedule slot
    Int slot = FindFreeScheduleSlot()
    If slot < 0
        Core.SendTaskNarration(akNPC, akNPC.GetDisplayName() + " has too many scheduled tasks already.")
        Return false
    EndIf

    ; Store schedule data
    ScheduledAgents[slot] = akNPC
    ScheduledDestinations[slot] = destination
    ScheduledTimes[slot] = meetingGameTime
    ScheduledTaskTypes[slot] = "travel"
    StorageUtil.SetIntValue(akNPC, "Intel_ScheduledState", 0)  ; pending
    ScheduledCount += 1

    ; Also store on actor for persistence
    StorageUtil.SetStringValue(akNPC, "Intel_ScheduledDest", destination)
    StorageUtil.SetFloatValue(akNPC, "Intel_ScheduledTime", meetingGameTime)
    StorageUtil.SetStringValue(akNPC, "Intel_ScheduledType", "travel")
    StorageUtil.SetFloatValue(akNPC, "Intel_ScheduledHour", targetHour)
    StorageUtil.SetStringValue(akNPC, "Intel_MeetingPlayerName", Game.GetPlayer().GetDisplayName())

    ; Calculate distance-based departure buffer (C++ estimates travel hours)
    Float currentGameTime = Utility.GetCurrentGameTime()
    ObjectReference destRef = IntelEngine.ResolveAnyDestination(akNPC, destination)
    If destRef != None
        Float travelDeadline = IntelEngine.CalculateDeadlineFromDistance(akNPC, destRef, false, 1.0, 12.0)
        Float travelHoursEstimate = (travelDeadline - currentGameTime) * 24.0
        StorageUtil.SetFloatValue(akNPC, "Intel_ScheduledDepartureHours", travelHoursEstimate)
        Core.DebugMsg("Departure buffer for " + akNPC.GetDisplayName() + ": " + travelHoursEstimate + "h (distance-based)")
    Else
        StorageUtil.SetFloatValue(akNPC, "Intel_ScheduledDepartureHours", DEPARTURE_BUFFER_HOURS)
        Core.DebugMsg("Departure buffer for " + akNPC.GetDisplayName() + ": " + DEPARTURE_BUFFER_HOURS + "h (fallback, dest not resolved)")
    EndIf

    ; Calculate human-readable time description using hours-until for precision
    Float hoursUntil = (meetingGameTime - currentGameTime) * 24.0
    String timeDesc = GetPreciseTimeDescription(targetHour, hoursUntil)

    Core.NotifyPlayer(akNPC.GetDisplayName() + " will meet you at " + destination + " " + timeDesc)

    Core.DebugMsg("Scheduled: " + akNPC.GetDisplayName() + " → " + destination + " at game time " + meetingGameTime + " (hour " + targetHour + ", now " + currentHour + ", in " + hoursUntil + "h, condition='" + timeCondition + "')")

    ; Ensure the update loop is running at the higher-frequency interval.
    ; This guards against the loop having stopped due to a prior error,
    ; and shortens the first check interval after scheduling.
    RegisterForSingleUpdateGameTime(0.5)

    Return true
EndFunction

; =============================================================================
; SCHEDULE FETCH / DELIVER
; =============================================================================

Bool Function ScheduleFetch(Actor akNPC, String targetName, String timeCondition)
    {
    Schedule fetching a person at a future time.

    Parameters:
        akNPC - The NPC who will do the fetching
        targetName - Name of the person to fetch
        timeCondition - When to go ("after sunset", "at dawn", "in 2 hours", etc.)

    Returns:
        true if scheduled successfully
    }

    If akNPC == None || akNPC.IsDead()
        Return false
    EndIf

    If targetName == ""
        Core.SendTaskNarration(akNPC, akNPC.GetDisplayName() + " was asked to schedule fetching someone but no target was specified.")
        Return false
    EndIf

    Float targetHour = IntelEngine.ParseTimeCondition(timeCondition)
    If targetHour < 0.0
        targetHour = HOUR_EVENING
    EndIf
    Float currentHour = GetCurrentGameHour()
    Float targetGameTime = IntelEngine.CalculateTargetGameTime(targetHour, currentHour)

    ; MCM confirmation prompt — BEFORE clearing any existing schedules
    If StorageUtil.GetIntValue(Game.GetPlayer(), "Intel_TaskConfirmPrompt") == 1
        String npcName = akNPC.GetDisplayName()
        Float hoursPreview = (targetGameTime - Utility.GetCurrentGameTime()) * 24.0
        String timePreview = GetPreciseTimeDescription(targetHour, hoursPreview)
        String promptText = npcName + " wants to fetch " + targetName + " " + timePreview + "."
        String confirmResult = SkyMessage.Show(promptText, "Allow", "Deny", "Deny (Silent)")
        If confirmResult == "Deny"
            Core.SendTaskNarration(akNPC, Game.GetPlayer().GetDisplayName() + " told " + npcName + " not to schedule the fetch.")
            Return false
        ElseIf confirmResult != "Allow"
            Return false
        EndIf
    EndIf

    ; Override any existing schedule for this NPC (after confirmation)
    Int existingSchedule = FindScheduleSlotByAgent(akNPC)
    If existingSchedule >= 0
        Core.DebugMsg("ScheduleFetch: " + akNPC.GetDisplayName() + " already scheduled — overriding")
        ClearScheduleSlot(existingSchedule)
    EndIf

    Int slot = FindFreeScheduleSlot()
    If slot < 0
        Core.SendTaskNarration(akNPC, akNPC.GetDisplayName() + " has too many scheduled tasks already.")
        Return false
    EndIf

    ; Store schedule data
    ScheduledAgents[slot] = akNPC
    ScheduledDestinations[slot] = ""
    ScheduledTimes[slot] = targetGameTime
    ScheduledTaskTypes[slot] = "fetch_npc"
    ScheduledTargetNames[slot] = targetName
    ScheduledMessages[slot] = ""
    StorageUtil.SetIntValue(akNPC, "Intel_ScheduledState", 0)  ; pending
    ScheduledCount += 1

    ; Persist on actor
    StorageUtil.SetStringValue(akNPC, "Intel_ScheduledDest", "")
    StorageUtil.SetFloatValue(akNPC, "Intel_ScheduledTime", targetGameTime)
    StorageUtil.SetStringValue(akNPC, "Intel_ScheduledType", "fetch_npc")
    StorageUtil.SetFloatValue(akNPC, "Intel_ScheduledHour", targetHour)
    StorageUtil.SetStringValue(akNPC, "Intel_ScheduledTargetName", targetName)

    Float hoursUntil = (targetGameTime - Utility.GetCurrentGameTime()) * 24.0
    String timeDesc = GetPreciseTimeDescription(targetHour, hoursUntil)

    Core.NotifyPlayer(akNPC.GetDisplayName() + " will fetch " + targetName + " " + timeDesc)
    Core.DebugMsg("Scheduled fetch: " + akNPC.GetDisplayName() + " → fetch " + targetName + " at game time " + targetGameTime)

    RegisterForSingleUpdateGameTime(0.5)
    Return true
EndFunction

Bool Function ScheduleDelivery(Actor akNPC, String targetName, String msgContent, String timeCondition, String meetLocation = "none", String meetTime = "none")
    {
    Schedule delivering a message to someone at a future time.
    If meetLocation and meetTime are provided, the recipient will also
    be scheduled to travel to that location after receiving the message.

    Parameters:
        akNPC - The NPC who will deliver the message
        targetName - Name of the person to deliver to
        msgContent - The message content
        timeCondition - When to deliver ("after sunset", "at dawn", "in 2 hours", etc.)
        meetLocation - Where the recipient should go (or "none")
        meetTime - When the recipient should go (or "none")

    Returns:
        true if scheduled successfully
    }

    If akNPC == None || akNPC.IsDead()
        Return false
    EndIf

    If targetName == ""
        Core.SendTaskNarration(akNPC, akNPC.GetDisplayName() + " was asked to schedule a delivery but no target was specified.")
        Return false
    EndIf

    Float targetHour = IntelEngine.ParseTimeCondition(timeCondition)
    If targetHour < 0.0
        targetHour = HOUR_EVENING
    EndIf
    Float currentHour = GetCurrentGameHour()
    Float targetGameTime = IntelEngine.CalculateTargetGameTime(targetHour, currentHour)

    ; MCM confirmation prompt — BEFORE clearing any existing schedules
    If StorageUtil.GetIntValue(Game.GetPlayer(), "Intel_TaskConfirmPrompt") == 1
        String npcName = akNPC.GetDisplayName()
        Float hoursPreview = (targetGameTime - Utility.GetCurrentGameTime()) * 24.0
        String timePreview = GetPreciseTimeDescription(targetHour, hoursPreview)
        String promptText = npcName + " wants to deliver a message to " + targetName + " " + timePreview + "."
        String confirmResult = SkyMessage.Show(promptText, "Allow", "Deny", "Deny (Silent)")
        If confirmResult == "Deny"
            Core.SendTaskNarration(akNPC, Game.GetPlayer().GetDisplayName() + " told " + npcName + " not to schedule the delivery.")
            Return false
        ElseIf confirmResult != "Allow"
            Return false
        EndIf
    EndIf

    ; Override any existing schedule for this NPC (after confirmation)
    Int existingSchedule = FindScheduleSlotByAgent(akNPC)
    If existingSchedule >= 0
        Core.DebugMsg("ScheduleDelivery: " + akNPC.GetDisplayName() + " already scheduled — overriding")
        ClearScheduleSlot(existingSchedule)
    EndIf

    Int slot = FindFreeScheduleSlot()
    If slot < 0
        Core.SendTaskNarration(akNPC, akNPC.GetDisplayName() + " has too many scheduled tasks already.")
        Return false
    EndIf

    ; Store schedule data
    ScheduledAgents[slot] = akNPC
    ScheduledDestinations[slot] = ""
    ScheduledTimes[slot] = targetGameTime
    ScheduledTaskTypes[slot] = "deliver_message"
    ScheduledTargetNames[slot] = targetName
    ScheduledMessages[slot] = msgContent
    ScheduledMeetLocations[slot] = meetLocation
    ScheduledMeetTimes[slot] = meetTime
    StorageUtil.SetIntValue(akNPC, "Intel_ScheduledState", 0)  ; pending
    ScheduledCount += 1

    ; Persist on actor
    StorageUtil.SetStringValue(akNPC, "Intel_ScheduledDest", "")
    StorageUtil.SetFloatValue(akNPC, "Intel_ScheduledTime", targetGameTime)
    StorageUtil.SetStringValue(akNPC, "Intel_ScheduledType", "deliver_message")
    StorageUtil.SetFloatValue(akNPC, "Intel_ScheduledHour", targetHour)
    StorageUtil.SetStringValue(akNPC, "Intel_ScheduledTargetName", targetName)
    StorageUtil.SetStringValue(akNPC, "Intel_ScheduledMessage", msgContent)
    StorageUtil.SetStringValue(akNPC, "Intel_ScheduledMeetLocation", meetLocation)
    StorageUtil.SetStringValue(akNPC, "Intel_ScheduledMeetTime", meetTime)

    Float hoursUntil = (targetGameTime - Utility.GetCurrentGameTime()) * 24.0
    String timeDesc = GetPreciseTimeDescription(targetHour, hoursUntil)

    Core.NotifyPlayer(akNPC.GetDisplayName() + " will deliver message to " + targetName + " " + timeDesc)
    Core.DebugMsg("Scheduled delivery: " + akNPC.GetDisplayName() + " → message to " + targetName + " at game time " + targetGameTime)

    RegisterForSingleUpdateGameTime(0.5)
    Return true
EndFunction

; =============================================================================
; MCM DISPLAY
; =============================================================================

String Function GetScheduleDisplay(Int slot)
    {Get a display string for a schedule slot (used by MCM)}

    If slot < 0 || slot >= MAX_SCHEDULED || ScheduledAgents[slot] == None
        Return "Empty"
    EndIf

    String npcName = ScheduledAgents[slot].GetDisplayName()
    String taskType = ScheduledTaskTypes[slot]
    Float hoursUntil = (ScheduledTimes[slot] - Utility.GetCurrentGameTime()) * 24.0

    ; Build task description
    String taskDesc = ""
    If taskType == "travel"
        taskDesc = "meet at " + ScheduledDestinations[slot]
    ElseIf taskType == "fetch_npc"
        taskDesc = "fetch " + ScheduledTargetNames[slot]
    ElseIf taskType == "deliver_message"
        taskDesc = "deliver message to " + ScheduledTargetNames[slot]
    Else
        taskDesc = taskType
    EndIf

    ; Build status string based on dispatch state (stored via StorageUtil on actor)
    Int schedState = StorageUtil.GetIntValue(ScheduledAgents[slot], "Intel_ScheduledState", 0)
    String statusStr = ""
    If schedState == 0
        ; Pending — show time estimate
        If hoursUntil <= 0.0
            statusStr = "overdue"
        ElseIf hoursUntil < 1.0
            statusStr = "very soon"
        Else
            statusStr = "in ~" + (hoursUntil as Int) + "h"
        EndIf
    ElseIf schedState == 1
        ; En route — also show time remaining or overdue
        If hoursUntil <= 0.0
            statusStr = "en route, overdue"
        ElseIf hoursUntil < 1.0
            statusStr = "en route, very soon"
        Else
            statusStr = "en route, in ~" + (hoursUntil as Int) + "h"
        EndIf
    ElseIf schedState == 2
        statusStr = "meeting"
    EndIf

    Return npcName + " — " + taskDesc + " (" + statusStr + ")"
EndFunction

Float Function GetCurrentGameHour()
    {Get current game hour (0-24)}
    Float gameTime = Utility.GetCurrentGameTime()
    Float dayFraction = gameTime - Math.Floor(gameTime)
    Return dayFraction * 24.0
EndFunction

String Function GetPreciseTimeDescription(Float hour, Float hoursUntil)
    {Get a precise human-readable description using both target hour and hours-until}

    ; For very short waits, use relative description
    If hoursUntil < 0.5
        Return "very soon"
    ElseIf hoursUntil < 1.5
        Return "in about an hour"
    ElseIf hoursUntil < 12.0
        ; Short-to-medium wait — show relative hours + time of day for clarity
        Int roundedHours = hoursUntil as Int
        If roundedHours < 1
            roundedHours = 1
        EndIf
        Return "in about " + roundedHours + " hours (" + GetTimeDescription(hour) + ")"
    ElseIf hoursUntil < 36.0
        ; Tomorrow — show time of day (avoid "tomorrow tonight")
        If hour >= 22.0 || hour < 5.0
            Return "tomorrow at night"
        EndIf
        Return "tomorrow " + GetTimeDescription(hour)
    EndIf

    ; Far future — just show time of day
    Return GetTimeDescription(hour)
EndFunction

String Function GetTimeDescription(Float hour)
    {Get human-readable time description}

    If hour >= 5.0 && hour < 6.0
        Return "at dawn"
    ElseIf hour >= 6.0 && hour < 8.0
        Return "at sunrise"
    ElseIf hour >= 8.0 && hour < 12.0
        Return "in the morning"
    ElseIf hour >= 12.0 && hour < 14.0
        Return "at midday"
    ElseIf hour >= 14.0 && hour < 18.0
        Return "in the afternoon"
    ElseIf hour >= 18.0 && hour < 20.0
        Return "in the evening"
    ElseIf hour >= 20.0 && hour < 22.0
        Return "at dusk"
    ElseIf hour >= 22.0 || hour < 5.0
        Return "tonight"
    EndIf

    Return "later"
EndFunction

; =============================================================================
; SCHEDULE MANAGEMENT
; =============================================================================

Int Function FindFreeScheduleSlot()
    Int i = 0
    While i < MAX_SCHEDULED
        If ScheduledAgents[i] == None
            Return i
        EndIf
        i += 1
    EndWhile
    Return -1
EndFunction

Int Function FindScheduleSlotByAgent(Actor npc)
    {Find the schedule slot assigned to a specific NPC. Returns -1 if not found.}
    Int i = 0
    While i < MAX_SCHEDULED
        If ScheduledAgents[i] == npc
            Return i
        EndIf
        i += 1
    EndWhile
    Return -1
EndFunction

Function ClearScheduleSlot(Int slot)
    If slot < 0 || slot >= MAX_SCHEDULED
        Return
    EndIf

    Actor npc = ScheduledAgents[slot]
    If npc != None
        StorageUtil.UnsetStringValue(npc, "Intel_ScheduledDest")
        StorageUtil.UnsetFloatValue(npc, "Intel_ScheduledTime")
        StorageUtil.UnsetStringValue(npc, "Intel_ScheduledType")
        StorageUtil.UnsetStringValue(npc, "Intel_ScheduledTargetName")
        StorageUtil.UnsetStringValue(npc, "Intel_ScheduledMessage")
        StorageUtil.UnsetStringValue(npc, "Intel_ScheduledMeetLocation")
        StorageUtil.UnsetStringValue(npc, "Intel_ScheduledMeetTime")
        StorageUtil.UnsetFloatValue(npc, "Intel_ScheduledDepartureHours")
        StorageUtil.UnsetFloatValue(npc, "Intel_ScheduledHour")
    EndIf

    ScheduledAgents[slot] = None
    ScheduledDestinations[slot] = ""
    ScheduledTimes[slot] = 0.0
    ScheduledTaskTypes[slot] = ""
    ScheduledTargetNames[slot] = ""
    ScheduledMessages[slot] = ""
    ScheduledMeetLocations[slot] = ""
    ScheduledMeetTimes[slot] = ""
    If npc != None
        StorageUtil.UnsetIntValue(npc, "Intel_ScheduledState")
    EndIf

    If ScheduledCount > 0
        ScheduledCount -= 1
    EndIf
EndFunction

Function SetScheduleState(Int slot, Int newState)
    {Set the dispatch state for a schedule slot. 0=pending, 1=dispatched, 2=meeting_active}
    If slot >= 0 && slot < MAX_SCHEDULED && ScheduledAgents[slot] != None
        StorageUtil.SetIntValue(ScheduledAgents[slot], "Intel_ScheduledState", newState)
    EndIf
EndFunction

Function ClearScheduleSlotByAgent(Actor npc)
    {Clear schedule slot by NPC reference. Called when meeting completes or times out.}
    If npc == None
        Return
    EndIf
    Int i = 0
    While i < MAX_SCHEDULED
        If ScheduledAgents[i] == npc
            ClearScheduleSlot(i)
            Return
        EndIf
        i += 1
    EndWhile
EndFunction

; =============================================================================
; UPDATE LOOP - Check for due schedules
; =============================================================================

Event OnUpdateGameTime()
    Float currentGameTime = Utility.GetCurrentGameTime()

    Int i = 0
    While i < MAX_SCHEDULED
        If ScheduledAgents[i] != None && StorageUtil.GetIntValue(ScheduledAgents[i], "Intel_ScheduledState", 0) == 0
            Float dispatchTime = GetSlotDispatchTime(i)

            If currentGameTime >= dispatchTime
                Float hoursEarly = (ScheduledTimes[i] - currentGameTime) * 24.0
                Core.DebugMsg("Schedule trigger: slot " + i + " at game time " + currentGameTime + " (due " + ScheduledTimes[i] + ", " + hoursEarly + "h early)")
                ExecuteScheduledTask(i)
            EndIf
        EndIf
        i += 1
    EndWhile

    ; Heartbeat: ensure monitoring loops are alive.
    ; Papyrus VM stack dumps (from MCM browsing, mod overload, etc.) can kill
    ; RegisterForSingleUpdate callbacks. The Schedule loop runs on game-time
    ; timers which are more resilient, so we re-kick both from here.
    If Travel
        Travel.EnsureMonitoringAlive()
    EndIf
    If NPCTasks
        NPCTasks.EnsureMonitoringAlive()
    EndIf

    ; Continue checking — sleep until next task is due (or 1 game hour if nothing pending)
    If ScheduledCount > 0
        ; Find soonest dispatch time among pending tasks
        Float soonest = currentGameTime + (1.0 / 24.0)  ; default: 1 game hour
        Int j = 0
        While j < MAX_SCHEDULED
            If ScheduledAgents[j] != None && StorageUtil.GetIntValue(ScheduledAgents[j], "Intel_ScheduledState", 0) == 0
                Float dt = GetSlotDispatchTime(j)
                If dt < soonest
                    soonest = dt
                EndIf
            EndIf
            j += 1
        EndWhile
        ; Sleep until the soonest task is due, minimum 5 game minutes to avoid busy-looping
        Float sleepHours = (soonest - currentGameTime) * 24.0
        If sleepHours < 0.083
            sleepHours = 0.083  ; ~5 game minutes minimum
        ElseIf sleepHours > 1.0
            sleepHours = 1.0  ; cap at 1 game hour
        EndIf
        Core.DebugMsg("Schedule loop: " + ScheduledCount + " pending, gameTime=" + currentGameTime + ", next check in " + sleepHours + "h")
        RegisterForSingleUpdateGameTime(sleepHours)
    Else
        RegisterForSingleUpdateGameTime(1.0)  ; Check every game hour otherwise
    EndIf
EndEvent

Function ExecuteScheduledTask(Int slot)
    ; Read ALL data from arrays BEFORE clearing the slot
    Actor npc = ScheduledAgents[slot]
    String destination = ScheduledDestinations[slot]
    String taskType = ScheduledTaskTypes[slot]
    Float meetingGameTime = ScheduledTimes[slot]
    String targetName = ScheduledTargetNames[slot]
    String msgContent = ScheduledMessages[slot]
    String meetLoc = ScheduledMeetLocations[slot]
    String meetTimeStr = ScheduledMeetTimes[slot]

    Core.DebugMsg("Executing scheduled task for " + npc.GetDisplayName() + ": " + taskType + " → " + destination)

    ; Check if NPC is still valid
    If npc == None || npc.IsDead()
        Core.DebugMsg("Scheduled NPC is invalid or dead")
        ClearScheduleSlot(slot)
        Return
    EndIf

    ; If NPC is already on a task, clear it first so the scheduled task takes priority
    If npc.IsInFaction(Core.IntelEngine_TaskFaction)
        Core.DebugMsg("Scheduled NPC " + npc.GetDisplayName() + " is on a task — clearing it for scheduled task")
        Int existingSlot = Core.FindSlotByAgent(npc)
        If existingSlot >= 0
            Core.ClearSlot(existingSlot, true)
        EndIf
    EndIf

    ; Mark dispatched AFTER clearing any existing task — Core.ClearSlot unsets
    ; Intel_ScheduledState as a side effect, so we must set it after, not before.
    StorageUtil.SetIntValue(npc, "Intel_ScheduledState", 1)

    ; Execute based on task type
    If taskType == "travel"
        ; Flag as scheduled meeting so Travel hooks can react differently
        StorageUtil.SetIntValue(npc, "Intel_IsScheduledMeeting", 1)

        ; Store meeting metadata for Travel's lateness detection and prompts
        StorageUtil.SetFloatValue(npc, "Intel_MeetingTime", meetingGameTime)
        StorageUtil.SetStringValue(npc, "Intel_MeetingDest", destination)
        StorageUtil.SetStringValue(npc, "Intel_MeetingPlayerName", Game.GetPlayer().GetDisplayName())

        ; Clear any previous meeting outcome before starting the new meeting
        Core.ClearMeetingOutcome(npc)

        ; Determine speed: jog if less than 1 hour to meeting, walk otherwise
        Float hoursToMeeting = (meetingGameTime - Utility.GetCurrentGameTime()) * 24.0
        Int speed = 0  ; walk
        If hoursToMeeting < 1.0
            speed = 1  ; jog — we're cutting it close
        EndIf

        ; Always pathfind to meetings — even off-screen — so NPCs can realistically
        ; be early or late. Teleporting skips travel time and removes immersion.
        ; The engine handles off-screen pathfinding via AI packages natively.
        Core.DebugMsg("Schedule execute: " + npc.GetDisplayName() + " → " + destination + " (3D=" + npc.Is3DLoaded() + ", speed=" + speed + ", " + hoursToMeeting + "h to meeting)")
        ; isScheduled=true bypasses MCM confirmation (player already agreed)
        Bool success = Travel.GoToLocation(npc, destination, speed, true)
        If success
            If npc.Is3DLoaded()
                Core.SendTaskNarration(npc, npc.GetDisplayName() + " headed out to " + destination + " as planned.")
            EndIf
        Else
            Core.DebugMsg("Schedule GoToLocation FAILED for " + npc.GetDisplayName())
            If npc.Is3DLoaded()
                Core.SendTaskNarration(npc, npc.GetDisplayName() + " tried to leave for " + destination + " but couldn't.")
            EndIf
            StorageUtil.UnsetIntValue(npc, "Intel_IsScheduledMeeting")
            StorageUtil.UnsetFloatValue(npc, "Intel_MeetingTime")
            StorageUtil.UnsetStringValue(npc, "Intel_MeetingDest")
            ClearScheduleSlot(slot)
        EndIf

    ElseIf taskType == "fetch_npc"
        Core.DebugMsg("Schedule execute: " + npc.GetDisplayName() + " → fetch " + targetName)
        ClearScheduleSlot(slot)  ; Non-meeting tasks don't need persistent schedule tracking
        NPCTasks.FetchNPC(npc, targetName)

    ElseIf taskType == "deliver_message"
        Core.DebugMsg("Schedule execute: " + npc.GetDisplayName() + " → deliver message to " + targetName)
        ClearScheduleSlot(slot)  ; Non-meeting tasks don't need persistent schedule tracking
        NPCTasks.DeliverMessage(npc, targetName, msgContent, meetLoc, meetTimeStr)
    EndIf
EndFunction

; =============================================================================
; CANCEL API
; =============================================================================

Function CancelSchedule(Actor npc)
    {Cancel any scheduled task for this NPC}

    If npc == None
        Return
    EndIf

    Int i = 0
    While i < MAX_SCHEDULED
        If ScheduledAgents[i] == npc
            Core.DebugMsg("Canceling schedule for " + npc.GetDisplayName())
            ClearScheduleSlot(i)
            Core.SendTaskNarration(npc, npc.GetDisplayName() + "'s scheduled task was cancelled.")
            Return
        EndIf
        i += 1
    EndWhile
EndFunction

Function CancelAllSchedules()
    {Cancel all scheduled tasks}

    Int i = 0
    While i < MAX_SCHEDULED
        If ScheduledAgents[i] != None
            ClearScheduleSlot(i)
        EndIf
        i += 1
    EndWhile

    ScheduledCount = 0
    Core.NotifyPlayer("All scheduled tasks cancelled")
EndFunction

; =============================================================================
; INTERNAL HELPERS
; =============================================================================

Float Function GetSlotDispatchTime(Int slot)
    {Calculate the effective dispatch time for a schedule slot.
    Travel tasks dispatch early to allow for pathfinding.}
    Float dispatchTime = ScheduledTimes[slot]
    If ScheduledTaskTypes[slot] == "travel"
        Float departHours = StorageUtil.GetFloatValue(ScheduledAgents[slot], "Intel_ScheduledDepartureHours", DEPARTURE_BUFFER_HOURS)
        dispatchTime = ScheduledTimes[slot] - (departHours / 24.0)
    EndIf
    Return dispatchTime
EndFunction
