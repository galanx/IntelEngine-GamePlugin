# Changelog

## 3.8.0 — unreleased

### Director
- Director-dispatched actions no longer show the Allow/Deny confirmation (the per-action "Skip follower" setting still applies).
- Story replacement accepts Director fields and explains refusals; a cancelling story must finish before it is replaced.
- Generate requires real NPC names and no longer makes another NPC approach you in informant narration; NPC suggestions rank exact names first.
- When an NPC can't be sent because they aren't loaded (they only exist near their home), the Director now says so instead of "no unique match".
- The dashboard hotkey is ignored while you type in a text field.
- Informant stories have their own form: Informant NPC, Subject (an NPC, a faction or you), optional Source and a required one-sentence Rumor. IE writes the informant's line, so there is no Narration field.
- A rumour is refused, with the reason, when it doesn't name the Subject as a whole word ("Ria" inside "Victoria" doesn't count) or starts with an -ing word.
- NPC Social gossip has a Subject field; the rumour is stored as "<Subject> <what they did>".
- The story type is never chosen by the LLM: a type left on (auto) must be picked before Dispatch, and Generate fills only that type's fields.
- Generated interaction narration describes the scene instead of copying a fact; generated gossip says how and where it was told.
- A social scene for two NPCs already standing together near you plays right there (it used to be applied off-screen).
- With Magelight UI installed, the Allow/Deny, door-knock and quest-offer prompts open as a Magelight page in the dashboard's style (keys 1-3, Esc = the do-nothing answer, timer bar on the knock). A prompt waits while the dashboard or another Magelight window is open. Without Magelight, the Papyrus MessageBox is used as before; it is now only needed without Magelight.
- Director quests need a Plea for help (and a Victim for rescue, an Item description for find_item) before Dispatch; Generate no longer picks the current location or a player home as the quest location.

### Story travel and arrival
- A story NPC counts as arrived after 15 seconds within talking range.
- Arrival timers use real time; a late NPC is re-placed once behind the target, then the story aborts with a notice.
- Story arrival waits until save-load recovery finishes. Director stories ignore the Hold Restriction; automatic stories still turn back and say why.
- Story NPCs who become your teammate are released from linger; linger timeouts survive pausing.
- Lingering NPCs are released after one game hour, so waiting or sleeping frees them (see "Meetings and visits" below for how that limit works now); the linger release distance keeps its default of 800, with the minimum lowered to 300.
- The story watchdog no longer marks an NPC who already arrived as "never finished", and strips travel packages when it resets a story.

### Stories and NPC scenes
- NPC-to-NPC scenes are narrated only within SkyrimNet's hearing range; otherwise the pair waits for you and plays when you come close, or is applied as facts only when it times out.
- An informant's rumour is one checked sentence; IE builds the arrival line from it, and the informant remembers why they came.
- Two NPCs with the same name (two "Gamlunda"s) resolve to the one the DM was shown.
- Spawned actors (battle soldiers, ambushers) are never picked for stories or gossip.
- The Story DM sees which story types each candidate can take, and a Markdown code fence around its reply no longer breaks validation.
- A seek_player story's memory is no longer added twice.

### Off-screen placement and fetch
- NPCs travelling while unloaded are now placed near the target when their estimated travel time runs out (they used to walk on indefinitely).
- A fetched NPC walking toward you is no longer sent home early, and one already beside you is no longer teleported away across an exterior cell boundary.

