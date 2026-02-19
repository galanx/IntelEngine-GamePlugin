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
GlobalVariable Property IntelEngine_StoryEngineEnabled Auto
GlobalVariable Property IntelEngine_StoryEngineInterval Auto
GlobalVariable Property IntelEngine_StoryEngineCooldown Auto

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
Int OID_LingerReleaseDistance
Int OID_StoryEngineEnabled
Int OID_StoryEngineInterval
Int OID_StoryEngineCooldown
Int OID_StoryForceRestart
Int OID_StoryLongAbsence
Int OID_StoryMaxTravel
Int OID_QuestExpiryDays
Int OID_NPCTickEnabled
Int OID_NPCTickInterval
Int OID_NPCSocialCooldown

; Per-type toggles
Int OID_TypeSeekPlayer
Int OID_TypeInformant
Int OID_TypeRoadEncounter
Int OID_TypeAmbush
Int OID_TypeStalker
Int OID_TypeMessage
Int OID_TypeQuest
Int OID_TypeNPCInteraction
Int OID_TypeNPCGossip

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
            String status = Core.Schedule.GetScheduleStatus(i)
            AddTextOption(display, status)
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

    Bool debugEnabled = Core.IsDebugMode()
    OID_DebugMode = AddToggleOption("Debug Mode", debugEnabled)

    Float maxTasks = Core.GetMaxConcurrentTasks() as Float
    OID_MaxTasks = AddSliderOption("Max Concurrent Tasks", maxTasks, "{0}")

    Float waitHours = Core.GetDefaultWaitHours()
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

    Float lingerDist = 800.0
    If Core != None
        lingerDist = Core.LINGER_RELEASE_DISTANCE
    EndIf
    OID_LingerReleaseDistance = AddSliderOption("NPC Release Distance", lingerDist, "{0}")

    AddEmptyOption()
    AddHeaderOption("Story Engine")

    Bool storyEnabled = Core.IsStoryEngineEnabled()
    OID_StoryEngineEnabled = AddToggleOption("Enable Story Engine", storyEnabled)
    OID_StoryForceRestart = AddTextOption("Force Restart", "GO")

    Float storyInterval = Core.GetStoryEngineInterval()
    OID_StoryEngineInterval = AddSliderOption("Check Interval (hours)", storyInterval, "{1}")

    Float storyCooldown = Core.GetStoryEngineCooldown()
    OID_StoryEngineCooldown = AddSliderOption("Story NPC Cooldown (hours)", storyCooldown, "{0}")

    AddEmptyOption()
    AddHeaderOption("Story Types (DM)")

    Bool tSeek = true
    Bool tInformant = true
    Bool tRoad = true
    Bool tAmbush = true
    Bool tStalker = true
    Bool tMessage = true
    Bool tQuest = true
    If Core != None && Core.StoryEngine != None
        tSeek = Core.StoryEngine.TypeSeekPlayerEnabled
        tInformant = Core.StoryEngine.TypeInformantEnabled
        tRoad = Core.StoryEngine.TypeRoadEncounterEnabled
        tAmbush = Core.StoryEngine.TypeAmbushEnabled
        tStalker = Core.StoryEngine.TypeStalkerEnabled
        tMessage = Core.StoryEngine.TypeMessageEnabled
        tQuest = Core.StoryEngine.TypeQuestEnabled
    EndIf
    OID_TypeSeekPlayer = AddToggleOption("Seek Player", tSeek)
    OID_TypeInformant = AddToggleOption("Informant", tInformant)
    OID_TypeRoadEncounter = AddToggleOption("Road Encounter", tRoad)
    OID_TypeAmbush = AddToggleOption("Ambush", tAmbush)
    OID_TypeStalker = AddToggleOption("Stalker", tStalker)
    OID_TypeMessage = AddToggleOption("Message", tMessage)
    OID_TypeQuest = AddToggleOption("Quest", tQuest)

    AddEmptyOption()
    AddHeaderOption("Story Tuning")

    Float longAbsence = 3.0
    Float maxTravel = 1.0
    If Core != None && Core.StoryEngine != None
        longAbsence = Core.StoryEngine.LongAbsenceDaysConfig
        maxTravel = Core.StoryEngine.MaxTravelDaysConfig
    EndIf
    OID_StoryLongAbsence = AddSliderOption("Long Absence (days)", longAbsence, "{0}")
    OID_StoryMaxTravel = AddSliderOption("Max Travel Time (days)", maxTravel, "{2}")

    Float questExpiry = 1.0
    If Core != None && Core.StoryEngine != None
        questExpiry = Core.StoryEngine.QUEST_EXPIRY_DAYS
    EndIf
    OID_QuestExpiryDays = AddSliderOption("Quest Timeout (days)", questExpiry, "{0}")

    AddEmptyOption()
    AddHeaderOption("NPC Social Life")

    Bool npcTickEnabled = true
    Float npcTickInterval = 1.5
    If Core != None && Core.StoryEngine != None
        npcTickEnabled = Core.StoryEngine.NPCTickEnabled
        npcTickInterval = Core.StoryEngine.NPCTickIntervalHours
    EndIf
    OID_NPCTickEnabled = AddToggleOption("Enable NPC Interactions", npcTickEnabled)

    Bool tInteraction = true
    Bool tGossip = true
    If Core != None && Core.StoryEngine != None
        tInteraction = Core.StoryEngine.TypeNPCInteractionEnabled
        tGossip = Core.StoryEngine.TypeNPCGossipEnabled
    EndIf
    OID_TypeNPCInteraction = AddToggleOption("NPC Interaction", tInteraction)
    OID_TypeNPCGossip = AddToggleOption("NPC Gossip", tGossip)

    OID_NPCTickInterval = AddSliderOption("NPC Interaction Interval (hours)", npcTickInterval, "{1}")

    Float npcSocialCooldown = 24.0
    If Core != None && Core.StoryEngine != None
        npcSocialCooldown = Core.StoryEngine.NPCSocialCooldownHours
    EndIf
    OID_NPCSocialCooldown = AddSliderOption("NPC Social Cooldown (hours)", npcSocialCooldown, "{0}")

