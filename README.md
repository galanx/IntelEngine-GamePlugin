# IntelEngine
### Autonomous NPC Dispatch & Scheduling for SkyrimNet

*"Meet me at the Western Watchtower at sunset."*
*She agrees. Hours pass. The sun dips. You arrive — and she's already there.*

---

## The Day Everything Changed

You step out of Breezehome at dawn with more to do than one Dragonborn can handle.

Farengar needs to warn the Jarl. You turn to him: *"Tell Jarl Balgruuf there's been a dragon sighting near the Western Watchtower. Tell him to meet me at the Bannered Mare tonight."* He nods and departs — **delivering your message** on foot through the keep. Balgruuf will hear it, remember who sent it, and the meeting request **schedules him to travel** to the inn that evening.

You need backup at the watchtower, so you find Jenassa at the Drunken Huntsman. *"Meet me at the Western Watchtower at sunset."* She agrees. The **meeting is scheduled**. She doesn't leave now — she knows when to depart, calculates the distance, and **leaves early enough to arrive on time**. You go about your day.

Before heading out, you need Adrianne. *"Lydia, go get Adrianne. The blacksmith. Bring her here."* Lydia walks to Warmaiden's, finds Adrianne at the forge, and **escorts her back** on foot. Adrianne **lingers nearby** — leaning on a post, sitting on a bench — until you've spoken and walk away. She drifts back to the forge on her own.

You tell Lydia to **go to the Bannered Mare** and wait. She descends the steps, crosses the market, pushes through the inn door, and settles into a seat by the fire. But you change your mind halfway — *"Actually, stop. Come back."* She **cancels the task** and turns around. *"Forget that. **Run** to the stables instead."* She takes off at full sprint.

Hours later, the sun touches the mountains. You reach the Western Watchtower. Jenassa is already there — sitting by the wall, calm. She arrived early. **The meeting is live.** You discuss the plan, scout the area, and when you're done, you walk away. **The meeting ends naturally** — no timer, no script, just proximity. She heads off on her own.

That evening, you push through the door of the Bannered Mare. Balgruuf is there — the message reached him, and he **kept his scheduled appointment**. He remembers the dragon warning. He knows Farengar carried it.

Tomorrow, things get more complex. You tell a guard: *"Go get Ysolda after sunrise."* The **fetch is scheduled** for morning — the guard stays at his post until dawn, then departs. You ask a courier: *"Tell Adrianne tomorrow afternoon that the steel shipment is ready."* The **delivery is scheduled** — words carried at the right time, not a moment too soon. Meanwhile, a companion offers to **search for** a missing traveler with you — *"Take me to Belethor."* You travel **together**, side by side, and when you fall behind, they **pause and wait** for you to catch up.

Five NPCs are acting simultaneously. Ten more tasks are queued for the future. The world doesn't wait for you to do everything yourself.

This is **IntelEngine**.

---

## What This Mod Does