### Politics
- New `war_allowed:` section in factions.yaml decides which faction pairs may go to war (default: any two factions of type `military`, so guilds and families stay out of it). Entries can be faction ids, display names, types or `*`. Political Engine realms never go to war.
- When the Political DM ignores the "declare war" rule for the most hostile allowed pair, IE declares the war itself (skipping factions whose leaders are all dead); war declarations for pairs that aren't allowed are refused.
- The Empire and the Aldmeri Dominion are neutral to each other: the Legion and the Thalmor are no longer allies, and their starting relation is 15 (was 50).
- A battle result for two factions that aren't at war is recorded as a border skirmish, and no soldiers spawn.
- Fighters left standing after a brawl or skirmish are removed shortly after it ends (they used to stay in the world forever).
- Loading a save resyncs the "at war" flags with the save's actual wars.
- Major political news (wars, battles, treaties, Political Engine developments) reaches every NPC; smaller events reach the factions involved and, for political factions, people in their hold. Repeated events show once with "(reported N times)".
- The Political DM no longer repeats one war's battle, counts a scheduled battle as that war's battle for one game day, and is told which wars can't have a battle yet.
- Political Engine: realm rulers (including puppet realms) are shown as faction leaders; a realm without a ruler clears its leader; a ruler change becomes news; IE resyncs when Political Engine (re)loads; realm allies and rivals follow live sides; factions can set `pe_side` (the Thalmor map to the Aldmeri Dominion).
- The dashboard colours faction names by Political Engine side and labels your own puppet and vassal realms.
- The Politics Enabled toggle comes first in the Faction Politics MCM page.
- Director Politics: a surrender names the Surrendering faction and the Victor, and is refused unless the two are at war; Generate never drafts war declarations, surrenders or peace offers.

### Other
- Battles no longer stop the story and quest timers when they reset.
- Soft stuck recovery no longer waits on latent calls; stuck detection samples at most every three seconds.
- Informant gossip keeps the subject's name.
- Notifications and Papyrus log lines use plain dashes (em dashes showed as "â€”").
- Optional Political Engine API v3 bridge: public campaign news reaches the Political DM as faction-less rumors, with one organization reaction per development and a persisted MCM/dashboard toggle for reaction relation changes. IE's own wars and battles are unaffected.
- Faction fragments: extra `factions.d/*.yaml` files add or replace factions and relations; a Political Engine fragment adds the nine vanilla realms as factions, with live rulers and the player's realm passed to the Political DM, when Political Engine is active.
- Action and scheduling prompts ask for exact in-game place names in the game's language.
- Extra travel and Director diagnostics at DebugLevel 4.

