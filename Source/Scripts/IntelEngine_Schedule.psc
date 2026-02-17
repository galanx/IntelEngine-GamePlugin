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
    Quest scripts don't receive OnPlayerLoadGame ? this is the equivalent.
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
    {Schedule NPC to travel to destination at a specific time.}

    If akNPC == None || akNPC.IsDead()
        Return false
    EndIf
    If destination == ""
        Core.SendTaskNarration(akNPC, akNPC.GetDisplayName() + " was asked to schedule a meeting but no destination was provided.")
        Return false
    EndIf

    ; Shared scheduling scaffolding: time parse ? MCM confirm ? override ? allocate
    Int slot = PrepareScheduleSlot(akNPC, "travel", "meet at " + destination, timeCondition)
    If slot < 0
        Return false
    EndIf

    Float targetHour = StorageUtil.GetFloatValue(akNPC, "Intel_ScheduledHour")
    Float meetingGameTime = ScheduledTimes[slot]

    ; Meeting-specific: store destination + player name
    ScheduledDestinations[slot] = destination
    StorageUtil.SetStringValue(akNPC, "Intel_ScheduledDest", destination)
    StorageUtil.SetStringValue(akNPC, "Intel_MeetingPlayerName", Game.GetPlayer().GetDisplayName())

    ; Also cancel any active meeting task
    If StorageUtil.GetIntValue(akNPC, "Intel_IsScheduledMeeting") == 1
        Int activeSlot = Core.FindSlotByAgent(akNPC)
        If activeSlot >= 0
            Core.ClearSlot(activeSlot, true)
        EndIf
    EndIf

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

    Float hoursUntil = (meetingGameTime - currentGameTime) * 24.0
    String timeDesc = GetPreciseTimeDescription(targetHour, hoursUntil)
    Core.NotifyPlayer(akNPC.GetDisplayName() + " will meet you at " + destination + " " + timeDesc)
    Core.DebugMsg("Scheduled: " + akNPC.GetDisplayName() + " ? " + destination + " at game time " + meetingGameTime + " (hour " + targetHour + ", in " + hoursUntil + "h, condition='" + timeCondition + "')")

    RegisterForSingleUpdateGameTime(0.5)
    Return true
EndFunction

; =============================================================================
; SCHEDULE FETCH / DELIVER
; =============================================================================

Bool Function ScheduleFetch(Actor akNPC, String targetName, String timeCondition)
    {Schedule fetching a person at a future time.}

    If akNPC == None || akNPC.IsDead()
        Return false
    EndIf
    If targetName == ""
        Core.SendTaskNarration(akNPC, akNPC.GetDisplayName() + " was asked to schedule fetching someone but no target was specified.")
        Return false
    EndIf

    Int slot = PrepareScheduleSlot(akNPC, "fetch_npc", "fetch " + targetName, timeCondition)
    If slot < 0
        Return false
    EndIf

    Float targetHour = StorageUtil.GetFloatValue(akNPC, "Intel_ScheduledHour")

    ; Fetch-specific: store target name
    ScheduledTargetNames[slot] = targetName
    StorageUtil.SetStringValue(akNPC, "Intel_ScheduledTargetName", targetName)

    Float hoursUntil = (ScheduledTimes[slot] - Utility.GetCurrentGameTime()) * 24.0
    String timeDesc = GetPreciseTimeDescription(targetHour, hoursUntil)
    Core.NotifyPlayer(akNPC.GetDisplayName() + " will fetch " + targetName + " " + timeDesc)
    Core.DebugMsg("Scheduled fetch: " + akNPC.GetDisplayName() + " ? fetch " + targetName + " at game time " + ScheduledTimes[slot])

    RegisterForSingleUpdateGameTime(0.5)
    Return true
EndFunction

