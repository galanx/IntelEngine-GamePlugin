Scriptname IntelEngine_MCM extends SKI_ConfigBase
{
    IntelEngine MCM Menu

    Provides configuration and management options:
    - View active task status
    - Clear individual tasks or all tasks
    - Toggle debug mode
    - Adjust concurrent task limits
    - Clear stored messages

    Requires: SkyUI (https://www.nexusmods.com/skyrimspecialedition/mods/12604)
}

; Every word the menu shows is a SkyUI translation key ("$IntelEngine_..."), so that it reads in the game's
; language: the words are in Interface/Translations/IntelEngine_<LANGUAGE>.txt (the game repository), one line a
; key; the English file is the source of the names (RunSettingNamesCheck reads them there, and
; RunMcmTranslationCheck holds every language to the English keys and to the column's width). A key written with
; braces carries values: "$IntelEngine_Slot{" + slot + "}" is the line "$IntelEngine_Slot{}" with the value put in
; its {}. SkyUI fills the {} in order, and it looks a value up only when the whole value is a key without braces:
; "$IntelEngine_HoldInfo{$IntelEngine_TypeSeek}{$IntelEngine_HoldNone}" works, a key with values inside another
; key's braces does not (SkyUI's Translator.translateNested pairs each { with the next }). The translations must
; keep the order of the values.

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
Int OID_ConfirmGoToLocation
Int OID_ConfirmDeliverMessage
Int OID_ConfirmFetchPerson
Int OID_ConfirmEscortTarget
Int OID_ConfirmSearchForActor
Int OID_ConfirmScheduleFetch
Int OID_ConfirmScheduleDelivery
Int OID_ConfirmScheduleMeeting
Int OID_SkipFollowerGoToLocation
Int OID_SkipFollowerDeliverMessage
Int OID_SkipFollowerFetchPerson
Int OID_SkipFollowerEscortTarget
Int OID_SkipFollowerSearchForActor
Int OID_SkipFollowerScheduleFetch
Int OID_SkipFollowerScheduleDelivery
Int OID_SkipFollowerScheduleMeeting
Int OID_AutoBioEnabled
Int OID_AutoBioThreshold
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
Int OID_AllowStuckTeleport
Int OID_DangerAllowAll
Int OID_DangerBlockCivilians
Int OID_DangerFollowersOnly
Int OID_DangerBlockAll
; 4.0 living world
Int OID_LWLevel
Int OID_LWInterruptions
Int OID_LWQuestNpcs
Int OID_LWPacing
Int OID_LWWaitDays
Int OID_LWLifeDays
Int OID_LWSkippedTime
Int OID_HomeAllowAll
Int OID_HomeBlockCivilians
Int OID_HomeFollowersOnly
Int OID_HomeBlockAll
Int OID_QuestExpiryDays
Int OID_NPCTickEnabled
Int OID_NPCTickInterval
Int OID_NPCSocialCooldown

; Per-type toggles
Int OID_TypeSeekPlayer
Int OID_TypeInformant
Int OID_TypeRoadEncounter
Int OID_TypeAmbush
Int OID_TypeFactionAmbush
Int OID_TypeStalker
Int OID_TypeMessage
Int OID_TypeQuest
Int OID_TypeNPCInteraction
Int OID_TypeNPCGossip

; Quest sub-type toggles
Int OID_QuestCombat
Int OID_QuestRescue
Int OID_QuestFindItem
Int OID_QuestFactionCombat
Int OID_QuestFactionRescue
Int OID_QuestFactionBattle
Int OID_QuestAllowDeath

; Faction Politics
Int OID_PoliticsEnabled
Int OID_PoliticsTickInterval
Int OID_PEIntegration
Int OID_PEReactions

; Hold Restriction page (per-story-type radio groups)
Int OID_HoldSeekNone
Int OID_HoldSeekCivilian
Int OID_HoldSeekExceptFollower
Int OID_HoldSeekAll
Int OID_HoldSeekLocalCivilian
Int OID_HoldSeekLocalExceptFollower
Int OID_HoldSeekLocalAll
Int OID_HoldInformantNone
Int OID_HoldInformantCivilian
Int OID_HoldInformantExceptFollower
Int OID_HoldInformantAll
Int OID_HoldInformantLocalCivilian
Int OID_HoldInformantLocalExceptFollower
Int OID_HoldInformantLocalAll
Int OID_HoldRoadNone
Int OID_HoldRoadCivilian
Int OID_HoldRoadExceptFollower
Int OID_HoldRoadAll
Int OID_HoldRoadLocalCivilian
Int OID_HoldRoadLocalExceptFollower
Int OID_HoldRoadLocalAll
Int OID_HoldAmbushNone
Int OID_HoldAmbushCivilian
Int OID_HoldAmbushExceptFollower
Int OID_HoldAmbushAll
Int OID_HoldAmbushLocalCivilian
Int OID_HoldAmbushLocalExceptFollower
Int OID_HoldAmbushLocalAll
Int OID_HoldStalkerNone
Int OID_HoldStalkerCivilian
Int OID_HoldStalkerExceptFollower
Int OID_HoldStalkerAll
Int OID_HoldStalkerLocalCivilian
Int OID_HoldStalkerLocalExceptFollower
Int OID_HoldStalkerLocalAll
Int OID_HoldMessageNone
Int OID_HoldMessageCivilian
Int OID_HoldMessageExceptFollower
Int OID_HoldMessageAll
Int OID_HoldMessageLocalCivilian
Int OID_HoldMessageLocalExceptFollower
Int OID_HoldMessageLocalAll
Int OID_HoldQuestNone
Int OID_HoldQuestCivilian
Int OID_HoldQuestExceptFollower
Int OID_HoldQuestAll
Int OID_HoldQuestLocalCivilian
Int OID_HoldQuestLocalExceptFollower
Int OID_HoldQuestLocalAll


; =============================================================================
; SKI_ConfigBase OVERRIDES
; =============================================================================

String Function GetCustomControl(Int optionId)
    Return ""
EndFunction

Int Function GetVersion()
    ; 5: the page names became translation keys (EnsurePages puts a save's English names right).
    Return 5
EndFunction

Event OnConfigInit()
    Debug.Trace("IntelEngine MCM: OnConfigInit fired")
    ModName = "IntelEngine"
    EnsurePages()
EndEvent

Event OnVersionUpdate(Int newVersion)
    Debug.Trace("IntelEngine MCM: OnVersionUpdate fired, newVersion=" + newVersion)
    EnsurePages()
EndEvent

Event OnConfigOpen()
    EnsurePages()
EndEvent

Event OnConfigClose()
    ; What was changed here also goes to SkyrimNet's settings file, for its plugin settings page.
    If Core
        Core.SyncSettingsToPluginConfig()
    EndIf
EndEvent

Function EnsurePages()
    {The page names are translation keys. A save made before they were holds the English names ("Active Tasks"),
     which OnPageReset no longer answers to: they are replaced here. OnConfigOpen runs before SkyUI is handed the
     names, so the menu never shows the old ones.}
    If Pages.Length != 4 || Pages[0] != "$IntelEngine_ActiveTasks"
        Pages = new String[4]
        Pages[0] = "$IntelEngine_ActiveTasks"
        Pages[1] = "$IntelEngine_ScheduledTasks"
        Pages[2] = "$IntelEngine_Settings"
        Pages[3] = "$IntelEngine_HoldRestrictions"
        Debug.Trace("IntelEngine MCM: Pages rebuilt to 4")
    EndIf
EndFunction

Event OnPageReset(String page)
    Debug.Trace("IntelEngine MCM: OnPageReset page='" + page + "' Pages.Length=" + Pages.Length)
    SetCursorFillMode(TOP_TO_BOTTOM)

    ; Clear schedule cancel OIDs when NOT on the scheduled page.
    ; SkyUI reuses OID numbers across pages, so stale cancel OIDs
    ; stored in StorageUtil can collide with toggles on other pages
    ; (e.g. OID_TypeMessage on Settings == cancel OID from Scheduled).
    If page != "$IntelEngine_ScheduledTasks"
        Form mcmForm = Self as Form
        Int ci = 0
        While ci < 10
            StorageUtil.UnsetIntValue(mcmForm, "MCM_CancelOID_" + ci)
            ci += 1
        EndWhile
    EndIf

    If page == "" || page == "$IntelEngine_ActiveTasks"
        ShowStatusPage()
    ElseIf page == "$IntelEngine_ScheduledTasks"
        ShowScheduledPage()
    ElseIf page == "$IntelEngine_Settings"
        ShowSettingsPage()
    ElseIf page == "$IntelEngine_HoldRestrictions"
        ShowHoldRestrictionsPage()
    EndIf
EndEvent

; =============================================================================
; STATUS PAGE
; =============================================================================

Function ShowStatusPage()
    SetCursorFillMode(TOP_TO_BOTTOM)
    SetCursorPosition(0)

    AddHeaderOption("$IntelEngine_ActiveTasks")
    AddEmptyOption()

    ; Show each slot status
    OID_Slot0Status = AddSlotRow(0)
    OID_ClearSlot0 = AddTextOption(SlotWhere(0), "$IntelEngine_Clear", GetClearFlag(0))

    OID_Slot1Status = AddSlotRow(1)
    OID_ClearSlot1 = AddTextOption(SlotWhere(1), "$IntelEngine_Clear", GetClearFlag(1))

    OID_Slot2Status = AddSlotRow(2)
    OID_ClearSlot2 = AddTextOption(SlotWhere(2), "$IntelEngine_Clear", GetClearFlag(2))

    OID_Slot3Status = AddSlotRow(3)
    OID_ClearSlot3 = AddTextOption(SlotWhere(3), "$IntelEngine_Clear", GetClearFlag(3))

    OID_Slot4Status = AddSlotRow(4)
    OID_ClearSlot4 = AddTextOption(SlotWhere(4), "$IntelEngine_Clear", GetClearFlag(4))

    AddEmptyOption()
    AddHeaderOption("$IntelEngine_Actions")
    OID_ResetAllTasks = AddTextOption("$IntelEngine_ResetAllTasks", "$IntelEngine_Click")
EndFunction

Int Function AddSlotRow(Int slot)
    {One row of the Active Tasks page. A slot in use shows who and what as the row's own text with nothing on the
     right: written as a value it was set in capitals from the right edge and lay over the "Slot N:" label
     ("SINMIR: TRAVELING TO DRUNKEN HUNTSM" over "Slot 0:", seen in the game 2026-11-22).}
    String status = GetSlotDisplay(slot)
    String word = SlotWord(status)
    If word != ""
        Return AddTextOption("$IntelEngine_Slot{" + slot + "}", word)
    EndIf
    Return AddTextOption(TaskRow(status), "")
EndFunction

String Function SlotWhere(Int slot)
    {Where a busy slot's NPC is ("(near The Bannered Mare)"), shown beside its Clear button: on the row above it
     ran past the column's edge and was cut.}
    String status = GetSlotDisplay(slot)
    If SlotWord(status) != ""
        Return ""
    EndIf
    String place = TaskPlace(status)
    If place == ""
        Return ""
    EndIf
    Return "$IntelEngine_SlotNear{" + PlaceValue(place) + "}"
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

String Function SlotWord(String status)
    {The key of an idle slot's word (Core.GetSlotStatus answers "Empty", "Invalid" or "Unknown"), or "" for a slot
     in use.}
    If status == "Empty"
        Return "$IntelEngine_SlotEmpty"
    ElseIf status == "Invalid"
        Return "$IntelEngine_SlotInvalid"
    ElseIf status == "Unknown"
        Return "$IntelEngine_SlotUnknown"
    ElseIf status == "Error: No Core"
        Return "$IntelEngine_NoCore"
    EndIf
    Return ""
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

; ---- A slot in use, in the menu's language ----
; Core.GetSlotStatus gives a busy slot as the DLL words it (GetSlotStatusNative, Papyrus.cpp): who, ": ", one of
; thirteen phrases (ten of them followed by a name), and " (near <cell>)" when the NPC is in a named cell or
; "[IN COMBAT]". The functions below take that apart and give the phrase's key with who and the name as its
; values; words they do not know (the DLL's wording changed) are shown as they came.

String Function TaskWho(String status)
    {Who a busy slot's text is about: what stands before its first ": ".}
    Int colon = StringUtil.Find(status, ": ")
    If colon <= 0
        Return ""
    EndIf
    Return StringUtil.Substring(status, 0, colon)
EndFunction

String Function TaskWhat(String status)
    {What a busy slot's NPC is doing: the text after who, without where.}
    String what = status
    Int colon = StringUtil.Find(status, ": ")
    If colon > 0
        what = StringUtil.Substring(status, colon + 2)
    EndIf
    Int near = StringUtil.Find(what, " (near ")
    If near >= 0
        what = StringUtil.Substring(what, 0, near)
    EndIf
    Return what
EndFunction

String Function TaskPlace(String status)
    {Where a busy slot's NPC is: the cell's name (or "[IN COMBAT]") in its " (near ...)", or "".}
    Int near = StringUtil.Find(status, " (near ")
    If near < 0
        Return ""
    EndIf
    Int chars = StringUtil.GetLength(status) - near - 8
    If chars <= 0
        Return ""
    EndIf
    Return StringUtil.Substring(status, near + 7, chars)
EndFunction

String Function PlaceValue(String place)
    {A place as the value of a key: the cell's name, or the key of the words for a fight.}
    If place == "[IN COMBAT]"
        Return "$IntelEngine_InCombat"
    EndIf
    Return place
EndFunction

String[] Function TaskStarts()
    {How GetSlotStatusNative begins each of its phrases, in the order of TaskKey: the first ten go on with a name,
     the last three stand alone.}
    String[] starts = new String[13]
    starts[0] = "Going to fetch "
    starts[1] = "Fetching "
    starts[2] = "Returning with "
    starts[3] = "Going to deliver a message to "
    starts[4] = "Delivering message to "
    starts[5] = "Searching for "
    starts[6] = "Going to escort "
    starts[7] = "Escorting "
    starts[8] = "Traveling to "
    starts[9] = "Going to visit "
    starts[10] = "Returning after delivering message"
    starts[11] = "Seeking out the player"
    starts[12] = "On a task"
    Return starts
EndFunction

Int Function TaskPhrase(String what)
    {Which of the DLL's phrases a slot's "what" is (TaskStarts), or -1.}
    String[] starts = TaskStarts()
    Int i = 0
    While i < 13
        If (i < 10 && StringUtil.Find(what, starts[i]) == 0) || what == starts[i]
            Return i
        EndIf
        i += 1
    EndWhile
    Return -1
EndFunction

String Function TaskName(String what, Int phrase)
    {The name after a phrase that takes one (phrase 0 to 9).}
    String[] starts = TaskStarts()
    Return StringUtil.Substring(what, StringUtil.GetLength(starts[phrase]))
EndFunction

String Function TaskKey(Int phrase, Int variant)
    {The key of one of the DLL's slot phrases: variant 0 the row (who, then "Traveling to" and a name), 1 the
     question before clearing it, 2 that question with where the NPC is.}
    String[] keys = new String[39]
    keys[0] = "$IntelEngine_TaskGoingToFetch"
    keys[1] = "$IntelEngine_ClearGoingToFetch"
    keys[2] = "$IntelEngine_ClearGoingToFetchNear"
    keys[3] = "$IntelEngine_TaskFetching"
    keys[4] = "$IntelEngine_ClearFetching"
    keys[5] = "$IntelEngine_ClearFetchingNear"
    keys[6] = "$IntelEngine_TaskReturningWith"
    keys[7] = "$IntelEngine_ClearReturningWith"
    keys[8] = "$IntelEngine_ClearReturningWithNear"
    keys[9] = "$IntelEngine_TaskGoingToDeliver"
    keys[10] = "$IntelEngine_ClearGoingToDeliver"
    keys[11] = "$IntelEngine_ClearGoingToDeliverNear"
    keys[12] = "$IntelEngine_TaskDelivering"
    keys[13] = "$IntelEngine_ClearDelivering"
    keys[14] = "$IntelEngine_ClearDeliveringNear"
    keys[15] = "$IntelEngine_TaskSearching"
    keys[16] = "$IntelEngine_ClearSearching"
    keys[17] = "$IntelEngine_ClearSearchingNear"
    keys[18] = "$IntelEngine_TaskGoingToEscort"
    keys[19] = "$IntelEngine_ClearGoingToEscort"
    keys[20] = "$IntelEngine_ClearGoingToEscortNear"
    keys[21] = "$IntelEngine_TaskEscorting"
    keys[22] = "$IntelEngine_ClearEscorting"
    keys[23] = "$IntelEngine_ClearEscortingNear"
    keys[24] = "$IntelEngine_TaskTraveling"
    keys[25] = "$IntelEngine_ClearTraveling"
    keys[26] = "$IntelEngine_ClearTravelingNear"
    keys[27] = "$IntelEngine_TaskVisiting"
    keys[28] = "$IntelEngine_ClearVisiting"
    keys[29] = "$IntelEngine_ClearVisitingNear"
    keys[30] = "$IntelEngine_TaskReturned"
    keys[31] = "$IntelEngine_ClearReturned"
    keys[32] = "$IntelEngine_ClearReturnedNear"
    keys[33] = "$IntelEngine_TaskSeekingYou"
    keys[34] = "$IntelEngine_ClearSeekingYou"
    keys[35] = "$IntelEngine_ClearSeekingYouNear"
    keys[36] = "$IntelEngine_TaskOther"
    keys[37] = "$IntelEngine_ClearOther"
    keys[38] = "$IntelEngine_ClearOtherNear"
    Return keys[phrase * 3 + variant]
EndFunction

String Function TaskRow(String status)
    {A busy slot's row: who and what they are doing.}
    String who = TaskWho(status)
    String what = TaskWhat(status)
    Int phrase = TaskPhrase(what)
    If phrase < 0
        If who == ""
            Return what
        EndIf
        Return who + ": " + what
    EndIf
    String row = TaskKey(phrase, 0) + "{" + who + "}"
    If phrase < 10
        row += "{" + TaskName(what, phrase) + "}"
    EndIf
    Return row
EndFunction

String Function ClearQuestion(Int slot, String status)
    {The question before clearing a slot: "Clear task in slot 2?" over the slot's text as its row and SlotWhere
     show it.}
    String who = TaskWho(status)
    String what = TaskWhat(status)
    Int phrase = TaskPhrase(what)
    If who == "" || phrase < 0
        Return "$IntelEngine_ClearSlot{" + slot + "}{" + status + "}"
    EndIf
    String place = TaskPlace(status)
    Int variant = 1
    If place != ""
        variant = 2
    EndIf
    String ask = TaskKey(phrase, variant) + "{" + slot + "}{" + who + "}"
    If phrase < 10
        ask += "{" + TaskName(what, phrase) + "}"
    EndIf
    If place != ""
        ask += "{" + PlaceValue(place) + "}"
    EndIf
    Return ask
EndFunction

; =============================================================================
; SCHEDULED MEETINGS PAGE
; =============================================================================

Function ShowScheduledPage()
    SetCursorFillMode(TOP_TO_BOTTOM)
    SetCursorPosition(0)

    If Core == None || Core.Schedule == None
        AddHeaderOption("$IntelEngine_ScheduledTasks")
        AddTextOption("$IntelEngine_Error", "$IntelEngine_ScheduleNotFound")
        Return
    EndIf

    AddHeaderOption("$IntelEngine_ScheduledTasks")
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
            AddTextOption(ScheduleRow(display, false), ScheduleWhen(status))
            Int cancelOID = AddTextOption("", "$IntelEngine_Cancel")
            StorageUtil.SetIntValue(mcmForm, "MCM_CancelOID_" + i, cancelOID)
            shown += 1
        EndIf
        i += 1
    EndWhile

    If shown == 0
        AddTextOption("$IntelEngine_NoScheduled", "")
    EndIf

    AddEmptyOption()
    AddHeaderOption("$IntelEngine_Actions")

    Int flag = OPTION_FLAG_NONE
    If shown == 0
        flag = OPTION_FLAG_DISABLED
    EndIf
    OID_CancelAllSchedules = AddTextOption("$IntelEngine_CancelAllScheduled", "$IntelEngine_Click", flag)
EndFunction

String Function ScheduleRow(String display, Bool asking)
    {A scheduled task as GetScheduleDisplay gives it ("Lydia @ Whiterun", "Lydia: fetch Ysolda", "Lydia: msg to
     Ysolda"): its row, or (asking) the question before cancelling it. A text without words of its own ("@") is
     shown as it came.}
    Int cut = StringUtil.Find(display, ": fetch ")
    If cut > 0
        If asking
            Return "$IntelEngine_CancelSchedFetch{" + StringUtil.Substring(display, 0, cut) + "}{" + StringUtil.Substring(display, cut + 8) + "}"
        EndIf
        Return "$IntelEngine_SchedFetch{" + StringUtil.Substring(display, 0, cut) + "}{" + StringUtil.Substring(display, cut + 8) + "}"
    EndIf
    cut = StringUtil.Find(display, ": msg to ")
    If cut > 0
        If asking
            Return "$IntelEngine_CancelSchedMessage{" + StringUtil.Substring(display, 0, cut) + "}{" + StringUtil.Substring(display, cut + 9) + "}"
        EndIf
        Return "$IntelEngine_SchedMessage{" + StringUtil.Substring(display, 0, cut) + "}{" + StringUtil.Substring(display, cut + 9) + "}"
    EndIf
    If asking
        Return "$IntelEngine_CancelSched{" + display + "}"
    EndIf
    Return display
EndFunction

String Function ScheduleWhen(String status)
    {When a scheduled task is due, as GetScheduleStatus gives it ("overdue", "in ~5h", "en route, soon", "meeting").}
    If status == "overdue"
        Return "$IntelEngine_SchedOverdue"
    ElseIf status == "very soon"
        Return "$IntelEngine_SchedVerySoon"
    ElseIf status == "en route, overdue"
        Return "$IntelEngine_SchedEnRouteOverdue"
    ElseIf status == "en route, soon"
        Return "$IntelEngine_SchedEnRouteSoon"
    ElseIf status == "meeting"
        Return "$IntelEngine_SchedMeeting"
    EndIf
    Int chars = StringUtil.GetLength(status)
    If chars > 5 && StringUtil.Find(status, "in ~") == 0
        Return "$IntelEngine_SchedInHours{" + StringUtil.Substring(status, 4, chars - 5) + "}"
    ElseIf chars > 12 && StringUtil.Find(status, "en route, ~") == 0
        Return "$IntelEngine_SchedEnRouteHours{" + StringUtil.Substring(status, 11, chars - 12) + "}"
    EndIf
    Return status
EndFunction

; =============================================================================
; SETTINGS PAGE
; =============================================================================

Function ShowSettingsPage()
    SetCursorFillMode(TOP_TO_BOTTOM)
    SetCursorPosition(0)

    AddHeaderOption("$IntelEngine_GeneralSettings")
    AddTextOption("$IntelEngine_ModBy", "Galanx", OPTION_FLAG_DISABLED)

    Bool debugEnabled = Core.IsDebugMode()
    OID_DebugMode = AddToggleOption("$IntelEngine_DebugMessages", debugEnabled)

    Float maxTasks = Core.GetMaxConcurrentTasks() as Float
    OID_MaxTasks = AddSliderOption("$IntelEngine_MaxTasks", maxTasks, "{0}")

    Float waitHours = Core.GetDefaultWaitHours()
    OID_DefaultWaitHours = AddSliderOption("$IntelEngine_DefaultWait", waitHours, "{0}")

    AddEmptyOption()
    AddHeaderOption("$IntelEngine_AskBeforeStarting")
    ; 0=Disabled, 1=Followers only, 2=Everyone
    If Core != None && Core.StoryEngine != None
        OID_ConfirmGoToLocation = AddTextOption("$IntelEngine_GoSomewhere", ConfirmModeLabel(Core.StoryEngine.ConfirmGoToLocation))
        OID_ConfirmFetchPerson = AddTextOption("$IntelEngine_FetchSomeone", ConfirmModeLabel(Core.StoryEngine.ConfirmFetchPerson))
        OID_ConfirmDeliverMessage = AddTextOption("$IntelEngine_DeliverMessage", ConfirmModeLabel(Core.StoryEngine.ConfirmDeliverMessage))
        OID_ConfirmEscortTarget = AddTextOption("$IntelEngine_EscortSomeone", ConfirmModeLabel(Core.StoryEngine.ConfirmEscortTarget))
        OID_ConfirmSearchForActor = AddTextOption("$IntelEngine_SearchSomeone", ConfirmModeLabel(Core.StoryEngine.ConfirmSearchForActor))
        OID_ConfirmScheduleMeeting = AddTextOption("$IntelEngine_ArrangeMeeting", ConfirmModeLabel(Core.StoryEngine.ConfirmScheduleMeeting))
        OID_ConfirmScheduleFetch = AddTextOption("$IntelEngine_FetchLater", ConfirmModeLabel(Core.StoryEngine.ConfirmScheduleFetch))
        OID_ConfirmScheduleDelivery = AddTextOption("$IntelEngine_DeliverLater", ConfirmModeLabel(Core.StoryEngine.ConfirmScheduleDelivery))
    EndIf

    Bool reportBack = StorageUtil.GetIntValue(Game.GetPlayer(), "Intel_DeliveryReportBack") as Bool
    OID_DeliveryReportBack = AddToggleOption("$IntelEngine_ReportBack", reportBack)

    Float meetTimeout = StorageUtil.GetFloatValue(Game.GetPlayer(), "Intel_MeetingTimeoutHours", 5.0)
    OID_MeetingTimeoutHours = AddSliderOption("$IntelEngine_MeetingWait", meetTimeout, "{1}")

    Float gracePeriod = 0.5
    If Core != None
        gracePeriod = Core.MeetingGracePeriod
    EndIf
    OID_MeetingGracePeriod = AddSliderOption("$IntelEngine_OnTimeUntil", gracePeriod, "{1}")

    Float lingerDist = 800.0
    If Core != None
        lingerDist = Core.LINGER_RELEASE_DISTANCE
    EndIf
    OID_LingerReleaseDistance = AddSliderOption("$IntelEngine_VisitEnds", lingerDist, "{0}")

    AddEmptyOption()
    ; The heading and the switch below it are the same key, as they were the same words: in English "Stories" (not
    ; "Story Engine": the story script has the string "Story engine", and Papyrus keeps one spelling per string).
    AddHeaderOption("$IntelEngine_Stories")

    Bool storyEnabled = Core.IsStoryEngineEnabled()
    OID_StoryEngineEnabled = AddToggleOption("$IntelEngine_Stories", storyEnabled)
    OID_StoryForceRestart = AddTextOption("$IntelEngine_ForceRestart", "$IntelEngine_Go")

    Float storyInterval = Core.GetStoryEngineInterval()
    OID_StoryEngineInterval = AddSliderOption("$IntelEngine_CheckInterval", storyInterval, "{1}")

    ; "Story NPC Cooldown" is not offered: the game uses the longer of it and Long Absence (three days by
    ; default), so its 6 to 72 hours changed nothing. Long Absence, under Story Tuning, is the setting.
    ; -1: no option of this page answers to the id.
    OID_StoryEngineCooldown = -1

    AddEmptyOption()
    ; 4.0. Spelled like the heading on SkyrimNet's settings page.
    AddHeaderOption("$IntelEngine_LivingWorld")
    If Core != None && Core.StoryEngine != None
        OID_LWLevel = AddTextOption("$IntelEngine_WorldLevel", LivingWorldLabel(0, Core.StoryEngine.LivingWorldLevel))
        OID_LWInterruptions = AddTextOption("$IntelEngine_Interruptions", LivingWorldLabel(1, Core.StoryEngine.LivingWorldInterruptions))
        OID_LWQuestNpcs = AddTextOption("$IntelEngine_QuestNpcsMove", LivingWorldLabel(2, Core.StoryEngine.LivingWorldQuestNpcs))
        OID_LWPacing = AddTextOption("$IntelEngine_Pacing", LivingWorldLabel(3, Core.StoryEngine.LivingWorldPacing))
        OID_LWSkippedTime = AddToggleOption("$IntelEngine_SkippedTime", Core.StoryEngine.LivingWorldSkippedTime)
        OID_LWWaitDays = AddSliderOption("$IntelEngine_WaitDays", Core.StoryEngine.LivingWorldWaitDays, "{0}")
        OID_LWLifeDays = AddSliderOption("$IntelEngine_LifeDays", Core.StoryEngine.LivingWorldLifeDays, "{0}")
    EndIf

    AddEmptyOption()
    AddHeaderOption("$IntelEngine_DangerPolicy")

    Int dangerPolicy = 1
    If Core != None && Core.StoryEngine != None
        dangerPolicy = Core.StoryEngine.DangerZonePolicy
    EndIf
    OID_DangerAllowAll = AddToggleOption("$IntelEngine_AllowAll", dangerPolicy == 0)
    OID_DangerBlockCivilians = AddToggleOption("$IntelEngine_BlockCivilians", dangerPolicy == 1)
    OID_DangerFollowersOnly = AddToggleOption("$IntelEngine_AllowFollowers", dangerPolicy == 2)
    OID_DangerBlockAll = AddToggleOption("$IntelEngine_BlockAll", dangerPolicy == 3)

    AddEmptyOption()
    AddHeaderOption("$IntelEngine_HomePolicy")

    Int homePolicy = 0
    If Core != None && Core.StoryEngine != None
        homePolicy = Core.StoryEngine.PlayerHomePolicy
    EndIf
    OID_HomeAllowAll = AddToggleOption("$IntelEngine_AllowAll", homePolicy == 0)
    OID_HomeBlockCivilians = AddToggleOption("$IntelEngine_BlockCivilians", homePolicy == 1)
    OID_HomeFollowersOnly = AddToggleOption("$IntelEngine_AllowFollowers", homePolicy == 2)
    OID_HomeBlockAll = AddToggleOption("$IntelEngine_BlockAll", homePolicy == 3)

    ; ---- Right column: Story Types + NPC Social + Tuning ----
    SetCursorPosition(1)

    ; Stored as "skip for followers"; shown the other way round (on = followers can do it), because a column of
    ; switches that are off under "Skip Action for Followers" read as "switched off for my followers".
    AddHeaderOption("$IntelEngine_FollowersCanDo")
    If Core != None && Core.StoryEngine != None
        OID_SkipFollowerGoToLocation = AddToggleOption("$IntelEngine_GoSomewhere", !Core.StoryEngine.SkipFollowerGoToLocation)
        OID_SkipFollowerFetchPerson = AddToggleOption("$IntelEngine_FetchSomeone", !Core.StoryEngine.SkipFollowerFetchPerson)
        OID_SkipFollowerDeliverMessage = AddToggleOption("$IntelEngine_DeliverMessage", !Core.StoryEngine.SkipFollowerDeliverMessage)
        OID_SkipFollowerEscortTarget = AddToggleOption("$IntelEngine_EscortSomeone", !Core.StoryEngine.SkipFollowerEscortTarget)
        OID_SkipFollowerSearchForActor = AddToggleOption("$IntelEngine_SearchSomeone", !Core.StoryEngine.SkipFollowerSearchForActor)
        OID_SkipFollowerScheduleMeeting = AddToggleOption("$IntelEngine_ArrangeMeeting", !Core.StoryEngine.SkipFollowerScheduleMeeting)
        OID_SkipFollowerScheduleFetch = AddToggleOption("$IntelEngine_FetchLater", !Core.StoryEngine.SkipFollowerScheduleFetch)
        OID_SkipFollowerScheduleDelivery = AddToggleOption("$IntelEngine_DeliverLater", !Core.StoryEngine.SkipFollowerScheduleDelivery)
    EndIf

    AddEmptyOption()
    AddHeaderOption("$IntelEngine_AutoBio")
    If Core != None && Core.StoryEngine != None
        OID_AutoBioEnabled = AddToggleOption("$IntelEngine_AutoBioOn", Core.StoryEngine.AutoBioEnabled)
        OID_AutoBioThreshold = AddSliderOption("$IntelEngine_AutoBioLines", Core.StoryEngine.AutoBioThreshold as Float, "{0}")
    EndIf

    AddEmptyOption()
    AddHeaderOption("$IntelEngine_StoryTypes")

    Bool tSeek = true
    Bool tInformant = true
    Bool tRoad = true
    Bool tAmbush = true
    Bool tFactionAmbush = true
    Bool tStalker = true
    Bool tMessage = true
    Bool tQuest = true
    If Core != None && Core.StoryEngine != None
        tSeek = Core.StoryEngine.TypeSeekPlayerEnabled
        tInformant = Core.StoryEngine.TypeInformantEnabled
        tRoad = Core.StoryEngine.TypeRoadEncounterEnabled
        tAmbush = Core.StoryEngine.TypeAmbushEnabled
        tFactionAmbush = Core.StoryEngine.TypeFactionAmbushEnabled
        tStalker = Core.StoryEngine.TypeStalkerEnabled
        tMessage = Core.StoryEngine.TypeMessageEnabled
        tQuest = Core.StoryEngine.TypeQuestEnabled
    EndIf
    OID_TypeSeekPlayer = AddToggleOption("$IntelEngine_TypeSeek", tSeek)
    OID_TypeInformant = AddToggleOption("$IntelEngine_TypeInformant", tInformant)
    OID_TypeRoadEncounter = AddToggleOption("$IntelEngine_TypeRoad", tRoad)
    OID_TypeAmbush = AddToggleOption("$IntelEngine_TypeAmbush", tAmbush)
    OID_TypeFactionAmbush = AddToggleOption("$IntelEngine_TypeFactionAmbush", tFactionAmbush)
    OID_TypeStalker = AddToggleOption("$IntelEngine_TypeStalker", tStalker)
    OID_TypeMessage = AddToggleOption("$IntelEngine_TypeMessage", tMessage)
    OID_TypeQuest = AddToggleOption("$IntelEngine_TypeQuest", tQuest)

    AddEmptyOption()
    AddHeaderOption("$IntelEngine_NpcsAmongThemselves")

    Bool npcTickEnabled = true
    Float npcTickInterval = 1.5
    If Core != None && Core.StoryEngine != None
        npcTickEnabled = Core.StoryEngine.NPCTickEnabled
        npcTickInterval = Core.StoryEngine.NPCTickIntervalHours
    EndIf
    OID_NPCTickEnabled = AddToggleOption("$IntelEngine_NpcVisits", npcTickEnabled)

    Bool tInteraction = true
    Bool tGossip = true
    If Core != None && Core.StoryEngine != None
        tInteraction = Core.StoryEngine.TypeNPCInteractionEnabled
        tGossip = Core.StoryEngine.TypeNPCGossipEnabled
    EndIf
    OID_TypeNPCInteraction = AddToggleOption("$IntelEngine_KindVisit", tInteraction)
    OID_TypeNPCGossip = AddToggleOption("$IntelEngine_KindGossip", tGossip)

    OID_NPCTickInterval = AddSliderOption("$IntelEngine_CheckInterval", npcTickInterval, "{1}")

    Float npcSocialCooldown = 24.0
    If Core != None && Core.StoryEngine != None
        npcSocialCooldown = Core.StoryEngine.NPCSocialCooldownHours
    EndIf
    OID_NPCSocialCooldown = AddSliderOption("$IntelEngine_RestPerNpc", npcSocialCooldown, "{0}")

    AddEmptyOption()
    AddHeaderOption("$IntelEngine_StoryTuning")

    Float longAbsence = 3.0
    Float maxTravel = 1.0
    If Core != None && Core.StoryEngine != None
        longAbsence = Core.StoryEngine.LongAbsenceDaysConfig
        maxTravel = Core.StoryEngine.MaxTravelDaysConfig
    EndIf
    OID_StoryLongAbsence = AddSliderOption("$IntelEngine_LongAbsence", longAbsence, "{0}")
    OID_StoryMaxTravel = AddSliderOption("$IntelEngine_LongestJourney", maxTravel, "{2}")

    Bool allowTeleport = true
    If Core != None && Core.StoryEngine != None
        allowTeleport = Core.StoryEngine.AllowStuckTeleport
    EndIf
    OID_AllowStuckTeleport = AddToggleOption("$IntelEngine_StuckTraveller", allowTeleport)

    Float questExpiry = 1.0
    If Core != None && Core.StoryEngine != None
        questExpiry = Core.StoryEngine.QUEST_EXPIRY_DAYS
    EndIf
    OID_QuestExpiryDays = AddSliderOption("$IntelEngine_QuestExpiry", questExpiry, "{0}")

    AddEmptyOption()
    AddHeaderOption("$IntelEngine_QuestKinds")
    Bool tQuestCombat = true
    Bool tQuestRescue = true
    Bool tQuestFindItem = true
    Bool tQuestFactionCombat = true
    Bool tQuestFactionRescue = true
    Bool tQuestFactionBattle = true
    Bool tQuestAllowDeath = false
    If Core != None && Core.StoryEngine != None
        tQuestCombat = Core.StoryEngine.QuestSubTypeCombatEnabled
        tQuestRescue = Core.StoryEngine.QuestSubTypeRescueEnabled
        tQuestFindItem = Core.StoryEngine.QuestSubTypeFindItemEnabled
        tQuestFactionCombat = Core.StoryEngine.QuestSubTypeFactionCombatEnabled
        tQuestFactionRescue = Core.StoryEngine.QuestSubTypeFactionRescueEnabled
        tQuestFactionBattle = Core.StoryEngine.QuestSubTypeFactionBattleEnabled
        tQuestAllowDeath = Core.StoryEngine.QuestAllowVictimDeath
    EndIf
    OID_QuestCombat = AddToggleOption("$IntelEngine_QuestClearOut", tQuestCombat)
    OID_QuestRescue = AddToggleOption("$IntelEngine_QuestRescue", tQuestRescue)
    OID_QuestFindItem = AddToggleOption("$IntelEngine_QuestFindItem", tQuestFindItem)
    OID_QuestFactionCombat = AddToggleOption("$IntelEngine_QuestFactionFight", tQuestFactionCombat)
    OID_QuestFactionRescue = AddToggleOption("$IntelEngine_QuestFactionRescue", tQuestFactionRescue)
    OID_QuestFactionBattle = AddToggleOption("$IntelEngine_QuestFactionBattle", tQuestFactionBattle)
    ; "Allow NPC death in rescue" is not offered: nothing reads the setting, and a rescue's victim is always
    ; kept alive (made essential) for its length.
    OID_QuestAllowDeath = -1

    AddEmptyOption()
    ; The heading and the switch below it are the same key, as they were the same words ("Faction politics"):
    ; "Faction Politics" over the switch once made it show with a capital P (one spelling per string), and a
    ; heading "Politics" would have met the key "politics" the politics script hands to the DLL.
    AddHeaderOption("$IntelEngine_FactionPolitics")

    Bool politicsEnabled = IntelEngine.IsPoliticsEnabled()
    OID_PoliticsEnabled = AddToggleOption("$IntelEngine_FactionPolitics", politicsEnabled)

    Float tickInterval = IntelEngine.GetPoliticsTickInterval() as Float
    OID_PoliticsTickInterval = AddSliderOption("$IntelEngine_CheckInterval", tickInterval, "{0}")
    OID_PEIntegration = AddToggleOption("$IntelEngine_PEIntegration", IntelEngine.GetPEIntegration())
    OID_PEReactions = AddToggleOption("$IntelEngine_PEReactions", IntelEngine.GetPEReactionsMoveRelations())

EndFunction

; =============================================================================
; HOLD RESTRICTIONS PAGE
; =============================================================================

Function ShowHoldRestrictionsPage()
    SetCursorFillMode(TOP_TO_BOTTOM)
    SetCursorPosition(0)

    AddHeaderOption("$IntelEngine_HoldRestrictions")
    AddTextOption("$IntelEngine_HoldIntro1", "", OPTION_FLAG_DISABLED)
    AddTextOption("$IntelEngine_HoldIntro2", "", OPTION_FLAG_DISABLED)
    AddTextOption("$IntelEngine_HoldIntro3", "", OPTION_FLAG_DISABLED)

    ; The defaults of StoryEngine's HoldPolicy properties (they differ by type).
    Int pSeek = 1
    Int pInformant = 6
    Int pRoad = 0
    Int pAmbush = 1
    Int pStalker = 1
    Int pMessage = 2
    Int pQuest = 0
    If Core != None && Core.StoryEngine != None
        pSeek = Core.StoryEngine.HoldPolicySeekPlayer
        pInformant = Core.StoryEngine.HoldPolicyInformant
        pRoad = Core.StoryEngine.HoldPolicyRoadEncounter
        pAmbush = Core.StoryEngine.HoldPolicyAmbush
        pStalker = Core.StoryEngine.HoldPolicyStalker
        pMessage = Core.StoryEngine.HoldPolicyMessage
        pQuest = Core.StoryEngine.HoldPolicyQuest
    EndIf

    ; ---- Left column (4 groups × 8 rows = 32 = exactly at SkyUI limit) ----
    AddHeaderOption("$IntelEngine_TypeSeek")
    OID_HoldSeekNone = AddToggleOption("$IntelEngine_HoldNone", pSeek == 0)
    OID_HoldSeekCivilian = AddToggleOption("$IntelEngine_HoldCivilians", pSeek == 1)
    OID_HoldSeekExceptFollower = AddToggleOption("$IntelEngine_HoldExceptFollowers", pSeek == 2)
    OID_HoldSeekAll = AddToggleOption("$IntelEngine_HoldEveryone", pSeek == 3)
    OID_HoldSeekLocalCivilian = AddToggleOption("$IntelEngine_TownCivilians", pSeek == 4)
    OID_HoldSeekLocalExceptFollower = AddToggleOption("$IntelEngine_TownExceptFollowers", pSeek == 5)
    OID_HoldSeekLocalAll = AddToggleOption("$IntelEngine_TownEveryone", pSeek == 6)
    AddHeaderOption("$IntelEngine_TypeInformant")
    OID_HoldInformantNone = AddToggleOption("$IntelEngine_HoldNone", pInformant == 0)
    OID_HoldInformantCivilian = AddToggleOption("$IntelEngine_HoldCivilians", pInformant == 1)
    OID_HoldInformantExceptFollower = AddToggleOption("$IntelEngine_HoldExceptFollowers", pInformant == 2)
    OID_HoldInformantAll = AddToggleOption("$IntelEngine_HoldEveryone", pInformant == 3)
    OID_HoldInformantLocalCivilian = AddToggleOption("$IntelEngine_TownCivilians", pInformant == 4)
    OID_HoldInformantLocalExceptFollower = AddToggleOption("$IntelEngine_TownExceptFollowers", pInformant == 5)
    OID_HoldInformantLocalAll = AddToggleOption("$IntelEngine_TownEveryone", pInformant == 6)
    AddHeaderOption("$IntelEngine_TypeRoad")
    OID_HoldRoadNone = AddToggleOption("$IntelEngine_HoldNone", pRoad == 0)
    OID_HoldRoadCivilian = AddToggleOption("$IntelEngine_HoldCivilians", pRoad == 1)
    OID_HoldRoadExceptFollower = AddToggleOption("$IntelEngine_HoldExceptFollowers", pRoad == 2)
    OID_HoldRoadAll = AddToggleOption("$IntelEngine_HoldEveryone", pRoad == 3)
    OID_HoldRoadLocalCivilian = AddToggleOption("$IntelEngine_TownCivilians", pRoad == 4)
    OID_HoldRoadLocalExceptFollower = AddToggleOption("$IntelEngine_TownExceptFollowers", pRoad == 5)
    OID_HoldRoadLocalAll = AddToggleOption("$IntelEngine_TownEveryone", pRoad == 6)
    AddHeaderOption("$IntelEngine_TypeAmbush")
    OID_HoldAmbushNone = AddToggleOption("$IntelEngine_HoldNone", pAmbush == 0)
    OID_HoldAmbushCivilian = AddToggleOption("$IntelEngine_HoldCivilians", pAmbush == 1)
    OID_HoldAmbushExceptFollower = AddToggleOption("$IntelEngine_HoldExceptFollowers", pAmbush == 2)
    OID_HoldAmbushAll = AddToggleOption("$IntelEngine_HoldEveryone", pAmbush == 3)
    OID_HoldAmbushLocalCivilian = AddToggleOption("$IntelEngine_TownCivilians", pAmbush == 4)
    OID_HoldAmbushLocalExceptFollower = AddToggleOption("$IntelEngine_TownExceptFollowers", pAmbush == 5)
    OID_HoldAmbushLocalAll = AddToggleOption("$IntelEngine_TownEveryone", pAmbush == 6)

    ; ---- Right column (3 groups × 8 rows = 24, under 32) ----
    SetCursorPosition(1)
    AddHeaderOption("$IntelEngine_TypeStalker")
    OID_HoldStalkerNone = AddToggleOption("$IntelEngine_HoldNone", pStalker == 0)
    OID_HoldStalkerCivilian = AddToggleOption("$IntelEngine_HoldCivilians", pStalker == 1)
    OID_HoldStalkerExceptFollower = AddToggleOption("$IntelEngine_HoldExceptFollowers", pStalker == 2)
    OID_HoldStalkerAll = AddToggleOption("$IntelEngine_HoldEveryone", pStalker == 3)
    OID_HoldStalkerLocalCivilian = AddToggleOption("$IntelEngine_TownCivilians", pStalker == 4)
    OID_HoldStalkerLocalExceptFollower = AddToggleOption("$IntelEngine_TownExceptFollowers", pStalker == 5)
    OID_HoldStalkerLocalAll = AddToggleOption("$IntelEngine_TownEveryone", pStalker == 6)
    AddHeaderOption("$IntelEngine_TypeMessage")
    OID_HoldMessageNone = AddToggleOption("$IntelEngine_HoldNone", pMessage == 0)
    OID_HoldMessageCivilian = AddToggleOption("$IntelEngine_HoldCivilians", pMessage == 1)
    OID_HoldMessageExceptFollower = AddToggleOption("$IntelEngine_HoldExceptFollowers", pMessage == 2)
    OID_HoldMessageAll = AddToggleOption("$IntelEngine_HoldEveryone", pMessage == 3)
    OID_HoldMessageLocalCivilian = AddToggleOption("$IntelEngine_TownCivilians", pMessage == 4)
    OID_HoldMessageLocalExceptFollower = AddToggleOption("$IntelEngine_TownExceptFollowers", pMessage == 5)
    OID_HoldMessageLocalAll = AddToggleOption("$IntelEngine_TownEveryone", pMessage == 6)
    AddHeaderOption("$IntelEngine_TypeQuest")
    OID_HoldQuestNone = AddToggleOption("$IntelEngine_HoldNone", pQuest == 0)
    OID_HoldQuestCivilian = AddToggleOption("$IntelEngine_HoldCivilians", pQuest == 1)
    OID_HoldQuestExceptFollower = AddToggleOption("$IntelEngine_HoldExceptFollowers", pQuest == 2)
    OID_HoldQuestAll = AddToggleOption("$IntelEngine_HoldEveryone", pQuest == 3)
    OID_HoldQuestLocalCivilian = AddToggleOption("$IntelEngine_TownCivilians", pQuest == 4)
    OID_HoldQuestLocalExceptFollower = AddToggleOption("$IntelEngine_TownExceptFollowers", pQuest == 5)
    OID_HoldQuestLocalAll = AddToggleOption("$IntelEngine_TownEveryone", pQuest == 6)
EndFunction

String Function LivingWorldLabel(Int which, Int index)
    {The choice names of the four living-world settings, as on SkyrimNet's settings page.}
    If which == 0
        If index == 0
            Return "$IntelEngine_Classic"
        ElseIf index == 1
            Return "$IntelEngine_Rumors"
        EndIf
        Return "$IntelEngine_Lives"
    ElseIf which == 1
        If index == 0
            Return "$IntelEngine_Never"
        ElseIf index == 1
            Return "$IntelEngine_IfUrgent"
        EndIf
        Return "$IntelEngine_Realistic"
    ElseIf which == 2
        If index == 0
            Return "$IntelEngine_Never"
        ElseIf index == 1
            Return "$IntelEngine_IfImportant"
        EndIf
        Return "$IntelEngine_Freely"
    EndIf
    If index == 0
        Return "$IntelEngine_Calm"
    ElseIf index == 1
        Return "$IntelEngine_Normal"
    EndIf
    Return "$IntelEngine_Lively"
EndFunction

Function CycleLivingWorld(Int optionId)
    {Click to go to the next choice of a living-world setting.}
    If Core == None || Core.StoryEngine == None
        Return
    EndIf
    Int which = 0
    String settingKey = "livingWorldLevel"
    Int value = Core.StoryEngine.LivingWorldLevel
    If optionId == OID_LWInterruptions
        which = 1
        settingKey = "livingWorldInterruptions"
        value = Core.StoryEngine.LivingWorldInterruptions
    ElseIf optionId == OID_LWQuestNpcs
        which = 2
        settingKey = "livingWorldQuestNpcs"
        value = Core.StoryEngine.LivingWorldQuestNpcs
    ElseIf optionId == OID_LWPacing
        which = 3
        settingKey = "livingWorldPacing"
        value = Core.StoryEngine.LivingWorldPacing
    EndIf
    value = (value + 1) % 3
    Core.StoryEngine.SetLivingWorldSetting(settingKey, value as Float)
    SetTextOptionValue(optionId, LivingWorldLabel(which, value))
EndFunction

String Function ConfirmModeLabel(Int mode)
    If mode == 0
        return "$IntelEngine_Disabled"
    ElseIf mode == 1
        return "$IntelEngine_FollowersOnly"
    ElseIf mode == 2
        return "$IntelEngine_Everyone"
    EndIf
    return "$IntelEngine_Disabled"
EndFunction

Function CycleConfirmMode(Int optionId, String propName)
    If Core == None || Core.StoryEngine == None
        return
    EndIf
    Int current = 0
    If propName == "GoToLocation"
        current = Core.StoryEngine.ConfirmGoToLocation
    ElseIf propName == "DeliverMessage"
        current = Core.StoryEngine.ConfirmDeliverMessage
    ElseIf propName == "FetchPerson"
        current = Core.StoryEngine.ConfirmFetchPerson
    ElseIf propName == "EscortTarget"
        current = Core.StoryEngine.ConfirmEscortTarget
    ElseIf propName == "SearchForActor"
        current = Core.StoryEngine.ConfirmSearchForActor
    ElseIf propName == "ScheduleFetch"
        current = Core.StoryEngine.ConfirmScheduleFetch
    ElseIf propName == "ScheduleDelivery"
        current = Core.StoryEngine.ConfirmScheduleDelivery
    ElseIf propName == "ScheduleMeeting"
        current = Core.StoryEngine.ConfirmScheduleMeeting
    EndIf
    Int next = (current + 1) % 3
    If propName == "GoToLocation"
        Core.StoryEngine.ConfirmGoToLocation = next
    ElseIf propName == "DeliverMessage"
        Core.StoryEngine.ConfirmDeliverMessage = next
    ElseIf propName == "FetchPerson"
        Core.StoryEngine.ConfirmFetchPerson = next
    ElseIf propName == "EscortTarget"
        Core.StoryEngine.ConfirmEscortTarget = next
    ElseIf propName == "SearchForActor"
        Core.StoryEngine.ConfirmSearchForActor = next
    ElseIf propName == "ScheduleFetch"
        Core.StoryEngine.ConfirmScheduleFetch = next
    ElseIf propName == "ScheduleDelivery"
        Core.StoryEngine.ConfirmScheduleDelivery = next
    ElseIf propName == "ScheduleMeeting"
        Core.StoryEngine.ConfirmScheduleMeeting = next
    EndIf
    SetTextOptionValue(optionId, ConfirmModeLabel(next))
EndFunction

Function ToggleSkipFollower(Int optionId, String propName)
    If Core == None || Core.StoryEngine == None
        return
    EndIf
    Bool current = false
    If propName == "GoToLocation"
        current = Core.StoryEngine.SkipFollowerGoToLocation
        Core.StoryEngine.SkipFollowerGoToLocation = !current
    ElseIf propName == "DeliverMessage"
        current = Core.StoryEngine.SkipFollowerDeliverMessage
        Core.StoryEngine.SkipFollowerDeliverMessage = !current
    ElseIf propName == "FetchPerson"
        current = Core.StoryEngine.SkipFollowerFetchPerson
        Core.StoryEngine.SkipFollowerFetchPerson = !current
    ElseIf propName == "EscortTarget"
        current = Core.StoryEngine.SkipFollowerEscortTarget
        Core.StoryEngine.SkipFollowerEscortTarget = !current
    ElseIf propName == "SearchForActor"
        current = Core.StoryEngine.SkipFollowerSearchForActor
        Core.StoryEngine.SkipFollowerSearchForActor = !current
    ElseIf propName == "ScheduleFetch"
        current = Core.StoryEngine.SkipFollowerScheduleFetch
        Core.StoryEngine.SkipFollowerScheduleFetch = !current
    ElseIf propName == "ScheduleDelivery"
        current = Core.StoryEngine.SkipFollowerScheduleDelivery
        Core.StoryEngine.SkipFollowerScheduleDelivery = !current
    ElseIf propName == "ScheduleMeeting"
        current = Core.StoryEngine.SkipFollowerScheduleMeeting
        Core.StoryEngine.SkipFollowerScheduleMeeting = !current
    EndIf
    ; The option shows "followers can do it": the opposite of the new skip value (!current), so `current`.
    SetToggleOptionValue(optionId, current)
EndFunction

Function SetHoldPolicy(String storyType, Int optionId, Int oidNone, Int oidCivilian, Int oidExceptFollower, Int oidAll, Int oidLocalCivilian, Int oidLocalExceptFollower, Int oidLocalAll)
    If Core == None || Core.StoryEngine == None
        return
    EndIf
    Int newPolicy = 1
    If optionId == oidNone
        newPolicy = 0
    ElseIf optionId == oidCivilian
        newPolicy = 1
    ElseIf optionId == oidExceptFollower
        newPolicy = 2
    ElseIf optionId == oidAll
        newPolicy = 3
    ElseIf optionId == oidLocalCivilian
        newPolicy = 4
    ElseIf optionId == oidLocalExceptFollower
        newPolicy = 5
    ElseIf optionId == oidLocalAll
        newPolicy = 6
    EndIf
    Core.SetHoldRestrictionPolicy(storyType, newPolicy)
    SetToggleOptionValue(oidNone, newPolicy == 0)
    SetToggleOptionValue(oidCivilian, newPolicy == 1)
    SetToggleOptionValue(oidExceptFollower, newPolicy == 2)
    SetToggleOptionValue(oidAll, newPolicy == 3)
    SetToggleOptionValue(oidLocalCivilian, newPolicy == 4)
    SetToggleOptionValue(oidLocalExceptFollower, newPolicy == 5)
    SetToggleOptionValue(oidLocalAll, newPolicy == 6)
EndFunction

; =============================================================================
; OPTION HANDLERS
; =============================================================================

Event OnOptionSelect(Int optionId)
    If optionId == OID_ResetAllTasks
        ; "$Yes" and "$No" are the game's own words (its Translate_<LANGUAGE>.txt), as SkyUI's own menu uses them.
        Bool confirm = ShowMessage("$IntelEngine_ResetConfirm", true, "$Yes", "$No")
        If confirm && Core != None
            Core.ForceResetAllSlots()
            ; Also restart story engine monitoring (prevents tick death after reset)
            If Core.StoryEngine != None
                Core.StoryEngine.RestartMonitoring()
            EndIf
            ShowMessage("$IntelEngine_ResetComplete", false)
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

    ElseIf optionId == OID_DangerAllowAll || optionId == OID_DangerBlockCivilians || \
           optionId == OID_DangerFollowersOnly || optionId == OID_DangerBlockAll
        If Core != None
            Int newPolicy = 1
            If optionId == OID_DangerAllowAll
                newPolicy = 0
            ElseIf optionId == OID_DangerBlockCivilians
                newPolicy = 1
            ElseIf optionId == OID_DangerFollowersOnly
                newPolicy = 2
            ElseIf optionId == OID_DangerBlockAll
                newPolicy = 3
            EndIf
            Core.SetDangerZonePolicy(newPolicy)
            SetToggleOptionValue(OID_DangerAllowAll, newPolicy == 0)
            SetToggleOptionValue(OID_DangerBlockCivilians, newPolicy == 1)
            SetToggleOptionValue(OID_DangerFollowersOnly, newPolicy == 2)
            SetToggleOptionValue(OID_DangerBlockAll, newPolicy == 3)
        EndIf

    ElseIf optionId == OID_HomeAllowAll || optionId == OID_HomeBlockCivilians || \
           optionId == OID_HomeFollowersOnly || optionId == OID_HomeBlockAll
        If Core != None
            Int newPolicy = 0
            If optionId == OID_HomeAllowAll
                newPolicy = 0
            ElseIf optionId == OID_HomeBlockCivilians
                newPolicy = 1
            ElseIf optionId == OID_HomeFollowersOnly
                newPolicy = 2
            ElseIf optionId == OID_HomeBlockAll
                newPolicy = 3
            EndIf
            Core.SetPlayerHomePolicy(newPolicy)
            SetToggleOptionValue(OID_HomeAllowAll, newPolicy == 0)
            SetToggleOptionValue(OID_HomeBlockCivilians, newPolicy == 1)
            SetToggleOptionValue(OID_HomeFollowersOnly, newPolicy == 2)
            SetToggleOptionValue(OID_HomeBlockAll, newPolicy == 3)
        EndIf

    ElseIf optionId == OID_CancelAllSchedules
        Bool confirm = ShowMessage("$IntelEngine_CancelAllConfirm", true, "$Yes", "$No")
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

    ElseIf optionId == OID_LWLevel || optionId == OID_LWInterruptions || optionId == OID_LWQuestNpcs || optionId == OID_LWPacing
        CycleLivingWorld(optionId)
    ElseIf optionId == OID_LWSkippedTime && Core != None && Core.StoryEngine != None
        Float counts = 1.0
        If Core.StoryEngine.LivingWorldSkippedTime
            counts = 0.0
        EndIf
        Core.StoryEngine.SetLivingWorldSetting("livingWorldSkippedTime", counts)
        SetToggleOptionValue(OID_LWSkippedTime, Core.StoryEngine.LivingWorldSkippedTime)
    ElseIf optionId == OID_ConfirmGoToLocation
        CycleConfirmMode(optionId, "GoToLocation")
    ElseIf optionId == OID_ConfirmDeliverMessage
        CycleConfirmMode(optionId, "DeliverMessage")
    ElseIf optionId == OID_ConfirmFetchPerson
        CycleConfirmMode(optionId, "FetchPerson")
    ElseIf optionId == OID_ConfirmEscortTarget
        CycleConfirmMode(optionId, "EscortTarget")
    ElseIf optionId == OID_ConfirmSearchForActor
        CycleConfirmMode(optionId, "SearchForActor")
    ElseIf optionId == OID_ConfirmScheduleFetch
        CycleConfirmMode(optionId, "ScheduleFetch")
    ElseIf optionId == OID_ConfirmScheduleDelivery
        CycleConfirmMode(optionId, "ScheduleDelivery")
    ElseIf optionId == OID_ConfirmScheduleMeeting
        CycleConfirmMode(optionId, "ScheduleMeeting")

    ElseIf optionId == OID_SkipFollowerGoToLocation
        ToggleSkipFollower(optionId, "GoToLocation")
    ElseIf optionId == OID_SkipFollowerDeliverMessage
        ToggleSkipFollower(optionId, "DeliverMessage")
    ElseIf optionId == OID_SkipFollowerFetchPerson
        ToggleSkipFollower(optionId, "FetchPerson")
    ElseIf optionId == OID_SkipFollowerEscortTarget
        ToggleSkipFollower(optionId, "EscortTarget")
    ElseIf optionId == OID_SkipFollowerSearchForActor
        ToggleSkipFollower(optionId, "SearchForActor")
    ElseIf optionId == OID_SkipFollowerScheduleFetch
        ToggleSkipFollower(optionId, "ScheduleFetch")
    ElseIf optionId == OID_SkipFollowerScheduleDelivery
        ToggleSkipFollower(optionId, "ScheduleDelivery")
    ElseIf optionId == OID_SkipFollowerScheduleMeeting
        ToggleSkipFollower(optionId, "ScheduleMeeting")

    ElseIf optionId == OID_AutoBioEnabled
        If Core != None && Core.StoryEngine != None
            Bool newVal = !Core.StoryEngine.AutoBioEnabled
            Core.StoryEngine.AutoBioEnabled = newVal
            IntelEngine.SetAutoBioEnabled(newVal)
            SetToggleOptionValue(OID_AutoBioEnabled, newVal)
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
        Core.SetStoryEnabled(newVal)
        SetToggleOptionValue(OID_StoryEngineEnabled, newVal)

    ElseIf optionId == OID_NPCTickEnabled
        If Core != None && Core.StoryEngine != None
            Core.StoryEngine.NPCTickEnabled = !Core.StoryEngine.NPCTickEnabled
            SetToggleOptionValue(OID_NPCTickEnabled, Core.StoryEngine.NPCTickEnabled)
        EndIf

    ElseIf optionId == OID_PoliticsEnabled
        Bool newVal = !IntelEngine.IsPoliticsEnabled()
        IntelEngine.SetPoliticsEnabled(newVal)
        SetToggleOptionValue(OID_PoliticsEnabled, newVal)
        If newVal && Core != None && Core.Politics != None
            Core.Politics.StartScheduler()
        ElseIf !newVal && Core != None && Core.Politics != None
            Core.Politics.StopScheduler()
        EndIf
    ElseIf optionId == OID_PEIntegration
        IntelEngine.SetPEIntegration(!IntelEngine.GetPEIntegration())
        SetToggleOptionValue(OID_PEIntegration, IntelEngine.GetPEIntegration())
    ElseIf optionId == OID_PEReactions
        IntelEngine.SetPEReactionsMoveRelations(!IntelEngine.GetPEReactionsMoveRelations())
        SetToggleOptionValue(OID_PEReactions, IntelEngine.GetPEReactionsMoveRelations())

    ElseIf optionId == OID_StoryForceRestart
        If Core != None
            ; Full maintenance: recover script refs, restart ALL monitoring loops,
            ; release stuck linger NPCs, clean expired facts
            Core.Maintenance(false)
            ShowMessage("$IntelEngine_RestartDone", false)
        EndIf

    ; ---- Hold Restriction toggles ----
    ElseIf optionId == OID_HoldSeekNone || optionId == OID_HoldSeekCivilian || \
           optionId == OID_HoldSeekExceptFollower || optionId == OID_HoldSeekAll || \
           optionId == OID_HoldSeekLocalCivilian || optionId == OID_HoldSeekLocalExceptFollower || optionId == OID_HoldSeekLocalAll
        SetHoldPolicy("seek_player", optionId, OID_HoldSeekNone, OID_HoldSeekCivilian, OID_HoldSeekExceptFollower, OID_HoldSeekAll, OID_HoldSeekLocalCivilian, OID_HoldSeekLocalExceptFollower, OID_HoldSeekLocalAll)

    ElseIf optionId == OID_HoldInformantNone || optionId == OID_HoldInformantCivilian || \
           optionId == OID_HoldInformantExceptFollower || optionId == OID_HoldInformantAll || \
           optionId == OID_HoldInformantLocalCivilian || optionId == OID_HoldInformantLocalExceptFollower || optionId == OID_HoldInformantLocalAll
        SetHoldPolicy("informant", optionId, OID_HoldInformantNone, OID_HoldInformantCivilian, OID_HoldInformantExceptFollower, OID_HoldInformantAll, OID_HoldInformantLocalCivilian, OID_HoldInformantLocalExceptFollower, OID_HoldInformantLocalAll)

    ElseIf optionId == OID_HoldRoadNone || optionId == OID_HoldRoadCivilian || \
           optionId == OID_HoldRoadExceptFollower || optionId == OID_HoldRoadAll || \
           optionId == OID_HoldRoadLocalCivilian || optionId == OID_HoldRoadLocalExceptFollower || optionId == OID_HoldRoadLocalAll
        SetHoldPolicy("road_encounter", optionId, OID_HoldRoadNone, OID_HoldRoadCivilian, OID_HoldRoadExceptFollower, OID_HoldRoadAll, OID_HoldRoadLocalCivilian, OID_HoldRoadLocalExceptFollower, OID_HoldRoadLocalAll)

    ElseIf optionId == OID_HoldAmbushNone || optionId == OID_HoldAmbushCivilian || \
           optionId == OID_HoldAmbushExceptFollower || optionId == OID_HoldAmbushAll || \
           optionId == OID_HoldAmbushLocalCivilian || optionId == OID_HoldAmbushLocalExceptFollower || optionId == OID_HoldAmbushLocalAll
        SetHoldPolicy("ambush", optionId, OID_HoldAmbushNone, OID_HoldAmbushCivilian, OID_HoldAmbushExceptFollower, OID_HoldAmbushAll, OID_HoldAmbushLocalCivilian, OID_HoldAmbushLocalExceptFollower, OID_HoldAmbushLocalAll)

    ElseIf optionId == OID_HoldStalkerNone || optionId == OID_HoldStalkerCivilian || \
           optionId == OID_HoldStalkerExceptFollower || optionId == OID_HoldStalkerAll || \
           optionId == OID_HoldStalkerLocalCivilian || optionId == OID_HoldStalkerLocalExceptFollower || optionId == OID_HoldStalkerLocalAll
        SetHoldPolicy("stalker", optionId, OID_HoldStalkerNone, OID_HoldStalkerCivilian, OID_HoldStalkerExceptFollower, OID_HoldStalkerAll, OID_HoldStalkerLocalCivilian, OID_HoldStalkerLocalExceptFollower, OID_HoldStalkerLocalAll)

    ElseIf optionId == OID_HoldMessageNone || optionId == OID_HoldMessageCivilian || \
           optionId == OID_HoldMessageExceptFollower || optionId == OID_HoldMessageAll || \
           optionId == OID_HoldMessageLocalCivilian || optionId == OID_HoldMessageLocalExceptFollower || optionId == OID_HoldMessageLocalAll
        SetHoldPolicy("message", optionId, OID_HoldMessageNone, OID_HoldMessageCivilian, OID_HoldMessageExceptFollower, OID_HoldMessageAll, OID_HoldMessageLocalCivilian, OID_HoldMessageLocalExceptFollower, OID_HoldMessageLocalAll)

    ElseIf optionId == OID_HoldQuestNone || optionId == OID_HoldQuestCivilian || \
           optionId == OID_HoldQuestExceptFollower || optionId == OID_HoldQuestAll || \
           optionId == OID_HoldQuestLocalCivilian || optionId == OID_HoldQuestLocalExceptFollower || optionId == OID_HoldQuestLocalAll
        SetHoldPolicy("quest", optionId, OID_HoldQuestNone, OID_HoldQuestCivilian, OID_HoldQuestExceptFollower, OID_HoldQuestAll, OID_HoldQuestLocalCivilian, OID_HoldQuestLocalExceptFollower, OID_HoldQuestLocalAll)

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
        ElseIf optionId == OID_TypeFactionAmbush
            Core.StoryEngine.TypeFactionAmbushEnabled = !Core.StoryEngine.TypeFactionAmbushEnabled
            SetToggleOptionValue(OID_TypeFactionAmbush, Core.StoryEngine.TypeFactionAmbushEnabled)
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
        ElseIf optionId == OID_AllowStuckTeleport
            Core.StoryEngine.AllowStuckTeleport = !Core.StoryEngine.AllowStuckTeleport
            SetToggleOptionValue(OID_AllowStuckTeleport, Core.StoryEngine.AllowStuckTeleport)
        ElseIf optionId == OID_QuestCombat
            Core.StoryEngine.QuestSubTypeCombatEnabled = !Core.StoryEngine.QuestSubTypeCombatEnabled
            SetToggleOptionValue(OID_QuestCombat, Core.StoryEngine.QuestSubTypeCombatEnabled)
        ElseIf optionId == OID_QuestRescue
            Core.StoryEngine.QuestSubTypeRescueEnabled = !Core.StoryEngine.QuestSubTypeRescueEnabled
            SetToggleOptionValue(OID_QuestRescue, Core.StoryEngine.QuestSubTypeRescueEnabled)
        ElseIf optionId == OID_QuestFindItem
            Core.StoryEngine.QuestSubTypeFindItemEnabled = !Core.StoryEngine.QuestSubTypeFindItemEnabled
            SetToggleOptionValue(OID_QuestFindItem, Core.StoryEngine.QuestSubTypeFindItemEnabled)
        ElseIf optionId == OID_QuestFactionCombat
            Core.StoryEngine.QuestSubTypeFactionCombatEnabled = !Core.StoryEngine.QuestSubTypeFactionCombatEnabled
            SetToggleOptionValue(OID_QuestFactionCombat, Core.StoryEngine.QuestSubTypeFactionCombatEnabled)
        ElseIf optionId == OID_QuestFactionRescue
            Core.StoryEngine.QuestSubTypeFactionRescueEnabled = !Core.StoryEngine.QuestSubTypeFactionRescueEnabled
            SetToggleOptionValue(OID_QuestFactionRescue, Core.StoryEngine.QuestSubTypeFactionRescueEnabled)
        ElseIf optionId == OID_QuestFactionBattle
            Core.StoryEngine.QuestSubTypeFactionBattleEnabled = !Core.StoryEngine.QuestSubTypeFactionBattleEnabled
            SetToggleOptionValue(OID_QuestFactionBattle, Core.StoryEngine.QuestSubTypeFactionBattleEnabled)
        ElseIf optionId == OID_QuestAllowDeath
            Core.StoryEngine.QuestAllowVictimDeath = !Core.StoryEngine.QuestAllowVictimDeath
            SetToggleOptionValue(OID_QuestAllowDeath, Core.StoryEngine.QuestAllowVictimDeath)
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
        SetSliderDialogStartValue(StorageUtil.GetFloatValue(Game.GetPlayer(), "Intel_MeetingTimeoutHours", 5.0))
        SetSliderDialogDefaultValue(5.0)
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
    ElseIf optionId == OID_AutoBioThreshold
        Float currentValue = 20.0
        If Core != None && Core.StoryEngine != None
            currentValue = Core.StoryEngine.AutoBioThreshold as Float
        EndIf
        SetSliderDialogStartValue(currentValue)
        SetSliderDialogDefaultValue(20.0)
        SetSliderDialogRange(5.0, 1000.0)
        SetSliderDialogInterval(5.0)
    ElseIf optionId == OID_LingerReleaseDistance
        Float currentValue = 800.0
        If Core != None
            currentValue = Core.LINGER_RELEASE_DISTANCE
        EndIf
        SetSliderDialogStartValue(currentValue)
        SetSliderDialogDefaultValue(800.0)
        SetSliderDialogRange(300.0, 2000.0)
        SetSliderDialogInterval(100.0)
    ElseIf optionId == OID_StoryEngineInterval
        SetSliderDialogStartValue(Core.GetStoryEngineInterval())
        SetSliderDialogDefaultValue(3.0)
        SetSliderDialogRange(0.5, 168.0)
        SetSliderDialogInterval(0.5)
    ElseIf optionId == OID_StoryEngineCooldown
        SetSliderDialogStartValue(Core.GetStoryEngineCooldown())
        SetSliderDialogDefaultValue(24.0)
        SetSliderDialogRange(6.0, 72.0)
        SetSliderDialogInterval(6.0)
    ElseIf optionId == OID_LWWaitDays || optionId == OID_LWLifeDays
        Float lwDays = 30.0
        Float lwDefault = 30.0
        Float lwMax = 120.0
        If optionId == OID_LWLifeDays
            lwDays = 7.0
            lwDefault = 7.0
            lwMax = 60.0
        EndIf
        If Core != None && Core.StoryEngine != None
            If optionId == OID_LWWaitDays
                lwDays = Core.StoryEngine.LivingWorldWaitDays
            Else
                lwDays = Core.StoryEngine.LivingWorldLifeDays
            EndIf
        EndIf
        SetSliderDialogStartValue(lwDays)
        SetSliderDialogDefaultValue(lwDefault)
        SetSliderDialogRange(1.0, lwMax)
        SetSliderDialogInterval(1.0)
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
        SetSliderDialogRange(0.5, 168.0)
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
    ElseIf optionId == OID_PoliticsTickInterval
        SetSliderDialogStartValue(IntelEngine.GetPoliticsTickInterval() as Float)
        SetSliderDialogDefaultValue(6.0)
        SetSliderDialogRange(1.0, 168.0)
        SetSliderDialogInterval(1.0)
    EndIf
EndEvent

Event OnOptionSliderAccept(Int optionId, Float sliderValue)
    If optionId == OID_MaxTasks
        Core.SetMaxTasks(sliderValue as Int)
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
    ElseIf optionId == OID_AutoBioThreshold
        If Core != None && Core.StoryEngine != None
            Core.StoryEngine.AutoBioThreshold = sliderValue as Int
            IntelEngine.SetAutoBioThreshold(sliderValue as Int)
        EndIf
        SetSliderOptionValue(OID_AutoBioThreshold, sliderValue, "{0}")
    ElseIf optionId == OID_LingerReleaseDistance
        If Core != None
            Core.SetReleaseDistance(sliderValue)
        EndIf
        SetSliderOptionValue(OID_LingerReleaseDistance, sliderValue, "{0}")
    ElseIf optionId == OID_StoryEngineInterval
        Core.SetStoryInterval(sliderValue)
        SetSliderOptionValue(OID_StoryEngineInterval, sliderValue, "{1}")
    ElseIf optionId == OID_StoryEngineCooldown
        Core.SetStoryCooldown(sliderValue)
        SetSliderOptionValue(OID_StoryEngineCooldown, sliderValue, "{0}")
    ElseIf optionId == OID_LWWaitDays || optionId == OID_LWLifeDays
        If Core != None && Core.StoryEngine != None
            If optionId == OID_LWWaitDays
                Core.StoryEngine.SetLivingWorldSetting("livingWorldWaitDays", sliderValue)
            Else
                Core.StoryEngine.SetLivingWorldSetting("livingWorldLifeDays", sliderValue)
            EndIf
        EndIf
        SetSliderOptionValue(optionId, sliderValue, "{0}")
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
    ElseIf optionId == OID_PoliticsTickInterval
        IntelEngine.SetPoliticsTickInterval(sliderValue as Int)
        SetSliderOptionValue(OID_PoliticsTickInterval, sliderValue, "{0}")
    EndIf
EndEvent

Event OnOptionMenuOpen(Int optionId)
EndEvent

Event OnOptionMenuAccept(Int optionId, Int index)
EndEvent

Event OnOptionHighlight(Int optionId)
    ; The help of "Story NPC Cooldown" and "Allow NPC death in rescue" is gone with their options (ids -1).
    If optionId == OID_LWLevel
        SetInfoText("$IntelEngine_WorldLevel_Info")
    ElseIf optionId == OID_LWInterruptions
        SetInfoText("$IntelEngine_Interruptions_Info")
    ElseIf optionId == OID_LWQuestNpcs
        SetInfoText("$IntelEngine_QuestNpcsMove_Info")
    ElseIf optionId == OID_LWPacing
        SetInfoText("$IntelEngine_Pacing_Info")
    ElseIf optionId == OID_LWSkippedTime
        SetInfoText("$IntelEngine_SkippedTime_Info")
    ElseIf optionId == OID_LWWaitDays
        SetInfoText("$IntelEngine_WaitDays_Info")
    ElseIf optionId == OID_LWLifeDays
        SetInfoText("$IntelEngine_LifeDays_Info")
    ElseIf optionId == OID_DebugMode
        SetInfoText("$IntelEngine_DebugMessages_Info")
    ElseIf optionId == OID_MaxTasks
        SetInfoText("$IntelEngine_MaxTasks_Info")
    ElseIf optionId == OID_DefaultWaitHours
        SetInfoText("$IntelEngine_DefaultWait_Info")
    ElseIf optionId == OID_ResetAllTasks
        SetInfoText("$IntelEngine_ResetAllTasks_Info")
    ElseIf optionId == OID_ConfirmGoToLocation || optionId == OID_ConfirmDeliverMessage || \
           optionId == OID_ConfirmFetchPerson || optionId == OID_ConfirmEscortTarget || \
           optionId == OID_ConfirmSearchForActor || optionId == OID_ConfirmScheduleFetch || \
           optionId == OID_ConfirmScheduleDelivery || optionId == OID_ConfirmScheduleMeeting
        SetInfoText("$IntelEngine_Confirm_Info")
    ElseIf optionId == OID_SkipFollowerGoToLocation || optionId == OID_SkipFollowerDeliverMessage || \
           optionId == OID_SkipFollowerFetchPerson || optionId == OID_SkipFollowerEscortTarget || \
           optionId == OID_SkipFollowerSearchForActor || optionId == OID_SkipFollowerScheduleFetch || \
           optionId == OID_SkipFollowerScheduleDelivery || optionId == OID_SkipFollowerScheduleMeeting
        SetInfoText("$IntelEngine_FollowerAllowed_Info")
    ElseIf optionId == OID_DeliveryReportBack
        SetInfoText("$IntelEngine_ReportBack_Info")
    ElseIf optionId == OID_MeetingTimeoutHours
        SetInfoText("$IntelEngine_MeetingWait_Info")
    ElseIf optionId == OID_MeetingGracePeriod
        SetInfoText("$IntelEngine_OnTimeUntil_Info")
    ElseIf optionId == OID_LingerReleaseDistance
        SetInfoText("$IntelEngine_VisitEnds_Info")
    ElseIf optionId == OID_CancelAllSchedules
        SetInfoText("$IntelEngine_CancelAllScheduled_Info")
    ElseIf optionId == OID_StoryEngineEnabled
        SetInfoText("$IntelEngine_Stories_Info")
    ElseIf optionId == OID_StoryEngineInterval
        SetInfoText("$IntelEngine_StoryInterval_Info")
    ElseIf optionId == OID_StoryLongAbsence
        SetInfoText("$IntelEngine_LongAbsence_Info")
    ElseIf optionId == OID_StoryMaxTravel
        SetInfoText("$IntelEngine_LongestJourney_Info")
    ElseIf optionId == OID_AllowStuckTeleport
        SetInfoText("$IntelEngine_StuckTraveller_Info")
    ElseIf optionId == OID_DangerAllowAll
        SetInfoText("$IntelEngine_DangerAllowAll_Info")
    ElseIf optionId == OID_DangerBlockCivilians
        SetInfoText("$IntelEngine_DangerBlockCivilians_Info")
    ElseIf optionId == OID_DangerFollowersOnly
        SetInfoText("$IntelEngine_DangerAllowFollowers_Info")
    ElseIf optionId == OID_DangerBlockAll
        SetInfoText("$IntelEngine_DangerBlockAll_Info")
    ElseIf optionId == OID_HomeAllowAll
        SetInfoText("$IntelEngine_HomeAllowAll_Info")
    ElseIf optionId == OID_HomeBlockCivilians
        SetInfoText("$IntelEngine_HomeBlockCivilians_Info")
    ElseIf optionId == OID_HomeFollowersOnly
        SetInfoText("$IntelEngine_HomeAllowFollowers_Info")
    ElseIf optionId == OID_HomeBlockAll
        SetInfoText("$IntelEngine_HomeBlockAll_Info")
    ElseIf optionId == OID_QuestExpiryDays
        SetInfoText("$IntelEngine_QuestExpiry_Info")
    ElseIf optionId == OID_TypeSeekPlayer
        SetInfoText("$IntelEngine_TypeSeek_Info")
    ElseIf optionId == OID_TypeInformant
        SetInfoText("$IntelEngine_TypeInformant_Info")
    ElseIf optionId == OID_TypeRoadEncounter
        SetInfoText("$IntelEngine_TypeRoad_Info")
    ElseIf optionId == OID_TypeAmbush
        SetInfoText("$IntelEngine_TypeAmbush_Info")
    ElseIf optionId == OID_TypeFactionAmbush
        SetInfoText("$IntelEngine_TypeFactionAmbush_Info")
    ElseIf optionId == OID_TypeStalker
        SetInfoText("$IntelEngine_TypeStalker_Info")
    ElseIf optionId == OID_TypeMessage
        SetInfoText("$IntelEngine_TypeMessage_Info")
    ElseIf optionId == OID_TypeQuest
        SetInfoText("$IntelEngine_TypeQuest_Info")
    ElseIf optionId == OID_TypeNPCInteraction
        SetInfoText("$IntelEngine_KindVisit_Info")
    ElseIf optionId == OID_TypeNPCGossip
        SetInfoText("$IntelEngine_KindGossip_Info")
    ElseIf optionId == OID_StoryForceRestart
        SetInfoText("$IntelEngine_ForceRestart_Info")
    ElseIf optionId == OID_NPCTickEnabled
        SetInfoText("$IntelEngine_NpcVisits_Info")
    ElseIf optionId == OID_NPCTickInterval
        SetInfoText("$IntelEngine_NpcInterval_Info")
    ElseIf optionId == OID_NPCSocialCooldown
        SetInfoText("$IntelEngine_RestPerNpc_Info")
    ElseIf optionId == OID_QuestCombat
        SetInfoText("$IntelEngine_QuestClearOut_Info")
    ElseIf optionId == OID_QuestRescue
        SetInfoText("$IntelEngine_QuestRescue_Info")
    ElseIf optionId == OID_QuestFindItem
        SetInfoText("$IntelEngine_QuestFindItem_Info")
    ElseIf optionId == OID_QuestFactionCombat
        SetInfoText("$IntelEngine_QuestFactionFight_Info")
    ElseIf optionId == OID_QuestFactionRescue
        SetInfoText("$IntelEngine_QuestFactionRescue_Info")
    ElseIf optionId == OID_QuestFactionBattle
        SetInfoText("$IntelEngine_QuestFactionBattle_Info")
    ElseIf optionId == OID_PoliticsEnabled
        SetInfoText("$IntelEngine_FactionPolitics_Info")
    ElseIf optionId == OID_PoliticsTickInterval
        SetInfoText("$IntelEngine_PoliticsInterval_Info")
    ElseIf optionId == OID_PEIntegration
        SetInfoText("$IntelEngine_PEIntegration_Info")
    ElseIf optionId == OID_PEReactions
        SetInfoText("$IntelEngine_PEReactions_Info")
    Else
        String holdDefault = HoldDefaultText(optionId)
        If holdDefault != ""
            SetInfoText(holdDefault)
        EndIf
    EndIf
EndEvent

String Function HoldDefaultText(Int optionId)
    {Help text of a Hold Restrictions option: what it limits, and the default of its story type. The page used
    to say "Default: Same Hold (Civilians)" for all seven types, which is true for three. The story type and its
    default are keys of their own, given as the values of the one help key.}
    If optionId >= OID_HoldSeekNone && optionId <= OID_HoldSeekLocalAll
        Return "$IntelEngine_HoldInfo{$IntelEngine_TypeSeek}{$IntelEngine_HoldCivilians}"
    ElseIf optionId >= OID_HoldInformantNone && optionId <= OID_HoldInformantLocalAll
        Return "$IntelEngine_HoldInfo{$IntelEngine_TypeInformant}{$IntelEngine_TownEveryone}"
    ElseIf optionId >= OID_HoldRoadNone && optionId <= OID_HoldRoadLocalAll
        Return "$IntelEngine_HoldInfo{$IntelEngine_TypeRoad}{$IntelEngine_HoldNone}"
    ElseIf optionId >= OID_HoldAmbushNone && optionId <= OID_HoldAmbushLocalAll
        Return "$IntelEngine_HoldInfo{$IntelEngine_TypeAmbush}{$IntelEngine_HoldCivilians}"
    ElseIf optionId >= OID_HoldStalkerNone && optionId <= OID_HoldStalkerLocalAll
        Return "$IntelEngine_HoldInfo{$IntelEngine_TypeStalker}{$IntelEngine_HoldCivilians}"
    ElseIf optionId >= OID_HoldMessageNone && optionId <= OID_HoldMessageLocalAll
        Return "$IntelEngine_HoldInfo{$IntelEngine_TypeMessage}{$IntelEngine_HoldExceptFollowers}"
    ElseIf optionId >= OID_HoldQuestNone && optionId <= OID_HoldQuestLocalAll
        Return "$IntelEngine_HoldInfo{$IntelEngine_TypeQuest}{$IntelEngine_HoldNone}"
    EndIf
    Return ""
EndFunction

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
                Bool confirm = ShowMessage(ScheduleRow(display, true), true, "$Yes", "$No")
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

    Bool confirm = ShowMessage(ClearQuestion(slot, status), true, "$Yes", "$No")
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
        ; A notice, not the menu: SkyUI's translation files do not reach it; the language packs do (IntelEngine.L).
        Debug.Notification(IntelEngine.L("IntelEngine: Slot " + slot + " cleared"))
        ForcePageReset()
    EndIf
EndFunction

