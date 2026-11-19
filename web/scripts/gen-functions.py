"""Generates src/core/functions.generated.ts from KestrelCore/Sources/KestrelCore/Command.swift."""
import re, pathlib
root = pathlib.Path(__file__).resolve().parents[2]
src = (root / "KestrelCore/Sources/KestrelCore/Command.swift").read_text()
enum = src[src.index("enum TerminalFunction"):src.index("public var title")]
cases = re.findall(r'(\w+) = "([A-Z&?]+)"', enum)
titles = dict(re.findall(r'case \.(\w+): "([^"]+)"', src[src.index("public var title"):src.index("public var requiresSecurity")]))
req = src[src.index("public var requiresSecurity"):src.index("static let aliases")]
needs = set(re.findall(r'\.(\w+)', req.split(": true")[0]))
alias_block = src[src.index("static let aliases"):src.index("public static func from")]
aliases = re.findall(r'"([^"]+)": \.(\w+)', alias_block)
code = {name: raw for name, raw in cases}
lines = ["// Generated from KestrelCore/Sources/KestrelCore/Command.swift by scripts/gen-functions.py. Do not edit by hand.",
         "export interface FunctionInfo { code: string; title: string; needsSecurity: boolean }", "", "export const functions: FunctionInfo[] = ["]
for name, raw in cases:
    lines.append(f'  {{ code: "{raw}", title: "{titles[name]}", needsSecurity: {"true" if name in needs else "false"} }},')
lines += ["];", "", "/** Alternate mnemonics accepted on the command line. */",
          "export const aliases: Record<string, string> = { " + ", ".join(f'"{a}": "{code[n]}"' for a, n in aliases) + " };", ""]
(root / "web/src/core/functions.generated.ts").write_text("\n".join(lines))
print(len(cases), "functions,", len(aliases), "aliases")
