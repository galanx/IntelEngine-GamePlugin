Scriptname IntelEngine_MCM extends SKI_ConfigBase
{
    IntelEngine MCM Menu v1.0

    Provides configuration and management options:
    - View active task status
    - Clear individual tasks or all tasks
    - Toggle debug mode
    - Adjust concurrent task limits
    - Clear stored messages

    Requires: SkyUI (https://www.nexusmods.com/skyrimspecialedition/mods/12604)
}

; =============================================================================
; PROPERTIES
; =============================================================================

; NOTE: ModName is inherited from SKI_ConfigBase - do NOT redeclare it here.
; Set it in OnConfigInit() instead (see below).

IntelEngine_Core Property Core Auto
{Reference to core script for task management}

GlobalVariable Property IntelEngine_DebugMode Auto
GlobalVariable Property IntelEngine_MaxConcurrentTasks Auto
GlobalVariable Property IntelEngine_DefaultWaitHours Auto

; =============================================================================
; MCM STATE - Option IDs
; =============================================================================

; Status page
Int OID_Slot0Status
Int OID_Slot1Status
Int OID_Slot2Status
Int OID_Slot3Status
Int OID_Slot4Status
Int OID_ClearSlot0
Int OID_ClearSlot1
Int OID_ClearSlot2
Int OID_ClearSlot3
Int OID_ClearSlot4
Int OID_ResetAllTasks

; Scheduled Tasks page (OIDs stored via StorageUtil to avoid old-save array issues)
Int OID_CancelAllSchedules

; Settings page
Int OID_DebugMode
Int OID_MaxTasks
Int OID_DefaultWaitHours
Int OID_TravelConfirmMode
Int OID_DeliveryReportBack
Int OID_MeetingTimeoutHours
Int OID_MeetingGracePeriod

; =============================================================================
; SKI_ConfigBase OVERRIDES
; =============================================================================

String Function GetCustomControl(Int optionId)
    Return ""
EndFunction

Int Function GetVersion()
    Return 2
EndFunction

Event OnConfigInit()
    ModName = "IntelEngine"
    Pages = new String[3]
    Pages[0] = "Active Tasks"
    Pages[1] = "Scheduled Tasks"
    Pages[2] = "Settings"
EndEvent

Event OnVersionUpdate(Int newVersion)
    If newVersion >= 2
        ; Refresh page names — OnConfigInit only runs on first save init,
        ; so renamed pages (e.g. "Scheduled Meetings" → "Scheduled Tasks")
        ; won't update on existing saves without this.
        Pages = new String[3]
        Pages[0] = "Active Tasks"
        Pages[1] = "Scheduled Tasks"
        Pages[2] = "Settings"
    EndIf
EndEvent

Event OnPageReset(String page)
    SetCursorFillMode(TOP_TO_BOTTOM)

    If page == "" || page == "Active Tasks"
        ShowStatusPage()
    ElseIf page == "Scheduled Tasks" || page == "Scheduled Meetings"
        ShowScheduledPage()
    ElseIf page == "Settings"
        ShowSettingsPage()
    EndIf
EndEvent

; =============================================================================
; STATUS PAGE
; =============================================================================

Function ShowStatusPage()
    SetCursorFillMode(TOP_TO_BOTTOM)
    SetCursorPosition(0)

    AddHeaderOption("Active Tasks")
    AddEmptyOption()

    ; Show each slot status
    String slot0 = GetSlotDisplay(0)
    String slot1 = GetSlotDisplay(1)
    String slot2 = GetSlotDisplay(2)
    String slot3 = GetSlotDisplay(3)
    String slot4 = GetSlotDisplay(4)

    OID_Slot0Status = AddTextOption("Slot 0:", slot0)
    OID_ClearSlot0 = AddTextOption("", "Clear", GetClearFlag(0))

    OID_Slot1Status = AddTextOption("Slot 1:", slot1)
    OID_ClearSlot1 = AddTextOption("", "Clear", GetClearFlag(1))

    OID_Slot2Status = AddTextOption("Slot 2:", slot2)
    OID_ClearSlot2 = AddTextOption("", "Clear", GetClearFlag(2))

    OID_Slot3Status = AddTextOption("Slot 3:", slot3)
    OID_ClearSlot3 = AddTextOption("", "Clear", GetClearFlag(3))

    OID_Slot4Status = AddTextOption("Slot 4:", slot4)
    OID_ClearSlot4 = AddTextOption("", "Clear", GetClearFlag(4))

    AddEmptyOption()
    AddHeaderOption("Actions")
    OID_ResetAllTasks = AddTextOption("Reset All Tasks", "Click")
EndFunction

String Function GetSlotDisplay(Int slot)
    If Core == None
        Return "Error: No Core"
    EndIf

    String status = Core.GetSlotStatus(slot)
    If status == "Empty"
        Return "Empty"
    EndIf
    Return status
EndFunction

Int Function GetClearFlag(Int slot)
    If Core == None
        Return OPTION_FLAG_DISABLED
    EndIf

    String status = Core.GetSlotStatus(slot)
    If status == "Empty" || status == "Invalid"
        Return OPTION_FLAG_DISABLED
    EndIf
    Return OPTION_FLAG_NONE
EndFunction

; =============================================================================
; SCHEDULED MEETINGS PAGE
; =============================================================================

Function ShowScheduledPage()
    SetCursorFillMode(TOP_TO_BOTTOM)
    SetCursorPosition(0)

    If Core == None || Core.Schedule == None
        AddHeaderOption("Scheduled Tasks")
        AddTextOption("Error:", "Schedule not found")
        Return
    EndIf

    AddHeaderOption("Scheduled Tasks")
    AddEmptyOption()

    ; Clear previous cancel OIDs (StorageUtil avoids old-save array crash)
    Form mcmForm = Self as Form
    Int i = 0
    While i < 10
        StorageUtil.UnsetIntValue(mcmForm, "MCM_CancelOID_" + i)
        i += 1
    EndWhile

    i = 0
    Int shown = 0
    While i < 10
        String display = Core.Schedule.GetScheduleDisplay(i)
        If display != "Empty"
            AddTextOption(display, "")
            Int cancelOID = AddTextOption("", "Cancel")
            StorageUtil.SetIntValue(mcmForm, "MCM_CancelOID_" + i, cancelOID)
            shown += 1
        EndIf
        i += 1
    EndWhile

    If shown == 0
        AddTextOption("No scheduled meetings", "")
    EndIf

    AddEmptyOption()
    AddHeaderOption("Actions")

    Int flag = OPTION_FLAG_NONE
    If shown == 0
        flag = OPTION_FLAG_DISABLED
    EndIf
    OID_CancelAllSchedules = AddTextOption("Cancel All Scheduled", "Click", flag)
EndFunction

; =============================================================================
; SETTINGS PAGE
; =============================================================================

Function ShowSettingsPage()
    SetCursorFillMode(TOP_TO_BOTTOM)
    SetCursorPosition(0)

    AddHeaderOption("General Settings")
    AddTextOption("Mod by", "Galanx", OPTION_FLAG_DISABLED)

    Bool debugEnabled = false
    If IntelEngine_DebugMode != None
        debugEnabled = IntelEngine_DebugMode.GetValue() > 0
    EndIf
    OID_DebugMode = AddToggleOption("Debug Mode", debugEnabled)

    Float maxTasks = 5.0
    If IntelEngine_MaxConcurrentTasks != None
        maxTasks = IntelEngine_MaxConcurrentTasks.GetValue()
    EndIf
    OID_MaxTasks = AddSliderOption("Max Concurrent Tasks", maxTasks, "{0}")

    Float waitHours = 48.0
    If IntelEngine_DefaultWaitHours != None
        waitHours = IntelEngine_DefaultWaitHours.GetValue()
    EndIf
    OID_DefaultWaitHours = AddSliderOption("Default Wait Hours", waitHours, "{0}")

    AddEmptyOption()
    AddHeaderOption("Task Settings")

    Bool travelPrompt = StorageUtil.GetIntValue(Game.GetPlayer(), "Intel_TaskConfirmPrompt") as Bool
    OID_TravelConfirmMode = AddToggleOption("Show Task Confirmation", travelPrompt)

    Bool reportBack = StorageUtil.GetIntValue(Game.GetPlayer(), "Intel_DeliveryReportBack") as Bool
    OID_DeliveryReportBack = AddToggleOption("Report Back After Delivery", reportBack)

    Float meetTimeout = StorageUtil.GetFloatValue(Game.GetPlayer(), "Intel_MeetingTimeoutHours", 3.0)
    OID_MeetingTimeoutHours = AddSliderOption("Meeting Timeout Hours", meetTimeout, "{1}")

    Float gracePeriod = 0.5
    If Core != None
        gracePeriod = Core.MeetingGracePeriod
    EndIf
    OID_MeetingGracePeriod = AddSliderOption("Meeting Grace Period (hours)", gracePeriod, "{1}")

EndFunction

; =============================================================================
; OPTION HANDLERS
; =============================================================================

Event OnOptionSelect(Int optionId)
    If optionId == OID_ResetAllTasks
        Bool confirm = ShowMessage("Reset all active tasks? NPCs will return to their normal routines.", true, "Yes", "No")
        If confirm && Core != None
            Core.ForceResetAllSlots()
            ShowMessage("All tasks have been reset.", false)
            ForcePageReset()
        EndIf

    ElseIf optionId == OID_ClearSlot0
        ClearSlotWithConfirm(0)
    ElseIf optionId == OID_ClearSlot1
        ClearSlotWithConfirm(1)
    ElseIf optionId == OID_ClearSlot2
        ClearSlotWithConfirm(2)
    ElseIf optionId == OID_ClearSlot3
        ClearSlotWithConfirm(3)
    ElseIf optionId == OID_ClearSlot4
        ClearSlotWithConfirm(4)

    ElseIf optionId == OID_CancelAllSchedules
        Bool confirm = ShowMessage("Cancel all scheduled meetings?", true, "Yes", "No")
        If confirm && Core != None && Core.Schedule != None
            Core.Schedule.CancelAllSchedules()
            ForcePageReset()
        EndIf

    ElseIf IsScheduleCancelOption(optionId)
        ; Handled inside IsScheduleCancelOption via side-effect

    ElseIf optionId == OID_DebugMode
        If IntelEngine_DebugMode != None
            Float current = IntelEngine_DebugMode.GetValue()
            If current > 0
                IntelEngine_DebugMode.SetValue(0)
                SetToggleOptionValue(OID_DebugMode, false)
            Else
                IntelEngine_DebugMode.SetValue(1)
                SetToggleOptionValue(OID_DebugMode, true)
            EndIf
        EndIf

    ElseIf optionId == OID_TravelConfirmMode
        Int current = StorageUtil.GetIntValue(Game.GetPlayer(), "Intel_TaskConfirmPrompt")
        If current > 0
            StorageUtil.SetIntValue(Game.GetPlayer(), "Intel_TaskConfirmPrompt", 0)
            SetToggleOptionValue(OID_TravelConfirmMode, false)
        Else
            StorageUtil.SetIntValue(Game.GetPlayer(), "Intel_TaskConfirmPrompt", 1)
            SetToggleOptionValue(OID_TravelConfirmMode, true)
        EndIf

    ElseIf optionId == OID_DeliveryReportBack
        Int current = StorageUtil.GetIntValue(Game.GetPlayer(), "Intel_DeliveryReportBack")
        If current > 0
            StorageUtil.SetIntValue(Game.GetPlayer(), "Intel_DeliveryReportBack", 0)
            SetToggleOptionValue(OID_DeliveryReportBack, false)
        Else
            StorageUtil.SetIntValue(Game.GetPlayer(), "Intel_DeliveryReportBack", 1)
            SetToggleOptionValue(OID_DeliveryReportBack, true)
        EndIf

    EndIf
EndEvent

Event OnOptionSliderOpen(Int optionId)
    If optionId == OID_MaxTasks
        SetSliderDialogStartValue(IntelEngine_MaxConcurrentTasks.GetValue())
        SetSliderDialogDefaultValue(5.0)
        SetSliderDialogRange(1.0, 5.0)
        SetSliderDialogInterval(1.0)
    ElseIf optionId == OID_DefaultWaitHours
        SetSliderDialogStartValue(IntelEngine_DefaultWaitHours.GetValue())
        SetSliderDialogDefaultValue(48.0)
        SetSliderDialogRange(6.0, 168.0)
        SetSliderDialogInterval(1.0)
    ElseIf optionId == OID_MeetingTimeoutHours
        SetSliderDialogStartValue(StorageUtil.GetFloatValue(Game.GetPlayer(), "Intel_MeetingTimeoutHours", 3.0))
        SetSliderDialogDefaultValue(3.0)
        SetSliderDialogRange(1.0, 12.0)
        SetSliderDialogInterval(0.5)
    ElseIf optionId == OID_MeetingGracePeriod
        Float currentValue = 0.5
        If Core != None
            currentValue = Core.MeetingGracePeriod
        EndIf
        SetSliderDialogStartValue(currentValue)
        SetSliderDialogDefaultValue(0.5)
        SetSliderDialogRange(0.0, 2.0)
        SetSliderDialogInterval(0.1)
    EndIf
EndEvent

Event OnOptionSliderAccept(Int optionId, Float sliderValue)
    If optionId == OID_MaxTasks
        IntelEngine_MaxConcurrentTasks.SetValue(sliderValue)
        SetSliderOptionValue(OID_MaxTasks, sliderValue, "{0}")
    ElseIf optionId == OID_DefaultWaitHours
        IntelEngine_DefaultWaitHours.SetValue(sliderValue)
        SetSliderOptionValue(OID_DefaultWaitHours, sliderValue, "{0}")
    ElseIf optionId == OID_MeetingTimeoutHours
        StorageUtil.SetFloatValue(Game.GetPlayer(), "Intel_MeetingTimeoutHours", sliderValue)
        SetSliderOptionValue(OID_MeetingTimeoutHours, sliderValue, "{1}")
    ElseIf optionId == OID_MeetingGracePeriod
        If Core != None
            Core.MeetingGracePeriod = sliderValue
        EndIf
        SetSliderOptionValue(OID_MeetingGracePeriod, sliderValue, "{1}")
    EndIf
EndEvent

Event OnOptionHighlight(Int optionId)
    If optionId == OID_DebugMode
        SetInfoText("Enable debug notifications and logging.")
    ElseIf optionId == OID_MaxTasks
        SetInfoText("Maximum number of NPCs that can be on tasks at once.")
    ElseIf optionId == OID_DefaultWaitHours
        SetInfoText("How many game hours NPCs wait at travel destinations before returning home. Does not affect scheduled meetings (those use Meeting Timeout).")
    ElseIf optionId == OID_ResetAllTasks
        SetInfoText("Force reset all active tasks. NPCs will return to their normal routines.")
    ElseIf optionId == OID_TravelConfirmMode
        SetInfoText("When enabled, a prompt appears before an NPC starts a task. You can Allow, Deny, or Deny Silently.")
    ElseIf optionId == OID_DeliveryReportBack
        SetInfoText("When enabled, messengers return to you after delivering a message off-screen and report back.")
    ElseIf optionId == OID_MeetingTimeoutHours
        SetInfoText("How long an NPC waits at the meeting spot after the scheduled time before giving up. If you're later than this, the meeting is cancelled.")
    ElseIf optionId == OID_MeetingGracePeriod
        SetInfoText("Arrival tolerance for meetings (±hours). Handles Dynamic Time Scaling mods. Default 0.5 (30 minutes). Set higher if using variable timescales.")
    ElseIf optionId == OID_CancelAllSchedules
        SetInfoText("Cancel all scheduled meetings and tasks.")
    EndIf
EndEvent

; =============================================================================
; UTILITY
; =============================================================================

Bool Function IsScheduleCancelOption(Int optionId)
    {Check if optionId matches a schedule cancel button, and handle it if so}
    If Core == None || Core.Schedule == None
        Return false
    EndIf

    Form mcmForm = Self as Form
    Int i = 0
    While i < 10
        Int cancelOID = StorageUtil.GetIntValue(mcmForm, "MCM_CancelOID_" + i)
        If cancelOID == optionId && cancelOID != 0
            String display = Core.Schedule.GetScheduleDisplay(i)
            If display != "Empty"
                Bool confirm = ShowMessage("Cancel scheduled task?\n" + display, true, "Yes", "No")
                If confirm
                    Core.Schedule.ClearScheduleSlot(i)
                    ForcePageReset()
                EndIf
            EndIf
            Return true
        EndIf
        i += 1
    EndWhile
    Return false
EndFunction

Function ClearSlotWithConfirm(Int slot)
    Core.DebugMsg("MCM ClearSlotWithConfirm called for slot " + slot)
    If Core == None
        Debug.Trace("IntelEngine MCM: Core is None in ClearSlotWithConfirm")
        Return
    EndIf

    String status = Core.GetSlotStatus(slot)
    Core.DebugMsg("MCM ClearSlot " + slot + " status: " + status)
    If status == "Empty"
        Return
    EndIf

    Bool confirm = ShowMessage("Clear task in slot " + slot + "?\n" + status, true, "Yes", "No")
    Core.DebugMsg("MCM ClearSlot " + slot + " confirm: " + confirm)
    If confirm
        Core.DebugMsg("MCM ClearSlot " + slot + " calling ClearSlot now")
        ; Mark as cancelled so it doesn't appear in task history
        ReferenceAlias slotAlias = Core.GetAgentAlias(slot)
        If slotAlias
            Actor agent = slotAlias.GetActorReference()
            If agent
                StorageUtil.SetStringValue(agent, "Intel_Result", "cancelled")
            EndIf
        EndIf
        Core.ClearSlot(slot, true)
        Core.DebugMsg("MCM ClearSlot " + slot + " ClearSlot returned, state now: " + Core.SlotStates[slot])
        Debug.Notification("IntelEngine: Slot " + slot + " cleared")
        ForcePageReset()
    EndIf
EndFunction