Bool Function ScheduleDelivery(Actor akNPC, String targetName, String msgContent, String timeCondition, String meetLocation = "none", String meetTime = "none")
    {Schedule delivering a message to someone at a future time.
    If meetLocation and meetTime are provided, the recipient will also
    be scheduled to travel to that location after receiving the message.}

    If akNPC == None || akNPC.IsDead()
        Return false
    EndIf
    If targetName == ""
        Core.SendTaskNarration(akNPC, akNPC.GetDisplayName() + " was asked to schedule a delivery but no target was specified.")
        Return false
    EndIf

    Int slot = PrepareScheduleSlot(akNPC, "deliver_message", "deliver a message to " + targetName, timeCondition)
    If slot < 0
        Return false
    EndIf

    Float targetHour = StorageUtil.GetFloatValue(akNPC, "Intel_ScheduledHour")

    ; Delivery-specific: store target, message, meeting data
    ScheduledTargetNames[slot] = targetName
    ScheduledMessages[slot] = msgContent
    ScheduledMeetLocations[slot] = meetLocation
    ScheduledMeetTimes[slot] = meetTime
    StorageUtil.SetStringValue(akNPC, "Intel_ScheduledTargetName", targetName)
    StorageUtil.SetStringValue(akNPC, "Intel_ScheduledMessage", msgContent)
    StorageUtil.SetStringValue(akNPC, "Intel_ScheduledMeetLocation", meetLocation)
    StorageUtil.SetStringValue(akNPC, "Intel_ScheduledMeetTime", meetTime)

    Float hoursUntil = (ScheduledTimes[slot] - Utility.GetCurrentGameTime()) * 24.0
    String timeDesc = GetPreciseTimeDescription(targetHour, hoursUntil)
    Core.NotifyPlayer(akNPC.GetDisplayName() + " will deliver message to " + targetName + " " + timeDesc)
    Core.DebugMsg("Scheduled delivery: " + akNPC.GetDisplayName() + " ? message to " + targetName + " at game time " + ScheduledTimes[slot])

    RegisterForSingleUpdateGameTime(0.5)
    Return true
EndFunction

; =============================================================================
; SHARED SCHEDULING SCAFFOLDING
;
; Consolidates the common pattern shared by ScheduleMeeting, ScheduleFetch,
; and ScheduleDelivery: time parsing ? MCM confirmation ? override existing ?
; find free slot ? store common data + persistence.
;
; Returns: schedule slot index (>= 0) on success, -1 on failure.
; Callers then store task-specific data and notify the player.
; =============================================================================

