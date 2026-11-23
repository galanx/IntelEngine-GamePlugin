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
Int Property EFFECT_CLOSER = 10 AutoReadOnly
Int Property EFFECT_APART = 11 AutoReadOnly
Int Property EFFECT_REMEDY = 12 AutoReadOnly
Int Property KIND_BRAWL = 5 AutoReadOnly
Int Property KIND_VISIT = 7 AutoReadOnly
Int Property KIND_STALK = 12 AutoReadOnly
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
Int Property SIGNAL_PLACE = 16384 AutoReadOnly       ; 1 << 14: a place's heart came into the game, or its marker moved
Int Property SIGNAL_AMBUSH = 8192 AutoReadOnly       ; 1 << 13: the ambush has work for the script (ArcField "ambushdo")
Int Property AMBUSH_PLACE = 1 AutoReadOnly
Int Property AMBUSH_STRIKE = 2 AutoReadOnly
Int Property AMBUSH_CALLOFF = 3 AutoReadOnly
Int Property AMBUSH_CHASE = 4 AutoReadOnly
Int Property AMBUSH_FIGHT = 5 AutoReadOnly
Int Property AMBUSH_STANDDOWN = 6 AutoReadOnly
Int Property KIND_AMBUSH = 11 AutoReadOnly
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
; The leader of each slot's ambush: held here so the body (and what it carries) stays in the world until the tale ends.
Actor[] AmbushLeaders
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

IntelEngine_Threads Function Threads()
    Return Quest.GetQuest("IntelEngine_Threads") as IntelEngine_Threads
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
    If AmbushLeaders.Length != SLOTS
        AmbushLeaders = new Actor[4]
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
    ; OStim's own events, heard softly (nothing happens without OStim): while the player's scene runs, nobody comes.
    RegisterForModEvent("ostim_thread_start", "OnOtherSceneStart")
    RegisterForModEvent("ostim_thread_end", "OnOtherSceneEnd")
    RegisterForModEvent("IntelEngine_ArcOffer", "OnArcOffer")
    RegisterForModEvent("IntelEngine_ArcUntie", "OnArcUntie")
    RegisterForModEvent("IntelEngine_ArcClue", "OnArcClue")
    RegisterForModEvent("IntelEngine_ArcSpirit", "OnArcSpirit")
    RegisterForModEvent("IntelEngine_Seam", "OnArrived")
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

Bool Function DebugRescue(Actor asker)
    {Test hook: a rescue is asked for, as the old dungeon master's quest of that name does (a story about someone
    close to the asker who is held at a place near their town, or nothing).}
    Bool ok = IntelEngine.ArcRequestRescue(asker)
    Core().DebugMsg("Arcs: a rescue asked for " + asker.GetDisplayName() + ": " + ok)
    Return ok
EndFunction

