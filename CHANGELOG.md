# Changelog

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
- **Per-save SQLite database** — political state persists independently per save file

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
