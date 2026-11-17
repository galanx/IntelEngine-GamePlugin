Scriptname IntelEngine_Threads extends Quest
{IntelEngine 4.0 storylines: shows what someone asked of the player in the journal ("Unfinished Business", six
slots of objectives under Miscellaneous), watches what happens, and hands the ending to the people in it. The record
and the rules are in the DLL (Storylines.h, StorylineBridge.cpp); this script shows, watches and applies.
At the Classic level of "How alive the world is" nothing opens here.}

; ----------------------------------------------------------------------------------------------- numbers of the DLL
; Aliases of a slot, in the order esp/EspBuilder makes them: slot * 4 + this.
Int Property ALIAS_NPC = 0 AutoReadOnly
Int Property ALIAS_TARGET = 1 AutoReadOnly
Int Property ALIAS_PLACE = 2 AutoReadOnly
Int Property ALIAS_ITEM = 3 AutoReadOnly
Int Property SLOTS = 6 AutoReadOnly

Int Property KIND_MEETING = 1 AutoReadOnly
Int Property KIND_REQUEST = 2 AutoReadOnly

Int Property REQ_FIND = 1 AutoReadOnly
Int Property REQ_ITEM = 2 AutoReadOnly
Int Property REQ_THREAT = 3 AutoReadOnly
Int Property REQ_ESCORT = 4 AutoReadOnly
Int Property REQ_WORD = 5 AutoReadOnly
Int Property REQ_RESCUE = 6 AutoReadOnly

Int Property STAGE_OPEN = 0 AutoReadOnly
Int Property STAGE_RETURN = 1 AutoReadOnly
Int Property STAGE_DONE = 10 AutoReadOnly
Int Property STAGE_FAILED = 13 AutoReadOnly

Int Property EV_ACHIEVED = 1 AutoReadOnly
Int Property EV_MET = 2 AutoReadOnly
Int Property EV_DECLINED = 3 AutoReadOnly
Int Property EV_TIME = 4 AutoReadOnly
Int Property EV_DIED = 5 AutoReadOnly
Int Property EV_TALKED = 6 AutoReadOnly
Int Property EV_NOSHOW = 7 AutoReadOnly
Int Property EV_FELLTHROUGH = 8 AutoReadOnly

Int Property OBJ_MEET = 0 AutoReadOnly
Int Property OBJ_FIND = 1 AutoReadOnly
Int Property OBJ_SPEAK = 2 AutoReadOnly
Int Property OBJ_RESCUE = 3 AutoReadOnly
Int Property OBJ_RETURN = 5 AutoReadOnly
Int Property OBJ_CONFRONT = 6 AutoReadOnly
Int Property OBJ_RECOVER = 7 AutoReadOnly

Float Property WATCH_SECONDS = 2.0 AutoReadOnly

; Hidden, disabled references that only lend an item's name to the journal ("Recover <item> for <name>").
ObjectReference[] NameHolders
IntelEngine_Core CoreScript

; ----------------------------------------------------------------------------------------------- opening

IntelEngine_Core Function Core()
    If CoreScript == None
        CoreScript = Quest.GetQuest("IntelEngine") as IntelEngine_Core
    EndIf
    Return CoreScript
EndFunction

Bool Function Enabled()
    IntelEngine_Core c = Core()
    Return c != None && c.StoryEngine != None && c.StoryEngine.LivingWorldLevel > 0
EndFunction

Function Begin()
    If !IsRunning()
        Start()
    EndIf
    If NameHolders.Length != SLOTS
        NameHolders = new ObjectReference[6]
    EndIf
    RegisterForSingleUpdate(WATCH_SECONDS)
EndFunction

Function Resume()
    {On every load: the watch goes on where a storyline is open.}
    If IntelEngine.StorylineOpenIds().Length > 0
        Begin()
    EndIf
EndFunction