Int Function PrepareScheduleSlot(Actor akNPC, String taskType, String taskDescription, String timeCondition)
    {Shared scheduling setup. Handles time parsing, MCM confirmation, slot override,
    and common data storage. Returns slot index or -1 on failure.
    After success, callers store task-specific data into ScheduledTargetNames,
    ScheduledMessages, etc. and call RegisterForSingleUpdateGameTime(0.5).}

    ; Parse time condition
    Float targetHour = IntelEngine.ParseTimeCondition(timeCondition)
    If targetHour < 0.0
        targetHour = HOUR_EVENING
    EndIf
    Float currentHour = GetCurrentGameHour()
    Float targetGameTime = IntelEngine.CalculateTargetGameTime(targetHour, currentHour)

    ; MCM confirmation prompt ? BEFORE clearing any existing schedules
    If StorageUtil.GetIntValue(Game.GetPlayer(), "Intel_TaskConfirmPrompt") == 1
        String npcName = akNPC.GetDisplayName()
        Float hoursPreview = (targetGameTime - Utility.GetCurrentGameTime()) * 24.0
        String timePreview = GetPreciseTimeDescription(targetHour, hoursPreview)
        String promptText = npcName + " wants to " + taskDescription + " " + timePreview + "."
        String confirmResult = SkyMessage.Show(promptText, "Allow", "Deny", "Deny (Silent)")
        If confirmResult == "Deny"
            Core.SendTaskNarration(akNPC, Game.GetPlayer().GetDisplayName() + " told " + npcName + " not to schedule that.")
            Core.InjectFact(akNPC, "invited " + Game.GetPlayer().GetDisplayName() + " to " + taskDescription + " but was turned down")
            Return -1
        ElseIf confirmResult != "Allow"
            ; Silent decline: inject fact (no narration) so LLM knows not to retry
            Core.InjectFact(akNPC, "proposed to " + taskDescription + " but the plan fell through")
            Return -1
        EndIf
    EndIf

    ; Override any existing schedule for this NPC (after confirmation)
    Int existingSchedule = FindScheduleSlotByAgent(akNPC)
    If existingSchedule >= 0
        Core.DebugMsg("PrepareScheduleSlot: " + akNPC.GetDisplayName() + " already scheduled ? overriding")
        ClearScheduleSlot(existingSchedule)
    EndIf

    ; Find a schedule slot
    Int slot = FindFreeScheduleSlot()
    If slot < 0
        Core.SendTaskNarration(akNPC, akNPC.GetDisplayName() + " has too many scheduled tasks already.")
        Return -1
    EndIf

    ; Store common schedule data
    ScheduledAgents[slot] = akNPC
    ScheduledDestinations[slot] = ""
    ScheduledTimes[slot] = targetGameTime
    ScheduledTaskTypes[slot] = taskType
    ScheduledTargetNames[slot] = ""
    ScheduledMessages[slot] = ""
    ScheduledMeetLocations[slot] = ""
    ScheduledMeetTimes[slot] = ""
    StorageUtil.SetIntValue(akNPC, "Intel_ScheduledState", 0)  ; pending
    ScheduledCount += 1

    ; Persist common fields on actor
    StorageUtil.SetStringValue(akNPC, "Intel_ScheduledDest", "")
    StorageUtil.SetFloatValue(akNPC, "Intel_ScheduledTime", targetGameTime)
    StorageUtil.SetStringValue(akNPC, "Intel_ScheduledType", taskType)
    StorageUtil.SetFloatValue(akNPC, "Intel_ScheduledHour", targetHour)

    Return slot
EndFunction

; =============================================================================
; MCM DISPLAY
; =============================================================================

String Function GetScheduleDisplay(Int slot)
    {Get task description for a schedule slot -- left column in MCM}

    If slot < 0 || slot >= MAX_SCHEDULED || ScheduledAgents[slot] == None
        Return "Empty"
    EndIf

    String npcName = ScheduledAgents[slot].GetDisplayName()
    String taskType = ScheduledTaskTypes[slot]

    If taskType == "travel"
        Return npcName + " @ " + ScheduledDestinations[slot]
    ElseIf taskType == "fetch_npc"
        Return npcName + ": fetch " + ScheduledTargetNames[slot]
    ElseIf taskType == "deliver_message"
        Return npcName + ": msg to " + ScheduledTargetNames[slot]
    EndIf
    Return npcName + ": " + taskType
EndFunction

