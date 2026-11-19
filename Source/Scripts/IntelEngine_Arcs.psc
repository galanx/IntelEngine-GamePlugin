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
Int Property EFFECT_LEAVE = 6 AutoReadOnly
Int Property EFFECT_BEFRIEND = 7 AutoReadOnly
Int Property EFFECT_ESTRANGE = 8 AutoReadOnly
Int Property EFFECT_GIVEITEM = 9 AutoReadOnly
Int Property KIND_BRAWL = 5 AutoReadOnly
Int Property KIND_VISIT = 7 AutoReadOnly
Int Property PATTERN_MURDER = 3 AutoReadOnly
Int Property PATTERN_FEUD = 2 AutoReadOnly
Int Property GEM_RUBY = 0x00063B42 AutoReadOnly
; The game's own brawl (FavorDialogueScript.Brawl): a story event with the opponent, quest DGIntimidateQuest, stage 15
; when the opponent goes down, 180 when the player does, 150 when it turned into a real fight.
Int Property BRAWL_EVENT = 0x00047AE2 AutoReadOnly
Int Property BRAWL_QUEST = 0x00047AE6 AutoReadOnly
Int Property SIGNAL_PLANT = 16777216 AutoReadOnly    ; 1 << 24
Int Property SIGNAL_CHOOSE = 33554432 AutoReadOnly   ; 1 << 25
Int Property SIGNAL_GIVE = 67108864 AutoReadOnly     ; 1 << 26
Int Property SIGNAL_VISIT = 32 AutoReadOnly          ; 1 << 5
Int Property SIGNAL_LINGER = 64 AutoReadOnly         ; 1 << 6
Int Property SIGNAL_GANG = 128 AutoReadOnly          ; 1 << 7
Int Property LINGER_QUIET_SECONDS = 60 AutoReadOnly  ; a talk gone quiet this long: they go back to their day
; A tale's journal log: two items of IntelEngine.esp per slot whose names the DLL writes (esp/EspBuilder AddTaleHolders).
Int Property HOLDER_TEXT = 0x000058DD AutoReadOnly   ; IntelEngine_TaleText0..3
Int Property HOLDER_CLOSE = 0x000058E1 AutoReadOnly  ; IntelEngine_TaleClose0..3
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
Int Property ALIAS_TALE = 11 AutoReadOnly
Int Property ALIAS_CLOSE = 12 AutoReadOnly
Int Property ROLES = 7 AutoReadOnly   ; the people of an arc, roles 1..7 in aliases 0..6

Float Property WATCH_SECONDS = 2.0 AutoReadOnly
Float Property JAIL_DAYS = 2.0 AutoReadOnly
Float Property AWAY_DAYS = 3.0 AutoReadOnly

; Hidden, disabled references that lend the props' names to the journal: two per slot.
ObjectReference[] NameHolders
; A tale's two log holders per slot (the story so far, the ending).
ObjectReference[] TaleHolders
IntelEngine_Core CoreScript
Bool Asking   ; an arc popup is up (or waiting its turn)

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
    If TaleHolders.Length != SLOTS * 2
        TaleHolders = new ObjectReference[8]
    EndIf
    ; The DLL forgets the holders with every load (it keeps no references of its own): told again, and the journal's
    ; texts written anew.
    Int slot = 0
    While slot < SLOTS
        If TaleHolders[slot * 2] != None
            IntelEngine.ArcSetHolders(slot, TaleHolders[slot * 2], TaleHolders[slot * 2 + 1])
        EndIf
        slot += 1
    EndWhile
    IntelEngine.ArcApplyTitles()
    RegisterForModEvent("IntelEngine_ArcAskerArrived", "OnAskerArrived")
    RegisterForModEvent("IntelEngine_ArcOffer", "OnArcOffer")
    RegisterForSingleUpdate(WATCH_SECONDS)
EndFunction

Quest Function JournalQuest(Int slot)
    If slot < 0 || slot >= SLOTS
        Return None
    EndIf
    Return Quest.GetQuest("IntelEngine_Arc" + slot)
EndFunction

; ----------------------------------------------------------------------------------------------- the offer

Int Function DebugArcWith(Actor asker, Int pattern, Actor other)
    {Test hook: DebugArc with the thief, the rival or the killer chosen.}
    IntelEngine.ArcDebugCast(other)
    Return DebugArc(asker, pattern)
EndFunction

Bool Function DebugTale(Actor asker)
    {Test hook (in-game tests): asks the dungeon master for a tale with this asker, as the director does; the offer
    comes once it is written (IntelEngine_ArcOffer). False when none can be asked for now.}
    Return IntelEngine.ArcRequestTale(asker)
