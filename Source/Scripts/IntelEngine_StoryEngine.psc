Scriptname IntelEngine_StoryEngine extends Quest

; =============================================================================
; STORY ENGINE V2.0 (LLM-AS-DUNGEON-MASTER)
;
; Autonomous NPC story system. A single DM prompt receives a pool of candidates
; with world context and decides both WHO acts and WHAT type of story fits.
;
; Story types (decided by the DM, not random rolls):
; - seek_player: NPC seeks out the player with compelling reason (includes long-absence visits)
; - informant: NPC relays gossip about another NPC to the player
; - npc_interaction: Two NPCs interact (off-screen or visible if near player)
; - npc_gossip: NPC shares a rumor with another NPC
; - road_encounter: NPC traveling on the road, approaches player if nearby
; - ambush: Hostile NPC stalks the player (warriors/rogues only), sneak ? combat
; - stalker: Romantic/jealous NPC secretly follows player, sneak ? caught confrontation
; - message: NPC delivers a verbal message (courier system, optional meeting invite)
; - quest: NPC requests help clearing enemies (courier or guide delivery)
; =============================================================================

; === Properties ===
IntelEngine_Core Property Core Auto
IntelEngine_Schedule Property Schedule Auto
GlobalVariable Property IntelEngine_StoryEngineEnabled Auto
GlobalVariable Property IntelEngine_StoryEngineInterval Auto
GlobalVariable Property IntelEngine_StoryEngineCooldown Auto

; === Dispatch State ===
Bool Property IsActive = false Auto Hidden
Actor Property ActiveStoryNPC = None Auto Hidden
String Property ActiveNarration = "" Auto Hidden
String Property PendingStoryType = "" Auto Hidden
Actor Property ActiveSecondNPC = None Auto Hidden
String Property ActiveStoryType = "" Auto Hidden
; === Constants ===
Float Property MONITOR_INTERVAL = 3.0 AutoReadOnly
Float Property ENCOUNTER_PROXIMITY = 300.0 AutoReadOnly
Float Property SNEAK_APPROACH_DISTANCE = 2000.0 AutoReadOnly
Float Property AMBUSH_CONFRONT_DISTANCE = 500.0 AutoReadOnly
Float Property STALKER_KEEP_DISTANCE = 800.0 AutoReadOnly
Float Property STALKER_RESUME_DISTANCE = 1000.0 AutoReadOnly
Float Property SNEAK_TIMEOUT_SECONDS = 300.0 AutoReadOnly
; === Configurable (MCM) ===
Float Property MaxTravelDaysConfig = 1.0 Auto Hidden
Float Property LongAbsenceDaysConfig = 3.0 Auto Hidden
String Property ExcludedTypesConfig = "" Auto Hidden

; === Per-type toggles (MCM) ===
Bool Property TypeSeekPlayerEnabled = true Auto Hidden
Bool Property TypeInformantEnabled = true Auto Hidden
Bool Property TypeRoadEncounterEnabled = true Auto Hidden
Bool Property TypeAmbushEnabled = true Auto Hidden
Bool Property TypeStalkerEnabled = true Auto Hidden
Bool Property TypeMessageEnabled = true Auto Hidden
Bool Property TypeQuestEnabled = true Auto Hidden
Bool Property TypeNPCInteractionEnabled = true Auto Hidden
Bool Property TypeNPCGossipEnabled = true Auto Hidden

; === NPC Social Tick (independent of player-centric tick) ===
Float Property LastNPCTickTime = 0.0 Auto Hidden
Float Property NPCTickIntervalHours = 1.5 Auto Hidden
Bool Property NPCTickEnabled = true Auto Hidden
Bool Property NPCTickPending = false Auto Hidden
Float Property NPCSocialCooldownHours = 24.0 Auto Hidden

; === NPC Social Dispatch (independent travel, does NOT touch IsActive) ===
Bool Property IsNPCStoryActive = false Auto Hidden
Actor Property NPCSocialTraveler = None Auto Hidden
Actor Property NPCSocialTarget = None Auto Hidden
String Property NPCSocialNarration = "" Auto Hidden
String Property NPCSocialType = "" Auto Hidden

; === Quest System ===
Bool Property QuestActive = false Auto Hidden
Actor Property QuestGiver = None Auto Hidden
Actor Property QuestGuideNPC = None Auto Hidden
ObjectReference Property QuestLocation = None Auto Hidden
String Property QuestEnemyType = "" Auto Hidden
String Property QuestLocationName = "" Auto Hidden
Int Property QuestSpawnCount = 0 Auto Hidden
Float Property QuestStartTime = 0.0 Auto Hidden
Bool Property QuestEnemiesSpawned = false Auto Hidden
Bool Property QuestGuideActive = false Auto Hidden
Bool Property QuestGuideWaiting = false Auto Hidden
Float Property QuestGuideStartTime = 0.0 Auto Hidden
Int Property QuestSpawnAttempts = 0 Auto Hidden

Float Property QUEST_EXPIRY_DAYS = 1.0 Auto Hidden
Float Property QUEST_GUIDE_WAIT_DIST = 2000.0 AutoReadOnly
Float Property QUEST_GUIDE_RESUME_DIST = 800.0 AutoReadOnly
Float Property QUEST_GUIDE_TIMEOUT_HOURS = 5.0 AutoReadOnly
Float Property LINGER_TIMEOUT_SECONDS = 300.0 AutoReadOnly
Float Property ENCOUNTER_RESUME_DISTANCE = 1500.0 AutoReadOnly
Float Property TELEPORT_OFFSET_INTERIOR = 500.0 AutoReadOnly
Float Property TELEPORT_OFFSET_EXTERIOR = 3500.0 AutoReadOnly

; CK Property -- quest objective alias (points compass at quest location)
ReferenceAlias Property QuestTargetAlias Auto
Int Property QUEST_OBJECTIVE_ID = 0 AutoReadOnly

; =============================================================================
; TIMER MANAGEMENT
; Two modes: game-time timer for scheduling, real-time timer for monitoring
; =============================================================================

Function StartScheduler()
    If IntelEngine_StoryEngineEnabled == None || IntelEngine_StoryEngineEnabled.GetValue() <= 0
        return
    EndIf
    If IsActive
        RegisterForSingleUpdate(MONITOR_INTERVAL)
    Else
        Float interval = 2.0
        If IntelEngine_StoryEngineInterval != None
            interval = IntelEngine_StoryEngineInterval.GetValue()
        EndIf
        RegisterForSingleUpdateGameTime(interval)
    EndIf
EndFunction

Function StopScheduler()
    UnregisterForUpdate()
    UnregisterForUpdateGameTime()
EndFunction

Function RestartMonitoring()
    ClearPending()
    NPCTickPending = false

    ; Save migration: new properties default to type-zero on old saves
    If NPCTickIntervalHours == 0.0
        NPCTickEnabled = true
        NPCTickIntervalHours = 1.5
        Core.DebugMsg("Story: NPC Social properties initialized (save migration)")
    EndIf

    ; Warm C++ volatile state from StorageUtil (C++ side is empty after game load)
    WarmCooldownMirror()
    WarmStoryTypeCounts()

    ; Clean up NPC Social dispatch on load (packages lost, travel state unrecoverable)
    If IsNPCStoryActive
        Core.DebugMsg("Story: abandoning NPC Social dispatch on load")
        CleanupNPCSocialDispatch()
    EndIf

    ; Recover quest guide walk (packages lost on load, but all state is in properties)
    If QuestGuideActive && QuestGuideNPC != None && QuestLocation != None
        If QuestGuideNPC.IsDead() || QuestGuideNPC.IsDisabled()
            QuestGuideActive = false
            QuestGuideWaiting = false
            ActiveStoryType = ""
            IsActive = false
            Core.DebugMsg("Story: quest guide died/disabled on load, abandoning guide")
        Else
            Core.RemoveAllPackages(QuestGuideNPC, false)
            PO3_SKSEFunctions.SetLinkedRef(QuestGuideNPC, QuestLocation, Core.IntelEngine_TravelTarget)
            ActorUtil.AddPackageOverride(QuestGuideNPC, Core.TravelPackage_Jog, Core.PRIORITY_TRAVEL, 1)
            Utility.Wait(0.1)
            QuestGuideNPC.EvaluatePackage()
            Core.DebugMsg("Story: recovered quest guide jog for " + QuestGuideNPC.GetDisplayName())
        EndIf
    ElseIf IsActive && ActiveStoryNPC != None
        If ActiveStoryNPC.IsDead() || ActiveStoryNPC.IsDisabled()
            CleanupStoryDispatch()
        ElseIf ActiveStoryType == "ambush" || ActiveStoryType == "ambush_charge" || ActiveStoryType == "stalker" || ActiveStoryType == "ambush_combat"
            ; Sneak/combat/charge phase can't be recovered reliably -- abandon, let NPC go home
            ; Motivation memory persists in SkyrimNet so DM can pick them again
            If ActiveStoryType == "ambush_combat"
                ; Was mid-combat with essential flag -- clean up
                ActiveStoryNPC.GetActorBase().SetEssential(false)
                ActiveStoryNPC.StopCombat()
                ActiveStoryNPC.SetActorValue("Aggression", 0)
                ActiveStoryNPC.SetActorValue("Confidence", 2)
            ElseIf ActiveStoryType == "stalker"
                ; Sneak package gets stripped by RemoveAllPackages below
            EndIf
            Core.DebugMsg("Story: abandoning " + ActiveStoryType + " on load (sneak/combat/flee state lost)")
            Int slot = Core.FindSlotByAgent(ActiveStoryNPC)
            If slot >= 0
                Core.ClearSlot(slot)
            EndIf
            Core.RemoveAllPackages(ActiveStoryNPC, false)
            CleanupStoryDispatch()
        Else
            ; Story dispatches are transient ? abandon on load.
            ; Reapplying stale packages causes NPCs to resume old travels even after
            ; manual intervention or completion. The DM will dispatch new stories.
            Core.DebugMsg("Story: abandoning " + ActiveStoryType + " for " + ActiveStoryNPC.GetDisplayName() + " on load")
            Int storySlot = Core.FindSlotByAgent(ActiveStoryNPC)
            If storySlot >= 0
                Core.ClearSlot(storySlot)
            EndIf
            Core.RemoveAllPackages(ActiveStoryNPC, false)
            CleanupStoryDispatch()
        EndIf
    EndIf

    ; Release orphaned linger NPCs on load.
    ; Package overrides (PO3 cosave) survive save/load but linked refs don't,
    ; so lingering NPCs would be stuck sandboxing in place forever.
    Actor player = Game.GetPlayer()

    ; Legacy IntList cleanup (pre-refactor saves that stored FormIDs)
    Int legacyCount = StorageUtil.IntListCount(player, "Intel_StoryLingerNPCs")
    If legacyCount > 0
        Core.DebugMsg("Story: releasing " + legacyCount + " legacy linger NPCs on load")
        Int li = 0
        While li < legacyCount
            Int fid = StorageUtil.IntListGet(player, "Intel_StoryLingerNPCs", li)
            Actor lingerNPC = Game.GetForm(fid) as Actor
            If lingerNPC != None
                Core.ReleaseLinger(lingerNPC)
                StorageUtil.UnsetFloatValue(lingerNPC, "Intel_StoryLingerStart")
            EndIf
            li += 1
        EndWhile
    EndIf
    StorageUtil.IntListClear(player, "Intel_StoryLingerNPCs")

    ; Current FormList cleanup (stores Actor refs directly — no FormID round-trip)
    Int lingerCount = StorageUtil.FormListCount(player, "Intel_StoryLingerActors")
    If lingerCount > 0
        Core.DebugMsg("Story: releasing " + lingerCount + " orphaned linger NPCs on load")
        Int li2 = 0
        While li2 < lingerCount
            Actor lingerNPC2 = StorageUtil.FormListGet(player, "Intel_StoryLingerActors", li2) as Actor
            If lingerNPC2 != None
                Core.ReleaseLinger(lingerNPC2)
                StorageUtil.UnsetFloatValue(lingerNPC2, "Intel_StoryLingerStart")
            EndIf
            li2 += 1
        EndWhile
    EndIf
    StorageUtil.FormListClear(player, "Intel_StoryLingerActors")

    ; Release orphaned road encounter NPCs on load.
    ; Package overrides survive save/load but linked refs and AI state don't,
    ; so NPCs get stranded with stale packages. Send them home.
    Int encounterCount = StorageUtil.IntListCount(player, "Intel_FakeEncounterNPCs")
    If encounterCount > 0
        Core.DebugMsg("Story: releasing " + encounterCount + " orphaned road encounter NPCs on load")
        Int ei = 0
        While ei < encounterCount
            Int efid = StorageUtil.IntListGet(player, "Intel_FakeEncounterNPCs", ei)
            Actor encounterNPC = Game.GetForm(efid) as Actor
            If encounterNPC != None
                ClearRoadEncounterTravelState(encounterNPC)
                StorageUtil.UnsetStringValue(encounterNPC, "Intel_FakeEncounterNarration")
                StorageUtil.UnsetIntValue(encounterNPC, "Intel_FakeEncounterInteracted")
                StorageUtil.UnsetFloatValue(encounterNPC, "Intel_FakeEncounterGreetTime")
                StorageUtil.UnsetFloatValue(encounterNPC, "Intel_FakeEncounterTime")
                encounterNPC.MoveToMyEditorLocation()
            EndIf
            ei += 1
        EndWhile
        StorageUtil.IntListClear(player, "Intel_FakeEncounterNPCs")
    EndIf

    StartScheduler()
EndFunction

; Game-time timer -- fires for scheduling new candidates
Event OnUpdateGameTime()
    ; Register FIRST so the timer chain survives even if processing errors out.
    ; (Same register-first pattern as OnUpdate — timer chain must never break.)
    StartScheduler()

    ; Safety net: clean up lingering NPCs even if real-time timer died
    CheckStoryLingerCleanup()
    ; Re-kick real-time monitoring if linger NPCs still exist
    If HasLingerNPCs()
        RegisterForSingleUpdate(MONITOR_INTERVAL)
    EndIf
    TickScheduler()
EndEvent

