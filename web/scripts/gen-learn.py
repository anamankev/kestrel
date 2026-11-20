"""Generates src/core/learn.generated.ts from the curriculum in KestrelCore/Sources/KestrelCore/Learn.swift."""
import json, pathlib, re
root = pathlib.Path(__file__).resolve().parents[2]
src = (root / "KestrelCore/Sources/KestrelCore/Learn.swift").read_text()
body = re.search(r'// BEGIN CURRICULUM\n\s*static let json = #"""\n(.*?)\n\s*"""#', src, re.S).group(1)
modules = json.loads(body)
out = ["// Generated from KestrelCore/Sources/KestrelCore/Learn.swift by scripts/gen-learn.py. Do not edit by hand.",
       'import type { Module } from "./learn";', "",
       "export const MODULES: Module[] = " + json.dumps(modules, ensure_ascii=False, indent=1) + ";", ""]
(root / "web/src/core/learn.generated.ts").write_text("\n".join(out))
print(len(modules), "modules,", sum(len(m["drills"]) for m in modules), "drills")