Int Function OpenMeeting(Actor owner, ObjectReference destination, Float days)
    {A meeting the player agreed to: "Meet <owner> at <place>", the marker on the meeting spot.}
    If !Enabled() || owner == None || destination == None
        Return 0
    EndIf
    Location place = destination.GetCurrentLocation()
    ; urgent: a meeting the player agreed to is recorded whatever the director's variety rule would say
    Int id = IntelEngine.StorylineOpen(KIND_MEETING, 0, owner, None, place, destination, None, days, 2, true)
    If id > 0
        ; The meeting system runs this meeting and reports how it went (OnMeetingOutcome); the watch leaves it alone.
        StorageUtil.SetIntValue(owner, "Intel_StorylineScheduled", id)
        Begin()
        Show(id)
    EndIf
    Return id
EndFunction

Int Function OpenRequest(Int request, Actor owner, Actor other, ObjectReference destination, Form item, Float days, Int importance)
    {Something the player was asked to do, shown with its objective and marker.}
    If !Enabled() || owner == None
        Return 0
    EndIf
    Location place = None
    If destination != None
        place = destination.GetCurrentLocation()
    ElseIf other != None
        place = other.GetCurrentLocation()
    EndIf
    ; urgent: asked in conversation, so it is recorded whatever the director's variety rule would say
    Int id = IntelEngine.StorylineOpen(KIND_REQUEST, request, owner, other, place, destination, item, days, importance, true)
    If id <= 0
        Return 0
    EndIf
    Begin()
    Show(id)
    If request == REQ_ESCORT
        Follow(owner, true)
    EndIf
    Return id
EndFunction

; ----------------------------------------------------------------------------------------------- the journal

Function Show(Int id)
    Int slot = IntelEngine.StorylineField(id, "slot")
    Int objective = IntelEngine.StorylineField(id, "objective")
    If slot < 0 || slot >= SLOTS || objective < 0 || objective > 9
        Return
    EndIf
    Actor owner = IntelEngine.StorylineOwner(id)
    Actor other = IntelEngine.StorylineOther(id)
    Location place = IntelEngine.StorylinePlace(id)
    ObjectReference target = IntelEngine.StorylineTarget(id)
    Form item = IntelEngine.StorylineItem(id)

    ; The name in the objective: the one it is about (to find, free, speak with, confront), else the one who asked.
    Actor named = owner
    If other != None && (objective == OBJ_FIND || objective == OBJ_SPEAK || objective == OBJ_RESCUE || objective == OBJ_CONFRONT)
        named = other
    EndIf
    (GetAlias(slot * 4 + ALIAS_NPC) as ReferenceAlias).ForceRefTo(named)

    ; The marker: going back points at the one who asked; otherwise the target, else the person it is about.
    ObjectReference marker = target
    If objective == OBJ_RETURN || (marker == None && (objective == OBJ_MEET || objective == OBJ_RECOVER))
        marker = owner
    ElseIf marker == None && other != None
        marker = other
    EndIf
    ReferenceAlias targetAlias = GetAlias(slot * 4 + ALIAS_TARGET) as ReferenceAlias
    If marker != None
        targetAlias.ForceRefTo(marker)
    Else
        targetAlias.Clear()
    EndIf
    LocationAlias placeAlias = GetAlias(slot * 4 + ALIAS_PLACE) as LocationAlias
    If place != None
        placeAlias.ForceLocationTo(place)
    Else
        placeAlias.Clear()
    EndIf
    ReferenceAlias itemAlias = GetAlias(slot * 4 + ALIAS_ITEM) as ReferenceAlias
    If item != None
        ObjectReference itemRef = item as ObjectReference
        If itemRef == None
            itemRef = NameHolder(slot, item)
        EndIf
        If itemRef != None
            itemAlias.ForceRefTo(itemRef)
        EndIf
    Else
        itemAlias.Clear()
    EndIf

    HideSlot(slot)
    SetObjectiveDisplayed(slot * 10 + objective, true, true)
    SetActive(true)
EndFunction

ObjectReference Function NameHolder(Int slot, Form item)
    {A disabled reference of the item, out of the way, so the journal can name it.}
    DropNameHolder(slot)
    ObjectReference holder = Game.GetPlayer().PlaceAtMe(item, 1, false, true)
    If holder != None
        holder.SetPosition(holder.GetPositionX(), holder.GetPositionY(), holder.GetPositionZ() - 10000.0)
        NameHolders[slot] = holder
    EndIf
    Return holder
