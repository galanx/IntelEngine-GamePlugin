Scriptname IntelEngine_Lives extends Quest
{IntelEngine 4.0: the lives of followers the player left behind. The record and every choice are in the DLL
(LivingWorld.h, LivingWorldLives.cpp); this script does only what Papyrus must: move someone while nobody can see,
put the package of their own life on, take it off again, and let them notice the player when they meet.
At the Classic and Rumors levels of "How alive the world is" no life begins, and the ones under way end here.}

; The package of a former follower's own life (IntelEngine.esp, made by esp/EspBuilder): a sandbox near where they
; are, which holds only while they are not the player's teammate.
Package Property LifeSandbox Auto

Float Property TICK_SECONDS = 10.0 AutoReadOnly
; Below every package of a task (sandbox 90, travel 100), so the player's errands always win.
Int Property PRIORITY_LIFE = 40 AutoReadOnly

Int Property ORDER_MOVE = 1 AutoReadOnly
Int Property ORDER_HOME = 2 AutoReadOnly
Int Property ORDER_RELEASE = 3 AutoReadOnly
Int Property ORDER_GREET = 4 AutoReadOnly

Float lastTick = 0.0

Function Begin()
    {On every load (Core.Maintenance) and at a new game.}
    If !IsRunning()
        Start()
    EndIf
    lastTick = 0.0
    RegisterForSingleUpdate(5.0)
EndFunction

Event OnInit()
    RegisterForSingleUpdate(5.0)
EndEvent

Event OnUpdate()
    Float now = Utility.GetCurrentRealTime()
    If lastTick <= 0.0 || now - lastTick >= TICK_SECONDS - 1.0 || now < lastTick
        lastTick = now
        Tick()
    EndIf
    RegisterForSingleUpdate(TICK_SECONDS)
EndEvent

Function Tick()
    IntelEngine.LivingWorldTrack()
    KeepInMemory()
    ; At most a few changes a tick; the DLL plans the next one when the last is done.
    Int done = 0
    Actor npc = IntelEngine.LivingWorldTakeOrder()
    While npc != None && done < 3
        CarryOut(npc)
        done += 1
        IntelEngine.LivingWorldTrack()
        npc = IntelEngine.LivingWorldTakeOrder()
    EndWhile
EndFunction

Function KeepInMemory()
    {Former and present followers whose life the DLL keeps a record of are held in this quest's aliases (LifeKeep00
    and on, IntelEngine.esp by esp/EspBuilder): a hireling's reference is not persistent, and once one walked home into
    a cell that was not loaded the game let go of them; their record froze at "near the player" and their own life
    never began (Jenassa, 2026-11-17). A filled alias keeps a reference in memory. Freed when the record lets go.}
    Int count = GetNumAliases()
    If count <= 0
        Return
    EndIf
    Actor[] keep = IntelEngine.LivingWorldKeepers(count)
    Int i = 0
    While i < count
        ReferenceAlias slot = GetNthAlias(i) as ReferenceAlias
        If slot != None
            Actor held = slot.GetActorReference()
            If held != None && (held.IsDead() || keep.Find(held) < 0)
                slot.Clear()
            EndIf
        EndIf
        i += 1
    EndWhile
    Int k = 0
    While k < keep.Length
        Actor npc = keep[k]
        If npc != None && !IsHeld(npc, count)
            ReferenceAlias free = FreeAlias(count)
            If free != None
                free.ForceRefTo(npc)
            EndIf
        EndIf
        k += 1
    EndWhile
EndFunction

Bool Function IsHeld(Actor npc, Int count)
    Int i = 0
    While i < count
        ReferenceAlias slot = GetNthAlias(i) as ReferenceAlias
        If slot != None && slot.GetActorReference() == npc
            Return true
        EndIf
        i += 1
    EndWhile
    Return false
EndFunction

ReferenceAlias Function FreeAlias(Int count)
    Int i = 0
    While i < count
        ReferenceAlias slot = GetNthAlias(i) as ReferenceAlias
        If slot != None && slot.GetReference() == None
            Return slot
        EndIf
        i += 1
    EndWhile
    Return None
