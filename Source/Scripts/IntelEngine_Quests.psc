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
Float PendingTriedAt
; Where they rest when placed on bare ground (made for them, deleted when they go).
ObjectReference RoadMarker
; The venture whose people are out there (one at a time), and where the meeting stands.
Int RoadVenture
Int RoadState
ObjectReference RoadSpot
Bool RoadHere          ; met at the place itself (the lives' greeting at their dungeon)
Float RoadSince        ; real seconds, when the state began
Float RoadNear         ; seconds the player has walked along with them since they set off
Float RoadFar          ; seconds the player has been far from them since they set off
Bool RoadSetOff
Float RoadLastD        ; how far they were on the last look, while coming over
Int RoadStalled        ; looks in a row they got no nearer
Bool RoadJog           ; the package they come over with now (walk or jog, to re-aim)
Bool CompanionPending  ; the companion has been told to speak and has not had their say yet
Bool RoadGreetedAlready ; met at a dungeon: the lives' greeting was their greeting, the meeting does not give another
Float RoadMetAt        ; when they stopped to talk (real time)
Float RoadGreetAt      ; when the ally was last given their greeting
Int RoadGreetTries

Int Property ROAD_RESTING = 1 AutoReadOnly
Int Property ROAD_COMING = 2 AutoReadOnly
Int Property ROAD_TALKING = 3 AutoReadOnly
Int Property ROAD_SETOFF = 4 AutoReadOnly
Int Property ROAD_JOINED = 5 AutoReadOnly
Int Property ROAD_LEAVING = 6 AutoReadOnly
Int Property PLACED_MET = 16 AutoReadOnly
Int Property PLACED_INVITED = 32 AutoReadOnly
Int Property PLACED_ATPLACE = 64 AutoReadOnly
Int Property ENDING_DECLINED = 12 AutoReadOnly
Int Property ENDING_LAPSED = 17 AutoReadOnly

Float Property RECOGNISE_DISTANCE = 2500.0 AutoReadOnly   ; they see the player this far off and come over
Float Property RECOGNISE_ANYWAY = 1000.0 AutoReadOnly     ; this close they notice whatever they are looking at

; Where the player has walked outdoors lately (every 400 units or more, the last 24 spots, one worldspace): the way
; the player is going, so a meeting is placed ahead of them.
Float[] TrailX
Float[] TrailY
Float[] TrailZ
Int TrailHead
Int TrailCount
WorldSpace TrailWorld

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
    RegisterForModEvent("IntelEngine_QuestCompanionSpeaks", "OnCompanionSpeaks")
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
        ; A venture is met by chance, not brought to the player: its people rest ahead, on the way the player goes.
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

; ----------------------------------------------------------------------------------------------- ventures: the meeting
;
; A former follower on an adventure of their own life, met by chance: resting at a spot ahead on the way the player is
; going (a bench, a bedroll, an idle marker, a doorstep), or at the dungeon itself (the lives' greeting). They notice
; the player, come over and talk, and whoever travels with them has their say too. Asking the player along is theirs
; to do in conversation (the InviteAlong action); only then does the player answer in the popup. When the talk is over
; they set off for the place, leading the way; on arrival they follow the player inside.

Bool Function PlaceVenture(Int id)
    {The former follower (and whoever travels with them) ahead of the player, resting at a spot where people stand,
    out of sight. Only outdoors; false when there is no such spot now (tried again as the player moves).}
    Actor ally = IntelEngine.QuestForm(id, "ally") as Actor
    Actor player = Game.GetPlayer()
    IntelEngine_Core c = Core()
    If ally == None || c == None || player.IsInCombat() || RoadVenture > 0
        Return false
    EndIf
    Cell here = player.GetParentCell()
    If here == None || here.IsInterior()
        Return false
    EndIf
    ObjectReference[] spots = IntelEngine.QuestSpotsAhead(TrailDX(), TrailDY())
    Float[] ground
    If spots.Length == 0
        ; The ground is read only when needed, and a moment later (each read stays under half a millisecond).
        Utility.Wait(0.1)
        ground = IntelEngine.QuestGroundAhead(TrailDX(), TrailDY())
        If ground.Length == 0
            Return false
        EndIf
    EndIf
    ; Where they were, to go back to unseen when no spot ahead is out of sight.
    ObjectReference back = ally.PlaceAtMe(Game.GetFormFromFile(0x0000003B, "Skyrim.esm"), 1, false, false)
    ally.SetAlpha(0.0, false)
    c.RemoveAllPackages(ally, false)
    ObjectReference spot = None
    Int i = 0
    While i < spots.Length && spot == None
        If PutUnseen(ally, spots[i], 70.0, 0.0)
            spot = spots[i]
        EndIf
        i += 1
    EndWhile
    ; No bench or bedroll that way out of sight: on the road ahead itself (or the ground, off the road).
    If spot == None && spots.Length > 0
        Utility.Wait(0.1)
        ground = IntelEngine.QuestGroundAhead(TrailDX(), TrailDY())
    EndIf
    i = 0
    While spot == None && i + 2 < ground.Length
        If PutUnseen(ally, player as ObjectReference, ground[i] - player.GetPositionX(), ground[i + 1] - player.GetPositionY(), ground[i + 2] - player.GetPositionZ() + 20.0)
            spot = ally.PlaceAtMe(Game.GetFormFromFile(0x0000003B, "Skyrim.esm"), 1, false, false)
            RoadMarker = spot
        EndIf
        i += 3
    EndWhile
    If spot == None
        If back != None
            ally.MoveTo(back, 0.0, 0.0, 0.0, false)
        EndIf
    EndIf
    ally.SetAlpha(1.0, false)
    If back != None
        back.Delete()
    EndIf
    If spot == None
        c.DebugMsg("Quests: no spot ahead out of sight for venture " + id + " yet")
        Return false
    EndIf
    OnTheRoad(ally, id)
    Rest(ally, spot, c)
    Actor companion = IntelEngine.QuestForm(id, "companion") as Actor
    If companion != None
        If companion.IsDead() || companion.IsInCombat()
            IntelEngine.QuestDropCompanion(id)
        Else
            ; Beside the ally, as unseen as the ally is. They rest at the spot whether or not they have loaded yet: one
            ; fetched from far away was left without orders and walked home to the Rift while the ally named her
            ; (Illia, 2026-11-18).
            companion.SetAlpha(0.0, false)
            c.RemoveAllPackages(companion, false)
            PutUnseen(companion, ally as ObjectReference, 110.0, 60.0)
            OnTheRoad(companion, id)
            Rest(companion, spot, c)
            companion.SetAlpha(1.0, false)
            If companion.GetWorldSpace() != ally.GetWorldSpace() || companion.GetDistance(ally) > 1500.0
                Release(companion, c)
                IntelEngine.QuestDropCompanion(id)
                c.DebugMsg("Quests: " + companion.GetDisplayName() + " could not be put beside " + ally.GetDisplayName() + "; " + ally.GetDisplayName() + " travels alone")
            EndIf
        EndIf
    EndIf
    IntelEngine.QuestVenturePlaced(id)
    RoadVenture = id
    RoadState = ROAD_RESTING
    RoadSpot = spot
    RoadHere = false
    RoadSince = Utility.GetCurrentRealTime()
    IntelEngine.LivingWorldMomentDispatched(ally, "road_encounter")
    c.DebugMsg("Quests: " + ally.GetDisplayName() + " rests ahead of the player on the way to " + IntelEngine.QuestText(id, "place") + " (venture " + id + ")")
    Return true
EndFunction

Bool Function PutUnseen(Actor npc, ObjectReference at, Float dx, Float dy, Float dz = 0.0)
    {Moved there (they are invisible while this runs), onto ground they can walk; true when the player cannot see
    the spot they ended on.}
    npc.MoveTo(at, dx, dy, dz, false)
    Int waited = 0
    ; Someone from far away needs a few seconds to load.
    While !npc.Is3DLoaded() && waited < 30
        Utility.Wait(0.1)
        waited += 1
    EndWhile
    PO3_SKSEFunctions.MoveToNearestNavmeshLocation(npc)
    Return npc.Is3DLoaded() && !Core().PlayerCanSee(npc)
EndFunction

Float Function TrailDX()
    {The way the player has been going lately (east-west), 0 when standing: then the way they face.}
    If TrailCount < 2 || TrailX.Length != 24
        Return 0.0
    EndIf
    Int last = (TrailHead + 23) % 24
    Int span = TrailCount
    If span > 4
        span = 4
    EndIf
    Return TrailX[last] - TrailX[(TrailHead + 24 - span) % 24]
EndFunction

Float Function TrailDY()
    If TrailCount < 2 || TrailY.Length != 24
        Return 0.0
    EndIf
    Int last = (TrailHead + 23) % 24
    Int span = TrailCount
    If span > 4
        span = 4
    EndIf
    Return TrailY[last] - TrailY[(TrailHead + 24 - span) % 24]
EndFunction

Function RecordTrail()
    {Where the player walks outdoors, every 400 units or more; a jump (fast travel, a door) starts over. It gives the
    way the player is going.}
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
    TrailHead = (TrailHead + 1) % 24
    If TrailCount < 24
        TrailCount += 1
    EndIf
EndFunction

; Packages of the meeting. Each change puts on another package than the one they were on: a travel package put back on
; with a new target keeps its old one (Jenassa walked on to White River Watch, 2026-11-18).

Function Rest(Actor npc, ObjectReference spot, IntelEngine_Core c)
    {Resting at the spot: sitting, standing about, as people do on a break from the road.}
    ActorUtil.RemovePackageOverride(npc, c.TravelPackage_Walk)
    PO3_SKSEFunctions.SetLinkedRef(npc, spot, c.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(npc, c.SandboxNearPlayerPackage, c.PRIORITY_SANDBOX, 1)
    npc.EvaluatePackage()
EndFunction

Function ComeOver(Actor npc, IntelEngine_Core c)
    {They noticed the player: they walk over.}
    ActorUtil.RemovePackageOverride(npc, c.SandboxNearPlayerPackage)
    PO3_SKSEFunctions.SetLinkedRef(npc, Game.GetPlayer() as ObjectReference, c.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(npc, c.TravelPackage_Walk, c.PRIORITY_TRAVEL, 1)
    npc.EvaluatePackage()
EndFunction

Function ReAim(Actor npc, IntelEngine_Core c, Bool jog)
    {Come over again, toward where the player is now.}
    ActorUtil.RemovePackageOverride(npc, c.TravelPackage_Walk)
    ActorUtil.RemovePackageOverride(npc, c.TravelPackage_Jog)
    PO3_SKSEFunctions.SetLinkedRef(npc, Game.GetPlayer() as ObjectReference, c.IntelEngine_TravelTarget)
    If jog
        ActorUtil.AddPackageOverride(npc, c.TravelPackage_Jog, c.PRIORITY_TRAVEL, 1)
    Else
        ActorUtil.AddPackageOverride(npc, c.TravelPackage_Walk, c.PRIORITY_TRAVEL, 1)
    EndIf
    npc.EvaluatePackage()
EndFunction

Function Linger(Actor npc, IntelEngine_Core c)
    {Standing with the player while they talk.}
    ActorUtil.RemovePackageOverride(npc, c.TravelPackage_Walk)
    ActorUtil.RemovePackageOverride(npc, c.TravelPackage_Jog)
    PO3_SKSEFunctions.SetLinkedRef(npc, Game.GetPlayer() as ObjectReference, c.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(npc, c.SandboxNearPlayerPackage, c.PRIORITY_SANDBOX, 1)
    npc.EvaluatePackage()
EndFunction

Function SetOff(Actor npc, ObjectReference goal, IntelEngine_Core c)
    {The talk is over: on to the place (leading the way when the player comes).}
    ActorUtil.RemovePackageOverride(npc, c.SandboxNearPlayerPackage)
    If goal != None
        PO3_SKSEFunctions.SetLinkedRef(npc, goal, c.IntelEngine_TravelTarget)
        ActorUtil.AddPackageOverride(npc, c.TravelPackage_Walk, c.PRIORITY_TRAVEL, 1)
    EndIf
    npc.EvaluatePackage()
EndFunction

Function OnTheRoad(Actor npc, Int id)
    {The meeting gives them packages now: Core's sweep of stray packages leaves them alone (it took Jenassa's and
    Vilkas' off on the road before, 2026-11-18). The mark goes with our packages (Release).}
    If npc != None
        StorageUtil.SetIntValue(npc, "Intel_RoadVenture", id)
        StorageUtil.SetFloatValue(npc, "Intel_RoadVentureAt", Utility.GetCurrentGameTime())
    EndIf
EndFunction

Function Release(Actor npc, IntelEngine_Core c)
    {Our packages off: their own life, or their own way home, goes on.}
    If npc == None
        Return
    EndIf
    StorageUtil.UnsetIntValue(npc, "Intel_RoadVenture")
    StorageUtil.UnsetFloatValue(npc, "Intel_RoadVentureAt")
    If c == None
        Return
    EndIf
    ActorUtil.RemovePackageOverride(npc, c.SandboxNearPlayerPackage)
    ActorUtil.RemovePackageOverride(npc, c.TravelPackage_Walk)
    ActorUtil.RemovePackageOverride(npc, c.TravelPackage_Jog)
    PO3_SKSEFunctions.SetLinkedRef(npc, None, c.IntelEngine_TravelTarget)
    npc.EvaluatePackage()
EndFunction

Function LetGo(Actor npc, IntelEngine_Core c)
    {Our packages off, unless a task of their own leads them now: its packages are the same travel packages, and
    taking them off would stop that trip.}
    If npc != None && c.FindSlotByAgent(npc) < 0
        Release(npc, c)
    ElseIf npc != None
        StorageUtil.UnsetIntValue(npc, "Intel_RoadVenture")
        StorageUtil.UnsetFloatValue(npc, "Intel_RoadVentureAt")
    EndIf
EndFunction

Int Function TaskCheck(Int id, Actor ally, Actor companion, IntelEngine_Core c)
    {Before the venture is taken on: 2 when the ally has a task of their own (the venture lapses), 1 when only the
    companion was called away (they drop out of it and the ally goes on alone), 0 when neither.}
    If c.FindSlotByAgent(ally) >= 0
        Return 2
    EndIf
    If companion != None && c.FindSlotByAgent(companion) >= 0
        LetGo(companion, c)
        IntelEngine.QuestDropCompanion(id)
        c.DebugMsg("Quests: " + companion.GetDisplayName() + " was called away; " + ally.GetDisplayName() + " goes on alone")
        Return 1
    EndIf
    Return 0
EndFunction

Bool Function OwnTask(Actor ally, Actor companion, IntelEngine_Core c)
    {A task of their own came of the talk (Jenassa answered "not this time" with IntelEngine's GoToLocation to the
    place, taking Illia, 2026-11-18): it leads them from here, and the meeting lets them go.}
    Return c.FindSlotByAgent(ally) >= 0 || (companion != None && c.FindSlotByAgent(companion) >= 0)
EndFunction

ObjectReference Function Goal(Int id, Actor ally)
    {Where they are going: the place itself, by the reference the quest holds (its boss room; the game paths them
    there through its door). Not by its name: "White River Watch" once resolved to the river by Riverwood.}
    ObjectReference anchor = IntelEngine.QuestForm(id, "anchor") as ObjectReference
    If anchor != None
        Return anchor
    EndIf
    Return IntelEngine.ResolveAnyDestination(ally, IntelEngine.QuestText(id, "place"))
EndFunction

Function ReleaseRoad()
    IntelEngine_Core c = Core()
    If RoadVenture > 0 && c != None
        Actor ally = IntelEngine.QuestForm(RoadVenture, "ally") as Actor
        Actor companion = IntelEngine.QuestForm(RoadVenture, "companion") as Actor
        If Math.LogicalAnd(IntelEngine.QuestField(RoadVenture, "placed"), PLACED_MET) != 0
            ; They talked with the player just now: their own life does not greet the player again.
            IntelEngine.LivingWorldMarkGreeted(ally)
            IntelEngine.LivingWorldMarkGreeted(companion)
        EndIf
        LetGo(ally, c)
        LetGo(companion, c)
    EndIf
    RoadVenture = 0
    RoadState = 0
    If RoadMarker != None
        RoadMarker.Delete()
        RoadMarker = None
    EndIf
EndFunction

Bool Function Answered(Actor ally)
    {They have said their piece since the player turned them down (their answer comes some seconds after it, and
    they say it before they turn to go), or half a minute went by without one.}
    Float since = Utility.GetCurrentRealTime() - RoadSince
    Float a = IntelEngine.GetSecondsSinceNPCSpoke(ally)
    Return (a >= 0.0 && a < since) || since >= 30.0
EndFunction

Bool Function AllyGreeted(Actor ally)
    {The ally has spoken since they stopped to talk with the player.}
    Float a = IntelEngine.GetSecondsSinceNPCSpoke(ally)
    Return a >= 0.0 && a < Utility.GetCurrentRealTime() - RoadMetAt
EndFunction

Bool Function TalkIsOver(Actor ally, Actor companion)
    {Nobody of the three has said anything for a while.}
    Float a = IntelEngine.GetSecondsSinceNPCSpoke(ally)
    If Speaking(ally) || (a >= 0.0 && a < 15.0)
        Return false
    EndIf
    If companion != None
        Float b = IntelEngine.GetSecondsSinceNPCSpoke(companion)
        If Speaking(companion) || (b >= 0.0 && b < 15.0)
            Return false
        EndIf
    EndIf
    Float p = IntelEngine.GetSecondsSincePlayerSpoke()
    Return p < 0.0 || p >= 15.0
EndFunction

Function WatchRoad()
    {The meeting, every two seconds while a venture's people are out there.}
    If RoadVenture <= 0
        Return
    EndIf
    Int id = RoadVenture
    IntelEngine_Core c = Core()
    Actor player = Game.GetPlayer()
    Actor ally = IntelEngine.QuestForm(id, "ally") as Actor
    Actor companion = IntelEngine.QuestForm(id, "companion") as Actor
    Int phase = IntelEngine.QuestField(id, "phase")
    If ally == None || c == None
        RoadVenture = 0
        Return
    EndIf
    Float now = Utility.GetCurrentRealTime()
    Float d = 99999.0
    If ally.Is3DLoaded() && ally.GetParentCell() != None && (ally.GetWorldSpace() == player.GetWorldSpace() || ally.GetParentCell() == player.GetParentCell())
        d = ally.GetDistance(player)
    EndIf

    If RoadState == ROAD_LEAVING
        ; Turned down: on their way when the talk is over, and let go once out of sight.
        If OwnTask(ally, companion, c)
            c.DebugMsg("Quests: " + ally.GetDisplayName() + " goes on with a task of their own")
            ReleaseRoad()
        ElseIf !RoadSetOff && ((Answered(ally) && TalkIsOver(ally, companion)) || d > 1200.0 || now - RoadSince > 180.0)
            RoadSetOff = true
            ObjectReference goal = Goal(id, ally)
            SetOff(ally, goal, c)
            If companion != None
                SetOff(companion, goal, c)
            EndIf
            If goal != None
                c.DebugMsg("Quests: " + ally.GetDisplayName() + " sets off for " + IntelEngine.QuestText(id, "place") + " (goal " + goal.GetFormID() + ", " + (d as Int) + " units from the player)")
            Else
                c.DebugMsg("Quests: " + ally.GetDisplayName() + " found no way to " + IntelEngine.QuestText(id, "place"))
            EndIf
        ElseIf RoadSetOff && (!ally.Is3DLoaded() || d > 6000.0)
            c.DebugMsg("Quests: " + ally.GetDisplayName() + " is out of sight and goes on with their own life")
            ReleaseRoad()
        EndIf
        Return
    EndIf
    If RoadState == ROAD_JOINED
        ; Together: they lead the way, and follow the player once both are there.
        If phase != 1
            ReleaseRoad()
        ElseIf IntelEngine.QuestField(id, "step") >= 1
            RoadVenture = 0
            RoadState = 0
            BeginVenture(id)
        EndIf
        Return
    EndIf
    If phase != PHASE_PLANNED
        ReleaseRoad()
        Return
    EndIf
    If RoadState == ROAD_RESTING || RoadState == ROAD_COMING || RoadState == ROAD_TALKING || RoadState == ROAD_SETOFF
        Int tasks = TaskCheck(id, ally, companion, c)
        If tasks == 2
            ; Given a task of their own (the story, another mod, their own choice in the talk): it comes first.
            c.DebugMsg("Quests: " + ally.GetDisplayName() + " has a task of their own; the venture lapses")
            IntelEngine.QuestEndPlanned(id, ENDING_LAPSED)
            ReleaseRoad()
            Return
        ElseIf tasks == 1
            companion = None
        EndIf
    EndIf

    If RoadState == ROAD_RESTING
        If ally.Is3DLoaded() && !ally.IsInCombat() && !player.IsInCombat() && (d <= RECOGNISE_ANYWAY || (d <= RECOGNISE_DISTANCE && ally.HasLOS(player)))
            ComeOver(ally, c)
            If companion != None && companion.Is3DLoaded()
                ComeOver(companion, c)
            EndIf
            RoadState = ROAD_COMING
            RoadSince = now
            RoadLastD = d
            RoadStalled = 0
            RoadJog = false
            c.DebugMsg("Quests: " + ally.GetDisplayName() + " recognises " + player.GetDisplayName() + " and comes over (" + (d as Int) + " units)")
        EndIf
    ElseIf RoadState == ROAD_COMING
        If d <= 450.0
            Meet(id, ally, companion, c)
        ElseIf d > 5000.0 || now - RoadSince > 90.0
            ; The player went on before they got there: back to their rest.
            Rest(ally, RoadSpot, c)
            If companion != None
                Rest(companion, RoadSpot, c)
            EndIf
            RoadState = ROAD_RESTING
        Else
            ; No nearer for three looks: the walk went where the player stood when it began. Aimed again, with the
            ; other package (the same one put back on keeps its old target).
            If d > RoadLastD - 50.0
                RoadStalled += 1
            Else
                RoadStalled = 0
            EndIf
            RoadLastD = d
            If RoadStalled >= 3
                RoadStalled = 0
                RoadJog = !RoadJog
                ReAim(ally, c, RoadJog)
                If companion != None && companion.Is3DLoaded()
                    ReAim(companion, c, RoadJog)
                EndIf
            EndIf
        EndIf
    ElseIf RoadState == ROAD_TALKING
        If c.IsFollowingPlayer(ally) || (companion != None && c.IsFollowingPlayer(companion))
            ; Another mod's follow, chosen in the conversation: they agreed to have the player along. Joined.
            TakePlayerAlong(ally)
        ElseIf !AllyGreeted(ally) && d <= 1200.0 && now - RoadMetAt < 120.0
            ; Their greeting has not been said yet. Another conversation can hold the scene (the GameMaster had Olava
            ; talking, and Jenassa's greeting waited behind her until Ugor's line pushed it out, 2026-11-18): it is
            ; given again while they wait, and nobody sets off before it is said.
            If now - RoadGreetAt >= 20.0 && RoadGreetTries < 4 && !Speaking(ally) \
                && (companion == None || !Speaking(companion))
                RoadGreetTries += 1
                RoadGreetAt = now
                c.DebugMsg("Quests: " + ally.GetDisplayName() + " has not had their say yet; the greeting is given again (" + RoadGreetTries + ")")
                c.SendTaskNarration(ally, IntelEngine.QuestText(id, "roadnarration"), player)
            EndIf
        ElseIf TalkIsOver(ally, companion) && now - RoadSince >= 25.0 && d <= 800.0 && Math.LogicalAnd(IntelEngine.QuestField(id, "placed"), PLACED_INVITED) == 0
            ; The talk is over and the player is still standing with them: they ask, as anyone would, rather than
            ; walk off. At Embershard the player said yes in words while the model chose an action that does not
            ; exist; Jenassa walked into the mine alone and the venture lapsed (2026-11-18).
            InviteAlong(ally)
        ElseIf TalkIsOver(ally, companion) && now - RoadSince >= 25.0 || d > 1200.0 || now - RoadSince > 180.0
            ObjectReference goal = Goal(id, ally)
            SetOff(ally, goal, c)
            If companion != None
                SetOff(companion, goal, c)
            EndIf
            If goal != None
                c.DebugMsg("Quests: " + ally.GetDisplayName() + " sets off for " + IntelEngine.QuestText(id, "place") + " (goal " + goal.GetFormID() + ")")
            Else
                c.DebugMsg("Quests: " + ally.GetDisplayName() + " found no way to " + IntelEngine.QuestText(id, "place"))
            EndIf
            RoadState = ROAD_SETOFF
            RoadSince = now
            RoadNear = 0.0
            RoadFar = 0.0
        EndIf
    ElseIf RoadState == ROAD_SETOFF
        If d <= 1500.0
            RoadNear += WATCH_SECONDS
        EndIf
        If d > 5000.0
            RoadFar += WATCH_SECONDS
        Else
            RoadFar = 0.0
        EndIf
        If c.IsFollowingPlayer(ally) || (companion != None && c.IsFollowingPlayer(companion))
            TakePlayerAlong(ally)
        ElseIf RoadNear >= 40.0 && Math.LogicalAnd(IntelEngine.QuestField(id, "placed"), PLACED_INVITED) == 0
            ; The player walks along with them: they turn and ask, as anyone would.
            c.SendTaskNarration(ally, "turns to " + player.GetDisplayName() + ", who has been walking along, and asks whether " + player.GetDisplayName() + " means to come all the way to " + IntelEngine.QuestText(id, "place"), player)
            InviteAlong(ally)
        ElseIf RoadFar >= 60.0
            ; They went their way and the player theirs: nothing came of it (nobody asked, nobody refused). A minute
            ; out of sight or far away, not the moment they step through a door: at a dungeon they go in, and a
            ; player who follows them inside finds them there.
            IntelEngine.QuestEndPlanned(id, ENDING_LAPSED)
            ReleaseRoad()
        EndIf
    EndIf
EndFunction

Function Meet(Int id, Actor ally, Actor companion, IntelEngine_Core c)
    {Face to face: they stop and talk (the ally first, then whoever travels with them).}
    Actor player = Game.GetPlayer()
    Linger(ally, c)
    If companion != None && companion.Is3DLoaded()
        Linger(companion, c)
    EndIf
    IntelEngine.QuestSetPlaced(id, PLACED_MET)
    RoadState = ROAD_TALKING
    RoadSince = Utility.GetCurrentRealTime()
    RoadGreetAt = RoadSince
    RoadGreetTries = 1
    ally.SetLookAt(player)
    If RoadGreetedAlready
        ; Met at a dungeon: the lives' greeting started the talk already (RoadMetAt is when it came).
        RoadGreetedAlready = false
    Else
        RoadMetAt = RoadSince
        c.SendTaskNarration(ally, IntelEngine.QuestText(id, "roadnarration"), player)
    EndIf
    If companion != None
        CompanionPending = true
        Int handle = ModEvent.Create("IntelEngine_QuestCompanionSpeaks")
        If handle
            ModEvent.PushInt(handle, id)
            ModEvent.Send(handle)
        EndIf
    EndIf
EndFunction

Event OnCompanionSpeaks(Int id)
    {The companion has their say once the ally has finished (one speaker at a time).}
    Actor companion = IntelEngine.QuestForm(id, "companion") as Actor
    Actor ally = IntelEngine.QuestForm(id, "ally") as Actor
    Actor player = Game.GetPlayer()
    If companion == None || companion.IsDead() || !companion.Is3DLoaded()
        CompanionPending = false
        Return
    EndIf
    ; After the ally, never before: their greeting can wait behind another conversation, and a companion's line
    ; then pushed it out (Ugor spoke first and Jenassa never did, 2026-11-18).
    Float waited = 0.0
    While !AllyGreeted(ally) && waited < 120.0 && RoadVenture == id && RoadState == ROAD_TALKING
        Utility.Wait(1.0)
        waited += 1.0
    EndWhile
    If !AllyGreeted(ally) || RoadVenture != id || RoadState != ROAD_TALKING
        CompanionPending = false
        Return
    EndIf
    WaitForSilence(ally, 40.0, 4.0)
    Utility.Wait(1.5)
    companion.SetLookAt(player)
    Core().SendTaskNarration(companion, CompanionNarration(id, companion), player)
    WaitForTheirSay(companion, 20.0, 4.0)
    CompanionPending = false
EndEvent

Function MeetHere(Actor npc)
    {From the lives' greeting: a former follower on an adventure of their own life at a dungeon noticed the player.
    The venture is theirs to offer in conversation, as on the road.}
    If npc == None || RoadVenture > 0 || !Enabled()
        Return
    EndIf
    Int id = IntelEngine.QuestPlanVentureHere(npc)
    If id <= 0
        Return
    EndIf
    IntelEngine.QuestVenturePlaced(id)
    IntelEngine.QuestSetPlaced(id, PLACED_ATPLACE)
    OnTheRoad(npc, id)
    RoadVenture = id
    RoadHere = true
    RoadSpot = npc as ObjectReference
    ; They noticed the player from as far as 1200 units: they come over first, as on the road, and the lives'
    ; greeting counts as theirs. Talking at that distance, the meeting took the player for gone and Jenassa walked
    ; into the mine after 18 seconds (2026-11-18).
    IntelEngine_Core c = Core()
    ComeOver(npc, c)
    Actor companion = IntelEngine.QuestForm(id, "companion") as Actor
    If companion != None && !companion.IsDead() && companion.Is3DLoaded()
        OnTheRoad(companion, id)
        ComeOver(companion, c)
    EndIf
    RoadState = ROAD_COMING
    RoadSince = Utility.GetCurrentRealTime()
    RoadMetAt = RoadSince
    RoadLastD = npc.GetDistance(Game.GetPlayer())
    RoadStalled = 0
    RoadJog = false
    RoadGreetedAlready = true
    c.DebugMsg("Quests: " + npc.GetDisplayName() + " met at " + IntelEngine.QuestText(id, "place") + " (venture " + id + ")")
EndFunction

Int Function Asking(Actor akNPC)
    {The venture this person may take the player along on now (met, not asked yet), marked as asked; 0 = none.}
    If akNPC == None
        Return 0
    EndIf
    Int id = IntelEngine.QuestVentureOf(akNPC)
    If id <= 0 || IntelEngine.QuestField(id, "phase") != PHASE_PLANNED
        Return 0
    EndIf
    If Math.LogicalAnd(IntelEngine.QuestField(id, "placed"), PLACED_INVITED) != 0
        Return 0
    EndIf
    IntelEngine.QuestSetPlaced(id, PLACED_INVITED)
    Return id
EndFunction

Function InviteAlong(Actor akNPC)
    {The InviteAlong action: they ask the player along. The player answers in the popup, once they have finished.}
    Int id = Asking(akNPC)
    If id <= 0
        Return
    EndIf
    Actor player = Game.GetPlayer()
    ; The action comes with the reply's text, before a word of it is spoken: first the whole reply (it begins, then
    ; four quiet seconds, as a reply comes in several lines), then the companion's say if it is still to come. The
    ; popup came while Jenassa was still asking (the user, 2026-11-18).
    WaitForTheirSay(akNPC, 30.0, 4.0)
    ; Then the other of the two (the companion may be the one who asked), only while they still have something to
    ; say: speaking now, a line on its way, or their turn just given. The popup came 18 s after Vilkas had asked and
    ; finished, waiting for a turn he had already had (2026-11-18).
    Actor ally = IntelEngine.QuestForm(id, "ally") as Actor
    Actor other = IntelEngine.QuestForm(id, "companion") as Actor
    If other == akNPC
        other = ally
    EndIf
    If other != None && other.Is3DLoaded()
        If Speaking(other)
            WaitForQuiet(other, 30.0, 4.0)
        ElseIf CompanionPending && other != ally
            WaitForTheirSay(other, 6.0, 4.0)
        EndIf
    EndIf
    String choice = Core().ShowChoice(akNPC.GetDisplayName(), "Come along", IntelEngine.QuestText(id, "prompt"), "I'll come along", "Not this time")
    If IntelEngine.QuestField(id, "phase") != PHASE_PLANNED
        Return
    EndIf
    If choice == "I'll come along"
        JoinNow(id, akNPC, "hears that " + player.GetDisplayName() + " will come along to " + IntelEngine.QuestText(id, "place") + ", and now travels with " + player.GetDisplayName() + " as a companion")
    Else
        IntelEngine.QuestEndPlanned(id, ENDING_DECLINED)
        Core().SendTaskNarration(akNPC, "hears that " + player.GetDisplayName() + " will not come along", player)
        RoadVenture = id
        RoadState = ROAD_LEAVING
        RoadSetOff = false
        RoadSince = Utility.GetCurrentRealTime()
    EndIf
EndFunction

Function TakePlayerAlong(Actor akNPC)
    {The TakePlayerAlong action: the player asked to come along and they agreed in their own reply. Nothing more to
    ask: the player is with them now (the user, 2026-11-18: "if I ask to join, they just join").}
    Int id = Asking(akNPC)
    If id > 0
        JoinNow(id, akNPC, "")
    EndIf
EndFunction

Function JoinNow(Int id, Actor akNPC, String narration)
    {Together now: the journal quest opens, and they follow the player to the place as companions, at the player's
    pace (the user, 2026-11-18: leading the way had the player trailing behind their slow walk, and Jenassa stuck by
    a river).}
    If !IntelEngine.QuestAccept(id)
        Return
    EndIf
    IntelEngine_Core c = Core()
    If narration != ""
        c.SendTaskNarration(akNPC, narration, Game.GetPlayer())
    EndIf
    Open(id)
    Actor ally = IntelEngine.QuestForm(id, "ally") as Actor
    Actor companion = IntelEngine.QuestForm(id, "companion") as Actor
    RoadVenture = id
    RoadState = ROAD_JOINED
    JoinPlayer(id, ally, c)
    JoinPlayer(id, companion, c)
EndFunction

Function JoinPlayer(Int id, Actor npc, IntelEngine_Core c)
    {One of them follows the player, through the follower system the player uses (SeverActions when installed,
    else SkyrimNet's follow; IntelEngine's own follow package when neither answers). Someone already following
    the player (another mod's follow, chosen in the talk) stays as they are, and stays when the venture ends.}
    If npc == None || npc.IsDead()
        Return
    EndIf
    Release(npc, c)
    If c.IsFollowingPlayer(npc)
        Return
    EndIf
    String how = IntelEngine.QuestFollower(npc, true)
    If how == ""
        IntelEngine_Threads t = Threads()
        If t != None
            t.Follow(npc, true)
        EndIf
        how = "IntelEngine"
    EndIf
    StorageUtil.SetIntValue(npc, "Intel_VentureFollower", id)
    StorageUtil.SetStringValue(npc, "Intel_VentureFollowerHow", how)
    c.DebugMsg("Quests: " + npc.GetDisplayName() + " follows the player for venture " + id + " (" + how + ")")
EndFunction

Function LeavePlayer(Int id, Actor npc)
    {The venture is over: whoever it made a follower goes their own way again, through the same system.}
    If npc == None || StorageUtil.GetIntValue(npc, "Intel_VentureFollower", 0) != id
        Return
    EndIf
    String how = StorageUtil.GetStringValue(npc, "Intel_VentureFollowerHow", "")
    StorageUtil.UnsetIntValue(npc, "Intel_VentureFollower")
    StorageUtil.UnsetStringValue(npc, "Intel_VentureFollowerHow")
    IntelEngine_Core c = Core()
    If how == "IntelEngine"
        IntelEngine_Threads t = Threads()
        If t != None
            t.Follow(npc, false)
        EndIf
    ElseIf !npc.IsDead()
        IntelEngine.QuestFollower(npc, false)
    EndIf
    IntelEngine.LivingWorldMarkGreeted(npc)
    WalkOn(npc, c)
    c.DebugMsg("Quests: " + npc.GetDisplayName() + " goes their own way after venture " + id)
EndFunction

Function WalkOn(Actor npc, IntelEngine_Core c)
    {Dismissed in sight of the player: they walk home at an ordinary pace (the user, 2026-11-18: walking normally,
    not running, which a far-off home sandbox can make them do). Core's walk-home bookkeeping takes the walk off again
    once they are home, out of sight, followed again or given a task.}
    If npc == None || npc.IsDead() || !npc.Is3DLoaded() || c == None
        Return
    EndIf
    ; The dismissal is carried out by its own system a moment later: until then they still count as following.
    Int waited = 0
    While c.IsFollowingPlayer(npc) && waited < 10
        Utility.Wait(0.5)
        waited += 1
    EndWhile
    If c.IsFollowingPlayer(npc) || c.FindSlotByAgent(npc) >= 0
        c.DebugMsg("Quests: " + npc.GetDisplayName() + " is not walked home: still following (" + c.IsFollowingPlayer(npc) + ") or on a task")
        Return
    EndIf
    ObjectReference home = IntelEngine.ResolveAnyDestination(npc, "home")
    If home == None
        home = IntelEngine.GetEditorLocationRef(npc)
    EndIf
    If home == None
        c.DebugMsg("Quests: " + npc.GetDisplayName() + " has no home to walk to")
        Return
    EndIf
    ActorUtil.RemovePackageOverride(npc, c.TravelPackage_Jog)
    ActorUtil.RemovePackageOverride(npc, c.TravelPackage_Run)
    PO3_SKSEFunctions.SetLinkedRef(npc, home, c.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(npc, c.TravelPackage_Walk, c.PRIORITY_TRAVEL, 1)
    c.TrackWalkHome(npc)
    npc.EvaluatePackage()
    c.DebugMsg("Quests: " + npc.GetDisplayName() + " walks home to " + home.GetFormID() + " (" + (npc.GetDistance(home) as Int) + " units)")
EndFunction

String Function CompanionNarration(Int id, Actor companion)
    {What drives the companion to speak when the two stop: an old friend glad to see the player, or someone who has
    never met them and travels with someone who has.}
    If IntelEngine.NPCKnowsPlayer(companion)
        Return IntelEngine.QuestText(id, "companionnarration")
    EndIf
    Return IntelEngine.QuestText(id, "companionstranger")
EndFunction

Function WaitForSilence(Actor npc, Float most, Float quiet = 2.5)
    {Until they have said everything: quiet for this long (two and a half seconds unless told). A reply comes in
    several lines and between two of them nobody is talking, so "not talking now" let a popup cut Jenassa off and
    Lob never had his say (2026-11-18). At most this long.}
    Float waited = 0.0
    While waited < most && npc != None && npc.Is3DLoaded()
        Float since = IntelEngine.GetSecondsSinceNPCSpoke(npc)
        If !Speaking(npc) && (since < 0.0 || since >= quiet)
            Return
        EndIf
        Utility.Wait(0.5)
        waited += 0.5
    EndWhile
EndFunction

Function WaitForTheirSay(Actor npc, Float most, Float quiet = 2.5)
    {After they were given something to say: until their reply has begun (within this long) and ended. Ended means
    not talking for the whole quiet time, as seen here: a reply often opens with a narrated gesture ("*Ugor eyes the
    iron armor*"), then nothing for two seconds while the first spoken line is made, and the popup came in that gap
    and cut Ugor off (2026-11-18).}
    Float waited = 0.0
    While waited < most && npc != None && npc.Is3DLoaded()
        Float since = IntelEngine.GetSecondsSinceNPCSpoke(npc)
        If Speaking(npc) || (since >= 0.0 && since <= waited + 0.5)
            ; Begun: as long as it takes to end (a reply of several lines runs half a minute), never forever.
            WaitForQuiet(npc, 45.0, quiet)
            Return
        EndIf
        Utility.Wait(0.5)
        waited += 0.5
    EndWhile
EndFunction

Bool Function Speaking(Actor npc)
    {A line of theirs is being said or is on its way: SkyrimNet's own account (queued, being voiced, audible). Not the
    engine's lip-sync test: it missed lines SkyrimNet plays through its own sound player (the popup came in the middle
    of Ugor's first line) and counted the game's own idle chatter (Jenassa's hireling lines kept the popup waiting
    twelve seconds), 2026-11-18.}
    Return IntelEngine.IsNPCSpeechPending(npc)
EndFunction

Function WaitForQuiet(Actor npc, Float most, Float quiet)
    {Until they have not been talking for this long, counted while watching (not from when they last spoke, which a
    narrated gesture does not set). At most this long.}
    Float waited = 0.0
    Float still = 0.0
    While waited < most && still < quiet && npc != None && npc.Is3DLoaded()
        Float since = IntelEngine.GetSecondsSinceNPCSpoke(npc)
        If Speaking(npc) || (since >= 0.0 && since < 0.5)
            still = 0.0
        Else
            still += 0.5
        EndIf
        Utility.Wait(0.5)
        waited += 0.5
    EndWhile
EndFunction

; Test help: the player goes somewhere by the game's own pathfinding, as an NPC would (along roads, around rocks and
; trees), so a test sees what a player on the road sees instead of being teleported into a rock face (the user,
; 2026-11-19). Never used in play.

ObjectReference DebugWalkGoal
ObjectReference DebugWalkMark
Float DebugWalkSpeed
Int DebugWalkTurn

Function DebugWalkTo(ObjectReference to, Bool run = true)
    {The player walks (or jogs) to this reference; DebugWalkStop gives the controls back before they arrive.}
    If to == None
        Return
    EndIf
    DebugWalkGoal = to
    DebugWalkSpeed = 0.5
    If run
        DebugWalkSpeed = 1.0
    EndIf
    ; On its own thread: the walk takes as long as the way is.
    RegisterForModEvent("IntelEngine_DebugWalk", "OnDebugWalk")
    SendModEvent("IntelEngine_DebugWalk")
EndFunction

Function DebugWalkToXY(Float x, Float y, Bool run = true)
    {To a point of the worldspace the player is in, within the loaded ground (farther off: give a reference).}
    Actor player = Game.GetPlayer()
    If DebugWalkMark == None
        DebugWalkMark = player.PlaceAtMe(Game.GetFormFromFile(0x0000003B, "Skyrim.esm"), 1, true, false)
    EndIf
    DebugWalkMark.MoveTo(player, x - player.GetPositionX(), y - player.GetPositionY(), 0.0)
    PO3_SKSEFunctions.MoveToNearestNavmeshLocation(DebugWalkMark)
    DebugWalkTo(DebugWalkMark, run)
EndFunction

Event OnDebugWalk(String eventName, String strArg, Float numArg, Form sender)
    Actor player = Game.GetPlayer()
    DebugWalkTurn += 1
    Int mine = DebugWalkTurn
    Game.SetPlayerAIDriven(true)
    ; One call of the game's pathing ends after a couple of minutes on a long way: on again from where it stopped,
    ; until the goal is near, nothing more is gained, or DebugWalkStop.
    Bool going = true
    While going && DebugWalkTurn == mine
        Float x0 = player.GetPositionX()
        Float y0 = player.GetPositionY()
        player.PathToReference(DebugWalkGoal, DebugWalkSpeed)
        Float dx = player.GetPositionX() - x0
        Float dy = player.GetPositionY() - y0
        Bool near = DebugWalkGoal.Is3DLoaded() && player.GetDistance(DebugWalkGoal) < 300.0
        going = !near && Math.Sqrt(dx * dx + dy * dy) > 200.0
    EndWhile
    If DebugWalkTurn == mine
        Game.SetPlayerAIDriven(false)
        If DebugWalkGoal.Is3DLoaded()
            Core().DebugMsg("Quests: the test walk ended " + (player.GetDistance(DebugWalkGoal) as Int) + " units from its goal")
        Else
            Core().DebugMsg("Quests: the test walk ended; its goal is not in the loaded ground")
        EndIf
    EndIf
EndEvent

Function DebugWalkStop()
    DebugWalkTurn += 1
    Game.SetPlayerAIDriven(false)
EndFunction

Int Function DebugVenture(Actor ally, Int companionMode = 0)
    {Test hook: plans a venture for this former follower and puts them ahead of the player; the id, 0 when none fits.
    companionMode: 0 by chance, 1 a follower type the player never travelled with, 2 another former follower, 3 alone.}
    IntelEngine.QuestDebugForceCompanion(companionMode)
    Int id = IntelEngine.QuestPlanVenture(ally)
    IntelEngine.QuestDebugForceCompanion(0)
    If id > 0 && !PlaceVenture(id)
        PendingVenture = id
    EndIf
    Return id
EndFunction

Function DebugDismiss()
    {Test hook: the open venture's people are let go as at its end (the quest itself stays open; reload after).}
    Int[] ids = IntelEngine.QuestOpenIds()
    Int i = 0
    While i < ids.Length
        If IntelEngine.QuestField(ids[i], "template") == TPL_VENTURE
            EndVenture(ids[i])
        EndIf
        i += 1
    EndWhile
EndFunction

Function DebugStopCasualFollow(Actor npc)
    {Test hook: ends a SeverActions casual follow (the one the test save carries on Olava the Feeble).}
    Core().DebugMsg("Quests: casual follow of " + npc.GetDisplayName() + " ended: " + IntelEngine.StopCasualFollow(npc))
EndFunction

Function DebugAdventure(Actor npc)
    {Test hook: the former follower's next life step is an adventure at the nearest dungeon out of the player's sight.}
    Core().DebugMsg("Quests: test: " + npc.GetDisplayName() + " sent adventuring at '" + IntelEngine.LivingWorldDebugAdventure(npc) + "'")
EndFunction

Function DebugMeetHere(Actor ally)
    {Test hook: as if the lives' greeting at their dungeon had just happened.}
    MeetHere(ally)
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
    If IntelEngine.QuestField(id, "template") == TPL_VENTURE
        Return
    EndIf
    String prompt = IntelEngine.QuestText(id, "prompt")
    String choice = Core().ShowChoice(giver.GetDisplayName(), "Quest offer", prompt, "I'll do it", "Not now")
    If IntelEngine.QuestField(id, "phase") != PHASE_PLANNED
        Return
    EndIf
    If choice == "I'll do it" && IntelEngine.QuestAccept(id)
        Core().SendTaskNarration(giver, "was told that " + player.GetDisplayName() + " will do it", player)
        Open(id)
    Else
        IntelEngine.QuestDecline(id)
        Core().SendTaskNarration(giver, "was told that " + player.GetDisplayName() + " will not do it", player)
    EndIf
EndEvent

IntelEngine_Threads Function Threads()
    Return Quest.GetQuest("IntelEngine_Threads") as IntelEngine_Threads
EndFunction

Function BeginVenture(Int id)
    {At the place together: they keep following the player inside until it ends. Anyone not following by now (an
    older save's venture, whose people led the way) is made a follower here.}
    IntelEngine_Core c = Core()
    Actor ally = IntelEngine.QuestForm(id, "ally") as Actor
    Actor companion = IntelEngine.QuestForm(id, "companion") as Actor
    If ally != None && StorageUtil.GetIntValue(ally, "Intel_VentureFollower", 0) != id
        JoinPlayer(id, ally, c)
    EndIf
    If companion != None && StorageUtil.GetIntValue(companion, "Intel_VentureFollower", 0) != id
        JoinPlayer(id, companion, c)
    EndIf
EndFunction

Function EndVenture(Int id)
    Actor ally = IntelEngine.QuestForm(id, "ally") as Actor
    Actor companion = IntelEngine.QuestForm(id, "companion") as Actor
    Release(ally, Core())
    Release(companion, Core())
    LeavePlayer(id, ally)
    LeavePlayer(id, companion)
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
        ObjectReference holder = NameHolders[slot]
        ; Only a hidden holder: a stale handle may name something else by now (the game reuses deleted references' ids).
        If holder.IsDisabled() && (holder as Actor) == None
            holder.Delete()
        EndIf
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
    If PendingVenture > 0 && Utility.GetCurrentRealTime() - PendingTriedAt >= 20.0
        PendingTriedAt = Utility.GetCurrentRealTime()
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
    Else
        KeepMarker(id, jq)
        If IntelEngine.QuestMayHandOver(id)
            OfferHandOver(id, jq)
        EndIf
    EndIf
EndFunction

Function KeepMarker(Int id, Quest jq)
    {The marker stays on what the step is about, asked again on every look: what it stood on may be gone by now (a
    body cleared away, the foe not in the game yet when the step was shown), and a marker on nothing reads as a
    broken quest.}
    If jq == None || IntelEngine.QuestField(id, "objective") < 0
        Return
    EndIf
    ReferenceAlias a = jq.GetAlias(ALIAS_MARKER) as ReferenceAlias
    ObjectReference now = IntelEngine.QuestForm(id, "marker") as ObjectReference
    If a != None && now != None && a.GetReference() != now
        ShowStep(id, jq)
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