EndFunction

Bool Function DebugTaleFile(Actor asker, String path)
    {Test hook: a tale written by hand (JSON at an absolute path), cast from the asker's town and offered like any other.}
    Return IntelEngine.ArcDebugTaleFile(asker, path)
EndFunction

Int Function DebugArc(Actor asker, Int pattern = 0)
    {Test hook (in-game tests): plans an arc with this asker as the director will and sends them to the player to ask;
    the id, 0 when none fits or they cannot come.}
    Int id = IntelEngine.ArcPlan(asker, pattern)
    If id <= 0
        Return 0
    EndIf
    IntelEngine_Core c = Core()
    If c == None || c.StoryEngine == None || !c.StoryEngine.DispatchArcOffer(asker, id)
        IntelEngine.ArcDrop(id)
        Return 0
    EndIf
    TheMurder(id)
    Return id
EndFunction

Function TheMurder(Int id)
    {A murder's victim dies before the asker reaches the player: at home, out of anyone's sight, by the killer's hand
    (the game's death reactions follow: mourning, the town's talk).}
    If IntelEngine.ArcField(id, "pattern") != PATTERN_MURDER
        Return
    EndIf
    Actor victim = IntelEngine.ArcStageVictim(id)
    Actor killer = IntelEngine.ArcForm(id, "culprit") as Actor
    If victim == None
        Return
    EndIf
    victim.Kill(killer)
    Core().DebugMsg("Arcs: #" + id + " " + victim.GetDisplayName() + " was killed at home")
EndFunction

Event OnArcOffer(String eventName, String strArg, Float numArg, Form sender)
    {The director planned an arc (ArcBridge::PlanFor): its asker comes to the player as a story visitor; a murder's
    victim dies now, out of sight.}
    Int id = numArg as Int
    Actor asker = sender as Actor
    If id <= 0 || asker == None
        Return
    EndIf
    IntelEngine_Core c = Core()
    If !Enabled() || c.StoryEngine == None || !c.StoryEngine.DispatchArcOffer(asker, id)
        ; Nobody comes, so nothing was offered: the plan is dropped and nobody remembers it.
        IntelEngine.ArcDrop(id)
        Return
    EndIf
    TheMurder(id)
EndEvent

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
    If IntelEngine.ArcField(id, "pattern") == PATTERN_MURDER
        Actor victim = IntelEngine.ArcForm(id, "victim") as Actor
        TheMurder(id)
        If victim == None || !victim.IsDead()
            ; The victim is alive where the player can see them: there is no murder to tell of. Nothing is offered.
            IntelEngine.ArcDrop(id)
            Core().DebugMsg("Arcs: #" + id + " the victim is still alive in sight; the murder is called off")
            Return
        EndIf
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
    ; Role r is in alias r - 1 (asker, culprit, witness, rival, victim, suspects; a tale's people in the order it cast them).
    Int r = 1
    While r <= ROLES
        Force(jq, r - 1, IntelEngine.ArcForm(id, "role" + r) as ObjectReference)
        r += 1
    EndWhile
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
    ; What someone carries from the start (the victim's gem in the killer's pocket, a tale's pocket): found by picking
    ; it, or on their body.
    p = 0
    While p < 3
        Actor carrier = IntelEngine.ArcForm(id, "pocket" + p) as Actor
        Form carried = IntelEngine.ArcForm(id, "prop" + p)
        If carrier != None && carried != None
            ObjectReference stamped = Game.GetPlayer().PlaceAtMe(carried, 1, false, true)
            If stamped != None
                stamped.SetDisplayName(IntelEngine.ArcText(id, "prop" + p), true)
                carrier.AddItem(stamped, 1, true)
                IntelEngine.ArcPlanted(id, p, carrier)
            EndIf
        EndIf
        p += 1
    EndWhile
    If IntelEngine.ArcField(id, "tale") == 1
        MakeTaleHolders(slot, jq)
        PlaceBosses(id)   ; after the holders: the places' masters are made last
    EndIf
    jq.SetStage(IntelEngine.ArcField(id, "openstage"))
    ShowStep(id, jq)
    jq.SetActive(true)
    If IntelEngine.ArcField(id, "pattern") == PATTERN_FEUD
        QuarrelHere(id)
    EndIf
EndFunction

Function MakeTaleHolders(Int slot, Quest jq)
    {A tale's log shows the story so far and its ending as the names of two items of this slot (the DLL writes them):
    hidden, disabled references of them fill the Tale and Close aliases.}
    Int k = 0
    While k < 2
        If TaleHolders[slot * 2 + k] != None
            DeleteHolder(TaleHolders[slot * 2 + k])
            TaleHolders[slot * 2 + k] = None
        EndIf
        Form base = None
        If k == 0
            base = Game.GetFormFromFile(HOLDER_TEXT + slot, "IntelEngine.esp")
        Else
            base = Game.GetFormFromFile(HOLDER_CLOSE + slot, "IntelEngine.esp")
        EndIf
        If base != None
            ObjectReference holder = Game.GetPlayer().PlaceAtMe(base, 1, true, true)
            If holder != None
                holder.SetPosition(holder.GetPositionX(), holder.GetPositionY(), holder.GetPositionZ() - 10000.0)
                TaleHolders[slot * 2 + k] = holder
                Force(jq, ALIAS_TALE + k, holder)
            EndIf
        EndIf
        k += 1
    EndWhile
    IntelEngine.ArcSetHolders(slot, TaleHolders[slot * 2], TaleHolders[slot * 2 + 1])
EndFunction

Function PlaceBosses(Int id)
    {A tale's places out in the world: the master each one's story needs, of the place's own kind, at its heart. Placed
    while nobody is there (the place need not be loaded); named as the story names them.}
    Int s = 0
    While s < 2
        Form base = IntelEngine.ArcForm(id, "bossbase" + s)
        ObjectReference anchor = IntelEngine.ArcForm(id, "siteanchor" + s) as ObjectReference
        If base != None && anchor != None
            Actor boss = anchor.PlaceAtMe(base, 1, true, false) as Actor
            If boss != None
                String name = IntelEngine.ArcText(id, "bossname" + s)
                If name != ""
                    boss.SetDisplayName(name, true)
                EndIf
            EndIf
            IntelEngine.ArcBossPlaced(id, s, boss)
        EndIf
        s += 1
    EndWhile
EndFunction

Function PlaceGang(Int id)
    {A place the player emptied before: two of its kind come back with the story's master, near its heart, once it is
    loaded.}
    Int s = IntelEngine.ArcField(id, "gangsite")
    ObjectReference anchor = IntelEngine.ArcForm(id, "siteanchor" + s) as ObjectReference
    Int k = 0
    While k < 2 && anchor != None
        Form base = IntelEngine.ArcForm(id, "gangbase" + k)
        If base != None
            ObjectReference one = anchor.PlaceAtMe(base, 1, false, false)
            If one != None
                Float dx = 220.0
                If k == 1
                    dx = -220.0
                EndIf
                one.MoveTo(anchor, dx, 160.0, 0.0)
            EndIf
        EndIf
        k += 1
    EndWhile
    IntelEngine.ArcGangPlaced(id)
EndFunction

Function DeleteHolder(ObjectReference holder)
    {A holder is a hidden, disabled item reference: a handle kept from another time that now names something else (the
    game gives a deleted reference's id to the next one it makes) is never deleted with it. A boss the story had just
    placed vanished that way (2026-11-19).}
    If holder != None && holder.IsDisabled() && (holder as Actor) == None
        holder.Delete()
    EndIf
EndFunction

Function QuarrelHere(Int id)
    {The rival is in the same room: no errand across it. The asker has it out with them there and then, in front of the
    player, the rival answers, and the player settles it on the spot (the user, 2026-11-18: "when Carlotta was in the
    same room, she could have settled things herself").}
    Actor player = Game.GetPlayer()
    Actor asker = IntelEngine.ArcForm(id, "asker") as Actor
    Actor rival = IntelEngine.ArcForm(id, "rival") as Actor
    If asker == None || rival == None || rival.IsDead() || !rival.Is3DLoaded()
        Return
    EndIf
    If rival.GetParentCell() != player.GetParentCell() || rival.GetDistance(player) > 1500.0 || asker.GetDistance(player) > 1500.0
        Return
    EndIf
    IntelEngine.ArcScene(id, 180.0)
    Quests().WaitForSilence(asker, 15.0)
    Core().SendTaskNarration(asker, "turns to " + rival.GetDisplayName() + ", who is right here, and has it out with them in front of " + player.GetDisplayName() + ": " + IntelEngine.ArcText(id, "grievance"), rival)
    Quests().WaitForTheirSay(asker, 30.0)
    Core().SendTaskNarration(rival, "answers " + asker.GetDisplayName() + " in front of " + player.GetDisplayName() + ", giving their own side of it", asker)
    Core().DebugMsg("Arcs: #" + id + " the quarrel plays out in the room")
    ; Once they have had it out, the player decides there and then (the watch has seen the rival's side by now).
    Quests().WaitForTheirSay(rival, 30.0)
    Utility.Wait(2.5)
    If IntelEngine.ArcField(id, "phase") == PHASE_OPEN && IntelEngine.ArcField(id, "node") == 1
        OfferChoice(id, JournalQuest(IntelEngine.ArcField(id, "slot")))
    EndIf
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
            DeleteHolder(NameHolders[slot * 2 + p])
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
    If IntelEngine.ArcField(id, "kind") == KIND_BRAWL && StorageUtil.GetFloatValue(self, "Intel_ArcFightFrom" + id, -1.0) < 0.0
        ; From now on a brawl with them counts, whoever started it (this popup, or their own challenge in talk).
        StorageUtil.SetFloatValue(self, "Intel_ArcFightFrom" + id, Utility.GetCurrentGameTime())
    EndIf
EndFunction

; ----------------------------------------------------------------------------------------------- fights

Function OfferFight(Int id)
    {One arc popup at a time: a second one waited behind the first and asked again what was already decided
    (2026-11-18). An answer to a step the story has left meanwhile is not taken.}
    If Asking
        Return
    EndIf
    Asking = true
    Int node = IntelEngine.ArcField(id, "node")
    OfferFightNow(id, node)
    Asking = false
EndFunction

Function OfferFightNow(Int id, Int node)
    {A feud to settle with fists: the rival has just talked with the player, who may start the fight now. It is the
    game's own brawl (no weapons, no deaths, the guards look on).}
    Actor rival = IntelEngine.ArcForm(id, "who") as Actor
    Actor player = Game.GetPlayer()
    If rival == None
        Return
    EndIf
    Quests().WaitForSilence(rival, 15.0)
    ; Already fighting: the game's brawl, or one of SeverActions (their own model may accept a challenge in talk,
    ; as Hulda did twice): no second fight is offered on top of it.
    Quest brawl = Game.GetFormFromFile(BRAWL_QUEST, "Skyrim.esm") as Quest
    If (brawl != None && brawl.IsRunning()) || rival.IsInCombat() || player.IsInCombat() || StorageUtil.GetFormValue(rival, "SeverBrawl_Opponent") != None
        IntelEngine.ArcAnswer(id, -1)
        Return
    EndIf
    String fightAnswer = Core().ShowChoice(rival.GetDisplayName(), "Story", IntelEngine.ArcText(id, "fight"), "Put up your fists", "Not now")
    If IntelEngine.ArcField(id, "node") != node || IntelEngine.ArcField(id, "phase") != PHASE_OPEN
        Return
    EndIf
    If fightAnswer != "Put up your fists"
        IntelEngine.ArcAnswer(id, -1)
        Return
    EndIf
    IntelEngine.ArcAnswer(id, -1)
    BeginFight(id, rival)
EndFunction

Bool Function Fighting(Actor who)
    {In a fight already: the game's brawl, one of SeverActions (its mirror on the fighter), or real combat.}
    Quest brawl = Game.GetFormFromFile(BRAWL_QUEST, "Skyrim.esm") as Quest
    Return (brawl != None && brawl.IsRunning()) || who.IsInCombat() || StorageUtil.GetFormValue(who, "SeverBrawl_Opponent") != None
EndFunction

Function BeginFight(Int id, Actor rival)
    {The player against the rival, fists only, in the game's own brawl: its quest makes the player essential for the
    fight, so losing means going down on one knee, never dying. A SeverActions brawl let a losing player be beaten to
    death (2026-11-18), and calling it needed that mod. Never a second fight on top of one already running (a brawl
    the rival's own model started in talk still counts: WatchBrawl reads it).}
    Actor player = Game.GetPlayer()
    If rival == None || rival.IsDead() || Fighting(rival) || Fighting(player)
        Return
    EndIf
    Keyword fight = Game.GetFormFromFile(BRAWL_EVENT, "Skyrim.esm") as Keyword
    If fight == None
        Return
    EndIf
    Core().SendTaskNarration(rival, "squares up to " + player.GetDisplayName() + " to settle the quarrel with fists, here and now", player)
    fight.SendStoryEvent(None, rival, None, 0, 0)
    Core().DebugMsg("Arcs: #" + id + " brawl with " + rival.GetDisplayName() + " started")
EndFunction

Function WatchBrawl(Int id)
    {Whether the feud's fight is over and who won: the game's brawl quest with them as the opponent, or a brawl of
    SeverActions (its result is left on both fighters), begun since this fight became the step.}
    Actor rival = IntelEngine.ArcForm(id, "who") as Actor
    Actor player = Game.GetPlayer()
    Float from = StorageUtil.GetFloatValue(self, "Intel_ArcFightFrom" + id, -1.0)
    If rival == None || from < 0.0
        Return
    EndIf
    Int result = 0
    Quest brawl = Game.GetFormFromFile(BRAWL_QUEST, "Skyrim.esm") as Quest
    If brawl != None && brawl.IsRunning()
        ReferenceAlias opponent = brawl.GetAlias(0) as ReferenceAlias
        If opponent != None && opponent.GetActorRef() == rival
            If brawl.GetStageDone(15)
                result = 1
            ElseIf brawl.GetStageDone(180) || brawl.GetStageDone(150)
                result = -1
            EndIf
        EndIf
    EndIf
    If result == 0 && StorageUtil.GetFloatValue(rival, "SeverBrawl_LastEndTime", -1.0) >= from
        Int reason = StorageUtil.GetIntValue(rival, "SeverBrawl_LastEndReason", 0)
        Actor winner = StorageUtil.GetFormValue(rival, "SeverBrawl_LastWinner") as Actor
        Actor loser = StorageUtil.GetFormValue(rival, "SeverBrawl_LastLoser") as Actor
        If (reason == 1 || reason == 2 || reason == 6) && winner == player && loser == rival
            result = 1
        ElseIf (reason == 1 || reason == 2 || reason == 6) && winner == rival && loser == player
            result = -1
        ElseIf reason == 4 && (winner == player || loser == player)
            result = -1
        EndIf
    EndIf
    If result != 0
        IntelEngine.ArcBrawl(id, result)
        StorageUtil.UnsetFloatValue(self, "Intel_ArcFightFrom" + id)
    EndIf
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
    WatchAway()
    WatchLinger()
EndFunction

; Staying with the player while they talk: the person of an arc's step keeps near the player (the linger package of
; IntelEngine's quests) until the talk goes quiet for a minute, the player walks away, or the step moves on.

Function StartLinger(Int id)
    Actor who = IntelEngine.ArcForm(id, "who") as Actor
    IntelEngine_Core c = Core()
    If who == None || c == None || who.IsDead() || who.IsInCombat() || who.IsPlayerTeammate() || who.GetCurrentScene() != None
        ; In a scene of the game (a preacher's sermon, a bard's song): the scene keeps them where they belong.
        If who != None && c != None
            c.DebugMsg("Arcs: #" + id + " " + who.GetDisplayName() + " is not held back (in a scene, a fight or following)")
        EndIf
        IntelEngine.ArcLingerOver(id)
        Return
    EndIf
    If c.FindSlotByActor(who) >= 0 || c.IsFollowingPlayer(who)
        ; An errand of IntelEngine's, or following the player: their own packages already keep them right.
        IntelEngine.ArcLingerOver(id)
        Return
    EndIf
    Quests().Linger(who, c)
    StorageUtil.SetIntValue(who, "Intel_ArcLingerArc", id)
    StorageUtil.FormListAdd(self, "Intel_ArcLinger", who, false)
    c.DebugMsg("Arcs: #" + id + " " + who.GetDisplayName() + " stays with the player while they talk")
EndFunction

Function WatchLinger()
    Int i = StorageUtil.FormListCount(self, "Intel_ArcLinger") - 1
    While i >= 0
        Actor who = StorageUtil.FormListGet(self, "Intel_ArcLinger", i) as Actor
        Int id = 0
        If who != None
            id = StorageUtil.GetIntValue(who, "Intel_ArcLingerArc", 0)
        EndIf
        Bool over = who == None || who.IsDead() || id <= 0
        If !over
            over = IntelEngine.ArcField(id, "phase") != PHASE_OPEN || IntelEngine.ArcForm(id, "who") != who
        EndIf
        Bool bored = false
        If !over
            If Core().ShouldReleaseLinger(who)
                over = true
            ElseIf IntelEngine.ArcField(id, "quiet") > LINGER_QUIET_SECONDS
                ; The player is still here but has said nothing for a while: they say so and go back to their day.
                over = true
                bored = true
            EndIf
        EndIf
        If bored && who.Is3DLoaded()
            Core().SendTaskNarration(who, "has waited a while with nothing more said, and goes back to what they were doing", Game.GetPlayer())
        EndIf
        If over
            If who != None
                StorageUtil.UnsetIntValue(who, "Intel_ArcLingerArc")
                If !who.IsDead()
                    Core().ReleaseLinger(who)
                EndIf
            EndIf
            StorageUtil.FormListRemoveAt(self, "Intel_ArcLinger", i)
            If id > 0
                IntelEngine.ArcLingerOver(id)
            EndIf
        EndIf
        i -= 1
    EndWhile
EndFunction

Function WatchOne(Int id)
    If IntelEngine.ArcField(id, "kind") == KIND_BRAWL
        WatchBrawl(id)
    EndIf
    Int r = IntelEngine.ArcAdvance(id)
    If r == 0
        Return
    EndIf
    Quest jq = JournalQuest(IntelEngine.ArcField(id, "slot"))
    If Math.LogicalAnd(r, SIGNAL_PLANT) != 0
        Plant(id)
    EndIf
    If Math.LogicalAnd(r, SIGNAL_VISIT) != 0
        Visit(id)
    EndIf
    If Math.LogicalAnd(r, SIGNAL_LINGER) != 0
        StartLinger(id)
    EndIf
    If Math.LogicalAnd(r, SIGNAL_GANG) != 0
        PlaceGang(id)
    EndIf
    ; Everything but the signals: the step done (bits 0-4), the ending, the effect.
    Int change = Math.LogicalAnd(r, 16777215 - SIGNAL_VISIT - SIGNAL_LINGER - SIGNAL_GANG)
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
    ElseIf Math.LogicalAnd(r, SIGNAL_CHOOSE) != 0 && IntelEngine.ArcField(id, "kind") == KIND_BRAWL
        OfferFight(id)
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
    Int done = Math.LogicalAnd(r, 31) - 1   ; the step done now, -1 = none
    Int ending = Math.LogicalAnd(Math.RightShift(r, 8), 31)   ; bit 15: stayed on the step
    Int effect = Math.LogicalAnd(Math.RightShift(r, 16), 15)
    Int role = Math.LogicalAnd(Math.RightShift(r, 20), 15)
    If done >= 0
        Int objective = IntelEngine.ArcField(id, "objective" + done)
        If jq != None && objective >= 0 && jq.IsObjectiveDisplayed(objective)
            jq.SetObjectiveCompleted(objective, true)
        EndIf
    EndIf
    Int logStage = IntelEngine.ArcField(id, "log")
    If logStage > 0 && jq != None
        jq.SetStage(logStage)
    EndIf
    If IntelEngine.ArcField(id, "tale") == 1
        IntelEngine.ArcApplyTitles()   ; the story so far, with the line of this step
    EndIf
    If ending == 0 && IntelEngine.ArcField(id, "kind") == KIND_BRAWL
        ; Fists chosen with the rival in the room: the fight between the player and the rival begins now, owned by
        ; the story. Left to talk, the rival's own model accepted a brawl with the asker instead, the player's punches
        ; fell into someone else's fight, and the inn and the guard turned on the player (2026-11-18).
        Actor rival = IntelEngine.ArcForm(id, "who") as Actor
        Actor player = Game.GetPlayer()
        If rival != None && rival.Is3DLoaded() && rival.GetParentCell() == player.GetParentCell() && rival.GetDistance(player) < 1500.0
            BeginFight(id, rival)
        EndIf
    EndIf
    If effect > 0
        DoEffect(id, effect, role)
        Int effect2 = IntelEngine.ArcField(id, "effect2")
        If effect2 > 0
            DoEffect(id, effect2, IntelEngine.ArcField(id, "effect2role"))
        EndIf
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
    Bool good = ending == ENDING_DONE || ending == ENDING_SETTLED || ending == ENDING_STAYEDOUT   ; a tale's "other" too
    ; The objective the player was on: failed when it did not end well (the node of the ending is completed by Settle).
    Int last = 0
    While last < 32
        ; Objectives 0..11 (the patterns') and 20..31 (a tale's steps); there are none between.
        If last == 12
            last = 20
        EndIf
        If jq.IsObjectiveDisplayed(last) && !jq.IsObjectiveCompleted(last) && !good
            jq.SetObjectiveFailed(last, true)
        EndIf
        last += 1
    EndWhile
    ; A tale's ending line goes on its holder before the stage shows it.
    IntelEngine.ArcApplyTitles()
    If stage > 0
        jq.SetStage(stage)
    EndIf
    Core().DebugMsg("Arcs: #" + id + " ended " + ending)
EndFunction

; ----------------------------------------------------------------------------------------------- choices and hand-overs

Function OfferChoice(Int id, Quest jq)
    {One arc popup at a time: a second one waited behind the first and asked again what was already decided
    (2026-11-18). An answer to a step the story has left meanwhile is not taken.}
    If Asking
        Return
    EndIf
    Asking = true
    Int node = IntelEngine.ArcField(id, "node")
    OfferChoiceNow(id, jq, node)
    Asking = false
EndFunction

Function OfferChoiceNow(Int id, Quest jq, Int node)
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
        ; The popup's Escape is its last button, the do-nothing answer: three real answers never sit on one popup
        ; (Escape chose "Stay out of it", and would have accused whoever was listed third). The third waits behind
        ; "Something else", beside "Not now".
        choice = Core().ShowChoice(title, "Story", question, shown[0], shown[1], "Something else")
        If choice == "Something else"
            choice = Core().ShowChoice(title, "Story", question, shown[2], "Not now")
        EndIf
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
    If IntelEngine.ArcField(id, "node") != node || IntelEngine.ArcField(id, "phase") != PHASE_OPEN
        Return
    EndIf
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
    {One arc popup at a time: a second one waited behind the first and asked again what was already decided
    (2026-11-18). An answer to a step the story has left meanwhile is not taken.}
    If Asking
        Return
    EndIf
    Asking = true
    Int node = IntelEngine.ArcField(id, "node")
    OfferGiveNow(id, jq, node)
    Asking = false
EndFunction

Function OfferGiveNow(Int id, Quest jq, Int node)
    {The prop is in the player's pack and the one it goes to has just talked with the player: the player may hand it
    over. The engine moves it; nothing said can.}
    Actor who = IntelEngine.ArcForm(id, "giveto") as Actor
    If who == None
        Return
    EndIf
    Quests().WaitForSilence(who, 15.0)
    String choice = Core().ShowChoice(who.GetDisplayName(), "Hand over", IntelEngine.ArcText(id, "give"), "Hand it over", "Not yet")
    If IntelEngine.ArcField(id, "node") != node || IntelEngine.ArcField(id, "phase") != PHASE_OPEN
        Return
    EndIf
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
    ElseIf effect == EFFECT_PLAYERPAYS && target != None
        ; A tale's own price, else the reward's worth (a feud bought off).
        Int price = IntelEngine.ArcField(id, "price")
        If price > 0
            player.RemoveItem(septims, price, true, target)
            Core().NotifyPlayer("You gave " + target.GetDisplayName() + " " + price + " gold.")
        EndIf
    ElseIf effect == EFFECT_JAIL && target != None
        Jail(id, target)
    ElseIf effect == EFFECT_LEAVE && target != None
        SendAway(id, target)
    ElseIf effect == EFFECT_GIVEITEM
        GiveProp(id, IntelEngine.ArcField(id, "effectprop"), target)
    ElseIf (effect == EFFECT_BEFRIEND || effect == EFFECT_ESTRANGE) && target != None
        Actor other = IntelEngine.ArcForm(id, "role" + IntelEngine.ArcField(id, "bondwith")) as Actor
        If other != None && other != target && !other.IsDead()
            ; The game's own ties: friends greet each other as friends; rivals never come to blows over it.
            Int rank = 1
            If effect == EFFECT_ESTRANGE
                rank = -1
            EndIf
            target.SetRelationshipRank(other, rank)
            other.SetRelationshipRank(target, rank)
            Core().DebugMsg("Arcs: #" + id + " " + target.GetDisplayName() + " and " + other.GetDisplayName() + " are now at rank " + rank)
        EndIf
    EndIf
EndFunction

Function GiveProp(Int id, Int p, Actor giver)
    {A tale's "give": someone hands the story's item over (a confession, a bargain). It comes from wherever it was put;
    never put anywhere yet (the player never went where it was hidden), it is made in the player's hands.}
    Actor player = Game.GetPlayer()
    If !IntelEngine.ArcFetchProp(id, p)
        Form base = IntelEngine.ArcForm(id, "prop" + p)
        If base == None
            Return
        EndIf
        ObjectReference stamped = player.PlaceAtMe(base, 1, false, true)
        If stamped == None
            Return
        EndIf
        stamped.SetDisplayName(IntelEngine.ArcText(id, "prop" + p), true)
        player.AddItem(stamped, 1, true)
        IntelEngine.ArcPlanted(id, p, player)
    EndIf
    String who = "Someone"
    If giver != None
        who = giver.GetDisplayName()
        Core().SendTaskNarration(giver, "hands " + IntelEngine.ArcText(id, "prop" + p) + " over to " + player.GetDisplayName(), player)
    EndIf
    Core().NotifyPlayer(who + " gave you " + IntelEngine.ArcText(id, "prop" + p) + ".")
EndFunction

Function Visit(Int id)
    {A tale's visit: the step's person comes to the player. Already here, they speak up; else they set out the way a
    story visitor does. Asked again by the DLL a couple of game hours later if they could not come.}
    Actor who = IntelEngine.ArcForm(id, "who") as Actor
    Actor player = Game.GetPlayer()
    If who == None || who.IsDead() || who.IsInCombat()
        Return
    EndIf
    String words = IntelEngine.ArcText(id, "visitwords")
    If who.Is3DLoaded() && who.GetParentCell() == player.GetParentCell() && who.GetDistance(player) < 1500.0
        Quests().WaitForSilence(who, 15.0)
        Core().SendTaskNarration(who, "comes over to " + player.GetDisplayName() + ": " + IntelEngine.ArcText(id, "goal"), player)
        Core().DebugMsg("Arcs: #" + id + " " + who.GetDisplayName() + " is here and comes over")
        Return
    EndIf
    IntelEngine_Core c = Core()
    If c == None || c.StoryEngine == None || !c.StoryEngine.DispatchArcVisit(who, id, words)
        Core().DebugMsg("Arcs: #" + id + " " + who.GetDisplayName() + " cannot come now")
    EndIf
EndFunction

; Gone from town for a while (a tale's "leave"): once nobody sees it, they are away (disabled) for a few days, then
; back where the game keeps them.

Function SendAway(Int id, Actor who)
    If who.Is3DLoaded() && who.GetDistance(Game.GetPlayer()) < 2000.0
        Core().SendTaskNarration(who, "makes ready to leave town for a while", Game.GetPlayer())
    EndIf
    StorageUtil.SetFloatValue(who, "Intel_ArcAwayUntil", Utility.GetCurrentGameTime() + AWAY_DAYS)
    StorageUtil.SetIntValue(who, "Intel_ArcAway", 0)
    StorageUtil.FormListAdd(self, "Intel_ArcAwayList", who, false)
EndFunction

Function WatchAway()
    Int i = StorageUtil.FormListCount(self, "Intel_ArcAwayList") - 1
    While i >= 0
        Actor who = StorageUtil.FormListGet(self, "Intel_ArcAwayList", i) as Actor
        If who == None || who.IsDead()
            StorageUtil.FormListRemoveAt(self, "Intel_ArcAwayList", i)
        ElseIf StorageUtil.GetIntValue(who, "Intel_ArcAway", 0) == 0
            If Unseen(who)
                who.Disable()
                StorageUtil.SetIntValue(who, "Intel_ArcAway", 1)
                Core().DebugMsg("Arcs: " + who.GetDisplayName() + " has left town")
            EndIf
        ElseIf Utility.GetCurrentGameTime() >= StorageUtil.GetFloatValue(who, "Intel_ArcAwayUntil")
            ; Back where the game keeps them, but never appearing in front of the player: while the player is in that
            ; room, or near that spot outdoors, they stay away a little longer.
            who.MoveToMyEditorLocation()
            Actor player = Game.GetPlayer()
            Cell there = who.GetParentCell()
            Bool inSight = there != None && there == player.GetParentCell() && (there.IsInterior() || who.GetDistance(player) < 4000.0)
            If !inSight
                who.Enable()
                who.EvaluatePackage()
                StorageUtil.UnsetIntValue(who, "Intel_ArcAway")
                StorageUtil.UnsetFloatValue(who, "Intel_ArcAwayUntil")
                StorageUtil.FormListRemoveAt(self, "Intel_ArcAwayList", i)
                Core().DebugMsg("Arcs: " + who.GetDisplayName() + " is back in town")
            EndIf
        EndIf
        i -= 1
    EndWhile
EndFunction

; Taken by the guard: once nobody sees it happen, they are in the hold's jail for a couple of days, then let out
; where the hold lets prisoners out, and walk home.

Function Jail(Int id, Actor who)
    ObjectReference jailAt = IntelEngine.ArcForm(id, "jail") as ObjectReference
    If jailAt == None
        Core().DebugMsg("Arcs: #" + id + " no jail for " + who.GetDisplayName())
        Return
    EndIf
    ; Told only when they are here to hear it (a killer named to the asker across town is not).
    If who.Is3DLoaded() && who.GetDistance(Game.GetPlayer()) < 2000.0
        Core().SendTaskNarration(who, "is caught: " + Game.GetPlayer().GetDisplayName() + " is handing them over to the guard", Game.GetPlayer())
    EndIf
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
