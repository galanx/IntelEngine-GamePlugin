# IntelEngine — FAQ

By Galanx 3/2026

Original answers are preserved below; ~~struck text~~ is superseded by the dated fork-dev update immediately after it, and dated notes qualify unverified claims.

**Q: What is IntelEngine?**

IntelEngine is a Skyrim mod that gives NPCs the ability to act independently in the game world. Instead of standing in one spot waiting for the player, NPCs can travel across the map, carry out tasks, remember what happened, and even pursue their own goals — all driven by AI via SkyrimNet.

**Q: What does it actually do in-game?**

You can give NPCs orders through natural conversation — things like "go find Ysolda and bring her here," "tell the Jarl I'll meet him at the inn at sunset," or "escort Adrianne to Dragonsreach." NPCs physically walk to their destination, ~~no teleporting~~. They calculate travel time, leave early enough to arrive on schedule, and wait naturally when they get there. Missed meetings and late arrivals are tracked and remembered.

> **Updated 2026-10-19 (fork dev, after 3.5.2):** Your NPCs normally walk, but they can teleport through doors or when they get stuck or take too long.

**Q: Do NPCs do things on their own?**

Yes. A built-in Dungeon Master system generates dynamic events throughout your playthrough. NPCs will seek you out over unfinished business, ambush you over old grudges, spread gossip through realistic chains of people, offer you quests like rescues or dungeon clears, and even cross your path by coincidence while traveling on their own errands.

**Q: Is there a political system?**

Nine factions form alliances, negotiate trade deals, spy on each other, declare wars, and fight battles in the background. If you happen to be nearby when a battle kicks off, soldiers spawn and fight it out. Your standing with each faction rises and falls based on your choices and actions.

**Q: Do NPCs remember what happens?**

~~Every completed task, delivered message, failed meeting, and overheard rumor persists in an NPC's memory and shapes how they interact with you going forward. Betray someone and they hold a grudge. Be reliable and they trust you more.~~

> **Updated 2026-10-19 (fork dev, after 3.5.2):** Yes — NPCs remember tasks, messages, meetings and gossip, but some facts fade over time. How they react still depends on the AI.

**Q: My followers keep leaving to do tasks. How do I stop this?**

MCM or Prisma Dashboard → Settings → Skip Action for Followers. Toggle ON for any actions you want blocked ~~(`Go To Location`, `Fetch Person`, `Deliver Message`, `Escort Target`)~~. ~~Followers will still talk, gossip, and interact — they just won't physically leave your side.~~

> **Updated 2026-10-19 (fork dev, after 3.5.2):** MCM or Dashboard -> Settings -> Skip Action for Followers: turn ON each action you want blocked, including Search For Actor and all three scheduling actions. These default OFF; your active followers can still talk to you, but aren't picked for autonomous stories or social events.

**Q: Can I get a confirmation prompt instead of blocking entirely?**

Under Action Confirmation Prompts, set actions to `Followers Only`. You'll get ~~a yes/no popup before any follower departs~~ (this is the default for most actions).

> **Updated 2026-10-19 (fork dev, after 3.5.2):** MCM -> Settings -> Action Confirmation Prompts -> Followers Only lets you choose Allow, Deny or Deny (Silent). Most actions default to Followers Only, Schedule Meeting defaults to Everyone, and any follower-skip toggle blocks the action without asking.

**Q:Nothing is happening. No NPCs are approaching me.**

Check that Story Engine is enabled in MCM → Settings. The default interval is 3 game hours — sleep or wait a bit. Also check that story types aren't all toggled off.

**Q: Events happen too often / not often enough.**

Adjust Check Interval (default 3 hours, range 0.5–168). Lower = more frequent.

**Q: The same NPC keeps getting picked.**

Increase ~~NPC Cooldown~~ (default 24 hours, range 6–72).

> **Updated 2026-10-19 (fork dev, after 3.5.2):** MCM -> Settings -> Story NPC Cooldown (hours): default 24, range 6–72. For NPC-to-NPC activity, adjust NPC Social Cooldown instead.

**Q: I don't want hostile encounters (ambushes, stalkers).**

MCM → Story Types (DM) → toggle OFF `Ambush`, `Stalker`, or `Faction Ambush` individually.

**Q: NPCs from other holds keep showing up.**

MCM → Hold Restrictions → ~~set each story type to `Same Town` or `Same Hold`~~.

> **Updated 2026-10-19 (fork dev, after 3.5.2):** MCM -> Hold Restrictions -> choose Same town (everyone) or Same hold (everyone) for each listed story type you want kept local. The civilian-only and follower-exempt options let some NPCs travel farther.

**Q: Does IntelEngine conflict with SeverActions?**

