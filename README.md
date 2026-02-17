# IntelEngine v2.0
### NPC Autonomy & Player-Driven Task Framework for SkyrimNet

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
- **Offer quests** to clear enemy camps, with a guide option and map marker
- **Interact with each other** independently — arguments, deals, whispered conspiracies

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

IntelEngine injects six **SkyrimNet awareness prompts** into every NPC's character bio. These render live game state as natural-language context the AI sees on every dialogue cycle. NPCs don't just execute tasks — they **know** what they've done, what they're doing, and what they've committed to.

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

## Story Engine — The Dungeon Master

The Story Engine is Part 2 of IntelEngine. Every few in-game hours, an LLM Dungeon Master observes the full world state — your location, time of day, NPC memories and relationships — and decides if something should happen. No random dice rolls. Every event is grounded in the actual history of your playthrough.

Nine story types, each individually toggleable via MCM:

- **Seek Player** — NPCs travel to find you because of unfinished business, old friendships, or something they overheard. Forgotten friends don't stay forgotten — NPCs you haven't seen in a while are more likely to come looking.
- **Informant** — NPCs approach with real gossip traced to actual game events. The chain of who told whom is tracked.
- **Road Encounter** — You cross paths with NPCs traveling on their own business. Exterior only. They have their own destination.
- **Ambush** — Hostile NPCs with real grudges stalk and attack you. Stealth or charge variants. Beat them and they yield — talk, kill, or walk away.
- **Stalker** — Romantically obsessed NPCs secretly follow you until caught. No combat — the emotional confrontation is the payoff.
- **Message** — Couriers deliver verbal messages from NPCs who can't come themselves, with optional meeting invitations that schedule the sender.
- **Quest** — NPCs ask you to clear enemies from a location. Guide option (they jog with you) or go alone with a map marker. Bandits, draugr, or dragons.
- **NPC Interaction** — Two NPCs interact independently of you. Arguments, deals, training, whispered conspiracies. Happens whether you're watching or not.
- **NPC Gossip** — Rumors spread through chains of up to 10 people. Information travels realistically through the world.

Every event injects facts into NPC bios that persist and influence all future dialogue. The Dungeon Master uses anti-repetition, type balancing, and per-NPC cooldowns to keep stories varied and meaningful.

---

## Planned Features

IntelEngine is under active development. The following features are planned for future releases:

- **Eliminate Target** — dispatch an NPC to kill a specific person. Assassinations, bounty hunting, or settling grudges — carried out autonomously across the world.
- **Lockpick Door** — send an NPC to pick a locked door, gaining access to restricted areas without doing the dirty work yourself.
- **Steal Item** — task an NPC with stealing something from someone's inventory or home. Risk and reward — their skill determines success.

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

*IntelEngine turns Skyrim's people from scenery into agents — NPCs who keep appointments, carry your words, fetch who you need, and remember what happened. And with the Dungeon Master, they also act on their own — seeking you out, settling grudges, spreading gossip, and living their own lives whether you're watching or not. The world doesn't wait for you anymore.*