EndFunction

; =============================================================================
; OPTION HANDLERS
; =============================================================================

Event OnOptionSelect(Int optionId)
    If optionId == OID_ResetAllTasks
        Bool confirm = ShowMessage("Reset all active tasks? NPCs will return to their normal routines.", true, "Yes", "No")
        If confirm && Core != None
            Core.ForceResetAllSlots()
            ; Also restart story engine monitoring (prevents tick death after reset)
            If Core.StoryEngine != None
                Core.StoryEngine.RestartMonitoring()
            EndIf
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
        Bool newVal = !Core.IsDebugMode()
        Core.SetSettingBool("Intel_MCM_DebugMode", newVal)
        SetToggleOptionValue(OID_DebugMode, newVal)

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

    ElseIf optionId == OID_StoryEngineEnabled
        Bool newVal = !Core.IsStoryEngineEnabled()
        Core.SetSettingBool("Intel_MCM_StoryEnabled", newVal)
        SetToggleOptionValue(OID_StoryEngineEnabled, newVal)
        If Core.StoryEngine != None
            If newVal
                Core.StoryEngine.StartScheduler()
            Else
                Core.StoryEngine.StopScheduler()
            EndIf
        EndIf

    ElseIf optionId == OID_NPCTickEnabled
        If Core != None && Core.StoryEngine != None
            Core.StoryEngine.NPCTickEnabled = !Core.StoryEngine.NPCTickEnabled
            SetToggleOptionValue(OID_NPCTickEnabled, Core.StoryEngine.NPCTickEnabled)
        EndIf

    ElseIf optionId == OID_StoryForceRestart
        If Core != None
            ; Full maintenance: recover script refs, restart ALL monitoring loops,
            ; release stuck linger NPCs, clean expired facts
            Core.Maintenance(false)
            ShowMessage("Story engine restarted. All monitoring loops re-initialized.", false)
        EndIf

    ElseIf Core != None && Core.StoryEngine != None
        If optionId == OID_TypeSeekPlayer
            Core.StoryEngine.TypeSeekPlayerEnabled = !Core.StoryEngine.TypeSeekPlayerEnabled
            SetToggleOptionValue(OID_TypeSeekPlayer, Core.StoryEngine.TypeSeekPlayerEnabled)
        ElseIf optionId == OID_TypeInformant
            Core.StoryEngine.TypeInformantEnabled = !Core.StoryEngine.TypeInformantEnabled
            SetToggleOptionValue(OID_TypeInformant, Core.StoryEngine.TypeInformantEnabled)
        ElseIf optionId == OID_TypeRoadEncounter
            Core.StoryEngine.TypeRoadEncounterEnabled = !Core.StoryEngine.TypeRoadEncounterEnabled
            SetToggleOptionValue(OID_TypeRoadEncounter, Core.StoryEngine.TypeRoadEncounterEnabled)
        ElseIf optionId == OID_TypeAmbush
            Core.StoryEngine.TypeAmbushEnabled = !Core.StoryEngine.TypeAmbushEnabled
            SetToggleOptionValue(OID_TypeAmbush, Core.StoryEngine.TypeAmbushEnabled)
        ElseIf optionId == OID_TypeStalker
            Core.StoryEngine.TypeStalkerEnabled = !Core.StoryEngine.TypeStalkerEnabled
            SetToggleOptionValue(OID_TypeStalker, Core.StoryEngine.TypeStalkerEnabled)
        ElseIf optionId == OID_TypeMessage
            Core.StoryEngine.TypeMessageEnabled = !Core.StoryEngine.TypeMessageEnabled
            SetToggleOptionValue(OID_TypeMessage, Core.StoryEngine.TypeMessageEnabled)
        ElseIf optionId == OID_TypeQuest
            Core.StoryEngine.TypeQuestEnabled = !Core.StoryEngine.TypeQuestEnabled
            SetToggleOptionValue(OID_TypeQuest, Core.StoryEngine.TypeQuestEnabled)
        ElseIf optionId == OID_TypeNPCInteraction
            Core.StoryEngine.TypeNPCInteractionEnabled = !Core.StoryEngine.TypeNPCInteractionEnabled
            SetToggleOptionValue(OID_TypeNPCInteraction, Core.StoryEngine.TypeNPCInteractionEnabled)
        ElseIf optionId == OID_TypeNPCGossip
            Core.StoryEngine.TypeNPCGossipEnabled = !Core.StoryEngine.TypeNPCGossipEnabled
            SetToggleOptionValue(OID_TypeNPCGossip, Core.StoryEngine.TypeNPCGossipEnabled)
        EndIf

    EndIf