; Real-time timer -- fires for arrival monitoring + linger proximity + quest monitoring
Event OnUpdate()
    ; Register FIRST so the loop survives even if processing errors out.
    ; (Same pattern as Travel.OnUpdate — timer chain must never break.)
    Bool needsRealTime = IsActive || IsNPCStoryActive || HasLingerNPCs() || QuestActive
    If needsRealTime
        RegisterForSingleUpdate(MONITOR_INTERVAL)
    EndIf

    CheckRoadEncounterProximity()
    CheckStoryLingerCleanup()

    ; Dialogue safety net: run on real-time tick too (not just game-time scheduler).
    ; C++ check is lightweight ? returns 0 instantly if no new dialogue keywords found.
    Core.RunDialogueSafetyNet()

    ; Quest monitoring (runs independently of IsActive)
    If QuestActive
        If QuestGuideActive
            CheckQuestGuide()
        EndIf
        CheckQuestProximity()
        CheckQuestExpiry()
    EndIf

    ; Monitor both dispatch systems independently
    If IsActive
        CheckStoryNPCArrival()
    EndIf
    If IsNPCStoryActive
        CheckNPCSocialArrival()
    EndIf

    ; If processing above created new work (e.g. FinishArrivalWithLinger added linger NPCs),
    ; ensure real-time monitoring is running even if we skipped it above.
    If !needsRealTime && (IsActive || IsNPCStoryActive || HasLingerNPCs() || QuestActive)
        RegisterForSingleUpdate(MONITOR_INTERVAL)
    ElseIf !needsRealTime
        ; No active dispatches, linger NPCs, or quest -- switch to game-time scheduling.
        ; Always call StartScheduler even if game-time timer was already registered —
        ; RegisterForSingleUpdateGameTime replaces the old registration (no double-fire).
        ; This is a safety net against timer chain death from exceptions.
        StartScheduler()
    EndIf

    ; Belt-and-suspenders: if nothing needs real-time AND this OnUpdate was the last one
    ; (needsRealTime was true at the top but everything got cleaned up during processing),
    ; ensure game-time scheduling is alive. Without this, the timer chain dies if the
    ; transition from real-time to game-time fails for any reason.
    If needsRealTime && !IsActive && !IsNPCStoryActive && !HasLingerNPCs() && !QuestActive
        StartScheduler()
    EndIf
EndEvent

; =============================================================================
; CORE SCHEDULER LOOP (V2 -- Dungeon Master)
; =============================================================================

Function TickScheduler()
    If IntelEngine_StoryEngineEnabled == None || IntelEngine_StoryEngineEnabled.GetValue() <= 0
        return
    EndIf

    ; NPC-to-NPC tick (independent of player-centric state, self-gates via interval timer)
    TickNPCInteractions()

    ; Dialogue safety net: catch missed schedule actions (C++ does heavy lifting)
    Core.RunDialogueSafetyNet()

    ; Safety net: return stranded fake encounter NPCs
    CleanupStrandedEncounters()

    ; --- Player-centric tick ---
    If !IsActive
        Actor player = Game.GetPlayer()
        If !player.IsInCombat()
            ; C++ builds world state + candidate pool in a single call
            String dmContext = IntelEngine.BuildDungeonMasterContext(7, LongAbsenceDaysConfig)
            If dmContext != ""
                ; Pre-warm C++ cooldown mirror from StorageUtil for all pool candidates.
                ; Prevents wasted LLM turns on NPCs that Papyrus would reject.
                If WarmCooldownsForPool()
                    ; Some candidates were on cooldown ? rebuild context without them
                    dmContext = IntelEngine.BuildDungeonMasterContext(7, LongAbsenceDaysConfig)
                    If dmContext == ""
                        return
                    EndIf
                EndIf

                PendingStoryType = "dm_analysis"
                String recentLog = GetRecentStoryEventsLog()

                ; Build exclude list from per-type toggles + environment
                String excludeList = BuildExcludeList(player)

                String contextJson = IntelEngine.BuildStoryDMRequestJson(dmContext, recentLog, excludeList)
                SendStoryLLMRequest("intel_story_dm", "OnDungeonMasterResponse", contextJson)
            EndIf
        EndIf
    EndIf
EndFunction

Bool Function IsNPCToNPCType()
    {Returns true if current active story type targets another NPC (not the player).}
    return (ActiveStoryType == "npc_interaction" || ActiveStoryType == "npc_gossip")
EndFunction

String Function BuildExcludeList(Actor player)
    {Build comma-separated exclude list from per-type toggles + environment auto-excludes.}
    String result = ""
    If !TypeSeekPlayerEnabled
        result = "seek_player"
    EndIf
    If !TypeInformantEnabled
        result = AppendExclude(result, "informant")
    EndIf
    If !TypeRoadEncounterEnabled
        result = AppendExclude(result, "road_encounter")
    EndIf
    If !TypeAmbushEnabled
        result = AppendExclude(result, "ambush")
    EndIf
    If !TypeStalkerEnabled
        result = AppendExclude(result, "stalker")
    EndIf
    If !TypeMessageEnabled
        result = AppendExclude(result, "message")
    EndIf
    If !TypeQuestEnabled
        result = AppendExclude(result, "quest")
    EndIf

    ; Auto-exclude types invalid in interiors
    Cell pCell = player.GetParentCell()
    If pCell != None && pCell.IsInterior()
        result = AppendExclude(result, "stalker")
        result = AppendExclude(result, "ambush")
        result = AppendExclude(result, "road_encounter")
    EndIf

    return result
EndFunction

String Function AppendExclude(String current, String item)
    If current == ""
        return item
    EndIf
    ; Don't add duplicates
    If StringUtil.Find(current, item) >= 0
        return current
    EndIf
    return current + ", " + item
EndFunction

; =============================================================================
; NPC SOCIAL TICK (independent of player-centric tick)
; =============================================================================

Function TickNPCInteractions()
    If !NPCTickEnabled
        return
    EndIf
    If !TypeNPCInteractionEnabled && !TypeNPCGossipEnabled
        return
    EndIf
    If NPCTickPending
        return
    EndIf

    Float currentTime = Utility.GetCurrentGameTime()
    Float intervalDays = NPCTickIntervalHours / 24.0
    If LastNPCTickTime > 0.0 && (currentTime - LastNPCTickTime) < intervalDays
        return
    EndIf

    LastNPCTickTime = currentTime
    NPCTickPending = true

    String npcContext = IntelEngine.BuildNPCInteractionContext(4)
    If npcContext == ""
        NPCTickPending = false
        return
    EndIf

    String recentLog = GetRecentStoryEventsLog()
    String contextJson = IntelEngine.BuildNPCInteractionRequestJson(npcContext, recentLog)
    SendStoryLLMRequest("intel_story_npc_dm", "OnNPCInteractionResponse", contextJson)
EndFunction

Function OnNPCInteractionResponse(String response, Int success)
    NPCTickPending = false

    If success != 1
        Debug.Trace("[IntelEngine] StoryEngine: NPC DM LLM response failed")
        return
    EndIf

    If !ParseShouldAct(response)
        Core.DebugMsg("NPC DM: rejected (no compelling interaction)")
        return
    EndIf

    String storyType = ExtractJsonField(response, "type")
    String npc1Name = ExtractJsonField(response, "npc")
    String npc2Name = ExtractJsonField(response, "npc2")
    String narration = ExtractJsonField(response, "narration")

    If storyType == "" || npc1Name == "" || npc2Name == ""
        return
    EndIf

    ; Per-type toggle filter
    If storyType == "npc_interaction" && !TypeNPCInteractionEnabled
        Core.DebugMsg("NPC DM: npc_interaction disabled via MCM toggle")
        return
    EndIf
    If storyType == "npc_gossip" && !TypeNPCGossipEnabled
        Core.DebugMsg("NPC DM: npc_gossip disabled via MCM toggle")
        return
    EndIf

    IntelEngine.NotifyStoryTypePicked(storyType)

    Actor npc1 = IntelEngine.ResolveStoryCandidate(npc1Name)
    Actor npc2 = IntelEngine.ResolveStoryCandidate(npc2Name)
    If npc1 == None || npc1.IsDead() || npc1.IsDisabled()
        return
    EndIf
    If npc2 == None || npc2.IsDead() || npc2.IsDisabled()
        return
    EndIf
    If !ApplyNPCSocialCooldown(npc1) || !ApplyNPCSocialCooldown(npc2)
        return
    EndIf

    Core.SendPersistentMemory(npc1, npc2, narration)
    Core.DebugMsg("NPC DM [" + storyType + "]: " + npc1.GetDisplayName() + " + " + npc2.GetDisplayName())

    ; Inject facts
    If storyType == "npc_interaction"
        String fact1 = ExtractJsonField(response, "fact1")
        String fact2 = ExtractJsonField(response, "fact2")
        If fact1 != ""
            Core.InjectFact(npc1, fact1)
        EndIf
        If fact2 != ""
            Core.InjectFact(npc2, fact2)
        EndIf
    ElseIf storyType == "npc_gossip"
        String gossipContent = ExtractJsonField(response, "gossip")
        If gossipContent != ""
            Core.InjectGossip(npc1, npc2, gossipContent)
        EndIf
        SpreadGossipOffScreen(npc1, npc2, gossipContent)
    EndIf

    ; Dispatch based on visibility. NPC Social dispatch is independent of IsActive.
    Actor player = Game.GetPlayer()
    Cell playerCell = player.GetParentCell()
    Bool npc1Visible = (playerCell != None && npc1.GetParentCell() == playerCell)
    Bool npc2Visible = (playerCell != None && npc2.GetParentCell() == playerCell)

    If npc1Visible && npc2Visible
        ; Both in player cell -- instant interaction
        PerformVisibleInteraction(npc1, npc2, narration, storyType)
    ElseIf (npc1Visible || npc2Visible) && !IsNPCStoryActive && !npc1.IsPlayerTeammate() && !npc2.IsPlayerTeammate()
        ; One visible -- dispatch the off-screen NPC to walk over
        ; Skip if: dispatch already active, or either is a follower
        If npc2Visible
            DispatchNPCSocial(npc1, npc2, narration, storyType)
        Else
            DispatchNPCSocial(npc2, npc1, narration, storyType)
        EndIf
    Else
        ; Neither visible, dispatch busy, or followers -- off-screen facts only
        String summary = BuildInteractionSummary(npc1, narration, npc2)
        AddRecentStoryEvent(storyType + ": " + summary)
        Core.DebugMsg("Story: " + summary)
    EndIf
EndFunction

; =============================================================================
; NPC SOCIAL DISPATCH (immersive NPC-to-NPC travel, independent of IsActive)
; =============================================================================

