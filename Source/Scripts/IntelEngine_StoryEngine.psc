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
Float Property IDLE_POLL_INTERVAL = 30.0 AutoReadOnly   ; Real-time backup poll (seconds) for low-timescale games
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
Bool Property AllowStuckTeleport = true Auto Hidden
Int Property DangerZonePolicy = 1 Auto Hidden
; 0 = allow all, 1 = block civilians, 2 = followers only, 3 = block all
Int Property PlayerHomePolicy = 0 Auto Hidden
; 0 = allow all, 1 = block civilians, 2 = followers only, 3 = block all

; Legacy (save migration only — removed from MCM, read once on load then ignored)
Bool Property BlockCiviliansInDanger = true Auto Hidden
Bool Property BlockAllInDanger = false Auto Hidden

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

; === Quest Sub-Type State ===
String Property QuestSubType = "" Auto Hidden              ; "combat", "rescue", "find_item"
Actor Property QuestVictimNPC = None Auto Hidden           ; Real named NPC (rescue)
ObjectReference Property QuestItemChest = None Auto Hidden ; Spawned chest (find_item)
String Property QuestVictimName = "" Auto Hidden           ; Display name for narration
String Property QuestItemDesc = "" Auto Hidden             ; LLM-provided item description
String Property QuestItemName = "" Auto Hidden             ; Resolved actual item name (from ItemIndex)
Bool Property QuestVictimFreed = false Auto Hidden         ; Has victim been unrestrained
Bool Property QuestDeferredToInterior = false Auto Hidden    ; Dungeon entrance found — defer spawning until player enters
Actor Property QuestBossNPC = None Auto Hidden             ; Boss enemy near treasure (find_item)
Bool Property QuestPrePlaced = false Auto Hidden            ; Victim/chest pre-placed at boss room via DungeonIndex
ObjectReference Property QuestBossAnchor = None Auto Hidden ; Boss room anchor from DungeonIndex
Bool Property QuestFurnitureScanned = false Auto Hidden     ; Prisoner furniture scan completed
Bool Property QuestVictimInFurniture = false Auto Hidden    ; Victim is using actual furniture (shackles/stocks) — not bleedout
Cell Property QuestDungeonLastCell = None Auto Hidden       ; Last tracked cell inside dungeon (depth tracking)
Int Property QuestDungeonDepth = 0 Auto Hidden              ; Door transitions inside dungeon (0 = entrance)
Int Property QuestDungeonScanFails = 0 Auto Hidden          ; Failed scan-ahead attempts (fallback after 5)

; === Tick Timing ===
Float Property LastStoryTickTime = 0.0 Auto Hidden          ; Game-time (days) of last DM tick — for real-time backup

; === Quest Sub-Type MCM Toggles (all enabled by default) ===
Bool Property QuestSubTypeCombatEnabled = true Auto Hidden
Bool Property QuestSubTypeRescueEnabled = true Auto Hidden
Bool Property QuestSubTypeFindItemEnabled = true Auto Hidden
Bool Property QuestAllowVictimDeath = false Auto Hidden

; CK Property -- quest objective alias (points compass at quest location)
ReferenceAlias Property QuestTargetAlias Auto
Int Property QUEST_OBJECTIVE_ID = 0 AutoReadOnly

; =============================================================================
; TIMER MANAGEMENT
; Two modes: game-time timer for scheduling, real-time timer for monitoring
; =============================================================================

Function StartScheduler()
    If !Core.IsStoryEngineEnabled()
        return
    EndIf
    If IsActive || IsNPCStoryActive || HasLingerNPCs() || QuestActive
        RegisterForSingleUpdate(MONITOR_INTERVAL)
    Else
        ; Game-time timer: fires instantly during Wait/Sleep
        RegisterForSingleUpdateGameTime(Core.GetStoryEngineInterval())
        ; Real-time backup: ensures tick fires even at low timescales (timescale 2-6).
        ; Without this, a 3-hour DM interval at timescale 2 = 90 real minutes of silence.
        RegisterForSingleUpdate(IDLE_POLL_INTERVAL)
    EndIf
EndFunction

Function StopScheduler()
    UnregisterForUpdate()
    UnregisterForUpdateGameTime()
EndFunction