~~No — they complement each other. We encourage using both. SeverActions features actions like `GiveItem` which pairs perfectly with IntelEngine's `find_item` quest — the NPC physically hands items and rewards to you and vice-versa. They share the same SkyrimNet action system with zero conflicts.~~

> **Updated 2026-10-19 (fork dev, after 3.5.2):** They can conflict if both offer the same travel, fetch, delivery or cancel actions — disable the duplicates in one mod. See the [compatibility guide](README.md#compatibility) before using them together.

**Q: Does it work with follower frameworks (AFT, NFF, etc.)?**

Yes. IntelEngine detects followers via the engine's `IsPlayerTeammate` flag, which all frameworks use. We recommend using SeverActions for managing followers.

> **Note 2026-10-19:** Follower detection depends on your framework marking the NPC as your active teammate; check your setup if the follower controls don't apply.

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

> **Updated 2026-10-19 (fork dev, after 3.5.2):** MCM -> Settings -> Quest Types -> Allow NPC death in rescue is OFF by default. Leave it OFF to protect rescue victims during the quest; other mods and what happens afterward can still put them at risk.

**Q: How long do I have to complete a quest?**

Quest Timeout slider (default 1 day, max 30). After this, unfinished quests auto-expire.

**Q: How do I see faction relations?**

Prisma Dashboard (`Shift+7`) → **Politics** tab. Shows faction grid, active wars, standings, and events.

**Q: Can I trigger political events manually?**

Dashboard → Director tab → ~~Political Director. Pick factions, event type, and dispatch.~~

> **Updated 2026-10-19 (fork dev, after 3.5.2):** Dashboard -> Director -> Political Event: pick both factions and the event type, add a description and a nonzero relation change, then click Dispatch Political Event.

**Q: Can I add custom factions?**

Edit `factions.yaml` in `SKSE/Plugins/SkyrimNet/config/plugins/IntelEngine/`. If missing, copy `factions.sample.yaml` and remove `.sample`. ~~Be sure to remove factions.yaml from MO2 overwrite folder if adding your own.~~ ~~Also make sure the faction EditorId actually exists in Skyrim.~~

> **Updated 2026-10-19 (fork dev, after 3.5.2):** Keep your custom factions — merge any MO2 Overwrite copy instead of deleting it, and check which copy your mod manager uses. Use a real faction EditorID for `skyrim_faction_id`; for example, `ImperialFaction` uses `CWImperialFaction`.

**Q: NPCs gossip and argue too much.**

Increase Interaction Interval (default 1.5 hours). Or toggle OFF `NPC Gossip` / `NPC Interaction` ~~under Story Types~~.

> **Updated 2026-10-19 (fork dev, after 3.5.2):** MCM -> Settings -> NPC Social Life -> raise NPC Interaction Interval (hours), or turn OFF NPC Gossip / NPC Interaction. The dashboard calls it Interaction Interval; default 1.5 hours, range 0.5–168.

**Q: Can I trigger NPC interactions manually?**

Dashboard → Director tab → ~~NPC Social Director~~.

> **Updated 2026-10-19 (fork dev, after 3.5.2):** Dashboard -> Director -> NPC Social: choose two NPCs, pick Interaction or Gossip, and add the narration.

**Q: NPCs take forever to get somewhere.**

Lower Max Travel Time (default 1 day). NPCs exceeding this teleport or give up.

**Q: An NPC is stuck.**

~~Teleport When Stuck~~ is ON by default. Check Active Tasks in MCM to see and manage ~~all tasks~~.

> **Updated 2026-10-19 (fork dev, after 3.5.2):** MCM -> Settings -> Teleport on stuck/timeout is ON by default. Manage player tasks in MCM -> Active Tasks, or inspect and remove stuck AI packages in Dashboard -> Packages.

**Q: Too many NPCs doing tasks at once.**

Lower Max Concurrent Tasks (default 5, min 1).

**Q: What is Auto Dynamic Bio?**

When enabled, NPC bios automatically rewrite after X dialogue lines per NPC — keeping their personality evolving based on conversations. Disabled by default.

**Q: How do I enable it?**

MCM or Dashboard → Auto Dynamic Bio  → toggle ON. Set "Lines Before Update" (default 20, range 5–1000).

**Q: How do I open the dashboard?**

`Shift+7` (default). Change the hotkey in SkyrimNet → Plugin Configurations.

> **Note 2026-10-19:** Hotkey defaults disagree, so set yours in SkyrimNet -> Plugin Configurations -> IntelEngine -> Dashboard Hotkey / Dashboard Modifiers; you'll also need PrismaUI.

**Q: Dashboard too small on 4K?**

Increase UI Scale (recommended 1.5–2.0 for 4K).

**Q: How do I change which AI model IntelEngine uses?**

Dashboard or SkyrimNet Web UI → Plugin Configurations → IntelEngine → LLM Overrides. Leave empty to use the default model.

**Q: NPCs keep wanting to repeatedly travel somewhere on their own**

If it happens consecutively, the llm might be too eager to make them travel if the previous location hasn't been found. You can configure action cooldowns to prevent this behavior in SkyrimNet → Actions Library or if you like, try to change the action description to have stricter rules in SkyrimNet → Custom Actions → GoToLocation (or the action of your choice), or you can disable it entirely.

> **Note 2026-10-19:** For repeated travel orders, check for duplicate actions first; the story and social cooldown sliders are for autonomous events.

**Q: I changed the intel_story_dm model and now stories stopped working**

IntelEngine DM prompts are long and complex, which means, you need a smart model with longer context who can output proper JSON. I personally use opus, but you may also use deepseek 3.2 or any other smarter model, except 8b models. Thinking models would also do great.

> **Note 2026-10-19:** Treat those model suggestions as personal recommendations; check that yours returns only JSON, with no extra thinking text or markdown.

**Q: Can I migrate an existing 3.5.2 save to this fork?**

If you are continuing a 3.5.2 playthrough, use the release's save converter before loading it with this fork. See [this fork's migration instructions](#this-fork-vs-the-original-intelengine). **Never load a converted save with IntelEngine 3.5.2.**

## This fork vs the original IntelEngine

**Q: What is this fork, and where does it live?**

It's an independently maintained version of Galanx's IntelEngine, with fixes for newer SkyrimNet releases. You'll find it at [Gerkinfeltser/IntelEngine-GamePlugin](https://github.com/Gerkinfeltser/IntelEngine-GamePlugin) and [Gerkinfeltser/IntelEngine-NativePlugin](https://github.com/Gerkinfeltser/IntelEngine-NativePlugin); you'll need SkyrimNet Beta 25 or newer, and VR isn't supported. Galanx created the original mod — please don't treat this fork as endorsed or reviewed by him.

**Q: What changes after Galanx's 3.5.2?**

This release adds the following changes after 3.5.2:

- **NPC names and memories:** fixes how memories are saved so they don't corrupt stored NPC names.
- **Script fixes:** corrects script checks and keeps the scripts talking properly to the native plugin.
- **Story NPC selection:** matches story NPCs against the current candidates instead of searching the whole world.
- **NPC social crash fixes:** makes background NPC activity safer around loading saves, though the reported 1.5.97 crash still needs confirmation.
- **Save converter:** lets you bring eligible 3.5.2 saves forward on Skyrim 1.6.1170 and 1.7.104.

See the [Game changelog](CHANGELOG.md#unreleased) and [native compatibility notes](https://github.com/Gerkinfeltser/IntelEngine-NativePlugin/blob/dev/README.md#compatibility) for details.

**Q: Can I switch an existing 3.5.2 playthrough to this fork?**

Yes — if you're continuing a 3.5.2 playthrough, run the included converter first so your old names carry over correctly. Starting a fresh game? You can skip this.

1. Close Skyrim.
2. Back up your save's matching `.ess` and `.skse` files and keep them together in the same folder; back up IntelEngine and SkyrimNet's extra data too if you might roll back.
3. Keep `LegacyCacheMigration.exe` beside `Convert-IE-Save.bat`, then drag your `.ess` onto `Convert-IE-Save.bat` — leave its matching `.skse` beside the save.
4. Once conversion succeeds, install this release's full package and load the new `_IEconverted` save, keeping its matching `_IEconverted.skse` alongside it.

This works on **Skyrim 1.6.1170 and 1.7.104 only**. It refuses saves it can't qualify and can't recover already-lost names; skipping it means old names may show up wrong. Your originals stay untouched — don't load an incomplete converted pair or mix old and converted files. **Never load a converted save with IntelEngine 3.5.2.**

Advanced users can read the [native offline-conversion documentation](https://github.com/Gerkinfeltser/IntelEngine-NativePlugin/blob/dev/docs/DLL_API.md#offline-legacy-save-conversion).

**Q: Where should I report bugs in this fork?**

Found a bug? Report it in this fork's [GamePlugin issues](https://github.com/Gerkinfeltser/IntelEngine-GamePlugin/issues) for scripts or dashboard problems, or [NativePlugin issues](https://github.com/Gerkinfeltser/IntelEngine-NativePlugin/issues) for crashes or conversion problems. Include your fork and Skyrim/SKSE versions, what you did, and relevant logs with personal information removed.

**Q: Will these changes go upstream to Galanx?**

This fork is currently maintained independently; its changes are not submitted upstream.