EndFunction

Function DropNameHolder(Int slot)
    If NameHolders.Length == SLOTS && NameHolders[slot] != None
        NameHolders[slot].Delete()
        NameHolders[slot] = None
    EndIf
EndFunction

Function HideSlot(Int slot)
    Int k = 0
    While k < 10
        Int index = slot * 10 + k
        If IsObjectiveDisplayed(index) && !IsObjectiveCompleted(index) && !IsObjectiveFailed(index)
            SetObjectiveDisplayed(index, false)
        EndIf
        k += 1
    EndWhile
EndFunction

Function ClearSlot(Int slot)
    (GetAlias(slot * 4 + ALIAS_NPC) as ReferenceAlias).Clear()
    (GetAlias(slot * 4 + ALIAS_TARGET) as ReferenceAlias).Clear()
    (GetAlias(slot * 4 + ALIAS_PLACE) as LocationAlias).Clear()
    (GetAlias(slot * 4 + ALIAS_ITEM) as ReferenceAlias).Clear()
    DropNameHolder(slot)
EndFunction

; ----------------------------------------------------------------------------------------------- what happened

Function Report(Int id, Int eventId)
    {Tell the DLL what happened; show the next objective or hand the ending to the people in it.}
    Int slot = IntelEngine.StorylineField(id, "slot")
    Int before = IntelEngine.StorylineField(id, "objective")
    If !IntelEngine.StorylineEvent(id, eventId)
        Return
    EndIf
    Int stage = IntelEngine.StorylineField(id, "stage")
    If slot >= 0 && slot < SLOTS && before >= 0 && before <= 9
        Int index = slot * 10 + before
        If stage == STAGE_DONE || stage == STAGE_RETURN
            SetObjectiveCompleted(index, true)
        ElseIf stage == STAGE_FAILED
            SetObjectiveFailed(index, true)
        Else
            SetObjectiveDisplayed(index, false)
        EndIf
    EndIf
    If stage == STAGE_RETURN
        Show(id)
    ElseIf stage >= STAGE_DONE
        Ended(id, stage, slot)
    EndIf
EndFunction

Function Ended(Int id, Int stage, Int slot)
    Actor owner = IntelEngine.StorylineOwner(id)
    Actor player = Game.GetPlayer()
    If IntelEngine.StorylineField(id, "request") == REQ_ESCORT
        Follow(owner, false)
    EndIf
    String memory = IntelEngine.StorylineMemory(id)
    If owner != None && memory != ""
        Core().SendPersistentMemory(owner, player, memory)
    EndIf
    If stage == STAGE_DONE
        Int gold = IntelEngine.StorylineReward(id, player.GetLevel())
        If gold > 0 && owner != None
            player.AddItem(Game.GetFormFromFile(0x0000000F, "Skyrim.esm"), gold, true)
            Core().NotifyPlayer(owner.GetDisplayName() + " gave you " + gold + " gold.")
            Core().SendPersistentMemory(owner, player, "I gave " + player.GetDisplayName() + " " + gold + " gold for it.")
        EndIf
    EndIf
    If owner != None && StorageUtil.GetIntValue(owner, "Intel_StorylineScheduled", 0) == id
        StorageUtil.UnsetIntValue(owner, "Intel_StorylineScheduled")
    EndIf
    If slot >= 0 && slot < SLOTS
        ClearSlot(slot)
    EndIf
EndFunction

Function OnMeetingOutcome(Actor npc, String outcome)
    {From Core.StoreMeetingOutcome: how a meeting the meeting system arranged went.}
    If npc == None
        Return
    EndIf
    Int id = IntelEngine.StorylineOpenIdFor(npc)
    If id <= 0 || IntelEngine.StorylineField(id, "kind") != KIND_MEETING
        Return
    EndIf
    If outcome == "player_no_show" || outcome == "npc_late_player_no_show"
        Report(id, EV_NOSHOW)
    ElseIf outcome == "npc_late"
        Report(id, EV_FELLTHROUGH)
    Else
        Report(id, EV_MET)
    EndIf
