# Changelog

## Unreleased

- Omit empty Director Generate fields while retaining blank-key metadata, and fall back to a nearby NPC when Action Generate returns no usable actor; offline dashboard verification only, no installation or game test.
- Give Action Generate the player's current location, forbid it as a destination, label the NPC picker as nearby-only, and make generated Action reasons required for the single automatic follow-up. Pair the rebuilt DLL, prompt and both dashboard trees; offline/headless checks only, no installation or game test.
- Notify the player when a Director action fails, inject its reason only after successful start, and give Generate nearby place names for resolvable GoToLocation/EscortTarget destinations. Pair Core PSC/PEX and prompt; compiled-bytecode and dashboard scenarios pass offline. No installation or game test.
- Ambush and stalker faction-leader facts use faction display names; clarify that the selected ambush NPC is the attacker, and have Generate write the chosen NPC's motive without repeating the type hint. Pair StoryEngine PSC/PEX, prompt and both dashboard trees; compiled-PEX and all headless dashboard scenarios pass offline. No installation, live model or game test.
- Require Action Generate to use exact known NPC targets, clear generated waitForPlayer, and fill GoToLocation destinations with non-empty named places; action motives describe the NPC's own reason. Pair both dashboard trees and prompt; all headless dashboard scenarios pass offline. No installation, live model or game test.
- Add optional Action Execution Reason, generate motives for all actions without changing CancelCurrentTask/ChangeSpeed, and inject the motive as an NPC fact. Pair Core PSC/PEX, prompt and both dashboard trees; headless/offline verification only, no installation or game test.
- Prefer faction-leader lookup over fuzzy NPC-name lookup for Story hirers; constrain Action Generate destinations to places, clear generated waitForPlayer, and prioritize queued title text over engine-busy text. Pair StoryEngine PSC/PEX, prompt and both dashboard trees; headless tests only, no installation or game test.
- Show Story/Social dispatches as queued until a fresh section state push, dashboard reopen, or 30 seconds; keep Political/Action Sent flashes. Pair both dashboard trees; headless/offline verification only, no installation or live-game test.
- Snap uniquely matching generated names to full tagged option names and require exact NPC names in the prompt. Add Action Execution Generate/Clear/Stop through the shared draft flow, nearby-only actor selection, action params, re-roll ownership and required-field follow-up; exclude CancelCurrentTask/ChangeSpeed. Accept action generation in the native handler. Retain and verify the existing Story/Social end-of-dispatch state pushes. Pair rebuilt DLL, Core PEX, prompt and both dashboard trees; headless/offline checks only, no installation or live-game/model test.
- Keep all Director form drafts, touched flags and the active tab across page reloads; Clear removes the form's saved draft. Add shared pointer-driven textarea resizing (rows minimum to 400px), top-right textarea clears and a single Social NPC/NPC/type row above full-width narration. Pair both dashboard trees; verified offline in headless Chrome, not installed or live-game tested.
- Polish Director fields with conditional × clears that return ownership to Generate, centred picker clears, visible textarea grips and full-width Social narration; add one required-field follow-up, explicit third-person named-character narration and clearer Informant gossip guidance. Pair both dashboard trees and prompt; all 17 headless scenarios pass offline. No installation, live model or game test.
- Generate re-roll keeps filled NPCs, factions and type; rewrites generated text; × a name to re-pick it.
- Tidied the Director Generate prompt: one consistent keep/rewrite rule (user-set kept, blank and previously generated rewritten), duplicates removed; no behaviour change.
- Story Types and Actions tabs say their toggles only affect automatic stories / AI-chosen actions; Director dispatch and Action Execution always work.
- Distinguish Actions category headers with larger bold titles and an amber left border; dim children and show `OFF (category)` while their category is disabled, preserving their own enabled values and working toggle payloads. Pair both dashboard trees; all 16 headless scenarios pass offline, with the extended category regression failing before/passing after. Frontend only; no installation or game test.
- Group Actions beneath their SkyrimNet category cards, ordered Travel/Communication/Scheduling with indented children; derive IntelEngine membership from `intel_` categories and group other mods by category. Retain counts, category labels, NPC text and toggle payloads. Pair rebuilt DLL and both dashboard trees; native-host and all 16 headless scenarios pass offline, with grouping/metadata regressions failing before and passing after. No installation or game test.
- Actions tab lists IntelEngine's Communication/Scheduling/Travel categories under IntelEngine (marked "(category)") and shows their template text as "the NPC".
- Require active Story and Social variant fields: show red stars, block Dispatch and name missing fields; retain `required: true` in Generate variant metadata and mark required base fields. Require non-empty strings, never null, in the prompt; silently skip optional null values. Pair both dashboard trees and prompt; all 15 headless scenarios pass, with required-field regression failing before/passing after. No DLL/Papyrus changes, installation, live model or game test.
- Move Director Story/NPC Social engine-busy details into italic amber section-title suffixes visible while collapsed; disable active Story dispatch, keep active Social dispatch available with its busy label, and preserve drafts across tab switches without storage. Pair both dashboard trees; 15 headless scenarios pass, with busy-header and draft regressions failing before/passing after. No DLL/Papyrus changes, installation or live-game test.
- Unify all Director base fields and Action variants through one readable label/control/hint component, with red required stars in labels, example-only base placeholders and clearer FetchPerson refusal guidance. Pair both dashboard trees; all dashboard scenarios verified headlessly offline. No DLL, installation or live-game test.
- Use one shared searchable picker for every Director NPC-name field, with nearby markers, known indexed display names, free text, and capped suggestions; keep Action NPC nearby-only with unchanged FormIDs and append labeled faction hirers. Send known names on dashboard open/index-count changes and retain them across periodic/coalesced snapshots. Pair rebuilt DLL and both dashboard trees; native host and all headless dashboard scenarios verified offline. No installation or live-game test.
- Show amber Story/NPC Social engine-busy hints beneath Director Dispatch buttons using current dashboard state, with friendly Story types and Tasks cancellation guidance; keep Dispatch available. Pair both dashboard trees; new headless busy-line regression fails before/passes after. No native/Papyrus changes, installation or live game test.
- Allow faction hirers for Director ambushes and stalkers: normalize faction names to IDs, offer faction suggestions, and teach faction leaders who ordered the encounter without changing NPC hirers. Pair StoryEngine PSC/PEX, both dashboard trees and Generate prompt; compiled-PEX and headless sender regressions fail before/pass after offline. No installation, live model or game test.
- Polish Director hints with consistent red required markers and per-field alignment, including Action Execution; enable native vertical textarea resizing. Generate leaves optional people blank without a plausible motive and writes past-tense Story motives instead of scenes. Pair both dashboard trees and shared prompt; headless polish regression fails before/passes after, with default/reroll/Story hints/section/package checks passing. No installation, live model or game test.
- Director Generate re-rolls fields it filled itself and keeps only fields the player typed or picked; larger, brighter hint text; type-specific Story narration examples.
- Require a picked Director political event type on initial load and after Clear; carry faction display names through dashboard/native JSON into Political notices, with IDs retained as the native label fallback. Pair rebuilt DLL, Core PSC/PEX and both dashboard trees; native and compiled-PEX label regressions fail before/pass after, and default dropdown/Story hints/section collapse/folded Packages checks pass headlessly. No installation or live game test.
- Explain all seven Director Story types with type-specific narration and field hints; pass selected-type guidance through the existing Generate schema and prompt. Pair both dashboard trees and shared prompt; headless Story hints/payload regression fails before/passes after and section/package regressions pass. No installation, live model or game test.
- Format Director Story/Social and busy-notice keys as friendly words through the new native `IntelEngine.FriendlyKey`; Political notices retain supplied event labels, format absent-label event keys and identify both sides using friendly faction IDs. Pair rebuilt DLL, IntelEngine/Core PSC and PEX. Native and compiled-Papyrus notice regressions pass offline; no installation or live game test.
- Fold Packages into Tasks: show each active task's matching IE package type and keep orphan-package Remove/Removing controls in collapsible Other IE packages; remove the Packages tab. Pair both dashboard trees; headless built-bundle regression fails before/passes after offline. No native/Papyrus changes, installation or live game test.
- Normalize generated faction display names to IDs; accept dispatch-resolved NPC names and silently skip empty/None identities without replacing chosen ones. Remove example placeholders from Generate metadata, constrain prompt fields by schema and expand collapsed sections on Generate. Add player notices for all three Director NPC lookup failures while retaining debug logs. Pair rebuilt Core PEX, shared prompt and both dashboard bundles; offline regression evidence only, no installation or live game/model test.
- Log Generate replies before parsing (first 600 characters), accept fenced/prose-wrapped JSON objects and include a 120-character excerpt in malformed errors. Pass explicit blank fields to the prompt and require non-empty narration/description suggestions; restore red field-local required stars. Rebuild/pair the DLL, prompt and both dashboard trees; native wrapped-reply and headless red-marker regressions fail before/pass after offline. No installation or live model/game test.
- Make all 20 dashboard sections collapsible with native details/summary, ▾/▸ headings and per-section localStorage persistence; keep header buttons independent. Pair both frontend host trees. Headless built-bundle collapse/reload/header-Generate regression fails before/passes after; no installation or live game testing.
- Include every visible Generate variant blank and request complete flat drafts; validate fields once in the dashboard rather than discarding a whole native/UI result for one invalid field. Preserve chosen/touched values and log per-field rejections. Extended production-bundle/native partial-result regressions fail before/pass after offline; no live model/game claim.
- Add one IntelEngine info line per completed Generate with form/request ID, filled/blank names and actual dashboard applied/rejected outcomes. Headless request/outcome and native log-route checks run offline; no game or installed log writes.
- Use the dashboard political option label in recorded-event notices, retaining the original event key and falling back to it when the label is absent. Native producer checks cover both fields and fallback; Core bytecode rebuilt offline.
- Restore Director section titles and right-aligned small Generate/Clear/Stop buttons; move required markers into field hints while keeping missing-field lists. Headless production-bundle layout and required-field scenario fails before/passes after; no installation or live testing.
- Mark Director required fields from the existing Dispatch validation and list missing fields beneath disabled buttons across Story, NPC Social, Political and Action Execution. Keep Story/Social variant fields unstarred where they do not gate Dispatch; update Action requirements with the selected command. Pair both rebuilt dashboard trees; headless required-field, Generate/Stop/Clear and busy-confirm checks pass offline. No installation or live testing.
- Add Director Generate and Clear for Story, NPC Social and Political forms using one shared optional SkyrimNet custom prompt. Preserve picked identities/touched dropdowns, show untouched choices as `(auto)`, validate generated drafts and never dispatch automatically. Generating locks that form; Stop discards its late result without clearing the draft. Pair the rebuilt DLL, prompt and both dashboard trees. Headless draft/Stop/Clear and native malformed/failure/close-reopen checks pass offline; no installation or live model/game test.
- Extend Director Story notices through the active dispatch-generation signal (including message courier names; road encounters skipped), Social notices after queued/applied outcomes and Political notices on acted=true. Submit buttons show Sent for two seconds, not game acceptance. Pair Core/StoryEngine/Politics PSC/PEX and both rebuilt dashboard trees; named Social/Political and message-generation regressions fail before/pass after offline. No installation or live testing.
- Add return-aware Director notices for the nine Bool-returning actions and seek/informant Story dispatches; failed calls emit no success notice. Preserve cancellation/conduct feedback; skip void Story, NPC Social and Politics paths without new result plumbing. Pair Core PSC/PEX; named compiled success/failure regression fails before and passes after offline, not live-tested.
- Clarify every Director form's common fields and retain per-type/action hints, including message sender/courier roles and gossip teller/listener roles; show existing YAML field descriptions below fallback action inputs. Clarify Debug Mode notifications versus always-on Papyrus logging and Actions Reload configs/next-launch behavior. Pair rebuilt dashboard assets for both hosts and update Native README.
- Add Director busy confirmation for Story, either NPC Social participant and Action Execution using existing active-slot state. First click asks `Busy — you sure?`; second sends slot cancellation(s) then the unchanged dispatch. NPC edits reset confirmation. Pair both dashboard trees; offline built-bundle cancel/dispatch regression fails before and passes after.
- Refresh the open dashboard at shared task-slot allocation and clearing, so Tasks cards appear/disappear without reopening. Closed dashboards skip snapshot building. Pair rebuilt Core PSC/PEX; offline compiled consumers pass, not live-tested.
- Add closing NPC facts before active-story task cancellation, generic load abandonment and six-hour watchdog cleanup. Cancellation skips empty narration. Pair rebuilt Core/StoryEngine PSC/PEX; named cancel regression fails before and passes after offline, without installation or live testing.
- Cancel the active story together with its NPC task through the shared cancellation helper; task-card cancellation now uses that helper. Stop suspended dispatch setup from re-arming tracking or modifying a replacement story. Pair only Core/StoryEngine PSC/PEX; named compiled courier-cancel/replacement regression and existing consumers pass.
- Successful Dashboard task-card cancellation now shows `<Name>'s task cancelled.` after cleanup; empty slots emit no success notice. One-line Core-only source/bytecode update; existing compiled harness passes.
- Refuse a new Director Story while the story engine already owns an active story, preserving the existing courier's context and travel slot. Reuse the Director admission helper; automatic and arrival flows remain unchanged. Core-only PSC/PEX paired; compiled courier-preservation/arrival regression passes.
- Round B P-lite: refuse busy Director Story, NPC Social and task-creating Action Execution requests before task/context writes, with a busy notification. Preserve cancellation, speed/conduct controls and automatic behavior. Pair only rebuilt IntelEngine_Core PSC/PEX; two compiled Director/run6 regressions pass. No native or arrival-flow change.
- Round B Q: reject self-pair relations, seeds, wars and political records at the database boundary; hide legacy same-faction relation rows on read without changing the save format. Preserve one-sided events and same-faction conduct's single standing change. Native SQLite/conduct checks pass; the combined round-B DLL is packaged with S.
- Round B R: show in-game calendar dates/times (nearest minute) on political events, war timelines, battle history and new NPC activity. Preserve absent timestamps as absent, including SQL NULL versus genuine zero; anchor custom-start dates/clocks to the current save and avoid float32 midnight rollover. Native SQLite and built-dashboard boundary checks pass; pair the combined round-B DLL and changed script bytecode.
- Round B S: active and scheduled cards show recorded origin, in-game allocation/creation time and existing dispatch reason. Retain provenance across save recovery without changing co-save format or task timers, and clear it on slot release. SkyrimNet action mappings pass origin only; upstream does not forward triggering dialogue text. Pair the combined Q/R/S DLL and seven rebuilt PSC/PEX pairs; offline producer/UI checks pass, no live verification.
- Round B T: show configured faction leaders on Politics faction cards using the existing native leader list (unloaded names retained, confirmed permanent deaths filtered). Offline built-dashboard checks pass; rebuilt shared assets paired in this item.
- Replace all eight dashboard native dropdown sites with one type-to-filter, pick-from-list combobox for Magelight and PrismaUI, each with a clear button; no plain-select variant. Keep existing choices, nearby actor filters and submitted values; unmatched/unpicked text cannot dispatch. Settings commits only picked numeric hotkeys (clearing edits its draft). Share measured placement with faction suggestions: down whenever the displayed list fits, otherwise up if it fits, otherwise clamp on the larger side. Preserve same-value fields, keyboard selection and current highlighting; dismiss on outside click/focus, containing-pane scroll/resize and Escape (including focus on Clear). Capture Magelight Escape only while a list is open. Rebuilt paired trees; offline Chromium checks only, game-host acceptance pending.
- Localization step 1: action and DM/scheduling prompts require exact in-game/context place names in the game's language without translation; semantic keywords stay English. GoToLocation supplies nearby names through SkyrimNet's `get_place_names("nearby")`. Prompt guidance only: no resolver/Director/SeverActions change or custom named-Place routing; localized-install acceptance pending.
- Follow-up O: register persistent `intel_social`/`intel_story` schemas on load and categorize executed interactions, stored gossip exchanges, seek/informant arrivals, story message/quest-request deliveries and detected-pursuit outcomes. Defer social facts/gossip until arrival in automatic and Director routes; cancelled travel emits no completed outcome and releases pending state. Replace matching generic memories, retain dialogue-driving narration, and leave politics in IntelEngine's tab. Pair rebuilt Core/StoryEngine PSC/PEX; compiled-path checks pass, live acceptance pending. Existing SkyrimNet distance/configuration filters still govern History retention.
- Follow-up N (slim guard): snapshot the story NPC, target, type and dispatch generation; use one shared ownership predicate only before shared-dispatch arrival/abort, slot cleanup and teleport/recovery mutations, not actor-local operations or read-only calls. Preserve latched ambush-combat monitoring, reject missing NPC-to-NPC targets, and leave O's social-arrival latch/outcomes unchanged. Pair rebuilt StoryEngine PSC/PEX. Pre-N PEX fails the cleared-NPC callback-cleanup regression; slim PEX passes arrival/history/cancel and typed-outcome checks. Offline evidence only; no installation/live acceptance.
- Follow-up M: conduct reports use valid faction IDs from the picker, first-choice sentiment defaults and required-field validation. Native processing accepts configured display names via the existing lookup and notifies success counts or exact input/readiness errors. Pair rebuilt DLL and both shared J/M dashboard trees; production-method SQLite and headless UI checks pass, not game-host/live acceptance.
- Follow-up J: custom Director faction suggestions open upward near the viewport bottom. Its initial native NPC/enum selectors and placement rule are superseded by the shared dropdown entry above. Shared rebuilt dashboard assets for J/M are paired in M; offline Chromium geometry checked, game-host acceptance remains pending.
- Follow-up L: Director CancelCurrentTask notifies successful cancellation or no active task; LLM-triggered cancellation is unchanged. Pair rebuilt Core PSC/PEX; compiled Director-event success/repeat checks pass, not live acceptance.
- Follow-up K: unresolved delivery/fetch/search/escort rejections lead with the missing target (`<Target> could not be found.`); preserve existing rejection routing and task safeguards. Pair rebuilt NPCTasks PSC/PEX; compiled-path checks pass, not new live acceptance.
- Follow-up I: reject unresolved/invalid delivery recipients through player notification/log instead of triggering NPC dialogue and a possible unrelated LLM travel action. Validate before replacing an existing task; register departure only after allocation. Resolved distant recipients remain actor targets. Pair rebuilt NPCTasks PSC/PEX; compiled rejection/actor-target checks pass, no new live acceptance.
- Follow-up H: Action Execution includes loaded actors within 4000 units across exterior cell borders in the same worldspace, or within the same interior cell. Preserve alive/enabled/loaded/base filters. Pair the combined rebuilt DLL for F/H; actual-method offline boundary checks pass, not in-game actor-list acceptance.
- Follow-up G: manual Director CancelCurrentTask bypasses only the nearby-player guard and uses full slot/package/link cleanup, including active Travel tasks. SkyrimNet/LLM cancellation retains the default guard. Pair rebuilt Core PSC/PEX with the conduct route from F; compiled-path checks pass, not live acceptance.
- Follow-up F: add the Director ReportPlayerConduct route with the selected NPC as reporter and YAML-defined sentiment choices. Rebuild both dashboard trees and pair the sentiment YAML; the shared Core PSC/PEX is included with G and the combined DLL with H. Offline verification only.
- Follow-up C: latch the shared story arrival entry before side effects so seek-player callback/poll re-entry cannot narrate/clear twice. Reset the latch for fresh dispatches and retain ambush/quest monitoring. Recompiled StoryEngine is paired with follow-up B.
- Follow-up E: filled faction inputs reopen the full list on click/focus, filter while typing, preserve free text, and provide a one-click clear button. Rebuilt both dashboard trees; hidden Chromium interaction checks passed with synthetic state (not in-game host acceptance).
- Follow-up D: Action Execution removes unsupported ReportPlayerConduct and exposes allowlisted parameter-less actions, including CancelCurrentTask. Dashboard assets are paired in follow-up E.
- Same-faction dispatch: reject identical faction IDs in native event, war and direct relation-adjustment paths; disable the Director political button for identical sides. Preserve one-sided events.
- Follow-up B: actor arrival uses a 200u base plus current speed times an estimated 0.50s allowance (150ms polling + 350ms assumed VM/package delay), preserving the 120u Z gate and marker 300u/200u bounds. Retain a claimed threshold through speed-drop rechecks; clear it on disarm/re-arm. Remove the story sandbox's extra 100ms evaluation wait. Run3 confirmed fixed-distance running overshoot; physical stopping still needs live verification. Includes changed PSC/PEX for IntelEngine, NPCTasks and StoryEngine (including C); combined DLL follows in A.
- Absent meeting location: omit the `at none` clause from the shared meeting description used by confirmations and declined-meeting facts.
- Log cleanup: optional response-field misses log at debug through a separate native accessor; required misses and malformed JSON still warn. Log dashboard open, close and refusal at info once per event. Distinguish hotkey/page close; Magelight's generic exit event supplies no Escape-specific reason. Recompiled source retains explicit Bool returns on every `DispatchToTarget` exit.
- Action Execution actors: include non-unique loaded guards/citizens/mod NPCs from the player's cell, preserving availability checks and exact reference FormIDs. Automatic candidate selection is unchanged.
- Follow-up A / #44 task-history wording: recognize known success outcomes case-insensitively at the native Papyrus boundary; retain attempted wording for missing/failed/unknown outcomes. Recompile Core with the raw result appended to its existing cleanup trace. Run3 confirmed the successful-delivery/attempted-history inverse, but its raw result was not captured; source and baseline bytecode show no overwrite between delivery and history. The case-semantics defect is fixed offline; attribution of the live inverse remains open. Includes the combined follow-up DLL. Source/offline/package evidence only, not a live-fix claim.
- Add optional recommended Magelight UI 1.7.1+ dashboard hosting with restart-only `ui.host: auto|magelight|prismaui`, frozen PrismaUI fallback, shared listener/FormID contracts, and Magelight Escape/UI-mode close. Include identical dashboard assets for both hosts; install host runtimes separately. Full DLL build, offline host/identity checks and local-file dashboard smoke passed. No close/notify on dispatch or SkyMessage changes. Installation and live acceptance remain unexecuted.
- Native #42: stage rebuilt `IntelEngine.pex` and `IntelEngine_Core.pex` with exact decimal-string dashboard FormID transport, including FE/FF IDs. Paired with the offline-built identity DLL; no installation or live verification performed.
- Native #41: manual Story and Social Director selections use exact full-name lookup across indexed and currently tracked actor references, independent of automatic candidate pools. Null, mismatched, deleted, disabled and dead references are filtered before ambiguity; same-reference duplicates are accepted, and distinct eligible-reference clashes log both FormIDs. If none are eligible, log the most specific rejection state. Automatic selection remains unchanged and now logs specific rejection branches.
- Native #43: reject empty/reverse/within-word faction-leader name matches, preserve title-prefixed names and player-cell preference, and log matched leader FormIDs at info level. Final paired DLL and both changed PEX compiled successfully; offline identity checks passed. Unloaded story dispatch is supported by the existing off-screen source path but remains unverified live.

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