IntelEngine is a task execution framework for [SkyrimNet](https://github.com/MinLL/SkyrimNet-GamePlugin). Where SkyrimNet gives NPCs the ability to think and speak through AI, IntelEngine gives them the ability to **act** — physically, across the game world, on their own two feet.

Through natural conversation, any NPC can:

- **Schedule meetings, fetches, and deliveries** for any future time — *"at sunset"*, *"tomorrow morning"*, *"in three hours"*
- **Travel** to named locations, relative directions, or anywhere the game world has a door
- **Fetch** people and escort them back to you on foot
- **Deliver messages** to anyone — with optional meeting requests that schedule the recipient to travel
- **Search** for someone alongside you, traveling together

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

**Natural arrival** — The NPC waits at the meeting point, idling naturally — sitting, leaning, looking around. When you arrive, the meeting is live. Walk away, and it ends. No arbitrary timer. No "press E to end meeting." Just proximity.

**No-shows are remembered.** If you never arrive, the NPC waits until their patience runs out (configurable, default 3 game hours), then leaves. They remember you didn't show — and it colors future interactions differently than a meeting that went well.

**Lateness is tracked.** The NPC knows if they arrived late (pathfinding trouble, long distance). You know if the player was late. The meeting outcome — success, late arrival, or no-show — persists in the NPC's memory.

### Schedule Fetch

> *"Go get Ysolda after sunset."*
> *"Bring me Nazeem tomorrow morning."*

The NPC stays where they are now. When the departure window arrives, they travel to the target, escort them back to you on foot, and the fetched person lingers nearby until you walk away.

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

When they arrive, the fetched person **lingers naturally** — sitting on furniture, leaning against walls, idling in place. They behave like someone who was asked to come over, not a mannequin planted in front of you. They stay as long as you're nearby. Walk away, and they return to their routine.

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

IntelEngine injects four **SkyrimNet awareness prompts** into every NPC's character bio. These are Jinja2 templates that read live game state and render it as natural-language context the AI sees on every dialogue cycle. NPCs don't just execute tasks — they **know** what they've done, what they're doing, and what they've committed to.

### Task Awareness
NPCs know their current task — *"traveling to Dragonsreach"*, *"delivering a message to Nazeem"*, *"returning with Adrianne"* — and maintain a timestamped history of completed tasks. *"I fetched Ysolda earlier today. Delivered a message to the Jarl yesterday."*

### Schedule Awareness
NPCs know their commitments — *"I'm meeting someone at the Bannered Mare this evening"* — and how long until departure. Active meetings, pending schedules, and en-route status are all visible to the NPC's AI.

### Meeting Outcomes
NPCs remember how meetings went. Did the player show up on time? Late? Not at all? Was the NPC themselves delayed? These outcomes persist — a no-show is a different memory than a successful rendezvous, and NPCs can reference either in future conversations.

### Received Messages
When a message is delivered, the recipient retains who sent it, who carried it, what it said, and when it arrived. This information stays in their character context so they can react naturally — *"Farengar told me about the dragon sighting. That was your warning?"*

---

## Concurrency & Persistence

- **5 simultaneous active tasks** — five NPCs traveling, fetching, or delivering at the same time, each tracked independently
- **10 scheduled tasks** — queued for future execution across all NPCs
- **Save/load safe** — active and scheduled tasks survive saving and reloading; AI packages are reconstructed on game load
- **Independent recovery** — each task slot has its own stuck detection, departure verification, and deadline tracking
- **Follower-aware** — follower NPCs are temporarily released for task execution and restored to your service when they return

---

## MCM Configuration

Three pages in the SkyUI Mod Configuration Menu:

### Active Tasks
Real-time view of all 5 task slots — what each NPC is doing, where, and current status. Clear individual tasks or reset everything.

### Scheduled Tasks
View all pending scheduled tasks with times and targets. Cancel individually or clear all.

### Settings

| Setting | Default | Range | Description |
|---|---|---|---|
| Debug Mode | Off | On/Off | Verbose logging for troubleshooting |
| Max Concurrent Tasks | 5 | 1-5 | How many NPCs can be active at once |
| Default Wait Hours | 48 | 6-168 | How long NPCs wait at destinations |
| Task Confirmation | On | On/Off | Prompt before executing tasks |
| Report Back After Delivery | On | On/Off | Messengers narrate delivery completion |
| Meeting Timeout | 3 hrs | 1-12 | How long NPCs wait at meeting spots |

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

**Papyrus Scripts** — game engine integration:
- AI package management (travel, sandbox, and escort packages at three speed tiers)
- Slot-based task state machine with dual persistence (runtime arrays + StorageUtil)
- Schedule monitoring with distance-based early departure calculation
- Save/load recovery with full package and linked-ref reconstruction
- MCM management interface

**SkyrimNet Action YAMLs** — nine AI-selectable actions with eligibility rules, typed parameters, and event strings that feed context back into NPC awareness for future decisions.

---

## Planned Features

IntelEngine is under active development. The following features are planned for future releases:

### New Task Types

- **Eliminate Target** — dispatch an NPC to kill a specific person. Assassinations, bounty hunting, or settling grudges — carried out autonomously across the world.
- **Lockpick Door** — send an NPC to pick a locked door, gaining access to restricted areas without doing the dirty work yourself.
- **Steal Item** — task an NPC with stealing something from someone's inventory or home. Risk and reward — their skill determines success.

### NPC-Initiated Visits

The most ambitious planned feature: **NPCs will visit you on their own.**

Based on their accumulated memories, past interactions, and relationship with you, NPCs may decide to seek you out. A companion you adventured with might track you down at the Bannered Mare because they haven't seen you in days. A friend might propose traveling somewhere together, hunting a dragon they heard about, or simply going for a walk. An NPC you wronged might show up with less friendly intentions.

This inverts the entire framework — instead of you dispatching NPCs, they dispatch themselves. The same cross-cell travel, scheduling, and awareness systems that power player-issued tasks would drive NPC-initiated ones. The world doesn't just respond to you — it comes looking for you.

> **Note:** This feature depends on SkyrimNet API capabilities that don't exist yet — specifically, endpoints to query NPC bios, memories, and relationship data relative to the player, and a way to run an LLM evaluation outside of dialogue to let NPCs decide *why* they'd visit. The visit reasons must also be grounded in real game state — if an NPC proposes hunting a dragon together, that dragon needs to actually exist in the world, and the NPC needs to lead you there. This is a long-term goal that will evolve alongside the SkyrimNet API.

---

## Compatibility

> **Warning: Overlapping SkyrimNet actions from other mods will cause conflicts.**
>
> SkyrimNet presents ALL registered actions to its AI when choosing what an NPC should do. If another mod provides its own travel, fetch, or cancel actions, the AI will see **duplicate options** — for example, two different "go to location" actions. It may pick IntelEngine's travel but the other mod's cancel, which won't work because each mod's cancel only affects its own tasks.
>
> **If you use another SkyrimNet mod that provides similar actions** (travel, fetch, deliver, cancel, etc.), you must **disable the overlapping actions** in either IntelEngine or the other mod. Each action YAML has an `enabled: true/false` flag — set conflicting actions to `enabled: false` in whichever mod you want to defer.

---

## Requirements

- Skyrim Special Edition / Skyrim VR
- [SKSE](https://skse.silverlock.org/)
- [SkyrimNet](https://github.com/MinLL/SkyrimNet-GamePlugin)
- [SkyUI](https://www.nexusmods.com/skyrimspecialedition/mods/12604) (MCM)
- [PapyrusUtil](https://www.nexusmods.com/skyrimspecialedition/mods/13048) (persistent storage)
- [powerofthree's Papyrus Extender](https://www.nexusmods.com/skyrimspecialedition/mods/22854) (package management, linked refs)

---

*IntelEngine doesn't add quests, dialogue, or story. It adds capability. Combined with SkyrimNet's conversational AI, it turns Skyrim's people from scenery into agents you can dispatch across the world — NPCs who walk where you point, carry what you say, fetch who you need, keep appointments, and remember what happened. The world doesn't wait for you to do everything yourself anymore.*