EndEvent

Event OnOptionSliderOpen(Int optionId)
    If optionId == OID_MaxTasks
        SetSliderDialogStartValue(Core.GetMaxConcurrentTasks() as Float)
        SetSliderDialogDefaultValue(5.0)
        SetSliderDialogRange(1.0, 5.0)
        SetSliderDialogInterval(1.0)
    ElseIf optionId == OID_DefaultWaitHours
        SetSliderDialogStartValue(Core.GetDefaultWaitHours())
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
    ElseIf optionId == OID_LingerReleaseDistance
        Float currentValue = 800.0
        If Core != None
            currentValue = Core.LINGER_RELEASE_DISTANCE
        EndIf
        SetSliderDialogStartValue(currentValue)
        SetSliderDialogDefaultValue(800.0)
        SetSliderDialogRange(200.0, 2000.0)
        SetSliderDialogInterval(100.0)
    ElseIf optionId == OID_StoryEngineInterval
        SetSliderDialogStartValue(Core.GetStoryEngineInterval())
        SetSliderDialogDefaultValue(2.0)
        SetSliderDialogRange(0.5, 12.0)
        SetSliderDialogInterval(0.5)
    ElseIf optionId == OID_StoryEngineCooldown
        SetSliderDialogStartValue(Core.GetStoryEngineCooldown())
        SetSliderDialogDefaultValue(24.0)
        SetSliderDialogRange(6.0, 72.0)
        SetSliderDialogInterval(6.0)
    ElseIf optionId == OID_StoryLongAbsence
        Float currentValue = 3.0
        If Core != None && Core.StoryEngine != None
            currentValue = Core.StoryEngine.LongAbsenceDaysConfig
        EndIf
        SetSliderDialogStartValue(currentValue)
        SetSliderDialogDefaultValue(3.0)
        SetSliderDialogRange(1.0, 14.0)
        SetSliderDialogInterval(1.0)
    ElseIf optionId == OID_StoryMaxTravel
        Float currentValue = 1.0
        If Core != None && Core.StoryEngine != None
            currentValue = Core.StoryEngine.MaxTravelDaysConfig
        EndIf
        SetSliderDialogStartValue(currentValue)
        SetSliderDialogDefaultValue(1.0)
        SetSliderDialogRange(0.25, 3.0)
        SetSliderDialogInterval(0.25)
    ElseIf optionId == OID_QuestExpiryDays
        Float currentValue = 1.0
        If Core != None && Core.StoryEngine != None
            currentValue = Core.StoryEngine.QUEST_EXPIRY_DAYS
        EndIf
        SetSliderDialogStartValue(currentValue)
        SetSliderDialogDefaultValue(1.0)
        SetSliderDialogRange(1.0, 30.0)
        SetSliderDialogInterval(1.0)
    ElseIf optionId == OID_NPCTickInterval
        Float currentValue = 1.5
        If Core != None && Core.StoryEngine != None
            currentValue = Core.StoryEngine.NPCTickIntervalHours
        EndIf
        SetSliderDialogStartValue(currentValue)
        SetSliderDialogDefaultValue(1.5)
        SetSliderDialogRange(0.5, 6.0)
        SetSliderDialogInterval(0.5)
    ElseIf optionId == OID_NPCSocialCooldown
        Float currentValue = 24.0
        If Core != None && Core.StoryEngine != None
            currentValue = Core.StoryEngine.NPCSocialCooldownHours
        EndIf
        SetSliderDialogStartValue(currentValue)
        SetSliderDialogDefaultValue(24.0)
        SetSliderDialogRange(6.0, 72.0)
        SetSliderDialogInterval(6.0)
    EndIf
