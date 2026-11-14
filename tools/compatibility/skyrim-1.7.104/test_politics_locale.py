"""Standard-library regressions for the opt-in faction-config generator."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("localize_factions", HERE / "localize_factions.py")
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)

BASE = '''factions:
  - id: "ImperialFaction"
    hold: "Solitude"
    name: "Imperial Legion"
    leader_names: ["General Tullius", "A custom leader"]
    war_threshold: -50
  - id: "CustomFaction"
    hold: "Other"
'''
HOLDS = {"ImperialFaction": "Haafingar"}
LEADERS = {"General Tullius": "Général Tullius"}


class ConfigLocaleTests(unittest.TestCase):
    def test_targeted_changes_preserve_rules_and_custom_values(self):
        result = module.translated_config(BASE, HOLDS, LEADERS)
        self.assertIn('hold: "Haafingar"', result)
        self.assertIn('leader_names: ["Général Tullius", "A custom leader"]', result)
        self.assertIn('name: "Imperial Legion"', result)
        self.assertIn("war_threshold: -50", result)
        self.assertIn('id: "CustomFaction"\n    hold: "Other"', result)
        self.assertEqual(module.translated_config(result, HOLDS, LEADERS), result)

    def test_missing_duplicate_or_following_faction_hold_refused(self):
        block = '  - id: "ImperialFaction"\n    hold: "Solitude"\n'
        for text in ["factions: []", block + block,
                     '  - id: "ImperialFaction"\n  - id: "CustomFaction"\n    hold: "Other"\n']:
            with self.subTest(text=text), self.assertRaisesRegex(ValueError, "Nonunique"):
                module.translated_config(text, HOLDS, LEADERS)

    def test_duplicate_hold_or_incomplete_duplicate_id_refused(self):
        duplicate_hold = BASE.replace('    hold: "Solitude"', '    hold: "Solitude"\n    hold: "Windhelm"')
        duplicate_id = BASE + '  - id: "ImperialFaction"\n    name: "Incomplete"\n'
        for text in [duplicate_hold, duplicate_id]:
            with self.subTest(text=text), self.assertRaisesRegex(ValueError, "Nonunique"):
                module.translated_config(text, HOLDS, LEADERS)

    def test_existing_escaped_hold_consumed_completely(self):
        old = json.dumps('A "quoted" place')
        text = BASE.replace('"Solitude"', old + " # preserve comment")
        result = module.translated_config(text, HOLDS, LEADERS)
        self.assertIn('hold: "Haafingar" # preserve comment', result)
        self.assertNotIn("quoted", result)

    def test_invalid_names_are_rejected(self):
        for values in [{}, {"Unknown": "X"}, {"ImperialFaction": "A\nB"},
                       {"ImperialFaction": 1}, {"ImperialFaction": ""}]:
            with self.subTest(values=values), self.assertRaises(ValueError):
                module.translated_config(BASE, values, LEADERS)

    def test_quoted_names_are_serialized_safely(self):
        result = module.translated_config(BASE, HOLDS, {"General Tullius": 'Tullius "test"'})
        array = next(line.split(":", 1)[1] for line in result.splitlines()
                     if "leader_names:" in line)
        self.assertEqual(json.loads(array), ['Tullius "test"', "A custom leader"])

    def test_generate_creates_side_output_and_preserves_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, names, output = [root / name for name in ("source.yaml", "names.json", "out.yaml")]
            source.write_text(BASE, encoding="utf-8")
            names.write_text(json.dumps({"hold_names": HOLDS, "leader_names": LEADERS}), encoding="utf-8")
            original = (source.read_bytes(), names.read_bytes())
            module.generate(source, names, output)
            self.assertIn('hold: "Haafingar"', output.read_text(encoding="utf-8"))
            self.assertEqual((source.read_bytes(), names.read_bytes()), original)
            with self.assertRaises(FileExistsError):
                module.generate(source, names, output)
            with self.assertRaises(FileExistsError):
                module.generate(source, names, source)
            self.assertEqual((source.read_bytes(), names.read_bytes()), original)

    def test_invalid_input_creates_no_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, names, output = [root / name for name in ("source.yaml", "names.json", "out.yaml")]
            source.write_text("factions: []", encoding="utf-8")
            names.write_text(json.dumps({"hold_names": HOLDS, "leader_names": LEADERS}), encoding="utf-8")
            with self.assertRaises(ValueError):
                module.generate(source, names, output)
            self.assertFalse(output.exists())

    def test_example_uses_territory_forms_and_all_default_factions(self):
        self.assertEqual(module.HOLD_FORMS["ImperialFaction"], 0x16770)
        self.assertEqual(module.HOLD_FORMS["StormcloakFaction"], 0x1676A)
        example = json.loads((HERE / "faction-names.fr.example.json").read_text(encoding="utf-8"))
        self.assertEqual(set(example["hold_names"]), set(module.HOLD_FORMS))
        self.assertEqual(set(example["leader_names"]), set(module.LEADER_FORMS))
        sample = HERE.parents[2] / "SKSE/Plugins/SkyrimNet/config/plugins/IntelEngine/factions.sample.yaml"
        result = module.translated_config(sample.read_text(encoding="utf-8-sig"),
                                          example["hold_names"], example["leader_names"])
        self.assertIn('hold: "Estemarche"', result)
        self.assertIn('hold: "Haafingar"', result)


if __name__ == "__main__":
    unittest.main()