### Stuck NPCs and package handling
- All monitoring runs on one shared timer with one owner. Scripts used to cancel or re-arm it for each other: switching the story engine off, or a battle ending, could freeze every trip, task and schedule.
- A task slot that changed hands while a handler was waiting is no longer wiped or marked "arrived" by the old handler; half-finished slots are cleaned up hourly.
- An hourly sweep releases NPCs who still run an IntelEngine package with no task behind it; "Reset all tasks" in the MCM does the same at once.
- NPCs with no routine of their own (many mod-added NPCs) are walked home when a trip, meeting, task or visit ends, instead of standing where it ended.
- No recovery move happens in the player's view: a stuck NPC who is being watched gets a fresh path instead of a hop, and unseen arrivals come in through the door indoors or from behind outdoors. "Behind the player" used to be "south of the player".
- Indoors nobody is placed 2000 units away (outside the building's shell) or leapfrogged through a wall.
- An NPC who is talking is not treated as stuck, and one who is asked to do something in conversation finishes the sentence before turning to go.
- During a task IntelEngine removes only its own packages, so a follow or wait order from another mod survives the task. If such a package blocks a trip it is cleared and the trip goes on.
- An unknown place name, an unknown target or no free slot no longer cancels the task the NPC already had.
- Trips: a disabled NPC's trip ends; a long road walked together with the player is not cut off at seven hours; the time limit no longer restarts on every load.
- Fetch, deliver, escort, search: a search has an overall limit and the searcher waits on the spot when you fall behind; an escort without "wait" lets the NPC go at the destination; a fetched NPC's visit ends on its own; waits are measured in seconds instead of monitoring passes; carriage drivers are never fetched or escorted.
- Stories: a refused faction courier gets their aggression back; an ambusher gets their own essential flag, aggression and confidence back; quest enemies, bosses and ambush soldiers are removed once out of sight; a dead guide ends the guiding, not the quest; a visitor walks the last stretch; two NPCs stay together for the length of their scene.
- Battles: spawned soldiers are remembered across a restart and removed; your crime factions are restored after a battle you joined; an assassin is no longer deleted at the moment of striking.

### Meetings and visits
- An NPC who is already inside the meeting place has arrived (they were sent to its outside door and the meeting was called off).
- A meeting is not called off because the NPC was talking, fighting or out of sight when it was time to leave.
- An NPC waiting at the door while you are inside walks in (the order used to be re-issued every three seconds, so the walk never got anywhere).
- After a load, an NPC waiting at a destination keeps their place.
- A visit no longer ends one game hour in, whatever is being said. It lasts while the NPC is talking with you and a little after, and six game hours at most. This applies to meetings, errands, story visitors and fetched NPCs.
- Times are understood in many more forms ("in 2 hours", "tomorrow at 6", "at dusk"). The natural-language time parser is by Lanosity.

### Prompts, dashboard and controller
- The choice popup scales with the screen (4K, ultrawide, VR), answers on key release (Enter no longer leaks into the game), takes Left/Right and E, and takes a gamepad when Magelight's gamepad layer is there. Its footer says what Esc answers.
- The task-permission prompt has a 20-second limit; no answer is a silent deny.
- The dashboard has a larger layout and can be driven with a gamepad or the arrow keys.
- A Director political event that is refused now says so (it showed "Sent" and did nothing).

### Wars that end stay ended
- A war that ends leaves the two factions at an uneasy truce instead of still being at each other's throats, so the same pair no longer declares war again after every cooldown, a little worse off each time.
- A war that ends by exhaustion or collapse is recorded as a surrender or a ceasefire, something NPCs can hear about and talk about. It used to end in the database only, with nothing in the world to show for it.
- A faction's own `war_threshold` is honoured when a war is declared in code, not only when the Political DM proposes one.

### Working with SkyrimNet
- An NPC who is given a task in conversation finishes what they are saying before they set off, also when their answer is still being synthesized. IntelEngine now hears from SkyrimNet itself that a line is on its way; it used to ask the game whether the NPC's mouth was moving, which is not yet the case in those seconds, and wait seven seconds at most.
- A running task shows on SkyrimNet's Package Manager page as a row of its own ("IntelEngine task: travel, Dragonsreach"). Remove on that page cancels the task cleanly, the way IntelEngine's own dashboard does, so an NPC you want back can be freed from either place. Needs a SkyrimNet with the package manager; older versions are left alone.
- IntelEngine's settings are on SkyrimNet's dashboard too, on the plugin settings page: stories and their types, how far NPCs travel for each kind of story, quest kinds, NPCs among themselves, tasks and their confirmation prompts, meetings, politics. A change there takes effect in the running game when you press Save; a change in the MCM or on IntelEngine's own dashboard shows there a few seconds later.
- These settings now belong to the installation, not to one save: a new game starts with what you set. A save from before this update keeps its own settings the first time it is loaded and writes them to the shared file.

### Assassins and soldiers that turned on the player
- An assassin sent after a faction leader goes for that leader and nobody else. They were made hostile to every neutral in reach, the player included, and attacked whoever stood nearest once the leader was down or out of reach.
- The pause between an assassin reaching the leader and striking no longer runs into the cleanup timer. When the walk had taken fifteen seconds, the assassin was taken off the books during that pause and then struck anyway: an attacker nothing ever removed. This is the assassin that "kept attacking".
- The attempt ends when the leader is dead, on their knees (leaders who cannot die) or gone; the assassin then stands down instead of looking for the next target. An attempt on a leader who has left the room is called off.
- Soldiers spawned for a brawl or a skirmish fight each other and their factions' enemies, not bystanders. Several soldier types, and the stand-in used for Political Engine realms, attacked any neutral on sight.
- Spawned fighters who survive their event put their weapons away, and are removed at once where nobody is looking.
- A faction ambush only comes from a faction that is hostile to you (standing -40 or lower), and stays small until the feud is deep. The model could pick any enemy of one of your friends, or a faction that does not exist.
- The people who remember an assassination attempt are those who stood around the victim. They were counted around you, so someone two rooms from the attack remembered having witnessed it, and the victim remembered having "witnessed an attempt on" a person with their own name; the victim now remembers being attacked.

### Fixes to 3.8 changes found in review
- NPC gossip without a subject no longer starts with a blank.
- The second NPC of a scene resolves again when they are not in the first one's cell (the pair was dropped as unresolved).
- A model answer with a field of the wrong type (`"gossip": null`) is rejected instead of ending the game.
- An informant rumor may start with "During", "King", "Something" and similar words.
- Choice popup: a lost race for the screen is noticed at once, a late entry no longer leaves the game paused on a hidden page, and a page that failed to load is not reused.
- A pair of NPCs waiting for you to come within hearing waits for the full time, not thirty seconds.
- A `factions.d` fragment with an unknown `requires:` line, or saved with a byte-order mark, is not loaded for everyone.
- A battle in a plugin whose file name is not plain ASCII no longer throws while it is recorded.
- An automatic story that is given up on (the NPC cannot reach you, or turns back at a hold border) says nothing on screen: it used to name a visitor you never saw setting out. A story you dispatched from the dashboard still reports back.
- A story NPC counts as having reached you only on the same floor, as travel arrivals already did; they used to arrive and speak from the room below.

## 3.7.1 — 2026-11-04

- The dashboard no longer goes blank when a game or mod name has invalid text encoding; it shows � instead.
- Fixed a crash near some modded NPCs whose faction list contains a non-faction record; the NPC is logged once so the mod can be found.
- MCM Hold Restriction toggles now save when clicked (they were unreachable in the MCM; the dashboard Settings tab already worked).

## 3.7.0 — 2026-11-03

- **Requires SkyrimNet Beta 27 or newer** (travel prompt uses the `get_place_names` decorator).

### Director
- Add Generate and draft controls for Story, NPC Social, Political, and Action forms. Generate is experimental; review drafts before dispatch.
- Keep chosen identities and edited text on re-roll, suggest distinct nearby participants, and guide required fields, destinations, and NPC motives.
- Add optional Action Execution reasons remembered only after a successful start, failure notices, busy confirmations, and Story/Social `queued: starts on dashboard close` feedback.
- Clarify that Story/Action toggles govern automatic stories and AI-chosen actions, not Director requests; Action changes need SkyrimNet Reload configs or a restart.

### Dashboard
- Save Director drafts across reloads; add searchable NPC/faction pickers, resizable text fields, clearer hints, and collapsible sections.
- Add optional Magelight hosting alongside PrismaUI, group actions by category, and fold packages into Tasks with recorded task origin, time, and reason.
- Show in-game calendar dates and faction leaders in Politics. Record completed Story/Social outcomes in SkyrimNet History, subject to its audience filters.

### Fixes
- Prevent duplicate arrivals and stale Story/Social callbacks from repeating outcomes or changing newer dispatches.
- Preserve cancellation/replacement state, improve moving-target arrival checks, and record attempted versus successful task outcomes accurately.
- Improve exact NPC and faction-leader matching, preserve full dynamic actor IDs, and reject missing delivery targets without replacing existing tasks.
- Reject same-faction political pairs and incomplete or invalid generated fields; preserve valid draft fields for review.
- Fix Director cancellation/conduct-report feedback and reason facts; preserve the selected same-name actor through Action Generate.
- Keep localized place names intact in action and DM prompts.

## v3.6.2

- Save converter: convert caches on temporary (0xFF) actors and orphaned global caches in place instead of refusing the whole save, and refuse a save whose caches are already in the 3.6 format (for example a later save made from an `_IEconverted` one). Output is readable multi-line text and warns against loading converted saves under any IE 3.5.x. Live: a converted ADT save loads with correct prompt text.
- Fix duplicate quest/message courier arrivals: the travel poll and the proximity callback could both handle one arrival, injecting blank-then-full facts and raising None errors after cleanup. Stale arrival continuations now stop without touching a newer dispatch. Live: one arrival, facts once, one cleanup.
- Dashboard "Cancel quest" after a courier arrives now frees the courier's task slot and package. Live: passed.
- Dashboard hotkey only toggles while Skyrim has focus and the configured modifiers match exactly (`0` no longer fires on Shift+0); documented default is Shift+7. Live: passed.
- Changing the dashboard hotkey on the SkyrimNet settings page now applies as soon as you click Save, without a restart. Live: owner-verified.
- Courier story facts are injected when the courier arrives, not at dispatch, so an aborted courier leaves no facts. Live arrival injection passed; live rejection is untested.
- Persist all four politics settings through shared native setters used by the MCM and dashboard. Politics initialized while disabled can be enabled later without restarting. Live: cold-load persistence and same-session enable passed.
- Print world knowledge shared by every Story DM candidate once, while preserving each candidate's additional facts and silent fact-check constraints. Zero or one candidate keeps knowledge local. Offline production-code and full-prompt checks passed; live untested.
- Truncate cached and prompt text on UTF-8 character boundaries.
- Remove unused Dialogue Safety Net and Director pending-parameter natives, their private backing code, and matching Papyrus declarations. Rebuild `IntelEngine.pex`; pair it with the matching DLL. Director parameters remain in the existing ModEvent JSON payload.

## v3.6.1

- Rebuilt bundled save converter to stop a Defender false positive (Wacatac.B!ml); no functional changes.

## v3.6.0

- Install the player FAQ, legacy save converter and drag-and-drop launcher for everyone. Retain the visible second FOMOD page with Required tools; fresh games do not need conversion. Convert an eligible old save before loading it with 3.6.0.
- Story DM skips ticks when all eight player-facing types are excluded, lists only currently allowed types in the prompt, and discourages repeated seek-player NPCs and long-absence motives. Rebuilt the StoryEngine script from source; offline exclusion and prompt-render checks passed. In a natural two-hour soak with `seek_player` disabled, 12 prompts omitted `seek_player`/PRIME. The automatic all-eight-types-off skip passed live; nonzero excluded-count filtering and natural disabled-pick rejection remain unobserved.
- The shared SE/AE/VR DLL should work in VR; partly tested on an emulated headset: startup/health, NPC/location lookups, MCM/Allow-Deny, travel arrival, two manual saves and a cold reload passed. Full acceptance remains untested for message delivery, fetch/escort, cancel, travel cleanup, VR overlay bios, dashboard, real-headset behavior and frame timing. The MCM right column is clipped on the emulated rig because of a Devkit emulated-window artifact; real-headset presentation remains untested. One automated-save attempt hung; this does not establish an IntelEngine defect.
- NPC Social DM snapshot/callback work uses the main-thread task queue and generation guards. SE/AE soaks passed; the 1.5.97 crash report on the original IntelEngine repo is not confirmed fixed.
- Cancellation was verified on Skyrim 1.6.1170 and 1.7.104: the slot, busy state and task cleared, with no success-history entry added.
- Fix Native #18: Bio Content Library base bios and overlay precedence verified on SE/AE 1.6.1170 and 1.7.104; base bios only verified in VR. Dynamic save-layer behavior was checked offline only.

### Offline legacy-save fix mode
- Refuse native rendered-cache assignments with missing values, including whitespace/NUL aliases hidden in opaque fields, before they can overwrite a repaired cache with empty data.
- Limit converter content validation to IntelEngine rendered-cache targets. Preserve other mods' blocks, duplicate unrelated serialization IDs and non-cache keys/values byte-for-byte, including control characters. Keep framing/count checks, refuse duplicate PapyrusUtil owners or STRV records and ambiguous targets, and verify all non-target bytes unchanged except the required enclosing length fields.
- Accept SKSE64 2.2.7 and 2.2.8 alongside 2.2.6 for Skyrim 1.6.1170, following the [SKSE release history](https://github.com/ianpatt/skse64/blob/v2.2.8/skse64_whatsnew.txt). No additional Skyrim runtimes are accepted.
- Add a player-oriented one-save fix command for eligible IE 3.5.2-or-earlier saves on Skyrim 1.6.1170/1.7.104 and VR-capable IE 3.5.1-or-earlier saves on VR 1.4.15 / SKSEVR 2.0.12. One real 3.5.2 save per qualified SE/AE runtime and one real 3.5.1 VR fixture passed bounded converted-copy acceptance; older versions remain format-gated, not separately tested. The VR fixture covered six facts/task-history caches, task recovery/progression, a roughly 39-minute sampled soak and one cold reload, not populated gossip or stored-name migration. All 66 cold cache comparisons matched; 76/77 state fields matched, with a small scalar deadline difference and unexplained SkyrimNet timeline differences. Three actor mappings were absent before and after; original SkyrimNet database restoration and the native name index remain unqualified. This is not general old-save or full VR qualification.
- Skyrim 1.5.97 / SKSE64 2.0.20 conversion: untested. Adds fix-only eligibility with synthetic coverage only, no live conversion test.
- Preserve non-cache values, including BEL-bearing task destinations and names, byte-for-byte without decoding or re-encoding. Only rendered-cache values are rewritten. A recognized PapyrusUtil owner without STRV can produce a verified unchanged cache-free pair; unknown record types/versions refuse. Expert 1.5.97 and VR conversion remain refused without a qualified historical provider.
- Convert before loading an old save: an unconverted VR copy recovered/progressed its Travel task but showed empty/header-only original facts caches and empty rendered histories despite some raw history remaining. An earlier process crashed with cause unproven; the evidence does not establish that it read the unconverted pair.
- Offline checks passed: both preserved original pairs reproduced their verified converted co-saves byte-for-byte through the production fix entry with a no-game test predicate; original ESS and source metadata remained unchanged. Real Inja/production-codec smoke passed on all three templates, including legacy percent substitutions and encoded literal preservation. The shipped CLI succeeded on a fresh scratch copy with Skyrim closed, preserving original and ESS bytes; it also correctly refused while Skyrim was running. Migration/codec, refusal, backup-locking, incomplete-publication and Unicode/single-file launcher checks passed.
- Historical writer provenance cannot be proved from the file. BEL-to-space is an owner policy, not independently established original text.
- Fix-mode backup covers only the save pair. Rollback also requires matching old providers and corresponding IntelEngine/SkyrimNet external-data backups; do not mix or repeat conversion, load an incomplete output pair, or expect recovery of lost names/history.

### Papyrus API and array guards
- Align the Papyrus API with seven existing native functions; no new native implementation or compatibility aliases.
- Replace one Core and two Schedule array-null comparisons with boolean guards, preserving initialization, length validation, restored state, recovery and monitoring.

### Verification and support
- Tested on official SkyrimNet Beta 28 on Skyrim 1.6.1170 and 1.7.104.
- Skyrim SE 1.5.x: untested.
- Verified on Skyrim 1.6.1170 and 1.7.104 from a fresh new game: caches, stored RNE names and on-screen names survive warm and independent cold reloads; repaired scripts compile and disassemble cleanly, and maintenance and populated-schedule retention were exercised across save/reload. On 1.7.104, on-screen names can take a moment to reappear after loading.
- Legacy migration verified on one real Skyrim 1.6.1170 save: 28/28 sampled surviving caches exact, plus fresh caches through warm and independent cold reloads. Temporary-actor names preserved byte-for-byte, not live-verified. One bounded 1.7.104 converted-copy acceptance retained 11 sampled caches, two owner-policy fields and 24 qualified live names through warm and independent cold reloads; four other name holders remain unverified. Never load a converted save with 3.5.2 or earlier. See [converter procedure and limits](docs/DLL_API.md#offline-legacy-save-conversion).

## v3.5.2 — 2026-10-09

### Skyrim compatibility update
- Uses the pinned MinLL/CommonLibVR native build with the audited non-VR ABI correction.
- Rebuilds with the corrected VS 2022 compiler flags, retaining C++23 without `/O2`, `/std:c++latest`, or `/d2ReducedOptimizeHugeFunctions`.
- Includes the freshly compiled Papyrus scripts and rebuilt dashboard in the full package.
- Verified on Skyrim 1.6.1170; Epicrob confirmed success on his affected 1.7.x setup.
- Requires SkyrimNet Beta 25 or newer and matching SKSE/Address Library; VR is not supported by this build.
- Release/package version is 3.5.2; the tested native DLL remains byte-identical and reports 3.5.1.
- Papyrus/translation backlog fixes and the 1.5.97 crash report on the original IntelEngine repo remain outside this release.

## v3.5.1 — 2026-09-12

### SkyrimNet Beta 25 migration
- Moved IntelEngine's 11 executable actions and three category containers into the `galanx.intelengine` external content bundle.
- Moved four custom prompts and seven character-bio submodules into the same external bundle.
- Preserved all action names, Papyrus mappings, category IDs, and prompt lookup names.
- Removed the retired loose `config/actions` and `prompts` copies to prevent duplicate registration.
- Updated the native dashboard to enumerate and toggle actions in the external bundle.
- Preserved `config/plugins/IntelEngine` separately so plugin settings and user-managed faction configuration continue to work.
- Requires SkyrimNet Beta 25 or newer.

## v3.2.1 — 2026-04-06

### Fix: Stuck tick watchdog (C++ DLL)
- **Politics, NPC interactions, and Story DM** could permanently stop ticking if an LLM callback was lost (SkyrimNet crash, save reload mid-request, etc.)
- Added C++ watchdog system that tracks pending state in the DLL — since the DLL loads fresh every game start, stale flags from saves are automatically detected and reset
- Timeouts: 1 game-hour for politics/NPC ticks, 6 game-hours for story DM (which legitimately runs for hours)
- Works on existing saves without ReSaver — no manual intervention needed

### Improvement: Political director faction dropdowns
- Replaced text inputs with dropdown selectors for faction A and faction B in the political event director
- Dropdown shows all factions from `factions.yaml` with display name and ID
- Prevents silent failures from typos in faction IDs

### Fix: JSON escaping for non-ASCII names
- Rewrote `EscapeJsonString` to properly handle UTF-8 multibyte characters (Cyrillic, CJK, etc.)
- Non-ASCII characters are now emitted as `\uXXXX` JSON escapes, preventing broken JSON when NPC names contain special characters
- Applied consistently across NPC index and dashboard JSON builders

## v3.0.0 — 2026-03-22

### New: Faction Politics System
- **9 configurable factions** — Imperial Legion, Stormcloaks, Thalmor, Companions, Thieves Guild, College of Winterhold, Dark Brotherhood, Silver-Blood Family, Black-Briar Family
- **Political DM** — AI-driven faction events every 6 game hours: trade deals, espionage, sabotage, assassinations, border skirmishes, war declarations, surrenders
- **Gradual escalation** — relations progress naturally from neutral to tense to hostile to war
- **War system** — formal declarations, army strength, morale tracking, off-screen battles, surrender conditions
- **Player standing** — per-faction reputation based on actions, crime, and battle participation
- **Political awareness** — NPCs know about recent political events and react in conversation
- **Configurable** — edit `factions.yaml` to add custom factions, change thresholds, set conflict styles
- **Per-playthrough SQLite database** — all saves in a playthrough share one political timeline; loading an earlier save removes later history and re-opens later-ended wars

### New: Battle System
- **Player-present battles** with 5 waves of spawned soldiers (up to 22 per side)
- **Pending battles** — spawn at real world locations, player must travel within 3 game hours or battle resolves off-screen
- **Mid-battle join** — arrive late to find a battle already in progress with casualties
- **Morale system** — battle ends when one side's morale drops below 20%
- **Standing rewards** — fight for your faction to gain reputation, spectate and lose it
- **Battle witness memories** — nearby NPCs remember the battle and who fought
- **Bounty immunity** — no bounty during faction quests, friendly fire forgiven via battle faction membership
- **Deferred cleanup** — dead soldiers cleaned up behind the player as they walk away

### New: Faction Quests
- **faction_combat** — clear enemy faction soldiers from a location
- **faction_rescue** — rescue a captive from enemy faction soldiers
- **faction_battle** — join a full-scale battle that affects war outcomes
- **Standing-gated** — faction quests appear when standing is 20+ with a faction
- **Faction couriers** — local guards/soldiers deliver the call to arms
- **Enemy validation** — fuzzy matching for LLM-suggested faction names

### New: Prisma UI Dashboard
- **Politics tab** — faction relations grid, active wars, player standings, recent events
- **Director: NPC Social** — manually trigger interactions and gossip between two NPCs
- **Per-action confirmation toggles** — disabled / followers only / everyone
- **Whitelist/blocklist settings** — faction, location, and NPC filters visible and editable
- **Action categories** — drill-down nested actions (Travel, Communication, Scheduling)
- Open with **Shift+7** (customizable hotkey)

### New: Story DM Improvements
- **Player familiarity** — stranger / aware / acquainted tiers based on dialogue and memory history
- **Gossip location context** — NPCs only relay gossip from their own hold
- **Quest subtype tracking** — different quest types don't block each other
- **Anti-duplication** — won't recreate vanilla quests (Amren's sword, etc.)
- **World silence detection** — actively dispatches after 2+ days of quiet

### New: Political DM
- Dedicated AI prompt governing faction relations independently
- War behavior with battle results, morale, surrender
- Conflict styles per faction type (military, guild, political)
- Critical status enforcement — war declaration mandatory at threshold

### Improvements
- Separate Story DM and NPC DM dispatch tracking
- Hold restriction "same town" policies
- GoToLocation blocked during fetch/escort/search tasks
- 100+ new C++ native functions
- Location resolution improvements for small settlements

### Bug Fixes
- Fixed FormID overflow for dynamically spawned actors
- Fixed standing wiped on save/load
- Fixed wrong enemy faction spawning in battles
- Fixed double quest completion
- Fixed guards attacking player during battle
- Fixed gossip without location context
- Fixed `[WAR]` tag showing without active war

---

## v0.9.1 — 2026-02-19

### Bug Fixes

- **Breezehome pathfinding bug**: Fixed NPCs being unable to navigate to Breezehome. The word "home" inside "Breezehome" was incorrectly triggering the home-resolution semantic intent, causing the location resolver to look for a home owner instead of the actual location. Added word boundary detection so compound names like "Breezehome" resolve correctly, while "go home" and "Carlotta's home" still work as expected. Also added exterior door fallback (Strategy 1b) for interior destinations without a world location marker.

- **MCM Story settings not saving**: Fixed Story Engine MCM settings (tick interval, enabled types) resetting to defaults after reloading a save. The scheduler now properly restarts with updated settings when changed via MCM, and settings persist correctly across save/load cycles.

- **Trespassing bug**: Fixed NPCs saying "you need to leave now" even when they personally led the player to their home. Root cause was anti-trespass state being restored prematurely when multiple NPCs shared the same destination cell. Added reference counting in C++ so the cell stays public until ALL visiting NPCs have departed, and added a player-in-cell guard in Papyrus so the cell is never restored to private while the player is still inside.

### Improvements

- **Enhanced Dungeon Master prompts**: Rewrote both the Story DM and NPC Social Life DM prompts with clear, structured instructions. The DM now evaluates each candidate's personality, class, faction allegiance, and profession before dispatching. A temple priest won't abandon their duties without a life-or-death reason, a Stormcloak sympathizer avoids Imperial territory, a timid farmer won't track someone into a Nordic ruin. Story dispatches are grounded in each NPC's recent memories and existing story threads rather than random selection.
