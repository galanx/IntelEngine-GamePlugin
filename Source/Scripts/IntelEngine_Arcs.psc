Scriptname IntelEngine_Arcs extends Quest
{IntelEngine 4.0 story arcs (docs/STORY_ARCS.md in the native plugin): stories of several steps whose people are real
people of a town, whose clues are real items in real homes, and whose branches follow facts of the game and the
player's own choices, never what anyone says. The record and every decision are in the DLL (Arcs.h, ArcBridge.cpp);
this script offers, shows, hides the props, asks the choices, pays and takes people away. It runs on its own quest,
IntelEngine_ArcKeeper; the journal quests IntelEngine_Arc0..3 have no script.}

; ----------------------------------------------------------------------------------------------- numbers of the DLL
Int Property SLOTS = 4 AutoReadOnly
Int Property PHASE_PLANNED = 0 AutoReadOnly
Int Property PHASE_OPEN = 1 AutoReadOnly
Int Property ENDING_DONE = 10 AutoReadOnly
Int Property ENDING_SETTLED = 18 AutoReadOnly
Int Property ENDING_STAYEDOUT = 19 AutoReadOnly
Int Property EFFECT_PAYGOLD = 1 AutoReadOnly
Int Property EFFECT_JAIL = 2 AutoReadOnly
Int Property EFFECT_SHAME = 3 AutoReadOnly
Int Property EFFECT_PLAYERPAYS = 5 AutoReadOnly
Int Property SIGNAL_PLANT = 16777216 AutoReadOnly    ; 1 << 24
Int Property SIGNAL_CHOOSE = 33554432 AutoReadOnly   ; 1 << 25
Int Property SIGNAL_GIVE = 67108864 AutoReadOnly     ; 1 << 26
; Aliases of an arc's journal quest, in the order esp/EspBuilder makes them.
Int Property ALIAS_ASKER = 0 AutoReadOnly
Int Property ALIAS_CULPRIT = 1 AutoReadOnly
Int Property ALIAS_WITNESS = 2 AutoReadOnly
Int Property ALIAS_RIVAL = 3 AutoReadOnly
Int Property ALIAS_VICTIM = 4 AutoReadOnly
Int Property ALIAS_SUSPECT2 = 5 AutoReadOnly
Int Property ALIAS_SUSPECT3 = 6 AutoReadOnly
Int Property ALIAS_ITEM0 = 7 AutoReadOnly
Int Property ALIAS_ITEM1 = 8 AutoReadOnly
Int Property ALIAS_MARKER = 9 AutoReadOnly
Int Property ALIAS_PLACE = 10 AutoReadOnly

Float Property WATCH_SECONDS = 2.0 AutoReadOnly
Float Property JAIL_DAYS = 2.0 AutoReadOnly

; Hidden, disabled references that lend the props' names to the journal: two per slot.
ObjectReference[] NameHolders
IntelEngine_Core CoreScript

; ----------------------------------------------------------------------------------------------- starting

IntelEngine_Core Function Core()
    If CoreScript == None
        CoreScript = Quest.GetQuest("IntelEngine") as IntelEngine_Core
    EndIf
    Return CoreScript
EndFunction

IntelEngine_Quests Function Quests()
    Return Quest.GetQuest("IntelEngine_QuestKeeper") as IntelEngine_Quests
EndFunction

Bool Function Enabled()
    IntelEngine_Core c = Core()
    Return c != None && c.StoryEngine != None && c.StoryEngine.LivingWorldLevel > 0
EndFunction

Event OnInit()
    Begin()
EndEvent