EndFunction

Function CarryOut(Actor npc)
    Int kind = IntelEngine.LivingWorldOrderKind()
    If kind == ORDER_RELEASE || kind == ORDER_HOME
        ; Back with the player, off on one of their errands, taken up by a story, or simply home for a while:
        ; the package of their own life comes off and their own packages (or the follower framework's) run again.
        TakeOff(npc)
        IntelEngine.LivingWorldOrderDone(true)
        Return
    EndIf
    If kind == ORDER_GREET
        Greet(npc)
        Return
    EndIf
    If kind != ORDER_MOVE
        IntelEngine.LivingWorldOrderDone(false)
        Return
    EndIf

    ObjectReference target = IntelEngine.LivingWorldOrderTarget()
    Actor companion = IntelEngine.LivingWorldOrderCompanion()
    ; Never in sight: nobody may vanish or appear where the player could see it. The DLL checked; the world may
    ; have moved on since, so look again.
    If target == None || npc.IsDead() || npc.Is3DLoaded() || target.Is3DLoaded()
        IntelEngine.LivingWorldOrderDone(false)
        Return
    EndIf
    If companion != None && (companion.IsDead() || companion.Is3DLoaded())
        IntelEngine.LivingWorldOrderDone(false)
        Return
    EndIf
    Bool protect = IntelEngine.LivingWorldOrderProtect()
    Float dx = IntelEngine.LivingWorldOrderOffset(0)
    Float dy = IntelEngine.LivingWorldOrderOffset(1)
    Float dz = IntelEngine.LivingWorldOrderOffset(2)
    PutOn(npc, target, dx, dy, dz, protect)
    If companion != None
        PutOn(companion, target, dx + 80.0, dy + 40.0, dz, protect)
    EndIf
    IntelEngine.LivingWorldOrderDone(true)
EndFunction

Function PutOn(Actor npc, ObjectReference target, Float dx, Float dy, Float dz, Bool protect)
    ; The package first, so they never stand at the new place with their old orders. No EvaluatePackage while
    ; they are not loaded: the engine picks the package up when their cell loads.
    If LifeSandbox
        ActorUtil.AddPackageOverride(npc, LifeSandbox, PRIORITY_LIFE, 1)
    EndIf
    npc.MoveTo(target, dx, dy, dz, false)
    ActorBase base = npc.GetActorBase()
    If protect
        ; Out at a dungeon they could meet anything: only the player could kill them while they are away.
        If base && !base.IsEssential() && !base.IsProtected() && StorageUtil.GetIntValue(npc, "Intel_LifeProtected") != 1
            base.SetProtected(true)
            StorageUtil.SetIntValue(npc, "Intel_LifeProtected", 1)
        EndIf
    Else
        Unprotect(npc)
    EndIf
EndFunction

Function TakeOff(Actor npc)
    If LifeSandbox
        ActorUtil.RemovePackageOverride(npc, LifeSandbox)
    EndIf
    Unprotect(npc)
    If npc.Is3DLoaded()
        npc.EvaluatePackage()
    EndIf
EndFunction

Function Unprotect(Actor npc)
    If StorageUtil.GetIntValue(npc, "Intel_LifeProtected") == 1
        ActorBase base = npc.GetActorBase()
        If base
            base.SetProtected(false)
        EndIf
        StorageUtil.UnsetIntValue(npc, "Intel_LifeProtected")
    EndIf
EndFunction

Function Greet(Actor npc)
    {The player came upon someone living their own life: they notice, and SkyrimNet has them speak (their own
    life is in their prompt, so what they say fits it).}
    Actor player = Game.GetPlayer()
    If npc.IsDead() || !npc.Is3DLoaded() || npc.IsInCombat() || player.IsInCombat() || !npc.HasLOS(player)
        IntelEngine.LivingWorldOrderDone(false)
        Return
    EndIf
    String narration = IntelEngine.LivingWorldOrderNarration()
    If narration != ""
        SkyrimNetApi.DirectNarration(narration, npc, player)
    EndIf
    IntelEngine.LivingWorldOrderDone(true)
EndFunction
