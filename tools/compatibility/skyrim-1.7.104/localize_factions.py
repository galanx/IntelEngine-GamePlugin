"""Generate a separate Intel faction configuration using names read from the game."""
from pathlib import Path
import argparse
import json
import re

# Skyrim.esm territory LCTN forms, deliberately distinct from the capital cities.
HOLD_FORMS = {
    "ImperialFaction": 0x16770, "StormcloakFaction": 0x1676A,
    "ThalmorFaction": 0x16770, "CompanionsFaction": 0x16772,
    "ThievesGuildFaction": 0x1676C, "CollegeOfWinterholdFaction": 0x1676B,
    "DarkBrotherhoodFaction": 0x1676F, "SilverBloodFamily": 0x16769,
    "BlackBriarFamily": 0x1676C,
}
LEADER_FORMS = {
    "General Tullius": 0x1327E, "Legate Rikke": 0x132A1,
    "Ulfric Stormcloak": 0x1414D, "Galmar Stone-Fist": 0x14128,
    "Elenwen": 0x13269, "Ondolemar": 0x133AF,
    "Kodlak Whitemane": 0x1A68E, "Vilkas": 0x1A694,
    "Mercer Frey": 0x1B07C, "Brynjolf": 0x1B07D,
    "Savos Aren": 0x1C19F, "Mirabelle Ervine": 0x1C1A0,
    "Astrid": 0x1BDB4, "Nazir": 0x1C3AB,
    "Thongvor Silver-Blood": 0x133BB, "Thonar Silver-Blood": 0x133BA,
    "Maven Black-Briar": 0x1336A,
}


def validate_names(values, known):
    if not isinstance(values, dict) or not values or set(values) - set(known):
        raise ValueError("Expected a nonempty map of known faction/leader identifiers")
    if any(not isinstance(name, str) or not name.strip()
           or any(ord(char) < 32 for char in name) for name in values.values()):
        raise ValueError("Expected nonempty single-line engine names")


def translated_config(text, holds, leaders):
    """Preserve rules and identifiers; refuse ambiguous/missing target holds."""
    validate_names(holds, HOLD_FORMS)
    validate_names(leaders, LEADER_FORMS)
    for faction, localized in holds.items():
        header = r'(?m)^[ \t]*-[ \t]*id:[ \t]*"' + re.escape(faction) + r'"[^\r\n]*(?:\r?\n|$)'
        matches = list(re.finditer(header, text))
        if len(matches) != 1:
            raise ValueError("Nonunique default faction hold: " + faction)
        start = matches[0].end()
        next_header = re.search(r"(?m)^[ \t]*-[ \t]*id:", text[start:])
        end = start + next_header.start() if next_header else len(text)
        block = text[start:end]
        keys = list(re.finditer(r"(?m)^[ \t]*hold:", block))
        pattern = r'(?m)^([ \t]*hold:[ \t]*)("(?:[^"\\\r\n]|\\[^\r\n])*")([ \t]*(?:#[^\r\n]*)?)(\r?)$'
        values = list(re.finditer(pattern, block))
        if len(keys) != 1 or len(values) != 1:
            raise ValueError("Nonunique default faction hold: " + faction)
        value = values[0]
        json.loads(value[2])  # Refuse unsupported quoting/escapes before writing.
        block = (block[:value.start(2)] + json.dumps(localized, ensure_ascii=False)
                 + block[value.end(2):])
        text = text[:start] + block + text[end:]
    pattern = r'(?m)^(\s*leader_names: \[)([^\r\n]*)(\])'

    def replace(match):
        values = json.loads("[" + match[2] + "]")
        if not isinstance(values, list) or any(not isinstance(v, str) for v in values):
            raise ValueError("Expected a JSON-compatible leader_names array")
        return match[1] + ", ".join(json.dumps(leaders.get(v, v), ensure_ascii=False)
                                   for v in values) + match[3]

    return re.sub(pattern, replace, text)


def generate(source, names, output):
    """Only create a new output; never overwrite an input or installed config."""
    output = Path(output)
    if output.exists():
        raise FileExistsError("New output file required")
    mapping = json.loads(Path(names).read_text(encoding="utf-8-sig"))
    if set(mapping) != {"hold_names", "leader_names"}:
        raise ValueError("Expected hold_names and leader_names maps")
    result = translated_config(Path(source).read_text(encoding="utf-8-sig"),
                               mapping["hold_names"], mapping["leader_names"])
    with output.open("x", encoding="utf-8", newline="") as stream:
        stream.write(result)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--names", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    generate(args.input, args.names, args.output)
    print("Created a separate localized configuration; no profile was edited.")
