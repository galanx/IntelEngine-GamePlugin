Scriptname IntelEngine_Quests extends Quest
{IntelEngine 4.0 quests (docs/QUESTS.md in the native plugin): the offer, the journal, and what a quest needs placed
in the world. The record and every decision are in the DLL (Quests.h, QuestBridge.cpp): a step is done when the game
says so, never because of anything said, so a quest runs the same in any language and on any model. This script
offers, shows, places, pays and watches. It runs on its own quest, IntelEngine_QuestKeeper; the journal quests
IntelEngine_Quest0..5 have no script.}

; ----------------------------------------------------------------------------------------------- numbers of the DLL
Int Property SLOTS = 6 AutoReadOnly
Int Property TPL_KEEPSAKE = 1 AutoReadOnly
Int Property TPL_BOUNTY = 2 AutoReadOnly
Int Property TPL_VENTURE = 3 AutoReadOnly
Int Property TRUTH_THIEF_DEAD = 2 AutoReadOnly
Int Property PHASE_PLANNED = 0 AutoReadOnly
Int Property ENDING_DONE = 10 AutoReadOnly
Int Property PLACED_FOE = 1 AutoReadOnly
Int Property PLACED_GANG = 2 AutoReadOnly
Int Property PLACED_KILLED = 4 AutoReadOnly
Int Property PLACED_ITEM = 8 AutoReadOnly
; Aliases of a journal quest, in the order esp/EspBuilder makes them.
Int Property ALIAS_GIVER = 0 AutoReadOnly
Int Property ALIAS_FOE = 1 AutoReadOnly
Int Property ALIAS_ALLY = 2 AutoReadOnly
Int Property ALIAS_ITEM = 3 AutoReadOnly
Int Property ALIAS_MARKER = 4 AutoReadOnly
Int Property ALIAS_PLACE = 5 AutoReadOnly
Int Property ALIAS_COMPANION = 6 AutoReadOnly

Float Property WATCH_SECONDS = 2.0 AutoReadOnly

; Hidden, disabled references that lend the stamped item's name to the journal, per slot.
ObjectReference[] NameHolders
IntelEngine_Core CoreScript
; A venture planned while the player was indoors: placed on the road once they are out.
Int PendingVenture

; ----------------------------------------------------------------------------------------------- starting

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

Event OnInit()
    Begin()
EndEvent