Function Begin()
    {On start and on every load (Core's maintenance): the events, the watch.}
    If NameHolders.Length != SLOTS * 2
        NameHolders = new ObjectReference[8]
    EndIf
    RegisterForModEvent("IntelEngine_ArcAskerArrived", "OnAskerArrived")
    RegisterForSingleUpdate(WATCH_SECONDS)
EndFunction

Quest Function JournalQuest(Int slot)
    If slot < 0 || slot >= SLOTS
        Return None
    EndIf
    Return Quest.GetQuest("IntelEngine_Arc" + slot)
EndFunction

; ----------------------------------------------------------------------------------------------- the offer

Int Function DebugArc(Actor asker, Int pattern = 0)
    {Test hook (in-game tests): plans an arc with this asker as the director will and sends them to the player to ask;
    the id, 0 when none fits or they cannot come.}
    Int id = IntelEngine.ArcPlan(asker, pattern)
    If id <= 0
        Return 0
    EndIf
    IntelEngine_Core c = Core()
    If c == None || c.StoryEngine == None || !c.StoryEngine.DispatchArcOffer(asker, id)
        IntelEngine.ArcDecline(id)
        Return 0
    EndIf
    Return id
EndFunction

Event OnAskerArrived(Form askerForm, Int id)
    {The asker reached the player and was told to speak (StoryEngine, seek_player arrival). Once their say is over, the
    player chooses in the popup.}
    Actor asker = askerForm as Actor
    Actor player = Game.GetPlayer()
    If asker == None || id <= 0 || IntelEngine.ArcField(id, "phase") != PHASE_PLANNED
        Return
    EndIf
    ; Let them have their say first: the popup never cuts a line off.
    Utility.Wait(2.0)
    Quests().WaitForTheirSay(asker, 30.0)
    If IntelEngine.ArcField(id, "phase") != PHASE_PLANNED || asker.IsDead() || asker.IsInCombat()
        Return
    EndIf
    String choice = Core().ShowChoice(asker.GetDisplayName(), "Quest offer", IntelEngine.ArcText(id, "prompt"), "I'll do it", "Not now")
    If IntelEngine.ArcField(id, "phase") != PHASE_PLANNED
        Return
    EndIf
    If choice == "I'll do it" && IntelEngine.ArcAccept(id)
        Core().SendTaskNarration(asker, "was told that " + player.GetDisplayName() + " will do it", player)
        Open(id)
    Else
        IntelEngine.ArcDecline(id)
        Core().SendTaskNarration(asker, "was told that " + player.GetDisplayName() + " will not do it", player)
    EndIf
EndEvent

; ----------------------------------------------------------------------------------------------- the journal

Function Open(Int id)
    {Taken on: the journal quest of its slot starts with its title (set by the DLL), its first log entry and the first
    objective.}
    Int slot = IntelEngine.ArcField(id, "slot")
    Quest jq = JournalQuest(slot)
    If jq == None
        Core().DebugMsg("Arcs: no journal quest for slot " + slot)
        Return
    EndIf
    If jq.IsRunning()
        jq.Stop()
    EndIf
    jq.Reset()
    DropNameHolders(slot)
    If !jq.Start()
        Core().DebugMsg("Arcs: journal quest " + slot + " did not start")
    EndIf
    IntelEngine.ArcApplyTitles()
    Force(jq, ALIAS_ASKER, IntelEngine.ArcForm(id, "asker") as ObjectReference)
    Force(jq, ALIAS_CULPRIT, IntelEngine.ArcForm(id, "culprit") as ObjectReference)
    Force(jq, ALIAS_WITNESS, IntelEngine.ArcForm(id, "witness") as ObjectReference)
    Force(jq, ALIAS_RIVAL, IntelEngine.ArcForm(id, "rival") as ObjectReference)
    Force(jq, ALIAS_VICTIM, IntelEngine.ArcForm(id, "victim") as ObjectReference)
    Force(jq, ALIAS_SUSPECT2, IntelEngine.ArcForm(id, "suspect2") as ObjectReference)
    Force(jq, ALIAS_SUSPECT3, IntelEngine.ArcForm(id, "suspect3") as ObjectReference)
    Location place = IntelEngine.ArcForm(id, "place") as Location
    LocationAlias placeAlias = jq.GetAlias(ALIAS_PLACE) as LocationAlias
    If placeAlias != None && place != None
        placeAlias.ForceLocationTo(place)
    EndIf
    Int p = 0
    While p < 2
        Form item = IntelEngine.ArcForm(id, "prop" + p)
        If item != None
            ObjectReference holder = Game.GetPlayer().PlaceAtMe(item, 1, false, true)
            If holder != None
                holder.SetPosition(holder.GetPositionX(), holder.GetPositionY(), holder.GetPositionZ() - 10000.0)
                holder.SetDisplayName(IntelEngine.ArcText(id, "prop" + p), true)
                NameHolders[slot * 2 + p] = holder
                Force(jq, ALIAS_ITEM0 + p, holder)
            EndIf
        EndIf
        p += 1
    EndWhile
    jq.SetStage(IntelEngine.ArcField(id, "openstage"))
    ShowStep(id, jq)
    jq.SetActive(true)
EndFunction

Function Force(Quest jq, Int aliasIndex, ObjectReference ref)
    ReferenceAlias a = jq.GetAlias(aliasIndex) as ReferenceAlias
    If a == None
        Return
    EndIf
    If ref != None
        a.ForceRefTo(ref)
    Else
        a.Clear()
    EndIf
EndFunction

Function DropNameHolders(Int slot)
    Int p = 0
    While p < 2
        If NameHolders.Length == SLOTS * 2 && NameHolders[slot * 2 + p] != None
            NameHolders[slot * 2 + p].Delete()
            NameHolders[slot * 2 + p] = None
        EndIf
        p += 1
    EndWhile
EndFunction

Function ShowStep(Int id, Quest jq)
    {The objective of the node the player is on, its marker on what the node is about. A node come back to (proof
    still wanted) shows its objective again.}
    Int objective = IntelEngine.ArcField(id, "objective")
    If objective < 0 || jq == None
        Return
    EndIf
    Force(jq, ALIAS_MARKER, IntelEngine.ArcForm(id, "marker") as ObjectReference)
    If jq.IsObjectiveCompleted(objective)
        jq.SetObjectiveCompleted(objective, false)
    EndIf
    jq.SetObjectiveDisplayed(objective, true, true)
EndFunction

; ----------------------------------------------------------------------------------------------- the watch

Event OnUpdate()
    If Enabled()
        Watch()
    EndIf
    RegisterForSingleUpdate(WATCH_SECONDS)
EndEvent

Function Watch()
    Int[] lapsed = IntelEngine.ArcLapse()
    Int i = 0
    While i < lapsed.Length
        Actor asker = IntelEngine.ArcForm(lapsed[i], "asker") as Actor
        If asker != None
            StorageUtil.UnsetIntValue(asker, "Intel_ArcOffer")
        EndIf
        i += 1
    EndWhile
    Int[] ids = IntelEngine.ArcOpenIds()
    i = 0
    While i < ids.Length
        WatchOne(ids[i])
        i += 1
    EndWhile
    WatchJailed()
EndFunction

Function WatchOne(Int id)
    Int r = IntelEngine.ArcAdvance(id)
    If r == 0
        Return
    EndIf
    Quest jq = JournalQuest(IntelEngine.ArcField(id, "slot"))
    If Math.LogicalAnd(r, SIGNAL_PLANT) != 0
        Plant(id)
    EndIf
    Int change = Math.LogicalAnd(r, 16777215)
    Int skipped = Math.LogicalAnd(Math.RightShift(r, 27), 15)
    If skipped > 0 && jq != None
        ; A node left by a shortcut (found before the witness was asked): its objective goes, it never happened.
        Int gone = IntelEngine.ArcField(id, "objective" + (skipped - 1))
        If gone >= 0 && jq.IsObjectiveDisplayed(gone) && !jq.IsObjectiveCompleted(gone)
            jq.SetObjectiveDisplayed(gone, false)
        EndIf
    EndIf
    If change != 0 || skipped > 0
        Settle(id, change, jq)
    ElseIf Math.LogicalAnd(r, SIGNAL_CHOOSE) != 0
        OfferChoice(id, jq)
    ElseIf Math.LogicalAnd(r, SIGNAL_GIVE) != 0
        OfferGive(id, jq)
    ElseIf Math.LogicalAnd(r, SIGNAL_PLANT) != 0 && jq != None
        ShowStep(id, jq)   ; the marker moves to where the prop now is
    EndIf
EndFunction

Function Settle(Int id, Int r, Quest jq)
    {Nodes done now: their objectives completed, the log of the branch taken; the effect; then the next node, or the
    ending.}
    Int done = Math.LogicalAnd(r, 255)
    Int ending = Math.LogicalAnd(Math.RightShift(r, 8), 255)
    Int effect = Math.LogicalAnd(Math.RightShift(r, 16), 15)
    Int role = Math.LogicalAnd(Math.RightShift(r, 20), 15)
    Int nodes = IntelEngine.ArcField(id, "nodes")
    Int i = 0
    While i < nodes
        If Math.LogicalAnd(done, Math.LeftShift(1, i)) != 0
            Int objective = IntelEngine.ArcField(id, "objective" + i)
            If jq != None && objective >= 0 && jq.IsObjectiveDisplayed(objective)
                jq.SetObjectiveCompleted(objective, true)
            EndIf
        EndIf
        i += 1
    EndWhile
    Int logStage = IntelEngine.ArcField(id, "log")
    If logStage > 0 && jq != None
        jq.SetStage(logStage)
    EndIf
    If effect > 0
        DoEffect(id, effect, role)
    EndIf
    If ending > 0
        Ended(id, ending, jq)
    ElseIf jq != None
        ShowStep(id, jq)
    EndIf
EndFunction

Function Ended(Int id, Int ending, Quest jq)
    {The ending's log entry completes or fails the journal quest. Memories and what the town hears are the DLL's.}
    If jq == None
        Return
    EndIf
    Int objective = IntelEngine.ArcField(id, "objective")
    Int stage = IntelEngine.ArcField(id, "endstage")
    Bool good = ending == ENDING_DONE || ending == ENDING_SETTLED || ending == ENDING_STAYEDOUT
    ; The objective the player was on: failed when it did not end well (the node of the ending is completed by Settle).
    Int last = 0
    While last < 12
        If jq.IsObjectiveDisplayed(last) && !jq.IsObjectiveCompleted(last) && !good
            jq.SetObjectiveFailed(last, true)
        EndIf
        last += 1
    EndWhile
    If stage > 0
        jq.SetStage(stage)
    EndIf
    Core().DebugMsg("Arcs: #" + id + " ended " + ending)
EndFunction

; ----------------------------------------------------------------------------------------------- choices and hand-overs

Function OfferChoice(Int id, Quest jq)
    {The node's person is right here and has just talked with the player: the player decides. With three answers a
    first popup asks whether to decide now (a popup holds three buttons at most); with two, "Not now" is the third.}
    Actor who = IntelEngine.ArcForm(id, "who") as Actor
    If who == None
        Return
    EndIf
    Quests().WaitForSilence(who, 15.0)
    String o0 = IntelEngine.ArcText(id, "option0")
    String o1 = IntelEngine.ArcText(id, "option1")
    String o2 = IntelEngine.ArcText(id, "option2")
    ; Answers the player cannot give now (gold they do not have) come back empty: the rest move up.
    String[] shown = new String[3]
    Int[] index = new Int[3]
    Int n = 0
    If o0 != ""
        shown[n] = o0
        index[n] = 0
        n += 1
    EndIf
    If o1 != ""
        shown[n] = o1
        index[n] = 1
        n += 1
    EndIf
    If o2 != ""
        shown[n] = o2
        index[n] = 2
        n += 1
    EndIf
    If n == 0
        Return
    EndIf
    String title = who.GetDisplayName()
    String question = IntelEngine.ArcText(id, "question")
    String choice = ""
    If n == 3
        If Core().ShowChoice(title, "Story", IntelEngine.ArcText(id, "ask"), "Yes", "Not now") != "Yes"
            IntelEngine.ArcAnswer(id, -1)
            Return
        EndIf
        choice = Core().ShowChoice(title, "Story", question, shown[0], shown[1], shown[2])
    ElseIf n == 2
        choice = Core().ShowChoice(title, "Story", question, shown[0], shown[1], "Not now")
    Else
        choice = Core().ShowChoice(title, "Story", question, shown[0], "Not now")
    EndIf
    Int picked = -1
    Int k = 0
    While k < n
        If choice == shown[k]
            picked = index[k]
        EndIf
        k += 1
    EndWhile
    IntelEngine.ArcAnswer(id, picked)
    If picked < 0
        Return
    EndIf
    Int r = IntelEngine.ArcAdvance(id)
    Int change = Math.LogicalAnd(r, 16777215)
    ; One line for them to react to: an effect brings its own (taken by the guard, paid), else the decision itself.
    If Math.LogicalAnd(Math.RightShift(change, 16), 15) == 0
        Core().SendTaskNarration(who, "hears the decision of " + Game.GetPlayer().GetDisplayName() + ": " + choice, Game.GetPlayer())
    EndIf
    If change != 0
        Settle(id, change, jq)
    EndIf
EndFunction

Function OfferGive(Int id, Quest jq)
    {The prop is in the player's pack and the one it goes to has just talked with the player: the player may hand it
    over. The engine moves it; nothing said can.}
    Actor who = IntelEngine.ArcForm(id, "giveto") as Actor
    If who == None
        Return
    EndIf
    Quests().WaitForSilence(who, 15.0)
    String choice = Core().ShowChoice(who.GetDisplayName(), "Hand over", IntelEngine.ArcText(id, "give"), "Hand it over", "Not yet")
    If choice != "Hand it over" || !IntelEngine.ArcHandOver(id)
        Return
    EndIf
    Int r = IntelEngine.ArcAdvance(id)
    Int change = Math.LogicalAnd(r, 16777215)
    If change != 0
        Settle(id, change, jq)
    EndIf
EndFunction

; ----------------------------------------------------------------------------------------------- the world

Function Plant(Int id)
    {A prop goes where the story hid it, now that the player is in that home (its things are loaded): into a container
    of theirs, or beside their bed. It belongs to the player, so taking it back is no theft.}
    ObjectReference at = IntelEngine.ArcForm(id, "plantat") as ObjectReference
    Int p = IntelEngine.ArcField(id, "plantprop")
    Form base = IntelEngine.ArcForm(id, "prop" + p)
    If at == None || base == None || p < 0
        IntelEngine.ArcPlanted(id, p, None)
        Return
    EndIf
    ObjectReference stamped = at.PlaceAtMe(base, 1, false, true)
    If stamped == None
        IntelEngine.ArcPlanted(id, p, None)
        Return
    EndIf
    stamped.SetDisplayName(IntelEngine.ArcText(id, "prop" + p), true)
    stamped.SetActorOwner(Game.GetPlayer().GetActorBase())
    If IntelEngine.ArcField(id, "plantfloor") == 1
        stamped.MoveTo(at, 0.0, 0.0, 60.0)
        stamped.Enable()
    Else
        at.AddItem(stamped, 1, true)
    EndIf
    IntelEngine.ArcPlanted(id, p, at)
    Core().DebugMsg("Arcs: #" + id + " " + IntelEngine.ArcText(id, "prop" + p) + " hidden at " + at)
EndFunction

Function DoEffect(Int id, Int effect, Int role)
    Actor player = Game.GetPlayer()
    Actor asker = IntelEngine.ArcForm(id, "asker") as Actor
    Actor target = IntelEngine.ArcForm(id, "role" + role) as Actor
    Int gold = IntelEngine.ArcField(id, "gold")
    Form septims = Game.GetFormFromFile(0x0000000F, "Skyrim.esm")
    If effect == EFFECT_PAYGOLD && gold > 0 && target != None
        ; What they already gave the player of it themselves (their own action) is not paid twice.
        Int owed = gold - IntelEngine.ArcField(id, "paid")
        If owed > 0
            player.AddItem(septims, owed, true)
            Core().NotifyPlayer(target.GetDisplayName() + " gave you " + owed + " gold.")
            If owed < gold
                Core().SendTaskNarration(target, "paid " + player.GetDisplayName() + " the rest of the " + gold + " gold promised", player)
            Else
                Core().SendTaskNarration(target, "paid " + player.GetDisplayName() + " the " + gold + " gold promised", player)
            EndIf
        Else
            Core().SendTaskNarration(target, "got it back, having already paid " + player.GetDisplayName() + " the " + gold + " gold promised", player)
        EndIf
    ElseIf effect == EFFECT_PLAYERPAYS && gold > 0 && target != None
        player.RemoveItem(septims, gold, true, target)
        Core().NotifyPlayer("You gave " + target.GetDisplayName() + " " + gold + " gold.")
    ElseIf effect == EFFECT_JAIL && target != None
        Jail(id, target)
    EndIf
EndFunction

; Taken by the guard: once nobody sees it happen, they are in the hold's jail for a couple of days, then let out
; where the hold lets prisoners out, and walk home.

Function Jail(Int id, Actor who)
    ObjectReference jailAt = IntelEngine.ArcForm(id, "jail") as ObjectReference
    If jailAt == None
        Core().DebugMsg("Arcs: #" + id + " no jail for " + who.GetDisplayName())
        Return
    EndIf
    Core().SendTaskNarration(who, "is caught: " + Game.GetPlayer().GetDisplayName() + " is handing them over to the guard", Game.GetPlayer())
    StorageUtil.SetFormValue(who, "Intel_ArcJailAt", jailAt)
    StorageUtil.SetFormValue(who, "Intel_ArcJailOut", IntelEngine.ArcForm(id, "jailout"))
    StorageUtil.SetFloatValue(who, "Intel_ArcJailUntil", Utility.GetCurrentGameTime() + JAIL_DAYS)
    StorageUtil.SetIntValue(who, "Intel_ArcJailed", 0)
    StorageUtil.FormListAdd(self, "Intel_ArcJail", who, false)
EndFunction

Bool Function Unseen(Actor who)
    Actor player = Game.GetPlayer()
    If !who.Is3DLoaded()
        Return true
    EndIf
    Return who.GetDistance(player) > 3000.0 && !player.HasLOS(who)
EndFunction

Function WatchJailed()
    Int n = StorageUtil.FormListCount(self, "Intel_ArcJail")
    Int i = n - 1
    While i >= 0
        Actor who = StorageUtil.FormListGet(self, "Intel_ArcJail", i) as Actor
        If who == None || who.IsDead()
            StorageUtil.FormListRemoveAt(self, "Intel_ArcJail", i)
        ElseIf StorageUtil.GetIntValue(who, "Intel_ArcJailed", 0) == 0
            ObjectReference jailAt = StorageUtil.GetFormValue(who, "Intel_ArcJailAt") as ObjectReference
            If Unseen(who) && jailAt != None
                IntelEngine_Lives lives = Quest.GetQuest("IntelEngine_Lives") as IntelEngine_Lives
                who.MoveTo(jailAt)
                If lives != None && lives.LifeSandbox != None
                    ActorUtil.AddPackageOverride(who, lives.LifeSandbox, 90, 1)
                EndIf
                who.EvaluatePackage()
                StorageUtil.SetIntValue(who, "Intel_ArcJailed", 1)
                Core().DebugMsg("Arcs: " + who.GetDisplayName() + " is in jail")
            EndIf
        ElseIf Utility.GetCurrentGameTime() >= StorageUtil.GetFloatValue(who, "Intel_ArcJailUntil") && Unseen(who)
            IntelEngine_Lives lives = Quest.GetQuest("IntelEngine_Lives") as IntelEngine_Lives
            If lives != None && lives.LifeSandbox != None
                ActorUtil.RemovePackageOverride(who, lives.LifeSandbox)
            EndIf
            ; Let out where the hold lets prisoners out; from there they walk home on their own.
            ObjectReference outAt = StorageUtil.GetFormValue(who, "Intel_ArcJailOut") as ObjectReference
            If outAt != None
                who.MoveTo(outAt)
            EndIf
            who.EvaluatePackage()
            StorageUtil.UnsetIntValue(who, "Intel_ArcJailed")
            StorageUtil.UnsetFormValue(who, "Intel_ArcJailAt")
            StorageUtil.UnsetFormValue(who, "Intel_ArcJailOut")
            StorageUtil.UnsetFloatValue(who, "Intel_ArcJailUntil")
            StorageUtil.FormListRemoveAt(self, "Intel_ArcJail", i)
            Core().DebugMsg("Arcs: " + who.GetDisplayName() + " is out of jail")
        EndIf
        i -= 1
    EndWhile
EndFunction
