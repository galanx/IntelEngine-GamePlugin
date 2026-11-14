# IntelEngine
### NPC Autonomy, Faction Politics & Player-Driven Task Framework for SkyrimNet

> [!IMPORTANT]
> **Compatibility:** IntelEngine 3.8.0 updates the DLL and scripts and requires SkyrimNet Beta 27 or newer (its travel prompt uses the `get_place_names` decorator added in Beta 27). The 3.6.0 runtime components were tested with official Beta 28. Beta 26 and earlier are incompatible.
>
> This repository carries a compatibility update for current SkyrimNet releases. IntelEngine was originally created by [Galanx](https://github.com/galanx).
> **Have issues? Report them here:** [IntelEngine GamePlugin issues](https://github.com/galanx/IntelEngine-GamePlugin/issues). Include your Skyrim, SKSE, SkyrimNet and IntelEngine versions and relevant logs with personal information removed.

Read the [player FAQ](FAQ.md) for Galanx's original answers, dated 3.6.0 updates, and migration guidance.

*"Meet me at the Western Watchtower at sunset."*
*She agrees. Hours pass. The sun dips. You arrive — and she's already there.*

---

IntelEngine has two parts that work together to make Skyrim's NPCs feel alive.

**Part 1 — Player-Driven Actions:** You tell NPCs what to do through natural conversation and they follow through physically across the entire game world. Scheduling is the core — meetings, fetches, and deliveries all support future time expressions.

**Part 2 — Dungeon Master (AI-Driven Stories):** An LLM Dungeon Master observes the world state and decides when NPCs should act on their own — seeking you out, ambushing you, spreading gossip, delivering messages, offering quests, and interacting with each other.

---

## The Day Everything Changed

You step out of Breezehome at dawn with more to do than one Dragonborn can handle.

Farengar needs to warn the Jarl. You turn to him: *"Tell Jarl Balgruuf there's been a dragon sighting near the Western Watchtower. Tell him to meet me at the Bannered Mare tonight."* He nods and departs — **delivering your message** on foot through the keep. Balgruuf will hear it, remember who sent it, and the meeting request **schedules him to travel** to the inn that evening.

You need backup at the watchtower, so you find Jenassa at the Drunken Huntsman. *"Meet me at the Western Watchtower at sunset."* She agrees. The **meeting is scheduled**. She doesn't leave now — she knows when to depart, calculates the distance, and **leaves early enough to arrive on time**. You go about your day.

Before heading out, you need Adrianne. *"Lydia, go get Adrianne. The blacksmith. Bring her here."* Lydia walks to Warmaiden's, finds Adrianne at the forge, and **escorts her back** on foot. Adrianne **lingers nearby** — leaning on a post, sitting on a bench — until you've spoken and walk away. She drifts back to the forge on her own.

You tell Lydia to **go to the Bannered Mare** and wait. She descends the steps, crosses the market, pushes through the inn door, and settles into a seat by the fire. But you change your mind halfway — *"Actually, stop. Come back."* She **cancels the task** and turns around. *"Forget that. **Run** to the stables instead."* She takes off at full sprint.

Hours later, the sun touches the mountains. You reach the Western Watchtower. Jenassa is already there — sitting by the wall, calm. She arrived early. **The meeting is live.** You discuss the plan, scout the area, and when you're done, you walk away. **The meeting ends naturally** — no timer, no script, just proximity. She heads off on her own.

That evening, you push through the door of the Bannered Mare. Balgruuf is there — the message reached him, and he **kept his scheduled appointment**. He remembers the dragon warning. He knows Farengar carried it.

But something else happened while you were at the watchtower. **On the road back**, you crossed paths with Adrianne — she was heading to Falkreath to sell swords, minding her own business. You stopped and chatted. She had no idea you'd be there. Neither did you. The **Dungeon Master** placed that encounter because it fit the moment.

And later that night, sitting in the inn, **a warrior you'd wronged three days ago tracked you down**. He snuck through the door, drew his blade, and attacked. You beat him — he yielded, dropped to his knees, and begged for mercy. He told you someone sent him. Someone you thought was a friend. That fact is now in his bio. And in yours.

Tomorrow, things get more complex. You tell a guard: *"Go get Ysolda after sunrise."* The **fetch is scheduled** for morning — the guard stays at his post until dawn, then departs. Meanwhile, **two NPCs at the market start arguing** about something that happened yesterday — the Dungeon Master decided it was time. You overhear it. Both of them remember it differently.

Five NPCs are acting simultaneously. Ten more tasks are queued for the future. Stories are unfolding that you didn't start. The world doesn't wait for you to do everything yourself.

This is **IntelEngine**.

---

## What This Mod Does

IntelEngine is an NPC autonomy framework for [SkyrimNet](https://github.com/MinLL/SkyrimNet-GamePlugin). Where SkyrimNet gives NPCs the ability to think and speak through AI, IntelEngine gives them the ability to **act** — physically, across the game world, on their own two feet. Both on your command and on their own initiative.

### Part 1 — Player-Driven Actions

Through natural conversation, any NPC can:

- **Schedule meetings, fetches, and deliveries** for any future time — *"at sunset"*, *"tomorrow morning"*, *"in three hours"*
- **Travel** to named locations, relative directions, or anywhere the game world has a door
- **Fetch** people and escort them back to you on foot
- **Deliver messages** to anyone — with optional meeting requests that schedule the recipient to travel
- **Search** for someone alongside you, traveling together

### Part 2 — Dungeon Master (AI-Driven Stories)

Without any player input, NPCs autonomously:

- **Seek you out** over unfinished business, old friendships, or something they overheard
- **Share gossip** traced to real events, spreading through chains of up to 10 people
- **Ambush you** for real grudges — with stealth approach, combat, and a yield system
- **Secretly follow you** out of obsession until caught
- **Deliver messages** from NPCs who can't come themselves
- **Offer quests** — bounty hunts, rescue missions, item retrieval, and **faction war battles**
- **Interact with each other** independently — arguments, deals, whispered conspiracies

### Part 3 — Faction Politics

A living political system where 9 factions (configurable) scheme, trade, and wage war:

- **Political DM** generates events every 6 game hours — trade deals, espionage, border skirmishes, assassinations, war declarations, and surrenders
- **Player standing** with each faction rises and falls based on your actions — fight for a faction, betray them, commit crimes in their territory
- **Faction wars** with morale, army strength, off-screen battles, and **player-present battles** with 5 waves of spawned soldiers (22 per side)
- **Faction quests** — when your standing is 40+ with a faction, they call on you for combat missions, rescue operations, and full-scale battles that affect war outcomes (battles you happen upon: you join automatically at standing 20+)
- **Political awareness** — NPCs know about recent political events and react to them in conversation
- **In-game dashboard** (Magelight UI recommended, PrismaUI fallback) with a Politics tab showing all faction relations, active wars, and player standings

**One political timeline per playthrough:** `IntelEngine-<id>.db` is one database shared by all saves in that playthrough, not a separate database per save. Loading an earlier save permanently removes later political events, wars, battles and standing history, and re-opens wars that ended after that save (`CleanupFutureEvents`). To keep a later timeline, back up the database and its `-wal`/`-shm` companions with the game closed before loading an earlier save; the `.ess`/`.skse` pair alone does not preserve it.

**Political Engine bridge (3.8.0, optional, off by default):** switch on "Political Engine integration" in the MCM (Faction politics), on the dashboard's Settings tab or on SkyrimNet's plugin settings page (`politics.pe_integration` in `settings.yaml`). With it on, Political Engine API v3 supplies public campaign news and current-owner district sides to the Political DM. Initial attachment and loads do not replay news. “PE reactions move relations” in MCM/dashboard defaults on; off still records tagged reactions without their relation/player-standing deltas. IE's own politics, decay and battles remain independent. Existing user `settings.yaml` is preserved; the new key is `politics.pe_reactions_move_relations`.

No teleportation. No console commands. No hardcoded location lists. IntelEngine dynamically indexes every actor and location across every cell in the game — every inn, every home, every NPC is discoverable because the index is built from your actual load order.

---

## Scheduling — The Core Feature

The ability to coordinate NPCs across time is what sets IntelEngine apart. You don't just dispatch NPCs on errands right now — you plan ahead, and the world follows through.

### Schedule Meeting

> *"Meet me at the Bannered Mare at sunset."*
> *"See you at Dragonsreach tomorrow morning."*
> *"Let's meet at the Western Watchtower in three hours."*

NPCs understand natural time expressions:

| Expression | Resolves To |
|---|---|
| dawn, sunrise | 5-6 AM |
| morning | 8 AM |
| noon, midday | 12 PM |
| afternoon | 2 PM |
| evening | 6 PM |
| sunset, dusk | 7-8 PM |
| night | 10 PM |
| midnight | 12 AM |
| "in 2 hours", "in half an hour" | Relative to current time |
| "tonight" | This evening |
| "tomorrow" | Tomorrow morning |

**Early departure** — NPCs calculate travel time based on distance and depart early enough to arrive before the scheduled hour. A meeting at the Western Watchtower means leaving Whiterun well before sunset — the system estimates the walk and builds in a buffer.

**Natural arrival** — The NPC waits at the meeting point, idling naturally — sitting, leaning, looking around. When you arrive, the meeting is live. Walk away, and it ends. No "press E to end meeting." Just proximity, and a visit clock in the background: a visit that goes on for six game hours ends by itself.

**No-shows are remembered.** If you never arrive, the NPC waits until their patience runs out (configurable, default 5 game hours), then leaves. They remember you didn't show — and it colors future interactions differently than a meeting that went well.

**Lateness is tracked.** The NPC knows if they arrived late (pathfinding trouble, long distance). You know if the player was late. The meeting outcome — success, late arrival, or no-show — persists in the NPC's memory.

### Schedule Fetch

> *"Go get Ysolda after sunset."*
> *"Bring me Nazeem tomorrow morning."*

The NPC stays where they are now. When the departure window arrives, they travel to the target, escort them back to you on foot, and the fetched person lingers nearby until you walk away, or until the visit has run its time (about two game hours, never in the middle of a conversation).

### Schedule Delivery

> *"Tell Adrianne after sunset that the shipment is ready."*
> *"Send word to Jarl Balgruuf tomorrow morning."*

A message delivered at the right time. If the message includes a meeting request — *"tell him to meet me at Dragonsreach tonight"* — the recipient is also scheduled to travel there.

**Up to 10 tasks** can be scheduled simultaneously across all NPCs.

---

## Immediate Tasks

### Go To Location

> *"Go to the Bannered Mare."*
> *"Head upstairs."*
> *"Wait outside."*
> *"Leave."*

Send any NPC to a destination right now. The location resolver understands:

- **Named places** — Whiterun, Dragonsreach, Bannered Mare, the Drunken Huntsman
- **Relative directions** — upstairs, downstairs, outside, inside, the back room
- **Fuzzy matching** — typos and partial names still resolve (*"Bannred Mare"* finds the Bannered Mare)
- **Contextual resolution** — *"go upstairs"* scans doors by Z-axis, *"go outside"* identifies exterior doors

Three travel speeds — **walk**, **jog**, or **run** — chosen based on urgency. New tasks automatically replace the current one — you don't need to cancel before redirecting, just speak and the NPC adapts.

### Fetch Person

> *"Go get Adrianne and bring her here."*
> *"Fetch Nazeem."*

The NPC walks to the target — **anywhere in Skyrim** — has a brief exchange, and escorts them back on foot. Ask someone in Whiterun to fetch an NPC living in Riverwood, and they'll walk the road, find them, and walk back together. The target doesn't need to be nearby, loaded, or even in the same hold. IntelEngine's C++ NPC index locates actors across the entire game world, including unloaded cells.

When they arrive, the fetched person **lingers naturally** — sitting on furniture, leaning against walls, idling in place. They behave like someone who was asked to come over, not a mannequin planted in front of you. They stay as long as you're nearby, for about two game hours (longer while you are talking, six at the most). Walk away, and they return to their routine.

NPC names are matched with **typo tolerance** — Levenshtein distance matching means *"Adiranne"* still finds Adrianne. Failed searches return suggestions.

### Deliver Message

> *"Tell Jarl Balgruuf about the dragon sighting."*
> *"Warn Adrianne that trouble is coming."*
> *"Go tell Alvor to meet me at the Bannered Mare in two hours."*

The NPC carries your words to the recipient face-to-face — **across any distance**. Send a messenger from Solitude to Riften, and they'll make the journey. The recipient **remembers** what was said, who sent it, and who carried it — information that persists in their character context for future conversations.

If the message includes a meeting request, the recipient is automatically **scheduled to travel** there at the specified time. One command chains a delivery into a meeting.

Messengers optionally **report back** to you after delivery (configurable via MCM).

### Search For Actor

> *"Take me to Ysolda."*
> *"Help me find Nazeem."*

Unlike Fetch — where the NPC goes alone — Search means you travel **together**. The NPC leads, you follow. If you fall behind, they **pause and wait** for you to catch up before continuing.

---

## Mid-Task Control

### Change Speed

> *"Hurry up." / "Run!" / "Pick up the pace."*
> *"Slow down." / "Walk." / "No rush."*

Adjust an NPC's travel pace on the fly — walk, jog, or run — without interrupting their current task.

### Cancel Task

> *"Stop." / "Wait." / "Hold on." / "Come back."*

Immediately halts the NPC's current active task. Scheduled tasks are unaffected — those still fire at their appointed time.

---

## Navigation Intelligence

### Dynamic World Indexing

IntelEngine does not use static location lists or hardcoded cell names. On game load, the native C++ SKSE plugin **dynamically indexes every actor and every location** across all loaded cells in your game — including mod-added content. Every inn, home, dungeon, shop, and NPC is discoverable because the index is built from your actual load order at runtime. If a mod adds a new tavern to Whiterun, IntelEngine can dispatch NPCs there.

### Cross-Cell Travel

**Every task in IntelEngine works across the entire game world.** Send an NPC from Riverwood to Riften. Schedule a meeting in Solitude while you're standing in Windhelm. Dispatch a messenger from Whiterun to deliver words to someone in Markarth. NPCs navigate using Skyrim's native AI pathfinding — they walk through doors, cross cell boundaries, traverse the open world between holds, and arrive at their destination on foot. The game engine handles the routing. IntelEngine provides the destination and the intent. There is no range limit.

### Semantic Location Resolution

The destination resolver processes spatial language beyond named locations:

| You say | What happens |
|---|---|
| "Go upstairs" | Scans doors by Z-axis, finds upper floors |
| "Go outside" | Identifies exterior doors in current cell |
| "Go to the back room" | Resolves interior spaces behind the main area |
| "Leave" | Finds the nearest exit |
| "Go to the inn" | Fuzzy-matches against dynamically indexed locations |

> **Note:** Upstairs/downstairs resolution relies on door Z-axis positions, which Skyrim's cell design doesn't always make reliable — some interiors place doors at unexpected heights or use single-level layouts with misleading geometry. Named locations and exterior/interior directions are consistently accurate.

### Stuck Recovery

Skyrim's pathfinding sometimes fails — doors won't open, navmesh gaps block the path, or geometry traps an NPC. IntelEngine monitors positions continuously through native C++ polling and responds with escalating recovery:

1. **Soft recovery** — re-evaluates AI packages, giving the engine another chance
2. **Progressive teleport** — nudges the NPC incrementally toward their destination, with decreasing distances on each attempt
3. **Safety timeout** — force-completes the task after extended time to prevent permanent soft-locks in unloaded cells

**Locked doors** are a common edge case — an NPC dispatched to fetch someone at night may find their target behind a locked home door. When the NPC can't reach the target and gets stuck at the entrance, the stuck detection system catches the stall, escalates through recovery, and if all else fails, narrates the failure so the NPC doesn't silently hang forever.

### Departure Verification

When an NPC is supposed to leave a location, IntelEngine verifies they actually moved from their starting position. If they're immobilized — locked door, blocked path, obstructed AI — recovery escalates before the task is abandoned.

---

## NPC Memory — Awareness Prompts

IntelEngine injects eight **SkyrimNet bio submodules** into every NPC's character bio. These render live game state as natural-language context the AI sees on every dialogue cycle. NPCs don't just execute tasks — they **know** what they've done, what they're doing, and what they've committed to.

### Task Awareness
NPCs know their current task — *"traveling to Dragonsreach"*, *"delivering a message to Nazeem"*, *"returning with Adrianne"* — and maintain a timestamped history of completed tasks. *"I fetched Ysolda earlier today. Delivered a message to the Jarl yesterday."*

### Schedule Awareness
NPCs know their commitments — *"I'm meeting someone at the Bannered Mare this evening"* — and how long until departure. Active meetings, pending schedules, and en-route status are all visible to the NPC's AI.

### Meeting Outcomes
NPCs remember how meetings went. Did the player show up on time? Late? Not at all? Was the NPC themselves delayed? These outcomes persist — a no-show is a different memory than a successful rendezvous, and NPCs can reference either in future conversations.

### Received Messages
When a message is delivered, the recipient retains who sent it, who carried it, what it said, and when it arrived. This information stays in their character context so they can react naturally — *"Farengar told me about the dragon sighting. That was your warning?"*

### Known Facts
Everything the NPC learned through story events — gossip heard, ambush outcomes, stalker catches, quest results. Displayed with natural time references: *"just now"*, *"earlier today"*, *"a few days ago."* Facts expire over time, so recent events feel vivid while old news fades.

### Gossip Network
Both rumors the NPC has heard (and from whom) and rumors they've shared (and to whom). Creates a visible web of social information — *"Ysolda told me that Nazeem was seen lurking near the warehouse."*

### Political Awareness
NPCs know the recent political events, wars and faction standings that concern their own faction (or the territory they are in). Leaders and members see their faction's events; public events reach everyone; secret ones only reach the factions involved. Faction members also know how their faction views you.

### Arrival Purpose
When an NPC has travelled to find you, they remember why they came, so their first words are about that errand.

---

## Concurrency & Persistence

- **5 simultaneous active tasks** — five NPCs traveling, fetching, or delivering at the same time, each tracked independently
- **10 scheduled tasks** — queued for future execution across all NPCs
- **Save/load safe** — active and scheduled tasks survive saving and reloading; AI packages are reconstructed on game load
- **Independent recovery** — each task slot has its own stuck detection, departure verification, and deadline tracking
- **Follower-aware** — follower NPCs are temporarily released for task execution and restored to your service when they return

---

## MCM Configuration

Four pages in the SkyUI Mod Configuration Menu:

### Active Tasks
Real-time view of all 5 task slots — what each NPC is doing, where, and current status. Clear individual tasks or reset everything.

### Scheduled Tasks
View all pending scheduled tasks with times and targets. Cancel individually or clear all.

### Settings

Every setting has one name: the MCM, the dashboard's Settings tab and SkyrimNet's plugin settings page call it the same. Two things differ by place. On the dashboard a unit stands beside the value instead of in brackets ("Check interval", 3 game hours). Under a heading that says what its switches are, they carry the rest of the name: "Story type: an ambush" on SkyrimNet's page is "An ambush" under "Story types".

| Setting | Default | Range | Description |
|---|---|---|---|
| Debug messages | Off | On/Off | Shows what IntelEngine does as notices on screen (the Papyrus log has it either way). |
| NPCs on a task at once | 5 | 1-5 | How many NPCs can be active at once |
| Wait at a destination (game hours) | 48 | 6-168 | How long an NPC you sent somewhere waits there for you |
| Visit ends when you walk away (units) | 800 | 300-2000 | How far you walk before an NPC who stayed with you after a task goes back to their own day |
| Ask before starting | Followers only (Arrange a meeting: Everyone) | Disabled / Followers only / Everyone | Set per action. With Magelight the prompt is a Magelight popup. It closes after 20 seconds, and no answer counts as a silent deny. Director actions never prompt |
| What followers can be asked to do | All on | On/Off per action | Off: that action is refused for your active followers, without a prompt |
| Report back after a delivery | On | On/Off | Messengers narrate delivery completion |
| Wait for you at a meeting (game hours) | 5 | 1-12 | How long NPCs wait at meeting spots |
| On time until (game hours late) | 0.5 | 0-2 | Arriving within this time after the agreed hour still counts as on time |

The two per-action groups list the actions in plain words: Go somewhere (GoToLocation), Deliver a message (DeliverMessage), Fetch someone (FetchPerson), Escort someone (EscortTarget), Search for someone (SearchForActor), Arrange a meeting (ScheduleMeeting), Fetch someone later (ScheduleFetch), Deliver a message later (ScheduleDelivery).

### Hold Restrictions
How far each kind of story may reach for its NPC ("Stories: how far NPCs travel" on SkyrimNet's page): No restriction, Same hold (civilians / except followers / everyone), or Same town (civilians / except followers / everyone). The defaults differ by kind: Someone comes to see you, An ambush and Someone follows you unseen: same hold (civilians); Someone brings a rumor: same town (everyone); A message is delivered: same hold (except followers); A meeting on the road and Someone has work for you: no restriction.

### Story Tuning

| Setting | Default | Description |
|---|---|---|
| Stories | On | The Story Engine itself: the Dungeon Master |
| Check interval (game hours) | 3 | How often the Dungeon Master evaluates the world (0.5–168) |
| Long absence (days) | 3 | After this many days without meeting you an NPC becomes a candidate; one who has just come to you is left alone for at least as long (1–14) |
| Longest journey (days) | 1 | How long a story NPC stays on the road before being brought to the end of the journey (0.25–3) |
| Move a stuck traveller along | On | A story NPC who cannot get on is placed further along, out of your sight; off, they give up |
| NPCs sent into dangerous places | Block civilians only | Who can be dispatched to dangerous areas (Allow all NPCs / Block civilians only / Allow followers only / Block all NPCs) |
| NPCs sent into your home | Allow all NPCs | Who can visit when you're at home (the same four) |
| Quest kinds | All on | One switch each: Clear out enemies, Rescue someone, Find an item, Fight a faction's enemies, Rescue for a faction, Join a faction's battle |
| Quest expires after (days) | 1 | A quest you were offered and did not finish ends after this many days (1–30) |
| NPCs visit and talk to each other | On | What NPCs do among themselves, with its two kinds (one NPC goes to see another, gossip passed on), a check interval (1.5 game hours) and a rest per NPC (24 game hours) |

### Story types

One switch per kind of story. The switch carries a name in plain words; the Director tab, the notices and the log use the type's short name.

| Switch | Type |
|---|---|
| Someone comes to see you | Seek Player |
| Someone brings a rumor | Informant |
| A meeting on the road | Road Encounter |
| A message is delivered | Message |
| Someone has work for you | Quest |
| An ambush | Ambush |
| A faction's patrol hunts you | Faction Ambush |
| Someone follows you unseen | Stalker |

---

## In-Game Dashboard

IntelEngine provides an optional real-time React dashboard via [Magelight UI](https://github.com/Severause/MagelightUI) **1.7.1 or newer** (recommended), with [PrismaUI](https://www.prismaui.dev/) as a frozen fallback. Install a host separately; neither runtime is bundled. With neither usable host, the dashboard is unavailable but IE gameplay and the MCM remain enabled.

Open with the configured hotkey (default: Shift+7). Skyrim must have foreground focus and exactly the configured Ctrl/Shift/Alt modifiers; release a held combo after returning focus. Another host's input ownership blocks opening without stealing focus or showing a notice. Magelight preserves the dashboard's game pause and supports Escape close; PrismaUI retains its existing X/hotkey close behavior without new Escape support.

Host selection is fixed until restart. In `Data/SKSE/Plugins/SkyrimNet/config/plugins/IntelEngine/settings.yaml`, set `ui.host` to `auto` (default, prefer Magelight), `magelight` (prefer Magelight), or `prismaui` (prefer PrismaUI). Each preference falls back to the other usable host; unknown values warn and use auto. Restart Skyrim after changing this setting; Reload UI does not switch hosts. A missing, too-old or unusable Magelight host logs the reason for PrismaUI fallback.

Change the dashboard hotkey in the dashboard's Settings tab or on the SkyrimNet settings page (click Save); both apply immediately. The MCM has no hotkey option.

### Tabs

**Tasks** — Live view of all active and scheduled tasks. Cancel individual tasks, see agent names, destinations, task types, speeds, and scheduled meeting timing ("in ~3h", "very soon", "overdue"). An IE packages section lists NPCs running IntelEngine AI packages (travel, sandbox, stalk) without a task slot; remove packages from stuck NPCs directly.

**Story** — Toggle the Story Engine and individual story types on/off. See the active dispatch, next DM check-in timer, NPC social activity, active quests, and a log of recent NPC-to-NPC interactions.

**Politics** — Active wars, faction relations, your standing with each faction, the factions themselves and a log of recent political events.

**Director** — Manual Dungeon Master controls. Dispatch any story type to any NPC with full parameter fields (informant gossip, quest locations, message content, etc.). Execute any of the 11 player-driven actions directly on loaded NPCs with guided field hints and required-field validation. **Generate** fills a form from nearby NPCs and factions; it is experimental, and small models (e.g. 4B) fill fields unreliably, so review drafts before dispatch.

**Actions** — Turn each IntelEngine AI action (and other mods' actions) on or off for the AI. Director Action Execution is not affected.

**Settings** — Full parity with the MCM. Every setting has a description hint. Includes plugin configuration (blocklists, LLM overrides, dashboard hotkey) read from `settings.yaml`.

### How It Works

The dashboard communicates through a shared C++ host bridge and existing Papyrus ModEvents. All JSON is built with `nlohmann::json` for proper escaping. Papyrus reads live quest properties and pushes comprehensive JSON snapshots. Remove Packages and Execute Action retain exact decimal-string actor FormIDs, including high-bit IDs.

Accepted Director submissions show an on-screen notice; rejected ones show the reason and keep the form open. The dashboard does not close on submission.

---

## Architecture

IntelEngine operates as two tightly integrated layers, with a third connecting it to SkyrimNet's AI:

**SKSE Native Plugin (C++)** — high-performance backend that runs outside Papyrus:
- **Dynamic world indexing** — scans all cells and actors on game load, building searchable indexes from your actual load order rather than static lists
- **Location resolution** — unified resolver handling named locations, semantic terms, fuzzy matching, and spatial analysis (door scanning, Z-axis direction, furniture detection)
- **NPC search** — name matching with Levenshtein distance tolerance, partial matching, and suggestion fallback
- **Time parsing** — natural language to game-hour conversion for scheduling
- **Stuck & departure detection** — native position polling at engine speed, independent per task slot
- **Cell analysis** — door enumeration, exterior/interior classification, directional scanning
- **Dashboard bridge** — shared C++ host bridge for Magelight UI (preferred) and PrismaUI with thread-safe C++/Papyrus event routing and JSON state serialization

**Papyrus Scripts** — game engine integration:
- AI package management (travel, sandbox, and escort packages at three speed tiers)
- Slot-based task state machine with dual persistence (runtime arrays + StorageUtil)
- Schedule monitoring with distance-based early departure calculation
- Save/load recovery with full package and linked-ref reconstruction
- MCM management interface

**SkyrimNet External Bundle** — IntelEngine's 11 AI-selectable actions, three category containers, five custom LLM prompts, and eight character-bio submodules ship under `SKSE/Plugins/SkyrimNet/external/galanx.intelengine/`. Action identities and Papyrus entry points remain unchanged.

**SkyrimNet Plugin Configuration** — IntelEngine's LLM variant, settings schema, generated `settings.yaml`, and user-editable `factions.yaml` remain under `SKSE/Plugins/SkyrimNet/config/plugins/IntelEngine/`. This configuration path is separate from the Beta 25 external content bundle.

**Extra faction files (`factions.d/`)** — besides `factions.yaml`, IntelEngine loads every `factions.d/*.yaml` next to it (`SKSE/Plugins/SkyrimNet/config/plugins/IntelEngine/`), in filename order. A faction whose `id` already exists is replaced whole; a new `id` is added. A relation for the same pair replaces the earlier one. A broken file is skipped with a log warning. If a file's first line is `requires: political_engine`, it loads only when Political Engine is installed and its integration setting is on (it is off by default); IntelEngine ships `political_engine.yaml` this way. Edits are whole-faction only: copy the full faction into your file to change it, because single fields cannot be overridden. A faction may set an optional `pe_side: 0-3` (Political Engine side: 0 Independent, 1 Empire, 2 Stormcloaks, 3 Aldmeri Dominion); without it the Imperial, Stormcloak and Thalmor engine factions map to 1, 2 and 3.

```yaml
# factions.d/zz_my_changes.yaml  (files load in name order: this one has to come after political_engine.yaml to change PE_Whiterun)
factions:
  - id: "PE_Whiterun"
    name: "Whiterun (mine)"
    type: "political"
    hold: "Whiterun"
    leader_names: ["Balgruuf the Greater"]
```

---

## Story Engine — The Dungeon Master

The Story Engine is Part 2 of IntelEngine. Every few in-game hours, an LLM Dungeon Master observes the full world state — your location, time of day, NPC memories and relationships — and decides if something should happen. World facts shared by every candidate are shown once, while each NPC's additional knowledge remains attached to them for silent fact-checking. No random dice rolls. Every event is grounded in the actual history of your playthrough.

Ten story types, each individually toggleable via MCM:

- **Seek Player** — NPCs travel to find you because of unfinished business, old friendships, or something they overheard. Forgotten friends don't stay forgotten — NPCs you haven't seen in a while are more likely to come looking.
- **Informant** — NPCs approach with real gossip traced to actual game events. The chain of who told whom is tracked.
- **Road Encounter** — You cross paths with NPCs traveling on their own business. Exterior only. They have their own destination.
- **Ambush** — Hostile NPCs with real grudges stalk and attack you. Stealth or charge variants. Beat them and they yield — talk, kill, or walk away.
- **Faction Ambush** — A faction that is hostile to you (standing -40 or lower) sends a patrol of 3–7 soldiers to waylay you on the road. Exterior only.
- **Stalker** — Romantically obsessed NPCs secretly follow you until caught. No combat — the emotional confrontation is the payoff.
- **Message** — Couriers deliver verbal messages from NPCs who can't come themselves, with optional meeting invitations that schedule the sender.
- **Quest: Combat** — NPCs ask you to clear enemies from a location. Guide option (they jog with you) or go alone with a map marker. Bandits, draugr, or dragons.
- **Quest: Rescue** — NPCs plead for help rescuing someone who's been taken. The victim is pre-placed deep inside the dungeon before you enter — restrained in prisoner furniture when available, or found injured in the boss room. The compass guides you through the dungeon to them.
- **Quest: Find Item** — NPCs send you to retrieve a specific item from a dungeon. A quest chest is placed at the boss room with a guardian enemy. The compass points directly at the chest.
- **NPC Interaction** — Two NPCs interact independently of you. Arguments, deals, training, whispered conspiracies. Happens whether you're watching or not.
- **NPC Gossip** — Rumors spread through chains of up to 10 people. Information travels realistically through the world.

**Background events in SkyrimNet History — implemented, pending live acceptance:** persistent `intel_social` and `intel_story` schemas categorize executed NPC interactions, gossip exchanges and story/seek/informant outcomes. Matching generic memories are replaced rather than duplicated; travel proposals, rejections and cooldown blocks do not emit these types. SkyrimNet's existing automatic-audience distance/configuration filters still apply, so off-screen registration does not guarantee History retention. Politics remains in IntelEngine's Politics tab: SkyrimNet currently has no History-only sink excluded from NPC prompts/memory.

Every event injects facts into NPC bios that persist and influence all future dialogue. Message and quest courier facts/memories are recorded only after arrival passes the travel rejection checks; rejected pending quests do not publish quest facts or repetition history. The Dungeon Master prompt lists only enabled story types and guards long-absence seek-player guidance accordingly. Anti-repetition, type balancing, and per-NPC cooldowns keep stories varied and meaningful.

---

## Planned Features

IntelEngine is under active development. The following features are planned for future releases:

- **Eliminate Target** — dispatch an NPC to kill a specific person. Assassinations, bounty hunting, or settling grudges — carried out autonomously across the world.
- **Lockpick Door** — send an NPC to pick a locked door, gaining access to restricted areas without doing the dirty work yourself.
- **Steal Item** — task an NPC with stealing something from someone's inventory or home. Risk and reward — their skill determines success.
- **Timeline-rewind notification — backlog, not implemented:** when loading an earlier save removes later political history (`CleanupFutureEvents` > 0), show a top-left `RE::DebugNotification` hint with the count, deferred until the load completes. Separate native feature, not part of the migration release.

---

## Compatibility

> **Warning: Overlapping SkyrimNet actions from other mods will cause conflicts.**
>
> SkyrimNet presents ALL registered actions to its AI when choosing what an NPC should do. If another mod provides its own travel, fetch, or cancel actions, the AI will see **duplicate options** — for example, two different "go to location" actions. It may pick IntelEngine's travel but the other mod's cancel, which won't work because each mod's cancel only affects its own tasks.
>
> **If you use another SkyrimNet mod that provides similar actions** (travel, fetch, deliver, cancel, etc.), you must **disable the overlapping actions** in either IntelEngine or the other mod. Each action YAML has an `enabled: true/false` flag — set conflicting actions to `enabled: false` in whichever mod you want to defer.

> **SkyrimNet Beta 25 / IntelEngine 3.5.1 migration:** IntelEngine content now loads from external plugin id `galanx.intelengine`. After upgrading, review its enablement and priority in SkyrimNet. Existing action names are unchanged, so per-action settings retain their keys, but should still be reviewed after the content-layer migration. Do not move or delete `config/plugins/IntelEngine`; it continues to own IntelEngine settings and faction configuration.

> **3.6.0 rendered-cache repair:** new rendered caches use delimiter-safe encoding. Fresh-new-game repair was verified on Skyrim 1.6.1170 and 1.7.104; eligible saves from IntelEngine 3.5.2 or earlier can use the offline converter below. Already-lost names/history cannot be recovered.
>
### How to convert an old save

For eligible SE/AE saves from IntelEngine 3.5.2 or earlier, or VR 1.4.15 saves from VR-capable IntelEngine 3.5.1 or earlier. Tested on one real 3.5.2 save per qualified SE/AE runtime and one real 3.5.1 VR fixture; older versions are format-gated, not separately tested. Fix mode does not read the IntelEngine version.

Rendered caches were first stored in IntelEngine 2.0.0; this history does not establish conversion testing on older versions.

The installer always includes `LegacyCacheMigration.exe`, `Convert-IE-Save.bat` and the FAQ in `IntelEngineTools`; no converter selection is needed. Starting a fresh game does not require running the converter.

**Convert before loading an old save with 3.6.0.** Close Skyrim and keep the matching same-directory `.ess` / `.skse` pair together. Run `LegacyCacheMigration.exe fix --save "<path-to-save.ess>"`, or drag one ESS onto the adjacent `Convert-IE-Save.bat`. Fix mode accepts SKSE co-save format 1 with complete framing, exactly one PapyrusUtil owner and, when present, exactly one STRV v1 record. Tested conversion runtimes: **1.6.1170**, **1.7.104**, or **VR 1.4.15 / SKSEVR 2.0.12**. Skyrim 1.5.97 / SKSE64 2.0.20 conversion: untested. VR also requires a bounded `TESV_SAVEGAME` version-12 ESS header. Eligibility does not guarantee every legacy save qualifies.

VR 1.4.15 should work and is partly tested. A populated IE 3.5.1 VR save passed conversion: 14 facts, gossip and task-history caches were repaired, stored names were preserved, and caches, stored names and one generated bio survived two cold reloads and a roughly 21-minute soak. Displayed-name qualification remains partial: one unloaded NPC reported a generic role despite retaining its stored name and memory. An earlier fixture passed task recovery/progression; active-task deadline drift remains untested. This is not full VR or general old-save qualification. Expert VR `convert` still refuses because no historical VR PapyrusUtil provider hash is qualified; `inspect` alone grants no eligibility.

Only rendered-cache values are rewritten. Non-cache fields, including BEL-bearing task destinations and stored names, pass through byte-for-byte without normalization. If STRV is absent and the PapyrusUtil owner contains only recognized record types/versions, `fix` can publish a verified byte-identical cache-free pair; this is a copy, not a repair. Unknown records in that path or a present STRV with no eligible targets refuse.

Validation focuses on IntelEngine's rendered caches. Other plugins' blocks, including duplicate serialization IDs, and non-cache keys and values pass through byte-for-byte; their content does not disqualify an otherwise eligible save. This does not repair other mods' data. Duplicate PapyrusUtil owners or STRV records, ambiguous cache targets and incomplete framing still refuse. Every byte outside the cache values and their enclosing length fields is verified unchanged.

For Skyrim **1.6.1170**, the converter accepts **SKSE64 2.2.6, 2.2.7 and 2.2.8**, which the [SKSE release history](https://github.com/ianpatt/skse64/blob/v2.2.8/skse64_whatsnew.txt) associates with that runtime. Other runtime gates are unchanged; this is not a separate in-game acceptance test.

If the converter says the save path is not allowed (Reparse path rejected), your save folder is a link or junction (for example My Games moved to another drive, or OneDrive): copy the .ess and .skse pair to a normal folder such as Desktop\IE-convert and drag the .ess from there.

It preserves the originals in `<stem>_IEbackup/` and creates sibling `<stem>_IEconverted.ess` / `<stem>_IEconverted.skse` without replacing existing files. Exit **0** means both outputs were published; **2** is a usage, eligibility or safety refusal; **3** is an I/O, verification or publication failure. If the second rename fails, the first converted file may remain; do not load an incomplete pair. Install the complete repaired DLL, both affected PEX files and all three prompts before using the converted pair. Never load a converted save with 3.5.2 or earlier.

Do not repeat conversion or mix original and converted companions. Writer provenance cannot be proved from the save; BEL-to-space is owner policy. Rollback requires the original pair, matching old components and corresponding IntelEngine/SkyrimNet external-data backups; the converter backs up only the pair.

**If you skip conversion:** fixed templates interpret recognized literal percent escapes as controls (for example, `%0A` becomes a newline); `%250A` becomes literal `%0A` without recursion. This does not make native restoration of raw legacy saves safe. See the [API conversion record](docs/DLL_API.md#player-fix-mode-how-to-convert-an-old-save) for exact decoder results and offline byte comparisons.

In the unconverted VR observation, the Travel task restored and progressed, but three of four original populated facts caches read back empty, the fourth only as a header, and both original rendered histories read back empty despite some raw history remaining. One earlier process crashed; its cause is unproven, and the evidence does not establish that it read the unconverted pair. A restored task is not evidence that skipping conversion is safe.

Both preserved legacy pairs reproduced their verified converted bytes through the unmodified shipped batch and production CLI with Skyrim closed, on ASCII and Unicode/space scratch paths. The production CLI also correctly refused while Skyrim was running. These offline results do not establish general existing-save safety.

> **Papyrus API and array guards:** seven existing native functions are now declared in `IntelEngine.psc`, and three array-null checks use boolean guards. Maintenance, recovery and schedule retention were exercised across save/reload.

**Historical 3.5.2 Skyrim compatibility update:** the full package used the corrected MinLL/CommonLibVR native build with VS 2022 flags. Tested on Skyrim **1.6.1170**, with Epicrob also confirming success on his affected **1.7.x** setup. Use matching SKSE and Address Library; VR was not supported by this build. The release/package version was 3.5.2; the tested DLL retained native version 3.5.1. This release did not include the deferred Papyrus/translation fixes or a claimed fix for the 1.5.97 crash report on the original IntelEngine repo.

---

## Requirements

- Skyrim Special Edition / Anniversary Edition. 3.8.0 was tested on Skyrim SE 1.5.97, on a small test setup and on a full Nolvus Awakening load order; it was not retested on the newer runtimes. 3.6.0 was tested on 1.6.1170 and 1.7.104. VR 1.4.15 should work and was partly tested.
- [SKSE](https://skse.silverlock.org/)
- [SkyrimNet](https://github.com/MinLL/SkyrimNet-GamePlugin): 3.8.0 was tested with SkyrimNet 1.1.1 Alpha; Beta 28 was used for 3.6.0 testing. Declared minimum for 3.8.0: Beta 27.
- [SkyUI](https://www.nexusmods.com/skyrimspecialedition/mods/12604) (MCM)
- [PapyrusUtil](https://www.nexusmods.com/skyrimspecialedition/mods/13048) (persistent storage)
- [powerofthree's Papyrus Extender](https://www.nexusmods.com/skyrimspecialedition/mods/22854) (package management, linked refs)
- Papyrus MessageBox (choice prompts; only needed without Magelight UI): [Papyrus MessageBox - SKSE NG](https://www.nexusmods.com/skyrimspecialedition/mods/83578) for Skyrim 1.6 and earlier, or [PapyrusMessageBox-1.7.104](https://www.nexusmods.com/skyrimspecialedition/mods/193932) for Skyrim 1.7

### Optional

- [Magelight UI](https://github.com/Severause/MagelightUI) **1.7.1+** — optional, recommended dashboard host. Install separately. With it, IE's choice prompts (Allow/Deny, door knock, quest offer) open as a Magelight page instead of a message box; a prompt waits while another Magelight window, such as the dashboard, holds the screen.
- [PrismaUI](https://www.prismaui.dev/) — optional frozen dashboard fallback; no new features or fixes on this path. Neither host is required for IE gameplay.

---

*IntelEngine turns Skyrim's people from scenery into agents — NPCs who keep appointments, carry your words, fetch who you need, and remember what happened. And with the Dungeon Master, they also act on their own — seeking you out, settling grudges, spreading gossip, sending you on rescue missions deep into dungeons, and living their own lives whether you're watching or not. The world doesn't wait for you anymore.*