Bool Function DebugHaunt(Actor asker)
    {Test hook: a haunting is asked for (a story about something that walks by night outside one of the places near
    the asker's town), or nothing.}
    Bool ok = IntelEngine.ArcRequestHaunt(asker)
    Core().DebugMsg("Arcs: a haunting asked for " + asker.GetDisplayName() + ": " + ok)
    Return ok
EndFunction

Bool Function DebugHuntRumored(Actor asker)
    {Test hook: a hunt that begins as talk in town (nobody comes to the player; the innkeeper has heard of it, and the
    offer goes out when the player comes to the one who wants help).}
    Bool ok = IntelEngine.ArcRequestHunt(asker, true)
    Core().DebugMsg("Arcs: a hunt asked for " + asker.GetDisplayName() + ", as talk in town: " + ok)
    Return ok
EndFunction

Function DebugSetOut(Int id)
    {Test hook: the asker of a story that began as talk sets out to find someone at the next look (whatever the hour,
    and whether or not they are the kind to).}
    IntelEngine.ArcDebugSetOut(id)
EndFunction

Function DebugBringUp()
    {Test hook: whoever keeps the place the player stands in brings up the talk of the day now.}
    BringUpRumor(true)
EndFunction

Function DebugFactionEditor()
    {Test hook: reads what the load order offers the faction editor and saves the faction file as it stands.}
    IntelEngine.FactionEditorSelfTest()
EndFunction

Function DebugRumor(String text, Float weight)
    {Test hook: something goes round the hold the player stands in, as news, with this weight (0.55 crosses one border,
    0.75 three, 0.9 reaches every hold; a game day for each).}
    Int id = IntelEngine.RumorDebugNote(text, None, weight)
    Core().DebugMsg("Arcs: test rumor #" + id + " goes round (weight " + weight + ")")
EndFunction

Event OnArrived(String eventName, String strArg, Float numArg, Form sender)
    {The player arrived somewhere (the director's moments). In an inn, whoever keeps it has heard the talk of the day.}
    If (numArg as Int) == 2 && Enabled()
        BringUpRumor(false)
    EndIf
EndEvent

Function BringUpRumor(Bool now)
    {The one who keeps the place passes on the one thing most worth a word: trouble someone wants help with first,
    else something new that has weight. Once in a while (six game hours), after the player has had a moment to come
    in, never at a bad moment, never the same thing twice. They say it themselves, in their own words (a narration
    to SkyrimNet); the DLL chooses what (RumorBridge::BringUp).}
    Float day = Utility.GetCurrentGameTime()
    If !now
        If (day - StorageUtil.GetFloatValue(self, "Intel_RumorBroughtUp", -10.0)) * 24.0 < 6.0
            Return
        EndIf
        Utility.Wait(7.0)
    EndIf
    Actor player = Game.GetPlayer()
    If player.IsInCombat() || Utility.IsInMenuMode()
        Return
    EndIf
    Actor teller = IntelEngine.RumorPublican()
    If teller == None
        Return
    EndIf
    String word = IntelEngine.RumorBringUp(teller)
    If word == ""
        Return
    EndIf
    StorageUtil.SetFloatValue(self, "Intel_RumorBroughtUp", day)
    Core().SendTaskNarration(teller, "has heard something and passes it on to " + player.GetDisplayName() + " unasked, in their own words, as hearsay: " + word, player)
    Core().DebugMsg("Arcs: " + teller.GetDisplayName() + " brings up the talk of the day: " + word)
EndFunction

Bool Function DebugHunt(Actor asker)
    {Test hook: a hunt is asked for (a story about what is killing people near the asker's town: what was left of a
    victim to look at, and what did it to face), or nothing.}
    Bool ok = IntelEngine.ArcRequestHunt(asker)
    Core().DebugMsg("Arcs: a hunt asked for " + asker.GetDisplayName() + ": " + ok)
    Return ok
EndFunction

Bool Function DebugTale(Actor asker)
    {Test hook (in-game tests): asks the dungeon master for a tale with this asker, as the director does; the offer
    comes once it is written (IntelEngine_ArcOffer). False when none can be asked for now.}
    Return IntelEngine.ArcRequestTale(asker)
EndFunction

Int Function DebugReach(Actor who)
    {Test hook: how the director's distance rule sees this person (the log says it in words).}
    Return IntelEngine.ArcDebugReach(who)
EndFunction

Bool Function DebugTaleWhy(Actor asker, String why)
    {Test hook: a tale as the director asks for one: the asker's own reason, and they come to the player wherever the
    player is.}
    Return IntelEngine.ArcRequestTaleWhy(asker, why)
EndFunction

Function DebugHeart(Actor who, Int sparked, Int stance, Float refusedDaysAgo = -1.0)
    {Test hook: tells the DLL what a relationship mod would keep about this person and the player (something of the
    heart on their side, the player's answer to it: -1, 0, 1; for a no, how many game days ago it was first seen),
    without touching any mod's records. Someone such a mod tracks is told again from its own records within a minute.}
    Float refusedAt = -1.0
    If stance < 0 && refusedDaysAgo >= 0.0
        refusedAt = Utility.GetCurrentGameTime() - refusedDaysAgo
    EndIf
    IntelEngine.ArcHeart(who, sparked, stance, 0, false, 0, false, refusedAt)
EndFunction

Bool Function DebugTaleFile(Actor asker, String path)
    {Test hook: a tale written by hand (JSON at an absolute path), cast from the asker's town and offered like any other.}
    Return IntelEngine.ArcDebugTaleFile(asker, path)
EndFunction

Bool Function DebugBond(Actor who)
    {Test hook: how this person stands with the player is read now from what they remember of the player (as it is
    for everybody, by and by, in a game without a relationship mod). The answer comes to IntelEngine.log a few
    seconds later ("Bonds: ... stands to the player as ..."); DebugBondOf says it afterwards.}
    Bool ok = IntelEngine.BondJudge(who)
    Core().DebugMsg("Bonds: a reading asked for " + who.GetDisplayName() + ": " + ok)
    Return ok
EndFunction

Function DebugBondOf(Actor who)
    {Test hook: what was last read of this person, in the log.}
    Core().DebugMsg("Bonds: " + who.GetDisplayName() + " - " + IntelEngine.BondDescribe(who))
EndFunction

Function DebugPlace()
    {Test hook: logs whether the player is where nobody is sent (another plane, a dungeon).}
    String why = IntelEngine.PlaceBarsNow()
    If why == ""
        why = "no: people may come to the player here"
    EndIf
    Core().DebugMsg("Arcs: a place nobody is sent to? " + why)
EndFunction

Function DebugCosts(Actor who)
    {Test hook: what the parts of a tale's request cost for this person (IntelEngine.log).}
    IntelEngine.ArcDebugCosts(who)
EndFunction

Function DebugQuestBusy()
    {Test hook: logs whether a quest of the journal holds the town's stories back right now.}
    Core().DebugMsg("Arcs: busy with a quest of the journal? " + IntelEngine.ArcQuestBusyNow())
EndFunction

Function DebugPrivate()
    {Test hook: logs why nobody in arms would come upon the player now, or that they may.}
    String why = IntelEngine.PrivateMomentNow()
    If why == ""
        why = "nothing: the player is on the road and may be come upon"
    EndIf
    Core().DebugMsg("Arcs: a private moment? " + why)
EndFunction

Function DebugPatrolAlways(Bool on)
    {Test hook: every moment the director lets land is a faction's patrol (while some faction holds the player for
    an enemy), with no rest between two.}
    IntelEngine.FactionPatrolTest(on)
EndFunction

Function DebugBondNoMod(Bool on)
    {Test hook: go on as if no relationship mod were installed (this session only), so that what was read counts.}
    IntelEngine.BondPretendNoMod(on)
EndFunction

Int Function DebugArc(Actor asker, Int pattern = 0)
    {Test hook (in-game tests): plans an arc with this asker as the director will and sends them to the player to ask;
    the id, 0 when none fits or they cannot come.}
    Int id = IntelEngine.ArcPlan(asker, pattern)
    If id <= 0
        Return 0
    EndIf
    ; By the door every offer goes out of (OnArcOffer does the rest): the hook used to send the asker straight off, so a
    ; test never met the rule on who goes to the player and who waits.
    IntelEngine.ArcOffer(id, asker)
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

Event OnOtherSceneStart(String eventName, String strArg, Float numArg, Form sender)
    {OStim: a scene has begun; thread 0 is always the player's.}
    If numArg as Int == 0
        IntelEngine.LivingWorldSceneBusy(true)
    EndIf
EndEvent

Event OnOtherSceneEnd(String eventName, String strArg, Float numArg, Form sender)
    If numArg as Int == 0
        IntelEngine.LivingWorldSceneBusy(false)
    EndIf
EndEvent

Event OnArcClue(String eventName, String strArg, Float numArg, Form sender)
    {The player looked closely at what a story left outside a place (their hand on it; the DLL hears it,
    ArcBridge::Activated): what they see there, in the story's own words. After that it is theirs to search like any
    other of the dead. The step is done by the watch, whenever the story comes to it.}
    Int id = numArg as Int
    Int k = strArg as Int
    ObjectReference lies = sender as ObjectReference
    If lies != None
        lies.BlockActivation(false)
    EndIf
    String seen = IntelEngine.ArcText(id, "cluetext" + k)
    Core().DebugMsg("Arcs: #" + id + " the player looked at what was left (" + k + "): " + seen)
    If seen != "" && lies != None
        ; IntelEngine's own window, like every other moment of a story (the game's plain message box showed no words
        ; at all in the test profile). Looked at, the dead can be searched like any other.
        ; "Stand up" last: that is what Esc answers.
        String answer = Core().ShowChoice(lies.GetDisplayName(), "What you see", seen, "Search the body", "Stand up")
        If answer == "Search the body"
            lies.Activate(Game.GetPlayer())
        EndIf
    EndIf
EndEvent

Event OnArcUntie(String eventName, String strArg, Float numArg, Form sender)
    {The player cut someone loose whom a story held bound (they activated them; the DLL hears it, ArcBridge::Activated):
    the bonds come off now, not at the next look.}
    WatchCaptives()
EndEvent

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
        If IntelEngine.ArcField(id, "camefar") == 1
            ; Someone who came all the way from another hold does not turn back because the moment was wrong (another
            ; visitor on the way): they wait an hour and try again, while their story stands.
            IntelEngine.ArcOfferLater(id)
            Return
        EndIf
        If IntelEngine.ArcField(id, "rumored") == 1
            ; Their trouble is talk in town already: it is not forgotten because this was the wrong moment to come.
            ; It waits for the next meeting, as before they set out.
            IntelEngine.ArcOfferDeferred(id)
            Return
        EndIf
        ; Nobody comes, so nothing was offered: the plan is dropped and nobody remembers it.
        IntelEngine.ArcDrop(id)
        Return
    EndIf
    TheMurder(id)
    TakeCaptive(id)
    If IntelEngine.ArcField(id, "asksaround") == 1
        AskAround(id, asker)
    EndIf
EndEvent

Function AskAround(Int id, Actor asker)
    {The asker of a story that began as talk in town is on their way to the player (the user, 2026-11-20: "we may
    sometimes witness people asking around for help until they reach you"). Before they come up to the player they
    stop someone who stands near and ask them, in sight of the player: someone looking for help, not someone looking
    for the player. One person, a short question, then they go on. Nothing happens when nobody stands near, when they
    are at the player's side already, or when the visit ends some other way first.}
    Actor player = Game.GetPlayer()
    Float until = Utility.GetCurrentRealTime() + 240.0
    While Utility.GetCurrentRealTime() < until
        Utility.Wait(0.5)
        If IntelEngine.ArcField(id, "phase") != PHASE_PLANNED || asker.IsDead() || asker.IsInCombat() \
            || StorageUtil.GetIntValue(asker, "Intel_ArcOffer", 0) != id
            Return
        EndIf
        If asker.Is3DLoaded() && player.Is3DLoaded() && asker.GetParentCell() != None \
            && (asker.GetParentCell() == player.GetParentCell() || (!asker.IsInInterior() && !player.IsInInterior()))
            Float d = asker.GetDistance(player)
            If d < 450.0
                Return   ; they are there: no detour now
            EndIf
            If d < 2400.0
                Actor other = IntelEngine.ArcBystander(id, asker)
                If other != None
                    ; Their road leads to that person first: the same travel as before with another end (the order that
                    ; walks them to the player stays in force, so walking there by any other means is pulled straight
                    ; back: played 2026-11-20). While it ends at the bystander they stay with them, and walk along if the
                    ; other walks.
                    Keyword road = Core().IntelEngine_TravelTarget
                    PO3_SKSEFunctions.SetLinkedRef(asker, other, road)
                    asker.EvaluatePackage()
                    Int steps = 0
                    While steps < 60 && asker.GetDistance(other) > 230.0 && StorageUtil.GetIntValue(asker, "Intel_ArcOffer", 0) == id && !asker.IsInCombat()
                        Utility.Wait(0.5)
                        steps += 1
                    EndWhile
                    If StorageUtil.GetIntValue(asker, "Intel_ArcOffer", 0) != id
                        Return   ; the visit ended meanwhile: whoever ended it took their travel off
                    EndIf
                    If asker.GetDistance(other) <= 320.0 && !asker.IsInCombat()
                        asker.SetLookAt(other)
                        Core().SendTaskNarration(asker, "has been asking around for help and now stops " + other.GetDisplayName() \
                            + " in passing to ask, briefly and in their own words, whether they know of anyone who would take this on: \"" \
                            + IntelEngine.ArcText(id, "askaround") + "\" A short question to someone in the street, not the whole tale", other)
                        Core().DebugMsg("Arcs: #" + id + " " + asker.GetDisplayName() + " asks " + other.GetDisplayName() + " first, on the way to the player")
                        Utility.Wait(2.0)
                        Quests().WaitForTheirSay(asker, 20.0)
                        Utility.Wait(1.5)
                        Quests().WaitForTheirSay(other, 12.0)
                        asker.ClearLookAt()
                    Else
                        Core().DebugMsg("Arcs: #" + id + " " + asker.GetDisplayName() + " could not get to " + other.GetDisplayName() + ": on to the player")
                    EndIf
                    ; And on to the player, if the visit still stands.
                    If StorageUtil.GetIntValue(asker, "Intel_ArcOffer", 0) == id
                        PO3_SKSEFunctions.SetLinkedRef(asker, player, road)
                        asker.EvaluatePackage()
                    EndIf
                    Return
                EndIf
            EndIf
        EndIf
    EndWhile
EndFunction

Int Function SpokenAnswer(Int id, Actor asker, Float beganAt)
    {The asker has made their request (begun at this real second). When the player has said something since it began,
    or says something in the next few seconds (typed or spoken; while SkyrimNet's text box is open the game stands
    still, so the time to write it does not count), the asker's reply to it is waited for and the talk is read for a
    yes or a no (IntelEngine.ArcReadOffer). 1 yes, 2 no, 0 nothing said or nothing decided: then the window asks, as
    it always did.}
    Float waited = 0.0
    Bool said = false
    While waited < 6.5 && !said
        Float since = IntelEngine.GetSecondsSincePlayerSpoke()
        ; A line of the player's younger than the request: said while they were asking, or after.
        said = since >= 0.0 && since < (Utility.GetCurrentRealTime() - beganAt) - 0.25
        If !said
            Utility.Wait(0.5)
            waited += 0.5
        EndIf
        If IntelEngine.ArcField(id, "phase") != PHASE_PLANNED || asker.IsDead() || asker.IsInCombat()
            Return 0
        EndIf
    EndWhile
    If !said
        Return 0
    EndIf
    ; What the asker says to it belongs to the talk that is read.
    Utility.Wait(1.5)
    Quests().WaitForTheirSay(asker, 20.0)
    IntelEngine.ArcReadOffer(id)
    Int answer = -1
    waited = 0.0
    While answer < 0 && waited < 26.0
        Utility.Wait(0.5)
        waited += 0.5
        answer = IntelEngine.ArcOfferSpoken(id)
    EndWhile
    If answer < 0
        answer = 0
    EndIf
    Core().DebugMsg("Arcs: #" + id + " the player answered " + asker.GetDisplayName() + " in talk: " + answer + " (1 yes, 2 no, 0 the window asks)")
    Return answer
EndFunction

Event OnAskerArrived(Form askerForm, Int id)
    {The asker reached the player and was told to speak (StoryEngine, seek_player arrival). Once their say is over, the
    player chooses in the popup.}
    Actor asker = askerForm as Actor
    Actor player = Game.GetPlayer()
    If asker == None || id <= 0 || IntelEngine.ArcField(id, "phase") != PHASE_PLANNED
        Return
    EndIf
    Float beganAt = Utility.GetCurrentRealTime()
    ; Let them have their say first: the popup never cuts a line off.
    Utility.Wait(2.0)
    Quests().WaitForTheirSay(asker, 30.0)
    If IntelEngine.ArcField(id, "phase") != PHASE_PLANNED || asker.IsDead() || asker.IsInCombat()
        Return
    EndIf
    If !CaptiveGone(id)
        ; The one said to be held stands where the player can see them: nothing is offered, and nobody remembers it.
        IntelEngine.ArcDrop(id)
        Core().DebugMsg("Arcs: #" + id + " the one to be held is still in sight; the story is called off")
        If Core().StoryEngine != None
            Core().StoryEngine.VisitOver(asker)
        EndIf
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
    ; The player may answer in their own words: a yes or a no said to the one who asked is taken as said, and the
    ; window comes only when nothing was said or nothing was decided.
    Int spoken = SpokenAnswer(id, asker, beganAt)
    If IntelEngine.ArcField(id, "phase") != PHASE_PLANNED || asker.IsDead() || asker.IsInCombat()
        Return
    EndIf
    String choice = ""
    If spoken == 1
        choice = "I'll do it"
    ElseIf spoken == 2
        choice = "Not now"
    Else
        choice = Core().ShowChoice(asker.GetDisplayName(), "Quest offer", IntelEngine.ArcText(id, "prompt"), "I'll do it", "Not now")
    EndIf
    If IntelEngine.ArcField(id, "phase") != PHASE_PLANNED
        Return
    EndIf
    Bool stays = false
    If choice == "I'll do it" && IntelEngine.ArcAccept(id)
        If spoken == 0
            Core().SendTaskNarration(asker, "was told that " + player.GetDisplayName() + " will do it", player)
        EndIf
        Open(id)
        ; The first thing to do is with the asker themselves: they stay for it.
        stays = (IntelEngine.ArcForm(id, "who") as Actor) == asker
    Else
        IntelEngine.ArcDecline(id)
        If spoken == 0
            Core().SendTaskNarration(asker, "was told that " + player.GetDisplayName() + " will not do it", player)
        EndIf
    EndIf
    ; The answer is given: once they have said their word to it, they take their leave and walk back where they came
    ; from, instead of standing beside the player for the rest of the visit.
    If !stays && Core().StoryEngine != None
        Utility.Wait(2.0)
        Quests().WaitForTheirSay(asker, 25.0)
        Core().StoryEngine.VisitOver(asker)
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
        PlaceCaptive(id)  ; only when the heart of their place is in the game already (the player stands in it)
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

Int BossTries = 0

Function PlaceBosses(Int id)
    {A tale's places out in the world: the master each one's story needs, of the place's own kind, at its heart. Placed
    while nobody is there (the place need not be loaded); named as the story names them.}
    Int s = 0
    While s < 2
        Form base = IntelEngine.ArcForm(id, "bossbase" + s)
        ObjectReference anchor = IntelEngine.ArcForm(id, "siteanchor" + s) as ObjectReference
        If base != None && anchor != None
            ; Where the heart only came into the game with the player already in the same hall, the master is not
            ; put down in plain view as long as that can be helped (a few looks; then it has to be).
            Actor player = Game.GetPlayer()
            If anchor.GetParentCell() == player.GetParentCell() && player.GetDistance(anchor) < 1500.0 && player.HasLOS(anchor) && BossTries < 8
                BossTries += 1
            Else
                BossTries = 0
                Actor boss = anchor.PlaceAtMe(base, 1, true, false) as Actor
                If boss != None
                    String name = IntelEngine.ArcText(id, "bossname" + s)
                    If name != ""
                        boss.SetDisplayName(name, true)
                    EndIf
                EndIf
                IntelEngine.ArcBossPlaced(id, s, boss)
            EndIf
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

; ----------------------------------------------------------------------------------------------- an ambush
; Hired men sent by someone of a tale: they wait on the player's way ahead, out of sight, step out when the player
; comes near (their leader has a word first), and fight. The game's own Hired Thugs, leveled to the player. Only out in
; the wilds (the DLL's InTheWilds), so no guard or townsfolk joins in, and they strike first: no crime to defend oneself.

Function Ambush(Int id)
    Int what = IntelEngine.ArcField(id, "ambushdo")
    If what == AMBUSH_PLACE
        PlaceAmbush(id)
    ElseIf what == AMBUSH_STRIKE
        StepOut(id)
    ElseIf what == AMBUSH_FIGHT
        Fight(id)
    ElseIf what == AMBUSH_STANDDOWN
        StandDown(id)
    ElseIf what == AMBUSH_CALLOFF
        CallOff(id, true)
    ElseIf what == AMBUSH_CHASE
        Chase(id)
    EndIf
EndFunction

Function PlaceAmbush(Int id)
    {On a stretch of the road ahead on the player's way that the player cannot see and where nobody lives; they are
    made behind the player, where nobody is looking, and moved there unseen. No such stretch now: tried again a little
    later; after a couple of tries they come after the player from behind instead. Never left standing in the woods
    (the user, 2026-11-19: "the ambusher wasn't even in the road but somewhere in the woods near the river").}
    Actor player = Game.GetPlayer()
    IntelEngine_Core c = Core()
    IntelEngine_Quests q = Quests()
    Int count = IntelEngine.ArcField(id, "thugs")
    Cell here = player.GetParentCell()
    Bool behind = false
    Int placed = 0
    If c != None && q != None && count > 0 && here != None && !here.IsInterior() && !player.IsInCombat()
        Float tx = q.TrailDX()
        Float ty = q.TrailDY()
        If tx == 0.0 && ty == 0.0
            ; Standing still: the way they face (angle 0 is north, +y, turning clockwise).
            tx = Math.Sin(player.GetAngleZ())
            ty = Math.Cos(player.GetAngleZ())
        EndIf
        Float span = Math.Sqrt(tx * tx + ty * ty)
        Bool fromBehind = IntelEngine.ArcField(id, "ambushtries") >= 2
        Float[] ahead = IntelEngine.QuestRoadAhead(tx, ty)
        Float[] back
        If ahead.Length >= 3 || fromBehind
            ; The ground is read a moment apart (each read stays under half a millisecond of the game's frame).
            Utility.Wait(0.1)
            back = IntelEngine.QuestGroundAhead(0.0 - tx, 0.0 - ty)
        EndIf
        ; Nobody is made when there is nowhere to put them now.
        If (ahead.Length >= 3 || fromBehind) && back.Length >= 3
            ObjectReference mark = player.PlaceAtMe(Game.GetFormFromFile(0x0000003B, "Skyrim.esm"), 1, false, false)
            mark.MoveTo(player, back[0] - player.GetPositionX(), back[1] - player.GetPositionY(), back[2] - player.GetPositionZ() + 20.0)
            String why = IntelEngine.ArcText(id, "thugwhy")
            String name = IntelEngine.ArcText(id, "thugname")
            Actor leader = None
            Float sx = 0.0   ; where the leader waits (the others on the same ground, a step to the side: placed
            Float sy = 0.0   ; beside the leader, the nearest navmesh could be down a slope, 1800 units off)
            Float sz = 0.0
            Bool given = false   ; nowhere for them now: nobody stays
            Int k = 0
            While k < count && !given
                Form base = IntelEngine.ArcForm(id, "thugbase" + k)
                Actor t = None
                If base != None
                    t = mark.PlaceAtMe(base, 1, false, false) as Actor
                EndIf
                If t != None
                    Int waited = 0
                    While !t.Is3DLoaded() && waited < 30
                        Utility.Wait(0.1)
                        waited += 1
                    EndWhile
                    t.SetAlpha(0.0, false)
                    If leader == None
                        Bool hidden = false
                        Int i = 0
                        While !hidden && i + 2 < ahead.Length
                            hidden = q.PutUnseen(t, player, ahead[i] - player.GetPositionX(), ahead[i + 1] - player.GetPositionY(), ahead[i + 2] - player.GetPositionZ() + 20.0)
                            hidden = hidden && IntelEngine.ArcInWilds(t)
                            If hidden
                                sx = ahead[i]
                                sy = ahead[i + 1]
                                sz = ahead[i + 2]
                            EndIf
                            i += 3
                        EndWhile
                        i = 0
                        While !hidden && fromBehind && i + 2 < back.Length
                            ; Behind the player, out of view: they come after the player from there.
                            hidden = q.PutUnseen(t, player, back[i] - player.GetPositionX(), back[i + 1] - player.GetPositionY(), back[i + 2] - player.GetPositionZ() + 20.0)
                            If hidden
                                sx = back[i]
                                sy = back[i + 1]
                                sz = back[i + 2]
                                behind = true
                            EndIf
                            i += 3
                        EndWhile
                        If hidden
                            leader = t
                            If name != ""
                                t.SetDisplayName(name, true)
                            EndIf
                            Int slot = IntelEngine.ArcField(id, "slot")
                            If slot >= 0 && slot < SLOTS
                                AmbushLeaders[slot] = t
                            EndIf
                        Else
                            ; Nowhere to hide him, and the game holds his body by now (it was waited for above): he
                            ; is not switched off and deleted where he stands, which is what crashed the game on a
                            ; big mod list. Not shown as he is (alpha 0), he steps out of the loaded ground the
                            ; game's own way and is taken away after that (Core.StepOut).
                            c.StepOut(t)
                            t = None
                            given = true
                        EndIf
                    Else
                        q.PutUnseen(t, player, sx - player.GetPositionX() + 140.0 * k - 210.0, sy - player.GetPositionY() - 100.0, sz - player.GetPositionZ() + 20.0)
                    EndIf
                    If t != None
                        t.SetAlpha(1.0, false)
                        StorageUtil.SetIntValue(t, "Intel_ArcThug", id)
                        If why != ""
                            c.InjectFact(t, why)
                        EndIf
                        IntelEngine.ArcThugPlaced(id, k, t)
                        placed += 1
                    EndIf
                EndIf
                k += 1
            EndWhile
            mark.Delete()
        EndIf
    EndIf
    IntelEngine.ArcAmbushDone(id, AMBUSH_PLACE)
    If placed > 0 && c != None
        If behind
            c.DebugMsg("Arcs: #" + id + " " + placed + " hired men come after the player from behind (no stretch of road ahead out of sight)")
            Chase(id)
        Else
            c.DebugMsg("Arcs: #" + id + " " + placed + " hired men wait on the road ahead on the player's way")
        EndIf
    EndIf
EndFunction

Function ComeAt(Int id, Bool armed = false)
    {They come to the player at a jog, wherever the player is (the fight is where the player stands, never off in the
    woods where the body and what it carries would not be found).}
    IntelEngine_Core c = Core()
    Actor player = Game.GetPlayer()
    Int k = 0
    While k < 3 && c != None
        Actor t = IntelEngine.ArcForm(id, "thug" + k) as Actor
        If t != None && !t.IsDead() && !t.IsInCombat()
            PO3_SKSEFunctions.SetLinkedRef(t, player as ObjectReference, c.IntelEngine_TravelTarget)
            ActorUtil.AddPackageOverride(t, c.TravelPackage_Jog, c.PRIORITY_TRAVEL, 1)
            t.EvaluatePackage()
            If armed
                t.DrawWeapon()
            EndIf
        EndIf
        k += 1
    EndWhile
EndFunction

Function StopComing(Actor t)
    IntelEngine_Core c = Core()
    If t != None && c != None
        ActorUtil.RemovePackageOverride(t, c.TravelPackage_Jog)
        ActorUtil.RemovePackageOverride(t, c.TravelPackage_Walk)
        ActorUtil.RemovePackageOverride(t, c.SandboxNearPlayerPackage)
        PO3_SKSEFunctions.SetLinkedRef(t, None, c.IntelEngine_TravelTarget)
    EndIf
EndFunction

Function Chase(Int id)
    {They come after the player: from behind when no stretch of road ahead was out of sight, down the road when the
    player did not come their way, or back at the player when something drew them off.}
    ComeAt(id)
    IntelEngine.ArcAmbushDone(id, AMBUSH_CHASE)
    Core().DebugMsg("Arcs: #" + id + " the hired men come after the player")
EndFunction

Function StepOut(Int id)
    {The player is near: the leader has a word as they come up (SkyrimNet gives the line, from what the men know of
    their errand and what they would settle for). They stop a few steps short. Nothing else yet: the player may
    answer, and the DLL reads what comes of it (ArcBridge::Parley); it says when they fall on the player.}
    Actor player = Game.GetPlayer()
    IntelEngine_Core c = Core()
    IntelEngine_Quests q = Quests()
    Actor leader = IntelEngine.ArcForm(id, "thug0") as Actor
    If leader != None && !leader.IsDead() && c != None
        ; Alone or with others: said as it is (a lone man spoke of "my lads", 2026-11-19).
        String company = ", alone, weapon drawn"
        If MenStanding(id) > 1
            company = " with the others, weapon drawn"
        EndIf
        If IntelEngine.ArcField(id, "ambushchase") == 1
            c.SendTaskNarration(leader, "has come after " + player.GetDisplayName() + " and closes in" + company, player)
        Else
            c.SendTaskNarration(leader, "steps out onto the road ahead of " + player.GetDisplayName() + " and comes on" + company, player)
        EndIf
        ComeAt(id, true)
    EndIf
    IntelEngine.ArcAmbushDone(id, AMBUSH_STRIKE)
    ; They stop a few steps short of the player and stand there, facing them (walked on, they pressed up against the
    ; player's shoulder, 2026-11-19).
    Float waited = 0.0
    While waited < 12.0 && leader != None && !leader.IsDead() && !leader.IsInCombat() && leader.GetDistance(player) > 380.0
        Utility.Wait(0.25)
        waited += 0.25
    EndWhile
    Int k = 0
    While k < 3 && q != None && c != None
        Actor t = IntelEngine.ArcForm(id, "thug" + k) as Actor
        If t != None && !t.IsDead() && !t.IsInCombat()
            q.Linger(t, c)
            t.SetLookAt(player)
        EndIf
        k += 1
    EndWhile
EndFunction

Function Fight(Int id)
    {They fall on the player: after the leader's word when nothing came of it, at once when the player struck first,
    again whenever they lost the player. Cutthroats from now on (the game's bandits: no crime to fight them), who go
    for the player on sight: told to fight from a distance alone, a leader 2900 units off never took it up
    (2026-11-19).}
    Actor player = Game.GetPlayer()
    IntelEngine_Core c = Core()
    Actor leader = IntelEngine.ArcForm(id, "thug0") as Actor
    If IntelEngine.ArcField(id, "ambushshort") == 1 && leader != None && !leader.IsDead() && c != None
        c.SendTaskNarration(leader, "finds " + player.GetDisplayName() + "'s purse too light for what was offered, and has had enough of talk", player)
    EndIf
    GuardPlayer(id)
    Faction bandits = Game.GetFormFromFile(0x0001BCC0, "Skyrim.esm") as Faction
    Int k = 0
    While k < 3
        Actor t = IntelEngine.ArcForm(id, "thug" + k) as Actor
        If t != None && !t.IsDead()
            StopComing(t)
            t.ClearLookAt()
            If bandits != None
                t.AddToFaction(bandits)
            EndIf
            t.SetActorValue("Aggression", 2.0)
            t.StartCombat(player)
            t.EvaluatePackage()
            Utility.Wait(0.3)
        EndIf
        k += 1
    EndWhile
    IntelEngine.ArcAmbushDone(id, AMBUSH_FIGHT)
EndFunction

Function StandDown(Int id)
    {The men stand down and leave: the player is beaten (they take what they came for), or they were talked out of
    it. They walk back toward whoever sent them and are gone once nobody sees it (WatchLeavers).}
    Actor player = Game.GetPlayer()
    IntelEngine_Core c = Core()
    Int why = IntelEngine.ArcField(id, "ambushend")
    Actor leader = IntelEngine.ArcForm(id, "thug0") as Actor
    Actor sender = IntelEngine.ArcForm(id, "thugsender") as Actor
    Int k = 0
    While k < 3 && c != None
        Actor t = IntelEngine.ArcForm(id, "thug" + k) as Actor
        If t != None && !t.IsDead()
            WalkOff(t, sender, c)
        EndIf
        k += 1
    EndWhile
    player.StopCombatAlarm()
    If why == 1
        ; Beaten: the player comes round a few moments after they have gone (WatchGuard).
        StorageUtil.SetFloatValue(self, "Intel_ArcGuardDown", Utility.GetCurrentRealTime())
    EndIf
    If leader != None && !leader.IsDead() && leader.Is3DLoaded() && c != None
        Bool others = StorageUtil.FormListCount(self, "Intel_ArcLeavers") > 1
        If why == 1 && others
            c.SendTaskNarration(leader, "stands over " + player.GetDisplayName() + ", beaten to the ground, takes what they came for and leaves with the others", player)
        ElseIf why == 1
            c.SendTaskNarration(leader, "stands over " + player.GetDisplayName() + ", beaten to the ground, takes what was wanted and leaves", player)
        ElseIf others
            c.SendTaskNarration(leader, "calls the others off: it is settled with " + player.GetDisplayName() + ", and they leave", player)
        Else
            c.SendTaskNarration(leader, "puts the weapon away: it is settled with " + player.GetDisplayName() + ", and leaves", player)
        EndIf
    EndIf
    IntelEngine.ArcAmbushDone(id, AMBUSH_STANDDOWN)
    If c != None
        c.DebugMsg("Arcs: #" + id + " the hired men stand down and leave (" + why + ")")
    EndIf
EndFunction

Function WalkOff(Actor t, Actor sender, IntelEngine_Core c)
    {One of the men is done here: a cutthroat no more, weapon away, walking back toward whoever sent them, and on the
    list of those who are gone once nobody is there to see it (WatchLeavers). (StandDown's own lines, shared with a
    story that ends while its men are still in the game: CallOff.) Only one of the men a story made, who carries its
    mark (PlaceAmbush): whoever is on that list is deleted once out of the game.}
    If t == None || StorageUtil.GetIntValue(t, "Intel_ArcThug", 0) <= 0
        Return
    EndIf
    Faction bandits = Game.GetFormFromFile(0x0001BCC0, "Skyrim.esm") as Faction
    If bandits != None
        t.RemoveFromFaction(bandits)
    EndIf
    t.SetActorValue("Aggression", 0.0)
    t.StopCombat()
    t.ClearLookAt()
    StopComing(t)
    If sender != None
        PO3_SKSEFunctions.SetLinkedRef(t, sender as ObjectReference, c.IntelEngine_TravelTarget)
        ActorUtil.AddPackageOverride(t, c.TravelPackage_Walk, c.PRIORITY_TRAVEL, 1)
    EndIf
    t.EvaluatePackage()
    t.SheatheWeapon()
    StorageUtil.FormListAdd(self, "Intel_ArcLeavers", t, false)
EndFunction

Int Function MenStanding(Int id)
    Int n = 0
    Int k = 0
    While k < 3
        Actor t = IntelEngine.ArcForm(id, "thug" + k) as Actor
        If t != None && !t.IsDead()
            n += 1
        EndIf
        k += 1
    EndWhile
    Return n
EndFunction

Function WatchLeavers()
    {Men of an ambush who stood down: gone from the world once nobody can see it, which is once the game no longer
    holds their body (they walk back toward whoever sent them, out of the loaded ground, or the player leaves). They
    used to be switched off and deleted from 3,000 units when out of view, their bodies still in the game: that is
    what crashed the game on a big mod list (Core.RemoveUnloaded has the rule; it also takes their mark off).}
    Int i = StorageUtil.FormListCount(self, "Intel_ArcLeavers") - 1
    If i < 0
        Return
    EndIf
    IntelEngine_Core c = Core()
    While i >= 0
        Actor t = StorageUtil.FormListGet(self, "Intel_ArcLeavers", i) as Actor
        Bool gone = t == None || t.IsDead() || t.IsDisabled()
        If !gone && c != None && c.RemoveUnloaded(t)
            gone = true
        EndIf
        If gone
            StorageUtil.FormListRemoveAt(self, "Intel_ArcLeavers", i)
        EndIf
        i -= 1
    EndWhile
EndFunction

; While the men of an ambush are on the player, the player is beaten down instead of killed (the game's own way: an
; essential actor goes to their knees), so that losing is a turn of the story and not a reload. Only when the story
; has a way on for a beaten player, only when nothing else already keeps the player alive (another mod's own
; defeat), and never longer than the fight.

Function GuardPlayer(Int id)
    If IntelEngine.ArcField(id, "ambushlost") != 1
        Return
    EndIf
    ActorBase who = Game.GetPlayer().GetActorBase()
    If StorageUtil.GetIntValue(self, "Intel_ArcGuard", 0) > 0
        StorageUtil.SetIntValue(self, "Intel_ArcGuard", id)
    ElseIf !who.IsEssential()
        who.SetEssential(true)
        StorageUtil.SetIntValue(self, "Intel_ArcGuard", id)
        Core().DebugMsg("Arcs: #" + id + " the player cannot be killed while the hired men are on them")
    EndIf
EndFunction

Function WatchGuard()
    Int id = StorageUtil.GetIntValue(self, "Intel_ArcGuard", 0)
    If id <= 0
        Return
    EndIf
    Actor player = Game.GetPlayer()
    Bool fight = IntelEngine.ArcField(id, "phase") == PHASE_OPEN && IntelEngine.ArcField(id, "kind") == KIND_AMBUSH && IntelEngine.ArcField(id, "struck") == 1
    If !fight && player.IsBleedingOut()
        ; Beaten and left there: the player comes round once the men have had time to go (left alone, the health
        ; stayed below nothing and the player on their knees, 2026-11-19).
        Float down = StorageUtil.GetFloatValue(self, "Intel_ArcGuardDown", 0.0)
        Float now = Utility.GetCurrentRealTime()
        If down <= 0.0 || now < down || now - down >= 6.0
            Float health = player.GetActorValue("Health")
            If health < 25.0
                player.RestoreActorValue("Health", 25.0 - health)
            EndIf
        EndIf
    ElseIf !fight
        player.GetActorBase().SetEssential(false)
        StorageUtil.UnsetIntValue(self, "Intel_ArcGuard")
        StorageUtil.UnsetFloatValue(self, "Intel_ArcGuardDown")
        Core().DebugMsg("Arcs: #" + id + " the fight with the hired men is over: the player is mortal again")
    EndIf
EndFunction

Function CallOff(Int id, Bool answer)
    {The player got away, reached a town, or the story is over: the men still alive stop coming, and leave the world
    once nobody can see it (asked again until they have). Only somebody whose body the game no longer holds is taken
    away (Core.RemoveUnloaded; it used to be done from 3,000 units when out of view, to bodies still in the game).
    Whoever is still there when the story is over is not asked about again: he walks off like the men who stood
    down and goes with them (WalkOff, WatchLeavers); he used to be left in the world.
    Only a man who still carries this story's mark (PlaceAmbush): the story keeps him by his id, and the id of one taken
    away already is handed out again by the game, to somebody this must never delete (Core.RemoveUnloaded takes the
    mark off with him).}
    IntelEngine_Core c = Core()
    Actor sender = IntelEngine.ArcForm(id, "thugsender") as Actor
    Int k = 0
    While k < 3
        Actor t = IntelEngine.ArcForm(id, "thug" + k) as Actor
        If t != None && StorageUtil.GetIntValue(t, "Intel_ArcThug", 0) == id && !t.IsDead() && StorageUtil.FormListFind(self, "Intel_ArcLeavers", t) < 0
            If c == None || !c.RemoveUnloaded(t)
                If answer || c == None
                    StopComing(t)
                    t.EvaluatePackage()
                Else
                    WalkOff(t, sender, c)
                EndIf
            EndIf
        EndIf
        k += 1
    EndWhile
    If answer
        IntelEngine.ArcAmbushDone(id, AMBUSH_CALLOFF)
    Else
        ; The story is over: the leader's body is let go of (and what was on it, if nobody took it).
        Actor leader = IntelEngine.ArcForm(id, "thug0") as Actor
        Int i = 0
        While i < AmbushLeaders.Length
            If AmbushLeaders[i] != None && (AmbushLeaders[i] == leader || AmbushLeaders[i].IsDisabled())
                AmbushLeaders[i] = None
            EndIf
            i += 1
        EndWhile
    EndIf
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

Function MoveMarker(Int id, Quest jq)
    {The journal's marker goes where the step's marker is now, without a word on the screen: the compass follows the
    alias by itself.}
    If jq == None || IntelEngine.ArcField(id, "objective") < 0
        Return
    EndIf
    ObjectReference now = IntelEngine.ArcForm(id, "marker") as ObjectReference
    ReferenceAlias a = jq.GetAlias(ALIAS_MARKER) as ReferenceAlias
    If a != None && a.GetReference() != now
        Force(jq, ALIAS_MARKER, now)
    EndIf
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

Int earshotLooks = 0
Int heartAt = 0

Function TellHearts()
    {What stands between the player and the people a relationship mod tracks is kept in that mod's own script storage:
    read here, a few people a look, and told to the DLL (HeartBridge), which reads the rest (factions, the game's
    ranks) itself. Without such a mod the list is empty and nothing happens. Soft reads only: a key that is not
    there reads as nothing.}
    Int total = StorageUtil.FormListCount(None, "SNRom_Roster")
    If total <= 0
        Return
    EndIf
    If heartAt >= total
        heartAt = 0
    EndIf
    Actor player = Game.GetPlayer()
    String playerName = player.GetDisplayName()
    Int looked = 0
    While looked < 4 && heartAt < total
        Actor who = StorageUtil.FormListGet(None, "SNRom_Roster", heartAt) as Actor
        If who != None
            ; With child, as SeverActions mirrors Fertility Mode for the women near the player.
            String carrying = StorageUtil.GetStringValue(who, "SkyrimNet_FM_State")
            Int withChild = 0
            If carrying == "first_trimester"
                withChild = 1
            ElseIf carrying == "second_trimester"
                withChild = 2
            ElseIf carrying == "third_trimester"
                withChild = 3
            EndIf
            String father = StorageUtil.GetStringValue(who, "SkyrimNet_FM_Father")
            Int children = StorageUtil.GetIntValue(who, "SNKin_ChildrenByPlayer")
            Int listed = StorageUtil.FormListCount(who, "SNKin_ChildrenByPlayer")
            If listed > children
                children = listed
            EndIf
            ; A no is remembered with its day (the relationship mod keeps only the no): it stands for a season, and
            ; what may come after is decided in the DLL (Hearts.h, SecondChance). A no taken back is forgotten.
            Int stance = StorageUtil.GetIntValue(who, "SNRom_PlayerStance")
            Float refusedAt = -1.0
            If stance < 0
                refusedAt = StorageUtil.GetFloatValue(who, "Intel_TurnedDownAt", -1.0)
                Float today = Utility.GetCurrentGameTime()
                If refusedAt < 0.0 || refusedAt > today
                    refusedAt = today
                    StorageUtil.SetFloatValue(who, "Intel_TurnedDownAt", refusedAt)
                EndIf
            ElseIf StorageUtil.HasFloatValue(who, "Intel_TurnedDownAt")
                StorageUtil.UnsetFloatValue(who, "Intel_TurnedDownAt")
            EndIf
            IntelEngine.ArcHeart(who, StorageUtil.GetIntValue(who, "SNRom_Sparked"), stance, \
                withChild, withChild > 0 && father != "" && father == playerName, children, StorageUtil.GetIntValue(who, "SNKin_IsPlayerChild") == 1, refusedAt)
        EndIf
        heartAt += 1
        looked += 1
    EndWhile
EndFunction

Function Watch()
    TellHearts()
    ; How far speech carries is SkyrimNet's setting (and whisper mode changes it): told to the engine on the first look
    ; and about once a minute.
    If earshotLooks <= 0
        earshotLooks = 30
        IntelEngine.ArcEarshot(SkyrimNetApi.GetConfigFloat("game", "interaction.maxDistance", 1600.0))
        ; The "Stories" switch of the settings holds for the town's own stories too: off, none begins.
        IntelEngine.ArcStoriesOn(Core().IsStoryEngineEnabled())
        ; So do the switches for each kind of moment: what is switched off there is not in a story either.
        IntelEngine_StoryEngine story = Core().StoryEngine
        If story != None
            Int off = 0
            If !story.TypeAmbushEnabled
                off += 1
            EndIf
            If !story.TypeStalkerEnabled
                off += 2
            EndIf
            If !story.QuestSubTypeRescueEnabled
                off += 4
            EndIf
            If !story.TypeQuestEnabled
                off += 8
            EndIf
            If !story.QuestSubTypeCombatEnabled
                off += 16
            EndIf
            If !story.QuestSubTypeFindItemEnabled
                off += 32
            EndIf
            IntelEngine.ArcStorySwitches(off)
        EndIf
    EndIf
    earshotLooks -= 1
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
    WatchCaptives()
    WatchLinger()
    WatchLeavers()
    WatchGuard()
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
    If Math.LogicalAnd(r, SIGNAL_PLACE) != 0
        ; The heart of a place is in the game only now (the player has come that far), or the journal's marker for
        ; the step has moved (onto the place, off it while inside, onto the heart or the master).
        PlaceBosses(id)
        PlaceCaptive(id)
        PlaceClues(id)
        TendSpirit(id)
        If jq != None && Math.LogicalAnd(r, 31) == 0
            ; Only the marker: the objective is on the screen already. Showing the step anew here put the quest's
            ; name and objective up again every time a marker moved or something was laid out in the world (the
            ; user, 2026-11-19: "The quest title appeared multiple times").
            MoveMarker(id, jq)
        EndIf
    EndIf
    If Math.LogicalAnd(r, SIGNAL_AMBUSH) != 0
        Ambush(id)
    EndIf
    ; Everything but the signals: the step done (bits 0-4), the ending, the effect.
    Int change = Math.LogicalAnd(r, 16777215 - SIGNAL_VISIT - SIGNAL_LINGER - SIGNAL_GANG - SIGNAL_AMBUSH - SIGNAL_PLACE)
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
    ; Someone who came to the player for a step of this story: that step is over, so is their visit.
    String visitorKey = "Intel_ArcVisitor" + IntelEngine.ArcField(id, "slot")
    Actor visitor = StorageUtil.GetFormValue(self, visitorKey) as Actor
    If visitor != None && (done >= 0 || Math.LogicalAnd(Math.RightShift(r, 8), 31) != 0)
        StorageUtil.UnsetFormValue(self, visitorKey)
        If Core().StoryEngine != None && (IntelEngine.ArcForm(id, "who") as Actor) != visitor
            Core().StoryEngine.VisitOver(visitor)
        EndIf
    EndIf
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
    CallOff(id, false)   ; men of an ambush still waiting somewhere unseen have no errand left
    ReleaseClues(id)
    ReleaseSpirit(id)
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
    If target == None && effect == EFFECT_PLAYERPAYS
        target = IntelEngine.ArcForm(id, "thug0") as Actor   ; the men's leader is paid off
    EndIf
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
    ElseIf effect == EFFECT_REMEDY
        GiveRemedy(id, IntelEngine.ArcField(id, "effectprop"), target)
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
    ElseIf (effect == EFFECT_CLOSER || effect == EFFECT_APART) && target != None && !target.IsDead()
        ; Someone and the player, a step closer or apart, as the game itself keeps it: friends greet as friends and
        ; share what is theirs. Never beyond friendship either way (the DLL's rule): what lies beyond is the
        ; player's own doing, and a relationship mod's to keep. Such a mod hears of it through what both remember
        ; of the story's ending; nothing of its state is written here.
        Int rank = target.GetRelationshipRank(player)
        Int after = IntelEngine.ArcRankAfter(rank, effect == EFFECT_CLOSER)
        If after != rank
            target.SetRelationshipRank(player, after)
        EndIf
        Core().DebugMsg("Arcs: #" + id + " " + target.GetDisplayName() + " and the player: rank " + rank + " -> " + after)
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
    If IntelEngine.ArcField(id, "kind") == KIND_STALK
        ; A tale's stalk step: they shadow the player from a distance until caught or coming forward (the story
        ; engine's stalker, with the tale's own reason).
        IntelEngine_Core sc = Core()
        If sc == None || sc.StoryEngine == None || !sc.StoryEngine.DispatchArcStalk(who, id, words)
            Core().DebugMsg("Arcs: #" + id + " " + who.GetDisplayName() + " cannot shadow the player now")
        EndIf
        Return
    EndIf
    If who.Is3DLoaded() && who.GetParentCell() == player.GetParentCell() && who.GetDistance(player) < 1500.0
        Quests().WaitForSilence(who, 15.0)
        Core().SendTaskNarration(who, "comes over to " + player.GetDisplayName() + ": " + IntelEngine.ArcText(id, "goal"), player)
        Core().DebugMsg("Arcs: #" + id + " " + who.GetDisplayName() + " is here and comes over")
        Return
    EndIf
    IntelEngine_Core c = Core()
    If c == None || c.StoryEngine == None || !c.StoryEngine.DispatchArcVisit(who, id, words)
        Core().DebugMsg("Arcs: #" + id + " " + who.GetDisplayName() + " cannot come now")
    Else
        StorageUtil.SetFormValue(self, "Intel_ArcVisitor" + IntelEngine.ArcField(id, "slot"), who)
    EndIf
EndFunction

; ----------------------------------------------------------------------------------------------- someone held at a place
; A tale may have one of its people held at a place out in the world (bandits, Forsworn, necromancers, vampires,
; hagravens, Falmer): taken out of anyone's sight before the asker has come, away from the game until the player has
; come as far as the heart of that place, bound there, freed by the player reaching them, and then with the player
; until they are out under the open sky, where they part and walk home. While held they are in the game's own faction
; for a dungeon's prisoners (Skyrim.esm dunPrisonerFaction, a friend of every such place's people, so nobody there
; harms them) and cannot die; all of it is taken off again when they part, or when the story ends without them.
; The 3.8 rescue quest did this by teleporting the victim in view and beating them into bleedout, and left them where
; they were when anything went wrong.

Int Property CAPTIVE_TOTAKE = 0 AutoReadOnly
Int Property CAPTIVE_AWAY = 1 AutoReadOnly
Int Property CAPTIVE_BOUND = 2 AutoReadOnly
Int Property CAPTIVE_FREED = 3 AutoReadOnly
Int Property CAPTIVE_HOME = 4 AutoReadOnly
Float Property CAPTIVE_PART_HOURS = 3.0 AutoReadOnly   ; with the player at most this long after being freed

Int CaptiveTries = 0
Int ClueTries = 0

Function PlaceClues(Int id)
    {What a tale leaves outside a place to be looked at closely (what was left of a victim: one of the game's hunters,
    or a beast of the farms and woods). Laid a few steps from the place's marker on the map, which stands by its way
    in, once that ground is in the game; dead from the first, and while the player is still a way off where that can
    be helped (a few looks; then it has to be). The player's hand on it is theirs to look, not to search, until they
    have looked (the DLL changes the crosshair's word).}
    Actor player = Game.GetPlayer()
    Int k = 0
    While k < 3
        Form base = IntelEngine.ArcForm(id, "cluebase" + k)
        ObjectReference anchor = IntelEngine.ArcForm(id, "clueanchor" + k) as ObjectReference
        If base != None && anchor != None
            Cell there = anchor.GetParentCell()
            If there != None && there.IsAttached()
                If player.GetDistance(anchor) < 2500.0 && ClueTries < 8
                    ClueTries += 1
                Else
                    ClueTries = 0
                    ; Right at the marker: that is where a traveller arrives, so it is ground one can stand on (a
                    ; few steps to the side, the first one lay inside a rock face). Dead only once it is really in
                    ; the game: killed a moment sooner, the body was there and could not be seen (played 2026-11-19).
                    ; A sign of a trail lies out from the place, on open ground the DLL found on the way to it
                    ; (ArcBridge::TrailSpot); what lies by the place itself, and anything no ground was found for,
                    ; lies at the place's marker. It is placed AT its spot: placed at the marker and moved there
                    ; before its body was in the game, it stayed invisible (the goat and the horse of the first
                    ; trail were there and could not be seen). So a marker goes to the spot first, which has no
                    ; body to wait for, and the dead one is placed at that.
                    ObjectReference at = anchor
                    ObjectReference pin = None
                    Float[] spot = IntelEngine.ArcTrailSpot(id, k)
                    If spot.Length == 3
                        Form xMarker = Game.GetFormFromFile(0x0000003B, "Skyrim.esm")
                        If xMarker != None
                            pin = anchor.PlaceAtMe(xMarker, 1, false, false)
                        EndIf
                        If pin != None
                            pin.SetPosition(spot[0], spot[1], spot[2] + 8.0)
                            at = pin
                        EndIf
                    EndIf
                    Actor lies = at.PlaceAtMe(base, 1, false, false) as Actor
                    If pin != None
                        pin.Delete()
                    EndIf
                    If lies != None
                        Int waited = 0
                        While !lies.Is3DLoaded() && waited < 30
                            Utility.Wait(0.1)
                            waited += 1
                        EndWhile
                        lies.KillSilent()
                        lies.BlockActivation(true)
                        ; The name the story gives the dead one, so that the crosshair and the window say who lies there.
                        String named = IntelEngine.ArcText(id, "cluename" + k)
                        If named != ""
                            lies.SetDisplayName(named, true)
                        EndIf
                        Core().DebugMsg("Arcs: #" + id + " " + lies.GetDisplayName() + " lies dead outside the place, to be looked at")
                    EndIf
                    IntelEngine.ArcCluePlaced(id, k, lies)
                EndIf
            EndIf
        EndIf
        k += 1
    EndWhile
EndFunction

Function GiveRemedy(Int id, Int site, Actor giver)
    {The player named rightly what killed someone: the one who heard it gives what they have against what lives in
    that place (the DLL knows what that is: the game's own potions and scrolls). Two of it, into the player's hands,
    and the giver knows they gave it.}
    Form remedy = IntelEngine.ArcForm(id, "remedy" + site)
    If remedy == None || giver == None || giver.IsDead()
        Return
    EndIf
    Actor player = Game.GetPlayer()
    player.AddItem(remedy, 2, true)
    Core().NotifyPlayer(giver.GetDisplayName() + " gave you " + remedy.GetName() + " (2).")
    Core().SendTaskNarration(giver, "hands " + player.GetDisplayName() + " two of " + remedy.GetName() + ", all they have against what did it", player)
    Core().DebugMsg("Arcs: #" + id + " " + giver.GetDisplayName() + " gives the player " + remedy.GetName() + " (named rightly what did it)")
EndFunction

Float SpiritTouchedAt = 0.0

Function TendSpirit(Int id)
    {What walks by night outside a place of a story. The DLL says when there is something to do: it is night and that
    ground is in the game (then "spiritbase" names whose shade to put there), or the sky has grown light while it is
    out. Put by the place's marker, or a little way behind the player when that spot is in plain view close by, and
    fading in either way: it is a shade. It is on nobody's side and starts no fight; the player's hand on it is the
    story's (the DLL hears it, OnArcSpirit). At first light it fades, unless it is fighting.}
    Actor player = Game.GetPlayer()
    Actor shade = IntelEngine.ArcForm(id, "spirit") as Actor
    Form base = IntelEngine.ArcForm(id, "spiritbase")
    If shade == None && base != None
        ObjectReference anchor = IntelEngine.ArcForm(id, "spiritanchor") as ObjectReference
        If anchor == None
            Return
        EndIf
        Cell there = anchor.GetParentCell()
        If there == None || !there.IsAttached()
            Return
        EndIf
        shade = anchor.PlaceAtMe(base, 1, true, true) as Actor
        If shade == None
            Return
        EndIf
        If player.GetDistance(anchor) < 1500.0 && player.HasLOS(anchor)
            Float behind = player.GetAngleZ() + 180.0
            shade.MoveTo(player, 900.0 * Math.Sin(behind), 900.0 * Math.Cos(behind), 0.0, false)
        EndIf
        shade.RemoveFromAllFactions()
        shade.SetActorValue("Aggression", 0)
        shade.SetActorValue("Confidence", 4)
        shade.SetActorValue("Assistance", 0)
        shade.BlockActivation(true)
        String named = IntelEngine.ArcText(id, "spiritname")
        If named != ""
            shade.SetDisplayName(named, true)
        EndIf
        ; The story's mark: only what carries it is ever taken out of the game as this story's shade (ShadeGoes).
        StorageUtil.SetIntValue(shade, "Intel_ArcShade", id)
        shade.Enable(true)
        IntelEngine.ArcSpiritOut(id, shade)
        Core().DebugMsg("Arcs: #" + id + " " + shade.GetDisplayName() + " walks outside " + IntelEngine.ArcText(id, "spiritplace") + " tonight")
    ElseIf shade != None && base == None
        Float day = Utility.GetCurrentGameTime()
        Float hour = (day - Math.Floor(day)) * 24.0
        If hour >= 5.0 && hour < 21.0 && !shade.IsDead() && !shade.IsInCombat()
            ShadeGoes(id, shade)
            IntelEngine.ArcSpiritGone(id, 0)
            Core().DebugMsg("Arcs: #" + id + " what walked there fades with the light")
        EndIf
    EndIf
EndFunction

Event OnArcSpirit(String eventName, String strArg, Float numArg, Form sender)
    {The player reached out to what walks by night (their hand on it; the DLL hears it, ArcBridge::Activated). With
    what it wants in their pack it is laid to rest: the thing goes with it, it says its last words, and it is gone.
    Without, their hand passes through it, and it answers that in its own way (not more than once in a while).}
    Int id = numArg as Int
    Actor shade = sender as Actor
    Actor player = Game.GetPlayer()
    ; Only the shade this story made (TendSpirit): laying it to rest takes it out of the game (ShadeGoes).
    If shade == None || shade.IsDead() || IntelEngine.ArcForm(id, "spirit") != shade
        Return
    EndIf
    If strArg == "rest"
        String thing = IntelEngine.ArcText(id, "spiritwants")
        If !IntelEngine.ArcSpiritRest(id)
            Return
        EndIf
        Core().DebugMsg("Arcs: #" + id + " " + shade.GetDisplayName() + " is laid to rest")
        Core().SendTaskNarration(shade, "is given " + thing + " by " + player.GetDisplayName() + ", the one thing that held them here, and can rest at last; they say their last words to the living before they are gone", player)
        Utility.Wait(2.0)
        Quests().WaitForTheirSay(shade, 30.0)
        ShadeGoes(id, shade)
        IntelEngine.ArcSpiritGone(id, 3)
    Else
        Float now = Utility.GetCurrentRealTime()
        If now - SpiritTouchedAt < 20.0 && now >= SpiritTouchedAt
            Return
        EndIf
        SpiritTouchedAt = now
        Core().SendTaskNarration(shade, "is reached for by " + player.GetDisplayName() + ", whose hand passes through them like cold mist", player)
    EndIf
EndEvent

Function ReleaseSpirit(Int id)
    {A story is over: nothing of it walks any more. What was struck down lies where it fell, as the game leaves its
    dead.}
    Actor shade = IntelEngine.ArcForm(id, "spirit") as Actor
    If shade != None
        If !shade.IsDead()
            ShadeGoes(id, shade)
        EndIf
        IntelEngine.ArcSpiritGone(id, 0)
    EndIf
EndFunction

Function ShadeGoes(Int id, Actor shade)
    {A shade is gone: it fades with the light, is laid to rest, or its story is over. It fades out where it stands,
    as it always did, but it is no longer switched off and deleted there: the game holds its body, and that is what
    crashed the game on a big mod list (Core, "People the mod made"). The fade is the game's own, with the game's own
    wait (its fading ghosts go by SetAlpha and two and a half seconds: DLC1FadingGhostScript.FadeOut); not shown any
    more, the shade steps out of the loaded ground the game's own way (Core.StepOut) and is taken away once its body
    is out of the game. Not in the game at all (the player is elsewhere): gone at once.
    Only the shade this story made: the story keeps it by its id, which the game hands out again once a body is gone
    (one struck down leaves its remains, and the story still names it), and Core deletes whoever it is given. So it
    has to carry the story's mark (TendSpirit), or, made before shades carried one, the story's name for it.}
    IntelEngine_Core c = Core()
    If c == None || shade == None
        Return
    EndIf
    Int mark = StorageUtil.GetIntValue(shade, "Intel_ArcShade", 0)
    Bool ours = mark == id
    If !ours && mark == 0
        String named = IntelEngine.ArcText(id, "spiritname")
        ours = named != "" && shade.GetDisplayName() == named
    EndIf
    If !ours
        c.DebugMsg("Arcs: #" + id + " " + shade + " is not the shade this story made - left alone")
        Return
    EndIf
    If c.RemoveUnloaded(shade)
        Return
    EndIf
    shade.SetAlpha(0.0, true)
    Utility.Wait(2.5)
    c.StepOut(shade)
EndFunction

Function ReleaseClues(Int id)
    {A story is over: what it left to be looked at is an ordinary body again, whether anyone looked or not.}
    Int k = 0
    While k < 2
        ObjectReference lies = IntelEngine.ArcForm(id, "clue" + k) as ObjectReference
        If lies != None
            lies.BlockActivation(false)
        EndIf
        k += 1
    EndWhile
EndFunction

Faction Function PrisonerFaction()
    Return Game.GetFormFromFile(0x000AA784, "Skyrim.esm") as Faction
EndFunction

Function TakeCaptive(Int id)
    {The story's asker is on the way: whoever is held in it leaves the game now, where nobody sees it.}
    Actor who = IntelEngine.ArcForm(id, "captive") as Actor
    If who == None || who.IsDead() || StorageUtil.GetIntValue(who, "Intel_ArcCaptive", 0) == id
        Return
    EndIf
    StorageUtil.SetIntValue(who, "Intel_ArcCaptive", id)
    StorageUtil.SetIntValue(who, "Intel_ArcCaptiveAt", CAPTIVE_TOTAKE)
    StorageUtil.FormListAdd(self, "Intel_ArcCaptives", who, false)
    WatchCaptives()
EndFunction

Bool Function CaptiveGone(Int id)
    {True when nobody is held in this story, or the one held is out of the game by now. False: they stand where the
    player may see them, and the asker's word that they were taken would be a lie in plain sight.}
    Actor who = IntelEngine.ArcForm(id, "captive") as Actor
    If who == None
        Return true
    EndIf
    TakeCaptive(id)
    Return StorageUtil.GetIntValue(who, "Intel_ArcCaptiveAt", CAPTIVE_TOTAKE) >= CAPTIVE_AWAY
EndFunction

Function PlaceCaptive(Int id)
    {The heart of the place is in the game (the player has come that far): the one held there is put beside it, bound,
    out of the player's view where that can be helped.}
    Actor who = IntelEngine.ArcForm(id, "captive") as Actor
    If who == None || who.IsDead() || StorageUtil.GetIntValue(who, "Intel_ArcCaptive", 0) != id
        Return
    EndIf
    If StorageUtil.GetIntValue(who, "Intel_ArcCaptiveAt", CAPTIVE_TOTAKE) != CAPTIVE_AWAY
        Return
    EndIf
    ObjectReference anchor = IntelEngine.ArcForm(id, "captiveanchor") as ObjectReference
    If anchor == None
        Return
    EndIf
    Cell there = anchor.GetParentCell()
    If there == None || !there.IsAttached()
        Return
    EndIf
    Actor player = Game.GetPlayer()
    If there == player.GetParentCell() && player.GetDistance(anchor) < 1500.0 && player.HasLOS(anchor) && CaptiveTries < 8
        CaptiveTries += 1
        Return
    EndIf
    CaptiveTries = 0
    ; A prisoner of the place before they stand in it: put there first and made one a moment later, the bandits
    ; beside them had already drawn on a stranger, and went on striking after the faction was set (played at White
    ; River Watch, 2026-11-19: two of them had him at half his health within twenty seconds).
    HoldCaptive(who)
    who.MoveTo(anchor, 110.0, 80.0, 0.0)
    who.Enable()
    who.SetRestrained(true)
    BindCaptive(who)
    StorageUtil.SetIntValue(who, "Intel_ArcCaptiveAt", CAPTIVE_BOUND)
    IntelEngine.ArcCaptive(id, CAPTIVE_BOUND)
    Core().DebugMsg("Arcs: #" + id + " " + who.GetDisplayName() + " is held at the heart of " + IntelEngine.ArcText(id, "captiveplace"))
EndFunction

Function HoldCaptive(Actor who)
    {Bound, safe from the people of the place, and not able to die while the story has them.}
    ActorBase base = who.GetActorBase()
    If StorageUtil.GetIntValue(who, "Intel_ArcCaptiveEss", -1) < 0
        StorageUtil.SetIntValue(who, "Intel_ArcCaptiveEss", base.IsEssential() as Int)
    EndIf
    base.SetEssential(true)
    Faction prisoners = PrisonerFaction()
    If prisoners != None && StorageUtil.GetIntValue(who, "Intel_ArcCaptiveFac", -1) < 0
        StorageUtil.SetIntValue(who, "Intel_ArcCaptiveFac", who.IsInFaction(prisoners) as Int)
        who.AddToFaction(prisoners)
    EndIf
    who.StopCombat()
    who.SetRestrained(true)
    ; The player's hand on them cuts them loose (the DLL hears the activation): the game's own answer to it (its
    ; dialogue menu) stays away meanwhile. The crosshair says "Cut loose" on them where it would say "Talk": the
    ; DLL's doing (ArcBridge.cpp, NpcActivateText), since a script cannot change that word.
    who.BlockActivation(true)
    who.EvaluatePackage()
    BindCaptive(who)
EndFunction

Function BindCaptive(Actor who)
    {On their knees, hands bound: the game's own pose for a prisoner. Asked for whenever they come into the game anew
    (a pose is not kept across a load or a change of cell).}
    If who.Is3DLoaded()
        Debug.SendAnimationEvent(who, "IdleBoundKneesStart")
        StorageUtil.SetFloatValue(who, "Intel_ArcCaptiveBound", Utility.GetCurrentRealTime())
    EndIf
EndFunction

Function UnholdCaptive(Actor who, Bool keepSafe)
    {The bonds come off. keepSafe: still the place's prisoner in its people's eyes and still not able to die (walking
    out with the player); else everything the story put on them is taken off.}
    who.SetRestrained(false)
    who.BlockActivation(false)
    If who.Is3DLoaded()
        Debug.SendAnimationEvent(who, "IdleForceDefaultState")
    EndIf
    StorageUtil.UnsetFloatValue(who, "Intel_ArcCaptiveBound")
    If !keepSafe
        Faction prisoners = PrisonerFaction()
        If prisoners != None && StorageUtil.GetIntValue(who, "Intel_ArcCaptiveFac", -1) == 0
            who.RemoveFromFaction(prisoners)
        EndIf
        StorageUtil.UnsetIntValue(who, "Intel_ArcCaptiveFac")
        Int was = StorageUtil.GetIntValue(who, "Intel_ArcCaptiveEss", -1)
        If was == 0
            who.GetActorBase().SetEssential(false)
        EndIf
        StorageUtil.UnsetIntValue(who, "Intel_ArcCaptiveEss")
    EndIf
    who.EvaluatePackage()
EndFunction

Function ForgetCaptive(Actor who, Int i)
    StorageUtil.UnsetIntValue(who, "Intel_ArcCaptive")
    StorageUtil.UnsetIntValue(who, "Intel_ArcCaptiveAt")
    StorageUtil.UnsetFloatValue(who, "Intel_ArcCaptiveFreed")
    StorageUtil.FormListRemoveAt(self, "Intel_ArcCaptives", i)
EndFunction

Function WatchCaptives()
    {Every look: whoever a story holds is moved on by what is true now. A story that ended, was turned down or never
    came lets go of them, and they are home again without anyone seeing how.}
    Int i = StorageUtil.FormListCount(self, "Intel_ArcCaptives") - 1
    Actor player = Game.GetPlayer()
    While i >= 0
        Actor who = StorageUtil.FormListGet(self, "Intel_ArcCaptives", i) as Actor
        If who == None
            StorageUtil.FormListRemoveAt(self, "Intel_ArcCaptives", i)
        ElseIf who.IsDead()
            who.BlockActivation(false)
            ForgetCaptive(who, i)
        Else
            Int id = StorageUtil.GetIntValue(who, "Intel_ArcCaptive", 0)
            Int at = StorageUtil.GetIntValue(who, "Intel_ArcCaptiveAt", CAPTIVE_TOTAKE)
            Int phase = IntelEngine.ArcField(id, "phase")   ; -1 dropped, 0 planned, 1 open, 2 ended
            Bool live = phase == PHASE_PLANNED || phase == PHASE_OPEN
            If at == CAPTIVE_TOTAKE
                If !live
                    ForgetCaptive(who, i)   ; never taken: nothing to undo
                ElseIf !who.Is3DLoaded()
                    ; Switched off only when the game does not hold their body. (Unseen() alone used to do: from
                    ; 3,000 units and out of view they were switched off as they stood, which is what crashed the
                    ; game on a big mod list: Core, "People the mod made".)
                    who.Disable()
                    StorageUtil.SetIntValue(who, "Intel_ArcCaptiveAt", CAPTIVE_AWAY)
                    IntelEngine.ArcCaptive(id, CAPTIVE_AWAY)
                    Core().DebugMsg("Arcs: #" + id + " " + who.GetDisplayName() + " has been taken (away from the game)")
                ElseIf Unseen(who)
                    ; Far off and out of view, but their body is in the game: they go to where they will be held,
                    ; the game's own way out of the loaded ground (MoveTo, as through any door), when that ground
                    ; is not in the game. The next look finds their body gone and switches them off. Nowhere to
                    ; go yet: they are taken once they or the player have left.
                    ObjectReference held = IntelEngine.ArcForm(id, "captiveanchor") as ObjectReference
                    If held != None && !Core().GroundInGame(held)
                        who.MoveTo(held, 110.0, 80.0, 0.0)
                    EndIf
                EndIf
            ElseIf at == CAPTIVE_AWAY
                If !live
                    ; Back where the game keeps them, never appearing in front of the player.
                    who.MoveToMyEditorLocation()
                    Cell home = who.GetParentCell()
                    Bool inSight = home != None && home == player.GetParentCell() && (home.IsInterior() || who.GetDistance(player) < 4000.0)
                    If !inSight
                        who.Enable()
                        who.EvaluatePackage()
                        ForgetCaptive(who, i)
                        Core().DebugMsg("Arcs: " + who.GetDisplayName() + " is back home (the story that had them taken is over)")
                    EndIf
                EndIf
            ElseIf at == CAPTIVE_BOUND
                If IntelEngine.ArcField(id, "captivestate") == CAPTIVE_FREED
                    ; The player has cut them loose with their own hand. Untied, and with the player from here.
                    UnholdCaptive(who, true)
                    IntelEngine_Threads t = Threads()
                    If t != None
                        t.Follow(who, true)
                    EndIf
                    StorageUtil.SetIntValue(who, "Intel_ArcCaptiveAt", CAPTIVE_FREED)
                    StorageUtil.SetFloatValue(who, "Intel_ArcCaptiveFreed", Utility.GetCurrentGameTime())
                    Core().SendTaskNarration(who, "has been found and untied by " + player.GetDisplayName() + " at " + IntelEngine.ArcText(id, "captiveplace") + ", and keeps close to " + player.GetDisplayName() + " on the way out", player)
                    Core().DebugMsg("Arcs: #" + id + " " + who.GetDisplayName() + " is free and follows the player out")
                ElseIf !live
                    ; The story ended with them still held (given up, too late): they are home again, unseen.
                    If Unseen(who)
                        UnholdCaptive(who, false)
                        who.MoveToMyEditorLocation()
                        who.EvaluatePackage()
                        ForgetCaptive(who, i)
                        Core().DebugMsg("Arcs: " + who.GetDisplayName() + " is back home (the story that held them is over)")
                    EndIf
                ElseIf who.Is3DLoaded() && StorageUtil.GetFloatValue(who, "Intel_ArcCaptiveBound", -1.0) < 0.0
                    BindCaptive(who)   ; come into the game anew: the pose again
                ElseIf !who.Is3DLoaded()
                    StorageUtil.UnsetFloatValue(who, "Intel_ArcCaptiveBound")
                EndIf
            ElseIf at == CAPTIVE_FREED
                Float since = (Utility.GetCurrentGameTime() - StorageUtil.GetFloatValue(who, "Intel_ArcCaptiveFreed", 0.0)) * 24.0
                Bool talking = (IntelEngine.ArcForm(id, "who") as Actor) == who && phase == PHASE_OPEN
                If (IntelEngine.ArcField(id, "captiveout") == 1 && !talking && !player.IsInCombat()) || since > CAPTIVE_PART_HOURS || phase < 0
                    ; Out under the open sky (or it has been long enough): they part here and walk home.
                    IntelEngine_Threads t = Threads()
                    If t != None
                        t.Follow(who, false)
                    EndIf
                    UnholdCaptive(who, false)
                    If who.Is3DLoaded() && who.GetDistance(player) < 2000.0
                        Core().SendTaskNarration(who, "is out and safe, parts from " + player.GetDisplayName() + " here and sets off for home", player)
                    EndIf
                    If who.Is3DLoaded()
                        Quests().WalkOn(who, Core())
                    Else
                        ; The player went on without them (fast travel, a long way ahead): nobody sees them, so they are
                        ; simply home, instead of standing where they were left.
                        who.MoveToMyEditorLocation()
                        who.EvaluatePackage()
                    EndIf
                    IntelEngine.ArcCaptive(id, CAPTIVE_HOME)
                    ForgetCaptive(who, i)
                    Core().DebugMsg("Arcs: #" + id + " " + who.GetDisplayName() + " parts from the player and walks home")
                EndIf
            EndIf
        EndIf
        i -= 1
    EndWhile
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
            ; Only when the game does not hold their body (they went indoors or out of the loaded ground, or the
            ; player did). Unseen() used to do: switched off as they stood from 3,000 units when out of view, which is
            ; what crashed the game on a big mod list (Core, "People the mod made"). They leave a little later now.
            If !who.Is3DLoaded()
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
