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
; The venture on the road, not met yet: whether its people have recognised the player and are coming over.
Int RoadVenture
Bool RoadRecognised

Float Property RECOGNISE_DISTANCE = 2500.0 AutoReadOnly   ; they see the player this far off and come over
Float Property RECOGNISE_ANYWAY = 1000.0 AutoReadOnly     ; this close they notice whatever they are looking at
Float Property CHASE_GIVE_UP = 120.0 AutoReadOnly         ; seconds of catching up before they let the player go

; The ground the player has walked outdoors lately (every 400 units or more, the last 24 spots, one worldspace): a
; venture is put on it, behind the player, where people really can walk. Placed a fixed distance ahead instead,
; Jenassa stood inside a hillside by the river in Riverwood and never moved (2026-11-18).
Float[] TrailX
Float[] TrailY
Float[] TrailZ
Int TrailHead
Int TrailCount
WorldSpace TrailWorld
Bool RoadChasing
Float RoadChaseSince

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
    If TrailX.Length != 24
        TrailX = new Float[24]
        TrailY = new Float[24]
        TrailZ = new Float[24]
    EndIf
    TrailCount = 0
    TrailHead = 0
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
    Bool behind = PlaceOnTrail(ally)
    If behind
        ; On the road the player walked, behind them: they saw the player ahead and hurry to catch up. Kept as a
        ; road traveller (the story engine greets the player when they are close, sends them on and home after).
        ObjectReference goal = IntelEngine.ResolveAnyDestination(ally, IntelEngine.QuestText(id, "place"))
        c.RemoveAllPackages(ally, false)
        If goal != None
            StorageUtil.SetFormValue(ally, "Intel_FakeEncounterDest", goal)
        EndIf
        StorageUtil.SetStringValue(ally, "Intel_FakeEncounterNarration", IntelEngine.QuestText(id, "roadcatchup"))
        StorageUtil.SetFloatValue(ally, "Intel_FakeEncounterTime", Utility.GetCurrentGameTime())
        StorageUtil.SetIntValue(ally, "Intel_FakeEncounterInteracted", 0)
        If StorageUtil.IntListFind(player, "Intel_FakeEncounterNPCs", ally.GetFormID()) < 0
            StorageUtil.IntListAdd(player, "Intel_FakeEncounterNPCs", ally.GetFormID())
        EndIf
        CatchUp(ally, c)
        c.RequestTick(c.StoryEngine.MONITOR_INTERVAL)
    Else
        c.StoryEngine.PlaceRoadEncounter(ally, IntelEngine.QuestText(id, "roadnarration"), IntelEngine.QuestText(id, "place"))
        ; On ground they can walk, as far as can be told without a trail.
        PO3_SKSEFunctions.MoveToNearestNavmeshLocation(ally)
    EndIf
    Actor companion = IntelEngine.QuestForm(id, "companion") as Actor
    ObjectReference dest = StorageUtil.GetFormValue(ally, "Intel_FakeEncounterDest") as ObjectReference
    If companion != None && !companion.IsDead()
        ; Beside the ally, out of sight as they were placed. Kept as a road traveller of their own (the story engine's
        ; road encounters), already walking: they stop when the ally greets the player, walk on with them when the
        ; player goes, and go home after a day like any road traveller.
        companion.SetAlpha(0.0, false)
        c.RemoveAllPackages(companion, false)
        companion.MoveTo(ally, 120.0, 60.0, 0.0, false)
        PO3_SKSEFunctions.MoveToNearestNavmeshLocation(companion)
        companion.SetAlpha(1.0, false)
        If dest != None
            StorageUtil.SetFormValue(companion, "Intel_FakeEncounterDest", dest)
        EndIf
        If behind
            CatchUp(companion, c)
        ElseIf dest != None
            PO3_SKSEFunctions.SetLinkedRef(companion, dest, c.IntelEngine_TravelTarget)
            ActorUtil.AddPackageOverride(companion, c.TravelPackage_Walk, c.PRIORITY_TRAVEL, 1)
        EndIf
        companion.EvaluatePackage()
        StorageUtil.SetStringValue(companion, "Intel_FakeEncounterNarration", CompanionNarration(id, companion))
        StorageUtil.SetFloatValue(companion, "Intel_FakeEncounterTime", Utility.GetCurrentGameTime())
        StorageUtil.SetIntValue(companion, "Intel_FakeEncounterInteracted", 2)
        If StorageUtil.IntListFind(player, "Intel_FakeEncounterNPCs", companion.GetFormID()) < 0
            StorageUtil.IntListAdd(player, "Intel_FakeEncounterNPCs", companion.GetFormID())
        EndIf
    EndIf
    IntelEngine.QuestVenturePlaced(id)
    RoadVenture = id
    RoadRecognised = behind
    RoadChasing = behind
    RoadChaseSince = Utility.GetCurrentRealTime()
    IntelEngine.LivingWorldMomentDispatched(ally, "road_encounter")
    c.DebugMsg("Quests: " + ally.GetDisplayName() + " is on the road to " + IntelEngine.QuestText(id, "place") + " (venture " + id + ")")
    Return true