Function DispatchNPCSocial(Actor npc, Actor target, String narration, String storyType)
    {Lightweight dispatch for NPC-to-NPC travel. Uses slots but does NOT touch IsActive/ActiveStoryNPC.}
    Int slot = Core.FindFreeAgentSlot()
    If slot < 0
        ; No free slots -- fall back to off-screen
        String summary = BuildInteractionSummary(npc, narration, target)
        AddRecentStoryEvent(storyType + ": " + summary)
        Core.DebugMsg("NPC Social: no free slot, off-screen: " + summary)
        return
    EndIf

    Core.AllocateSlot(slot, npc, "npc_social", target.GetDisplayName(), 1)

    NPCSocialTraveler = npc
    NPCSocialTarget = target
    NPCSocialNarration = narration
    NPCSocialType = storyType
    IsNPCStoryActive = true

    ; Set up travel package toward target NPC
    Core.RemoveAllPackages(npc, false)
    PO3_SKSEFunctions.SetLinkedRef(npc, target as ObjectReference, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(npc, Core.TravelPackage_Jog, Core.PRIORITY_TRAVEL, 1)
    Utility.Wait(0.1)
    npc.EvaluatePackage()

    Core.InitializeStuckTrackingForSlot(slot, npc)
    Core.InitOffScreenTracking(slot, npc, target as ObjectReference)

    Core.DebugMsg("NPC Social: dispatching " + npc.GetDisplayName() + " to " + target.GetDisplayName())

    ; Ensure real-time monitoring is active
    RegisterForSingleUpdate(MONITOR_INTERVAL)
EndFunction

Function CheckNPCSocialArrival()
    {Monitor NPC Social dispatch arrival. Independent of player-centric story state.}
    If NPCSocialTraveler == None
        CleanupNPCSocialDispatch()
        return
    EndIf

    If NPCSocialTraveler.IsDead() || NPCSocialTraveler.IsDisabled()
        CleanupNPCSocialDispatch()
        return
    EndIf
    If NPCSocialTarget == None || NPCSocialTarget.IsDead() || NPCSocialTarget.IsDisabled()
        CleanupNPCSocialDispatch()
        return
    EndIf

    Float dist = NPCSocialTraveler.GetDistance(NPCSocialTarget)

    ; Arrival check
    If dist <= Core.ARRIVAL_DISTANCE && dist > 0.0
        OnNPCSocialArrived()
        return
    EndIf

    Int slot = Core.FindSlotByAgent(NPCSocialTraveler)
    If slot < 0
        CleanupNPCSocialDispatch()
        return
    EndIf

    ; Off-screen: NPC not loaded -- use time-based arrival
    If !NPCSocialTraveler.Is3DLoaded()
        If Core.HandleOffScreenTravel(slot, NPCSocialTraveler, NPCSocialTarget as ObjectReference)
            TeleportNPCSocialAndResume(TELEPORT_OFFSET_EXTERIOR)
        EndIf
        return
    EndIf

    ; On-screen: stuck detection
    Int stuckStatus = IntelEngine.CheckStuckStatus(NPCSocialTraveler, slot, Core.STUCK_DISTANCE_THRESHOLD)
    If stuckStatus == 1
        Core.SoftStuckRecovery(NPCSocialTraveler, slot, NPCSocialTarget as ObjectReference)
    ElseIf stuckStatus >= 3
        TeleportNPCSocialAndResume(TELEPORT_OFFSET_EXTERIOR)
    EndIf

    ; Timeout: 4 game hours (NPC-to-NPC is same location, should be quick)
    Float taskStart = StorageUtil.GetFloatValue(NPCSocialTraveler, "Intel_TaskStartTime", 0.0)
    If taskStart > 0.0 && (Utility.GetCurrentGameTime() - taskStart) > (4.0 / 24.0)
        Core.DebugMsg("NPC Social: timeout for " + NPCSocialTraveler.GetDisplayName())
        TeleportNPCSocialAndResume(200.0)
        OnNPCSocialArrived()
    EndIf
EndFunction

Function TeleportNPCSocialAndResume(Float distance)
    {Teleport NPC Social traveler near target and reapply travel package.}
    Float[] offset = IntelEngine.GetOffsetBehind(NPCSocialTarget, distance)
    NPCSocialTraveler.MoveTo(NPCSocialTarget, offset[0], offset[1], 0.0, false)
    Core.RemoveAllPackages(NPCSocialTraveler, false)
    PO3_SKSEFunctions.SetLinkedRef(NPCSocialTraveler, NPCSocialTarget as ObjectReference, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(NPCSocialTraveler, Core.TravelPackage_Jog, Core.PRIORITY_TRAVEL, 1)
    Utility.Wait(0.1)
    NPCSocialTraveler.EvaluatePackage()
EndFunction

Function OnNPCSocialArrived()
    {NPC Social traveler arrived at target. Perform visible interaction and clean up.}
    Core.DebugMsg("NPC Social: " + NPCSocialTraveler.GetDisplayName() + " arrived at " + NPCSocialTarget.GetDisplayName())
    PerformVisibleInteraction(NPCSocialTraveler, NPCSocialTarget, NPCSocialNarration, NPCSocialType)
    CleanupNPCSocialDispatch()
EndFunction

Function CleanupNPCSocialDispatch()
    If NPCSocialTraveler != None
        Int slot = Core.FindSlotByAgent(NPCSocialTraveler)
        If slot >= 0
            Core.ClearSlot(slot)  ; handles packages, linked refs, StorageUtil keys
        Else
            Core.RemoveAllPackages(NPCSocialTraveler, false)
        EndIf
    EndIf
    NPCSocialTraveler = None
    NPCSocialTarget = None
    NPCSocialNarration = ""
    NPCSocialType = ""
    IsNPCStoryActive = false
EndFunction

Bool Function ApplyCooldownCheck(Actor candidate)
    {Check STORY cooldown + scheduled state. Sets Intel_StoryLastPicked on success. Returns true if passed.}
    If StorageUtil.GetIntValue(candidate, "Intel_ScheduledState", -1) >= 0
        return false
    EndIf

    Float lastPicked = StorageUtil.GetFloatValue(candidate, "Intel_StoryLastPicked", 0.0)
    Float currentTime = Utility.GetCurrentGameTime()
    Float cooldownHours = 24.0
    If IntelEngine_StoryEngineCooldown != None
        cooldownHours = IntelEngine_StoryEngineCooldown.GetValue()
    EndIf
    Float cooldownDays = cooldownHours / 24.0
    If lastPicked > 0.0 && (currentTime - lastPicked) < cooldownDays
        IntelEngine.NotifyStoryCooldown(candidate, lastPicked)
        ; Self-heal formlist for warmup on next game load
        StorageUtil.FormListAdd(self, "Intel_CooldownActors", candidate, false)
        return false
    EndIf

    StorageUtil.SetFloatValue(candidate, "Intel_StoryLastPicked", currentTime)
    IntelEngine.NotifyStoryCooldown(candidate, currentTime)
    ; Track for warmup on next game load (StorageUtil persists, C++ mirror doesn't)
    StorageUtil.FormListAdd(self, "Intel_CooldownActors", candidate, false)
    return true
EndFunction

Bool Function ApplyNPCSocialCooldown(Actor candidate)
    {Separate cooldown for NPC-NPC social interactions (gossip, npc_interaction).
     Uses its own StorageUtil key so it doesn't block story DM dispatches.}
    Float lastPicked = StorageUtil.GetFloatValue(candidate, "Intel_NPCSocialLastPicked", 0.0)
    Float currentTime = Utility.GetCurrentGameTime()
    Float cooldownDays = NPCSocialCooldownHours / 24.0
    If lastPicked > 0.0 && (currentTime - lastPicked) < cooldownDays
        return false
    EndIf

    StorageUtil.SetFloatValue(candidate, "Intel_NPCSocialLastPicked", currentTime)
    return true
EndFunction

Function WarmCooldownMirror()
    {Populate C++ cooldown mirror from StorageUtil on game load. Prevents wasted LLM turns.}
    Float currentTime = Utility.GetCurrentGameTime()
    Float cooldownHours = 24.0
    If IntelEngine_StoryEngineCooldown != None
        cooldownHours = IntelEngine_StoryEngineCooldown.GetValue()
    EndIf
    Float cooldownDays = cooldownHours / 24.0

    Int count = StorageUtil.FormListCount(self, "Intel_CooldownActors")
    Int warmed = 0
    Int i = count - 1
    While i >= 0
        Actor npc = StorageUtil.FormListGet(self, "Intel_CooldownActors", i) as Actor
        If npc != None
            Float lastPicked = StorageUtil.GetFloatValue(npc, "Intel_StoryLastPicked", 0.0)
            If lastPicked > 0.0 && (currentTime - lastPicked) < cooldownDays
                IntelEngine.NotifyStoryCooldown(npc, lastPicked)
                warmed += 1
            Else
                StorageUtil.FormListRemoveAt(self, "Intel_CooldownActors", i)
            EndIf
        Else
            StorageUtil.FormListRemoveAt(self, "Intel_CooldownActors", i)
        EndIf
        i -= 1
    EndWhile
    If warmed > 0
        Core.DebugMsg("Story: warmed C++ cooldown mirror (" + warmed + " NPCs)")
    EndIf
EndFunction

Bool Function WarmCooldownsForPool()
    {Check StorageUtil cooldowns for all DM candidate pool NPCs and warm C++ mirror.
    Returns true if any candidates were on cooldown (caller should rebuild context).}
    Int[] formIDs = IntelEngine.GetDMCandidatePoolFormIDs()
    If formIDs.Length == 0
        return false
    EndIf

    Float currentTime = Utility.GetCurrentGameTime()
    Float cooldownHours = 24.0
    If IntelEngine_StoryEngineCooldown != None
        cooldownHours = IntelEngine_StoryEngineCooldown.GetValue()
    EndIf
    Float cooldownDays = cooldownHours / 24.0

    Int warmed = 0
    Int i = 0
    While i < formIDs.Length
        Actor npc = Game.GetForm(formIDs[i]) as Actor
        If npc != None
            Float lastPicked = StorageUtil.GetFloatValue(npc, "Intel_StoryLastPicked", 0.0)
            If lastPicked > 0.0 && (currentTime - lastPicked) < cooldownDays
                IntelEngine.NotifyStoryCooldown(npc, lastPicked)
                StorageUtil.FormListAdd(self, "Intel_CooldownActors", npc, false)
                warmed += 1
            EndIf
        EndIf
        i += 1
    EndWhile
    If warmed > 0
        Core.DebugMsg("Story: pre-warmed " + warmed + " cooldowns from pool candidates")
    EndIf
    return warmed > 0
EndFunction

Function WarmStoryTypeCounts()
    {Parse type prefixes from Intel_RecentStoryEvents and warm C++ type counts.
    Recent events persist in StorageUtil; C++ counts are volatile.
    Gives the DM prompt immediate balancing data from the start of each session.}
    Actor player = Game.GetPlayer()
    Int count = StorageUtil.StringListCount(player, "Intel_RecentStoryEvents")
    If count == 0
        return
    EndIf
    Int i = 0
    While i < count
        String entry = StorageUtil.StringListGet(player, "Intel_RecentStoryEvents", i)
        Int colonPos = StringUtil.Find(entry, ":")
        If colonPos > 0
            String storyType = StringUtil.Substring(entry, 0, colonPos)
            IntelEngine.NotifyStoryTypePicked(storyType)
        EndIf
        i += 1
    EndWhile
    Core.DebugMsg("Story: warmed type counts from " + count + " recent events")
EndFunction

; =============================================================================
; LLM COMMUNICATION
; =============================================================================

Function SendStoryLLMRequest(String promptName, String callbackName, String contextJson)
    Int result = SkyrimNetApi.SendCustomPromptToLLM(promptName, "", contextJson, \
        Self, "IntelEngine_StoryEngine", callbackName)
    If result < 0
        Debug.Trace("[IntelEngine] StoryEngine: LLM call failed (" + promptName + ") code " + result)
        ClearPending()
    EndIf
EndFunction

; =============================================================================
; DUNGEON MASTER RESPONSE HANDLER
; =============================================================================

Function OnDungeonMasterResponse(String response, Int success)
    ClearPending()

    If success != 1
        Debug.Trace("[IntelEngine] StoryEngine: DM LLM response failed")
        return
    EndIf

    Int responseLen = StringUtil.GetLength(response)
    Debug.Trace("[IntelEngine] StoryEngine: DM response len=" + responseLen + " success=" + success)

    If !ParseShouldAct(response)
        Core.DebugMsg("Story DM: rejected (no compelling story)")
        return
    EndIf

    String storyType = ExtractJsonField(response, "type")
    String npcName = ExtractJsonField(response, "npc")
    String narration = ExtractJsonField(response, "narration")

    If storyType == "" || npcName == ""
        Debug.Trace("[IntelEngine] StoryEngine: DM response missing type or npc -- response len=" + responseLen)
        return
    EndIf

    IntelEngine.NotifyStoryTypePicked(storyType)

    ; Resolve primary NPC from candidate pool (exact FormID, no name ambiguity)
    Actor npc = IntelEngine.ResolveStoryCandidate(npcName)
    If npc == None || npc.IsDead() || npc.IsDisabled()
        Core.DebugMsg("Story DM: NPC '" + npcName + "' not found or invalid")
        return
    EndIf
    If !ApplyCooldownCheck(npc)
        Core.DebugMsg("Story DM: " + npc.GetDisplayName() + " on cooldown")
        return
    EndIf

    ; Re-validate: reject player-targeted types if NPC ended up in the player's cell
    ; (pool was built seconds ago ? player may have moved cells during LLM round-trip)
    If storyType == "seek_player" || storyType == "informant" || storyType == "message"
        Cell npcCell = npc.GetParentCell()
        Cell playerCell = Game.GetPlayer().GetParentCell()
        If npcCell != None && playerCell != None && npcCell == playerCell
            Core.DebugMsg("Story DM: " + npc.GetDisplayName() + " already in player's cell, skipping " + storyType)
            return
        EndIf
    EndIf

    ; Stalker/ambush require outdoor space ? interiors are too small for sneak gameplay
    If storyType == "stalker" || storyType == "ambush"
        Cell playerCell2 = Game.GetPlayer().GetParentCell()
        If playerCell2 != None && playerCell2.IsInterior()
            Core.DebugMsg("Story DM: rejecting " + storyType + " -- player is in interior")
            return
        EndIf
    EndIf

    Core.DebugMsg("Story DM [" + storyType + "]: " + npc.GetDisplayName() + " -- " + narration)

    ; Pre-validate type-specific required fields BEFORE sending persistent memory.
    ; If we narrate first and then the handler rejects, the NPC talks about
    ; something that never happens (e.g., a quest with no valid location).
    If storyType == "quest"
        If QuestActive
            Core.DebugMsg("Story DM: quest rejected -- one already active")
            return
        EndIf
        If ExtractJsonField(response, "questLocation") == "" || ExtractJsonField(response, "enemyType") == ""
            Core.DebugMsg("Story DM: quest rejected -- missing questLocation or enemyType")
            return
        EndIf
    ElseIf storyType == "message"
        If ExtractJsonField(response, "msgContent") == ""
            Core.DebugMsg("Story DM: message rejected -- missing msgContent")
            return
        EndIf
    EndIf

    ; Record dispatch as a persistent event (generic text, NOT the full narration).
    ; The actual narration fires only once on arrival via OnStoryNPCArrived.
    Core.SendPersistentMemory(npc, Game.GetPlayer(), npc.GetDisplayName() + " set out to find " + Game.GetPlayer().GetDisplayName())

    ; Route by type
    If storyType == "seek_player"
        Core.InjectFact(npc, "set out to find " + Game.GetPlayer().GetDisplayName() + " -- " + narration)
        ActiveStoryType = storyType
        DispatchToTarget(npc, Game.GetPlayer(), narration, "story")

    ElseIf storyType == "message"
        HandleMessageDispatch(npc, narration, response)

    ElseIf storyType == "ambush" || storyType == "stalker"
        HandleAmbushStalkerDispatch(npc, narration, response, storyType)

    ElseIf storyType == "quest"
        HandleQuestDispatch(npc, narration, response)

    ElseIf storyType == "informant"
        String subjectName = ExtractJsonField(response, "subject")
        String gossipText = ExtractJsonField(response, "gossip")
        String gossipSource = ExtractJsonField(response, "sender")
        If subjectName != "" && gossipText != ""
            Actor subjectNPC = IntelEngine.FindNPCByName(subjectName)
            If subjectNPC != None
                Core.InjectFact(subjectNPC, gossipText)
            EndIf
            ; Informant must know the gossip AND its source to relay during dialogue
            If gossipSource != ""
                Core.InjectFact(npc, "heard from " + gossipSource + " that " + subjectName + " " + gossipText)
            Else
                Core.InjectFact(npc, "witnessed that " + subjectName + " " + gossipText)
            EndIf
        EndIf
        ActiveStoryType = "informant"
        DispatchToTarget(npc, Game.GetPlayer(), narration, "story")

    ElseIf storyType == "road_encounter"
        String destination = ExtractJsonField(response, "destination")
        Core.InjectFact(npc, narration)
        PlaceRoadEncounter(npc, narration, destination)

    Else
        Core.DebugMsg("Story DM: unknown type '" + storyType + "'")
    EndIf
EndFunction

Function SpreadGossipOffScreen(Actor originalGossiper, Actor firstRecipient, String gossip)
    {When both NPCs are off-screen, the rumor chains through up to 10 additional NPCs.
    Each new recipient heard it from the PREVIOUS person in the chain, not the original source.
    A tells B (primary), B tells C, C tells D, etc.}
    Actor player = Game.GetPlayer()
    Cell playerCell = player.GetParentCell()

    ; Only chain-spread if both original NPCs are off-screen
    If playerCell != None
        If originalGossiper.GetParentCell() == playerCell || firstRecipient.GetParentCell() == playerCell
            return
        EndIf
    EndIf

    ; Track all involved NPCs via temp list to prevent loops
    String trackKey = "Intel_GossipChainTemp"
    StorageUtil.IntListClear(player, trackKey)
    StorageUtil.IntListAdd(player, trackKey, originalGossiper.GetFormID())
    StorageUtil.IntListAdd(player, trackKey, firstRecipient.GetFormID())

    Int spreads = Utility.RandomInt(1, 10)
    Actor currentGiver = firstRecipient
    Int s = 0
    While s < spreads
        Actor nextRecipient = IntelEngine.GetRelatedCandidate(currentGiver)
        If nextRecipient != None && StorageUtil.IntListFind(player, trackKey, nextRecipient.GetFormID()) < 0
            Core.InjectGossip(currentGiver, nextRecipient, gossip)
            Debug.Trace("[IntelEngine] StoryEngine [npc_gossip chain]: " + currentGiver.GetDisplayName() + " -> " + nextRecipient.GetDisplayName())
            AddRecentStoryEvent("npc_gossip: " + currentGiver.GetDisplayName() + " told " + nextRecipient.GetDisplayName() + ": " + gossip)
            StorageUtil.IntListAdd(player, trackKey, nextRecipient.GetFormID())
            currentGiver = nextRecipient
        Else
            StorageUtil.IntListClear(player, trackKey)
            return
        EndIf
        s += 1
    EndWhile
    StorageUtil.IntListClear(player, trackKey)
EndFunction

; =============================================================================
; DISPATCH (unified -- handles both player-targeted and NPC-targeted)
; =============================================================================

Function DispatchToTarget(Actor npc, Actor target, String narration, String slotTaskType)
    Int slot = Core.FindFreeAgentSlot()
    If slot < 0
        Debug.Trace("[IntelEngine] StoryEngine: No free slots for dispatch")
        ; For NPC targets, log event (facts already injected by caller)
        If target != Game.GetPlayer()
            AddRecentStoryEvent(ActiveStoryType + ": " + BuildInteractionSummary(npc, narration, target))
        EndIf
        ; Reset state set by caller before DispatchToTarget was called
        ActiveStoryType = ""
        return
    EndIf

    ; Determine slot target name
    String targetName = target.GetDisplayName()
    If target != Game.GetPlayer()
        ActiveSecondNPC = target
    EndIf

    Core.AllocateSlot(slot, npc, slotTaskType, targetName, 1)

    ActiveStoryNPC = npc
    ActiveNarration = narration
    IsActive = true
    StorageUtil.SetIntValue(npc, "Intel_IsStoryDispatch", 1)
    StorageUtil.SetStringValue(npc, "Intel_StoryNarration", narration)

    ReapplyTravelPackage(npc)

    Core.InitializeStuckTrackingForSlot(slot, npc)
    Core.InitOffScreenTracking(slot, npc, target as ObjectReference)

    ; Cap off-screen estimate for player-targeted stories to prevent stranding.
    ; NPC may physically walk to the area faster than the distance estimate, then get
    ; stuck in a different cell when the player moves. 15 game minutes max keeps it snappy.
    If target == Game.GetPlayer()
        Float MAX_STORY_OFFSCREEN_HOURS = 0.25
        Float maxWait = MAX_STORY_OFFSCREEN_HOURS / 24.0
        Float now = Utility.GetCurrentGameTime()
        Float estimate = StorageUtil.GetFloatValue(npc, "Intel_OffscreenArrival", 0.0)
        If estimate > 0.0 && (estimate - now) > maxWait
            Float capped = now + maxWait
            IntelEngine.InitOffScreenTravel(slot, capped, npc)
            StorageUtil.SetFloatValue(npc, "Intel_OffscreenArrival", capped)
            Core.DebugMsg(npc.GetDisplayName() + " story off-screen capped to " + MAX_STORY_OFFSCREEN_HOURS + "H (was " + ((estimate - now) * 24.0) + "H)")
        EndIf
    EndIf

    StopScheduler()
    RegisterForSingleUpdate(MONITOR_INTERVAL)
EndFunction

; =============================================================================
; NPC-TO-NPC INTERACTION
; =============================================================================

Function PerformVisibleInteraction(Actor npc1, Actor npc2, String eventText, String eventType = "npc_interaction")
    {Both NPCs in player cell -- instant visible interaction, no travel needed.}
    npc1.SetLookAt(npc2)
    npc2.SetLookAt(npc1)
    Utility.Wait(0.5)

    String summary = BuildInteractionSummary(npc1, eventText, npc2)
    Core.SendTaskNarration(npc1, summary, npc2)

    AddRecentStoryEvent(eventType + ": " + summary)
    Debug.Trace("[IntelEngine] StoryEngine: Visible " + eventType + " performed")
EndFunction

; =============================================================================
; ROAD ENCOUNTER (NPC travels to real destination, approaches player if nearby)
; =============================================================================

Function PlaceRoadEncounter(Actor npc, String narration, String destination)
    Actor player = Game.GetPlayer()
    Cell playerCell = player.GetParentCell()

    ; Only in exteriors
    If playerCell != None && playerCell.IsInterior()
        Debug.Trace("[IntelEngine] StoryEngine: Skipping road encounter -- player is indoors")
        return
    EndIf

    ; Place NPC AHEAD of player (negative distance = forward direction)
    Float placeDist = Utility.RandomFloat(3000.0, 5000.0)
    Float[] offset = IntelEngine.GetOffsetBehind(player, -placeDist)
    npc.MoveTo(player, offset[0], offset[1], 0.0, false)

    ; Give NPC conversational context
    Core.SendPersistentMemory(npc, npc, npc.GetDisplayName() + " " + narration)

    ; Try to resolve a real destination for travel
    ObjectReference destMarker = None
    If destination != ""
        destMarker = IntelEngine.ResolveAnyDestination(npc, destination)
    EndIf

    ; Clear existing packages so travel override takes priority
    Core.RemoveAllPackages(npc, false)

    If destMarker != None
        ; Real travel: set up walk package to destination
        StorageUtil.SetFormValue(npc, "Intel_FakeEncounterDest", destMarker)
        PO3_SKSEFunctions.SetLinkedRef(npc, destMarker, Core.IntelEngine_TravelTarget)
        ActorUtil.AddPackageOverride(npc, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
        Utility.Wait(0.1)
        npc.EvaluatePackage()
        Core.DebugMsg("Story: road encounter " + npc.GetDisplayName() + " traveling to " + destination)
    Else
        ; Fallback: sandbox at placement (old behavior)
        npc.EvaluatePackage()
        Core.DebugMsg("Story: road encounter " + npc.GetDisplayName() + " (no destination resolved)")
    EndIf

    ; Store narration for proximity interaction
    StorageUtil.SetStringValue(npc, "Intel_FakeEncounterNarration", narration)

    ; Track for proximity monitoring + return safety net
    StorageUtil.SetFloatValue(npc, "Intel_FakeEncounterTime", Utility.GetCurrentGameTime())
    Int npcFormId = npc.GetFormID()
    If StorageUtil.IntListFind(player, "Intel_FakeEncounterNPCs", npcFormId) < 0
        StorageUtil.IntListAdd(player, "Intel_FakeEncounterNPCs", npcFormId)
    EndIf

    AddRecentStoryEvent("road_encounter: " + npc.GetDisplayName() + " -- " + narration)

    ; Ensure real-time monitoring is running for proximity checks
    RegisterForSingleUpdate(MONITOR_INTERVAL)
EndFunction

Function CheckRoadEncounterProximity()
    {Checks all active road encounter NPCs for proximity to the player.
    Called every MONITOR_INTERVAL from OnUpdate regardless of IsActive state.}
    Actor player = Game.GetPlayer()
    Int count = StorageUtil.IntListCount(player, "Intel_FakeEncounterNPCs")
    If count == 0
        return
    EndIf

    Int i = count - 1
    While i >= 0
        Int formId = StorageUtil.IntListGet(player, "Intel_FakeEncounterNPCs", i)
        Actor npc = Game.GetForm(formId) as Actor

        If npc == None || npc.IsDead() || npc.IsDisabled()
            ; Stale entry -- remove
            StorageUtil.IntListRemoveAt(player, "Intel_FakeEncounterNPCs", i)
            i -= 1
        Else
            ; Check if NPC has reached destination
            ObjectReference destMarker = StorageUtil.GetFormValue(npc, "Intel_FakeEncounterDest") as ObjectReference
            If destMarker != None && npc.Is3DLoaded() && destMarker.Is3DLoaded()
                If npc.GetDistance(destMarker) <= Core.ARRIVAL_DISTANCE
                    CleanupRoadEncounterTravel(npc)
                EndIf
            EndIf

            ; Check proximity to player (only if not already interacted)
            Int encounterPhase = StorageUtil.GetIntValue(npc, "Intel_FakeEncounterInteracted")
            If encounterPhase == 0
                If npc.Is3DLoaded() && player.Is3DLoaded()
                    Float dist = npc.GetDistance(player)
                    If dist <= ENCOUNTER_PROXIMITY && dist > 0.0
                        TriggerRoadEncounterGreeting(npc)
                    EndIf
                EndIf
            ElseIf encounterPhase == 1
                ; Lingering -- resume travel when player walks away or max linger exceeded
                Float dist = npc.GetDistance(player)
                Float greetTime = StorageUtil.GetFloatValue(npc, "Intel_FakeEncounterGreetTime", 0.0)
                Float elapsed = Utility.GetCurrentRealTime() - greetTime
                Bool shouldResume = (dist > ENCOUNTER_RESUME_DISTANCE) || (greetTime > 0.0 && elapsed > LINGER_TIMEOUT_SECONDS) || !npc.Is3DLoaded()
                If shouldResume
                    ; Restore destination travel (or just remove sandbox if no destination)
                    ActorUtil.RemovePackageOverride(npc, Core.SandboxNearPlayerPackage)
                    destMarker = StorageUtil.GetFormValue(npc, "Intel_FakeEncounterDest") as ObjectReference
                    If destMarker != None
                        PO3_SKSEFunctions.SetLinkedRef(npc, destMarker, Core.IntelEngine_TravelTarget)
                        ActorUtil.AddPackageOverride(npc, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
                    Else
                        PO3_SKSEFunctions.SetLinkedRef(npc, None, Core.IntelEngine_TravelTarget)
                    EndIf
                    npc.EvaluatePackage()
                    StorageUtil.SetIntValue(npc, "Intel_FakeEncounterInteracted", 2)
                    StorageUtil.UnsetFloatValue(npc, "Intel_FakeEncounterGreetTime")
                    Core.DebugMsg("Story [encounter]: " + npc.GetDisplayName() + " resuming travel")
                EndIf
            ; Phase 2: traveling to destination (post-linger) -- no action needed, just skip
            EndIf
            i -= 1
        EndIf
    EndWhile
EndFunction

; =============================================================================
; STORY ARRIVAL LINGER
; After a story NPC arrives and talks, they sandbox near the player until
; the player walks away (>1500u) or 5 min real-time elapses.
; SkyrimNet follow packages (higher priority) override the sandbox naturally.
; =============================================================================

Bool Function HasLingerNPCs()
    Actor player = Game.GetPlayer()
    return StorageUtil.FormListCount(player, "Intel_StoryLingerActors") > 0 || \
           StorageUtil.IntListCount(player, "Intel_FakeEncounterNPCs") > 0
EndFunction

Function StartStoryLinger(Actor npc)
    Actor player = Game.GetPlayer()
    If StorageUtil.FormListFind(player, "Intel_StoryLingerActors", npc as Form) < 0
        StorageUtil.FormListAdd(player, "Intel_StoryLingerActors", npc as Form)
    EndIf
    StorageUtil.SetFloatValue(npc, "Intel_StoryLingerStart", Utility.GetCurrentRealTime())
EndFunction

Function FinishArrivalWithLinger(Actor arrivedNPC, ObjectReference lingerTarget)
    {Shared arrival pattern: clear slot, cleanup dispatch, sandbox near target, start linger tracking.
     Caller MUST save arrivedNPC from ActiveStoryNPC BEFORE calling (CleanupStoryDispatch clears it).}
    Int slot = Core.FindSlotByAgent(arrivedNPC)
    If slot >= 0
        Core.ClearSlot(slot)
    EndIf
    CleanupStoryDispatch()

    ; For player-targeted stories: sandbox at NPC's current position (linked ref = self).
    ; NOT the player -- linking to the player makes the NPC follow indefinitely
    ; because the sandbox center moves with the player.
    ; For NPC-to-NPC: sandbox near the other NPC (stationary target is fine).
    ObjectReference sandboxRef = arrivedNPC as ObjectReference
    If lingerTarget != None && lingerTarget != Game.GetPlayer() as ObjectReference
        sandboxRef = lingerTarget
    EndIf
    PO3_SKSEFunctions.SetLinkedRef(arrivedNPC, sandboxRef, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(arrivedNPC, Core.SandboxNearPlayerPackage, Core.PRIORITY_SANDBOX, 1)
    Utility.Wait(0.1)
    arrivedNPC.EvaluatePackage()
    ; Ensure building access: if NPC is inside an interior, unlock door + remove trespass
    Core.EnsureBuildingAccess(arrivedNPC)
    StartStoryLinger(arrivedNPC)
    ; OnUpdate registers FIRST (Travel pattern) — will detect HasLingerNPCs() on next tick.
    ; Also OnUpdateGameTime re-kicks real-time monitoring as safety net.
    RegisterForSingleUpdate(MONITOR_INTERVAL)
EndFunction

Function CheckStoryLingerCleanup()
    {Remove sandbox from story NPCs when player walks away or timeout.
    Uses Core.ShouldReleaseLinger — single source of truth for release decision.
    Stores Actor refs directly via FormList — no FormID round-trip.}
    Actor player = Game.GetPlayer()
    Int count = StorageUtil.FormListCount(player, "Intel_StoryLingerActors")
    If count == 0
        return
    EndIf

    Int i = count - 1
    While i >= 0
        Actor npc = StorageUtil.FormListGet(player, "Intel_StoryLingerActors", i) as Actor

        If npc == None || npc.IsDead() || npc.IsDisabled()
            StorageUtil.FormListRemoveAt(player, "Intel_StoryLingerActors", i)
        Else
            ; Real-time timeout (story-specific safety valve)
            Float lingerStart = StorageUtil.GetFloatValue(npc, "Intel_StoryLingerStart", 0.0)
            Float elapsed = Utility.GetCurrentRealTime() - lingerStart
            Bool timedOut = lingerStart > 0.0 && elapsed > LINGER_TIMEOUT_SECONDS
            Bool shouldRelease = Core.ShouldReleaseLinger(npc)

            If timedOut || shouldRelease
                Core.ReleaseLinger(npc)
                StorageUtil.UnsetFloatValue(npc, "Intel_StoryLingerStart")
                StorageUtil.FormListRemoveAt(player, "Intel_StoryLingerActors", i)
            EndIf
        EndIf
        i -= 1
    EndWhile
EndFunction

Function TriggerRoadEncounterGreeting(Actor npc)
    {NPC noticed the player nearby -- greet and linger. Sandbox near player until
    player walks away (>1500u) or max linger time (5 min real) exceeded.
    Destination restored by CheckRoadEncounterProximity.}
    Actor player = Game.GetPlayer()
    String narration = StorageUtil.GetStringValue(npc, "Intel_FakeEncounterNarration")

    ; Stop walking and sandbox near player so NPC stays close for conversation
    ActorUtil.RemovePackageOverride(npc, Core.TravelPackage_Walk)
    PO3_SKSEFunctions.SetLinkedRef(npc, player as ObjectReference, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(npc, Core.SandboxNearPlayerPackage, Core.PRIORITY_SANDBOX, 1)
    npc.EvaluatePackage()

    ; Face player and trigger SkyrimNet conversation (NPC must be idle, not walking)
    Utility.Wait(0.5)
    npc.SetLookAt(player)
    Core.SendTaskNarration(npc, narration, player)

    ; Mark as interacted + store time for max-linger fallback
    StorageUtil.SetIntValue(npc, "Intel_FakeEncounterInteracted", 1)
    StorageUtil.SetFloatValue(npc, "Intel_FakeEncounterGreetTime", Utility.GetCurrentRealTime())

    Core.DebugMsg("Story [encounter]: " + npc.GetDisplayName() + " lingering near player")
EndFunction

Function ClearRoadEncounterTravelState(Actor npc)
    {Shared cleanup: remove all encounter packages, linked ref, and destination marker.}
    ActorUtil.RemovePackageOverride(npc, Core.TravelPackage_Walk)
    ActorUtil.RemovePackageOverride(npc, Core.SandboxNearPlayerPackage)
    PO3_SKSEFunctions.SetLinkedRef(npc, None, Core.IntelEngine_TravelTarget)
    StorageUtil.UnsetFormValue(npc, "Intel_FakeEncounterDest")
EndFunction

Function CleanupRoadEncounterTravel(Actor npc)
    {NPC reached their destination -- remove travel overrides, let them sandbox.}
    ClearRoadEncounterTravelState(npc)
    npc.EvaluatePackage()
    Core.DebugMsg("Story: " + npc.GetDisplayName() + " reached destination")
    ; NPC stays in Intel_FakeEncounterNPCs for eventual home-return by CleanupStrandedEncounters
EndFunction

Function CleanupStrandedEncounters()
    {Safety net: return road encounter NPCs to editor location after >1 game day.}
    Actor player = Game.GetPlayer()
    Int count = StorageUtil.IntListCount(player, "Intel_FakeEncounterNPCs")
    If count == 0
        return
    EndIf
    Float currentTime = Utility.GetCurrentGameTime()
    ; Iterate backwards so removals don't shift indices
    Int i = count - 1
    While i >= 0
        Int formId = StorageUtil.IntListGet(player, "Intel_FakeEncounterNPCs", i)
        Actor npc = Game.GetForm(formId) as Actor
        If npc != None
            Float encounterTime = StorageUtil.GetFloatValue(npc, "Intel_FakeEncounterTime", 0.0)
            If encounterTime > 0.0 && (currentTime - encounterTime) > 1.0
                ; Clean up all state before returning home
                Core.RemoveAllPackages(npc, false)
                ClearRoadEncounterTravelState(npc)
                StorageUtil.UnsetStringValue(npc, "Intel_FakeEncounterNarration")
                StorageUtil.UnsetIntValue(npc, "Intel_FakeEncounterInteracted")
                StorageUtil.UnsetFloatValue(npc, "Intel_FakeEncounterGreetTime")
                npc.MoveToMyEditorLocation()
                StorageUtil.UnsetFloatValue(npc, "Intel_FakeEncounterTime")
                StorageUtil.IntListRemoveAt(player, "Intel_FakeEncounterNPCs", i)
                Debug.Trace("[IntelEngine] StoryEngine: Returned road encounter NPC " + npc.GetDisplayName())
            EndIf
        Else
            ; NPC no longer valid -- remove stale entry
            StorageUtil.IntListRemoveAt(player, "Intel_FakeEncounterNPCs", i)
        EndIf
        i -= 1
    EndWhile
EndFunction

; =============================================================================
; ARRIVAL MONITORING
; =============================================================================

Function CheckStoryNPCArrival()
    If ActiveStoryNPC == None || ActiveStoryNPC.IsDead() || ActiveStoryNPC.IsDisabled()
        CleanupStoryDispatch()
        return
    EndIf

    ; Corrupt state detection: IsActive true but no type means something went wrong
    ; during concurrent event processing (seen with Sylvi seek_player — FinishArrivalWithLinger
    ; Utility.Wait re-entry corrupted state). Clean up to prevent tick death.
    If ActiveStoryType == ""
        Core.DebugMsg("Story: corrupt state detected (IsActive but no type) for " + ActiveStoryNPC.GetDisplayName() + " - cleaning up")
        CleanupStoryDispatch()
        return
    EndIf

    ; Orphan detection: if NPC is valid but no longer in a slot, dispatch was
    ; externally cleared (console, MCM). Clean up to unblock future ticks.
    Int activeSlot = Core.FindSlotByAgent(ActiveStoryNPC)
    If activeSlot < 0
        Core.DebugMsg("Story: orphaned dispatch detected for " + ActiveStoryNPC.GetDisplayName() + " [" + ActiveStoryType + "] - cleaning up")
        CleanupStoryDispatch()
        return
    EndIf

    Actor player = Game.GetPlayer()

    ; === Ambush combat monitoring (yield when hurt) ===
    If ActiveStoryType == "ambush_combat"
        CheckAmbushCombat()
        return
    EndIf

    ; === Ambush/Stalker sneak monitoring (overrides normal arrival) ===
    If (ActiveStoryType == "ambush" || ActiveStoryType == "stalker") && ActiveStoryNPC.Is3DLoaded()
        ; Timeout: if sneak phase runs too long AND player is far away, give up
        Float sneakStart = StorageUtil.GetFloatValue(ActiveStoryNPC, "Intel_SneakStartTime", 0.0)
        If sneakStart > 0.0 && (Utility.GetCurrentRealTime() - sneakStart) > SNEAK_TIMEOUT_SECONDS && Core.ShouldReleaseLinger(ActiveStoryNPC)
            Core.DebugMsg("Story [" + ActiveStoryType + "]: " + ActiveStoryNPC.GetDisplayName() + " timed out after " + SNEAK_TIMEOUT_SECONDS as Int + "s - abandoning")
            Core.NotifyPlayer("Story: " + ActiveStoryNPC.GetDisplayName() + " gave up")
            If ActiveStoryNPC.IsSneaking()
                ActiveStoryNPC.StartSneaking()
            EndIf
            Debug.SendAnimationEvent(ActiveStoryNPC, "sneakStop")
            StorageUtil.UnsetFloatValue(ActiveStoryNPC, "Intel_SneakStartTime")
            Int slot = Core.FindSlotByAgent(ActiveStoryNPC)
            If slot >= 0
                Core.ClearSlot(slot)
            EndIf
            Core.RemoveAllPackages(ActiveStoryNPC, false)
            CleanupStoryDispatch()
            return
        EndIf

        Float sneakDist = ActiveStoryNPC.GetDistance(player)
        Int sneakPhase = StorageUtil.GetIntValue(ActiveStoryNPC, "Intel_SneakPhase")

        ; Stalkers use TravelPackage_Stalk ? if phase 0 on load, reapply sneak package
        If ActiveStoryType == "stalker" && sneakPhase == 0
            ReapplyTravelPackage(ActiveStoryNPC)
            StorageUtil.SetIntValue(ActiveStoryNPC, "Intel_SneakPhase", 1)
            sneakPhase = 1
            Core.DebugMsg("Story [stalker]: " + ActiveStoryNPC.GetDisplayName() + " sneak package applied at " + sneakDist + "u")
        EndIf

        ; Ambushers enter sneak at approach distance (jog normally until then)
        If ActiveStoryType == "ambush" && sneakPhase == 0 && sneakDist <= SNEAK_APPROACH_DISTANCE
            If sneakDist > AMBUSH_CONFRONT_DISTANCE
                ActiveStoryNPC.StartSneaking()
                StorageUtil.SetIntValue(ActiveStoryNPC, "Intel_SneakPhase", 1)
                sneakPhase = 1
                Core.DebugMsg("Story [ambush]: " + ActiveStoryNPC.GetDisplayName() + " entered sneak at " + sneakDist + "u")
            Else
                ; Overshot sneak window ? confront immediately
                Core.DebugMsg("Story [ambush]: " + ActiveStoryNPC.GetDisplayName() + " overshot sneak at " + sneakDist + "u")
                OnAmbushConfront()
                return
            EndIf
        EndIf

        ; Phase 1+: resolve based on type
        If sneakPhase >= 1
            If ActiveStoryType == "ambush"
                ; Ambush: detected by engine stealth OR proximity failsafe (<400u) OR within confront distance
                If sneakDist <= AMBUSH_CONFRONT_DISTANCE && sneakDist > 0.0
                    OnAmbushConfront()
                    return
                EndIf
                If ActiveStoryNPC.IsDetectedBy(player) || sneakDist <= 400.0
                    Core.DebugMsg("Story [ambush]: " + ActiveStoryNPC.GetDisplayName() + " detected while sneaking at " + sneakDist + "u - confronting early")
                    OnAmbushConfront()
                    return
                EndIf
            Else
                ; Stalker: detected by engine stealth system OR proximity failsafe (<400u)
                If ActiveStoryNPC.IsDetectedBy(player) || sneakDist <= 400.0
                    OnStalkerDetected()
                    return
                EndIf

                ; Phase 1 (following): hold position when too close
                If sneakPhase == 1 && sneakDist <= STALKER_KEEP_DISTANCE
                    Core.RemoveAllPackages(ActiveStoryNPC, false)
                    StorageUtil.SetIntValue(ActiveStoryNPC, "Intel_SneakPhase", 2)
                    Core.DebugMsg("Story [stalker]: " + ActiveStoryNPC.GetDisplayName() + " holding at " + sneakDist + "u")
                EndIf

                ; Phase 2 (holding): resume following when player moves away
                If sneakPhase == 2 && sneakDist > STALKER_RESUME_DISTANCE
                    ReapplyTravelPackage(ActiveStoryNPC)
                    StorageUtil.SetIntValue(ActiveStoryNPC, "Intel_SneakPhase", 1)
                    Core.DebugMsg("Story [stalker]: " + ActiveStoryNPC.GetDisplayName() + " resuming follow at " + sneakDist + "u")
                EndIf
            EndIf
            ; Stay in sneak ? don't fall through to normal arrival check.
            ; Both resolve via detection (IsDetectedBy) or distance threshold.
            return
        EndIf
        ; Ambush phase 0 and far away: fall through to normal travel monitoring
    EndIf

    ; === Quest guide monitoring ===
    If ActiveStoryType == "quest_guide"
        ; Guide walk handled by CheckQuestGuide in OnUpdate
        return
    EndIf

    ; Determine arrival target based on story type
    Actor arrivalTarget = player
    If IsNPCToNPCType() && ActiveSecondNPC != None
        arrivalTarget = ActiveSecondNPC
    EndIf

    ; Pause arrival during combat (don't greet while fighting)
    If arrivalTarget == player && player.IsInCombat()
        return
    EndIf

    Float dist = ActiveStoryNPC.GetDistance(arrivalTarget)

    ; Arrived when within standard arrival distance
    If dist <= Core.ARRIVAL_DISTANCE && dist > 0.0
        OnStoryNPCArrived()
        return
    EndIf

    ; Same interior cell shortcut: only count as arrived if also within distance.
    ; Large interiors like Dragonsreach can have NPCs 3000+ units apart in the same cell.
    Cell targetCell = arrivalTarget.GetParentCell()
    Cell npcCell = ActiveStoryNPC.GetParentCell()
    If npcCell != None && targetCell != None && npcCell == targetCell
        If targetCell.IsInterior() && dist <= Core.ARRIVAL_DISTANCE && dist > 0.0
            OnStoryNPCArrived()
            return
        EndIf
    EndIf

    Int slot = Core.FindSlotByAgent(ActiveStoryNPC)
    If slot < 0
        return
    EndIf

    ; Off-screen: NPC not loaded ? leapfrog won't work, use time-based arrival
    If !ActiveStoryNPC.Is3DLoaded()
        If Core.HandleOffScreenTravel(slot, ActiveStoryNPC, arrivalTarget as ObjectReference)
            ; Off-screen arrival triggered ? teleport near target to become loaded
            ImmersiveTeleportToTarget(ActiveStoryNPC, arrivalTarget)
        EndIf
        return
    EndIf

    ; On-screen: stuck detection with leapfrog recovery
    Int stuckStatus = IntelEngine.CheckStuckStatus(ActiveStoryNPC, slot, Core.STUCK_DISTANCE_THRESHOLD)
    If stuckStatus == 1
        Core.SoftStuckRecovery(ActiveStoryNPC, slot, arrivalTarget as ObjectReference)
    ElseIf stuckStatus >= 3
        ImmersiveTeleportToTarget(ActiveStoryNPC, arrivalTarget)
    EndIf

    ; Timeout safety net
    Float taskStart = StorageUtil.GetFloatValue(ActiveStoryNPC, "Intel_TaskStartTime", 0.0)
    If taskStart > 0.0 && (Utility.GetCurrentGameTime() - taskStart) > MaxTravelDaysConfig
        Debug.Trace("[IntelEngine] StoryEngine: Travel timeout for " + ActiveStoryNPC.GetDisplayName())
        ImmersiveTeleportToTarget(ActiveStoryNPC, arrivalTarget)
    EndIf
EndFunction

; =============================================================================
; IMMERSIVE TELEPORT SYSTEM
; =============================================================================

Function ImmersiveTeleportToTarget(Actor npc, Actor target)
    Cell targetCell = target.GetParentCell()

    If targetCell != None && targetCell.IsInterior()
        Core.TeleportBehindPlayer(npc, TELEPORT_OFFSET_INTERIOR)
    Else
        Float[] offset = IntelEngine.GetOffsetBehind(target, TELEPORT_OFFSET_EXTERIOR)
        npc.MoveTo(target, offset[0], offset[1], 0.0, false)
    EndIf

    ReapplyTravelPackage(npc)
EndFunction

; =============================================================================
; ARRIVAL HANDLING
; =============================================================================

Function OnStoryNPCArrived()
    Core.DebugMsg("Story: " + ActiveStoryNPC.GetDisplayName() + " arrived! [" + ActiveStoryType + "]")

    ; === Ambush arrival (both stealth and charge variants) ===
    If ActiveStoryType == "ambush_charge" || ActiveStoryType == "ambush"
        OnAmbushConfront()
        return
    EndIf

    ; === Message courier arrival ===
    If ActiveStoryType == "message"
        OnMessageArrived()
        return
    EndIf

    ; === Quest courier/direct arrival ===
    If ActiveStoryType == "quest"
        OnQuestNPCArrived()
        return
    EndIf

    If IsNPCToNPCType() && ActiveSecondNPC != None
        ; NPC-to-NPC: face each other and trigger dialogue
        ActiveStoryNPC.SetLookAt(ActiveSecondNPC)
        ActiveSecondNPC.SetLookAt(ActiveStoryNPC)
        Utility.Wait(0.5)
        Core.SendTaskNarration(ActiveStoryNPC, BuildInteractionSummary(ActiveStoryNPC, ActiveNarration, ActiveSecondNPC), ActiveSecondNPC)
    Else
        ; seek_player / informant: narrate on arrival (single narration, no early phase)
        ActiveStoryNPC.SetLookAt(Game.GetPlayer())
        Core.SendTaskNarration(ActiveStoryNPC, ActiveNarration, Game.GetPlayer())
    EndIf

    ; Anti-repetition (capture before cleanup)
    String npcName = ActiveStoryNPC.GetDisplayName()
    String eventSummary = ActiveStoryType + ": " + npcName + " -- " + ActiveNarration
    AddRecentStoryEvent(eventSummary)

    ; Store ref before cleanup clears it
    Actor arrivedNPC = ActiveStoryNPC
    Actor secondNPC = ActiveSecondNPC
    Bool isNpcToNpc = IsNPCToNPCType()

    ; Sandbox near arrival target (NPC-to-NPC lingers near second NPC, solo lingers near player)
    ObjectReference lingerTarget = Game.GetPlayer() as ObjectReference
    If isNpcToNpc && secondNPC != None
        lingerTarget = secondNPC as ObjectReference
    EndIf
    FinishArrivalWithLinger(arrivedNPC, lingerTarget)
EndFunction

; =============================================================================
; MESSAGE COURIER SYSTEM
; =============================================================================

Function HandleMessageDispatch(Actor npc, String narration, String response)
    String senderName = ExtractJsonField(response, "sender")
    String msgContent = ExtractJsonField(response, "msgContent")
    String destination = ExtractJsonField(response, "destination")
    String meetTime = ExtractJsonField(response, "meetTime")

    ; Inject fact on sender -- they remember sending the message
    If senderName != ""
        Actor senderNPC = IntelEngine.FindNPCByName(senderName)
        If senderNPC != None
            Core.InjectFact(senderNPC, "sent word to " + Game.GetPlayer().GetDisplayName() + ": " + msgContent)
        EndIf
    EndIf

    ; Inject purpose fact on messenger (survives narration failure)
    String playerName = Game.GetPlayer().GetDisplayName()
    If senderName != "" && senderName != npc.GetDisplayName()
        Core.InjectFact(npc, "was sent to deliver a message from " + senderName + " for " + playerName)
    Else
        Core.InjectFact(npc, "came to deliver an important message for " + playerName)
    EndIf

    ; Store for arrival narration
    StorageUtil.SetStringValue(npc, "Intel_MessageSender", senderName)
    StorageUtil.SetStringValue(npc, "Intel_MessageContent", msgContent)
    StorageUtil.SetStringValue(npc, "Intel_MessageDest", destination)
    StorageUtil.SetStringValue(npc, "Intel_MessageTime", meetTime)

    ActiveStoryType = "message"
    DispatchToTarget(npc, Game.GetPlayer(), narration, "story")
EndFunction

Function OnMessageArrived()
    String senderName = StorageUtil.GetStringValue(ActiveStoryNPC, "Intel_MessageSender")
    String msgContent = StorageUtil.GetStringValue(ActiveStoryNPC, "Intel_MessageContent")
    String msgDest = StorageUtil.GetStringValue(ActiveStoryNPC, "Intel_MessageDest")
    String meetTime = StorageUtil.GetStringValue(ActiveStoryNPC, "Intel_MessageTime")

    ; Narration
    String fullNarration = ""
    If senderName != "" && senderName != ActiveStoryNPC.GetDisplayName()
        fullNarration = "delivered a message from " + senderName + ": " + msgContent
    Else
        fullNarration = ActiveNarration
    EndIf
    Core.SendTaskNarration(ActiveStoryNPC, fullNarration, Game.GetPlayer())

    ; Schedule meeting on SENDER if destination provided
    If msgDest != "" && Schedule != None
        Actor senderForMeeting = None
        If senderName != ""
            senderForMeeting = IntelEngine.FindNPCByName(senderName)
        EndIf
        If senderForMeeting != None
            String timeCondition = meetTime
            If timeCondition == ""
                timeCondition = "evening"
            EndIf
            Schedule.ScheduleMeeting(senderForMeeting, msgDest, timeCondition)
        EndIf
    EndIf

    ; Anti-repetition
    AddRecentStoryEvent("message: " + ActiveStoryNPC.GetDisplayName() + " -- " + fullNarration)

    FinishArrivalWithLinger(ActiveStoryNPC, Game.GetPlayer() as ObjectReference)
EndFunction

; =============================================================================
; AMBUSH + STALKER SYSTEM
; =============================================================================

Function HandleAmbushStalkerDispatch(Actor npc, String narration, String response, String storyType)
    String senderName = ExtractJsonField(response, "sender")
    String playerName = Game.GetPlayer().GetDisplayName()

    ; 1. Inject motivation as persistent memory (SkyrimNet sees this in bio)
    Core.SendPersistentMemory(npc, npc, npc.GetDisplayName() + " " + narration)

    ; 2. Inject narration as current-state fact (includes WHO and WHY from LLM)
    Core.InjectFact(npc, narration)

    ; 3. Inject fact on sender (who ordered/encouraged this)
    If senderName != ""
        Actor senderNPC = IntelEngine.FindNPCByName(senderName)
        If senderNPC != None
            If storyType == "ambush"
                Core.InjectFact(senderNPC, "sent " + npc.GetDisplayName() + " to ambush " + playerName)
            Else
                Core.InjectFact(senderNPC, "encouraged " + npc.GetDisplayName() + " to follow " + playerName)
            EndIf
        EndIf
    EndIf

    ; Ambush variety: 50% stealth (stalk package) vs 50% charge (sprint + attack)
    If storyType == "ambush"
        If Utility.RandomInt(0, 1) == 1
            storyType = "ambush_charge"
            Core.DebugMsg("Story [ambush]: " + npc.GetDisplayName() + " choosing aggressive charge approach")
        Else
            Core.DebugMsg("Story [ambush]: " + npc.GetDisplayName() + " choosing stealthy approach")
        EndIf
    EndIf

    ActiveStoryType = storyType
    DispatchToTarget(npc, Game.GetPlayer(), narration, "story")

    ; Stalkers and stealth ambushers use TravelPackage_Stalk (Always Sneak flag)
    If storyType == "stalker" || storyType == "ambush"
        StorageUtil.SetIntValue(npc, "Intel_SneakPhase", 1)
        ReapplyTravelPackage(npc)
        Core.DebugMsg("Story [" + storyType + "]: " + npc.GetDisplayName() + " dispatched with stalk package")
    EndIf

    ; Track sneak start time for timeout (stealth ambush and stalker only)
    If storyType == "ambush" || storyType == "stalker"
        StorageUtil.SetFloatValue(npc, "Intel_SneakStartTime", Utility.GetCurrentRealTime())
    EndIf
EndFunction

Function OnAmbushConfront()
    If ActiveStoryNPC.IsSneaking()
        ActiveStoryNPC.StartSneaking()
    EndIf

    ; Replace current-state fact with confrontation fact
    Core.InjectFact(ActiveStoryNPC, "confronted " + Game.GetPlayer().GetDisplayName() + " with weapon drawn, ready to attack")

    ; Narrate confrontation -- triggers SkyrimNet dialogue with hostile context
    Core.SendTaskNarration(ActiveStoryNPC, ActiveNarration, Game.GetPlayer())
    Utility.Wait(1.5)

    ; Make essential so they bleedout instead of dying -- gives yield a chance to fire
    ActiveStoryNPC.GetActorBase().SetEssential(true)

    ; Start combat -- NPC commits to the fight
    ActiveStoryNPC.SetActorValue("Confidence", 4)
    ActiveStoryNPC.StartCombat(Game.GetPlayer())

    ; Transition to combat monitoring (DON'T cleanup yet -- monitor for yield)
    ActiveStoryType = "ambush_combat"
    StorageUtil.SetFloatValue(ActiveStoryNPC, "Intel_CombatStartTime", Utility.GetCurrentRealTime())
    AddRecentStoryEvent("ambush: " + ActiveStoryNPC.GetDisplayName() + " -- " + ActiveNarration)
EndFunction

Function CheckAmbushCombat()
    {Monitor ambush combat: yield when NPC health drops below threshold.}
    If ActiveStoryType != "ambush_combat" || ActiveStoryNPC == None
        return
    EndIf

    ; Timeout: if combat runs too long AND player is far away (bugged state), force end
    Float combatStart = StorageUtil.GetFloatValue(ActiveStoryNPC, "Intel_CombatStartTime", 0.0)
    If combatStart > 0.0 && (Utility.GetCurrentRealTime() - combatStart) > SNEAK_TIMEOUT_SECONDS && Core.ShouldReleaseLinger(ActiveStoryNPC)
        Core.DebugMsg("Story [ambush_combat]: " + ActiveStoryNPC.GetDisplayName() + " combat timed out - forcing end")
        ActiveStoryNPC.GetActorBase().SetEssential(false)
        ActiveStoryNPC.StopCombat()
        ActiveStoryNPC.StopCombatAlarm()
        ActiveStoryNPC.SetActorValue("Aggression", 0)
        ActiveStoryNPC.SetActorValue("Confidence", 2)
        StorageUtil.UnsetFloatValue(ActiveStoryNPC, "Intel_CombatStartTime")
        Actor endedNPC = ActiveStoryNPC
        FinishArrivalWithLinger(endedNPC, Game.GetPlayer() as ObjectReference)
        return
    EndIf

    If ActiveStoryNPC.IsDead()
        ActiveStoryNPC.GetActorBase().SetEssential(false)
        Int slot = Core.FindSlotByAgent(ActiveStoryNPC)
        If slot >= 0
            Core.ClearSlot(slot)
        EndIf
        CleanupStoryDispatch()
        return
    EndIf

    ; Bleedout = essential NPC hit 0 HP -- this is the yield trigger
    If ActiveStoryNPC.IsBleedingOut()
        OnAmbushYield()
        return
    EndIf

    If !ActiveStoryNPC.IsInCombat()
        ; Combat ended naturally (player ran away, guards intervened, etc.)
        ActiveStoryNPC.GetActorBase().SetEssential(false)
        ActiveStoryNPC.SetActorValue("Aggression", 0)
        ActiveStoryNPC.SetActorValue("Confidence", 2)
        Actor endedNPC = ActiveStoryNPC
        FinishArrivalWithLinger(endedNPC, Game.GetPlayer() as ObjectReference)
        return
    EndIf
EndFunction

Function OnAmbushYield()
    {Ambusher is beaten down and yields -- stops combat, linger for dialogue.}
    String playerName = Game.GetPlayer().GetDisplayName()

    ; Remove essential -- player can now kill them if they choose
    ActiveStoryNPC.GetActorBase().SetEssential(false)

    ; Stop fighting
    ActiveStoryNPC.StopCombat()
    ActiveStoryNPC.StopCombatAlarm()
    ActiveStoryNPC.SetActorValue("Aggression", 0)
    ActiveStoryNPC.SetActorValue("Confidence", 1)

    ; Restore health so they can stand up from bleedout
    ActiveStoryNPC.RestoreActorValue("Health", 50.0)

    ; Inject yield fact -- SkyrimNet sees this and generates begging/reasoning dialogue
    Core.InjectFact(ActiveStoryNPC, "was beaten in combat by " + playerName + " and yielded, begging for mercy")

    ; Narrate the yield -- triggers SkyrimNet dialogue
    Core.SendTaskNarration(ActiveStoryNPC, "dropped to one knee and yielded to " + playerName + ", exhausted and beaten", Game.GetPlayer())

    Core.DebugMsg("Story [ambush]: " + ActiveStoryNPC.GetDisplayName() + " yielded at " + (ActiveStoryNPC.GetActorValuePercentage("Health") * 100.0) + "% health")

    ; Save ref, then sandbox + linger for post-combat dialogue
    Actor yieldedNPC = ActiveStoryNPC
    FinishArrivalWithLinger(yieldedNPC, Game.GetPlayer() as ObjectReference)
EndFunction

Function OnStalkerDetected()
    {Stalker detected by player: stop sneaking, narrate caught, linger for dialogue.
    No flee phase — TranslateTo ignores navmesh and breaks immersion.}
    String playerName = Game.GetPlayer().GetDisplayName()
    String npcName = ActiveStoryNPC.GetDisplayName()

    ; Exit sneak: toggle state off + force animation event so the NPC stands up
    If ActiveStoryNPC.IsSneaking()
        ActiveStoryNPC.StartSneaking()
    EndIf
    Debug.SendAnimationEvent(ActiveStoryNPC, "sneakStop")

    ; Caught fact for SkyrimNet dialogue context (flustered/embarrassed)
    Core.InjectFact(ActiveStoryNPC, "was caught secretly following " + playerName)
    Core.SendTaskNarration(ActiveStoryNPC, ActiveNarration, Game.GetPlayer())

    ; Persistent memory
    Core.SendPersistentMemory(ActiveStoryNPC, Game.GetPlayer(), npcName + " was caught secretly following " + playerName)

    AddRecentStoryEvent("stalker: " + npcName + " -- caught")

    ; Save ref before cleanup clears it
    Actor caughtNPC = ActiveStoryNPC

    ; Same arrival pattern as every other type: sandbox + linger + release when player walks away
    FinishArrivalWithLinger(caughtNPC, Game.GetPlayer() as ObjectReference)

    Core.DebugMsg("Story [stalker]: " + npcName + " caught - lingering for confrontation")
EndFunction

; =============================================================================
; QUEST SYSTEM
; =============================================================================

Function HandleQuestDispatch(Actor npc, String narration, String response)
    If QuestActive
        Core.DebugMsg("Story DM: quest rejected -- one already active")
        return
    EndIf

    String senderName = ExtractJsonField(response, "sender")
    String msgContent = ExtractJsonField(response, "msgContent")
    String questLocationStr = ExtractJsonField(response, "questLocation")
    String enemyType = ExtractJsonField(response, "enemyType")

    If questLocationStr == "" || enemyType == ""
        Core.DebugMsg("Story DM: quest missing questLocation or enemyType")
        return
    EndIf

    ObjectReference questDest = IntelEngine.ResolveAnyDestination(npc, questLocationStr)
    If questDest == None
        Core.DebugMsg("Story DM: quest location '" + questLocationStr + "' could not be resolved")
        return
    EndIf

    ; Pre-check slot availability BEFORE setting quest state.
    ; Without this, a failed dispatch orphans the quest (QuestActive=true, no courier).
    If Core.FindFreeAgentSlot() < 0
        Core.DebugMsg("Story DM: quest rejected -- no free slots")
        return
    EndIf

    ; Determine quest giver
    Actor questGiverActor = npc
    If senderName != ""
        Actor senderActor = IntelEngine.FindNPCByName(senderName)
        If senderActor != None
            questGiverActor = senderActor
        EndIf
    EndIf

    Core.InjectFact(questGiverActor, "asked " + Game.GetPlayer().GetDisplayName() + " for help: " + msgContent)

    ; Inject purpose fact on courier (when courier != quest giver, courier needs own context)
    If questGiverActor != npc
        Core.InjectFact(npc, "was sent to deliver a plea for help from " + questGiverActor.GetDisplayName() + " about " + enemyType + " trouble near " + questLocationStr)
    EndIf

    ; Set up quest state
    QuestActive = true
    QuestGiver = questGiverActor
    QuestLocation = questDest
    QuestEnemyType = enemyType
    QuestLocationName = questLocationStr
    QuestEnemiesSpawned = false
    QuestGuideActive = false
    QuestGuideWaiting = false
    QuestStartTime = Utility.GetCurrentGameTime()
    QuestSpawnCount = 0

    StorageUtil.SetStringValue(npc, "Intel_MessageSender", senderName)
    StorageUtil.SetStringValue(npc, "Intel_MessageContent", msgContent)
    StorageUtil.SetStringValue(npc, "Intel_QuestLocation", questLocationStr)

    ActiveStoryType = "quest"
    DispatchToTarget(npc, Game.GetPlayer(), narration, "story")
EndFunction

Function OnQuestNPCArrived()
    String senderName = StorageUtil.GetStringValue(ActiveStoryNPC, "Intel_MessageSender")
    String msgContent = StorageUtil.GetStringValue(ActiveStoryNPC, "Intel_MessageContent")
    String questLoc = StorageUtil.GetStringValue(ActiveStoryNPC, "Intel_QuestLocation")

    ; Clean up keys immediately (read into locals above, no longer needed on NPC)
    StorageUtil.UnsetStringValue(ActiveStoryNPC, "Intel_MessageSender")
    StorageUtil.UnsetStringValue(ActiveStoryNPC, "Intel_MessageContent")
    StorageUtil.UnsetStringValue(ActiveStoryNPC, "Intel_QuestLocation")

    ; Narrate
    String fullNarration = ""
    If senderName != "" && senderName != ActiveStoryNPC.GetDisplayName()
        fullNarration = "delivered word from " + senderName + ": " + msgContent
    Else
        fullNarration = ActiveNarration
    EndIf
    Core.SendTaskNarration(ActiveStoryNPC, fullNarration, Game.GetPlayer())

    Bool isDirect = (senderName == "" || senderName == ActiveStoryNPC.GetDisplayName())

    If isDirect
        ; Direct approach: offer to guide (unless NPC is a follower — SkyrimNet's
        ; FollowPlayer package conflicts with our travel package, making them
        ; follow the player instead of leading to the destination)
        ; Prevent re-entry: Utility.Wait is latent (yields thread), so OnUpdate
        ; keeps firing during the wait. IsActive=false stops CheckStoryNPCArrival
        ; from calling OnQuestNPCArrived again. BeginQuestGuide/FinishArrivalWithLinger
        ; handle restoring IsActive as needed.
        IsActive = false
        ; Delay before quest prompt so NPC has time to talk
        Utility.Wait(15.0)
        ; Bail out if NPC became invalid during the wait
        If ActiveStoryNPC == None || ActiveStoryNPC.IsDead() || ActiveStoryNPC.IsInCombat()
            CleanupQuest()
            CleanupStoryDispatch()
            return
        EndIf
        ; Bail out if slot was externally cleared (console, MCM)
        If Core.FindSlotByAgent(ActiveStoryNPC) < 0
            CleanupQuest()
            CleanupStoryDispatch()
            return
        EndIf
        String choice = ""
        If ActiveStoryNPC.IsPlayerTeammate()
            choice = SkyMessage.Show(ActiveStoryNPC.GetDisplayName() + " tells you about trouble near " + questLoc + ".", "I'll check it out", "Not interested")
            If choice == "Not interested"
                ; Fall through to cancel below
            Else
                ; "I'll check it out" — same as "I'll go alone"
                PlaceQuestMarker()
                Core.SendTaskNarration(ActiveStoryNPC, "was told that " + Game.GetPlayer().GetDisplayName() + " would handle it", Game.GetPlayer())
                Core.NotifyPlayer("Quest: " + msgContent + " [" + questLoc + "]")
                AddRecentStoryEvent("quest: " + QuestEnemyType + " at " + questLoc)
                ; Clear type so CleanupStoryDispatch doesn't wipe quest state
                ActiveStoryType = ""
                FinishArrivalWithLinger(ActiveStoryNPC, Game.GetPlayer() as ObjectReference)
                return
            EndIf
        Else
            choice = SkyMessage.Show(ActiveStoryNPC.GetDisplayName() + " offers to guide you to " + questLoc + ".", "Lead the way", "I'll go alone", "Not interested")
        EndIf
        If choice == "Lead the way"
            PlaceQuestMarker()
            AddRecentStoryEvent("quest: " + ActiveStoryNPC.GetDisplayName() + " guiding to " + questLoc)
            BeginQuestGuide(ActiveStoryNPC)
            return
        ElseIf choice == "Not interested"
            ; Cancel quest entirely
            Core.SendTaskNarration(ActiveStoryNPC, "was told that " + Game.GetPlayer().GetDisplayName() + " wasn't interested in helping", Game.GetPlayer())
            RemoveQuestMarker()
            CleanupQuest()
            FinishArrivalWithLinger(ActiveStoryNPC, Game.GetPlayer() as ObjectReference)
            return
        EndIf
        ; "I'll go alone" -- narrate, player goes with map marker
        Core.SendTaskNarration(ActiveStoryNPC, "was told that " + Game.GetPlayer().GetDisplayName() + " would handle it alone", Game.GetPlayer())
        Core.NotifyPlayer("Quest: " + msgContent + " [" + questLoc + "]")
    Else
        ; Courier mode
        Core.NotifyPlayer("Quest: " + msgContent + " [" + questLoc + "]")
    EndIf

    ; Place marker. Covers "I'll go alone" + courier paths.
    PlaceQuestMarker()
    AddRecentStoryEvent("quest: " + QuestEnemyType + " at " + questLoc)

    ; Clear type so CleanupStoryDispatch doesn't wipe quest state
    ActiveStoryType = ""
    FinishArrivalWithLinger(ActiveStoryNPC, Game.GetPlayer() as ObjectReference)
EndFunction

; =============================================================================
; QUEST GUIDE SYSTEM
; =============================================================================

Function BeginQuestGuide(Actor guideNPC)
    {NPC jogs WITH the player to the quest location.}
    QuestGuideNPC = guideNPC
    QuestGuideActive = true
    QuestGuideWaiting = false
    QuestGuideStartTime = Utility.GetCurrentGameTime()

    ; Transition to guide mode (don't call full CleanupStoryDispatch)
    ActiveStoryType = "quest_guide"
    ActiveStoryNPC = guideNPC
    IsActive = true

    ; Nuke ALL overrides (SkyrimNet follow/talk packages from conversation)
    ; so the jog package is the only one active.
    Core.DismissFollowerForTask(guideNPC)
    PO3_SKSEFunctions.SetLinkedRef(guideNPC, QuestLocation, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(guideNPC, Core.TravelPackage_Jog, Core.PRIORITY_TRAVEL, 1)
    Utility.Wait(0.5)
    guideNPC.EvaluatePackage()

    ; Initialize stuck tracking for the guide phase (new travel target)
    Int slot = Core.FindSlotByAgent(guideNPC)
    If slot >= 0
        Core.InitializeStuckTrackingForSlot(slot, guideNPC)
        Core.InitOffScreenTracking(slot, guideNPC, QuestLocation)
    EndIf

    Float guideDist = 0.0
    If QuestLocation.Is3DLoaded() && guideNPC.Is3DLoaded()
        guideDist = guideNPC.GetDistance(QuestLocation)
    EndIf
    Core.DebugMsg("Story [quest_guide]: " + guideNPC.GetDisplayName() + " guiding player to " + QuestLocationName + " (dist=" + guideDist + ", loaded=" + QuestLocation.Is3DLoaded() + ")")
    RegisterForSingleUpdate(MONITOR_INTERVAL)
EndFunction

Function CheckQuestGuide()
    {Monitor guide NPC: wait if player falls behind, resume when close, trigger spawn on arrival.}
    If !QuestGuideActive || QuestGuideNPC == None
        return
    EndIf

    ; Guide timeout: if walking for too long, give up and let player use map marker
    Float guideElapsed = (Utility.GetCurrentGameTime() - QuestGuideStartTime) * 24.0
    If guideElapsed > QUEST_GUIDE_TIMEOUT_HOURS
        Core.DebugMsg("Story [quest_guide]: guide timed out after " + guideElapsed + " hours")
        Core.RemoveAllPackages(QuestGuideNPC, false)
        Int slot = Core.FindSlotByAgent(QuestGuideNPC)
        If slot >= 0
            Core.ClearSlot(slot)
        EndIf
        QuestGuideActive = false
        QuestGuideWaiting = false
        ActiveStoryType = ""
        IsActive = false
        StartStoryLinger(QuestGuideNPC)
        return
    EndIf

    Actor player = Game.GetPlayer()
    Int slot = Core.FindSlotByAgent(QuestGuideNPC)

    ; Off-screen handling: if guide is unloaded, use off-screen travel logic
    If !QuestGuideNPC.Is3DLoaded()
        If slot >= 0 && Core.HandleOffScreenTravel(slot, QuestGuideNPC, QuestLocation)
            ; Off-screen arrival: teleport near quest location
            Float[] offset = IntelEngine.GetOffsetBehind(QuestLocation, TELEPORT_OFFSET_INTERIOR)
            QuestGuideNPC.MoveTo(QuestLocation, offset[0], offset[1], 0.0, false)
            Core.RemoveAllPackages(QuestGuideNPC, false)
            PO3_SKSEFunctions.SetLinkedRef(QuestGuideNPC, QuestLocation, Core.IntelEngine_TravelTarget)
            ActorUtil.AddPackageOverride(QuestGuideNPC, Core.TravelPackage_Jog, Core.PRIORITY_TRAVEL, 1)
            QuestGuideNPC.EvaluatePackage()
            Core.DebugMsg("Story [quest_guide]: off-screen arrival near " + QuestLocationName)
        EndIf
        return
    EndIf

    Float distToPlayer = QuestGuideNPC.GetDistance(player)

    ; Check if guide arrived at quest location (distance + same-cell fallback)
    Bool guideArrived = false
    If QuestLocation.Is3DLoaded()
        Float distToDest = QuestGuideNPC.GetDistance(QuestLocation)
        If distToDest <= Core.ARRIVAL_DISTANCE
            guideArrived = true
        EndIf
    EndIf
    ; Fallback: same parent cell as quest location marker (handles underground/interior markers)
    If !guideArrived && QuestGuideNPC.GetParentCell() != None
        Cell questCell = QuestLocation.GetParentCell()
        If questCell != None && QuestGuideNPC.GetParentCell() == questCell
            guideArrived = true
            Core.DebugMsg("Story [quest_guide]: same-cell arrival fallback triggered")
        EndIf
    EndIf
    ; Fallback: guide is in the same BGSLocation (or child) as the quest marker
    If !guideArrived
        Location questLoc = QuestLocation.GetCurrentLocation()
        If questLoc != None && QuestGuideNPC.IsInLocation(questLoc)
            guideArrived = true
            Core.DebugMsg("Story [quest_guide]: BGSLocation arrival fallback triggered")
        EndIf
    EndIf
    If guideArrived
        OnQuestGuideArrived()
        return
    EndIf

    ; Stuck detection (same as normal story travel)
    If slot >= 0 && !QuestGuideWaiting
        Int stuckStatus = IntelEngine.CheckStuckStatus(QuestGuideNPC, slot, Core.STUCK_DISTANCE_THRESHOLD)
        If stuckStatus == 1
            Core.SoftStuckRecovery(QuestGuideNPC, slot, QuestLocation)
        ElseIf stuckStatus >= 3
            ; Hard stuck: teleport near quest location
            Float[] offset = IntelEngine.GetOffsetBehind(QuestLocation, TELEPORT_OFFSET_INTERIOR)
            QuestGuideNPC.MoveTo(QuestLocation, offset[0], offset[1], 0.0, false)
            Core.RemoveAllPackages(QuestGuideNPC, false)
            PO3_SKSEFunctions.SetLinkedRef(QuestGuideNPC, QuestLocation, Core.IntelEngine_TravelTarget)
            ActorUtil.AddPackageOverride(QuestGuideNPC, Core.TravelPackage_Jog, Core.PRIORITY_TRAVEL, 1)
            QuestGuideNPC.EvaluatePackage()
            Core.DebugMsg("Story [quest_guide]: hard stuck - teleported near " + QuestLocationName)
        EndIf
    EndIf

    ; Wait/resume logic: if player falls behind, guide stops in place and waits
    If !QuestGuideWaiting && distToPlayer > QUEST_GUIDE_WAIT_DIST
        QuestGuideWaiting = true
        ActorUtil.RemovePackageOverride(QuestGuideNPC, Core.TravelPackage_Jog)
        ; Sandbox at NPC's OWN position (NOT the player -- linking to player makes the NPC
        ; follow indefinitely because the sandbox center moves with the player)
        PO3_SKSEFunctions.SetLinkedRef(QuestGuideNPC, QuestGuideNPC as ObjectReference, Core.IntelEngine_TravelTarget)
        ActorUtil.AddPackageOverride(QuestGuideNPC, Core.SandboxNearPlayerPackage, Core.PRIORITY_SANDBOX, 1)
        QuestGuideNPC.EvaluatePackage()
        Core.DebugMsg("Story [quest_guide]: waiting for player (dist=" + distToPlayer + ")")
    ElseIf QuestGuideWaiting && distToPlayer <= QUEST_GUIDE_RESUME_DIST
        QuestGuideWaiting = false
        ActorUtil.RemovePackageOverride(QuestGuideNPC, Core.SandboxNearPlayerPackage)
        PO3_SKSEFunctions.SetLinkedRef(QuestGuideNPC, QuestLocation, Core.IntelEngine_TravelTarget)
        ActorUtil.AddPackageOverride(QuestGuideNPC, Core.TravelPackage_Jog, Core.PRIORITY_TRAVEL, 1)
        QuestGuideNPC.EvaluatePackage()
        Core.DebugMsg("Story [quest_guide]: player caught up, resuming")
    EndIf
EndFunction

Function OnQuestGuideArrived()
    Core.DebugMsg("Story [quest_guide]: arrived at " + QuestLocationName)

    ; Do NOT spawn enemies here. The guide may arrive while the player is still
    ; outside (BGSLocation fallback triggers on exterior). Spawning in an unloaded
    ; interior cell creates temp refs that get cleaned up by the engine.
    ; CheckQuestProximity handles spawning when the player actually enters the area.

    ; Clear slot FIRST (removes travel packages + linked refs), then add sandbox.
    ; ClearSlot calls RemoveAllPackages, so adding sandbox before it would be undone.
    QuestGuideActive = false
    Int slot = Core.FindSlotByAgent(QuestGuideNPC)
    If slot >= 0
        Core.ClearSlot(slot)
    EndIf
    ActiveStoryType = ""
    IsActive = false

    ; NOW add sandbox near quest location (after ClearSlot wiped travel packages)
    PO3_SKSEFunctions.SetLinkedRef(QuestGuideNPC, QuestGuideNPC as ObjectReference, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(QuestGuideNPC, Core.SandboxNearPlayerPackage, Core.PRIORITY_SANDBOX, 1)
    Utility.Wait(0.1)
    QuestGuideNPC.EvaluatePackage()

    ; Ensure building access: if guide is inside an interior, unlock for player
    Core.EnsureBuildingAccess(QuestGuideNPC)
    StartStoryLinger(QuestGuideNPC)
    RegisterForSingleUpdate(MONITOR_INTERVAL)
EndFunction

; =============================================================================
; QUEST PROXIMITY + SPAWN + COMPLETION
; =============================================================================

Function CheckQuestProximity()
    If !QuestActive || QuestLocation == None || QuestGuideActive
        return
    EndIf

    If !QuestEnemiesSpawned
        Bool atQuestArea = false
        If QuestLocation.Is3DLoaded()
            atQuestArea = true
        EndIf
        ; Fallback: player is in the same cell as the quest location marker
        If !atQuestArea
            Cell questCell = QuestLocation.GetParentCell()
            Cell playerCell = Game.GetPlayer().GetParentCell()
            If questCell != None && playerCell != None && questCell == playerCell
                atQuestArea = true
                Core.DebugMsg("Story [quest]: same-cell spawn fallback triggered")
            EndIf
        EndIf
        ; Fallback: player is in the same BGSLocation (or child) as the quest marker
        ; Handles interior dungeons where QuestLocation is an exterior MapMarkerREF
        If !atQuestArea
            Location questLoc = QuestLocation.GetCurrentLocation()
            If questLoc != None && Game.GetPlayer().IsInLocation(questLoc)
                atQuestArea = true
                Core.DebugMsg("Story [quest]: BGSLocation spawn fallback triggered")
            EndIf
        EndIf
        If atQuestArea
            SpawnQuestEnemies()
        EndIf
    Else
        If AreAllQuestEnemiesDead()
            OnQuestComplete()
        EndIf
    EndIf
EndFunction

Function SpawnQuestEnemies()
    If QuestEnemiesSpawned
        return
    EndIf

    QuestSpawnAttempts += 1

    ; Spawn near player if in interior (QuestLocation is likely an exterior MapMarkerREF)
    Actor player = Game.GetPlayer()
    ObjectReference spawnAnchor = QuestLocation
    If player.IsInInterior()
        spawnAnchor = player
        Core.DebugMsg("Story [quest]: spawning near player (interior)")
    EndIf

    Actor[] spawnedActors = IntelEngine.SpawnQuestEnemies(spawnAnchor, QuestEnemyType)
    QuestSpawnCount = spawnedActors.Length

    If QuestSpawnCount > 0
        ; Persist Actor refs in StorageUtil FormList (survives save/load)
        Int i = 0
        While i < QuestSpawnCount
            StorageUtil.FormListAdd(player, "Intel_QuestSpawnedNPCs", spawnedActors[i])
            i += 1
        EndWhile
        QuestEnemiesSpawned = true
        Core.DebugMsg("Story [quest]: Spawned " + QuestSpawnCount + " " + QuestEnemyType + " at " + QuestLocationName)
    ElseIf QuestSpawnAttempts >= 3
        ; Safety net: after 3 failed spawn attempts, auto-complete so quest doesn't hang forever
        Core.DebugMsg("Story [quest]: spawn failed after 3 attempts, auto-completing")
        QuestEnemiesSpawned = true
        OnQuestComplete()
    Else
        Core.DebugMsg("Story [quest]: Failed to spawn " + QuestEnemyType + " (attempt " + QuestSpawnAttempts + "/3)")
    EndIf
EndFunction

Bool Function AreAllQuestEnemiesDead()
    Actor player = Game.GetPlayer()
    Int count = StorageUtil.FormListCount(player, "Intel_QuestSpawnedNPCs")
    If count == 0
        return false
    EndIf
    Int i = 0
    While i < count
        Actor spawned = StorageUtil.FormListGet(player, "Intel_QuestSpawnedNPCs", i) as Actor
        If spawned != None && !spawned.IsDead()
            return false
        EndIf
        i += 1
    EndWhile
    return true
EndFunction

Function OnQuestComplete()
    Core.DebugMsg("Story [quest]: Completed at " + QuestLocationName + "!")
    Core.NotifyPlayer("Quest completed!")

    String playerName = Game.GetPlayer().GetDisplayName()
    If QuestGiver != None
        Core.InjectFact(QuestGiver, "learned that " + playerName + " dealt with the " + QuestEnemyType + " threat at " + QuestLocationName)
    EndIf

    ; Guide NPC also learns about the outcome (if different from quest giver)
    If QuestGuideNPC != None && QuestGuideNPC != QuestGiver
        Core.InjectFact(QuestGuideNPC, "witnessed " + playerName + " clear the " + QuestEnemyType + " at " + QuestLocationName)
    EndIf

    RemoveQuestMarker()
    CleanupQuest()
EndFunction

Function CheckQuestExpiry()
    If !QuestActive || QuestStartTime <= 0.0
        return
    EndIf
    Float elapsed = Utility.GetCurrentGameTime() - QuestStartTime
    If elapsed > QUEST_EXPIRY_DAYS
        Core.DebugMsg("Story [quest]: Expired after " + QUEST_EXPIRY_DAYS + " days")
        If QuestGiver != None
            Core.InjectFact(QuestGiver, "grew disappointed that " + Game.GetPlayer().GetDisplayName() + " never dealt with the " + QuestEnemyType + " threat at " + QuestLocationName)
        EndIf
        RemoveQuestMarker()
        CleanupQuest()
    EndIf
EndFunction

Function CleanupQuest()
    String eventText = "quest: " + QuestEnemyType + " at " + QuestLocationName
    StorageUtil.FormListClear(Game.GetPlayer(), "Intel_QuestSpawnedNPCs")

    If QuestGuideNPC != None
        Int slot = Core.FindSlotByAgent(QuestGuideNPC)
        If slot >= 0
            Core.ClearSlot(slot)
        EndIf
        Core.RemoveAllPackages(QuestGuideNPC, false)
    EndIf

    QuestActive = false
    QuestGiver = None
    QuestGuideNPC = None
    QuestGuideActive = false
    QuestGuideWaiting = false
    QuestGuideStartTime = 0.0
    QuestLocation = None
    QuestEnemyType = ""
    QuestLocationName = ""
    QuestEnemiesSpawned = false
    QuestSpawnCount = 0
    QuestSpawnAttempts = 0
    QuestStartTime = 0.0

    AddRecentStoryEvent(eventText)
EndFunction

; =============================================================================
; QUEST MAP MARKER
; =============================================================================

Function PlaceQuestMarker()
    ; Runtime recovery: Auto properties added after quest start aren't filled on
    ; existing saves. Iterate quest aliases, skip known agent/target/player aliases.
    If QuestTargetAlias == None
        Int i = GetNumAliases() - 1
        While i >= 1 && QuestTargetAlias == None
            ReferenceAlias ra = GetAlias(i) as ReferenceAlias
            If ra != None \
                && ra != Core.AgentAlias00 && ra != Core.AgentAlias01 \
                && ra != Core.AgentAlias02 && ra != Core.AgentAlias03 \
                && ra != Core.AgentAlias04 \
                && ra != Core.TargetAlias00 && ra != Core.TargetAlias01 \
                && ra != Core.TargetAlias02 && ra != Core.TargetAlias03 \
                && ra != Core.TargetAlias04
                QuestTargetAlias = ra
                Core.DebugMsg("Story [quest]: Recovered QuestTargetAlias at alias index " + i)
            EndIf
            i -= 1
        EndWhile
    EndIf
    If QuestTargetAlias == None
        Core.DebugMsg("Story [quest]: WARNING - QuestTargetAlias not found! Check alias setup in CK")
        Core.NotifyPlayer("Quest marker unavailable (alias not found)")
        return
    EndIf
    If QuestLocation == None
        Core.DebugMsg("Story [quest]: WARNING - QuestLocation is None, can't place marker")
        return
    EndIf
    Core.DebugMsg("Story [quest]: PlaceQuestMarker - alias=" + QuestTargetAlias + ", location=" + QuestLocation + " (" + QuestLocationName + "), questRunning=" + IsRunning() + ", questActive=" + IsActive())
    ; Reset from any previous quest (completed state + display)
    SetObjectiveCompleted(QUEST_OBJECTIVE_ID, false)
    SetObjectiveDisplayed(QUEST_OBJECTIVE_ID, false)
    ; Point alias at quest location
    QuestTargetAlias.ForceRefTo(QuestLocation)
    ; Wait for engine to process the alias fill before displaying objective
    Utility.Wait(0.5)
    ObjectReference aliasRef = QuestTargetAlias.GetReference()
    Core.DebugMsg("Story [quest]: After ForceRefTo - aliasRef=" + aliasRef + " (expected=" + QuestLocation + ")")
    ; Activate quest in tracker so compass/map markers appear
    SetActive(true)
    ; Direct call for immediate display (synchronous)
    SetObjectiveDisplayed(QUEST_OBJECTIVE_ID, true)
    ; Stage for quest state tracking (fragment also calls SetObjectiveDisplayed as backup)
    SetStage(100)
    Core.DebugMsg("Story [quest]: Marker placed for " + QuestLocationName + ", questActive=" + IsActive() + ", objDisplayed=" + IsObjectiveDisplayed(QUEST_OBJECTIVE_ID))
EndFunction

Function RemoveQuestMarker()
    If QuestTargetAlias == None
        return
    EndIf
    SetObjectiveCompleted(QUEST_OBJECTIVE_ID)
    SetActive(false)
    QuestTargetAlias.Clear()
    Core.DebugMsg("Story [quest]: Objective completed, quest deactivated")
EndFunction

; =============================================================================
; CLEANUP
; =============================================================================

Function CleanupStoryDispatch()
    ; If quest dispatch is being cleaned up, also reset quest state
    If ActiveStoryType == "quest" || ActiveStoryType == "quest_guide"
        If QuestActive
            CleanupQuest()
        EndIf
    EndIf

    If ActiveStoryNPC != None
        StorageUtil.UnsetIntValue(ActiveStoryNPC, "Intel_IsStoryDispatch")
        StorageUtil.UnsetStringValue(ActiveStoryNPC, "Intel_StoryNarration")
        StorageUtil.UnsetIntValue(ActiveStoryNPC, "Intel_SneakPhase")
        StorageUtil.UnsetFloatValue(ActiveStoryNPC, "Intel_SneakStartTime")
        StorageUtil.UnsetFloatValue(ActiveStoryNPC, "Intel_CombatStartTime")
        StorageUtil.UnsetFloatValue(ActiveStoryNPC, "Intel_OffscreenArrival")
        ; Message courier keys
        StorageUtil.UnsetStringValue(ActiveStoryNPC, "Intel_MessageSender")
        StorageUtil.UnsetStringValue(ActiveStoryNPC, "Intel_MessageContent")
        StorageUtil.UnsetStringValue(ActiveStoryNPC, "Intel_MessageDest")
        StorageUtil.UnsetStringValue(ActiveStoryNPC, "Intel_MessageTime")
        StorageUtil.UnsetStringValue(ActiveStoryNPC, "Intel_QuestLocation")
    EndIf
    ActiveStoryNPC = None
    ActiveSecondNPC = None
    ActiveNarration = ""
    ActiveStoryType = ""
    IsActive = false
    ClearPending()
    ; Re-register game-time scheduling so TickScheduler keeps firing.
    ; DispatchToTarget calls StopScheduler (kills game-time timer) then registers
    ; real-time only. When the dispatch ends here, game-time must restart or
    ; TickScheduler never fires again — especially when HasLingerNPCs() keeps
    ; the real-time loop alive (road encounters in Intel_FakeEncounterNPCs),
    ; because OnUpdate's transition logic requires !HasLingerNPCs() to call
    ; StartScheduler. This only adds a game-time timer (RegisterForSingleUpdateGameTime),
    ; which is independent of the real-time timer — no interference with OnUpdate.
    StartScheduler()
EndFunction

Function ClearPending()
    PendingStoryType = ""
EndFunction

; =============================================================================
; TRAVEL PACKAGE
; =============================================================================

Function ReapplyTravelPackage(Actor npc)
    ; Determine travel target: NPC target or player
    Actor target = Game.GetPlayer()
    If IsNPCToNPCType() && ActiveSecondNPC != None
        target = ActiveSecondNPC
    EndIf

    ; Stalkers and stealth ambushers use sneak travel package (walk speed + Always Sneak flag)
    Package travelPkg = Core.TravelPackage_Jog
    If ActiveStoryType == "stalker" || ActiveStoryType == "ambush"
        If Core.TravelPackage_Stalk
            travelPkg = Core.TravelPackage_Stalk
            Core.DebugMsg("Story [" + ActiveStoryType + "]: using TravelPackage_Stalk")
        Else
            Core.DebugMsg("Story [" + ActiveStoryType + "]: WARNING - TravelPackage_Stalk is None! Fill property on IntelEngine quest in CK")
        EndIf
    EndIf

    Core.RemoveAllPackages(npc, false)
    PO3_SKSEFunctions.SetLinkedRef(npc, target as ObjectReference, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(npc, travelPkg, Core.PRIORITY_TRAVEL, 1)
    Utility.Wait(0.1)
    npc.EvaluatePackage()
EndFunction

; =============================================================================
; ANTI-REPETITION SYSTEM
; =============================================================================

Function AddRecentStoryEvent(String summary)
    Actor player = Game.GetPlayer()
    StorageUtil.StringListAdd(player, "Intel_RecentStoryEvents", summary)
    While StorageUtil.StringListCount(player, "Intel_RecentStoryEvents") > 8
        StorageUtil.StringListRemoveAt(player, "Intel_RecentStoryEvents", 0)
    EndWhile
EndFunction

String Function GetRecentStoryEventsLog()
    Actor player = Game.GetPlayer()
    Int count = StorageUtil.StringListCount(player, "Intel_RecentStoryEvents")
    If count == 0
        return "None yet."
    EndIf
    String log = ""
    Int i = 0
    While i < count
        If log != ""
            log += ", "
        EndIf
        log += StorageUtil.StringListGet(player, "Intel_RecentStoryEvents", i)
        i += 1
    EndWhile
    return log
EndFunction

; =============================================================================
; STRING HELPERS
; =============================================================================

String Function BuildInteractionSummary(Actor npc1, String eventText, Actor npc2)
    return npc1.GetDisplayName() + " " + eventText + " with " + npc2.GetDisplayName()
EndFunction

; =============================================================================
; JSON PARSING (delegated to C++ natives for performance)
; =============================================================================

Bool Function ParseShouldAct(String response)
    return IntelEngine.StoryResponseShouldAct(response)
EndFunction

String Function ExtractJsonField(String json, String fieldName)
    return IntelEngine.StoryResponseGetField(json, fieldName)
EndFunction
