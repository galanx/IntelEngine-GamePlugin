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
Bool Property TypeFactionAmbushEnabled = true Auto Hidden
Bool Property TypeNPCInteractionEnabled = true Auto Hidden
Bool Property TypeNPCGossipEnabled = true Auto Hidden

; === Per-type hold restriction (MCM) ===
; 0 = no restriction, 1 = same hold civilians only (default), 2 = same hold except followers, 3 = same hold everyone
Int Property HoldPolicySeekPlayer = 1 Auto Hidden      ; Same hold (civilians) — warriors can cross for strong reasons
Int Property HoldPolicyInformant = 6 Auto Hidden        ; Same town (everyone) — gossip is local, nobody travels far for rumors
Int Property HoldPolicyRoadEncounter = 0 Auto Hidden    ; No restriction — road encounters are coincidental
Int Property HoldPolicyAmbush = 1 Auto Hidden           ; Same hold (civilians) — combat NPCs can travel, civilians can't ambush
Int Property HoldPolicyStalker = 1 Auto Hidden          ; Same hold (civilians) — stalkers need proximity
Int Property HoldPolicyMessage = 2 Auto Hidden          ; Same hold (except followers) — messages go via local messengers
Int Property HoldPolicyQuest = 0 Auto Hidden            ; No restriction — quests can come from anywhere

; === Per-Action Confirmation Prompts ===
; 0=disabled, 1=active followers only (default), 2=everyone
Int Property ConfirmGoToLocation = 1 Auto Hidden
Int Property ConfirmDeliverMessage = 1 Auto Hidden
Int Property ConfirmFetchPerson = 1 Auto Hidden
Int Property ConfirmEscortTarget = 1 Auto Hidden
Int Property ConfirmSearchForActor = 1 Auto Hidden
Int Property ConfirmScheduleFetch = 1 Auto Hidden
Int Property ConfirmScheduleDelivery = 1 Auto Hidden
Int Property ConfirmScheduleMeeting = 2 Auto Hidden

; === Per-Action Follower Skip ===
; When true, silently blocks the action for followers (checked before confirmation prompt)
Bool Property SkipFollowerGoToLocation = false Auto Hidden
Bool Property SkipFollowerDeliverMessage = false Auto Hidden
Bool Property SkipFollowerFetchPerson = false Auto Hidden
Bool Property SkipFollowerEscortTarget = false Auto Hidden
Bool Property SkipFollowerSearchForActor = false Auto Hidden
Bool Property SkipFollowerScheduleFetch = false Auto Hidden
Bool Property SkipFollowerScheduleDelivery = false Auto Hidden
Bool Property SkipFollowerScheduleMeeting = false Auto Hidden

; === Auto Dynamic Bio Updates ===
; Updates NPC dynamic bios after X dialogue lines (per-NPC tracking, reset after each update)
Bool Property AutoBioEnabled = false Auto Hidden
Int Property AutoBioThreshold = 20 Auto Hidden

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
String Property QuestBriefing = "" Auto Hidden             ; DM's msgContent — persists for save/load decorator re-push
Bool Property QuestVictimFreed = false Auto Hidden         ; Has victim been unrestrained
Bool Property QuestDeferredToInterior = false Auto Hidden    ; Dungeon entrance found — defer spawning until player enters
Actor Property QuestBossNPC = None Auto Hidden             ; Boss enemy near treasure (find_item)
ObjectReference Property QuestBattleMarker = None Auto Hidden ; Exterior XMarker for faction_battle (cleanup needed)
Bool Property QuestPrePlaced = false Auto Hidden            ; Victim/chest pre-placed at boss room via DungeonIndex
ObjectReference Property QuestBossAnchor = None Auto Hidden ; Boss room anchor from DungeonIndex
Bool Property QuestFurnitureScanned = false Auto Hidden     ; Prisoner furniture scan completed
Bool Property QuestVictimInFurniture = false Auto Hidden    ; Victim is using actual furniture (shackles/stocks) — not bleedout
Cell Property QuestDungeonLastCell = None Auto Hidden       ; Last tracked cell inside dungeon (depth tracking)
Int Property QuestDungeonDepth = 0 Auto Hidden              ; Door transitions inside dungeon (0 = entrance)
Int Property QuestDungeonScanFails = 0 Auto Hidden          ; Failed scan-ahead attempts (fallback after 5)

; === Faction Ambush State ===
Actor[] Property FactionAmbushActors Auto Hidden
Int Property FactionAmbushCount = 0 Auto Hidden
Bool Property FactionAmbushActive = false Auto Hidden
Float Property FactionAmbushStartTime = 0.0 Auto Hidden
Float Property FACTION_AMBUSH_CLEANUP_TIMEOUT = 120.0 AutoReadOnly
Float Property FACTION_AMBUSH_HARD_TIMEOUT = 360.0 AutoReadOnly    ; force cleanup even if still in combat (prevents permanent lockout)

; === Faction Battle Constants ===
Float Property BATTLE_DELAY_MIN_DAYS = 0.015 AutoReadOnly       ; ~22s at timescale 20
Float Property BATTLE_DELAY_VARIANCE_DAYS = 0.015 AutoReadOnly  ; additional random 0-22s
Float Property BATTLE_BUILDUP_NOTIFY_MIN = 0.01 AutoReadOnly    ; when second notification fires
Float Property BATTLE_BUILDUP_NOTIFY_MAX = 0.03 AutoReadOnly    ; window for second notification
Float Property BATTLE_MIN_START_DELAY = 0.04 AutoReadOnly       ; don't check completion before this
Float Property BATTLE_MARKER_OFFSET_UNITS = 3000.0 AutoReadOnly ; distance past city for exterior marker
Int Property QUEST_STANDING_REWARD = 5 AutoReadOnly
Int Property QUEST_STANDING_PENALTY = -5 AutoReadOnly
Int Property AMBUSH_STANDING_PENALTY = -3 AutoReadOnly

; === Tick Timing ===
Float Property LastStoryTickTime = 0.0 Auto Hidden          ; Game-time (days) of last Story DM tick
Float Property LastIdlePollTickTime = 0.0 Auto Hidden      ; Game-time (days) of last idle-poll TickScheduler call

; === Quest Sub-Type MCM Toggles (all enabled by default) ===
Bool Property QuestSubTypeCombatEnabled = true Auto Hidden
Bool Property QuestSubTypeRescueEnabled = true Auto Hidden
Bool Property QuestSubTypeFindItemEnabled = true Auto Hidden
Bool Property QuestSubTypeFactionCombatEnabled = true Auto Hidden
Bool Property QuestSubTypeFactionRescueEnabled = true Auto Hidden
Bool Property QuestSubTypeFactionBattleEnabled = true Auto Hidden
Bool Property QuestAllowVictimDeath = false Auto Hidden
String Property QuestAlliedFaction = "" Auto Hidden
String Property QuestBattleEnemyFaction = "" Auto Hidden  ; faction_battle: validated enemy from DM
Bool Property QuestBattleScheduled = false Auto Hidden  ; faction_battle: waiting for battle to end

; CK Property -- quest objective alias (points compass at quest location)
ReferenceAlias Property QuestTargetAlias Auto
Int Property QUEST_OBJECTIVE_ID = 0 AutoReadOnly

; =============================================================================
; TIMER MANAGEMENT
; Two modes: game-time timer for scheduling, real-time timer for monitoring
; =============================================================================

Function StartScheduler()
    ; StoryEngine owns the shared game-time timer for ALL systems (Story, NPC, Politics).
    ; Always register the timer even if Story DM is disabled — other systems may be active.
    ; Each system self-gates via its own enabled check.
    ; Clear stale ambush StorageUtil key if ambush isn't active (survives save/load but FactionAmbushActive resets)
    If !FactionAmbushActive
        StorageUtil.UnsetStringValue(Game.GetPlayer(), "Intel_FactionAmbushFaction")
    EndIf
    If IsActive || IsNPCStoryActive || HasLingerNPCs() || QuestActive || FactionAmbushActive
        RegisterForSingleUpdate(MONITOR_INTERVAL)
        Core.DebugMsg("Story: StartScheduler — real-time mode (active=" + IsActive + " npcStory=" + IsNPCStoryActive + " quest=" + QuestActive + ")")
    Else
        ; Game-time timer: fires instantly during Wait/Sleep.
        ; Use the SHORTEST interval across all systems (Story, NPC, Politics)
        ; because all scripts share the same quest and RegisterForSingleUpdateGameTime
        ; is per-quest — only one can be active. Each system self-gates via elapsed time.
        Float storyInterval = 3.0
        If Core != None
            storyInterval = Core.GetStoryEngineInterval()
        EndIf
        Float npcInterval = NPCTickIntervalHours
        Float politicsInterval = IntelEngine.GetPoliticsTickInterval() as Float
        If politicsInterval <= 0.0
            politicsInterval = 6.0
        EndIf

        Float interval = storyInterval
        If npcInterval > 0.0 && npcInterval < interval
            interval = npcInterval
        EndIf
        If politicsInterval > 0.0 && politicsInterval < interval
            interval = politicsInterval
        EndIf

        RegisterForSingleUpdateGameTime(interval)
        ; Real-time backup: ensures tick fires even at low timescales (timescale 2-6).
        RegisterForSingleUpdate(IDLE_POLL_INTERVAL)
        Core.DebugMsg("Story: StartScheduler — game-time mode (interval=" + interval + "h = min of story=" + storyInterval + " npc=" + npcInterval + " politics=" + politicsInterval + ")")
    EndIf
EndFunction

Function StopScheduler()
    UnregisterForUpdate()
    UnregisterForUpdateGameTime()
EndFunction

Function SyncHoldRestrictionPolicies()
    IntelEngine.SetHoldRestrictionPolicy("seek_player", HoldPolicySeekPlayer)
    IntelEngine.SetHoldRestrictionPolicy("informant", HoldPolicyInformant)
    IntelEngine.SetHoldRestrictionPolicy("road_encounter", HoldPolicyRoadEncounter)
    IntelEngine.SetHoldRestrictionPolicy("ambush", HoldPolicyAmbush)
    IntelEngine.SetHoldRestrictionPolicy("stalker", HoldPolicyStalker)
    IntelEngine.SetHoldRestrictionPolicy("message", HoldPolicyMessage)
    IntelEngine.SetHoldRestrictionPolicy("quest", HoldPolicyQuest)
EndFunction