Function RestartMonitoring()
    ClearPending()
    NPCTickPending = false

    ; Initialize tick timestamp so the real-time backup can fire on first interval
    LastStoryTickTime = Utility.GetCurrentGameTime()

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
            Int deadSlot2 = Core.FindSlotByAgent(ActiveStoryNPC)
            If deadSlot2 >= 0
                Core.ClearSlot(deadSlot2)
            EndIf
            Core.RemoveAllPackages(ActiveStoryNPC, false)
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

    ; Rescue victim safety: if victim ref was lost on load, auto-expire quest
    If QuestActive && QuestSubType == "rescue"
        If QuestVictimNPC == None
            Core.DebugMsg("Story: quest/rescue victim lost on load, expiring quest")
            RemoveQuestMarker()
            CleanupQuest()
        ElseIf !QuestVictimFreed && QuestEnemiesSpawned
            ; Re-apply restrained state on load (runtime state lost on save/load)
            If QuestVictimInFurniture
                ; Furniture victim: just keep DontMove, don't damage health
                QuestVictimNPC.SetDontMove(true)
                Core.DebugMsg("Story: re-applied furniture DontMove on load for " + QuestVictimNPC.GetDisplayName())
            Else
                ; Bleedout victim: re-apply bleedout only (no SetRestrained/SetDontMove — they override bleedout anim)
                QuestVictimNPC.SetNoBleedoutRecovery(true)
                QuestVictimNPC.DamageActorValue("Health", QuestVictimNPC.GetActorValue("Health") + 100.0)
                QuestVictimNPC.EvaluatePackage()
                Core.DebugMsg("Story: re-applied victim bleedout on load for " + QuestVictimNPC.GetDisplayName())
            EndIf
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
    ; Check rescued NPC deaths on game-time tick (no need for real-time polling)
    CheckRescuedNPCDeaths()
    ; Re-kick real-time monitoring if linger NPCs still exist
    If HasLingerNPCs()
        RegisterForSingleUpdate(MONITOR_INTERVAL)
    EndIf
    LastStoryTickTime = Utility.GetCurrentGameTime()
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
        ; Idle mode: real-time backup tick for low-timescale games.
        ; RegisterForSingleUpdateGameTime fires instantly during Wait/Sleep but can stall
        ; for 90+ real minutes at timescale 2. This polls every IDLE_POLL_INTERVAL seconds
        ; and fires TickScheduler when enough game time has elapsed.
        Float now = Utility.GetCurrentGameTime()
        Float intervalDays = Core.GetStoryEngineInterval() / 24.0
        If (now - LastStoryTickTime) >= intervalDays
            LastStoryTickTime = now
            TickScheduler()
        EndIf
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
    If !Core.IsStoryEngineEnabled()
        return
    EndIf

    ; Save migration: old saves have separate Bool properties, migrate to Int policy
    If DangerZonePolicy == 0 && (BlockCiviliansInDanger || BlockAllInDanger)
        If BlockAllInDanger
            DangerZonePolicy = 3
        ElseIf BlockCiviliansInDanger
            DangerZonePolicy = 1
        EndIf
        Core.DebugMsg("Story: migrated danger zone policy to " + DangerZonePolicy)
    EndIf

    ; Sync danger zone policy to C++
    IntelEngine.SetDangerZonePolicy(DangerZonePolicy)
    IntelEngine.SetPlayerHomePolicy(PlayerHomePolicy)

    ; NPC-to-NPC tick (independent of player-centric state, self-gates via interval timer)
    TickNPCInteractions()


    ; Safety net: return stranded fake encounter NPCs
    CleanupStrandedEncounters()

    ; Monitor rescued NPCs for death (game-time is sufficient — no urgency)
    CheckRescuedNPCDeaths()

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

                ; Build exclude list from per-type toggles + environment
                String excludeList = BuildExcludeList(player)

                String contextJson = IntelEngine.BuildStoryDMRequestJson(dmContext, excludeList)
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

    ; Quest sub-type excludes (only if quest itself is enabled)
    If TypeQuestEnabled
        If !QuestSubTypeCombatEnabled
            result = AppendExclude(result, "quest_combat")
        EndIf
        If !QuestSubTypeRescueEnabled
            result = AppendExclude(result, "quest_rescue")
        EndIf
        If !QuestSubTypeFindItemEnabled
            result = AppendExclude(result, "quest_find_item")
        EndIf
    EndIf

    ; Auto-exclude types invalid in interiors
    Cell pCell = player.GetParentCell()
    If pCell != None && pCell.IsInterior()
        result = AppendExclude(result, "stalker")
        result = AppendExclude(result, "ambush")
        result = AppendExclude(result, "road_encounter")
    EndIf

    ; Auto-exclude informant in danger zones (gossip isn't worth risking your life)
    If IntelEngine.IsPlayerInDangerousLocation()
        result = AppendExclude(result, "informant")
    EndIf

    Core.DebugMsg("BuildExcludeList: [" + result + "] (ambush=" + TypeAmbushEnabled + " message=" + TypeMessageEnabled + " quest=" + TypeQuestEnabled + ")")
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

    ; Warm social cooldowns from StorageUtil into C++ mirror, then rebuild if any found
    If WarmSocialCooldownsForPool()
        npcContext = IntelEngine.BuildNPCInteractionContext(4)
        If npcContext == ""
            NPCTickPending = false
            return
        EndIf
    EndIf

    String contextJson = IntelEngine.BuildNPCInteractionRequestJson(npcContext)
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

    ; Check cooldown for BOTH before applying either (avoid partial cooldown reset)
    If !CheckNPCSocialCooldown(npc1) || !CheckNPCSocialCooldown(npc2)
        Core.DebugMsg("NPC DM: " + npc1.GetDisplayName() + " or " + npc2.GetDisplayName() + " on social cooldown")
        return
    EndIf
    ; Both passed — now stamp both
    SetNPCSocialCooldown(npc1)
    SetNPCSocialCooldown(npc2)

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
        AddNPCSocialLog(storyType, npc1.GetDisplayName(), npc2.GetDisplayName(), narration)
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
        AddNPCSocialLog(storyType, npc.GetDisplayName(), target.GetDisplayName(), narration)
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
    Float cooldownDays = Core.GetStoryEngineCooldown() / 24.0
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

Bool Function CheckNPCSocialCooldown(Actor candidate)
    {Check if NPC is off social cooldown. Does NOT write timestamp — use SetNPCSocialCooldown after both pass.}
    Float lastPicked = StorageUtil.GetFloatValue(candidate, "Intel_NPCSocialLastPicked", 0.0)
    If lastPicked <= 0.0
        return true
    EndIf
    Float cooldownDays = NPCSocialCooldownHours / 24.0
    return (Utility.GetCurrentGameTime() - lastPicked) >= cooldownDays
EndFunction

Function SetNPCSocialCooldown(Actor candidate)
    {Stamp the NPC's social cooldown. Call only after both NPCs pass CheckNPCSocialCooldown.}
    Float now = Utility.GetCurrentGameTime()
    StorageUtil.SetFloatValue(candidate, "Intel_NPCSocialLastPicked", now)
    If !StorageUtil.FormListHas(self, "Intel_SocialCooldownActors", candidate)
        StorageUtil.FormListAdd(self, "Intel_SocialCooldownActors", candidate)
    EndIf
    IntelEngine.NotifySocialCooldown(candidate, now, NPCSocialCooldownHours)
EndFunction

Function WarmCooldownMirror()
    {Populate C++ cooldown mirror from StorageUtil on game load. Prevents wasted LLM turns.}
    Float currentTime = Utility.GetCurrentGameTime()
    Float cooldownDays = Core.GetStoryEngineCooldown() / 24.0

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

    ; Warm social cooldowns
    Float socialCooldownDays = NPCSocialCooldownHours / 24.0
    Int socialCount = StorageUtil.FormListCount(self, "Intel_SocialCooldownActors")
    Int socialWarmed = 0
    Int si = socialCount - 1
    While si >= 0
        Actor socialNpc = StorageUtil.FormListGet(self, "Intel_SocialCooldownActors", si) as Actor
        If socialNpc != None
            Float socialLastPicked = StorageUtil.GetFloatValue(socialNpc, "Intel_NPCSocialLastPicked", 0.0)
            If socialLastPicked > 0.0 && (currentTime - socialLastPicked) < socialCooldownDays
                IntelEngine.NotifySocialCooldown(socialNpc, socialLastPicked, NPCSocialCooldownHours)
                socialWarmed += 1
            Else
                StorageUtil.FormListRemoveAt(self, "Intel_SocialCooldownActors", si)
            EndIf
        Else
            StorageUtil.FormListRemoveAt(self, "Intel_SocialCooldownActors", si)
        EndIf
        si -= 1
    EndWhile
    If socialWarmed > 0
        Core.DebugMsg("Story: warmed C++ social cooldown mirror (" + socialWarmed + " NPCs)")
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
    Float cooldownDays = Core.GetStoryEngineCooldown() / 24.0

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
            Else
                ; Also exclude scheduled NPCs from pool (pending/dispatched/active meeting)
                Int schedState = StorageUtil.GetIntValue(npc, "Intel_ScheduledState", -1)
                If schedState >= 0
                    IntelEngine.NotifyStoryCooldown(npc, currentTime)
                    StorageUtil.FormListAdd(self, "Intel_CooldownActors", npc, false)
                    warmed += 1
                EndIf
            EndIf
        EndIf
        i += 1
    EndWhile
    If warmed > 0
        Core.DebugMsg("Story: pre-warmed " + warmed + " cooldowns from pool candidates")
    EndIf
    return warmed > 0
EndFunction

Bool Function WarmSocialCooldownsForPool()
    {Check NPC interaction pool candidates against StorageUtil social cooldowns.
     Returns true if any were on cooldown (caller should rebuild pool).}
    Int[] formIDs = IntelEngine.GetNPCCandidatePoolFormIDs()
    If formIDs.Length == 0
        return false
    EndIf

    Float currentTime = Utility.GetCurrentGameTime()
    Float cooldownDays = NPCSocialCooldownHours / 24.0

    Int warmed = 0
    Int i = 0
    While i < formIDs.Length
        Actor npc = Game.GetForm(formIDs[i]) as Actor
        If npc != None
            Float lastPicked = StorageUtil.GetFloatValue(npc, "Intel_NPCSocialLastPicked", 0.0)
            If lastPicked > 0.0 && (currentTime - lastPicked) < cooldownDays
                IntelEngine.NotifySocialCooldown(npc, lastPicked, NPCSocialCooldownHours)
                If !StorageUtil.FormListHas(self, "Intel_SocialCooldownActors", npc)
                    StorageUtil.FormListAdd(self, "Intel_SocialCooldownActors", npc)
                EndIf
                warmed += 1
            EndIf
        EndIf
        i += 1
    EndWhile
    If warmed > 0
        Core.DebugMsg("NPC Social: pre-warmed " + warmed + " social cooldowns from pool")
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
    Int result = SkyrimNetApi.SendCustomPromptToLLM(promptName, "intel_story_dm", contextJson, \
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
    If storyType == "seek_player" || storyType == "informant"
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

    ; Safety net: reject types disabled in MCM (LLM may ignore hidden prompt sections)
    If (storyType == "seek_player" && !TypeSeekPlayerEnabled) || \
       (storyType == "informant" && !TypeInformantEnabled) || \
       (storyType == "road_encounter" && !TypeRoadEncounterEnabled) || \
       (storyType == "ambush" && !TypeAmbushEnabled) || \
       (storyType == "stalker" && !TypeStalkerEnabled) || \
       (storyType == "message" && !TypeMessageEnabled) || \
       (storyType == "quest" && !TypeQuestEnabled)
        Core.DebugMsg("Story DM: rejecting " + storyType + " -- disabled in MCM")
        return
    EndIf

    ; Safety net: Jarls NEVER travel personally. Only message and quest (courier) allowed.
    If IntelEngine.IsJarl(npc) && storyType != "message" && storyType != "quest"
        Core.DebugMsg("Story DM: rejecting " + storyType + " for Jarl " + npc.GetDisplayName() + " -- Jarls don't travel personally")
        return
    EndIf

    ; Pre-validate type-specific required fields BEFORE sending persistent memory.
    ; If we narrate first and then the handler rejects, the NPC talks about
    ; something that never happens (e.g., a quest with no valid location).
    If storyType == "quest"
        If QuestActive
            Core.DebugMsg("Story DM: quest rejected -- one already active")
            return
        EndIf
        String preSubType = ExtractJsonField(response, "questSubType")
        If preSubType == ""
            preSubType = "combat"
        EndIf
        ; Check MCM sub-type toggles
        If preSubType == "combat" && !QuestSubTypeCombatEnabled
            Core.DebugMsg("Story DM: quest/combat rejected -- disabled in MCM")
            return
        ElseIf preSubType == "rescue" && !QuestSubTypeRescueEnabled
            Core.DebugMsg("Story DM: quest/rescue rejected -- disabled in MCM")
            return
        ElseIf preSubType == "find_item" && !QuestSubTypeFindItemEnabled
            Core.DebugMsg("Story DM: quest/find_item rejected -- disabled in MCM")
            return
        EndIf
        ; Validate required fields per sub-type
        If preSubType == "rescue"
            If ExtractJsonField(response, "questLocation") == "" || ExtractJsonField(response, "enemyType") == "" || ExtractJsonField(response, "victimName") == ""
                Core.DebugMsg("Story DM: quest/rescue rejected -- missing questLocation, enemyType, or victimName")
                return
            EndIf
        ElseIf preSubType == "find_item"
            If ExtractJsonField(response, "questLocation") == "" || ExtractJsonField(response, "enemyType") == ""
                Core.DebugMsg("Story DM: quest/find_item rejected -- missing questLocation or enemyType")
                return
            EndIf
        Else
            If ExtractJsonField(response, "questLocation") == "" || ExtractJsonField(response, "enemyType") == ""
                Core.DebugMsg("Story DM: quest rejected -- missing questLocation or enemyType")
                return
            EndIf
        EndIf
    ElseIf storyType == "message"
        If ExtractJsonField(response, "msgContent") == ""
            Core.DebugMsg("Story DM: message rejected -- missing msgContent")
            return
        EndIf
    EndIf

    ; Record dispatch as a persistent event (generic text, NOT the full narration).
    ; The actual narration fires only once on arrival via OnStoryNPCArrived.
    ; Message type sends its own persistent memory inside HandleMessageDispatch (references messenger, not sender).
    If storyType != "message"
        Core.SendPersistentMemory(npc, Game.GetPlayer(), npc.GetDisplayName() + " set out to find " + Game.GetPlayer().GetDisplayName())
    EndIf

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
    Actor player = Game.GetPlayer()

    ; === Player home knocking prompt ===
    If target == player && !IsNPCToNPCType() && IntelEngine.IsPlayerInOwnHome()
        ObjectReference exteriorDoor = IntelEngine.GetPlayerHomeExteriorDoor()
        If exteriorDoor != None
            String npcName = npc.GetDisplayName()
            String playerName = player.GetDisplayName()

            ; NPC stays at their origin (unloaded/far away) — player never sees them.
            ; The prompt fires before MoveTo, slot allocation, or package application.
            String knockResult = SkyMessage.Show(npcName + " is knocking at your door.", \
                "Let them in", "Send them away", "Ignore", "", "", "", "", "", "", "", false, 0.1, 30.0)

            If knockResult == "Let them in"
                ; Unlock player's home door for NPC entry (player cell, not NPC's home)
                Cell playerCell = player.GetParentCell()
                If playerCell != None
                    IntelEngine.SetHomeDoorAccessForCell(playerCell.GetFormID(), true)
                EndIf
                npc.MoveTo(exteriorDoor, 0.0, 0.0, 0.0, false)
                ; Fall through to normal dispatch below
            ElseIf knockResult == "Send them away"
                npc.MoveTo(exteriorDoor, 0.0, 0.0, 0.0, false)
                Core.InjectFact(npc, "went to visit " + playerName + " at home but was turned away at the door")
                Core.SendPersistentMemory(npc, player, npcName + " knocked on " + playerName + "'s door but was told to go away")
                ActiveStoryType = ""
                return
            Else ; "Ignore" or "TIMED_OUT"
                npc.MoveTo(exteriorDoor, 0.0, 0.0, 0.0, false)
                Core.InjectFact(npc, "went to visit " + playerName + " at home but nobody answered the door")
                Core.SendPersistentMemory(npc, player, npcName + " knocked on " + playerName + "'s door but got no answer")
                ActiveStoryType = ""
                return
            EndIf
        EndIf
    EndIf

    Int slot = Core.FindFreeAgentSlot()
    If slot < 0
        Debug.Trace("[IntelEngine] StoryEngine: No free slots for dispatch")
        ; For NPC targets, log event (facts already injected by caller)
        If target != player
            AddRecentStoryEvent(ActiveStoryType + ": " + BuildInteractionSummary(npc, narration, target))
        EndIf
        ; Reset state set by caller before DispatchToTarget was called
        ActiveStoryType = ""
        return
    EndIf

    ; Determine slot target name
    String targetName = target.GetDisplayName()
    If target != player
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
    If target == player
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
    AddNPCSocialLog(eventType, npc1.GetDisplayName(), npc2.GetDisplayName(), eventText)
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
            ; For rescued NPCs, death fact injection is handled by CheckRescuedNPCDeaths
            ; via Intel_RecentlyRescuedNPCs — rescue metadata preserved for that purpose.
            If npc != None
                StorageUtil.UnsetStringValue(npc, "Intel_RescueNarration")
            EndIf
            StorageUtil.FormListRemoveAt(player, "Intel_StoryLingerActors", i)
        Else
            ; Deferred rescue narration: fire when victim reaches the player
            String pendingNarration = StorageUtil.GetStringValue(npc, "Intel_RescueNarration", "")
            If pendingNarration != ""
                Float dist = IntelEngine.GetDistance3D(npc, player)
                If dist < 400.0
                    npc.SetLookAt(player)
                    Core.SendTaskNarration(npc, pendingNarration, player)
                    StorageUtil.UnsetStringValue(npc, "Intel_RescueNarration")
                    Core.DebugMsg("Story [quest/rescue]: " + npc.GetDisplayName() + " reached player, narrating")
                EndIf
            EndIf

            ; Real-time timeout (story-specific safety valve)
            Float lingerStart = StorageUtil.GetFloatValue(npc, "Intel_StoryLingerStart", 0.0)
            Float elapsed = Utility.GetCurrentRealTime() - lingerStart
            Bool timedOut = lingerStart > 0.0 && elapsed > LINGER_TIMEOUT_SECONDS
            ; Grace period: don't check distance for the first 30 seconds so
            ; NPCs that start far away (e.g. rescued victims) can pathfind to the player
            Bool shouldRelease = elapsed > 30.0 && Core.ShouldReleaseLinger(npc)

            If timedOut || shouldRelease
                ; Clean up narration (already fired or timed out)
                StorageUtil.UnsetStringValue(npc, "Intel_RescueNarration")
                ; NOTE: Intel_RescueQuestGiver and Intel_RescuePlayerName are NOT cleaned here.
                ; They persist on Intel_RecentlyRescuedNPCs so CheckRescuedNPCDeaths can detect
                ; post-linger kills and inject facts to the quest giver.
                Core.ReleaseLinger(npc)
                StorageUtil.UnsetFloatValue(npc, "Intel_StoryLingerStart")
                StorageUtil.FormListRemoveAt(player, "Intel_StoryLingerActors", i)
            EndIf
        EndIf
        i -= 1
    EndWhile
EndFunction

Function CheckRescuedNPCDeaths()
    {Monitor recently rescued NPCs for death — persists beyond linger release.
    Uses GetKiller() for attribution and nearby friendly NPCs for witness detection.
    If player killed with no witnesses: suspect language. With witnesses or other killer: factual.}
    Actor player = Game.GetPlayer()
    Int count = StorageUtil.FormListCount(player, "Intel_RecentlyRescuedNPCs")
    If count == 0
        return
    EndIf

    Int i = count - 1
    While i >= 0
        Actor npc = StorageUtil.FormListGet(player, "Intel_RecentlyRescuedNPCs", i) as Actor
        If npc == None || npc.IsDisabled()
            ; NPC unloaded or gone — clean up silently
            If npc != None
                StorageUtil.UnsetFormValue(npc, "Intel_RescueQuestGiver")
                StorageUtil.UnsetStringValue(npc, "Intel_RescuePlayerName")
                StorageUtil.UnsetFloatValue(npc, "Intel_RescueTime")
            EndIf
            StorageUtil.FormListRemoveAt(player, "Intel_RecentlyRescuedNPCs", i)
        ElseIf npc.IsDead()
            Actor rescueGiver = StorageUtil.GetFormValue(npc, "Intel_RescueQuestGiver") as Actor
            If rescueGiver != None
                String victimName = npc.GetDisplayName()
                Actor killer = npc.GetKiller()

                If killer == player
                    ; Player killed them — check for witnesses (friendly NPCs nearby)
                    Bool hasWitness = false
                    Actor[] nearbyNPCs = MiscUtil.ScanCellNPCs(npc, 3000.0)
                    Int j = 0
                    While j < nearbyNPCs.Length
                        Actor witness = nearbyNPCs[j]
                        If witness != player && witness != npc && !witness.IsHostileToActor(player)
                            hasWitness = true
                            j = nearbyNPCs.Length ; break
                        EndIf
                        j += 1
                    EndWhile

                    If hasWitness
                        ; Witnessed — quest giver learns the truth
                        String rPlayerName = StorageUtil.GetStringValue(npc, "Intel_RescuePlayerName", "the rescuer")
                        Core.InjectFact(rescueGiver, "learned that " + victimName + " was killed by " + rPlayerName + " shortly after being rescued")
                    Else
                        ; No witnesses — quest giver only hears rumors, player is a suspect
                        Core.InjectFact(rescueGiver, "heard that " + victimName + " died under suspicious circumstances shortly after being rescued")
                    EndIf
                ElseIf killer != None
                    ; Killed by someone else (bandit, animal, etc.)
                    String killerName = killer.GetDisplayName()
                    Core.InjectFact(rescueGiver, "learned that " + victimName + " was killed by " + killerName + " shortly after being rescued")
                Else
                    ; Unknown killer (engine didn't track it)
                    Core.InjectFact(rescueGiver, "learned that " + victimName + " died shortly after being rescued")
                EndIf
                Core.DebugMsg("Story [quest/rescue]: " + victimName + " killed post-rescue (killer=" + killer + ") — fact injected to " + rescueGiver.GetDisplayName())
            EndIf
            ; Clean up all rescue metadata
            StorageUtil.UnsetFormValue(npc, "Intel_RescueQuestGiver")
            StorageUtil.UnsetStringValue(npc, "Intel_RescuePlayerName")
            StorageUtil.UnsetFloatValue(npc, "Intel_RescueTime")
            StorageUtil.FormListRemoveAt(player, "Intel_RecentlyRescuedNPCs", i)
        Else
            ; Alive — expire tracking after 1 game day (NPC survived long enough)
            Float rescueTime = StorageUtil.GetFloatValue(npc, "Intel_RescueTime", 0.0)
            If rescueTime > 0.0 && (Utility.GetCurrentGameTime() - rescueTime) > 1.0
                StorageUtil.UnsetFormValue(npc, "Intel_RescueQuestGiver")
                StorageUtil.UnsetStringValue(npc, "Intel_RescuePlayerName")
                StorageUtil.UnsetFloatValue(npc, "Intel_RescueTime")
                StorageUtil.FormListRemoveAt(player, "Intel_RecentlyRescuedNPCs", i)
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
        If ActiveStoryNPC != None
            Int deadSlot = Core.FindSlotByAgent(ActiveStoryNPC)
            If deadSlot >= 0
                Core.ClearSlot(deadSlot)
            EndIf
            Core.RemoveAllPackages(ActiveStoryNPC, false)
        EndIf
        CleanupStoryDispatch()
        return
    EndIf

    ; Corrupt state detection: IsActive true but no type means something went wrong
    ; during concurrent event processing (seen with Sylvi seek_player — FinishArrivalWithLinger
    ; Utility.Wait re-entry corrupted state). Clean up to prevent tick death.
    If ActiveStoryType == ""
        Core.DebugMsg("Story: corrupt state detected (IsActive but no type) for " + ActiveStoryNPC.GetDisplayName() + " - cleaning up")
        Int corruptSlot = Core.FindSlotByAgent(ActiveStoryNPC)
        If corruptSlot >= 0
            Core.ClearSlot(corruptSlot)
        EndIf
        Core.RemoveAllPackages(ActiveStoryNPC, false)
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

    ; Cancel dispatch if player entered a blocked location during travel
    If arrivalTarget == player && IntelEngine.IsPlayerInBlockedLocation()
        Core.DebugMsg("Story: cancelling " + ActiveStoryType + " for " + ActiveStoryNPC.GetDisplayName() + " -- player at blocked location")
        Core.SendTaskNarration(ActiveStoryNPC, "gave up looking for " + player.GetDisplayName() + " and turned back", player)
        AbortStoryTravel("player at blocked location")
        return
    EndIf

    ; Abort dispatch if player entered a dangerous location during travel
    If arrivalTarget == player && IntelEngine.IsPlayerInDangerousLocation()
        ; Type-specific: informant always aborts in danger (gossip not worth dying for)
        If ActiveStoryType == "informant"
            Core.DebugMsg("Story: aborting informant for " + ActiveStoryNPC.GetDisplayName() + " -- danger zone (type rule)")
            Core.SendTaskNarration(ActiveStoryNPC, "thought better of chasing " + player.GetDisplayName() + " into danger just for gossip and turned back", player)
            AbortStoryTravel("informant in danger zone")
            return
        EndIf
        ; MCM-controlled danger zone policy
        If DangerZonePolicy == 3 || \
           (DangerZonePolicy == 2 && !IntelEngine.IsPotentialFollower(ActiveStoryNPC)) || \
           (DangerZonePolicy == 1 && IntelEngine.IsCivilianClass(ActiveStoryNPC))
            Core.DebugMsg("Story: aborting " + ActiveStoryType + " for " + ActiveStoryNPC.GetDisplayName() + " -- danger zone policy (" + DangerZonePolicy + ")")
            Core.SendTaskNarration(ActiveStoryNPC, "turned back after learning that " + player.GetDisplayName() + " had ventured into a dangerous place", player)
            AbortStoryTravel("danger zone policy")
            return
        EndIf
    EndIf

    ; MCM-controlled player home visit policy
    If arrivalTarget == player && IntelEngine.IsPlayerInOwnHome()
        If PlayerHomePolicy == 3 || \
           (PlayerHomePolicy == 2 && !IntelEngine.IsPotentialFollower(ActiveStoryNPC)) || \
           (PlayerHomePolicy == 1 && IntelEngine.IsCivilianClass(ActiveStoryNPC))
            Core.DebugMsg("Story: aborting " + ActiveStoryType + " for " + ActiveStoryNPC.GetDisplayName() + " -- player home policy (" + PlayerHomePolicy + ")")
            Core.SendTaskNarration(ActiveStoryNPC, "decided not to bother " + player.GetDisplayName() + " at home and turned back", player)
            AbortStoryTravel("player home policy")
            return
        EndIf
    EndIf

    ; Abort exterior-only types if player entered an interior during travel
    If arrivalTarget == player
        Cell pCell = player.GetParentCell()
        If pCell != None && pCell.IsInterior()
            If ActiveStoryType == "road_encounter" || ActiveStoryType == "stalker" || ActiveStoryType == "ambush"
                Core.DebugMsg("Story: aborting " + ActiveStoryType + " for " + ActiveStoryNPC.GetDisplayName() + " -- player entered interior")
                Core.SendTaskNarration(ActiveStoryNPC, "lost track of " + player.GetDisplayName() + " after they went inside and gave up", player)
                AbortStoryTravel("exterior type in interior")
                return
            EndIf
        EndIf
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
    Cell npcCell2 = ActiveStoryNPC.GetParentCell()
    If npcCell2 != None && targetCell != None && npcCell2 == targetCell
        If targetCell.IsInterior() && dist <= Core.ARRIVAL_DISTANCE && dist > 0.0
            OnStoryNPCArrived()
            return
        EndIf
    EndIf

    Int slot = Core.FindSlotByAgent(ActiveStoryNPC)
    If slot < 0
        return
    EndIf

    ; Off-screen: NPC not loaded — leapfrog won't work, use time-based arrival
    If !ActiveStoryNPC.Is3DLoaded()
        ; Abort dispatch if player entered a dangerous location
        If arrivalTarget == player && IntelEngine.IsPlayerInDangerousLocation()
            If ActiveStoryType == "informant"
                Core.DebugMsg("Story: aborting informant for " + ActiveStoryNPC.GetDisplayName() + " -- danger zone (off-screen, type rule)")
                Core.SendTaskNarration(ActiveStoryNPC, "thought better of chasing " + player.GetDisplayName() + " into danger just for gossip and turned back", player)
                AbortStoryTravel("informant in danger zone (off-screen)")
                return
            EndIf
            If DangerZonePolicy == 3 || \
               (DangerZonePolicy == 2 && !IntelEngine.IsPotentialFollower(ActiveStoryNPC)) || \
               (DangerZonePolicy == 1 && IntelEngine.IsCivilianClass(ActiveStoryNPC))
                Core.DebugMsg("Story: aborting " + ActiveStoryType + " for " + ActiveStoryNPC.GetDisplayName() + " -- danger zone policy (off-screen, " + DangerZonePolicy + ")")
                Core.SendTaskNarration(ActiveStoryNPC, "turned back after learning that " + player.GetDisplayName() + " had ventured into a dangerous place", player)
                AbortStoryTravel("danger zone policy (off-screen)")
                return
            EndIf
        EndIf
        ; MCM-controlled player home visit policy (off-screen)
        If arrivalTarget == player && IntelEngine.IsPlayerInOwnHome()
            If PlayerHomePolicy == 3 || \
               (PlayerHomePolicy == 2 && !IntelEngine.IsPotentialFollower(ActiveStoryNPC)) || \
               (PlayerHomePolicy == 1 && IntelEngine.IsCivilianClass(ActiveStoryNPC))
                Core.DebugMsg("Story: aborting " + ActiveStoryType + " for " + ActiveStoryNPC.GetDisplayName() + " -- player home policy (off-screen, " + PlayerHomePolicy + ")")
                Core.SendTaskNarration(ActiveStoryNPC, "decided not to bother " + player.GetDisplayName() + " at home and turned back", player)
                AbortStoryTravel("player home policy (off-screen)")
                return
            EndIf
        EndIf
        ; Abort exterior-only types if player entered interior (off-screen)
        If arrivalTarget == player
            Cell offPCell = player.GetParentCell()
            If offPCell != None && offPCell.IsInterior()
                If ActiveStoryType == "road_encounter" || ActiveStoryType == "stalker" || ActiveStoryType == "ambush"
                    Core.DebugMsg("Story: aborting " + ActiveStoryType + " for " + ActiveStoryNPC.GetDisplayName() + " -- player entered interior (off-screen)")
                    Core.SendTaskNarration(ActiveStoryNPC, "lost track of " + player.GetDisplayName() + " after they went inside and gave up", player)
                    AbortStoryTravel("exterior type in interior (off-screen)")
                    return
                EndIf
            EndIf
        EndIf
        ; Check if estimated travel time has elapsed (without teleporting yet)
        Int offscreenStatus = IntelEngine.CheckOffScreenProgress(slot, ActiveStoryNPC, Utility.GetCurrentGameTime())
        If offscreenStatus == 1
            Core.DebugMsg(ActiveStoryNPC.GetDisplayName() + " off-screen arrival (estimated time elapsed)")
            ImmersiveTeleportToTarget(ActiveStoryNPC, arrivalTarget)
            ; Prevent timeout from re-firing while NPC walks the last stretch
            StorageUtil.UnsetFloatValue(ActiveStoryNPC, "Intel_TaskStartTime")
        EndIf
        return
    EndIf

    ; On-screen: stuck detection with leapfrog recovery
    Int stuckStatus = IntelEngine.CheckStuckStatus(ActiveStoryNPC, slot, Core.STUCK_DISTANCE_THRESHOLD)
    If stuckStatus == 1
        Core.SoftStuckRecovery(ActiveStoryNPC, slot, arrivalTarget as ObjectReference)
    ElseIf stuckStatus >= 3
        If AllowStuckTeleport
            ImmersiveTeleportToTarget(ActiveStoryNPC, arrivalTarget)
            ; Prevent timeout from re-firing while NPC walks the last stretch
            StorageUtil.UnsetFloatValue(ActiveStoryNPC, "Intel_TaskStartTime")
        Else
            AbortStoryTravel("stuck, teleport disabled")
        EndIf
        return
    EndIf

    ; Timeout safety net — NPC exceeded MaxTravelDaysConfig, force-arrive immediately.
    ; Previous bug: ImmersiveTeleportToTarget placed NPC 3500u behind the player
    ; (outside 300u arrival radius) without clearing task state, causing infinite
    ; re-teleport every 3s. Fix: teleport + force-arrive in one step.
    Float taskStart = StorageUtil.GetFloatValue(ActiveStoryNPC, "Intel_TaskStartTime", 0.0)
    If taskStart > 0.0 && (Utility.GetCurrentGameTime() - taskStart) > MaxTravelDaysConfig
        Debug.Trace("[IntelEngine] StoryEngine: Travel timeout for " + ActiveStoryNPC.GetDisplayName() + " — force-arriving")
        If AllowStuckTeleport
            ImmersiveTeleportToTarget(ActiveStoryNPC, arrivalTarget)
            OnStoryNPCArrived()
        Else
            AbortStoryTravel("travel timeout, teleport disabled")
        EndIf
        return
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

Function HandleMessageDispatch(Actor senderNPC, String narration, String response)
    String msgContent = ExtractJsonField(response, "msgContent")
    String destination = ExtractJsonField(response, "destination")
    String meetTime = ExtractJsonField(response, "meetTime")

    String playerName = Game.GetPlayer().GetDisplayName()
    String senderName = senderNPC.GetDisplayName()

    ; Find a suitable messenger via C++ cascade (household → associate → guard → civilian)
    Actor messenger = IntelEngine.FindMessengerForSender(senderNPC)

    If messenger == None
        ; No external messenger — civilians can self-deliver, others cannot
        If IntelEngine.IsCivilianClass(senderNPC)
            messenger = senderNPC
            Core.DebugMsg("Story message: " + senderName + " self-delivering (civilian)")
        Else
            Core.DebugMsg("Story message: rejected -- no messenger for " + senderName + " (non-civilian, no self-delivery)")
            return
        EndIf
    EndIf

    String messengerName = messenger.GetDisplayName()

    ; Inject facts so both parties remember the arrangement
    If messenger != senderNPC
        Core.InjectFact(senderNPC, "asked " + messengerName + " to deliver a message to " + playerName + ": " + msgContent)
        Core.InjectFact(messenger, "was sent by " + senderName + " to deliver a message to " + playerName + ": " + msgContent)
        Core.SendPersistentMemory(messenger, Game.GetPlayer(), messengerName + " set out to deliver a message from " + senderName + " to " + playerName)
    Else
        Core.InjectFact(senderNPC, "set out to deliver a message to " + playerName + ": " + msgContent)
        Core.SendPersistentMemory(senderNPC, Game.GetPlayer(), senderName + " set out to find " + playerName)
    EndIf

    ; Store on the messenger (the one who physically travels)
    StorageUtil.SetStringValue(messenger, "Intel_MessageSender", senderName)
    StorageUtil.SetStringValue(messenger, "Intel_MessageContent", msgContent)
    StorageUtil.SetStringValue(messenger, "Intel_MessageDest", destination)
    StorageUtil.SetStringValue(messenger, "Intel_MessageTime", meetTime)

    ActiveStoryType = "message"
    DispatchToTarget(messenger, Game.GetPlayer(), narration, "story")
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

    ; Safety net: if msgContent conveys urgency but meetTime is set, the LLM
    ; contradicted itself (e.g., "needs you immediately" + meetTime="afternoon").
    ; Drop the meeting — treat as plain message so narration and schedule don't clash.
    If msgDest != "" && meetTime != ""
        String lowerMsg = IntelEngine.StringToLower(msgContent)
        If StringUtil.Find(lowerMsg, "immediate") >= 0 || StringUtil.Find(lowerMsg, "right now") >= 0 || StringUtil.Find(lowerMsg, "at once") >= 0 || StringUtil.Find(lowerMsg, "right away") >= 0 || StringUtil.Find(lowerMsg, "urgently") >= 0
            Core.DebugMsg("Story message: urgency in msgContent conflicts with meetTime '" + meetTime + "' -- dropping meeting, treating as plain message")
            msgDest = ""
            meetTime = ""
        EndIf
    EndIf

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

    ; Extract sub-type fields (default to "combat" for backward compatibility)
    String questSubTypeStr = ExtractJsonField(response, "questSubType")
    String victimName = ExtractJsonField(response, "victimName")
    String itemDesc = ExtractJsonField(response, "itemDesc")
    String itemName = ExtractJsonField(response, "itemName")
    If questSubTypeStr == ""
        questSubTypeStr = "combat"
    EndIf

    ; Jarls never travel personally — reject DIRECT mode (sender empty = npc IS the quest giver)
    If IntelEngine.IsJarl(npc) && (senderName == "" || senderName == npc.GetDisplayName())
        Core.DebugMsg("Story DM: quest rejected -- Jarl " + npc.GetDisplayName() + " cannot deliver quest personally (needs courier)")
        return
    EndIf

    If questLocationStr == "" || enemyType == ""
        Core.DebugMsg("Story DM: quest missing questLocation or enemyType")
        return
    EndIf

    ; Validate rescue victim
    Actor victimActor = None
    If questSubTypeStr == "rescue" && victimName != ""
        victimActor = IntelEngine.FindNPCByName(victimName)
        If victimActor == None || victimActor.IsDead() || victimActor.IsDisabled()
            Core.DebugMsg("Story DM: quest/rescue victim '" + victimName + "' not found or invalid, rejecting")
            return
        EndIf
        ; Victim cannot be the quest giver or the courier
        If victimActor == npc
            Core.DebugMsg("Story DM: quest/rescue rejected -- victim '" + victimName + "' is the courier NPC")
            return
        EndIf
        If senderName != "" && victimName == senderName
            Core.DebugMsg("Story DM: quest/rescue rejected -- victim '" + victimName + "' is the quest giver")
            return
        EndIf
        ; Hard cooldown — victim was recently used in a quest or story dispatch
        If IntelEngine.IsActorOnStoryCooldown(victimActor)
            Core.DebugMsg("Story DM: quest/rescue rejected -- victim '" + victimName + "' is on story cooldown")
            return
        EndIf
    ElseIf questSubTypeStr == "rescue" && victimName == ""
        Core.DebugMsg("Story DM: quest/rescue rejected -- no victimName")
        return
    EndIf

    ; Validate find_item item name
    If questSubTypeStr == "find_item"
        If itemName == "" || !IntelEngine.ValidateQuestItem(itemName)
            ; Try fallback: get a random valuable item
            itemName = IntelEngine.GetRandomQuestItemName(500)
            If itemName == ""
                Core.DebugMsg("Story DM: quest/find_item rejected -- no valid item found")
                return
            EndIf
            Core.DebugMsg("Story DM: quest/find_item -- LLM item not found, using fallback: " + itemName)
        EndIf
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

    ; Sub-type specific fact injection
    If questSubTypeStr == "rescue" && victimActor != None
        Core.InjectFact(victimActor, "was captured by " + enemyType + " near " + questLocationStr + " and held against my will")
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

    ; Set sub-type state
    QuestSubType = questSubTypeStr
    QuestVictimNPC = victimActor
    QuestVictimName = victimName
    QuestItemDesc = itemDesc
    QuestItemName = itemName
    QuestVictimFreed = false
    QuestItemChest = None

    ; Track used items/victims/locations for rotation (avoids repeats across quests)
    If questLocationStr != ""
        IntelEngine.NotifyQuestLocationUsed(questLocationStr)
    EndIf
    If questSubTypeStr == "find_item" && itemName != ""
        IntelEngine.NotifyQuestItemUsed(itemName)
    EndIf
    If questSubTypeStr == "rescue" && victimName != ""
        IntelEngine.NotifyRescueVictimUsed(victimName)
    EndIf

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

    ; Both direct and courier paths show the quest dialog. The only difference:
    ; direct NPCs can offer to guide (they know the way), couriers cannot.
    ; Prevent re-entry: Utility.Wait is latent (yields thread), so OnUpdate
    ; keeps firing during the wait. IsActive=false stops CheckStoryNPCArrival
    ; from calling OnQuestNPCArrived again. BeginQuestGuide/FinishArrivalWithLinger
    ; handle restoring IsActive as needed.
    IsActive = false
    ; Pin the NPC in place with a high-priority sandbox so SkyrimNet's TalkToPlayer
    ; (priority 1) can't override and walk them away during the wait.
    ; Uses PRIORITY_TRAVEL (100) to beat TalkToPlayer without nuking SkyrimNet packages.
    PO3_SKSEFunctions.SetLinkedRef(ActiveStoryNPC, ActiveStoryNPC as ObjectReference, Core.IntelEngine_TravelTarget)
    ActorUtil.AddPackageOverride(ActiveStoryNPC, Core.SandboxNearPlayerPackage, Core.PRIORITY_TRAVEL, 1)
    ActiveStoryNPC.EvaluatePackage()
    ; Delay before quest prompt so NPC has time to talk
    Utility.Wait(15.0)
    ; Bail out if NPC became invalid during the wait
    If ActiveStoryNPC == None || ActiveStoryNPC.IsDead() || ActiveStoryNPC.IsInCombat()
        If ActiveStoryNPC != None
            Int questSlot = Core.FindSlotByAgent(ActiveStoryNPC)
            If questSlot >= 0
                Core.ClearSlot(questSlot)
            EndIf
            Core.RemoveAllPackages(ActiveStoryNPC, false)
        EndIf
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
    ; Remove the pinning sandbox before showing dialog (travel/linger packages get applied after)
    ActorUtil.RemovePackageOverride(ActiveStoryNPC, Core.SandboxNearPlayerPackage)
    ; Build sub-type-specific prompt text
    String questPromptText = ""
    If QuestSubType == "rescue"
        questPromptText = ActiveStoryNPC.GetDisplayName() + " pleads for help rescuing " + QuestVictimName + " near " + questLoc + "."
    ElseIf QuestSubType == "find_item"
        questPromptText = ActiveStoryNPC.GetDisplayName() + " tells you about " + QuestItemDesc + " near " + questLoc + "."
    Else
        questPromptText = ActiveStoryNPC.GetDisplayName() + " tells you about trouble near " + questLoc + "."
    EndIf

    String choice = ""
    ; Couriers and followers can't guide (couriers don't know the way,
    ; followers' FollowPlayer package conflicts with travel package)
    Bool canGuide = isDirect && !ActiveStoryNPC.IsPlayerTeammate()
    If canGuide
        choice = SkyMessage.Show(questPromptText, "Lead the way", "I'll go alone", "Not interested")
    Else
        choice = SkyMessage.Show(questPromptText, "I'll check it out", "Not interested")
        ; Map "I'll check it out" to the "I'll go alone" path
        If choice == "I'll check it out"
            choice = "I'll go alone"
        EndIf
    EndIf
    If choice == "Lead the way"
        PrePlaceQuestTargets()
        PlaceQuestMarker()
        AddRecentStoryEvent("quest: " + ActiveStoryNPC.GetDisplayName() + " guiding to " + questLoc)
        BeginQuestGuide(ActiveStoryNPC)
        return
    ElseIf choice == "Not interested"
        ; Cancel quest entirely
        Actor refusedNPC = ActiveStoryNPC  ; save before CleanupQuest nulls ActiveStoryNPC
        Core.SendTaskNarration(refusedNPC, "was told that " + Game.GetPlayer().GetDisplayName() + " wasn't interested in helping", Game.GetPlayer())
        ; Notify quest giver that player refused (works whether giver is courier or separate NPC)
        If QuestGiver != None
            Core.InjectFact(QuestGiver, "learned that " + Game.GetPlayer().GetDisplayName() + " refused to help with the " + QuestEnemyType + " threat at " + QuestLocationName)
        EndIf
        RemoveQuestMarker()  ; completed=false: hides objective without "quest completed" notification
        CleanupQuest()
        FinishArrivalWithLinger(refusedNPC, Game.GetPlayer() as ObjectReference)
        return
    EndIf
    ; "I'll go alone" / "I'll check it out" — narrate, player goes with map marker
    Core.SendTaskNarration(ActiveStoryNPC, "was told that " + Game.GetPlayer().GetDisplayName() + " would handle it", Game.GetPlayer())
    Core.NotifyPlayer("Quest: " + msgContent + " [" + questLoc + "]")

    ; Pre-place victim/chest/enemies at boss room if DungeonIndex has data
    PrePlaceQuestTargets()
    ; Place marker (points at victim/chest if pre-placed, else exterior location)
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
; QUEST PRE-PLACEMENT (vanilla-style: place targets at boss room before player enters)
; =============================================================================

Function PrePlaceQuestTargets()
    {Pre-place victim/chest/boss at dungeon boss room when DungeonIndex has data.
     Called at quest acceptance (both "I'll go alone" and "Lead the way" paths).
     Regular enemies are deferred to cell load (need loaded cell for AI init).}

    ObjectReference bossAnchor = IntelEngine.GetDungeonBossAnchor(QuestLocationName)
    If bossAnchor == None
        Core.DebugMsg("Story [quest/" + QuestSubType + "]: no dungeon boss anchor for '" + QuestLocationName + "' — using deferred spawn")
        return
    EndIf

    QuestBossAnchor = bossAnchor
    Core.DebugMsg("Story [quest/" + QuestSubType + "]: pre-placing at boss anchor in '" + QuestLocationName + "'")

    ; === RESCUE: place victim at boss room ===
    If QuestSubType == "rescue" && QuestVictimNPC != None
        Core.RemoveAllPackages(QuestVictimNPC, false)
        QuestVictimNPC.MoveTo(bossAnchor, Utility.RandomFloat(-150.0, 150.0), Utility.RandomFloat(-150.0, 150.0), 0.0)
        StorageUtil.SetIntValue(QuestVictimNPC, "Intel_WasEssential", QuestVictimNPC.IsEssential() as Int)
        QuestVictimNPC.GetActorBase().SetEssential(true)
        QuestVictimNPC.SetNoBleedoutRecovery(true)
        QuestVictimNPC.DamageActorValue("Health", QuestVictimNPC.GetActorValue("Health") + 100.0)
        QuestVictimNPC.EvaluatePackage()
        IntelEngine.NotifyStoryCooldown(QuestVictimNPC, Utility.GetCurrentGameTime())
        Core.DebugMsg("Story [quest/rescue]: victim " + QuestVictimNPC.GetDisplayName() + " placed at boss room in bleedout")
    EndIf

    ; === FIND_ITEM: spawn chest near player, then MoveTo boss room ===
    ; PlaceObjectAtMe needs a loaded cell, so spawn at player (in dialogue — invisible)
    ; then immediately move to the unloaded boss anchor. Same pattern as victim MoveTo.
    If QuestSubType == "find_item" && QuestItemName != ""
        Actor player = Game.GetPlayer()
        ObjectReference chest = IntelEngine.SpawnQuestChest(player, QuestItemName)
        If chest != None
            chest.MoveTo(bossAnchor, Utility.RandomFloat(-100.0, 100.0), Utility.RandomFloat(-100.0, 100.0), 0.0)
            QuestItemChest = chest
            Core.DebugMsg("Story [quest/find_item]: chest with " + QuestItemName + " placed at boss room")
        EndIf
    EndIf

    ; === COMBAT: spawn boss near player, then MoveTo boss room ===
    ; Same pattern as find_item chest — PlaceObjectAtMe at player, then MoveTo anchor.
    ; Boss serves as the compass target so the marker leads INSIDE the dungeon.
    If QuestSubType == "combat"
        Actor player = Game.GetPlayer()
        Actor boss = IntelEngine.SpawnQuestBoss(player, QuestEnemyType)
        If boss != None
            boss.MoveTo(bossAnchor, Utility.RandomFloat(-150.0, 150.0), Utility.RandomFloat(-150.0, 150.0), 0.0)
            QuestBossNPC = boss
            StorageUtil.FormListAdd(player, "Intel_QuestSpawnedNPCs", boss)
            QuestSpawnCount += 1
            Core.DebugMsg("Story [quest/combat]: boss placed at boss room")
        EndIf
    EndIf

    ; Regular enemies are NOT spawned here — they need a loaded cell for AI init.
    ; They spawn when the boss room cell loads (CheckQuestProximity monitors
    ; QuestBossAnchor.Is3DLoaded() and spawns directly at the anchor).
    QuestPrePlaced = true
    Core.DebugMsg("Story [quest/" + QuestSubType + "]: pre-placed target at boss anchor in '" + QuestLocationName + "', enemies deferred to cell load")
EndFunction

; =============================================================================
; QUEST PROXIMITY + SPAWN + COMPLETION
; =============================================================================

Function CheckQuestProximity()
    If !QuestActive || QuestLocation == None || QuestGuideActive
        return
    EndIf

    ; Don't spawn enemies while the quest courier is still traveling to the player.
    ; ActiveStoryType == "quest" means the courier hasn't arrived and prompted yet.
    ; Without this, if the player is already at the quest location when the DM
    ; dispatches a quest, enemies spawn before the courier even reaches them.
    If ActiveStoryType == "quest"
        return
    EndIf

    If !QuestEnemiesSpawned
        ; === Pre-placed quests: spawn enemies/chest when boss room cell loads ===
        ; The boss anchor was set by PrePlaceQuestTargets (victim already MoveTo'd there).
        ; We wait for Is3DLoaded() so PlaceObjectAtMe works directly at the anchor —
        ; nothing ever appears near the player.
        If QuestPrePlaced && QuestBossAnchor != None
            ; Spawn trigger: boss anchor cell loaded OR player is near the victim.
            ; The anchor ref might be in a different cell than where the victim ended up
            ; (e.g., fort tower vs cave interior), so also check victim proximity.
            Bool bossLoaded = QuestBossAnchor.Is3DLoaded()
            Bool targetNearby = false
            If !bossLoaded && QuestSubType == "rescue" && QuestVictimNPC != None && QuestVictimNPC.Is3DLoaded()
                targetNearby = Game.GetPlayer().GetDistance(QuestVictimNPC) < 2000.0
            ElseIf !bossLoaded && QuestSubType == "combat" && QuestBossNPC != None && QuestBossNPC.Is3DLoaded()
                targetNearby = Game.GetPlayer().GetDistance(QuestBossNPC) < 2000.0
            EndIf
            If bossLoaded || targetNearby
                If targetNearby && !bossLoaded
                    Core.DebugMsg("Story [quest]: pre-placed target nearby but boss anchor not loaded — safety spawn")
                Else
                    Core.DebugMsg("Story [quest]: boss room cell loaded — spawning enemies/chest at anchor")
                EndIf
                ; Use pre-placed target as spawn point if anchor isn't loaded
                ObjectReference spawnPoint = QuestBossAnchor
                If targetNearby && !bossLoaded
                    If QuestSubType == "rescue" && QuestVictimNPC != None
                        spawnPoint = QuestVictimNPC as ObjectReference
                    ElseIf QuestSubType == "combat" && QuestBossNPC != None
                        spawnPoint = QuestBossNPC as ObjectReference
                    EndIf
                EndIf
                Actor player = Game.GetPlayer()

                ; Chest already placed at dispatch time (PrePlaceQuestTargets) — no need to spawn here

                ; Spawn enemies at spawn point. Disable before move to prevent detection
                ; system race (crash) and hide visual pop-in from the player.
                Actor[] enemies = IntelEngine.SpawnQuestEnemies(spawnPoint, QuestEnemyType)
                Int i = 0
                While i < enemies.Length
                    enemies[i].DisableNoWait()
                    enemies[i].MoveTo(spawnPoint, Utility.RandomFloat(-300.0, 300.0), Utility.RandomFloat(-300.0, 300.0), 0.0)
                    StorageUtil.FormListAdd(player, "Intel_QuestSpawnedNPCs", enemies[i])
                    i += 1
                EndWhile

                ; Spawn boss if not already pre-placed (combat pre-places boss at dispatch time)
                Actor boss = None
                If QuestBossNPC == None
                    boss = IntelEngine.SpawnQuestBoss(spawnPoint, QuestEnemyType)
                    If boss != None
                        boss.DisableNoWait()
                        boss.MoveTo(spawnPoint, Utility.RandomFloat(-150.0, 150.0), Utility.RandomFloat(-150.0, 150.0), 0.0)
                        QuestBossNPC = boss
                        StorageUtil.FormListAdd(player, "Intel_QuestSpawnedNPCs", boss)
                    EndIf
                EndIf

                ; Enable all enemies at their final positions (after all moves complete)
                i = 0
                While i < enemies.Length
                    enemies[i].EnableNoWait()
                    i += 1
                EndWhile
                If boss != None
                    boss.EnableNoWait()
                EndIf

                QuestSpawnCount = enemies.Length
                If QuestBossNPC != None
                    QuestSpawnCount += 1
                EndIf
                If QuestSpawnCount > 0
                    QuestEnemiesSpawned = true
                    Core.DebugMsg("Story [quest/" + QuestSubType + "]: spawned " + QuestSpawnCount + " " + QuestEnemyType + " at boss room")
                Else
                    Core.DebugMsg("Story [quest]: WARNING - no enemies spawned at boss room, falling back to deferred")
                EndIf

                ; Re-apply bleedout NOW — dispatch-time state doesn't survive unloaded cells.
                ; Without this, the victim walks normally when their cell first loads.
                If QuestSubType == "rescue" && QuestVictimNPC != None && !QuestVictimFreed && !QuestVictimInFurniture
                    QuestVictimNPC.SetNoBleedoutRecovery(true)
                    QuestVictimNPC.DamageActorValue("Health", QuestVictimNPC.GetActorValue("Health") + 100.0)
                    QuestVictimNPC.EvaluatePackage()
                    Core.DebugMsg("Story [quest/rescue]: re-applied bleedout on first 3D load")
                EndIf
            EndIf
            return  ; Pre-placed quests don't use the proximity-based spawn path below
        EndIf

        ; Never spawn quest enemies while the player is in a safe interior (inn, shop, home).
        ; Is3DLoaded() on exterior markers can return true from inside a nearby building,
        ; which would spawn bandits in The Bannered Mare when the quest is at Nilheim.
        ; Exception: if we already deferred to interior (dungeon entrance found), trust that
        ; the player is entering the quest dungeon — don't skip even if location keywords miss.
        Actor player = Game.GetPlayer()
        If player.IsInInterior() && !QuestDeferredToInterior && !IntelEngine.IsPlayerInDangerousLocation()
            return
        EndIf

        Bool atQuestArea = false
        ; --- Layer 1: 3D + distance ---
        ; Is3DLoaded() fires when the marker's 3D mesh is loaded — this includes
        ; nearby-but-different locations (e.g., Nilheim visible from Ivarstead).
        ; Add a distance gate: player must be within 4000 units (~58m) of the marker.
        If QuestLocation.Is3DLoaded()
            Float dist = IntelEngine.GetDistance3D(player, QuestLocation)
            If dist < 4000.0
                atQuestArea = true
            EndIf
        EndIf
        ; --- Layer 2: same cell ---
        If !atQuestArea
            Cell questCell = QuestLocation.GetParentCell()
            Cell playerCell = player.GetParentCell()
            If questCell != None && playerCell != None && questCell == playerCell
                atQuestArea = true
                Core.DebugMsg("Story [quest]: same-cell spawn fallback triggered")
            EndIf
        EndIf
        ; --- Layer 3: BGSLocation hierarchy ---
        ; Handles interior dungeons where QuestLocation is an exterior MapMarkerREF
        If !atQuestArea
            Location questLoc = QuestLocation.GetCurrentLocation()
            If questLoc != None && player.IsInLocation(questLoc)
                atQuestArea = true
                Core.DebugMsg("Story [quest]: BGSLocation spawn fallback triggered")
            EndIf
        EndIf
        ; --- Layer 4: deferred interior entry ---
        ; When we previously detected a dungeon entrance near the quest marker and
        ; deferred spawning, the player is now inside. The exterior marker may be
        ; unloaded (Layer 1 fails), in a different cell (Layer 2 fails), and BGSLocation
        ; hierarchy may not link the interior (Layer 3 fails). Since we already deferred
        ; and the safe interior guard already filtered inns/shops, any interior is the dungeon.
        If !atQuestArea && QuestDeferredToInterior && player.IsInInterior()
            atQuestArea = true
            Core.DebugMsg("Story [quest]: deferred interior entry — player entered dungeon")
        EndIf
        If atQuestArea
            If !player.IsInInterior()
                ; Player is outside near the quest marker.
                ; Check if there's a dungeon entrance nearby — if so, defer spawning
                ; so the player explores the dungeon and we spawn deep inside.
                If !QuestDeferredToInterior
                    If IntelEngine.HasNearbyDungeonEntrance(QuestLocation)
                        QuestDeferredToInterior = true
                        Core.DebugMsg("Story [quest]: dungeon entrance found, deferring spawn until player enters")
                    Else
                        ; Pure exterior camp — no dungeon nearby, spawn immediately
                        SpawnQuestEnemies()
                    EndIf
                Else
                    Core.DebugMsg("Story [quest]: waiting for player to enter dungeon")
                EndIf
            Else
                ; Player is in a dangerous interior. Scan cells AHEAD (through
                ; doors) for cages, shackles, boss chests — anything that makes
                ; a good anchor. Place victim + enemies there immediately.
                ; The anchor is always 1+ door ahead = invisible to player.
                Cell currentCell = player.GetParentCell()
                If QuestDungeonLastCell == None
                    QuestDungeonLastCell = currentCell
                    QuestDungeonDepth = 0
                ElseIf currentCell != QuestDungeonLastCell
                    QuestDungeonLastCell = currentCell
                    QuestDungeonDepth += 1
                EndIf
                Core.DebugMsg("Story [quest]: dungeon depth " + QuestDungeonDepth + ", scanning ahead...")

                ; Scan cells beyond doors for cages/landmarks
                ObjectReference aheadAnchor = IntelEngine.ScanAheadForAnchor(player)
                If aheadAnchor != None
                    ; Found a cage/landmark in the next cell — place everything there
                    Core.DebugMsg("Story [quest]: anchor found ahead! Placing victim + enemies")
                    QuestBossAnchor = aheadAnchor

                    ; Place victim at anchor (rescue)
                    If QuestSubType == "rescue" && QuestVictimNPC != None
                        Core.RemoveAllPackages(QuestVictimNPC, false)
                        QuestVictimNPC.MoveTo(aheadAnchor, Utility.RandomFloat(-100.0, 100.0), Utility.RandomFloat(-100.0, 100.0), 0.0)
                        StorageUtil.SetIntValue(QuestVictimNPC, "Intel_WasEssential", QuestVictimNPC.IsEssential() as Int)
                        QuestVictimNPC.GetActorBase().SetEssential(true)
                        QuestVictimNPC.SetNoBleedoutRecovery(true)
                        QuestVictimNPC.DamageActorValue("Health", QuestVictimNPC.GetActorValue("Health") + 100.0)
                        QuestVictimNPC.EvaluatePackage()
                        IntelEngine.NotifyStoryCooldown(QuestVictimNPC, Utility.GetCurrentGameTime())
                        ; Move marker to victim immediately
                        If QuestTargetAlias != None
                            QuestTargetAlias.ForceRefTo(QuestVictimNPC)
                            SetObjectiveDisplayed(QUEST_OBJECTIVE_ID, false)
                            Utility.Wait(0.1)
                            SetObjectiveDisplayed(QUEST_OBJECTIVE_ID, true)
                        EndIf
                        Core.DebugMsg("Story [quest/rescue]: victim placed at ahead anchor in bleedout")
                    EndIf

                    ; Place chest at anchor (find_item)
                    If QuestSubType == "find_item" && QuestItemName != "" && QuestItemChest == None
                        ObjectReference chest = IntelEngine.SpawnQuestChest(aheadAnchor, QuestItemName)
                        If chest != None
                            QuestItemChest = chest
                            If QuestTargetAlias != None
                                QuestTargetAlias.ForceRefTo(QuestItemChest)
                                SetObjectiveDisplayed(QUEST_OBJECTIVE_ID, false)
                                Utility.Wait(0.1)
                                SetObjectiveDisplayed(QUEST_OBJECTIVE_ID, true)
                            EndIf
                            Core.DebugMsg("Story [quest/find_item]: chest placed at ahead anchor")
                        EndIf
                    EndIf

                    ; Spawn enemies at anchor. Disable before move to prevent detection crash.
                    Actor[] enemies = IntelEngine.SpawnQuestEnemies(aheadAnchor, QuestEnemyType)
                    Int idx = 0
                    While idx < enemies.Length
                        enemies[idx].DisableNoWait()
                        enemies[idx].MoveTo(aheadAnchor, Utility.RandomFloat(-300.0, 300.0), Utility.RandomFloat(-300.0, 300.0), 0.0)
                        StorageUtil.FormListAdd(player, "Intel_QuestSpawnedNPCs", enemies[idx])
                        idx += 1
                    EndWhile
                    Actor boss = IntelEngine.SpawnQuestBoss(aheadAnchor, QuestEnemyType)
                    If boss != None
                        boss.DisableNoWait()
                        boss.MoveTo(aheadAnchor, Utility.RandomFloat(-150.0, 150.0), Utility.RandomFloat(-150.0, 150.0), 0.0)
                        QuestBossNPC = boss
                        StorageUtil.FormListAdd(player, "Intel_QuestSpawnedNPCs", boss)
                    EndIf
                    ; Enable all at final positions
                    idx = 0
                    While idx < enemies.Length
                        enemies[idx].EnableNoWait()
                        idx += 1
                    EndWhile
                    If boss != None
                        boss.EnableNoWait()
                    EndIf
                    QuestSpawnCount = enemies.Length
                    If boss != None
                        QuestSpawnCount += 1
                    EndIf
                    If QuestSpawnCount > 0
                        QuestEnemiesSpawned = true
                    EndIf
                    QuestPrePlaced = true
                    Core.DebugMsg("Story [quest/" + QuestSubType + "]: placed " + QuestSpawnCount + " enemies at ahead anchor")
                Else
                    ; No anchor found this tick — track failed scans
                    QuestDungeonScanFails += 1
                    If QuestDungeonDepth >= 3 || QuestDungeonScanFails >= 5
                        ; Enough attempts — spawn near player as last resort
                        Core.DebugMsg("Story [quest]: no anchors found (depth=" + QuestDungeonDepth + ", scans=" + QuestDungeonScanFails + ") — using fallback spawn")
                        SpawnQuestEnemies()
                    EndIf
                EndIf
            EndIf
        EndIf
    Else
        If QuestSubType == "find_item"
            ; Find item: complete when player takes the specific quest item (enemies optional)
            If QuestItemChest != None && QuestItemName != "" && !IntelEngine.IsQuestItemInChest(QuestItemChest, QuestItemName)
                Core.DebugMsg("Story [quest/find_item]: quest item '" + QuestItemName + "' retrieved from chest")
                OnQuestComplete()
            EndIf
        ElseIf QuestSubType == "rescue"
            ; === Maintenance: furniture scan (once) + state re-apply (every tick) ===
            ; Runs before completion checks so victim state is correct when player arrives.
            If !QuestVictimFreed && QuestVictimNPC != None && QuestVictimNPC.Is3DLoaded()
                ; One-time furniture scan when victim's cell preloads
                If QuestPrePlaced && !QuestFurnitureScanned
                    QuestFurnitureScanned = true
                    ObjectReference usableFurn = IntelEngine.FindUsablePrisonerFurniture(QuestVictimNPC)
                    If usableFurn != None
                        ; Switch from bleedout to furniture: recover health first
                        QuestVictimNPC.SetNoBleedoutRecovery(false)
                        QuestVictimNPC.RestoreActorValue("Health", 500.0)
                        QuestVictimNPC.SetRestrained(false)
                        QuestVictimNPC.SetDontMove(false)
                        QuestVictimNPC.MoveTo(usableFurn, 0.0, 0.0, 0.0)
                        usableFurn.Activate(QuestVictimNPC)
                        QuestVictimNPC.SetDontMove(true)
                        QuestVictimInFurniture = true
                        Core.DebugMsg("Story [quest/rescue]: victim activated usable furniture in boss room")
                    Else
                        ObjectReference prisonFurn = IntelEngine.FindPrisonerFurniture(QuestVictimNPC)
                        If prisonFurn != None
                            QuestVictimNPC.MoveTo(prisonFurn, 0.0, 0.0, 0.0)
                            Core.DebugMsg("Story [quest/rescue]: nudged victim to decorative prison prop in boss room")
                        EndIf
                        QuestVictimNPC.SetNoBleedoutRecovery(true)
                        QuestVictimNPC.DamageActorValue("Health", QuestVictimNPC.GetActorValue("Health") + 100.0)
                        QuestVictimNPC.EvaluatePackage()
                    EndIf
                EndIf
                ; Per-tick state re-apply (runtime state can be lost anytime)
                If QuestVictimInFurniture
                    QuestVictimNPC.SetDontMove(true)
                Else
                    ; Bleedout: only SetNoBleedoutRecovery. No SetRestrained/SetDontMove — they override bleedout anim.
                    QuestVictimNPC.SetNoBleedoutRecovery(true)
                    If QuestVictimNPC.GetActorValue("Health") > 1.0
                        QuestVictimNPC.DamageActorValue("Health", QuestVictimNPC.GetActorValue("Health") + 100.0)
                        QuestVictimNPC.EvaluatePackage()
                        Core.DebugMsg("Story [quest/rescue]: re-applied bleedout to " + QuestVictimNPC.GetDisplayName())
                    EndIf
                EndIf
            EndIf

            ; === Completion checks ===
            If QuestVictimNPC != None && QuestVictimNPC.IsDead()
                Core.DebugMsg("Story [quest/rescue]: victim " + QuestVictimName + " died — quest failed")
                OnQuestFailed()
            ElseIf AreAllQuestEnemiesDead() && IsAreaClearOfHostiles()
                ; Auto-complete: all quest enemies dead + area clear
                If !QuestVictimFreed
                    FreeQuestVictim()
                EndIf
                OnQuestComplete()
            ElseIf !QuestVictimFreed && QuestVictimNPC != None && QuestVictimNPC.Is3DLoaded()
                ; Manual free: player walks up to victim (200 units) while NOT in combat — fallback if enemies are stuck
                Actor player = Game.GetPlayer()
                If !player.IsInCombat() && player.GetDistance(QuestVictimNPC) < 200.0
                    FreeQuestVictim()
                    OnQuestComplete()
                EndIf
            EndIf
        Else
            ; Combat: enemies dead → complete
            If AreAllQuestEnemiesDead()
                OnQuestComplete()
            EndIf
        EndIf
    EndIf
EndFunction

Function SpawnQuestEnemies()
    If QuestEnemiesSpawned
        return
    EndIf

    QuestSpawnAttempts += 1

    ; Determine spawn anchors. Rescue uses SEPARATE anchors for victim (deep) and
    ; enemies (near player). Other types use a single anchor for both.
    ; For exteriors: use the quest location marker directly.
    Actor player = Game.GetPlayer()
    ObjectReference victimAnchor = QuestLocation
    ObjectReference enemyAnchor = QuestLocation
    If player.IsInInterior()
        ; Block spawns in safe interiors (inns, shops, homes).
        If !IntelEngine.IsPlayerInDangerousLocation()
            Core.DebugMsg("Story [quest/" + QuestSubType + "]: blocked spawn in safe interior")
            return
        EndIf
        If QuestSubType == "rescue"
            ; Deep scan: follows doors to adjacent cells for prisoner furniture
            ObjectReference rescuePoint = IntelEngine.FindRescueAnchor(player)
            If rescuePoint != None
                victimAnchor = rescuePoint
                enemyAnchor = player    ; enemies between player and victim
                Core.DebugMsg("Story [quest/rescue]: victim deep at rescue anchor, enemies near player")
            Else
                victimAnchor = player
                enemyAnchor = player
                Core.DebugMsg("Story [quest/rescue]: no rescue anchor found, spawning near player")
            EndIf
        Else
            ; find_item / combat: deeper dungeon point or player
            ObjectReference deeperPoint = IntelEngine.FindDeeperSpawnPoint(player)
            If deeperPoint != None
                victimAnchor = deeperPoint
                enemyAnchor = deeperPoint
                Core.DebugMsg("Story [quest/" + QuestSubType + "]: spawning at dungeon landmark")
            Else
                victimAnchor = player
                enemyAnchor = player
                Core.DebugMsg("Story [quest/" + QuestSubType + "]: no landmarks found, spawning near player")
            EndIf
        EndIf
    EndIf

    ; === Rescue sub-type: teleport victim DEEP inside ===
    If QuestSubType == "rescue" && QuestVictimNPC != None
        ; Strip all packages BEFORE teleport+restrain (packages can override restraint)
        Core.RemoveAllPackages(QuestVictimNPC, false)
        QuestVictimNPC.MoveTo(victimAnchor, 0.0, 0.0, 0.0, false)
        ; Protect victim from death — always make essential for bleedout
        StorageUtil.SetIntValue(QuestVictimNPC, "Intel_WasEssential", QuestVictimNPC.IsEssential() as Int)
        QuestVictimNPC.GetActorBase().SetEssential(true)
        ; Trigger natural bleedout: damage to 0 HP while essential → engine bleedout animation
        ; No SetRestrained/SetDontMove — they override the bleedout kneel animation
        QuestVictimNPC.SetNoBleedoutRecovery(true)
        QuestVictimNPC.DamageActorValue("Health", QuestVictimNPC.GetActorValue("Health") + 100.0)
        QuestVictimNPC.EvaluatePackage()
        Core.DebugMsg("Story [quest/rescue]: placed victim " + QuestVictimNPC.GetDisplayName() + " in bleedout")
        ; Apply story cooldown to the victim so they can't be re-kidnapped soon
        IntelEngine.NotifyStoryCooldown(QuestVictimNPC, Utility.GetCurrentGameTime())
        ; Move quest marker to the victim and refresh display
        If QuestTargetAlias != None
            QuestTargetAlias.ForceRefTo(QuestVictimNPC)
            SetObjectiveDisplayed(QUEST_OBJECTIVE_ID, false)
            Utility.Wait(0.1)
            SetObjectiveDisplayed(QUEST_OBJECTIVE_ID, true)
            Core.DebugMsg("Story [quest/rescue]: quest marker moved to victim")
        EndIf
    EndIf

    ; === Find item sub-type: spawn chest with item ===
    If QuestSubType == "find_item" && QuestItemName != ""
        ObjectReference chest = IntelEngine.SpawnQuestChest(victimAnchor, QuestItemName)
        If chest != None
            QuestItemChest = chest
            Core.DebugMsg("Story [quest/find_item]: placed chest with " + QuestItemName + " at " + QuestLocationName)
            ; Move quest marker to the chest and refresh display
            If QuestTargetAlias != None
                QuestTargetAlias.ForceRefTo(QuestItemChest)
                SetObjectiveDisplayed(QUEST_OBJECTIVE_ID, false)
                Utility.Wait(0.1)
                SetObjectiveDisplayed(QUEST_OBJECTIVE_ID, true)
                Core.DebugMsg("Story [quest/find_item]: quest marker moved to chest")
            EndIf
            ; Spawn boss near the chest (mandatory for find_item)
            Actor boss = IntelEngine.SpawnQuestBoss(QuestItemChest, QuestEnemyType)
            If boss != None
                QuestBossNPC = boss
                StorageUtil.FormListAdd(player, "Intel_QuestSpawnedNPCs", boss)
                QuestSpawnCount += 1
                Core.DebugMsg("Story [quest/find_item]: spawned boss near chest")
            EndIf
        Else
            Core.DebugMsg("Story [quest/find_item]: WARNING - chest spawn failed for " + QuestItemName)
        EndIf
    EndIf

    ; === Spawn enemies at anchor with offset spread (prevent clipping) ===
    Actor[] spawnedActors = IntelEngine.SpawnQuestEnemies(enemyAnchor, QuestEnemyType)
    Int regularCount = spawnedActors.Length
    QuestSpawnCount += regularCount

    If regularCount > 0
        ; Disable, spread with offsets, then enable (same pattern as pre-placed path)
        Int i = 0
        While i < regularCount
            spawnedActors[i].DisableNoWait()
            spawnedActors[i].MoveTo(enemyAnchor, Utility.RandomFloat(-300.0, 300.0), Utility.RandomFloat(-300.0, 300.0), 0.0)
            StorageUtil.FormListAdd(player, "Intel_QuestSpawnedNPCs", spawnedActors[i])
            i += 1
        EndWhile
        i = 0
        While i < regularCount
            spawnedActors[i].EnableNoWait()
            i += 1
        EndWhile

        ; Spawn boss if not already pre-placed
        If QuestBossNPC == None
            Actor boss = IntelEngine.SpawnQuestBoss(enemyAnchor, QuestEnemyType)
            If boss != None
                boss.DisableNoWait()
                boss.MoveTo(enemyAnchor, Utility.RandomFloat(-150.0, 150.0), Utility.RandomFloat(-150.0, 150.0), 0.0)
                QuestBossNPC = boss
                StorageUtil.FormListAdd(player, "Intel_QuestSpawnedNPCs", boss)
                QuestSpawnCount += 1
                boss.EnableNoWait()
            EndIf
        EndIf

        QuestEnemiesSpawned = true
        Core.DebugMsg("Story [quest/" + QuestSubType + "]: spawned " + QuestSpawnCount + " " + QuestEnemyType + " at " + QuestLocationName)

        ; Update compass to boss for combat quests (marker was on entrance before enemies spawned)
        If QuestSubType == "combat" && QuestBossNPC != None && QuestTargetAlias != None
            QuestTargetAlias.ForceRefTo(QuestBossNPC)
            SetObjectiveDisplayed(QUEST_OBJECTIVE_ID, false)
            Utility.Wait(0.1)
            SetObjectiveDisplayed(QUEST_OBJECTIVE_ID, true)
            Core.DebugMsg("Story [quest/combat]: quest marker moved to boss")
        EndIf
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
        ; Treat None, dead, deleted, or disabled enemies as "gone" — prevents quest
        ; hanging forever if enemies clipped into geometry or fell through the world.
        If spawned != None && !spawned.IsDead() && !spawned.IsDeleted() && !spawned.IsDisabled()
            return false
        EndIf
        i += 1
    EndWhile
    return true
EndFunction

Bool Function IsAreaClearOfHostiles()
    {Returns false if any living hostile NPC is near the rescue victim.
    Uses MiscUtil.ScanCellNPCs to scan ALL nearby actors, not just quest-spawned.}
    If QuestVictimNPC == None
        return true
    EndIf
    Actor player = Game.GetPlayer()
    Actor[] nearbyNPCs = MiscUtil.ScanCellNPCs(QuestVictimNPC, 3000.0)
    Int i = 0
    While i < nearbyNPCs.Length
        Actor npc = nearbyNPCs[i]
        If npc != player && npc != QuestVictimNPC && npc.IsHostileToActor(player)
            return false
        EndIf
        i += 1
    EndWhile
    return true
EndFunction

Function FreeQuestVictim()
    If QuestVictimNPC == None || QuestVictimFreed
        return
    EndIf
    QuestVictimFreed = true
    If QuestVictimInFurniture
        ; Furniture victim: exit the furniture by moving to self
        QuestVictimNPC.SetDontMove(false)
        QuestVictimNPC.MoveTo(QuestVictimNPC)
        QuestVictimNPC.EvaluatePackage()
        Core.DebugMsg("Story [quest/rescue]: victim " + QuestVictimNPC.GetDisplayName() + " freed from furniture")
    Else
        ; Bleedout victim: recover from bleedout
        QuestVictimNPC.SetNoBleedoutRecovery(false)
        Core.DebugMsg("Story [quest/rescue]: victim " + QuestVictimNPC.GetDisplayName() + " freed from bleedout")
    EndIf
    ; Heal victim fully after freeing
    QuestVictimNPC.RestoreActorValue("Health", 500.0)
    Core.NotifyPlayer(QuestVictimNPC.GetDisplayName() + " has been freed!")
EndFunction

Function OnQuestComplete()
    Core.DebugMsg("Story [quest/" + QuestSubType + "]: Completed at " + QuestLocationName + "!")

    String playerName = Game.GetPlayer().GetDisplayName()

    If QuestSubType == "rescue"
        ; Double-check victim is alive — IsDead() can lag behind bleedout/kill-cam
        If QuestVictimNPC != None && QuestVictimNPC.IsDead()
            Core.DebugMsg("Story [quest/rescue]: victim died before completion could finalize — redirecting to failed")
            OnQuestFailed()
            return
        EndIf
        Core.NotifyPlayer("Rescue completed!")
        If QuestGiver != None
            Core.InjectFact(QuestGiver, "learned that " + playerName + " rescued " + QuestVictimName + " from " + QuestEnemyType + " at " + QuestLocationName)
        EndIf
        If QuestVictimNPC != None
            ; Check victim's awareness of the player (0=stranger, 1=seen before, 2=acquainted)
            Int victimAwareness = IntelEngine.GetPlayerInteractionCount(QuestVictimNPC)
            If victimAwareness == 0
                ; True stranger — never been near the player, doesn't know their name
                Core.InjectFact(QuestVictimNPC, "was rescued from " + QuestEnemyType + " captivity at " + QuestLocationName + " by a stranger whose name I didn't know at the time")
                StorageUtil.SetStringValue(QuestVictimNPC, "Intel_RescueNarration", "was just freed from " + QuestEnemyType + " captivity by a stranger whose name they don't know")
            ElseIf victimAwareness == 1
                ; Seen before — witnessed the player nearby but never directly interacted
                Core.InjectFact(QuestVictimNPC, "was rescued by " + playerName + " from " + QuestEnemyType + " captivity at " + QuestLocationName + ". I recognized them — I'd seen them around before but we had never actually spoken")
                StorageUtil.SetStringValue(QuestVictimNPC, "Intel_RescueNarration", "was just freed from " + QuestEnemyType + " captivity by " + playerName + ", someone they recognized from around town but had never spoken to before")
            Else
                ; Acquainted — has direct dialogue history
                Core.InjectFact(QuestVictimNPC, "was rescued by " + playerName + " from " + QuestEnemyType + " captivity at " + QuestLocationName)
                StorageUtil.SetStringValue(QuestVictimNPC, "Intel_RescueNarration", "was just freed from " + QuestEnemyType + " captivity by " + playerName)
            EndIf
            ; Restore essential state now (before sandbox)
            Int wasEssential = StorageUtil.GetIntValue(QuestVictimNPC, "Intel_WasEssential", -1)
            If wasEssential >= 0
                QuestVictimNPC.GetActorBase().SetEssential(wasEssential as Bool)
                StorageUtil.UnsetIntValue(QuestVictimNPC, "Intel_WasEssential")
            EndIf
            ; Store rescue metadata for post-rescue death detection.
            ; CheckRescuedNPCDeaths monitors this list beyond linger release.
            If QuestGiver != None
                StorageUtil.SetFormValue(QuestVictimNPC, "Intel_RescueQuestGiver", QuestGiver)
                StorageUtil.SetStringValue(QuestVictimNPC, "Intel_RescuePlayerName", playerName)
                StorageUtil.SetFloatValue(QuestVictimNPC, "Intel_RescueTime", Utility.GetCurrentGameTime())
                ; Track in persistent list — survives linger cleanup
                Actor trackedPlayer = Game.GetPlayer()
                If StorageUtil.FormListFind(trackedPlayer, "Intel_RecentlyRescuedNPCs", QuestVictimNPC as Form) < 0
                    StorageUtil.FormListAdd(trackedPlayer, "Intel_RecentlyRescuedNPCs", QuestVictimNPC as Form)
                EndIf
            EndIf
            ; Pathfind to player — sandbox with linked ref = player.
            ; Narration deferred until NPC reaches player (CheckStoryLingerCleanup fires it).
            Core.RemoveAllPackages(QuestVictimNPC, false)
            PO3_SKSEFunctions.SetLinkedRef(QuestVictimNPC, Game.GetPlayer() as ObjectReference, Core.IntelEngine_TravelTarget)
            ActorUtil.AddPackageOverride(QuestVictimNPC, Core.SandboxNearPlayerPackage, Core.PRIORITY_SANDBOX, 1)
            Utility.Wait(0.1)
            QuestVictimNPC.EvaluatePackage()
            StartStoryLinger(QuestVictimNPC)
            ; Mark victim as handled — CleanupQuest won't teleport them
            QuestVictimNPC = None
        EndIf
    ElseIf QuestSubType == "find_item"
        Core.NotifyPlayer("Found " + QuestItemDesc + "!")
        If QuestGiver != None
            Core.InjectFact(QuestGiver, "learned that " + playerName + " found " + QuestItemDesc + " at " + QuestLocationName)
        EndIf
    Else
        Core.NotifyPlayer("Quest completed!")
        If QuestGiver != None
            Core.InjectFact(QuestGiver, "learned that " + playerName + " dealt with the " + QuestEnemyType + " threat at " + QuestLocationName)
        EndIf
    EndIf

    ; Guide NPC also learns about the outcome (if different from quest giver)
    If QuestGuideNPC != None && QuestGuideNPC != QuestGiver
        Core.InjectFact(QuestGuideNPC, "witnessed " + playerName + " clear the " + QuestEnemyType + " at " + QuestLocationName)
    EndIf

    RemoveQuestMarker(true)
    CleanupQuest()
EndFunction

Function OnQuestFailed()
    Core.DebugMsg("Story [quest/" + QuestSubType + "]: Failed at " + QuestLocationName + " — victim died")

    String playerName = Game.GetPlayer().GetDisplayName()

    Core.NotifyPlayer(QuestVictimName + " didn't make it.")
    If QuestGiver != None
        Core.InjectFact(QuestGiver, "learned that " + QuestVictimName + " was killed by " + QuestEnemyType + " at " + QuestLocationName + " despite " + playerName + "'s efforts")
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
        Core.DebugMsg("Story [quest/" + QuestSubType + "]: Expired after " + QUEST_EXPIRY_DAYS + " days")
        String playerName = Game.GetPlayer().GetDisplayName()
        If QuestSubType == "rescue"
            If QuestGiver != None
                Core.InjectFact(QuestGiver, "grew desperate -- " + QuestVictimName + " may be lost, " + playerName + " never came to help")
            EndIf
            ; Victim escape fact is handled by CleanupQuest
        ElseIf QuestSubType == "find_item"
            If QuestGiver != None
                Core.InjectFact(QuestGiver, "gave up hope that " + playerName + " would find " + QuestItemDesc + " at " + QuestLocationName)
            EndIf
        Else
            If QuestGiver != None
                Core.InjectFact(QuestGiver, "grew disappointed that " + playerName + " never dealt with the " + QuestEnemyType + " threat at " + QuestLocationName)
            EndIf
        EndIf
        RemoveQuestMarker()
        CleanupQuest()
    EndIf
EndFunction

Function CleanupQuest()
    ; Always remove the map marker/objective (idempotent — safe if never placed)
    RemoveQuestMarker()

    String eventText = "quest/" + QuestSubType + ": " + QuestEnemyType + " at " + QuestLocationName
    StorageUtil.FormListClear(Game.GetPlayer(), "Intel_QuestSpawnedNPCs")

    ; === Courier/quest giver dispatch cleanup ===
    ; If the courier is still traveling to the player (IsActive + ActiveStoryType == "quest"),
    ; clear their slot and dispatch so they don't keep searching for a cancelled quest.
    If IsActive && ActiveStoryNPC != None && ActiveStoryType == "quest"
        Int courierSlot = Core.FindSlotByAgent(ActiveStoryNPC)
        If courierSlot >= 0
            Core.ClearSlot(courierSlot)
        EndIf
        Core.RemoveAllPackages(ActiveStoryNPC, false)
        ; Don't call CleanupStoryDispatch here — it would recurse back into CleanupQuest.
        ; Instead, manually clear the dispatch state.
        StorageUtil.UnsetIntValue(ActiveStoryNPC, "Intel_IsStoryDispatch")
        StorageUtil.UnsetStringValue(ActiveStoryNPC, "Intel_StoryNarration")
        StorageUtil.UnsetStringValue(ActiveStoryNPC, "Intel_MessageSender")
        StorageUtil.UnsetStringValue(ActiveStoryNPC, "Intel_MessageContent")
        StorageUtil.UnsetStringValue(ActiveStoryNPC, "Intel_QuestLocation")
        ActiveStoryNPC = None
        ActiveNarration = ""
        ActiveStoryType = ""
        IsActive = false
        Core.DebugMsg("Story [quest]: cleared courier dispatch (quest cancelled)")
    EndIf

    If QuestGuideNPC != None
        Int slot = Core.FindSlotByAgent(QuestGuideNPC)
        If slot >= 0
            Core.ClearSlot(slot)
        EndIf
        Core.RemoveAllPackages(QuestGuideNPC, false)
    EndIf

    ; === Rescue victim cleanup ===
    If QuestVictimNPC != None
        If QuestVictimInFurniture
            QuestVictimNPC.MoveTo(QuestVictimNPC)  ; exit furniture idle
        EndIf
        QuestVictimNPC.SetRestrained(false)
        QuestVictimNPC.SetDontMove(false)
        QuestVictimNPC.SetNoBleedoutRecovery(false)
        QuestVictimNPC.RestoreActorValue("Health", 500.0)
        StorageUtil.UnsetStringValue(QuestVictimNPC, "Intel_RescueNarration")
        Core.RemoveAllPackages(QuestVictimNPC, false)
        ; Restore original essential state
        Int wasEssential = StorageUtil.GetIntValue(QuestVictimNPC, "Intel_WasEssential", -1)
        If wasEssential >= 0
            QuestVictimNPC.GetActorBase().SetEssential(wasEssential as Bool)
            StorageUtil.UnsetIntValue(QuestVictimNPC, "Intel_WasEssential")
        EndIf
        ; If victim was NOT freed by the player, they "escaped"
        If !QuestVictimFreed
            Core.InjectFact(QuestVictimNPC, "managed to escape " + QuestEnemyType + " captivity at " + QuestLocationName + " on my own")
        EndIf
        QuestVictimNPC.MoveToMyEditorLocation()
        ; Force AI re-evaluation so NPCs re-engage furniture (e.g., Jarl sits on throne)
        QuestVictimNPC.EvaluatePackage()
        QuestVictimNPC = None
    EndIf

    ; === Find item chest cleanup ===
    If QuestItemChest != None
        QuestItemChest.Disable()
        QuestItemChest.Delete()
        QuestItemChest = None
    EndIf

    QuestActive = false
    QuestGiver = None
    QuestGuideNPC = None
    QuestGuideActive = false
    QuestGuideWaiting = false
    QuestGuideStartTime = 0.0
    QuestLocation = None
    QuestDeferredToInterior = false
    QuestEnemyType = ""
    QuestLocationName = ""
    QuestEnemiesSpawned = false
    QuestSpawnCount = 0
    QuestSpawnAttempts = 0
    QuestStartTime = 0.0

    ; Reset sub-type state
    QuestSubType = ""
    QuestVictimName = ""
    QuestItemDesc = ""
    QuestItemName = ""
    QuestVictimFreed = false
    QuestBossNPC = None
    QuestPrePlaced = false
    QuestBossAnchor = None
    QuestFurnitureScanned = false
    QuestVictimInFurniture = false
    QuestDungeonLastCell = None
    QuestDungeonDepth = 0
    QuestDungeonScanFails = 0

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
    Core.DebugMsg("Story [quest]: PlaceQuestMarker - alias=" + QuestTargetAlias + ", location=" + QuestLocation + " (" + QuestLocationName + "), prePlaced=" + QuestPrePlaced + ", questRunning=" + IsRunning() + ", questActive=" + IsActive())
    ; Reset from any previous quest (completed state + display)
    SetObjectiveCompleted(QUEST_OBJECTIVE_ID, false)
    SetObjectiveDisplayed(QUEST_OBJECTIVE_ID, false)
    ; Point alias at quest target — victim/chest if pre-placed (compass points through dungeon),
    ; otherwise exterior quest location (current fallback behavior)
    If QuestPrePlaced && QuestSubType == "rescue" && QuestVictimNPC != None
        QuestTargetAlias.ForceRefTo(QuestVictimNPC)
        Core.DebugMsg("Story [quest]: marker on victim (pre-placed deep inside)")
    ElseIf QuestPrePlaced && QuestSubType == "find_item" && QuestItemChest != None
        QuestTargetAlias.ForceRefTo(QuestItemChest)
        Core.DebugMsg("Story [quest]: marker on chest (pre-placed deep inside)")
    ElseIf QuestPrePlaced && QuestSubType == "combat" && QuestBossNPC != None
        QuestTargetAlias.ForceRefTo(QuestBossNPC)
        Core.DebugMsg("Story [quest]: marker on boss (pre-placed deep inside)")
    Else
        QuestTargetAlias.ForceRefTo(QuestLocation)
    EndIf
    ; Wait for engine to process the alias fill before displaying objective
    Utility.Wait(0.5)
    ObjectReference aliasRef = QuestTargetAlias.GetReference()
    Core.DebugMsg("Story [quest]: After ForceRefTo - aliasRef=" + aliasRef)
    ; Activate quest in tracker so compass/map markers appear
    SetActive(true)
    ; Direct call for immediate display (synchronous)
    SetObjectiveDisplayed(QUEST_OBJECTIVE_ID, true)
    ; Stage for quest state tracking (fragment also calls SetObjectiveDisplayed as backup)
    SetStage(100)
    Core.DebugMsg("Story [quest]: Marker placed for " + QuestLocationName + ", questActive=" + IsActive() + ", objDisplayed=" + IsObjectiveDisplayed(QUEST_OBJECTIVE_ID))
EndFunction

Function RemoveQuestMarker(Bool completed = false)
    If QuestTargetAlias == None
        return
    EndIf
    If completed
        SetObjectiveCompleted(QUEST_OBJECTIVE_ID)
        Core.DebugMsg("Story [quest]: Objective completed, quest deactivated")
    Else
        SetObjectiveDisplayed(QUEST_OBJECTIVE_ID, false)
        Core.DebugMsg("Story [quest]: Objective hidden, quest deactivated")
    EndIf
    SetActive(false)
    QuestTargetAlias.Clear()
EndFunction

; =============================================================================
; CLEANUP
; =============================================================================

Function AbortStoryTravel(String reason)
    {Abort active story travel: clear slot, remove packages, full cleanup.}
    Core.DebugMsg("Story: " + ActiveStoryNPC.GetDisplayName() + " " + reason + " — aborting")
    Int abortSlot = Core.FindSlotByAgent(ActiveStoryNPC)
    If abortSlot >= 0
        Core.ClearSlot(abortSlot)
    EndIf
    Core.RemoveAllPackages(ActiveStoryNPC, false)
    CleanupStoryDispatch()
EndFunction

Function CleanupStoryDispatch()
    ; If quest dispatch is being cleaned up, also reset quest state
    If ActiveStoryType == "quest" || ActiveStoryType == "quest_guide"
        If QuestActive
            ; Notify quest giver that the quest fell through (courier aborted, stuck, etc.)
            If QuestGiver != None && QuestEnemyType != "" && QuestLocationName != ""
                Core.InjectFact(QuestGiver, "never heard back about the " + QuestEnemyType + " threat at " + QuestLocationName + " — the request seems to have fallen through")
            EndIf
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

Function AddNPCSocialLog(String eventType, String npc1Name, String npc2Name, String narration)
    {Store structured NPC social interaction for dashboard display. Parallel StringLists, last 5.}
    Actor player = Game.GetPlayer()
    StorageUtil.StringListAdd(player, "Intel_SocialLog_Type", eventType)
    StorageUtil.StringListAdd(player, "Intel_SocialLog_NPC1", npc1Name)
    StorageUtil.StringListAdd(player, "Intel_SocialLog_NPC2", npc2Name)
    StorageUtil.StringListAdd(player, "Intel_SocialLog_Text", narration)
    While StorageUtil.StringListCount(player, "Intel_SocialLog_Type") > 5
        StorageUtil.StringListRemoveAt(player, "Intel_SocialLog_Type", 0)
        StorageUtil.StringListRemoveAt(player, "Intel_SocialLog_NPC1", 0)
        StorageUtil.StringListRemoveAt(player, "Intel_SocialLog_NPC2", 0)
        StorageUtil.StringListRemoveAt(player, "Intel_SocialLog_Text", 0)
    EndWhile
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