EndFunction

Function Decline(Actor owner)
    {The player turned down what this NPC asked (the PlayerTurnsDownRequest action).}
    Int id = IntelEngine.StorylineOpenIdFor(owner)
    If id > 0
        Report(id, EV_DECLINED)
    EndIf
EndFunction

; ----------------------------------------------------------------------------------------------- watching

Event OnUpdate()
    Watch()
    Int[] open = IntelEngine.StorylineOpenIds()
    If open.Length > 0
        RegisterForSingleUpdate(WATCH_SECONDS)
    EndIf
EndEvent

Function Watch()
    Int[] overdue = IntelEngine.StorylineOverdue()
    Int i = 0
    While i < overdue.Length
        Report(overdue[i], EV_TIME)
        i += 1
    EndWhile
    Int[] ids = IntelEngine.StorylineOpenIds()
    Actor player = Game.GetPlayer()
    i = 0
    While i < ids.Length
        WatchOne(ids[i], player)
        i += 1
    EndWhile
EndFunction

Function WatchOne(Int id, Actor player)
    Actor owner = IntelEngine.StorylineOwner(id)
    If owner == None
        Return
    EndIf
    Int kind = IntelEngine.StorylineField(id, "kind")
    Int request = IntelEngine.StorylineField(id, "request")
    Int stage = IntelEngine.StorylineField(id, "stage")
    Actor other = IntelEngine.StorylineOther(id)
    If owner.IsDead()
        Report(id, EV_DIED)
        Return
    EndIf
    ; The death of the one to deal with is the deed itself; anyone else's death ends it badly.
    If other != None && other.IsDead() && request != REQ_THREAT
        Report(id, EV_DIED)
        Return
    EndIf
    ObjectReference target = IntelEngine.StorylineTarget(id)
    If kind == KIND_MEETING
        ; A meeting the meeting system runs is reported by Core.StoreMeetingOutcome (OnMeetingOutcome). Any other
        ; meeting counts as kept when the player is with them at the spot.
        If StorageUtil.GetIntValue(owner, "Intel_StorylineScheduled", 0) != id && Near(player, owner, 400.0) && target != None && Near(player, target, 1500.0)
            Report(id, EV_MET)
        EndIf
        Return
    EndIf
    If kind != KIND_REQUEST
        Return
    EndIf
    If stage == STAGE_RETURN
        If Near(player, owner, 300.0) && Spoke(owner)
            If request == REQ_ITEM
                Form asked = IntelEngine.StorylineItem(id)
                Form held = None
                If asked != None
                    held = IntelEngine.FindItemNamedExactly(player, asked.GetName())
                EndIf
                If held == None
                    Return                                   ; the item is gone again: not yet
                EndIf
                player.RemoveItem(held, 1, false, owner)
            EndIf
            Report(id, EV_MET)
        EndIf
        Return
    EndIf
    If request == REQ_FIND
        If other != None && Near(player, other, 400.0) && player.HasLOS(other)
            Report(id, EV_ACHIEVED)
        EndIf
    ElseIf request == REQ_WORD
        If other != None && Near(player, other, 300.0) && Spoke(other)
            Report(id, EV_TALKED)
        EndIf
    ElseIf request == REQ_ITEM
        ; Any item of that name counts (two mods may both have an "Ale").
        Form wanted = IntelEngine.StorylineItem(id)
        If wanted != None && IntelEngine.FindItemNamedExactly(player, wanted.GetName()) != None
            Report(id, EV_ACHIEVED)
        EndIf
    ElseIf request == REQ_ESCORT
        If target != None && Near(owner, target, 700.0) && Near(player, owner, 1500.0)
            Report(id, EV_ACHIEVED)
        EndIf
    ElseIf request == REQ_THREAT
        If other != None && other.IsDead()
            Report(id, EV_ACHIEVED)
        EndIf
    ElseIf request == REQ_RESCUE
        If other != None && Near(player, other, 300.0)
            Report(id, EV_ACHIEVED)
        EndIf
    EndIf