String Function GetScheduleStatus(Int slot)
    {Get timing status for a schedule slot -- right column in MCM}

    If slot < 0 || slot >= MAX_SCHEDULED || ScheduledAgents[slot] == None
        Return ""
    EndIf

    Float hoursUntil = (ScheduledTimes[slot] - Utility.GetCurrentGameTime()) * 24.0
    Int schedState = StorageUtil.GetIntValue(ScheduledAgents[slot], "Intel_ScheduledState", 0)

    If schedState == 0
        If hoursUntil <= 0.0
            Return "overdue"
        ElseIf hoursUntil < 1.0
            Return "very soon"
        Else
            Return "in ~" + (hoursUntil as Int) + "h"
        EndIf
    ElseIf schedState == 1
        If hoursUntil <= 0.0
            Return "en route, overdue"
        ElseIf hoursUntil < 1.0
            Return "en route, soon"
        Else
            Return "en route, ~" + (hoursUntil as Int) + "h"
        EndIf
    ElseIf schedState == 2
        Return "meeting"
    EndIf
    Return ""
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
        ; Short-to-medium wait ? show relative hours + time of day for clarity
        Int roundedHours = hoursUntil as Int
        If roundedHours < 1
            roundedHours = 1
        EndIf
        Return "in about " + roundedHours + " hours (" + GetTimeDescription(hour) + ")"
    ElseIf hoursUntil < 36.0
        ; Could be today or tomorrow ? check if target crosses midnight
        ; Derive current hour: currentHour = targetHour - hoursUntil, normalized to 0-24
        Float currentHour = hour - hoursUntil
        While currentHour < 0.0
            currentHour += 24.0
        EndWhile
        While currentHour >= 24.0
            currentHour -= 24.0
        EndWhile
        Float hoursToMidnight = 24.0 - currentHour
        If hoursUntil < hoursToMidnight
            ; Still today ? just show time of day (e.g., "tonight", "in the evening")
            Return GetTimeDescription(hour)
        EndIf
        ; Tomorrow ? show time of day with "tomorrow" prefix
        If hour >= 22.0 || hour < 5.0
            Return "tomorrow at night"
        EndIf
        Return "tomorrow " + GetTimeDescription(hour)
    EndIf

    ; Far future ? just show time of day
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

    ; Continue checking ? sleep until next task is due (or 1 game hour if nothing pending)
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

    Core.DebugMsg("Executing scheduled task for " + npc.GetDisplayName() + ": " + taskType + " ? " + destination)

    ; Check if NPC is still valid
    If npc == None || npc.IsDead()
        Core.DebugMsg("Scheduled NPC is invalid or dead")
        ClearScheduleSlot(slot)
        Return
    EndIf

    ; If NPC is already on a task, clear it first so the scheduled task takes priority
    If npc.IsInFaction(Core.IntelEngine_TaskFaction)
        Core.DebugMsg("Scheduled NPC " + npc.GetDisplayName() + " is on a task ? clearing it for scheduled task")
        Int existingSlot = Core.FindSlotByAgent(npc)
        If existingSlot >= 0
            Core.ClearSlot(existingSlot, true)
        EndIf
    EndIf

    ; Mark dispatched AFTER clearing any existing task ? Core.ClearSlot unsets
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
            speed = 1  ; jog ? we're cutting it close
        EndIf

        ; Always pathfind to meetings ? even off-screen ? so NPCs can realistically
        ; be early or late. Teleporting skips travel time and removes immersion.
        ; The engine handles off-screen pathfinding via AI packages natively.
        Core.DebugMsg("Schedule execute: " + npc.GetDisplayName() + " ? " + destination + " (3D=" + npc.Is3DLoaded() + ", speed=" + speed + ", " + hoursToMeeting + "h to meeting)")
        ; waitForPlayer=1, isScheduled=true bypasses MCM confirmation (player already agreed)
        Bool success = Travel.GoToLocation(npc, destination, speed, 1, true)
        If success
            If npc.Is3DLoaded()
                ; Narrate TO the player so the NPC addresses them directly ("see you there")
                ; instead of monologuing about the player in third person
                Core.SendTaskNarration(npc, npc.GetDisplayName() + " departed for " + destination + ".", Game.GetPlayer())
            EndIf
        Else
            Core.DebugMsg("Schedule GoToLocation FAILED for " + npc.GetDisplayName())
            If npc.Is3DLoaded()
                Core.SendTaskNarration(npc, npc.GetDisplayName() + " tried to leave for " + destination + " but was unable to.", Game.GetPlayer())
            EndIf
            StorageUtil.UnsetIntValue(npc, "Intel_IsScheduledMeeting")
            StorageUtil.UnsetFloatValue(npc, "Intel_MeetingTime")
            StorageUtil.UnsetStringValue(npc, "Intel_MeetingDest")
            ClearScheduleSlot(slot)
        EndIf

    ElseIf taskType == "fetch_npc"
        Core.DebugMsg("Schedule execute: " + npc.GetDisplayName() + " ? fetch " + targetName)
        ClearScheduleSlot(slot)  ; Non-meeting tasks don't need persistent schedule tracking
        NPCTasks.FetchNPC(npc, targetName)

    ElseIf taskType == "deliver_message"
        Core.DebugMsg("Schedule execute: " + npc.GetDisplayName() + " ? deliver message to " + targetName)
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