Function Begin()
    {On start and on every load (Core's maintenance): the events, the watch.}
    If NameHolders.Length != SLOTS
        NameHolders = new ObjectReference[6]
    EndIf
    RegisterForModEvent("IntelEngine_QuestOffer", "OnQuestOffer")
    RegisterForModEvent("IntelEngine_QuestGiverArrived", "OnGiverArrived")
    RegisterForSingleUpdate(WATCH_SECONDS)
EndFunction

Quest Function JournalQuest(Int slot)
    If slot < 0 || slot >= SLOTS
        Return None
    EndIf
    Return Quest.GetQuest("IntelEngine_Quest" + slot)
EndFunction

; ----------------------------------------------------------------------------------------------- the offer

Event OnQuestOffer(String eventName, String strArg, Float numArg, Form sender)
    {The director planned a quest (QuestBridge::PlanFor): its giver comes to the player as a story visitor.}
    Int id = numArg as Int
    Actor giver = sender as Actor
    If id <= 0 || giver == None
        Return
    EndIf
    IntelEngine_Core c = Core()
    If IntelEngine.QuestField(id, "template") == TPL_VENTURE
        ; A venture is met on the road, not brought to the player: placed ahead, out of sight, on the way there.
        If !Enabled() || !PlaceVenture(id)
            PendingVenture = id
        EndIf
        Return
    EndIf
    If !Enabled() || c.StoryEngine == None || !c.StoryEngine.DispatchQuestOffer(giver, id)
        ; Nobody comes, so nothing was offered: the plan is dropped and nobody remembers it.
        IntelEngine.QuestDecline(id)
    EndIf
EndEvent

Bool Function PlaceVenture(Int id)
    {The former follower (and whoever goes with them) on the road ahead of the player, out of sight, walking to the
    place; they greet the player as road encounters do, and then ask them along. Only outdoors; false otherwise.}
    Actor ally = IntelEngine.QuestForm(id, "ally") as Actor
    Actor player = Game.GetPlayer()
    IntelEngine_Core c = Core()
    If ally == None || c == None || c.StoryEngine == None || player.IsInCombat()
        Return false
    EndIf
    Cell here = player.GetParentCell()
    If here == None || here.IsInterior()
        Return false
    EndIf
    StorageUtil.SetIntValue(ally, "Intel_QuestOffer", id)
    c.StoryEngine.PlaceRoadEncounter(ally, IntelEngine.QuestText(id, "roadnarration"), IntelEngine.QuestText(id, "place"))
    Actor companion = IntelEngine.QuestForm(id, "companion") as Actor
    ObjectReference dest = StorageUtil.GetFormValue(ally, "Intel_FakeEncounterDest") as ObjectReference
    If companion != None && !companion.IsDead()
        companion.MoveTo(ally, 120.0, 60.0, 0.0, false)
        If dest != None
            PO3_SKSEFunctions.SetLinkedRef(companion, dest, c.IntelEngine_TravelTarget)
            ActorUtil.AddPackageOverride(companion, c.TravelPackage_Walk, c.PRIORITY_TRAVEL, 1)
            companion.EvaluatePackage()
        EndIf
    EndIf
    IntelEngine.LivingWorldMomentDispatched(ally, "road_encounter")
    c.DebugMsg("Quests: " + ally.GetDisplayName() + " is on the road to " + IntelEngine.QuestText(id, "place") + " (venture " + id + ")")
    Return true
EndFunction

Int Function DebugVenture(Actor ally)
    {Test hook: plans a venture for this former follower and puts them on the road ahead; the id, 0 when none fits.}
    Int id = IntelEngine.QuestPlanVenture(ally)
    If id > 0 && !PlaceVenture(id)
        PendingVenture = id
    EndIf
    Return id
EndFunction

Event OnGiverArrived(Form giverForm, Int id)
    {The giver reached the player and was told to speak (StoryEngine, seek_player arrival). Once their first line is
    said, the player chooses in the offer popup, as with IntelEngine's quest offers before.}
    Actor giver = giverForm as Actor
    Actor player = Game.GetPlayer()
    If giver == None || id <= 0 || IntelEngine.QuestField(id, "phase") != PHASE_PLANNED
        Return
    EndIf
    ; Let them speak first: the popup never cuts a line off.
    Utility.Wait(6.0)
    Float waited = 0.0
    While waited < 20.0 && giver.Is3DLoaded() && IntelEngine.IsActorTalking(giver)
        Utility.Wait(0.5)
        waited += 0.5
    EndWhile
    If IntelEngine.QuestField(id, "phase") != PHASE_PLANNED || giver.IsDead() || giver.IsInCombat()
        Return
    EndIf
    String prompt = IntelEngine.QuestText(id, "prompt")
    Bool venture = IntelEngine.QuestField(id, "template") == TPL_VENTURE
    String yes = "I'll do it"
    String no = "Not now"
    String agreed = " will do it"
    String refused = " will not do it"
    If venture
        yes = "I'll come along"
        no = "Not this time"
        agreed = " will come along"
        refused = " will not come along"
    EndIf
    String choice = Core().ShowChoice(giver.GetDisplayName(), "Quest offer", prompt, yes, no)
    If IntelEngine.QuestField(id, "phase") != PHASE_PLANNED
        Return
    EndIf
    If choice == yes && IntelEngine.QuestAccept(id)
        Core().SendTaskNarration(giver, "was told that " + player.GetDisplayName() + agreed, player)
        Open(id)
        If venture
            BeginVenture(id)
        EndIf
    Else
        IntelEngine.QuestDecline(id)
        Core().SendTaskNarration(giver, "was told that " + player.GetDisplayName() + refused, player)
    EndIf
EndEvent

IntelEngine_Threads Function Threads()
    Return Quest.GetQuest("IntelEngine_Threads") as IntelEngine_Threads
EndFunction

Function BeginVenture(Int id)
    {They go with the player now: the road encounter is over for them, and they follow the player (the follow
    package storylines use) until the venture ends.}
    IntelEngine_Core c = Core()
    IntelEngine_Threads t = Threads()
    Actor ally = IntelEngine.QuestForm(id, "ally") as Actor
    Actor companion = IntelEngine.QuestForm(id, "companion") as Actor
    If c != None && c.StoryEngine != None && ally != None
        c.StoryEngine.ForgetLingerActor(ally)
        c.StoryEngine.ClearRoadEncounterTravelState(ally)
    EndIf
    If c != None && c.StoryEngine != None && companion != None
        c.StoryEngine.ClearRoadEncounterTravelState(companion)
    EndIf
    If t != None
        t.Follow(ally, true)
        t.Follow(companion, true)
    EndIf
EndFunction

Function EndVenture(Int id)
    IntelEngine_Threads t = Threads()
    If t != None
        t.Follow(IntelEngine.QuestForm(id, "ally") as Actor, false)
        t.Follow(IntelEngine.QuestForm(id, "companion") as Actor, false)
    EndIf
EndFunction

Int Function DebugOffer(Actor giver)
    {Test hook (in-game tests): plans a quest for this giver as the director would and sends them to offer it; the id,
    0 when none fits or they cannot come.}
    Int id = IntelEngine.QuestPlanFor(giver)
    If id <= 0
        Return 0
    EndIf
    IntelEngine_Core c = Core()
    If c == None || c.StoryEngine == None || !c.StoryEngine.DispatchQuestOffer(giver, id)
        IntelEngine.QuestDecline(id)
        Return 0
    EndIf
    Return id
EndFunction

; ----------------------------------------------------------------------------------------------- the journal

Function Open(Int id)
    {Taken on: the journal quest of its slot starts with its title (set by the DLL), its first log entry, the first
    objective; what the truth needs at the place is placed now (the foe and the stamped item at the boss room; the
    gang once the cell is loaded).}
    Int slot = IntelEngine.QuestField(id, "slot")
    Quest jq = JournalQuest(slot)
    If jq == None
        Core().DebugMsg("Quests: no journal quest for slot " + slot)
        Return
    EndIf
    If jq.IsRunning()
        jq.Stop()
    EndIf
    jq.Reset()
    DropNameHolder(slot)
    If !jq.Start()
        Core().DebugMsg("Quests: journal quest " + slot + " did not start")
    EndIf
    IntelEngine.QuestApplyTitles()
    Actor giver = IntelEngine.QuestForm(id, "giver") as Actor
    Actor ally = IntelEngine.QuestForm(id, "ally") as Actor
    Actor companion = IntelEngine.QuestForm(id, "companion") as Actor
    Location place = IntelEngine.QuestForm(id, "place") as Location
    Force(jq, ALIAS_GIVER, giver)
    Force(jq, ALIAS_ALLY, ally)
    Force(jq, ALIAS_COMPANION, companion)
    LocationAlias placeAlias = jq.GetAlias(ALIAS_PLACE) as LocationAlias
    If placeAlias != None && place != None
        placeAlias.ForceLocationTo(place)
    EndIf
    Form item = IntelEngine.QuestForm(id, "item")
    If item != None
        ObjectReference holder = Game.GetPlayer().PlaceAtMe(item, 1, false, true)
        If holder != None
            holder.SetPosition(holder.GetPositionX(), holder.GetPositionY(), holder.GetPositionZ() - 10000.0)
            holder.SetDisplayName(IntelEngine.QuestText(id, "stamp"), true)
            NameHolders[slot] = holder
            Force(jq, ALIAS_ITEM, holder)
        EndIf
    EndIf
    Place(id, jq)
    jq.SetStage(IntelEngine.QuestField(id, "openstage"))
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

Function DropNameHolder(Int slot)
    If NameHolders.Length == SLOTS && NameHolders[slot] != None
        NameHolders[slot].Delete()
        NameHolders[slot] = None
    EndIf
EndFunction

Function ShowStep(Int id, Quest jq)
    {The objective of the step the player is on, its marker on what the step is about.}
    Int objective = IntelEngine.QuestField(id, "objective")
    If objective < 0
        Return
    EndIf
    Force(jq, ALIAS_MARKER, IntelEngine.QuestForm(id, "marker") as ObjectReference)
    jq.SetObjectiveDisplayed(objective, true, true)
EndFunction

; ----------------------------------------------------------------------------------------------- the world

Function Place(Int id, Quest jq)
    {What the truth needs at the place. The foe (the thief, alive or dead, or the brigand) is placed at the boss room
    when the quest is taken on; the cell need not be loaded. The stamped item and the gang come when the cell is, and a
    thief who lies dead there dies then (an actor in an unloaded cell does not die properly).}
    Int tmpl = IntelEngine.QuestField(id, "template")
    ObjectReference anchor = IntelEngine.QuestForm(id, "anchor") as ObjectReference
    If anchor == None
        Return
    EndIf
    Int placed = IntelEngine.QuestField(id, "placed")
    Bool crypt = IntelEngine.QuestField(id, "crypt") == 1
    Bool thiefDead = IntelEngine.QuestField(id, "truth") == TRUTH_THIEF_DEAD
    ; The thief is one of the road's thieves; a brigand where the dead walk is one of the dead.
    String foeKind = "bandit"
    If tmpl != TPL_KEEPSAKE && crypt
        foeKind = "draugr"
    EndIf
    ; What lives at the place: the dead in a crypt, else the thief's own kind.
    String gangKind = "bandit"
    If crypt
        gangKind = "draugr"
    EndIf
    Actor foe = IntelEngine.QuestForm(id, "foe") as Actor
    If Math.LogicalAnd(placed, PLACED_FOE) == 0
        foe = IntelEngine.SpawnQuestBoss(anchor, foeKind)
        ; A brigand the giver already named is a man or a woman as the name says: the spawn is matched to it.
        If tmpl == TPL_BOUNTY
            Int wanted = IntelEngine.QuestField(id, "foefemale")
            Int tries = 0
            While foe != None && tries < 6 && foe.GetLeveledActorBase().GetSex() != wanted
                foe.Delete()
                foe = IntelEngine.SpawnQuestBoss(anchor, foeKind)
                tries += 1
            EndWhile
        EndIf
        If foe == None
            Core().DebugMsg("Quests: #" + id + " could not place the foe at " + IntelEngine.QuestText(id, "place"))
            Return
        EndIf
        String name = IntelEngine.QuestSetFoe(id, foe)
        If name != ""
            foe.SetDisplayName(name, true)
        EndIf
        IntelEngine.QuestSetPlaced(id, PLACED_FOE)
        placed = Math.LogicalOr(placed, PLACED_FOE)
        If jq != None
            Force(jq, ALIAS_FOE, foe)
        EndIf
        Core().DebugMsg("Quests: #" + id + " " + name + " placed at " + IntelEngine.QuestText(id, "place"))
    EndIf
    If !anchor.Is3DLoaded()
        Return
    EndIf
    ; The stamped item goes on the thief once the place is loaded: made at an unloaded boss room it never reached
    ; their pockets (2026-11-18). Made where they stand, out of sight (disabled), and put straight into their inventory.
    If tmpl == TPL_KEEPSAKE && foe != None && Math.LogicalAnd(placed, PLACED_ITEM) == 0
        Form item = IntelEngine.QuestForm(id, "item")
        If item != None
            ObjectReference stamped = foe.PlaceAtMe(item, 1, false, true)
            If stamped != None
                stamped.SetDisplayName(IntelEngine.QuestText(id, "stamp"), true)
                foe.AddItem(stamped, 1, true)
                Core().DebugMsg("Quests: #" + id + " " + IntelEngine.QuestText(id, "stamp") + " is on " + foe.GetDisplayName())
            EndIf
        EndIf
        IntelEngine.QuestSetPlaced(id, PLACED_ITEM)
    EndIf
    If Math.LogicalAnd(placed, PLACED_GANG) == 0
        Actor[] gang = IntelEngine.SpawnQuestEnemies(anchor, gangKind)
        IntelEngine.QuestSetPlaced(id, PLACED_GANG)
        Core().DebugMsg("Quests: #" + id + " " + gang.Length + " " + gangKind + " at " + IntelEngine.QuestText(id, "place"))
    EndIf
    If thiefDead && foe != None && Math.LogicalAnd(placed, PLACED_KILLED) == 0 && foe.Is3DLoaded()
        foe.KillSilent()
        IntelEngine.QuestSetPlaced(id, PLACED_KILLED)
        Core().DebugMsg("Quests: #" + id + " the thief lies dead at " + IntelEngine.QuestText(id, "place"))
    EndIf
EndFunction

; ----------------------------------------------------------------------------------------------- watching

Event OnUpdate()
    If Enabled()
        Watch()
    EndIf
    RegisterForSingleUpdate(WATCH_SECONDS)
EndEvent

Function Watch()
    If PendingVenture > 0
        If IntelEngine.QuestField(PendingVenture, "phase") != PHASE_PLANNED || PlaceVenture(PendingVenture)
            PendingVenture = 0
        EndIf
    EndIf
    Int[] lapsed = IntelEngine.QuestLapse()
    Int i = 0
    While i < lapsed.Length
        Actor giver = IntelEngine.QuestForm(lapsed[i], "giver") as Actor
        If giver != None
            StorageUtil.UnsetIntValue(giver, "Intel_QuestOffer")
        EndIf
        i += 1
    EndWhile
    Int[] ids = IntelEngine.QuestOpenIds()
    i = 0
    While i < ids.Length
        WatchOne(ids[i])
        i += 1
    EndWhile
EndFunction

Function WatchOne(Int id)
    Quest jq = JournalQuest(IntelEngine.QuestField(id, "slot"))
    Place(id, jq)
    Int r = IntelEngine.QuestAdvance(id)
    If r != 0
        Settle(id, r, jq)
    ElseIf IntelEngine.QuestMayHandOver(id)
        OfferHandOver(id, jq)
    EndIf
EndFunction

Function Settle(Int id, Int r, Quest jq)
    {Steps done now: their objectives completed (those that were shown), the log of the furthest one; then the next
    step, or the ending.}
    Int done = Math.LogicalAnd(r, 255)
    Int ending = r / 256
    Int steps = IntelEngine.QuestField(id, "steps")
    Int furthest = -1
    Int i = 0
    While i < steps
        If Math.LogicalAnd(done, Math.LeftShift(1, i)) != 0
            furthest = i
            Int objective = IntelEngine.QuestField(id, "objective" + i)
            If jq != None && objective >= 0 && jq.IsObjectiveDisplayed(objective)
                jq.SetObjectiveCompleted(objective, true)
            EndIf
        EndIf
        i += 1
    EndWhile
    ; Only the step whose fact held writes its log: a step jumped over did not happen as written ("I have reached
    ; the place" when the thief was met on the road).
    If furthest >= 0 && jq != None
        Int logStage = IntelEngine.QuestField(id, "log" + furthest)
        If logStage > 0
            jq.SetStage(logStage)
        EndIf
    EndIf
    If ending > 0
        Ended(id, ending, jq)
    ElseIf jq != None
        ShowStep(id, jq)
    EndIf
EndFunction

Function OfferHandOver(Int id, Quest jq)
    {The stamped item is on the player, the giver is right here and just spoke: the player may hand it over. The
    engine moves the item itself; nothing said can.}
    Actor giver = IntelEngine.QuestForm(id, "giver") as Actor
    If giver == None
        Return
    EndIf
    Float waited = 0.0
    While waited < 15.0 && giver.Is3DLoaded() && IntelEngine.IsActorTalking(giver)
        Utility.Wait(0.5)
        waited += 0.5
    EndWhile
    String stamp = IntelEngine.QuestText(id, "stamp")
    String choice = Core().ShowChoice(giver.GetDisplayName(), "Hand over", "Give the " + IntelEngine.QuestText(id, "itembase") + " back to " + giver.GetDisplayName() + "?", "Hand it over", "Not yet")
    If choice != "Hand it over" || !IntelEngine.QuestHandOver(id)
        Return
    EndIf
    Int r = IntelEngine.QuestAdvance(id)
    If r != 0
        Settle(id, r, jq)
    EndIf
EndFunction

Function Ended(Int id, Int ending, Quest jq)
    {The ending's log entry completes or fails the journal quest; the reward is paid; the giver is told what happened
    so their words follow it (their memory and the deed in the hold are written by the DLL).}
    Actor player = Game.GetPlayer()
    Actor giver = IntelEngine.QuestForm(id, "giver") as Actor
    Int tmpl = IntelEngine.QuestField(id, "template")
    If tmpl == TPL_VENTURE
        EndVenture(id)
    EndIf
    If jq != None
        Int objective = IntelEngine.QuestField(id, "objective")
        If ending != ENDING_DONE && objective >= 0 && jq.IsObjectiveDisplayed(objective)
            jq.SetObjectiveFailed(objective, true)
        EndIf
        Int stage = IntelEngine.QuestField(id, "endstage")
        If stage > 0
            jq.SetStage(stage)
        EndIf
    EndIf
    If ending != ENDING_DONE || giver == None
        Return
    EndIf
    Int gold = IntelEngine.QuestField(id, "gold")
    If gold > 0
        player.AddItem(Game.GetFormFromFile(0x0000000F, "Skyrim.esm"), gold, true)
        If tmpl == TPL_VENTURE
            Core().NotifyPlayer("Your share of the spoils: " + gold + " gold.")
        Else
            Core().NotifyPlayer(giver.GetDisplayName() + " gave you " + gold + " gold.")
        EndIf
    EndIf
    If tmpl == TPL_KEEPSAKE
        Core().SendTaskNarration(giver, "was handed back " + IntelEngine.QuestText(id, "stamp") + " by " + player.GetDisplayName() + ", and paid " + player.GetDisplayName() + " the " + gold + " gold promised", player)
    ElseIf tmpl == TPL_VENTURE
        Core().SendTaskNarration(giver, "shares out what was found in " + IntelEngine.QuestText(id, "place") + ", and the share of " + player.GetDisplayName() + " comes to " + gold + " gold", player)
    Else
        Core().SendTransientEvent(giver, player, giver.GetDisplayName() + " paid " + player.GetDisplayName() + " the " + gold + " gold promised.")
    EndIf
EndFunction