EndFunction

Bool Function Near(ObjectReference a, ObjectReference b, Float distance)
    {Within this distance in the same space. GetDistance is 0 across worldspaces, so the space is checked first.}
    If a == None || b == None || !a.Is3DLoaded() || !b.Is3DLoaded()
        Return false
    EndIf
    If a.GetWorldSpace() != b.GetWorldSpace()
        Return false
    EndIf
    If a.IsInInterior() && a.GetParentCell() != b.GetParentCell()
        Return false
    EndIf
    Return a.GetDistance(b) <= distance
EndFunction

Bool Function Spoke(Actor npc)
    {They said something in the last twenty seconds (SkyrimNet's speech events): a conversation is going on.}
    Float since = IntelEngine.GetSecondsSinceNPCSpoke(npc)
    Return since >= 0.0 && since <= 20.0
EndFunction

Function Follow(Actor npc, Bool start)
    {Someone the player takes somewhere follows the player (IntelEngine's own follow-the-player package).}
    If npc == None
        Return
    EndIf
    Package followPackage = Game.GetFormFromFile(0x00001836, "IntelEngine.esp") as Package
    If followPackage == None
        Return
    EndIf
    If start
        ActorUtil.AddPackageOverride(npc, followPackage, 100, 1)
    Else
        ActorUtil.RemovePackageOverride(npc, followPackage)
    EndIf
    npc.EvaluatePackage()
EndFunction

; ----------------------------------------------------------------------------------------------- SkyrimNet actions

Function AskPlayerForHelp(Actor akNPC, String helpKind, String subject, String place)
    {The AskPlayerForHelp action: the NPC asks the player for something real. The person, item or place must exist;
    otherwise nothing opens and the NPC learns why.}
    If akNPC == None || !Enabled()
        Return
    EndIf
    Actor player = Game.GetPlayer()
    Int request = 0
    Actor other = None
    ObjectReference destination = None
    Form item = None
    String kindLower = helpKind
    If kindLower == "find_person" || kindLower == "deliver_word"
        request = REQ_FIND
        If kindLower == "deliver_word"
            request = REQ_WORD
        EndIf
        other = IntelEngine.FindNPCByName(subject)
        If other == None || other == player || other == akNPC
            Core().SendTransientEvent(akNPC, player, "There is nobody called " + subject + " to ask " + player.GetDisplayName() + " about.")
            Return
        EndIf
    ElseIf kindLower == "bring_item"
        request = REQ_ITEM
        item = IntelEngine.ResolveItemByName(subject)
        If item == None
            Core().SendTransientEvent(akNPC, player, "There is no such thing as " + subject + " to ask " + player.GetDisplayName() + " for.")
            Return
        EndIf
    ElseIf kindLower == "escort_me"
        request = REQ_ESCORT
        destination = IntelEngine.ResolveAnyDestination(akNPC, place)
        If destination == None
            Core().SendTransientEvent(akNPC, player, "There is no place called " + place + " to be taken to.")
            Return
        EndIf
    Else
        Return
    EndIf
    String refusal = IntelEngine.StorylineRefusal(KIND_REQUEST, request, akNPC)
    If refusal != ""
        ; Only the hard limits are left here (six open, one per person): the NPC learns it, so the talk stays true.
        Core().DebugMsg("Storylines: " + akNPC.GetDisplayName() + " cannot ask now: " + refusal)
        Core().SendTransientEvent(akNPC, player, player.GetDisplayName() + " has too many other people's errands on their hands to take this one on now.")
        Return
    EndIf
    Float days = 3.0
    If request == REQ_ESCORT
        days = 1.0
    EndIf
    ; What they asked shows in their bio from now on (get_intelengine_storylines), so no memory is written here.
    OpenRequest(request, akNPC, other, destination, item, days, 2)
EndFunction

Function PlayerTurnsDownRequest(Actor akNPC)
    {The PlayerTurnsDownRequest action: the player said no to what this NPC asked.}
    Decline(akNPC)
EndFunction