EndEvent

Event OnOptionSliderAccept(Int optionId, Float sliderValue)
    If optionId == OID_MaxTasks
        Core.SetSettingFloat("Intel_MCM_MaxTasks", sliderValue)
        SetSliderOptionValue(OID_MaxTasks, sliderValue, "{0}")
    ElseIf optionId == OID_DefaultWaitHours
        Core.SetSettingFloat("Intel_MCM_DefaultWaitHours", sliderValue)
        SetSliderOptionValue(OID_DefaultWaitHours, sliderValue, "{0}")
    ElseIf optionId == OID_MeetingTimeoutHours
        StorageUtil.SetFloatValue(Game.GetPlayer(), "Intel_MeetingTimeoutHours", sliderValue)
        SetSliderOptionValue(OID_MeetingTimeoutHours, sliderValue, "{1}")
    ElseIf optionId == OID_MeetingGracePeriod
        If Core != None
            Core.MeetingGracePeriod = sliderValue
        EndIf
        SetSliderOptionValue(OID_MeetingGracePeriod, sliderValue, "{1}")
    ElseIf optionId == OID_LingerReleaseDistance
        If Core != None
            Core.LINGER_RELEASE_DISTANCE = sliderValue
        EndIf
        SetSliderOptionValue(OID_LingerReleaseDistance, sliderValue, "{0}")
    ElseIf optionId == OID_StoryEngineInterval
        Core.SetSettingFloat("Intel_MCM_StoryInterval", sliderValue)
        SetSliderOptionValue(OID_StoryEngineInterval, sliderValue, "{1}")
        ; Restart scheduler so the new interval takes effect immediately
        If Core != None && Core.StoryEngine != None
            Core.StoryEngine.StartScheduler()
        EndIf
    ElseIf optionId == OID_StoryEngineCooldown
        Core.SetSettingFloat("Intel_MCM_StoryCooldown", sliderValue)
        SetSliderOptionValue(OID_StoryEngineCooldown, sliderValue, "{0}")
    ElseIf optionId == OID_StoryLongAbsence
        If Core != None && Core.StoryEngine != None
            Core.StoryEngine.LongAbsenceDaysConfig = sliderValue
        EndIf
        SetSliderOptionValue(OID_StoryLongAbsence, sliderValue, "{0}")
    ElseIf optionId == OID_StoryMaxTravel
        If Core != None && Core.StoryEngine != None
            Core.StoryEngine.MaxTravelDaysConfig = sliderValue
        EndIf
        SetSliderOptionValue(OID_StoryMaxTravel, sliderValue, "{2}")
    ElseIf optionId == OID_QuestExpiryDays
        If Core != None && Core.StoryEngine != None
            Core.StoryEngine.QUEST_EXPIRY_DAYS = sliderValue
        EndIf
        SetSliderOptionValue(OID_QuestExpiryDays, sliderValue, "{0}")
    ElseIf optionId == OID_NPCTickInterval
        If Core != None && Core.StoryEngine != None
            Core.StoryEngine.NPCTickIntervalHours = sliderValue
        EndIf
        SetSliderOptionValue(OID_NPCTickInterval, sliderValue, "{1}")
    ElseIf optionId == OID_NPCSocialCooldown
        If Core != None && Core.StoryEngine != None
            Core.StoryEngine.NPCSocialCooldownHours = sliderValue
        EndIf
        SetSliderOptionValue(OID_NPCSocialCooldown, sliderValue, "{0}")
    EndIf
