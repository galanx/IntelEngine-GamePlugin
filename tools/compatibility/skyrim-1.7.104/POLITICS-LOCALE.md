# Localized political inputs: source fix and bounded validation

This is an experimental source/configuration correction accompanying the native
1.7.104 candidate. It does not require a French-specific native DLL and does not
change the shared SkyrimNet prompt, vanilla records, relations, cooldowns,
probabilities, or battle limits.

## Why physical consequences were absent

The native manifestation gate compares the player territory name with the
configured faction `hold`, or finds a named leader nearby. The shipped config
uses city labels in several of those fields. City and territory are different
locations: Solitude is in Haafingar, while Windhelm is in Eastmarch (Estemarche
in the tested game). The gate also reads localized engine names, so English
leader strings can fail to identify their translated counterparts.

Separately, native resolution of the canonical battle location `Whiterun`
returned no location in the French game, while `Blancherive` resolved to
Skyrim.esm LCTN `018A56`. Falling back to a different city while keeping the
original narrative produced inconsistent consequences.

## Source changes

`Source/Scripts/IntelEngine_Locale.psc` resolves nine canonical capital names
through stable Skyrim.esm LCTN forms and their actual `Form.GetName()` values.
One line in `IntelEngine_Politics.OnPoliticalDMResponse` normalizes the input
before the original native processor.

The helper parses with JContainers only to read the root `battle_location`.
It substitutes a single literal value without serializing the envelope: the
JContainers serializer converts JSON booleans into integers, which broke an
earlier rejected candidate. The tested flat responses preserve unknown/missing locations, invalid JSON
and duplicate literal keys for the original validator, and retain unrelated
JSON bytes/types. This is not a general root-key tokenizer: an escaped root
key together with a literal nested battle_location key can make the global
literal search select the nested value. That uncommon shape is outside the
verified input contract and remains an explicit limitation of this experimental
helper; use plain, unescaped top-level keys. No general guarantee for arbitrary
nested/escaped JSON is claimed.

This is deliberately limited to nine capital aliases. It does not translate
all villages, arbitrary mod locations, narration, or NPC dialogue.

Compile **both** `IntelEngine_Locale.psc` and `IntelEngine_Politics.psc` with your
existing Papyrus build and the original IntelEngine/dependency imports (SKSE,
JContainers, PapyrusUtil, SkyrimNet and the existing mod dependencies). Install
only the two resulting PEX overrides into a disposable test profile. Keep the
other original IntelEngine scripts. No PEX is added by this proposal.

After UTF-8 decoding and CRLF-to-LF normalization, the helper source SHA-256 is
`678e9ab062bd090180ec73166cd62662585bc9c809fd99a30967d5ea37501ec8`.
The corresponding normalized Politics source SHA-256 is
`89c40602619558ed46154fa78caaa6366d6dc6c097dc867e8e858ef5a18dacf7`.
Both sources compiled successfully in the private test build; the delivered
source contents match that tested build. Compiled hashes are toolchain-specific.
Compile-only interfaces extracted from the author declarations were used to
avoid recursively compiling unrelated author bodies; no substitute Core,
Battle, or StoryEngine implementation was installed.

## Explicit faction-configuration generation

`localize_factions.py` reads a configuration and a supplied names JSON file,
then creates a **new output file**. It never discovers a profile, edits one,
overwrites an existing file, or issues a game command.

```console
python tools/compatibility/skyrim-1.7.104/localize_factions.py --input SKSE/Plugins/SkyrimNet/config/plugins/IntelEngine/factions.sample.yaml --names tools/compatibility/skyrim-1.7.104/faction-names.fr.example.json --output /path/to/NEW-factions.yaml
```

For an existing private profile, use its active config as input so custom rules
are retained. Review the output before placing it in that profile as
`SKSE/Plugins/SkyrimNet/config/plugins/IntelEngine/factions.yaml`, then restart
or invoke the original `IntelEngine.ReloadFactionConfig()` API. Preserve a
backup. The tool accepts the shipped quoted-faction/inline-leader-list syntax;
a different hold layout fails rather than matching the following faction.
It is a bounded transformer, not a general YAML editor.

The example JSON is an **observed engine-name snapshot**, not a universal French
translation. Some territory names in that tested stack remained English.
Check the `HOLD_FORMS` (territories, not cities) and `LEADER_FORMS` NPC bases via
`Game.GetFormFromFile(id, "Skyrim.esm").GetName()` in the actual winning load
order, then supply your own names file if necessary. Identifiers, custom
leaders and all non-target settings are preserved.

## Reproduction and results

Run the 17 standard-library tests from the repository root:

```console
python -m unittest discover -s tools/compatibility/skyrim-1.7.104 -p "test_*.py" -v
```

Those tests exercise the native patch/converter and config generator; they do
not execute Papyrus. Seven separate real-engine helper regressions checked:

| Input | Observed result |
| --- | --- |
| Whiterun with true, false, numbers, array and narrative | Only battle_location becomes Blancherive; every unrelated byte/type is retained |
| Whiterun with should_act false | Location translated; false remains a JSON boolean |
| Unknown capital | Unchanged |
| No battle_location | Unchanged |
| Windhelm | Vendeaume |
| Invalid JSON | Unchanged |
| Duplicate battle_location keys | Unchanged |

After correcting the config, native manifestation returned instructions and a
forced Director `border_skirmish` created six new soldiers absent from the
baseline actor census. No direct SpawnBattleSoldiers, StartCombat, DamageAV or
Kill call was used to manufacture the result.

In the combined profile, five living new actors had opposing combat targets;
sampled health included an Imperial at 32.11668/50 and a Stormcloak at
40.88000/50. The sixth actor was already dead at the sample; its cause is unknown
and is not attributed to combat. A screenshot was a single visual sample,
not a recording proving every spawn point or complete fight.

An IntelEngine travel task and a SeverActions follow task were assigned to
separate disposable actors. Their slots/packages stayed with their own
controllers during the event. Both tasks restored after explicit live
cancellation and loading a private save. The political relation changed from
-30 to -38; after a temporary diagnostic live adjustment to -37, reloading the
save restored -38 and both tasks. This distinguishes restored state from a
check that accidentally reads the pre-load values.

These observations cover one forced skirmish and selected saved tasks in an
isolated combined profile. They do not prove general controller compatibility,
autonomous LLM decisions, a full ceremony/reconstruction, or a long playthrough.

## Comparison with Gerkinfeltser v3.5.2

This comparison pins the game package to
[ee1099d](https://github.com/Gerkinfeltser/IntelEngine-GamePlugin/tree/ee1099d18f0f41f20b79d3799791d134e2012802)
and native source to
[0a99931](https://github.com/Gerkinfeltser/IntelEngine-NativePlugin/tree/0a9993194a231b91b30130d896c332f6795fecbf).
The fetched main branches pointed to those same commits at inspection time.
No build or runtime test of that fork is claimed here.

Its rebuilt native DLL and pinned CommonLib handle the newer runtime/Address
Library layouts directly, including additional ABI work beyond our four
original-binary edits. Its package also migrates actions/prompts to the Beta25+
external bundle. That is a better basis for continued source maintenance than
extending the old binary fallback; our patch tool is not for its different DLL.

The release still passes the raw political response to native processing,
and its sample faction config retains city labels/English leader names.
Native hold matching still compares the displayed territory name exactly;
leader lookup uses the displayed-name index. The localized input/configuration
contribution therefore remains complementary. The source diff for the helper
and one-line handler change applies cleanly to the v3.5.2 package checkout;
this is an applicability check, not an in-game compatibility result.

The native source also confirms the off-screen replay issue described below:
RecordOffScreenBattle records a war_battles row and directly adjusts relation,
while the reload recalculation resets the score and replays faction_events.
No event for that additional battle penalty is recorded on that path. This is
a static source finding on the inspected version, not a runtime test of its
release. The hold field is also used as a fallback travel destination, so a
correct territory-name comparison alone is not proof of a good spawn location.

## Open defects: do not claim these are fixed

- **Off-screen relation replay:** native battle resolution writes army/morale
  and applies a -10 relation change without a matching durable faction event.
  Reload recalculates relations from events and loses that delta. The same
  behavior is present in the inspected original DLL; it is not established as
  a regression of the runtime port. A separate manual -22 diagnostic adjustment
  was also unjournaled, but is a test precondition, not that battle defect.
  A correct native fix needs durable exactly-once replay and migration handling;
  no fabricated event, SQLite rewrite or disabled recalculation is provided.
- **MessageBox:** the helper DLL requires a rebuild for the newer Address
  Library. It was disabled in the private profile. Intel menus relying on it
  remain untested, even though the tested tasks/political interfaces work.
- **Other integrations:** Organic Factions alias/cast warnings remain, and
  automatic Intel Story/NPCDM LLM calls failed. No success is claimed for those
  systems. An unrelated custom weather prompt had a parser failure and was
  left unchanged. The co-loaded custom modules were not modified to make this
  experiment pass.

The principal profile, its saves and original modules were not changed. This
proposal contains no private configuration, credentials, raw logs, saves,
address-library table, additional DLL/PEX, or decompiled source.
