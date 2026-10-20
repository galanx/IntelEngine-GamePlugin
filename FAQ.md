# IntelEngine — FAQ

By Galanx 3/2026

Original answers are preserved below; ~~struck text~~ is superseded by the dated fork-dev update immediately after it, and dated notes qualify unverified claims.

**Q: What is IntelEngine?**

IntelEngine is a Skyrim mod that gives NPCs the ability to act independently in the game world. Instead of standing in one spot waiting for the player, NPCs can travel across the map, carry out tasks, remember what happened, and even pursue their own goals — all driven by AI via SkyrimNet.

**Q: What does it actually do in-game?**

You can give NPCs orders through natural conversation — things like "go find Ysolda and bring her here," "tell the Jarl I'll meet him at the inn at sunset," or "escort Adrianne to Dragonsreach." NPCs physically walk to their destination, ~~no teleporting~~. They calculate travel time, leave early enough to arrive on schedule, and wait naturally when they get there. Missed meetings and late arrivals are tracked and remembered.

> **Updated 2026-10-19 (fork dev, after 3.5.2):** Normal travel is physical, but door transitions, stuck recovery and travel timeouts can teleport NPCs. Scheduled departure and meeting outcomes are tracked; arrival on time is not guaranteed.

**Q: Do NPCs do things on their own?**

Yes. A built-in Dungeon Master system generates dynamic events throughout your playthrough. NPCs will seek you out over unfinished business, ambush you over old grudges, spread gossip through realistic chains of people, offer you quests like rescues or dungeon clears, and even cross your path by coincidence while traveling on their own errands.

**Q: Is there a political system?**

Nine factions form alliances, negotiate trade deals, spy on each other, declare wars, and fight battles in the background. If you happen to be nearby when a battle kicks off, soldiers spawn and fight it out. Your standing with each faction rises and falls based on your choices and actions.

**Q: Do NPCs remember what happens?**

~~Every completed task, delivered message, failed meeting, and overheard rumor persists in an NPC's memory and shapes how they interact with you going forward. Betray someone and they hold a grudge. Be reliable and they trust you more.~~

> **Updated 2026-10-19 (fork dev, after 3.5.2):** Tasks, messages, meeting outcomes, facts and gossip provide NPC context, but facts can expire. Memory is not a guarantee of permanent retention or a particular trust/grudge response from the AI.

**Q: My followers keep leaving to do tasks. How do I stop this?**

MCM or Prisma Dashboard → Settings → Skip Action for Followers. Toggle ON for any actions you want blocked ~~(`Go To Location`, `Fetch Person`, `Deliver Message`, `Escort Target`)~~. ~~Followers will still talk, gossip, and interact — they just won't physically leave your side.~~

> **Updated 2026-10-19 (fork dev, after 3.5.2):** Settings → Skip Action for Followers now has eight actions: Go To Location, Fetch Person, Deliver Message, Escort Target, Search For Actor, Schedule Meeting, Schedule Fetch and Schedule Delivery. All skip toggles default OFF. Enable each action you want blocked; this is not a universal stay-with-me switch. Active followers are excluded from autonomous Story/social candidate selection; ordinary conversation is separate.

**Q: Can I get a confirmation prompt instead of blocking entirely?**

Under Action Confirmation Prompts, set actions to `Followers Only`. You'll get ~~a yes/no popup before any follower departs~~ (this is the default for most actions).

> **Updated 2026-10-19 (fork dev, after 3.5.2):** Action Confirmation Prompts cycles through Disabled, Followers Only and Everyone. The popup choices are Allow, Deny and Deny (Silent). Seven actions default to Followers Only; Schedule Meeting defaults to Everyone. Follower-skip toggles take precedence over prompts.

**Q:Nothing is happening. No NPCs are approaching me.**

Check that Story Engine is enabled in MCM → Settings. The default interval is 3 game hours — sleep or wait a bit. Also check that story types aren't all toggled off.

**Q: Events happen too often / not often enough.**

Adjust Check Interval (default 3 hours, range 0.5–168). Lower = more frequent.

**Q: The same NPC keeps getting picked.**

Increase ~~NPC Cooldown~~ (default 24 hours, range 6–72).

> **Updated 2026-10-19 (fork dev, after 3.5.2):** The MCM label is Story NPC Cooldown (hours): default 24, range 6–72. NPC Social Cooldown is a separate setting.

**Q: I don't want hostile encounters (ambushes, stalkers).**

MCM → Story Types (DM) → toggle OFF `Ambush`, `Stalker`, or `Faction Ambush` individually.

**Q: NPCs from other holds keep showing up.**

MCM → Hold Restrictions → ~~set each story type to `Same Town` or `Same Hold`~~.

