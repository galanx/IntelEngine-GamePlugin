"""Offline guard check against real native outputs; requires clang++.

Usage: python tests/StoryTypeFilteringCheck.py <native-repo>
Compiles BuildExcludeList verbatim and translates the Papyrus guard's string
concatenation/Find expression, without a game VM. Papyrus compilation is separate.
"""
import pathlib
import re
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
native = pathlib.Path(sys.argv[1])
source = (native / "SKSE/src/FactionPolitics.cpp").read_text(encoding="utf-8")
start = source.index("    std::string FactionPolitics::BuildExcludeList(")
end = source.index("\n    }", start) + len("\n    }")
method = source[start:end].replace("FactionPolitics::", "")
script = (root / "Source/Scripts/IntelEngine_StoryEngine.psc").read_text(encoding="utf-8")
guard = script.split("Bool Function AllStoryTypesExcluded(String excludeList)\n", 1)[1].split("EndFunction", 1)[0]
guard = "\n".join(line.split(";", 1)[0] for line in guard.splitlines())
guard = guard.replace("\\\n", "\n").replace("String types =", "std::string types =")
guard = re.sub(r'StringUtil.Find\(types, ("[^"]*")\) >= 0', r'types.find(\1) != std::string::npos', guard)
guard = guard.replace('\n    return', ';\n    return').rstrip() + ";"
with tempfile.TemporaryDirectory(prefix="story-type-filtering-") as directory:
    work = pathlib.Path(directory)
    cpp = work / "check.cpp"
    cpp.write_text('''#include <cassert>
#include <iostream>
#include <string>
#include <vector>
''' + method + '\nbool AllStoryTypesExcluded(std::string excludeList) {\n' + guard + '''
}
int main() {
    for (int toggles = 0; toggles < (1 << 14); ++toggles) {
        for (int env = 0; env < 4; ++env) {
            int available = toggles & 255;
            if (env & 1) available &= ~((1 << 2) | (1 << 3) | (1 << 4) | (1 << 7));
            if (env & 2) available &= ~(1 << 1);
            assert(AllStoryTypesExcluded(BuildExcludeList(toggles, env)) == (available == 0));
        }
    }
    std::cout << "PASS: 65536 real BuildExcludeList toggle/environment outputs; exact top-level matching\\n";
}
''', encoding="utf-8")
    exe = work / "check.exe"
    subprocess.run(["clang++", "-std=c++20", "-Wall", "-Wextra", "-Werror", str(cpp), "-o", str(exe)], check=True)
    subprocess.run([str(exe)], check=True)