EndFunction

Function RecordTrail()
    {Where the player walks outdoors, every 400 units or more; a jump (fast travel, a door, a teleport) starts over.}
    Actor player = Game.GetPlayer()
    Cell here = player.GetParentCell()
    If here == None || here.IsInterior() || TrailX.Length != 24
        Return
    EndIf
    WorldSpace world = player.GetWorldSpace()
    If world != TrailWorld
        TrailWorld = world
        TrailCount = 0
    EndIf
    Float x = player.GetPositionX()
    Float y = player.GetPositionY()
    Float z = player.GetPositionZ()
    If TrailCount > 0
        Int last = (TrailHead + 23) % 24
        Float dx = x - TrailX[last]
        Float dy = y - TrailY[last]
        Float d = Math.Sqrt(dx * dx + dy * dy)
        If d < 400.0
            Return
        EndIf
        If d > 3000.0
            TrailCount = 0
        EndIf
    EndIf
    TrailX[TrailHead] = x
    TrailY[TrailHead] = y
    TrailZ[TrailHead] = z
    TrailHead = (TrailHead + 1) % 24
    If TrailCount < 24
        TrailCount += 1
    EndIf
EndFunction

Bool Function PlaceOnTrail(Actor npc)
    {On a spot of the player's trail 2000 to 6000 units away that the player cannot see, the nearest such first.}
    Actor player = Game.GetPlayer()
    If TrailCount == 0 || player.GetWorldSpace() != TrailWorld
        Return false
    EndIf
    Float px = player.GetPositionX()
    Float py = player.GetPositionY()
    Float pz = player.GetPositionZ()
    IntelEngine_Core c = Core()
    Int k = 1
    While k <= TrailCount
        Int i = (TrailHead - k + 48) % 24
        Float dx = TrailX[i] - px
        Float dy = TrailY[i] - py
        Float d = Math.Sqrt(dx * dx + dy * dy)
        If d >= 2000.0 && d <= 6000.0
            npc.SetAlpha(0.0, false)
            npc.MoveTo(player, dx, dy, TrailZ[i] - pz + 10.0, false)
            Int waited = 0
            While !npc.Is3DLoaded() && waited < 10
                Utility.Wait(0.1)
                waited += 1
            EndWhile
            If npc.Is3DLoaded() && !c.PlayerCanSee(npc)
                npc.SetAlpha(1.0, false)
                c.DebugMsg("Quests: " + npc.GetDisplayName() + " is on the road behind the player (" + (d as Int) + " units)")
                Return true
            EndIf
        EndIf
        k += 1
    EndWhile
    npc.SetAlpha(1.0, false)
    Return false
EndFunction

Function CatchUp(Actor npc, IntelEngine_Core c)
    {Hurry after the player (a jog), as someone does who saw a friend ahead on the road.}
    ActorUtil.RemovePackageOverride(npc, c.TravelPackage_Walk)
    PO3_SKSEFunctions.SetLinkedRef(npc, Game.GetPlayer() as ObjectReference, c.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(npc, c.TravelPackage_Jog, c.PRIORITY_TRAVEL, 1)
    npc.EvaluatePackage()
EndFunction

Function GiveUpChase(IntelEngine_Core c)
    {The player got away: they walk on to the place instead (and are road travellers as before).}
    RoadChasing = false
    Actor ally = IntelEngine.QuestForm(RoadVenture, "ally") as Actor
    Actor companion = IntelEngine.QuestForm(RoadVenture, "companion") as Actor
    Int n = 0
    While n < 2
        Actor npc = ally
        If n == 1
            npc = companion
        EndIf
        If npc != None
            ActorUtil.RemovePackageOverride(npc, c.TravelPackage_Jog)
            ObjectReference goal = StorageUtil.GetFormValue(npc, "Intel_FakeEncounterDest") as ObjectReference
            If goal != None
                PO3_SKSEFunctions.SetLinkedRef(npc, goal, c.IntelEngine_TravelTarget)
                ActorUtil.AddPackageOverride(npc, c.TravelPackage_Walk, c.PRIORITY_TRAVEL, 1)
            EndIf
            npc.EvaluatePackage()
        EndIf
        n += 1
    EndWhile
    c.DebugMsg("Quests: the venture's people could not catch up with the player and walk on")
    RoadVenture = 0
EndFunction

String Function CompanionNarration(Int id, Actor companion)
    {What drives the companion to speak when the two stop: an old friend glad to see the player, or someone who has
    never met them and travels with someone who has.}
    If IntelEngine.NPCKnowsPlayer(companion)
        Return IntelEngine.QuestText(id, "companionnarration")
    EndIf
    Return IntelEngine.QuestText(id, "companionstranger")
EndFunction

Function WatchRoad()
    {The venture on the road: once its people see the player (in sight and near enough, or close by), they turn and
    come over instead of walking on; the story engine's road encounter greets the player when they are there.}
    If RoadVenture <= 0
        Return
    EndIf
    If IntelEngine.QuestField(RoadVenture, "phase") != PHASE_PLANNED
        RoadVenture = 0
        Return
    EndIf
    Actor ally = IntelEngine.QuestForm(RoadVenture, "ally") as Actor
    Actor player = Game.GetPlayer()
    If RoadRecognised
        IntelEngine_Core c0 = Core()
        ; Come over and close enough: they greet the player even when the walk ended a little short of the story
        ; engine's own greeting distance.
        If ally != None && ally.Is3DLoaded() && StorageUtil.GetIntValue(ally, "Intel_FakeEncounterInteracted", 0) == 0 && ally.GetDistance(player) <= 450.0
            StorageUtil.SetIntValue(ally, "Intel_FakeEncounterInteracted", 1)
            RoadChasing = false
            c0.StoryEngine.TriggerRoadEncounterGreeting(ally)
        ElseIf RoadChasing && Utility.GetCurrentRealTime() - RoadChaseSince > CHASE_GIVE_UP
            GiveUpChase(c0)
        EndIf
        Return
    EndIf
    If ally == None || !ally.Is3DLoaded() || ally.IsInCombat() || player.IsInCombat()
        Return
    EndIf
    Cell here = ally.GetParentCell()
    If here == None || here.IsInterior() || ally.GetWorldSpace() != player.GetWorldSpace()
        Return
    EndIf
    Float distance = ally.GetDistance(player)
    If distance > RECOGNISE_DISTANCE
        Return
    EndIf
    If distance > RECOGNISE_ANYWAY && !ally.HasLOS(player)
        Return
    EndIf
    RoadRecognised = true
    IntelEngine_Core c = Core()
    ComeOver(ally, c, false)
    Actor companion = IntelEngine.QuestForm(RoadVenture, "companion") as Actor
    If companion != None && companion.Is3DLoaded()
        ComeOver(companion, c, true)
    EndIf
    c.DebugMsg("Quests: " + ally.GetDisplayName() + " recognises " + player.GetDisplayName() + " on the road and comes over (" + (distance as Int) + " units)")
EndFunction

Function ComeOver(Actor npc, IntelEngine_Core c, Bool stay)
    {Turn from the road and walk to the player. The walk is taken off and put on again: a running travel package
    keeps the target it started with, and only re-pointing its linked reference let Jenassa walk on (2026-11-18).
    The one who comes along (stay) gets the linger instead, so they wait by the player once there: on a walk alone
    Ugor arrived, the walk ended, and she went home.}
    ActorUtil.RemovePackageOverride(npc, c.TravelPackage_Walk)
    PO3_SKSEFunctions.SetLinkedRef(npc, Game.GetPlayer() as ObjectReference, c.IntelEngine_TravelTarget)
    ; Another package than the walk they were on: the same one put back kept its old target, and Jenassa walked on
    ; to White River Watch (2026-11-18). A jog: they hurry over.
    If stay
        ActorUtil.AddPackageOverride(npc, c.SandboxNearPlayerPackage, c.PRIORITY_SANDBOX, 1)
    Else
        ActorUtil.AddPackageOverride(npc, c.TravelPackage_Jog, c.PRIORITY_TRAVEL, 1)
    EndIf
    npc.EvaluatePackage()
EndFunction

Function CompanionStops(Int id)
    {The ally greeted the player: whoever travels with them stops too, stands with them, and has their say once the
    ally's line is over (one speaker at a time).}
    Actor companion = IntelEngine.QuestForm(id, "companion") as Actor
    Actor ally = IntelEngine.QuestForm(id, "ally") as Actor
    Actor player = Game.GetPlayer()
    IntelEngine_Core c = Core()
    If companion == None || companion.IsDead() || !companion.Is3DLoaded() || c == None
        Return
    EndIf
    ActorUtil.RemovePackageOverride(companion, c.TravelPackage_Walk)
    ActorUtil.RemovePackageOverride(companion, c.TravelPackage_Jog)
    PO3_SKSEFunctions.SetLinkedRef(companion, player as ObjectReference, c.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(companion, c.SandboxNearPlayerPackage, c.PRIORITY_SANDBOX, 1)
    companion.EvaluatePackage()
    StorageUtil.SetIntValue(companion, "Intel_FakeEncounterInteracted", 1)
    StorageUtil.SetFloatValue(companion, "Intel_FakeEncounterGreetTime", Utility.GetCurrentRealTime())
    StorageUtil.SetFloatValue(companion, "Intel_FakeEncounterElapsed", 0.0)
    WaitForSilence(ally, 25.0)
    companion.SetLookAt(player)
    c.SendTaskNarration(companion, StorageUtil.GetStringValue(companion, "Intel_FakeEncounterNarration"), player)
    WaitForTheirSay(companion, 25.0)
EndFunction

Function WaitForSilence(Actor npc, Float most)
    {Until they have said everything: quiet for two and a half seconds. A reply comes in several lines and between
    two of them nobody is talking, so "not talking now" let the popup cut Jenassa off and Lob never had his say
    (2026-11-18). At most this long.}
    Float waited = 0.0
    While waited < most && npc != None && npc.Is3DLoaded()
        Float since = IntelEngine.GetSecondsSinceNPCSpoke(npc)
        If !IntelEngine.IsActorTalking(npc) && (since < 0.0 || since >= 2.5)
            Return
        EndIf
        Utility.Wait(0.5)
        waited += 0.5
    EndWhile
EndFunction

Function WaitForTheirSay(Actor npc, Float most)
    {After they were given something to say: until their reply has begun and ended, at most this long.}
    Float waited = 0.0
    While waited < most && npc != None && npc.Is3DLoaded()
        Float since = IntelEngine.GetSecondsSinceNPCSpoke(npc)
        If IntelEngine.IsActorTalking(npc) || (since >= 0.0 && since <= waited + 0.5)
            WaitForSilence(npc, most - waited)
            Return
        EndIf
        Utility.Wait(0.5)
        waited += 0.5
    EndWhile
EndFunction

Int Function DebugVenture(Actor ally, Int companionMode = 0)
    {Test hook: plans a venture for this former follower and puts them on the road ahead; the id, 0 when none fits.
    companionMode: 0 by chance, 1 a follower type the player never travelled with, 2 another former follower, 3 alone.}
    IntelEngine.QuestDebugForceCompanion(companionMode)
    Int id = IntelEngine.QuestPlanVenture(ally)
    IntelEngine.QuestDebugForceCompanion(0)
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
    ; Let them have their say first: the popup never cuts a line off.
    Utility.Wait(2.0)
    WaitForTheirSay(giver, 30.0)
    If IntelEngine.QuestField(id, "phase") != PHASE_PLANNED || giver.IsDead() || giver.IsInCombat()
        Return
    EndIf
    Bool venture = IntelEngine.QuestField(id, "template") == TPL_VENTURE
    If venture
        RoadVenture = 0
        RoadChasing = false
        ; The hurry is over: they stand with the player now (the story engine's linger), and later walk on with the
        ; walk it gives back; a jog left on top of that would outrank it.
        ActorUtil.RemovePackageOverride(giver, Core().TravelPackage_Jog)
        giver.EvaluatePackage()
        CompanionStops(id)
        If IntelEngine.QuestField(id, "phase") != PHASE_PLANNED
            Return
        EndIf
    EndIf
    String prompt = IntelEngine.QuestText(id, "prompt")
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
        c.StoryEngine.ForgetLingerActor(companion)
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
    RecordTrail()
    WatchRoad()
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
    WaitForSilence(giver, 15.0)
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