> **Updated 2026-10-19 (fork dev, after 3.5.2):** In MCM → Hold Restrictions, choose Same town (everyone) or Same hold (everyone) for a strict restriction. Civilian-only and follower-exempt options are less restrictive. The page covers Seek Player, Informant, Road Encounter, Ambush, Stalker, Message and Quest; defaults vary by type.

**Q: Does IntelEngine conflict with SeverActions?**

~~No — they complement each other. We encourage using both. SeverActions features actions like `GiveItem` which pairs perfectly with IntelEngine's `find_item` quest — the NPC physically hands items and rewards to you and vice-versa. They share the same SkyrimNet action system with zero conflicts.~~

> **Updated 2026-10-19 (fork dev, after 3.5.2):** Do not assume zero conflicts. Overlapping travel, fetch, deliver or cancel actions can give the AI duplicate choices and incompatible task cancellation. Disable overlapping actions in one provider. IntelEngine has a find_item quest, but this fork does not establish a guaranteed SeverActions GiveItem/reward integration. See [compatibility guidance](README.md#compatibility).

**Q: Does it work with follower frameworks (AFT, NFF, etc.)?**

Yes. IntelEngine detects followers via the engine's `IsPlayerTeammate` flag, which all frameworks use. We recommend using SeverActions for managing followers.

> **Note 2026-10-19:** IntelEngine uses IsPlayerTeammate for follower checks, but these repositories do not establish that every AFT/NFF version or configuration sets that flag. The SeverActions recommendation above is Galanx’s original advice, not a compatibility guarantee from this fork.

**Q: How do I exclude a specific NPC?**

Plugin Configurations → NPC Blocklist (comma-separated). Example: `Nazeem, Heimskr`

**Q: How do I restrict events to specific NPCs only?**

Add names to NPC Whitelist. When non-empty, only listed NPCs are eligible.

**Q: How do I block a location or faction?**

Location Blocklist: `Whiterun, Solitude`

Faction Blocklist: `CrimeFactionWhiterun` (append `:rank` to filter by max rank, e.g. `BanditFaction:0`)

**Q: I lost my config files.**

Copy `settings.sample.yaml` or `factions.sample.yaml` from the mod folder and remove `.sample` from the filename.

**Q: Can I disable certain quest types?**

MCM or Dashboard → Quest Types → toggle OFF what you don't want (Combat, Rescue, Find Item, Faction Combat, Faction Rescue, Faction Battle).

**Q: Can rescue targets die?**

~~Only if you enable Allow NPC Death (Rescue) (OFF by default).~~ ⚠️ This can permanently kill named NPCs and break other quests.

> **Updated 2026-10-19 (fork dev, after 3.5.2):** The MCM toggle is Allow NPC death in rescue, OFF by default. Rescue handling temporarily protects victims and later restores their original essential state; OFF is not a guarantee of global invulnerability against other game/mod behavior. Keep the permanent-loss warning in mind.

**Q: How long do I have to complete a quest?**

Quest Timeout slider (default 1 day, max 30). After this, unfinished quests auto-expire.

**Q: How do I see faction relations?**

Prisma Dashboard (`Shift+7`) → **Politics** tab. Shows faction grid, active wars, standings, and events.

**Q: Can I trigger political events manually?**

Dashboard → Director tab → ~~Political Director. Pick factions, event type, and dispatch.~~

> **Updated 2026-10-19 (fork dev, after 3.5.2):** Dashboard → Director → Political Event → Dispatch Political Event. Select both factions and event type, and supply a description and a nonzero relation change.

**Q: Can I add custom factions?**

Edit `factions.yaml` in `SKSE/Plugins/SkyrimNet/config/plugins/IntelEngine/`. If missing, copy `factions.sample.yaml` and remove `.sample`. ~~Be sure to remove factions.yaml from MO2 overwrite folder if adding your own.~~ ~~Also make sure the faction EditorId actually exists in Skyrim.~~

> **Updated 2026-10-19 (fork dev, after 3.5.2):** Preserve and merge any customized MO2 Overwrite copy rather than deleting it blindly; resolve which factions.yaml wins in your mod manager. The internal id is distinct from skyrim_faction_id: for example, ImperialFaction maps to CWImperialFaction. Engine faction IDs and other referenced forms must exist in your load order.

**Q: NPCs gossip and argue too much.**

Increase Interaction Interval (default 1.5 hours). Or toggle OFF `NPC Gossip` / `NPC Interaction` ~~under Story Types~~.

> **Updated 2026-10-19 (fork dev, after 3.5.2):** In MCM, use Settings → NPC Social Life → NPC Interaction Interval (hours), NPC Gossip or NPC Interaction. The dashboard calls the interval Interaction Interval. Default 1.5 game hours, range 0.5–168; NPC Social Cooldown is separate.

**Q: Can I trigger NPC interactions manually?**

Dashboard → Director tab → ~~NPC Social Director~~.

> **Updated 2026-10-19 (fork dev, after 3.5.2):** Dashboard → Director → NPC Social. Supply two NPCs, interaction/gossip type and narration; additional fields depend on the selected social type.

**Q: NPCs take forever to get somewhere.**

Lower Max Travel Time (default 1 day). NPCs exceeding this teleport or give up.

**Q: An NPC is stuck.**

~~Teleport When Stuck~~ is ON by default. Check Active Tasks in MCM to see and manage ~~all tasks~~.

> **Updated 2026-10-19 (fork dev, after 3.5.2):** The MCM toggle is Teleport on stuck/timeout, ON by default. Active Tasks manages player task slots, not every Story/social activity. The dashboard also has a Packages tab for inspecting and removing AI packages.

**Q: Too many NPCs doing tasks at once.**

Lower Max Concurrent Tasks (default 5, min 1).

**Q: What is Auto Dynamic Bio?**

When enabled, NPC bios automatically rewrite after X dialogue lines per NPC — keeping their personality evolving based on conversations. Disabled by default.

**Q: How do I enable it?**

MCM or Dashboard → Auto Dynamic Bio  → toggle ON. Set "Lines Before Update" (default 20, range 5–1000).

**Q: How do I open the dashboard?**

`Shift+7` (default). Change the hotkey in SkyrimNet → Plugin Configurations.

> **Note 2026-10-19:** Shift+7 is the sample/README configuration, but defaults conflict: settings.sample.yaml uses modifier 2 (Shift), manifest.yaml sets defaultValue 0 (no modifier), and its description says default 3 (Ctrl+Shift). Set Dashboard Hotkey and Dashboard Modifiers explicitly in IntelEngine plugin configuration. Modifier bits are 1=Ctrl, 2=Shift, 4=Alt; key -1 disables the dashboard hotkey. PrismaUI is required for the dashboard.

**Q: Dashboard too small on 4K?**

Increase UI Scale (recommended 1.5–2.0 for 4K).

**Q: How do I change which AI model IntelEngine uses?**

Dashboard or SkyrimNet Web UI → Plugin Configurations → IntelEngine → LLM Overrides. Leave empty to use the default model.

**Q: NPCs keep wanting to repeatedly travel somewhere on their own**

If it happens consecutively, the llm might be too eager to make them travel if the previous location hasn't been found. You can configure action cooldowns to prevent this behavior in SkyrimNet → Actions Library or if you like, try to change the action description to have stricter rules in SkyrimNet → Custom Actions → GoToLocation (or the action of your choice), or you can disable it entirely.

> **Note 2026-10-19:** The proposed LLM cause and SkyrimNet menu/cooldown advice are not verified fixes by this fork. Story/social NPC cooldowns are separate from conversational GoToLocation actions. Review action configuration and overlapping action providers; changing a description is not a guaranteed cure.

**Q: I changed the intel_story_dm model and now stories stopped working**

IntelEngine DM prompts are long and complex, which means, you need a smart model with longer context who can output proper JSON. I personally use opus, but you may also use deepseek 3.2 or any other smarter model, except 8b models. Thinking models would also do great.

> **Note 2026-10-19:** Model recommendations are anecdotal, not a supported-model list. The Story DM requires raw JSON without analysis or markdown; thinking output outside that JSON can break parsing. Check the model response and your override settings rather than assuming every small model fails or every thinking model works.

**Q: Can I migrate an existing 3.5.2 save to this fork?**

Only eligible saves can use the bounded offline converter; do not simply swap components or assume every old save is supported. See [this fork's migration guidance and next-release player workflow](#this-fork-vs-the-original-intelengine). **Never load a converted save with IntelEngine 3.5.2.**

## This fork vs the original IntelEngine

**Q: What is this fork, and where does it live?**

IntelEngine was originally created by Galanx. This fork carries compatibility and maintenance changes for current SkyrimNet releases in [Gerkinfeltser/IntelEngine-GamePlugin](https://github.com/Gerkinfeltser/IntelEngine-GamePlugin) (game scripts, content and dashboard) and [Gerkinfeltser/IntelEngine-NativePlugin](https://github.com/Gerkinfeltser/IntelEngine-NativePlugin) (native plugin and converter). SkyrimNet Beta 25 or newer is required; VR is not supported by the current build. See the [README](README.md), [changelog](CHANGELOG.md) and [native README](https://github.com/Gerkinfeltser/IntelEngine-NativePlugin/blob/dev/README.md). This is not a claim that Galanx endorses or reviews the fork.

**Q: What changes after Galanx's 3.5.2?**

The following are development changes, not a claim that every released 3.5.2 download already includes them:

- **Rendered name/cache persistence repair:** facts, gossip and task-history caches are encoded for co-save storage and decoded for prompts, preventing those cache values from corrupting later stored values such as NPC names. Fresh-new-game persistence is documented on Skyrim 1.6.1170 and 1.7.104. This cannot recover text already lost in an old save.
- **Papyrus API and array guards:** declarations are aligned with existing native functions, and three array-null guards are corrected without replacing the task system.
- **Story DM candidate resolution:** selected names resolve within the latest Story/social candidate pools instead of falling back to worldwide fuzzy matching. Unknown/ambiguous names reject. This is offline-regression checked; live identity verification remains pending. Overlapping requests are not isolated, and the Courier/Messenger substitution path is unchanged.
- **NPC Social DM CTD fix work:** async game-state snapshotting is queued on the main thread and stale pre-load results are discarded. The native README does **not** claim the reported Skyrim 1.5.97 CTD is cured; reporter confirmation and the stated live verification remain required.
- **Skyrim 1.7.104 and legacy conversion:** native-dev documentation now qualifies a bounded 3.5.2 converted-save lineage on 1.7.104 as well as 1.6.1170. It does not promise arbitrary-save or full-HUD compatibility.

Sources: [Game changelog, Unreleased](CHANGELOG.md#unreleased), [native compatibility and unreleased fixes](https://github.com/Gerkinfeltser/IntelEngine-NativePlugin/blob/dev/README.md#compatibility), and [native offline conversion eligibility and limits](https://github.com/Gerkinfeltser/IntelEngine-NativePlugin/blob/dev/docs/DLL_API.md#offline-legacy-save-conversion). Native dev has newer 1.7.104 migration qualification than the current Game README/changelog's older “not yet verified” text; use the linked native limits for that qualification.

**Q: Can I switch an existing 3.5.2 playthrough to this fork?**

Not by dropping in a replacement DLL alone. The current dev converter supports only independently qualified 3.5.2 writer lineages on **Skyrim 1.6.1170.0 and 1.7.104.0**. Documentation reports one bounded accepted legacy save on each runtime, not general support for every save. On 1.7.104, 11 independently sampled caches, two explicit policy-derived fields and 24 qualified live names passed the documented reload checks; four other name holders remain unverified. Unknown provenance, ambiguous/truncated streams, unsupported identities and unqualified control characters refuse conversion. Already-lost values cannot be restored.

Before migration, close the game and preserve the matching `.ess`/`.skse` pair plus IntelEngine and SkyrimNet backing databases/data. Work on copies outside live save directories. Current dev uses the explicit **inspect/convert** workflow with source-specific evidence and qualification; inspection alone does not grant eligibility. Install the complete repaired DLL, both affected PEX files and all three prompts together, then validate the converted copy separately before adopting it. **Never load a converted save with IntelEngine 3.5.2.** Keep the original pair and its matching old components/backing-data snapshot separate for rollback. If your save cannot qualify, start a fresh new game with the coherent repaired set rather than forcing a conversion.

The simpler **fix / drag-and-drop player procedure is coming in the next release**; it is **not on dev yet** and is not the current dev conversion procedure. <!-- TODO(owner): Confirm next-release delivery timing for the fix / drag-and-drop player workflow before publishing a release. -->

Follow the [native converter procedure and refusal policy](https://github.com/Gerkinfeltser/IntelEngine-NativePlugin/blob/dev/docs/DLL_API.md#offline-legacy-save-conversion), not commands or qualification files copied from someone else's save. After the Beta 25 content migration, review `galanx.intelengine` enablement/priority and retain `SKSE/Plugins/SkyrimNet/config/plugins/IntelEngine/` for settings and factions.

**Q: Where should I report bugs in this fork?**

Use this fork's [GamePlugin issues](https://github.com/Gerkinfeltser/IntelEngine-GamePlugin/issues) for scripts, content or dashboard reports, or [NativePlugin issues](https://github.com/Gerkinfeltser/IntelEngine-NativePlugin/issues) for native/converter reports. Include the fork version/commit, Skyrim/SKSE versions, reproduction steps and relevant logs with personal information removed. Do not assume an upstream issue demonstrates that a fork-specific change is fixed or broken.

**Q: Will these changes go upstream to Galanx?**

This fork is maintained independently; its changes are not submitted upstream. <!-- TODO(owner): Confirm this ongoing maintenance/upstream policy before publication; it is owner policy, not a source-code guarantee. --> Galanx's original authorship is retained, but this FAQ does not imply endorsement, review or support of the fork by Galanx.