Function RestartMonitoring()
    ; Self-heal Core property if None (old saves where property wasn't in ESP)
    If Core == None
        Quest q = Self as Quest
        Core = q as IntelEngine_Core
        If Core != None
            Debug.Trace("[IntelEngine] StoryEngine: recovered Core property via cast")
        EndIf
    EndIf
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

    ; Repair real-time timers carried over from a prior Skyrim session.
    ClearStaleRealTimeTimers()

    SyncHoldRestrictionPolicies()

    ; Re-push active quest state to C++ (singleton resets on game load)
    If QuestActive && QuestLocationName != ""
        String giverName = ""
        If QuestGiver != None
            giverName = QuestGiver.GetDisplayName()
        EndIf
        IntelEngine.NotifyQuestActive(QuestLocationName, QuestSubType, QuestEnemyType, \
            giverName, QuestBriefing, QuestVictimName, QuestItemName, QuestAlliedFaction)
        Core.DebugMsg("Story: re-pushed quest state to C++ decorator")
    EndIf

    ; Sync auto bio settings to C++ DialogueTracker
    IntelEngine.SetAutoBioEnabled(AutoBioEnabled)
    IntelEngine.SetAutoBioThreshold(AutoBioThreshold)
    WarmBioLineCounts()

    ; Restore orphaned aggression changes from faction couriers (crash/save mid-dispatch)
    If ActiveStoryNPC != None
        Float origAggr = StorageUtil.GetFloatValue(ActiveStoryNPC, "Intel_OrigAggression", -1.0)
        If origAggr >= 0.0
            ActiveStoryNPC.SetActorValue("Aggression", origAggr)
            StorageUtil.UnsetFloatValue(ActiveStoryNPC, "Intel_OrigAggression")
            Core.DebugMsg("Story: restored orphaned aggression on " + ActiveStoryNPC.GetDisplayName())
        EndIf
    EndIf

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
                ; Bleedout victim on save-load: DamageActorValue + EvaluatePackage
                ; re-triggers the bleedout state transition. No SetDontMove — blocks anim.
                QuestVictimNPC.SetNoBleedoutRecovery(true)
                QuestVictimNPC.DamageActorValue("Health", QuestVictimNPC.GetActorValue("Health") + 100.0)
                QuestVictimNPC.EvaluatePackage()
                Core.DebugMsg("Story: re-applied victim bleedout on load for " + QuestVictimNPC.GetDisplayName())
            EndIf
        EndIf
    EndIf

    ; faction_battle recovery: battle schedule is lost on load (Battle.ResetState clears it).
    ; If QuestBattleScheduled persists but the battle system was wiped, fail the quest cleanly.
    If QuestActive && QuestBattleScheduled
        If Core.Battle == None || (!Core.Battle.BattleScheduled && !IntelEngine.IsBattleActive())
            Core.DebugMsg("Story: faction_battle quest — battle schedule lost on load, granting partial credit")
            Debug.Notification("The fighting has ended before you arrived.")
            ; Partial standing for willingness to fight
            If QuestAlliedFaction != ""
                IntelEngine.AdjustPlayerFactionStanding(QuestAlliedFaction, QUEST_STANDING_REWARD / 2)
                String allyName = IntelEngine.GetFactionDisplayName(QuestAlliedFaction)
                If allyName != ""
                    Debug.Notification("The " + allyName + " acknowledge your intent to fight.")
                EndIf
            EndIf
            RemoveQuestMarker()
            CleanupQuest()
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
    Core.DebugMsg("Story: OnUpdateGameTime fired (gameTime=" + Utility.GetCurrentGameTime() + ")")
    ; Register FIRST so the timer chain survives even if processing errors out.
    ; StoryEngine owns the game-time timer for ALL systems (shared quest).
    StartScheduler()

    ; Safety net: clean up lingering NPCs even if real-time timer died
    CheckStoryLingerCleanup()
    ; Check rescued NPC deaths on game-time tick (no need for real-time polling)
    CheckRescuedNPCDeaths()
    ; Re-kick real-time monitoring if linger NPCs still exist
    If HasLingerNPCs()
        RegisterForSingleUpdate(MONITOR_INTERVAL)
    EndIf
    ; Do NOT set LastStoryTickTime here — it's set inside TickScheduler
    ; only when the Story DM actually runs. Setting it here would reset the
    ; elapsed-time check to 0 on every shared-timer fire (e.g., every 1.5h for NPC ticks).
    TickScheduler()
EndEvent

; Real-time timer -- fires for arrival monitoring + linger proximity + quest monitoring
Event OnUpdate()
    ; Register FIRST so the loop survives even if processing errors out.
    ; (Same pattern as Travel.OnUpdate — timer chain must never break.)
    Bool needsRealTime = IsActive || IsNPCStoryActive || HasLingerNPCs() || QuestActive || FactionAmbushActive
    If needsRealTime
        RegisterForSingleUpdate(MONITOR_INTERVAL)
    EndIf

    CheckRoadEncounterProximity()
    CheckStoryLingerCleanup()
    CheckFactionAmbushCleanup()


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
    If !needsRealTime && (IsActive || IsNPCStoryActive || HasLingerNPCs() || QuestActive || FactionAmbushActive)
        RegisterForSingleUpdate(MONITOR_INTERVAL)
    ElseIf !needsRealTime
        StartScheduler()
    EndIf

    ; Idle-poll: trigger TickScheduler based on game-time elapsed.
    ; Runs in BOTH real-time and idle modes — background events (ambush, quest, linger)
    ; must NOT block story/politics/NPC ticks from firing.
    Float now = Utility.GetCurrentGameTime()
    Float storyInterval = 3.0
    If Core != None
        storyInterval = Core.GetStoryEngineInterval()
    EndIf
    Float npcInterval = NPCTickIntervalHours
    Float politicsInterval = IntelEngine.GetPoliticsTickInterval() as Float
    If politicsInterval <= 0.0
        politicsInterval = 6.0
    EndIf
    Float minInterval = storyInterval
    If npcInterval > 0.0 && npcInterval < minInterval
        minInterval = npcInterval
    EndIf
    If politicsInterval > 0.0 && politicsInterval < minInterval
        minInterval = politicsInterval
    EndIf
    Float intervalDays = minInterval / 24.0
    Float sinceLastTick = now - LastIdlePollTickTime
    If sinceLastTick >= intervalDays
        Core.DebugMsg("Story: OnUpdate idle-poll — triggering TickScheduler (elapsed=" + (sinceLastTick * 24.0) + "h, threshold=" + minInterval + "h)")
        LastIdlePollTickTime = now
        TickScheduler()
    EndIf

    ; Belt-and-suspenders: if nothing needs real-time AND this OnUpdate was the last one
    ; (needsRealTime was true at the top but everything got cleaned up during processing),
    ; ensure game-time scheduling is alive.
    If needsRealTime && !IsActive && !IsNPCStoryActive && !HasLingerNPCs() && !QuestActive && !FactionAmbushActive
        Core.DebugMsg("Story: OnUpdate — transitioning real-time to game-time (all flags cleared). Calling StartScheduler.")
        StartScheduler()
        Core.DebugMsg("Story: OnUpdate — StartScheduler returned after transition")
    EndIf
EndEvent

; =============================================================================
; CORE SCHEDULER LOOP (V2 -- Dungeon Master)
; =============================================================================

Function TickScheduler()
    If Core == None
        Debug.Trace("[IntelEngine] TickScheduler: Core is None — aborting")
        return
    EndIf
    Core.DebugMsg("Story: TickScheduler — running (IsActive=" + IsActive + ", storyEnabled=" + Core.IsStoryEngineEnabled() + ")")

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

    SyncHoldRestrictionPolicies()

    ; NPC-to-NPC tick (self-gates via own interval)
    TickNPCInteractions()

    ; Politics tick (self-gates via own interval). Politics used to rely on
    ; OnUpdateGameTime, but StartScheduler re-registering RegisterForSingleUpdateGameTime
    ; on every idle-poll meant the game-time timer kept getting reset and never fired.
    ; Driving Politics from the shared TickScheduler matches how Story DM and NPC DM
    ; already work and makes politics ticks fire reliably during real-time play.
    If Core != None && Core.Politics != None
        Core.Politics.TickNow()
    EndIf

    ; Safety net: return stranded fake encounter NPCs
    CleanupStrandedEncounters()

    ; Monitor rescued NPCs for death (game-time is sufficient — no urgency)
    CheckRescuedNPCDeaths()

    ; --- Self-gate: Story DM only fires when its own interval has elapsed ---
    ; The shared game-time timer fires at the shortest interval (may be politics or NPC DM).
    Float storyInterval = 3.0
    If Core != None
        storyInterval = Core.GetStoryEngineInterval()
    EndIf
    Float storyElapsed = (Utility.GetCurrentGameTime() - LastStoryTickTime) * 24.0  ; days to hours
    If storyElapsed < storyInterval
        return
    EndIf

    ; Story interval reached — update timestamp BEFORE processing (prevents re-entry)
    LastStoryTickTime = Utility.GetCurrentGameTime()
    Core.DebugMsg("Story: TickScheduler — story interval reached (" + storyElapsed + "h >= " + storyInterval + "h)")

    ; --- Player-centric Story DM tick (only if enabled) ---
    If !Core.IsStoryEngineEnabled()
        Core.DebugMsg("Story: TickScheduler — story engine disabled, skipping DM call")
        return
    EndIf

    If IsActive
        ; C++ watchdog: 6h timeout (stories legitimately run for hours, but not this long).
        ; Also catches stale flags from save reloads (DLL loads fresh, has no record).
        If IntelEngine.ShouldResetPending("storyDM", 6.0, Utility.GetCurrentGameTime())
            Core.DebugMsg("Story: watchdog reset IsActive (stuck or stale)")
            CleanupStoryDispatch()
            ; Don't fall through to dispatch a new story in the same tick —
            ; let the next scheduled tick handle it after the system settles.
            return
        EndIf
    EndIf

    If !IsActive
        Actor player = Game.GetPlayer()
        If !player.IsInCombat()
            ; Populate recent gossip for DM context (read from StorageUtil, pass to C++)
            Int gossipCount = StorageUtil.StringListCount(player, "Intel_SocialLog_Type")
            If gossipCount > 0
                String gossipLines = ""
                Int gi = gossipCount - 1
                Int gossipShown = 0
                While gi >= 0 && gossipShown < 5
                    String gNpc1 = StorageUtil.StringListGet(player, "Intel_SocialLog_NPC1", gi)
                    String gNpc2 = StorageUtil.StringListGet(player, "Intel_SocialLog_NPC2", gi)
                    String gText = StorageUtil.StringListGet(player, "Intel_SocialLog_Text", gi)
                    String gLoc = StorageUtil.StringListGet(player, "Intel_SocialLog_Location", gi)
                    If gLoc != ""
                        gossipLines += "- [" + gLoc + "] " + gNpc1 + " told " + gNpc2 + ": " + gText + "\n"
                    Else
                        gossipLines += "- " + gNpc1 + " told " + gNpc2 + ": " + gText + "\n"
                    EndIf
                    gossipShown += 1
                    gi -= 1
                EndWhile
                IntelEngine.SetRecentGossipContext(gossipLines)
            Else
                IntelEngine.SetRecentGossipContext("")
            EndIf

            ; Async path: snapshot on main thread (fast), then build context+JSON on
            ; worker thread. OnStoryDMContextReady fires the LLM call on completion.
            ; Eliminates ~30-60ms main-thread stutter from synchronous SQL + actor scans.
            PendingStoryType = "dm_analysis"
            String excludeList = BuildExcludeList(player)
            IntelEngine.BeginAsyncStoryDMTick(7, LongAbsenceDaysConfig, excludeList, \
                Self, "IntelEngine_StoryEngine", "OnStoryDMContextReady")
        EndIf
    EndIf
EndFunction

Function OnStoryDMContextReady(String contextJson)
    If contextJson == ""
        ClearPending()
        return
    EndIf
    SendStoryLLMRequest("intel_story_dm", "OnDungeonMasterResponse", contextJson)
EndFunction

Bool Function IsNPCToNPCType()
    {Returns true if current active story type targets another NPC (not the player).}
    return (ActiveStoryType == "npc_interaction" || ActiveStoryType == "npc_gossip")
EndFunction

String Function BuildExcludeList(Actor player)
    ; Pack MCM toggles into bitmask for C++ (avoids stale bytecode + substring bug)
    ; Bit order: 0=seekPlayer, 1=informant, 2=roadEncounter, 3=ambush, 4=stalker,
    ; 5=message, 6=quest, 7=factionAmbush, 8=questCombat, 9=questRescue,
    ; 10=questFindItem, 11=questFactionCombat, 12=questFactionRescue, 13=questFactionBattle
    Int toggles = 0
    If TypeSeekPlayerEnabled
        toggles += 1     ; bit 0
    EndIf
    If TypeInformantEnabled
        toggles += 2     ; bit 1
    EndIf
    If TypeRoadEncounterEnabled
        toggles += 4     ; bit 2
    EndIf
    If TypeAmbushEnabled
        toggles += 8     ; bit 3
    EndIf
    If TypeStalkerEnabled
        toggles += 16    ; bit 4
    EndIf
    If TypeMessageEnabled
        toggles += 32    ; bit 5
    EndIf
    If TypeQuestEnabled
        toggles += 64    ; bit 6
    EndIf
    If TypeFactionAmbushEnabled
        toggles += 128   ; bit 7
    EndIf
    If QuestSubTypeCombatEnabled
        toggles += 256   ; bit 8
    EndIf
    If QuestSubTypeRescueEnabled
        toggles += 512   ; bit 9
    EndIf
    If QuestSubTypeFindItemEnabled
        toggles += 1024  ; bit 10
    EndIf
    If QuestSubTypeFactionCombatEnabled
        toggles += 2048  ; bit 11
    EndIf
    If QuestSubTypeFactionRescueEnabled
        toggles += 4096  ; bit 12
    EndIf
    If QuestSubTypeFactionBattleEnabled
        toggles += 8192  ; bit 13
    EndIf

    ; Environment flags
    Int envFlags = 0
    Cell pCell = player.GetParentCell()
    If pCell != None && pCell.IsInterior()
        envFlags += 1    ; bit 0 = isInterior
    EndIf
    If IntelEngine.IsPlayerInDangerousLocation()
        envFlags += 2    ; bit 1 = isDangerous
    EndIf

    ; C++ builds the exclude string (exact match dedup, no substring bugs)
    String result = IntelEngine.BuildExcludeList(toggles, envFlags)
    Core.DebugMsg("BuildExcludeList: [" + result + "] (ambush=" + TypeAmbushEnabled + " message=" + TypeMessageEnabled + " quest=" + TypeQuestEnabled + ")")
    return result
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
    Float currentTime = Utility.GetCurrentGameTime()

    If NPCTickPending
        If IntelEngine.ShouldResetPending("npcInteraction", 1.0, currentTime)
            Core.DebugMsg("NPC DM: watchdog reset NPCTickPending (stuck or stale)")
            NPCTickPending = false
        Else
            return
        EndIf
    EndIf

    Float intervalDays = NPCTickIntervalHours / 24.0
    If LastNPCTickTime > 0.0 && (currentTime - LastNPCTickTime) < intervalDays
        return
    EndIf

    LastNPCTickTime = currentTime
    NPCTickPending = true
    IntelEngine.MarkSystemPending("npcInteraction", currentTime)

    ; Async path: snapshot on main thread (fast), build context+JSON on worker thread,
    ; OnNPCDMContextReady fires the LLM call once the prepared JSON is ready.
    ; Eliminates ~20-50ms main-thread stutter from synchronous SQL + actor scans.
    IntelEngine.BeginAsyncNPCDMTick(4, Self, "IntelEngine_StoryEngine", "OnNPCDMContextReady")
EndFunction

Function OnNPCDMContextReady(String contextJson)
    If contextJson == ""
        NPCTickPending = false
        IntelEngine.ClearSystemPending("npcInteraction")
        return
    EndIf
    ; Inline the LLM request so we can clear NPCTickPending on failure.
    ; SendStoryLLMRequest only clears PendingStoryType (storyDM watchdog), not the
    ; npcInteraction watchdog — we'd otherwise leak pending state for ~1h on failure.
    Int result = SkyrimNetApi.SendCustomPromptToLLM("intel_story_npc_dm", "intel_story_dm", contextJson, \
        Self, "IntelEngine_StoryEngine", "OnNPCInteractionResponse")
    If result < 0
        Debug.Trace("[IntelEngine] StoryEngine: NPC DM LLM call failed code " + result)
        NPCTickPending = false
        IntelEngine.ClearSystemPending("npcInteraction")
    EndIf
EndFunction

Function OnNPCInteractionResponse(String response, Int success)
    NPCTickPending = false
    IntelEngine.ClearSystemPending("npcInteraction")

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

    ; Inject facts and build detail string for dashboard log
    String dashboardText = narration
    String logDetail = ""
    If storyType == "npc_interaction"
        String fact1 = ExtractJsonField(response, "fact1")
        String fact2 = ExtractJsonField(response, "fact2")
        If fact1 != ""
            Core.InjectFact(npc1, fact1)
        EndIf
        If fact2 != ""
            Core.InjectFact(npc2, fact2)
        EndIf
        If fact1 != ""
            logDetail = npc1.GetDisplayName() + ": " + fact1
        EndIf
        If fact2 != ""
            If logDetail != ""
                logDetail += " | "
            EndIf
            logDetail += npc2.GetDisplayName() + ": " + fact2
        EndIf
    ElseIf storyType == "npc_gossip"
        String gossipContent = ExtractJsonField(response, "gossip")
        If gossipContent != ""
            Core.InjectGossip(npc1, npc2, gossipContent)
            logDetail = "Gossip: " + gossipContent
            dashboardText = gossipContent
        EndIf
        SpreadGossipOffScreen(npc1, npc2, gossipContent)
    EndIf
    AddNPCSocialLog(storyType, npc1.GetDisplayName(), npc2.GetDisplayName(), dashboardText, npc1, logDetail)

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
        ; No free slots -- fall back to off-screen (log already added before visibility branch)
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

Function ClearStaleRealTimeTimers()
    {Reset real-time timer stamps whose saved values exceed current real time.
     Utility.GetCurrentRealTime() resets each Skyrim launch, but StorageUtil
     floats and save-persistent properties don't — so a saved value from a
     prior session is always larger than `now` and makes `now - saved` negative,
     which means `elapsed > TIMEOUT_SECONDS` watchdogs never fire and NPCs get
     stuck in linger/greet/sneak/combat states. Snap stale stamps forward to
     `now` so the countdown restarts from load.}
    Float now = Utility.GetCurrentRealTime()
    Actor player = Game.GetPlayer()

    If FactionAmbushStartTime > now
        FactionAmbushStartTime = now
    EndIf

    ; Per-NPC linger timers
    Int lingerCount = StorageUtil.FormListCount(player, "Intel_StoryLingerActors")
    Int i = lingerCount - 1
    While i >= 0
        Actor npc = StorageUtil.FormListGet(player, "Intel_StoryLingerActors", i) as Actor
        If npc != None
            Float t = StorageUtil.GetFloatValue(npc, "Intel_StoryLingerStart", 0.0)
            If t > now
                StorageUtil.SetFloatValue(npc, "Intel_StoryLingerStart", now)
            EndIf
        EndIf
        i -= 1
    EndWhile

    ; Per-NPC road-encounter greet timers
    Int encCount = StorageUtil.IntListCount(player, "Intel_FakeEncounterNPCs")
    i = encCount - 1
    While i >= 0
        Int formId = StorageUtil.IntListGet(player, "Intel_FakeEncounterNPCs", i)
        Actor npc = Game.GetForm(formId) as Actor
        If npc != None
            Float t = StorageUtil.GetFloatValue(npc, "Intel_FakeEncounterGreetTime", 0.0)
            If t > now
                StorageUtil.SetFloatValue(npc, "Intel_FakeEncounterGreetTime", now)
            EndIf
        EndIf
        i -= 1
    EndWhile

    ; Active story NPC sneak/combat timers
    If ActiveStoryNPC != None
        Float sneakStart = StorageUtil.GetFloatValue(ActiveStoryNPC, "Intel_SneakStartTime", 0.0)
        If sneakStart > now
            StorageUtil.SetFloatValue(ActiveStoryNPC, "Intel_SneakStartTime", now)
        EndIf
        Float combatStart = StorageUtil.GetFloatValue(ActiveStoryNPC, "Intel_CombatStartTime", 0.0)
        If combatStart > now
            StorageUtil.SetFloatValue(ActiveStoryNPC, "Intel_CombatStartTime", now)
        EndIf
    EndIf
EndFunction

Function WarmBioLineCounts()
    {Restore per-NPC dialogue line counts from StorageUtil into C++ DialogueTracker.}
    Int count = StorageUtil.FormListCount(self, "Intel_BioTrackActors")
    Int warmed = 0
    Int i = count - 1
    While i >= 0
        Actor npc = StorageUtil.FormListGet(self, "Intel_BioTrackActors", i) as Actor
        If npc != None
            Int lines = StorageUtil.GetIntValue(npc, "Intel_BioLineCount", 0)
            If lines > 0
                IntelEngine.SetAutoBioCount(npc, lines)
                warmed += 1
            EndIf
        Else
            StorageUtil.FormListRemoveAt(self, "Intel_BioTrackActors", i)
        EndIf
        i -= 1
    EndWhile
    If warmed > 0
        Core.DebugMsg("Story: warmed bio line counts (" + warmed + " NPCs)")
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
    Passes the full string list to C++ for parsing (no string ops in Papyrus).}
    Actor player = Game.GetPlayer()
    Int count = StorageUtil.StringListCount(player, "Intel_RecentStoryEvents")
    If count == 0
        return
    EndIf
    ; Build comma-separated list for C++ to parse
    String csv = ""
    Int i = 0
    While i < count
        If i > 0
            csv += "|"
        EndIf
        csv += StorageUtil.StringListGet(player, "Intel_RecentStoryEvents", i)
        i += 1
    EndWhile
    IntelEngine.WarmStoryTypeCountsFromCSV(csv)
    Core.DebugMsg("Story: warmed type counts from " + count + " recent events (C++)")
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

    If storyType == ""
        Debug.Trace("[IntelEngine] StoryEngine: DM response missing type -- response len=" + responseLen)
        return
    EndIf

    ; Faction ambush doesn't use a candidate NPC — handle separately before NPC validation
    If storyType == "faction_ambush"
        IntelEngine.NotifyStoryTypePicked(storyType)
        IntelEngine.RecordStoryDispatch(storyType, ExtractJsonField(response, "ambushFaction"), narration)
        HandleFactionAmbushDispatch(narration, response)
        return
    EndIf

    ; Faction quests (faction_combat, faction_rescue, faction_battle) always use FindFactionMember —
    ; the DM has no faction context for candidates, so C++ handles NPC selection.
    ; Check subtype REGARDLESS of whether the LLM filled npc (it shouldn't, but may ignore the prompt).
    Bool isFactionQuest = false
    If storyType == "quest"
        String preSubTypeEarly = ExtractJsonField(response, "questSubType")
        If preSubTypeEarly == "faction_combat" || preSubTypeEarly == "faction_rescue" || preSubTypeEarly == "faction_battle"
            isFactionQuest = true
            If npcName != ""
                Core.DebugMsg("Story DM: faction quest " + preSubTypeEarly + " sent npc='" + npcName + "' -- ignoring (system handles NPC selection)")
                npcName = ""
            EndIf
        ElseIf npcName == ""
            Debug.Trace("[IntelEngine] StoryEngine: DM response missing npc -- response len=" + responseLen)
            return
        EndIf
    ElseIf npcName == ""
        Debug.Trace("[IntelEngine] StoryEngine: DM response missing npc -- response len=" + responseLen)
        return
    EndIf

    ; Track quest subtypes separately so "quest/rescue" doesn't block "quest/faction_battle".
    ; Build typeWithSub once and reuse it for BOTH NotifyStoryTypePicked (counts) and
    ; RecordStoryDispatch (history) — single source of truth for sub-type derivation.
    String typeWithSub = storyType
    If storyType == "quest"
        String subTypeForTracking = ExtractJsonField(response, "questSubType")
        If subTypeForTracking != ""
            typeWithSub = "quest/" + subTypeForTracking
        EndIf
    EndIf
    IntelEngine.NotifyStoryTypePicked(typeWithSub)

    ; Record full dispatch detail for the rolling history block in the next DM tick prompt.
    ; Lets the DM verify "vary type/dispatcher" and "don't strike at the same beloved NPC twice".
    IntelEngine.RecordStoryDispatch(typeWithSub, npcName, narration)

    ; Resolve primary NPC from candidate pool (exact FormID, no name ambiguity)
    ; For faction quests with empty npc, FindFactionMember provides the NPC in HandleQuestDispatch
    Actor npc = None
    If !isFactionQuest
        npc = IntelEngine.ResolveStoryCandidate(npcName)
        If npc == None || npc.IsDead() || npc.IsDisabled()
            ; Vanilla "Courier" / "Messenger" refs are kept .Disable()'d between
            ; CourierQuest deliveries, so they exist in the index but IsDisabled
            ; rejects them. Substitute with a real actor who can physically walk:
            ;   - alliedFaction → FindFactionMember (faction guard/soldier)
            ;   - sender → FindMessengerForSender (household/associate/guard/civilian
            ;     near the sender, same cascade real messages use)
            String lowerNpcName = IntelEngine.StringToLower(npcName)
            If lowerNpcName == "courier" || lowerNpcName == "messenger"
                ; Clear the disabled/dead Courier so the fallback paths overwrite it.
                npc = None
                String substFaction = ExtractJsonField(response, "alliedFaction")
                If substFaction != ""
                    npc = IntelEngine.FindFactionMember(substFaction)
                    If npc != None
                        Core.DebugMsg("Story DM: substituting disabled '" + npcName + "' with " + substFaction + " member " + npc.GetDisplayName())
                    EndIf
                EndIf
                If npc == None
                    String substSender = ExtractJsonField(response, "sender")
                    If substSender != ""
                        Actor senderActor = IntelEngine.FindNPCByName(substSender)
                        If senderActor != None && !senderActor.IsDead() && !senderActor.IsDisabled()
                            npc = IntelEngine.FindMessengerForSender(senderActor)
                            If npc != None
                                Core.DebugMsg("Story DM: substituting disabled '" + npcName + "' with " + npc.GetDisplayName() + " (messenger near " + substSender + ")")
                            EndIf
                        EndIf
                    EndIf
                EndIf
            EndIf
            If npc == None || npc.IsDead() || npc.IsDisabled()
                Core.DebugMsg("Story DM: NPC '" + npcName + "' not found or invalid")
                IntelEngine.MarkLastDispatchFailed("npc not found / dead / disabled")
                return
            EndIf
        EndIf
    EndIf
    ; Cooldown and NPC-specific checks only apply when we have a resolved NPC
    If npc != None
        ; High-status NPCs (Jarls, essential leaders) should never physically travel.
        ; Only block types where the NPC walks to the player:
        ;   - "message" is exempt: NPC is the SENDER, a courier physically travels
        ;   - "quest" is exempt: courier/sender logic in HandleQuestDispatch handles this
        ; Block: seek_player, informant, road_encounter, ambush, stalker
        If IntelEngine.IsHighStatusNPC(npc) && storyType != "message" && storyType != "quest"
            Core.DebugMsg("Story DM: " + npc.GetDisplayName() + " is high-status — rejected (should use courier mode)")
            IntelEngine.MarkLastDispatchFailed("high-status NPC cannot physically travel")
            return
        EndIf
        ; Hold restriction enforcement — the LLM may ignore the Eligible line.
        ; Server-side reject if the NPC doesn't pass hold restriction for this type.
        If !IntelEngine.CheckHoldRestriction(npc, storyType)
            Core.DebugMsg("Story DM: " + npc.GetDisplayName() + " rejected — hold restriction for " + storyType)
            IntelEngine.MarkLastDispatchFailed("hold restriction")
            return
        EndIf
        If !ApplyCooldownCheck(npc)
            Core.DebugMsg("Story DM: " + npc.GetDisplayName() + " on cooldown")
            IntelEngine.MarkLastDispatchFailed("npc on story cooldown")
            return
        EndIf

        ; Re-validate: reject player-targeted types if NPC ended up in the player's cell
        ; (pool was built seconds ago — player may have moved cells during LLM round-trip)
        If storyType == "seek_player" || storyType == "informant"
            Cell npcCell = npc.GetParentCell()
            Cell playerCell = Game.GetPlayer().GetParentCell()
            If npcCell != None && playerCell != None && npcCell == playerCell
                Core.DebugMsg("Story DM: " + npc.GetDisplayName() + " already in player's cell, skipping " + storyType)
                IntelEngine.MarkLastDispatchFailed("npc already in player's cell")
                return
            EndIf
        EndIf

        ; Stalker/ambush require outdoor space — interiors are too small for sneak gameplay
        If storyType == "stalker" || storyType == "ambush"
            Cell playerCell2 = Game.GetPlayer().GetParentCell()
            If playerCell2 != None && playerCell2.IsInterior()
                Core.DebugMsg("Story DM: rejecting " + storyType + " -- player is in interior")
                IntelEngine.MarkLastDispatchFailed("interior cell rejects stalker/ambush")
                return
            EndIf
        EndIf
    EndIf

    If isFactionQuest
        Core.DebugMsg("Story DM [quest/faction]: " + ExtractJsonField(response, "questSubType") + " -- " + narration)
    Else
        Core.DebugMsg("Story DM [" + storyType + "]: " + npc.GetDisplayName() + " -- " + narration)
    EndIf

    ; C++ validates: MCM toggles, known subtypes, field presence (stale-bytecode-safe)
    ; Uses the same bitmask approach as BuildExcludeList for toggle packing.
    Int toggles = PackToggleBitmask()
    Int envFlags = PackEnvFlags(Game.GetPlayer())
    String validateJson = IntelEngine.ValidateStoryResponse(response, toggles, envFlags)
    If IntelEngine.StoryResponseGetField(validateJson, "valid") != "true"
        String validationReason = IntelEngine.StoryResponseGetField(validateJson, "reason")
        Core.DebugMsg("Story DM: C++ validation rejected -- " + validationReason)
        IntelEngine.MarkLastDispatchFailed("validation: " + validationReason)
        return
    EndIf

    ; Papyrus-only checks: Jarl (requires Actor), quest active state
    If npc != None && IntelEngine.IsJarl(npc) && storyType != "message" && storyType != "quest"
        Core.DebugMsg("Story DM: rejecting " + storyType + " for Jarl " + npc.GetDisplayName())
        IntelEngine.MarkLastDispatchFailed("Jarl cannot physically travel")
        return
    EndIf

    ; Quest-specific Papyrus-only check: only one quest at a time
    If storyType == "quest"
        If QuestActive
            Core.DebugMsg("Story DM: quest rejected -- one already active")
            IntelEngine.MarkLastDispatchFailed("a quest is already active")
            return
        EndIf
        ; Field validation handled by C++ ValidateStoryResponse above
    ElseIf storyType == "message"
        If ExtractJsonField(response, "msgContent") == ""
            Core.DebugMsg("Story DM: message rejected -- missing msgContent")
            IntelEngine.MarkLastDispatchFailed("missing msgContent")
            return
        EndIf
    EndIf

    ; Record dispatch as a persistent event (generic text, NOT the full narration).
    ; The actual narration fires only once on arrival via OnStoryNPCArrived.
    ; Message type sends its own persistent memory inside HandleMessageDispatch (references messenger, not sender).
    ; Faction quests with empty npc skip this — persistent memory is sent after FindFactionMember in HandleQuestDispatch.
    If storyType != "message" && npc != None
        String npcDispName = npc.GetDisplayName()
        String playerDispName = Game.GetPlayer().GetDisplayName()
        If IntelEngine.NPCKnowsPlayer(npc)
            Core.SendPersistentMemory(npc, Game.GetPlayer(), npcDispName + " set out to find " + playerDispName)
        Else
            Core.SendPersistentMemory(npc, Game.GetPlayer(), npcDispName + " set out to find someone known as '" + playerDispName + "' — has never met them before, only heard the name")
            Core.InjectFact(npc, "has never met " + playerDispName + " personally — approaching a stranger, should introduce themselves and confirm identity")
        EndIf
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
    IntelEngine.MarkSystemPending("storyDM", Utility.GetCurrentGameTime())
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

    ; Fast-path proximity arrival. The C++ monitor ticks every 150ms and
    ; fires OnProximityArrived the instant the NPC enters range of the
    ; story target (player or second NPC). Eliminates the face-bumping
    ; that the 3s MONITOR_INTERVAL otherwise creates.
    IntelEngine.ArmProximityArrival(slot, npc as ObjectReference, target as ObjectReference, Self, "IntelEngine_StoryEngine", "OnProximityArrived")

    RegisterForSingleUpdate(MONITOR_INTERVAL)
EndFunction

; Callback invoked by the C++ ProximityMonitor when a dispatched story NPC
; enters arrival range of its target. Routes through CheckStoryNPCArrival
; so all abort checks (danger zone, blocked location, player-in-combat,
; player-home restrictions) run identically to the 3s poll's path.
Function OnProximityArrived(String slotStr)
    If !IsActive
        Return
    EndIf
    ; ActiveStoryNPC gates the arrival handler; don't attempt if cleaned up.
    If ActiveStoryNPC == None
        Return
    EndIf
    CheckStoryNPCArrival()
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
    ; NOTE: AddNPCSocialLog is called BEFORE the visibility branch in OnNPCInteractionResponse
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
            ; Approach phase — swap TravelPackage_Walk for SandboxNearPlayerPackage
            ; once close. Matches the Travel/Meeting linger pattern (same flag name).
            If StorageUtil.GetIntValue(npc, "Intel_MeetingLingerApproaching") == 1
                Bool closeEnough = false
                If npc.Is3DLoaded() && player.Is3DLoaded()
                    closeEnough = npc.GetDistance(player) <= Core.LINGER_APPROACH_DISTANCE
                ElseIf npc.GetParentCell() == player.GetParentCell()
                    closeEnough = true
                EndIf
                If closeEnough
                    ; Add sandbox BEFORE removing travel — no gap for default AI to kick in
                    ActorUtil.AddPackageOverride(npc, Core.SandboxNearPlayerPackage, Core.PRIORITY_TRAVEL, 1)
                    ActorUtil.RemovePackageOverride(npc, Core.TravelPackage_Walk)
                    Utility.Wait(0.1)
                    npc.EvaluatePackage()
                    StorageUtil.UnsetIntValue(npc, "Intel_MeetingLingerApproaching")
                    Core.DebugMsg("Story [quest/rescue]: " + npc.GetDisplayName() + " reached player, sandboxing")
                EndIf
            EndIf

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

    ; Cancel dispatch if player is at a blocked location or not at a whitelisted location
    If arrivalTarget == player
        If IntelEngine.IsPlayerInBlockedLocation()
            Core.DebugMsg("Story: cancelling " + ActiveStoryType + " for " + ActiveStoryNPC.GetDisplayName() + " -- player at blocked location")
            Core.SendTaskNarration(ActiveStoryNPC, "gave up looking for " + player.GetDisplayName() + " and turned back", player)
            AbortStoryTravel("player at blocked location")
            return
        EndIf
        If !IntelEngine.IsPlayerInWhitelistedLocation()
            Core.DebugMsg("Story: cancelling " + ActiveStoryType + " for " + ActiveStoryNPC.GetDisplayName() + " -- player not at whitelisted location")
            Core.SendTaskNarration(ActiveStoryNPC, "decided not to seek " + player.GetDisplayName() + " at this location", player)
            AbortStoryTravel("player not at whitelisted location")
            return
        EndIf
    EndIf

    ; Abort dispatch if player entered a dangerous location during travel
    ; Shared abort checks (on-screen path)
    If arrivalTarget == player
        If ShouldAbortForDangerZone(ActiveStoryNPC, player, ActiveStoryType, "")
            return
        EndIf
        If ShouldAbortForPlayerHome(ActiveStoryNPC, player, ActiveStoryType, "")
            return
        EndIf
        If ShouldAbortForHoldRestriction(ActiveStoryNPC, player, ActiveStoryType, "")
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
        ; Shared abort checks (off-screen path)
        If arrivalTarget == player
            If ShouldAbortForDangerZone(ActiveStoryNPC, player, ActiveStoryType, " (off-screen)")
                return
            EndIf
            If ShouldAbortForPlayerHome(ActiveStoryNPC, player, ActiveStoryType, " (off-screen)")
                return
            EndIf
            If ShouldAbortForHoldRestriction(ActiveStoryNPC, player, ActiveStoryType, " (off-screen)")
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

    ; Persist the delivered message on both the messenger and the player
    ; so both parties recall it in future conversations
    Core.SendPersistentMemory(ActiveStoryNPC, Game.GetPlayer(), ActiveStoryNPC.GetDisplayName() + " delivered a message from " + senderName + ": " + msgContent)

    ; Safety net: if msgContent conveys urgency but meetTime is set, the LLM
    ; contradicted itself (e.g., "needs you immediately" + meetTime="afternoon").
    ; Drop the meeting — treat as plain message so narration and schedule don't clash.
    If msgDest != "" && meetTime != ""
        If IntelEngine.IsUrgentMessage(msgContent)
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

    ; Stalkers start in sneak immediately (stalk package, phase 1).
    ; Ambush stealth starts in phase 0 (jog normally), enters sneak at 2000 units.
    If storyType == "stalker"
        StorageUtil.SetIntValue(npc, "Intel_SneakPhase", 1)
        ReapplyTravelPackage(npc)
        Core.DebugMsg("Story [stalker]: " + npc.GetDisplayName() + " dispatched with stalk package")
    ElseIf storyType == "ambush"
        StorageUtil.SetIntValue(npc, "Intel_SneakPhase", 0)
        Core.DebugMsg("Story [ambush]: " + npc.GetDisplayName() + " dispatched (jog → sneak at 2000u)")
    EndIf

    ; Track sneak start time for timeout (stealth ambush and stalker only)
    If storyType == "ambush" || storyType == "stalker"
        StorageUtil.SetFloatValue(npc, "Intel_SneakStartTime", Utility.GetCurrentRealTime())
    EndIf
EndFunction

Function HandleFactionAmbushDispatch(String narration, String response)
    {Faction group ambush — spawn 3-7 hostile soldiers from a faction near the player.}
    String factionId = ExtractJsonField(response, "ambushFaction")
    String countStr = ExtractJsonField(response, "ambushCount")

    If factionId == ""
        Core.DebugMsg("Story [faction_ambush]: missing ambushFaction")
        return
    EndIf

    Int count = countStr as Int
    If count < 3
        count = 3
    ElseIf count > 7
        count = 7
    EndIf

    ; Guard: don't overlap with active battle, existing faction ambush, or manifestation
    If IntelEngine.IsBattleActive()
        Core.DebugMsg("Story [faction_ambush]: battle active, skipping")
        return
    EndIf
    If FactionAmbushActive
        Core.DebugMsg("Story [faction_ambush]: previous ambush still active, skipping")
        return
    EndIf
    If Core.Battle != None && Core.Battle.ManifestActive
        Core.DebugMsg("Story [faction_ambush]: manifestation active, skipping")
        return
    EndIf

    Actor player = Game.GetPlayer()

    ; Spawn soldiers — C++ handles leveled list resolution + crime faction removal (no bounty)
    Actor[] soldiers = IntelEngine.SpawnBattleSoldiers(factionId + ":" + count, player)
    If soldiers.Length == 0
        Core.DebugMsg("Story [faction_ambush]: no soldiers spawned for " + factionId)
        return
    EndIf

    ; Crime factions already removed by C++ SpawnBattleSoldiers — no bounty for killing any spawned soldiers

    FactionAmbushActors = new Actor[7]
    FactionAmbushCount = 0
    Float playerAngle = player.GetAngleZ()

    Int i = 0
    While i < soldiers.Length
        If soldiers[i] != None && FactionAmbushCount < 7
            ; Spawn behind player (out of view, close enough to engage quickly)
            Float angle = playerAngle + 180.0 + Utility.RandomFloat(-45.0, 45.0)
            Float dist = Utility.RandomFloat(800.0, 1200.0)
            Float offsetX = Math.Sin(angle) * dist
            Float offsetY = Math.Cos(angle) * dist
            soldiers[i].MoveTo(player, offsetX, offsetY, 0.0)
            soldiers[i].SetActorValue("Confidence", 4)
            soldiers[i].SetActorValue("Aggression", 1)  ; Aggressive (not Very Aggressive — won't attack civilians)
            FactionAmbushActors[FactionAmbushCount] = soldiers[i]
            FactionAmbushCount += 1
        EndIf
        i += 1
    EndWhile

    If FactionAmbushCount == 0
        Core.DebugMsg("Story [faction_ambush]: all soldiers None after spawn")
        return
    EndIf

    String factionName = IntelEngine.GetFactionDisplayName(factionId)

    ; Wait for actors to load, then warn player with faction identification
    Utility.Wait(1.5 + Utility.RandomFloat(0.0, 1.0))
    Debug.Notification("Something feels wrong...")
    Utility.Wait(1.0)
    Int ambushMsg = Utility.RandomInt(0, 2)
    If ambushMsg == 0
        Debug.Notification(factionName + " soldiers emerge from hiding!")
    ElseIf ambushMsg == 1
        Debug.Notification("Ambush! " + factionName + " forces surround you!")
    Else
        Debug.Notification(factionName + " troops close in from behind!")
    EndIf

    ; Stagger combat starts for natural feel
    i = 0
    While i < FactionAmbushCount
        If FactionAmbushActors[i] != None
            FactionAmbushActors[i].StartCombat(player)
            Utility.Wait(Utility.RandomFloat(0.3, 0.6))
        EndIf
        i += 1
    EndWhile

    AddRecentStoryEvent("faction_ambush: " + factionName + " (" + FactionAmbushCount + " soldiers) -- " + narration)

    FactionAmbushActive = true
    FactionAmbushStartTime = Utility.GetCurrentRealTime()
    StorageUtil.SetStringValue(player, "Intel_FactionAmbushFaction", factionId)
    Core.DebugMsg("Story [faction_ambush]: " + FactionAmbushCount + " " + factionName + " soldiers spawned")
EndFunction

Function CheckFactionAmbushCleanup()
    {Monitor faction ambush actors — cleanup when all dead or timeout elapsed.}
    If !FactionAmbushActive
        return
    EndIf

    Float elapsed = Utility.GetCurrentRealTime() - FactionAmbushStartTime
    Bool allDead = true
    Int deadCount = 0
    Int i = 0
    While i < FactionAmbushCount
        If FactionAmbushActors[i] != None
            If FactionAmbushActors[i].IsDead()
                deadCount += 1
            Else
                allDead = false
            EndIf
        EndIf
        i += 1
    EndWhile

    ; Cleanup when all dead, or soft timeout (out of combat), or hard timeout
    Bool timeoutReady = elapsed >= FACTION_AMBUSH_CLEANUP_TIMEOUT && !Game.GetPlayer().IsInCombat()
    Bool hardTimeout = elapsed >= FACTION_AMBUSH_HARD_TIMEOUT
    If allDead || timeoutReady || hardTimeout
        ; Standing: worsens the AMBUSH faction's view of the player (they failed to kill you).
        ; The player defended themselves — no penalty for the player.
        ; If player killed some soldiers, the faction respects/fears them less.
        String ambushFactionId = StorageUtil.GetStringValue(Game.GetPlayer(), "Intel_FactionAmbushFaction")
        If ambushFactionId != ""
            If deadCount > 0
                ; Faction sees player as a threat — their standing with player worsens
                Int factionPenalty = deadCount * -2
                IntelEngine.AdjustPlayerFactionStanding(ambushFactionId, factionPenalty)
                Core.DebugMsg("Story [faction_ambush]: " + ambushFactionId + " standing " + factionPenalty + " (killed " + deadCount + " soldiers)")
            EndIf
            StorageUtil.UnsetStringValue(Game.GetPlayer(), "Intel_FactionAmbushFaction")
        EndIf

        Core.DebugMsg("Story [faction_ambush]: cleanup (" + FactionAmbushCount + " actors, allDead=" + allDead + ", elapsed=" + elapsed as Int + "s)")
        ; Disable+Delete ALL soldiers (dead and living) — prevents leaking hostile actors
        i = 0
        While i < FactionAmbushCount
            If FactionAmbushActors[i] != None
                If !FactionAmbushActors[i].IsDead()
                    ; Reset aggression before disable so they don't attack on re-enable edge cases
                    FactionAmbushActors[i].SetActorValue("Aggression", 0)
                    FactionAmbushActors[i].StopCombat()
                EndIf
                FactionAmbushActors[i].DisableNoWait()
                FactionAmbushActors[i].Delete()
                FactionAmbushActors[i] = None
            EndIf
            i += 1
        EndWhile
        FactionAmbushCount = 0
        FactionAmbushActive = false
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
    String alliedFaction = ExtractJsonField(response, "alliedFaction")
    String suggestedEnemy = ExtractJsonField(response, "enemyFaction")
    If questSubTypeStr == ""
        questSubTypeStr = "combat"
    EndIf

    ; Jarls never travel personally — reject DIRECT mode (sender empty = npc IS the quest giver)
    If npc != None && IntelEngine.IsJarl(npc) && (senderName == "" || senderName == npc.GetDisplayName())
        Core.DebugMsg("Story DM: quest rejected -- Jarl " + npc.GetDisplayName() + " cannot deliver quest personally (needs courier)")
        return
    EndIf

    If questLocationStr == "" || (enemyType == "" && questSubTypeStr != "faction_battle")
        Core.DebugMsg("Story DM: quest missing questLocation or enemyType")
        return
    EndIf

    ; Validate rescue victim (applies to both rescue and faction_rescue)
    Actor victimActor = None
    If (questSubTypeStr == "rescue" || questSubTypeStr == "faction_rescue") && victimName != ""
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
        ; Can't kidnap the player's active teammate — even if bleedout applied, the
        ; follower framework continuously re-asserts combat readiness and overrides
        ; Aggression/Confidence, so the passive enforcement can't take effect.
        If victimActor.IsPlayerTeammate()
            Core.DebugMsg("Story DM: quest/rescue rejected -- victim '" + victimName + "' is the player's teammate")
            return
        EndIf
        ; Hard cooldown — victim was recently used in a quest or story dispatch
        If IntelEngine.IsActorOnStoryCooldown(victimActor)
            Core.DebugMsg("Story DM: quest/rescue rejected -- victim '" + victimName + "' is on story cooldown")
            return
        EndIf
    ElseIf (questSubTypeStr == "rescue" || questSubTypeStr == "faction_rescue") && victimName == ""
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

    ; Faction quests with empty npc: find a loaded faction member first (need actor for ResolveAnyDestination)
    If alliedFaction != "" && npc == None
        Actor factionMember = IntelEngine.FindFactionMember(alliedFaction)
        If factionMember == None
            Core.DebugMsg("Story DM: quest/" + questSubTypeStr + " rejected -- no loaded " + alliedFaction + " member found")
            return
        EndIf
        ; Guard: faction member must not be the rescue victim
        If victimActor != None && factionMember == victimActor
            Core.DebugMsg("Story DM: quest/" + questSubTypeStr + " rejected -- only loaded " + alliedFaction + " member is the rescue victim")
            return
        EndIf
        npc = factionMember
        ; Make courier non-hostile so NPCs don't attack them on approach (e.g., Volkihar vampires)
        ; Save original aggression for restoration after task completes
        StorageUtil.SetFloatValue(npc, "Intel_OrigAggression", npc.GetActorValue("Aggression"))
        npc.SetActorValue("Aggression", 0)
        ; Skip cooldown for faction couriers — they're generic/interchangeable soldiers.
        ; Rejecting a faction_battle because the nearest guard has a cooldown wastes a valid quest.
        String factionName = IntelEngine.GetFactionDisplayName(alliedFaction)
        narration = BuildFactionQuestNarration(factionName, questLocationStr)
        Core.DebugMsg("Story DM: quest/" + questSubTypeStr + " -- faction member " + npc.GetDisplayName() + " selected for " + alliedFaction)
        ; Send persistent memory — stranger couriers don't know the player's name
        String playerName2 = Game.GetPlayer().GetDisplayName()
        If IntelEngine.NPCKnowsPlayer(npc)
            Core.SendPersistentMemory(npc, Game.GetPlayer(), npc.GetDisplayName() + " set out to find " + playerName2 + " with urgent orders from " + factionName)
        Else
            Core.SendPersistentMemory(npc, Game.GetPlayer(), npc.GetDisplayName() + " was sent to find a warrior described as '" + playerName2 + "' — never met them personally, only knows them by reputation and description")
            Core.InjectFact(npc, "has never met " + playerName2 + " before — was given a physical description and told to look for them. Should introduce themselves and confirm identity before delivering the message.")
        EndIf
    EndIf

    ObjectReference questDest = IntelEngine.ResolveAnyDestination(npc, questLocationStr)
    If questDest == None
        Core.DebugMsg("Story DM: quest location '" + questLocationStr + "' could not be resolved")
        return
    EndIf
    If IntelEngine.IsLocationNonCombative(questDest)
        Core.DebugMsg("Story DM: quest location '" + questLocationStr + "' is non-combative (temple/castle/guild) — rejecting")
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

    ; Safety net: verify quest giver belongs to the allied faction.
    ; FindFactionMember always returns correct faction members, but the senderName override above
    ; can replace questGiverActor with a non-faction NPC if the LLM's sender field names someone outside the faction.
    If alliedFaction != "" && questGiverActor != None
        String giverFaction = IntelEngine.GetNPCPoliticalFactionId(questGiverActor)
        If giverFaction != alliedFaction
            Actor factionSub = IntelEngine.FindFactionMember(alliedFaction)
            If factionSub == None
                Core.DebugMsg("Story DM: quest/" + questSubTypeStr + " rejected -- no loaded " + alliedFaction + " member found")
                return
            EndIf
            If victimActor != None && factionSub == victimActor
                Core.DebugMsg("Story DM: quest/" + questSubTypeStr + " rejected -- only loaded " + alliedFaction + " member is the rescue victim")
                return
            EndIf
            If !ApplyCooldownCheck(factionSub)
                Core.DebugMsg("Story DM: quest/" + questSubTypeStr + " rejected -- substitute faction member " + factionSub.GetDisplayName() + " on cooldown")
                return
            EndIf
            Core.DebugMsg("Story DM: quest/" + questSubTypeStr + " -- substituting " + questGiverActor.GetDisplayName() + " with faction member " + factionSub.GetDisplayName())
            questGiverActor = factionSub
            npc = factionSub
            String factionName2 = IntelEngine.GetFactionDisplayName(alliedFaction)
            narration = BuildFactionQuestNarration(factionName2, questLocationStr)
        EndIf
    EndIf

    ; faction_battle: validate battle prerequisites in C++
    If questSubTypeStr == "faction_battle"
        If Core.Battle == None
            Core.DebugMsg("Story DM: quest/faction_battle rejected -- Battle quest not set (check CK property)")
            return
        EndIf
        String validateJson = IntelEngine.ValidateFactionBattleDispatch(alliedFaction, suggestedEnemy)
        If IntelEngine.StoryResponseGetField(validateJson, "canStart") != "true"
            Core.DebugMsg("Story DM: quest/faction_battle rejected -- " + IntelEngine.StoryResponseGetField(validateJson, "failReason"))
            return
        EndIf
        ; Store the validated enemy faction (C++ resolved it from DM suggestion or war enemy)
        QuestBattleEnemyFaction = IntelEngine.StoryResponseGetField(validateJson, "enemyFaction")
        Core.DebugMsg("Story DM: faction_battle enemy = " + QuestBattleEnemyFaction)
        ; Also check Papyrus-only state (BattleScheduled is a Papyrus property)
        If Core.Battle.BattleScheduled
            Core.DebugMsg("Story DM: quest/faction_battle rejected -- battle system busy (scheduled)")
            return
        EndIf
    EndIf

    ; Inject purpose facts — C++ builds faction_battle text, Papyrus handles generic
    If questSubTypeStr == "faction_battle"
        Core.InjectFact(questGiverActor, IntelEngine.BuildFactionBattleDispatchFact(alliedFaction, questLocationStr, Game.GetPlayer().GetDisplayName()))
    Else
        Core.InjectFact(questGiverActor, "asked " + Game.GetPlayer().GetDisplayName() + " for help: " + msgContent)
    EndIf

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

    ; Normalize faction sub-types to their base types — faction_combat/faction_rescue
    ; work identically to combat/rescue, just with faction soldiers as enemies.
    ; Standing rewards are driven by QuestAlliedFaction being set, not by the sub-type name.
    QuestAlliedFaction = alliedFaction

    ; Faction quests: remove player from crime factions for the ENTIRE quest duration.
    ; This prevents bounty from stray hits during battle, near guards, etc.
    ; Restored in OnQuestComplete / OnQuestFailed / OnQuestExpired.
    If alliedFaction != ""
        IntelEngine.RemovePlayerCrimeFactions()
    EndIf
    If questSubTypeStr == "faction_combat"
        questSubTypeStr = "combat"
    ElseIf questSubTypeStr == "faction_rescue"
        questSubTypeStr = "rescue"
    EndIf

    ; Sub-type specific fact injection (after normalization so "rescue" covers both rescue and faction_rescue)
    If questSubTypeStr == "rescue" && victimActor != None
        Core.InjectFact(victimActor, "was captured by " + enemyType + " near " + questLocationStr + " and held against my will")
    EndIf

    ; Set sub-type state
    QuestSubType = questSubTypeStr
    QuestBriefing = msgContent
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

    ; Push quest state to C++ for SkyrimNet decorator
    IntelEngine.NotifyQuestActive(QuestLocationName, QuestSubType, QuestEnemyType, \
        questGiverActor.GetDisplayName(), msgContent, victimName, itemName, alliedFaction)

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
    ; Delay before quest prompt so NPC has time to talk (reduced from 15s)
    Utility.Wait(8.0)
    Debug.Notification("They seem to have more to ask...")
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
    ElseIf QuestSubType == "faction_battle" || (QuestAlliedFaction != "" && QuestSubType == "combat")
        String allyName = IntelEngine.GetFactionDisplayName(QuestAlliedFaction)
        questPromptText = ActiveStoryNPC.GetDisplayName() + " rallies you to fight alongside the " + allyName + " near " + questLoc + "."
    ElseIf QuestAlliedFaction != "" && QuestSubType == "rescue"
        String allyName2 = IntelEngine.GetFactionDisplayName(QuestAlliedFaction)
        questPromptText = ActiveStoryNPC.GetDisplayName() + " urges you to rescue " + QuestVictimName + " for the " + allyName2 + " near " + questLoc + "."
    Else
        questPromptText = ActiveStoryNPC.GetDisplayName() + " tells you about trouble near " + questLoc + "."
    EndIf

    String choice = ""
    ; Couriers, followers, and faction quest couriers can't guide.
    ; Faction couriers are local guards/soldiers — already at the location.
    Bool canGuide = isDirect && !ActiveStoryNPC.IsPlayerTeammate() && QuestAlliedFaction == ""
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
    IntelEngine.MarkSystemPending("storyDM", Utility.GetCurrentGameTime())

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

    ; faction_battle: battle system handles everything via ScheduleBattle — no pre-placement needed.
    ; Without this guard, QuestPrePlaced gets set and CheckQuestProximity enters the pre-placed
    ; path, which waits for the boss room cell to load. But faction_battle spawns are exterior
    ; (battle soldiers), so the boss room never loads and nothing ever spawns.
    If QuestSubType == "faction_battle"
        return
    EndIf

    ObjectReference bossAnchor = IntelEngine.GetDungeonBossAnchor(QuestLocationName)
    If bossAnchor == None
        Core.DebugMsg("Story [quest/" + QuestSubType + "]: no dungeon boss anchor for '" + QuestLocationName + "' — using deferred spawn")
        return
    EndIf

    QuestBossAnchor = bossAnchor
    Core.DebugMsg("Story [quest/" + QuestSubType + "]: pre-placing at boss anchor in '" + QuestLocationName + "'")

    ; === RESCUE: place victim at boss room ===
    ; Package override (sandbox at anchor) keeps her at the anchor in unloaded cells.
    ; Essential + NoBleedoutRecovery + HP=1: the first bandit hit drops her to 0 HP,
    ; triggering the engine's native bleedout state (kneel pose, unable to act, unable
    ; to die, unable to recover). Per-tick re-pins HP to 1 in case of natural regen.
    If QuestSubType == "rescue" && QuestVictimNPC != None
        Core.RemoveAllPackages(QuestVictimNPC, false)
        QuestVictimNPC.MoveTo(bossAnchor, 0.0, 0.0, 0.0)
        ; Package override prevents persistent NPCs' template package from walking
        ; them home while the cell is unloaded.
        PO3_SKSEFunctions.SetLinkedRef(QuestVictimNPC, bossAnchor, Core.IntelEngine_TravelTarget)
        ActorUtil.AddPackageOverride(QuestVictimNPC, Core.SandboxNearPlayerPackage, Core.PRIORITY_TRAVEL, 1)
        StorageUtil.SetIntValue(QuestVictimNPC, "Intel_WasEssential", QuestVictimNPC.IsEssential() as Int)
        QuestVictimNPC.GetActorBase().SetEssential(true)
        QuestVictimNPC.SetNoBleedoutRecovery(true)
        ; DamageActorValue past current HP + EvaluatePackage is the pattern that
        ; reliably triggers the bleedout state + kneel anim on essential actors.
        ; This is what the committed version used — it works flawlessly when the
        ; cell is loaded, and first-3D-load re-applies for the unloaded case.
        QuestVictimNPC.DamageActorValue("Health", QuestVictimNPC.GetActorValue("Health") + 100.0)
        QuestVictimNPC.EvaluatePackage()
        IntelEngine.NotifyStoryCooldown(QuestVictimNPC, Utility.GetCurrentGameTime())
        Core.DebugMsg("Story [quest/rescue]: victim " + QuestVictimNPC.GetDisplayName() + " placed at boss room in bleedout")
    EndIf

    ; === FIND_ITEM: spawn chest directly at boss anchor ===
    ; PlaceObjectAtMe on a persistent XMarker creates the ref inside the anchor's
    ; cell natively, even when that cell is unloaded. Avoids the
    ; spawn-at-player-then-MoveTo pattern which is unreliable for non-persistent refs.
    If QuestSubType == "find_item" && QuestItemName != ""
        ObjectReference chest = IntelEngine.SpawnQuestChest(bossAnchor, QuestItemName)
        If chest != None
            QuestItemChest = chest
            Core.DebugMsg("Story [quest/find_item]: chest with " + QuestItemName + " spawned at boss anchor")
        EndIf
    EndIf

    ; === COMBAT: spawn boss directly at boss anchor ===
    ; Same rationale as find_item chest — spawn at anchor so PlaceObjectAtMe
    ; places the new ref in the anchor's cell. Boss is the compass target, so
    ; the marker leads straight to where the enemies will spawn on cell load.
    If QuestSubType == "combat"
        Actor boss = IntelEngine.SpawnQuestBoss(bossAnchor, QuestEnemyType)
        If boss != None
            QuestBossNPC = boss
            StorageUtil.FormListAdd(Game.GetPlayer(), "Intel_QuestSpawnedNPCs", boss)
            QuestSpawnCount += 1
            Core.DebugMsg("Story [quest/combat]: boss spawned at boss anchor")
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
            ; GUARD: targetNearby requires player to also be near QuestLocation.
            ; Without this, a boss/victim whose position reverts after save/reload
            ; (non-persistent PlaceObjectAtMe refs in unloaded cells) spawns enemies
            ; wherever the player happens to be — not at the dungeon.
            Bool bossLoaded = QuestBossAnchor.Is3DLoaded()
            Bool targetNearby = false
            If !bossLoaded && QuestLocation != None
                Float questDist = IntelEngine.GetDistance3D(Game.GetPlayer(), QuestLocation)
                Bool nearQuestArea = questDist < 4000.0
                If nearQuestArea && QuestSubType == "rescue" && QuestVictimNPC != None && QuestVictimNPC.Is3DLoaded()
                    targetNearby = Game.GetPlayer().GetDistance(QuestVictimNPC) < 2000.0
                ElseIf nearQuestArea && QuestSubType == "combat" && QuestBossNPC != None && QuestBossNPC.Is3DLoaded()
                    targetNearby = Game.GetPlayer().GetDistance(QuestBossNPC) < 2000.0
                EndIf
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

                ; Apply bleedout BEFORE enabling enemies — generic NPCs can't survive a
                ; bandit room in combat. Order: lock passive + damage + pin + anim, THEN
                ; activate hostiles so they spawn into a room with a downed captive.
                If QuestSubType == "rescue" && QuestVictimNPC != None && !QuestVictimFreed && !QuestVictimInFurniture
                    QuestVictimNPC.SetNoBleedoutRecovery(true)
                    QuestVictimNPC.DamageActorValue("Health", QuestVictimNPC.GetActorValue("Health") + 100.0)
                    QuestVictimNPC.EvaluatePackage()
                    Core.DebugMsg("Story [quest/rescue]: re-applied bleedout on first 3D load")
                EndIf

                ; Find_item: chests created via PlaceObjectAtMe in unloaded cells
                ; don't sync script-added items to the inventory UI until first-open.
                ; Re-add the item now that the cell is loaded so the player sees it
                ; on their very first interaction.
                If QuestSubType == "find_item" && QuestItemChest != None && QuestItemName != ""
                    IntelEngine.EnsureQuestItemInChest(QuestItemChest, QuestItemName)
                    Core.DebugMsg("Story [quest/find_item]: ensured '" + QuestItemName + "' is in chest on first 3D load")
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
            EndIf
            return  ; Pre-placed quests don't use the proximity-based spawn path below
        EndIf

        ; Never spawn quest enemies while the player is in a safe interior (inn, shop, home).
        ; Is3DLoaded() on exterior markers can return true from inside a nearby building,
        ; which would spawn bandits in The Bannered Mare when the quest is at Nilheim.
        ; Exception 1: dangerous locations (dungeons, forts) always allow spawns.
        ; Exception 2: QuestDeferredToInterior means we detected a dungeon entrance near
        ; the quest marker. Some modded dungeons lack LocTypeDungeon keywords, so
        ; IsPlayerInDangerousLocation returns false. The deferred flag + Layer 4's
        ; location verification (below) together guard against wrong-dungeon spawns.
        Actor player = Game.GetPlayer()
        If player.IsInInterior() && !IntelEngine.IsPlayerInDangerousLocation() && !QuestDeferredToInterior
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
        ; Handles interior dungeons where QuestLocation is an exterior MapMarkerREF.
        ; IMPORTANT: BGSLocation for cities (Whiterun, Solitude) covers a huge area
        ; including farms, meaderies, and stables. Add a distance gate so we don't
        ; trigger at Honningbrew when the quest is at Whiterun city center.
        If !atQuestArea
            Location questLoc = QuestLocation.GetCurrentLocation()
            If questLoc != None && player.IsInLocation(questLoc)
                ; Verify player is reasonably close (within 6000 units = ~86m)
                Float locDist = IntelEngine.GetDistance3D(player, QuestLocation)
                If locDist < 6000.0
                    atQuestArea = true
                    Core.DebugMsg("Story [quest]: BGSLocation spawn fallback triggered (dist=" + locDist + ")")
                Else
                    Core.DebugMsg("Story [quest]: BGSLocation match but too far (" + locDist + " units) — waiting")
                EndIf
            EndIf
        EndIf
        ; --- Layer 4: deferred interior entry ---
        ; When we previously detected a dungeon entrance near the quest marker and
        ; deferred spawning, the player is now inside. The exterior marker may be
        ; unloaded (Layer 1 fails), in a different cell (Layer 2 fails), and BGSLocation
        ; hierarchy may not link the interior (Layer 3 fails).
        ; IMPORTANT: verify the player is in a dungeon connected to the quest location.
        ; Without this, entering ANY dungeon (even across Skyrim) would trigger spawns
        ; because QuestDeferredToInterior stays true until quest cleanup.
        ; NOTE: GetDistance3D is unreliable across interior/exterior worldspaces (different
        ; coordinate spaces). Use the quest exterior marker's linked door chain instead.
        If !atQuestArea && QuestDeferredToInterior && player.IsInInterior()
            ; Check if the quest location's exterior has a door whose destination cell
            ; matches the player's current cell (or is in the same BGSLocation).
            ; GetParentCell on interior refs returns the interior cell.
            ; If QuestLocation Is3DLoaded, the player is near the entrance — trust it.
            If QuestLocation.Is3DLoaded()
                atQuestArea = true
                Core.DebugMsg("Story [quest]: deferred interior entry — quest exterior still loaded (player near entrance)")
            Else
                ; Exterior unloaded but check if IsPlayerInDangerousLocation matches
                ; the quest location's BGSLocation hierarchy
                Location questLoc = QuestLocation.GetCurrentLocation()
                If questLoc != None && player.IsInLocation(questLoc)
                    atQuestArea = true
                    Core.DebugMsg("Story [quest]: deferred interior entry — BGSLocation match")
                Else
                    ; Last resort: the player entered SOME dungeon while deferred was set.
                    ; We can't reliably verify it's the quest dungeon without coordinate math.
                    ; Be conservative: do NOT spawn. The dungeon scan path (lines below)
                    ; will handle it once they go deeper and ScanAheadForAnchor finds something.
                    Core.DebugMsg("Story [quest]: deferred interior but can't verify quest dungeon — waiting for scan")
                EndIf
            EndIf
        EndIf
        If atQuestArea
            ; faction_battle: trigger battle system instead of spawning enemies
            If QuestSubType == "faction_battle" && QuestAlliedFaction != "" && !QuestBattleScheduled
                Core.DebugMsg("Story [quest/faction_battle]: player arrived at " + QuestLocationName + " — triggering battle")
                ; Use the validated enemy from dispatch (not re-derived) — prevents DM's choice being overridden
                String enemyFaction = QuestBattleEnemyFaction
                If enemyFaction == ""
                    ; Fallback for old saves where QuestBattleEnemyFaction wasn't set
                    enemyFaction = IntelEngine.GetFactionWarEnemy(QuestAlliedFaction)
                EndIf
                If enemyFaction != "" && enemyFaction != QuestAlliedFaction
                    IntelEngine_Battle battle = Core.Battle
                    If battle != None && !IntelEngine.IsBattleActive() && !battle.BattleScheduled
                        ; Set guards BEFORE calling StartBattleImmediate — it has Utility.Wait
                        ; calls inside SpawnWave that yield the thread, allowing CheckQuestProximity
                        ; to re-enter and trigger a second battle (which sees "busy" and kills the quest).
                        QuestBattleScheduled = true
                        QuestEnemiesSpawned = true  ; prevent normal spawn logic
                        ; Player agreed to fight — auto-join the allied faction
                        battle.QuestAutoJoinFaction = QuestAlliedFaction
                        battle.BattleSpawnAnchor = QuestLocation
                        battle.StartBattleImmediate(QuestAlliedFaction, enemyFaction, 0)
                        ; Verify the battle actually started
                        If !IntelEngine.IsBattleActive()
                            Core.DebugMsg("Story [quest/faction_battle]: StartBattleImmediate failed, failing quest")
                            Debug.Notification("The forces have already moved on.")
                            QuestBattleScheduled = false
                            QuestEnemiesSpawned = false
                            RemoveQuestMarker()
                            CleanupQuest()
                            return
                        EndIf
                        Core.DebugMsg("Story [quest/faction_battle]: battle started — " + QuestAlliedFaction + " vs " + enemyFaction)
                    Else
                        Core.DebugMsg("Story [quest/faction_battle]: battle system busy, granting partial credit")
                        Debug.Notification("The fighting is already underway elsewhere.")
                        If QuestAlliedFaction != ""
                            IntelEngine.AdjustPlayerFactionStanding(QuestAlliedFaction, QUEST_STANDING_REWARD / 2)
                        EndIf
                        RemoveQuestMarker()
                        CleanupQuest()
                    EndIf
                Else
                    Core.DebugMsg("Story [quest/faction_battle]: no rival found for " + QuestAlliedFaction + ", failing quest")
                    String allyFailName = IntelEngine.GetFactionDisplayName(QuestAlliedFaction)
                    If allyFailName != ""
                        Debug.Notification("The " + allyFailName + " held the field unopposed.")
                    EndIf
                    RemoveQuestMarker()
                    CleanupQuest()
                EndIf
                return
            EndIf
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

                    ; Place victim at anchor (rescue). Cell is loaded here (player is
                    ; inside the dungeon), so SetDontMove + damage apply reliably. Package
                    ; override for consistency with dispatch-time placement.
                    If QuestSubType == "rescue" && QuestVictimNPC != None
                        Core.RemoveAllPackages(QuestVictimNPC, false)
                        QuestVictimNPC.MoveTo(aheadAnchor, 0.0, 0.0, 0.0)
                        PO3_SKSEFunctions.SetLinkedRef(QuestVictimNPC, aheadAnchor, Core.IntelEngine_TravelTarget)
                        ActorUtil.AddPackageOverride(QuestVictimNPC, Core.SandboxNearPlayerPackage, Core.PRIORITY_TRAVEL, 1)
                        StorageUtil.SetIntValue(QuestVictimNPC, "Intel_WasEssential", QuestVictimNPC.IsEssential() as Int)
                        QuestVictimNPC.GetActorBase().SetEssential(true)
                        QuestVictimNPC.SetNoBleedoutRecovery(true)
                        ; DamageActorValue + EvaluatePackage reliably triggers bleedout
                        ; state + kneel animation on essential actors.
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
        ; faction_battle: monitor for battle end (quest completes when battle finishes)
        If QuestBattleScheduled
            ; Second buildup notification — fires once during the waiting period
            Float battleElapsed = Utility.GetCurrentGameTime() - QuestGuideStartTime
            If battleElapsed > BATTLE_BUILDUP_NOTIFY_MIN && battleElapsed < BATTLE_BUILDUP_NOTIFY_MAX && QuestSpawnAttempts == 0
                QuestSpawnAttempts = 1  ; prevent repeat
                Debug.Notification("You hear the clink of armor ahead.")
            EndIf
            ; Third dramatic beat: fire once when battle actually starts
            If IntelEngine.IsBattleActive() && QuestSpawnAttempts < 2
                QuestSpawnAttempts = 2
                Debug.Notification("Sounds of fighting carry from up ahead.")
            EndIf
            ; Minimum delay: don't check for completion until battle has had time to start
            If battleElapsed < BATTLE_MIN_START_DELAY
                return
            EndIf
            If !IntelEngine.IsBattleActive() && (Core.Battle == None || !Core.Battle.BattleScheduled)
                Core.DebugMsg("Story [quest/faction_battle]: battle ended, completing quest. QuestActive=" + QuestActive + " IsActive=" + IsActive + " IsNPCStoryActive=" + IsNPCStoryActive)
                OnQuestComplete()
                Core.DebugMsg("Story [quest/faction_battle]: OnQuestComplete returned. QuestActive=" + QuestActive + " IsActive=" + IsActive)
            EndIf
            return
        EndIf
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
                ; Per-tick state re-apply. SetDontMove only for furniture — on bleedout
                ; victims it blocks the fall-to-kneel animation.
                If QuestVictimInFurniture
                    QuestVictimNPC.SetDontMove(true)
                Else
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
        ; No safe-interior re-check here — CheckQuestProximity already validated
        ; the location via the 4-layer proximity system + safe interior guard.
        ; Double-gating caused enemies to never spawn in dungeons whose deeper
        ; cells lacked LocTypeDungeon keywords (common in modded content).
        If QuestSubType == "rescue"
            ; Deep scan: follows doors to adjacent cells for prisoner furniture
            ObjectReference rescuePoint = IntelEngine.FindRescueAnchor(player)
            If rescuePoint != None
                victimAnchor = rescuePoint
                enemyAnchor = player    ; enemies between player and victim
                Core.DebugMsg("Story [quest/rescue]: victim deep at rescue anchor, enemies near player")
            Else
                ; No rescue anchor — spawn near player (we're inside the quest dungeon).
                ; Can't use QuestLocation — it's an exterior marker, wrong worldspace.
                victimAnchor = player
                enemyAnchor = player
                Core.DebugMsg("Story [quest/rescue]: no rescue anchor, spawning near player (interior fallback)")
            EndIf
        Else
            ; find_item / combat: deeper dungeon point, or offset from player as last resort
            ObjectReference deeperPoint = IntelEngine.FindDeeperSpawnPoint(player)
            If deeperPoint != None
                victimAnchor = deeperPoint
                enemyAnchor = deeperPoint
                Core.DebugMsg("Story [quest/" + QuestSubType + "]: spawning at dungeon landmark")
            Else
                ; No landmarks found. We're confirmed inside the quest dungeon (Layer 4
                ; verified proximity). Spawn ahead of the player — not ON them (jarring)
                ; and not at QuestLocation (exterior marker = wrong worldspace).
                ; Using player as anchor with offset in MoveTo calls downstream.
                victimAnchor = player
                enemyAnchor = player
                Core.DebugMsg("Story [quest/" + QuestSubType + "]: no landmarks found, spawning near player (interior fallback)")
            EndIf
        EndIf
    EndIf

    ; === Rescue sub-type: teleport victim DEEP inside ===
    If QuestSubType == "rescue" && QuestVictimNPC != None
        ; Strip all packages BEFORE teleport+restrain (packages can override restraint)
        Core.RemoveAllPackages(QuestVictimNPC, false)
        QuestVictimNPC.MoveTo(victimAnchor, 0.0, 0.0, 0.0, false)
        ; Package override pins her at victimAnchor so her template package can't
        ; pull her home. No SetDontMove — it blocks the bleedout fall-to-kneel
        ; transition; bleedout is self-immobilizing via engine.
        PO3_SKSEFunctions.SetLinkedRef(QuestVictimNPC, victimAnchor, Core.IntelEngine_TravelTarget)
        ActorUtil.AddPackageOverride(QuestVictimNPC, Core.SandboxNearPlayerPackage, Core.PRIORITY_TRAVEL, 1)
        ; Protect victim from death — always make essential for bleedout
        StorageUtil.SetIntValue(QuestVictimNPC, "Intel_WasEssential", QuestVictimNPC.IsEssential() as Int)
        QuestVictimNPC.GetActorBase().SetEssential(true)
        ; DamageActorValue + EvaluatePackage triggers bleedout state + kneel anim on essentials.
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
        ; Safety net: after 3 failed spawn attempts, grant partial completion.
        ; The player traveled here — reward the effort even if spawns failed.
        Core.DebugMsg("Story [quest]: spawn failed after 3 attempts, granting partial completion")
        Debug.Notification("The area is quiet. The threat seems to have moved on.")
        If QuestGiver != None && QuestEnemyType != "" && QuestLocationName != ""
            Core.InjectFact(QuestGiver, "learned that " + Game.GetPlayer().GetDisplayName() + " traveled to " + QuestLocationName + " but the " + QuestEnemyType + " threat had already dispersed")
        EndIf
        ; Partial standing reward for showing up (half of normal quest reward)
        If QuestAlliedFaction != "" && QuestSubType != "faction_battle"
            IntelEngine.AdjustPlayerFactionStanding(QuestAlliedFaction, QUEST_STANDING_REWARD / 2)
            String allyName = IntelEngine.GetFactionDisplayName(QuestAlliedFaction)
            If allyName != ""
                Debug.Notification("The " + allyName + " acknowledge your willingness to help.")
            EndIf
        EndIf
        RemoveQuestMarker(true)
        CleanupQuest()
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
        ; Bleedout victim: unpin and recover from bleedout
        QuestVictimNPC.SetDontMove(false)
        QuestVictimNPC.SetNoBleedoutRecovery(false)
        Core.DebugMsg("Story [quest/rescue]: victim " + QuestVictimNPC.GetDisplayName() + " freed from bleedout")
    EndIf
    ; Heal victim fully after freeing
    QuestVictimNPC.RestoreActorValue("Health", 500.0)
    Core.NotifyPlayer(QuestVictimNPC.GetDisplayName() + " has been freed!")
EndFunction

Function OnQuestComplete()
    ; Re-entrant guard: battle poll + story tick can both call CheckQuestProximity simultaneously
    If !QuestActive
        return
    EndIf
    QuestActive = false  ; prevent double-completion from concurrent calls

    ; Restore crime factions if this was a faction quest
    If QuestAlliedFaction != ""
        IntelEngine.RestorePlayerCrimeFactions()
    EndIf

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
            ; Two-phase walk-to-player: Phase 1 TravelPackage_Walk actively paths her
            ; toward the player; Phase 2 swaps to SandboxNearPlayerPackage once she's
            ; within LINGER_APPROACH_DISTANCE. Handled by CheckStoryLingerCleanup, same
            ; approach flag Travel uses so the behavior matches "wait for player" arrivals.
            ; Narration fires on proximity (~400 units) regardless of which package is active.
            Core.RemoveAllPackages(QuestVictimNPC, false)
            PO3_SKSEFunctions.SetLinkedRef(QuestVictimNPC, Game.GetPlayer() as ObjectReference, Core.IntelEngine_TravelTarget)
            ActorUtil.AddPackageOverride(QuestVictimNPC, Core.TravelPackage_Walk, Core.PRIORITY_TRAVEL, 1)
            StorageUtil.SetIntValue(QuestVictimNPC, "Intel_MeetingLingerApproaching", 1)
            Utility.Wait(0.1)
            QuestVictimNPC.EvaluatePackage()
            StartStoryLinger(QuestVictimNPC)
            ; Mark victim as handled — CleanupQuest won't teleport them
            QuestVictimNPC = None
        EndIf
    ElseIf QuestSubType == "find_item"
        Core.NotifyPlayer("You claim the " + QuestItemDesc + ".")
        If QuestGiver != None
            Core.InjectFact(QuestGiver, "learned that " + playerName + " found " + QuestItemDesc + " at " + QuestLocationName)
        EndIf
    ElseIf QuestSubType == "faction_battle"
        ; C++ handles: political event recording, fact text building, notification
        String completionJson = IntelEngine.RecordFactionBattleCompletion(QuestAlliedFaction, QuestLocationName, playerName, QuestBattleEnemyFaction)
        String completionNotif = IntelEngine.StoryResponseGetField(completionJson, "notification")
        If completionNotif != ""
            Debug.Notification(completionNotif)
        EndIf
        ; Papyrus-only: inject facts into loaded actors (requires Actor handles)
        If QuestGiver != None
            Core.InjectFact(QuestGiver, IntelEngine.StoryResponseGetField(completionJson, "questGiverFact"))
        EndIf
        String leaderFact = IntelEngine.StoryResponseGetField(completionJson, "leaderFact")
        If leaderFact != ""
            Actor[] leaders = IntelEngine.GetFactionLeaderActors(QuestAlliedFaction)
            Int li = 0
            While li < leaders.Length
                If leaders[li] && leaders[li] != QuestGiver
                    Core.InjectFact(leaders[li], leaderFact)
                EndIf
                li += 1
            EndWhile
        EndIf
        ; Standing handled entirely by the battle system (ApplyPostBattleStanding)
    Else
        Core.NotifyPlayer("The threat has been dealt with.")
        If QuestGiver != None
            Core.InjectFact(QuestGiver, "learned that " + playerName + " dealt with the " + QuestEnemyType + " threat at " + QuestLocationName)
        EndIf
    EndIf

    ; Extract enemy faction ID once (used for guide fact + standing rewards)
    String enemyFactionId = IntelEngine.ExtractFactionId(QuestEnemyType)
    String enemyFactionDisplayName = ""
    If enemyFactionId != ""
        enemyFactionDisplayName = IntelEngine.GetFactionDisplayName(enemyFactionId)
    EndIf

    ; Guide NPC also learns about the outcome (if different from quest giver)
    If QuestGuideNPC != None && QuestGuideNPC != QuestGiver
        String guideEnemyDesc = QuestEnemyType
        If enemyFactionDisplayName != ""
            guideEnemyDesc = enemyFactionDisplayName + " soldiers"
        EndIf
        Core.InjectFact(QuestGuideNPC, "witnessed " + playerName + " clear the " + guideEnemyDesc + " at " + QuestLocationName)
    EndIf

    ; Faction standing rewards — driven by QuestAlliedFaction being set (faction quest sub-types
    ; are normalized to combat/rescue but keep the allied faction for standing adjustment).
    ; Skip for faction_battle — the battle system handles standing via ApplyPostBattleStanding.
    If QuestAlliedFaction != "" && QuestSubType != "faction_battle"
        If enemyFactionId != ""
            IntelEngine.AdjustPlayerFactionStanding(enemyFactionId, QUEST_STANDING_PENALTY)
            Core.DebugMsg("Story [quest/" + QuestSubType + "]: Standing " + QUEST_STANDING_PENALTY + " with " + enemyFactionId)
        EndIf
        IntelEngine.AdjustPlayerFactionStanding(QuestAlliedFaction, QUEST_STANDING_REWARD)
        Core.DebugMsg("Story [quest/" + QuestSubType + "]: Standing +" + QUEST_STANDING_REWARD + " with " + QuestAlliedFaction)
        ; Single immersive notification covering both effects
        String allyName = IntelEngine.GetFactionDisplayName(QuestAlliedFaction)
        If allyName != ""
            Int standingRoll = Utility.RandomInt(0, 2)
            If standingRoll == 0
                Debug.Notification("Your name carries weight among the " + allyName + ".")
            ElseIf standingRoll == 1
                Debug.Notification("The " + allyName + " speak your name with respect.")
            Else
                Debug.Notification("Word of your deeds reaches the " + allyName + ".")
            EndIf
        EndIf
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

Bool Property QuestExpiryWarned = false Auto Hidden

Function CheckQuestExpiry()
    If !QuestActive || QuestStartTime <= 0.0
        return
    EndIf
    Float elapsed = Utility.GetCurrentGameTime() - QuestStartTime
    ; Warning at 75% of expiry time
    If !QuestExpiryWarned && elapsed > (QUEST_EXPIRY_DAYS * 0.75)
        QuestExpiryWarned = true
        Debug.Notification("You should hurry — the situation won't hold much longer.")
    EndIf
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
        ElseIf QuestSubType == "faction_battle"
            If QuestGiver != None
                String allyNameExpiry = IntelEngine.GetFactionDisplayName(QuestAlliedFaction)
                Core.InjectFact(QuestGiver, "noted that " + playerName + " never arrived to fight alongside the " + allyNameExpiry + " at " + QuestLocationName)
            EndIf
            ; Cancel the scheduled battle if it hasn't started yet
            If QuestBattleScheduled && Core.Battle != None && Core.Battle.BattleScheduled && !IntelEngine.IsBattleActive()
                Core.Battle.ResetState()
                Core.DebugMsg("Story [quest/faction_battle]: cancelled scheduled battle on expiry")
            EndIf
            Debug.Notification("Word reaches you: the battle has moved on.")
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
        ; Restore courier aggression if it was modified
        Float origAggr = StorageUtil.GetFloatValue(ActiveStoryNPC, "Intel_OrigAggression", -1.0)
        If origAggr >= 0.0
            ActiveStoryNPC.SetActorValue("Aggression", origAggr)
            StorageUtil.UnsetFloatValue(ActiveStoryNPC, "Intel_OrigAggression")
        EndIf
        StorageUtil.UnsetIntValue(ActiveStoryNPC, "Intel_IsStoryDispatch")
        StorageUtil.UnsetStringValue(ActiveStoryNPC, "Intel_StoryNarration")
        StorageUtil.UnsetStringValue(ActiveStoryNPC, "Intel_MessageSender")
        StorageUtil.UnsetStringValue(ActiveStoryNPC, "Intel_MessageContent")
        StorageUtil.UnsetStringValue(ActiveStoryNPC, "Intel_QuestLocation")
        StorageUtil.UnsetIntValue(ActiveStoryNPC, "Intel_SneakPhase")
        StorageUtil.UnsetFloatValue(ActiveStoryNPC, "Intel_SneakStartTime")
        StorageUtil.UnsetFloatValue(ActiveStoryNPC, "Intel_CombatStartTime")
        StorageUtil.UnsetFloatValue(ActiveStoryNPC, "Intel_OffscreenArrival")
        StorageUtil.UnsetStringValue(ActiveStoryNPC, "Intel_MessageDest")
        StorageUtil.UnsetStringValue(ActiveStoryNPC, "Intel_MessageTime")
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

    ; === Battle marker cleanup ===
    If QuestBattleMarker != None
        QuestBattleMarker.Disable()
        QuestBattleMarker.Delete()
        QuestBattleMarker = None
    EndIf

    ; Safety net: restore crime factions if this was a faction quest.
    ; OnQuestComplete already calls this, but CleanupQuest is also called from
    ; expiry, failure, and abort paths — belt-and-suspenders.
    If QuestAlliedFaction != ""
        IntelEngine.RestorePlayerCrimeFactions()
    EndIf

    QuestActive = false
    IntelEngine.NotifyQuestCleared()
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
    QuestBriefing = ""
    QuestVictimName = ""
    QuestItemDesc = ""
    QuestItemName = ""
    QuestAlliedFaction = ""
    QuestBattleScheduled = false
    QuestVictimFreed = false
    QuestBossNPC = None
    QuestPrePlaced = false
    QuestBossAnchor = None
    QuestFurnitureScanned = false
    QuestVictimInFurniture = false
    QuestDungeonLastCell = None
    QuestDungeonDepth = 0
    QuestDungeonScanFails = 0
    QuestExpiryWarned = false

    AddRecentStoryEvent(eventText)
    Core.DebugMsg("Story [quest]: CleanupQuest done — QuestActive=" + QuestActive + " IsActive=" + IsActive + " IsNPCStoryActive=" + IsNPCStoryActive + " HasLingerNPCs=" + HasLingerNPCs())
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
    ElseIf QuestSubType == "faction_battle" && QuestLocation != None
        ; Temporary marker on quest location — SpawnFullBattle will move it
        ; to the battle leader's head once soldiers spawn. No XMarker math needed.
        QuestTargetAlias.ForceRefTo(QuestLocation)
        Core.DebugMsg("Story [quest]: temporary marker at " + QuestLocationName + " (moves to leader on spawn)")
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

Bool Function ShouldAbortForDangerZone(Actor npc, Actor player, String storyType, String logSuffix)
    If !IntelEngine.IsPlayerInDangerousLocation()
        return false
    EndIf
    If storyType == "informant"
        Core.DebugMsg("Story: aborting informant for " + npc.GetDisplayName() + " -- danger zone" + logSuffix)
        Core.SendTaskNarration(npc, "thought better of chasing " + player.GetDisplayName() + " into danger just for gossip and turned back", player)
        AbortStoryTravel("informant in danger zone" + logSuffix)
        return true
    EndIf
    If DangerZonePolicy == 3 || \
       (DangerZonePolicy == 2 && !IntelEngine.IsPotentialFollower(npc)) || \
       (DangerZonePolicy == 1 && IntelEngine.IsCivilianClass(npc))
        Core.DebugMsg("Story: aborting " + storyType + " for " + npc.GetDisplayName() + " -- danger zone policy" + logSuffix)
        Core.SendTaskNarration(npc, "turned back after learning that " + player.GetDisplayName() + " had ventured into a dangerous place", player)
        AbortStoryTravel("danger zone policy" + logSuffix)
        return true
    EndIf
    return false
EndFunction

Bool Function ShouldAbortForPlayerHome(Actor npc, Actor player, String storyType, String logSuffix)
    If !IntelEngine.IsPlayerInOwnHome()
        return false
    EndIf
    If PlayerHomePolicy == 3 || \
       (PlayerHomePolicy == 2 && !IntelEngine.IsPotentialFollower(npc)) || \
       (PlayerHomePolicy == 1 && IntelEngine.IsCivilianClass(npc))
        Core.DebugMsg("Story: aborting " + storyType + " for " + npc.GetDisplayName() + " -- player home policy" + logSuffix)
        Core.SendTaskNarration(npc, "decided not to bother " + player.GetDisplayName() + " at home and turned back", player)
        AbortStoryTravel("player home policy" + logSuffix)
        return true
    EndIf
    return false
EndFunction

Bool Function ShouldAbortForHoldRestriction(Actor npc, Actor player, String storyType, String logSuffix)
    If !IntelEngine.CheckHoldRestriction(npc, storyType)
        Core.DebugMsg("Story: aborting " + storyType + " for " + npc.GetDisplayName() + " -- hold restriction" + logSuffix)
        Core.SendTaskNarration(npc, "decided the journey to find " + player.GetDisplayName() + " was too far and turned back", player)
        AbortStoryTravel("hold restriction" + logSuffix)
        return true
    EndIf
    return false
EndFunction

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
        ; Restore original aggression if it was lowered for courier approach
        Float origAggr = StorageUtil.GetFloatValue(ActiveStoryNPC, "Intel_OrigAggression", -1.0)
        If origAggr >= 0.0
            ActiveStoryNPC.SetActorValue("Aggression", origAggr)
            StorageUtil.UnsetFloatValue(ActiveStoryNPC, "Intel_OrigAggression")
        EndIf
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
    IntelEngine.ClearSystemPending("storyDM")
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

Function AddNPCSocialLog(String eventType, String npc1Name, String npc2Name, String narration, Actor sourceNPC = None, String detail = "")
    {Store structured NPC social interaction for dashboard display. Parallel StringLists, last 5.}
    Actor player = Game.GetPlayer()
    ; Get hold name from the NPC who initiated the interaction (not the player)
    String locName = ""
    If sourceNPC != None
        locName = IntelEngine.GetActorHoldName(sourceNPC)
    EndIf
    If locName == ""
        locName = IntelEngine.GetActorHoldName(player)
    EndIf
    ; Align Detail list with Type list (handles both save migration and prior off-by-one bug)
    ; Must run BEFORE adding the new Type entry, otherwise it pads the current entry's slot
    Int typeCount = StorageUtil.StringListCount(player, "Intel_SocialLog_Type")
    Int detailCount = StorageUtil.StringListCount(player, "Intel_SocialLog_Detail")
    While detailCount < typeCount
        StorageUtil.StringListAdd(player, "Intel_SocialLog_Detail", "")
        detailCount += 1
    EndWhile
    While detailCount > typeCount
        StorageUtil.StringListRemoveAt(player, "Intel_SocialLog_Detail", 0)
        detailCount -= 1
    EndWhile
    StorageUtil.StringListAdd(player, "Intel_SocialLog_Type", eventType)
    StorageUtil.StringListAdd(player, "Intel_SocialLog_NPC1", npc1Name)
    StorageUtil.StringListAdd(player, "Intel_SocialLog_NPC2", npc2Name)
    StorageUtil.StringListAdd(player, "Intel_SocialLog_Text", narration)
    StorageUtil.StringListAdd(player, "Intel_SocialLog_Location", locName)
    StorageUtil.StringListAdd(player, "Intel_SocialLog_Detail", detail)
    While StorageUtil.StringListCount(player, "Intel_SocialLog_Type") > 5
        StorageUtil.StringListRemoveAt(player, "Intel_SocialLog_Type", 0)
        StorageUtil.StringListRemoveAt(player, "Intel_SocialLog_NPC1", 0)
        StorageUtil.StringListRemoveAt(player, "Intel_SocialLog_NPC2", 0)
        StorageUtil.StringListRemoveAt(player, "Intel_SocialLog_Text", 0)
        StorageUtil.StringListRemoveAt(player, "Intel_SocialLog_Location", 0)
        StorageUtil.StringListRemoveAt(player, "Intel_SocialLog_Detail", 0)
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

String Function BuildFactionQuestNarration(String factionName, String questLocation)
    Int variant = Utility.RandomInt(0, 3)
    If variant == 0
        return "brought urgent word from the " + factionName + " about trouble near " + questLocation
    ElseIf variant == 1
        return "arrived bearing a warning from the " + factionName + " concerning " + questLocation
    ElseIf variant == 2
        return "brought word of trouble brewing at " + questLocation + " — the " + factionName + " need help"
    Else
        return "rushed over with grim news from the " + factionName + " about " + questLocation
    EndIf
EndFunction

Int Function PackToggleBitmask()
    ; Pack MCM toggles into bitmask for C++ validation.
    ; Only reads current property values — no logic to go stale.
    Int t = 0
    If TypeSeekPlayerEnabled
        t += 1
    EndIf
    If TypeInformantEnabled
        t += 2
    EndIf
    If TypeRoadEncounterEnabled
        t += 4
    EndIf
    If TypeAmbushEnabled
        t += 8
    EndIf
    If TypeStalkerEnabled
        t += 16
    EndIf
    If TypeMessageEnabled
        t += 32
    EndIf
    If TypeQuestEnabled
        t += 64
    EndIf
    If TypeFactionAmbushEnabled
        t += 128
    EndIf
    If QuestSubTypeCombatEnabled
        t += 256
    EndIf
    If QuestSubTypeRescueEnabled
        t += 512
    EndIf
    If QuestSubTypeFindItemEnabled
        t += 1024
    EndIf
    If QuestSubTypeFactionCombatEnabled
        t += 2048
    EndIf
    If QuestSubTypeFactionRescueEnabled
        t += 4096
    EndIf
    If QuestSubTypeFactionBattleEnabled
        t += 8192
    EndIf
    return t
EndFunction

Int Function PackEnvFlags(Actor player)
    Int f = 0
    Cell pCell = player.GetParentCell()
    If pCell != None && pCell.IsInterior()
        f += 1
    EndIf
    If IntelEngine.IsPlayerInDangerousLocation()
        f += 2
    EndIf
    return f
EndFunction

String Function ExtractJsonField(String json, String fieldName)
    return IntelEngine.StoryResponseGetField(json, fieldName)
EndFunction