EndEvent

Event OnOptionInputOpen(Int optionId)
EndEvent

Event OnOptionInputAccept(Int optionId, String inputValue)
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
    ElseIf optionId == OID_LingerReleaseDistance
        SetInfoText("How far (game units) you must walk away before an NPC stops lingering and returns to normal. Affects all systems: travel arrivals, task completions, story encounters. Default 800.")
    ElseIf optionId == OID_CancelAllSchedules
        SetInfoText("Cancel all scheduled meetings and tasks.")
    ElseIf optionId == OID_StoryEngineEnabled
        SetInfoText("Enable the Story Engine. NPCs with unfinished business will autonomously seek you out based on your shared history.")
    ElseIf optionId == OID_StoryEngineInterval
        SetInfoText("How often (in game hours) the Story Engine checks for NPCs with compelling reasons to find you.")
    ElseIf optionId == OID_StoryEngineCooldown
        SetInfoText("How long (game hours) a picked NPC's priority stays reduced. Higher = more variety in NPC picks, lower = favorites return sooner.")
    ElseIf optionId == OID_StoryLongAbsence
        SetInfoText("Minimum game days since your last interaction with an NPC before the Story Engine considers them as a candidate.")
    ElseIf optionId == OID_StoryMaxTravel
        SetInfoText("Maximum game days an NPC will travel before being teleported to the target. Lower = faster delivery, higher = more realistic.")
    ElseIf optionId == OID_QuestExpiryDays
        SetInfoText("How many in-game days before an unfinished dynamic quest auto-expires. The quest giver remembers you never showed up. Default 1.")
    ElseIf optionId == OID_TypeSeekPlayer
        SetInfoText("NPC travels to find you based on shared history or unfinished business.")
    ElseIf optionId == OID_TypeInformant
        SetInfoText("NPC approaches you to relay gossip about a third party.")
    ElseIf optionId == OID_TypeRoadEncounter
        SetInfoText("NPC appears on the road nearby, coincidentally traveling. Exterior only.")
    ElseIf optionId == OID_TypeAmbush
        SetInfoText("Hostile NPC stalks and attacks you. Requires combat class and hostile memories.")
    ElseIf optionId == OID_TypeStalker
        SetInfoText("Romantic or jealous NPC secretly follows you. Exterior only.")
    ElseIf optionId == OID_TypeMessage
        SetInfoText("NPC delivers a verbal message, optionally with a meeting invitation.")
    ElseIf optionId == OID_TypeQuest
        SetInfoText("NPC asks you to kill enemies at a location. Courier or guide delivery.")
    ElseIf optionId == OID_TypeNPCInteraction
        SetInfoText("Two NPCs interact: argue, trade, train, bond. Visible or off-screen.")
    ElseIf optionId == OID_TypeNPCGossip
        SetInfoText("One NPC shares a rumor about a third party with another NPC.")
    ElseIf optionId == OID_StoryForceRestart
        SetInfoText("Force restart all monitoring loops. Use if story ticks seem frozen or NPCs stop acting.")
    ElseIf optionId == OID_NPCTickEnabled
        SetInfoText("Enable autonomous NPC-to-NPC interactions. NPCs gossip, argue, trade, and socialize independently.")
    ElseIf optionId == OID_NPCTickInterval
        SetInfoText("How often (game hours) the NPC social system checks for NPC-to-NPC interactions.")
    ElseIf optionId == OID_NPCSocialCooldown
        SetInfoText("How long (game hours) before an NPC can be picked for another social interaction. Separate from story cooldown.")
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
