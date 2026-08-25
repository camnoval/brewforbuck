#!/usr/bin/env bash
# generate_brand_table — turn Tooling/Data/beverages.json into a compiled, Foundation-free Swift
# table (§9 codegen). Run this whenever you edit beverages.json. Requires python3 (ships with the
# Xcode command-line tools). The generated file is committed so `swift build` needs no JSON parsing.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JSON="$ROOT/Tooling/Data/beverages.json"
OUT="$ROOT/Core/Sources/CoreContracts/GeneratedBrandTable.swift"

python3 - "$JSON" "$OUT" <<'PY'
import json, sys

json_path, out_path = sys.argv[1], sys.argv[2]
data = json.load(open(json_path))
brands = data["brands"]

ALLOWED = {"draftBeer","bottledBeer","cider","wineGlass","sangria","cocktail",
           "frozenCocktail","martini","shot","seltzer","nonAlcoholic","unknown"}

seen, rows = set(), []
for b in brands:
    label = b["name"]
    key = label.lower()
    cat = b["category"]
    abv = float(b["abv"])
    if cat not in ALLOWED:
        sys.exit(f"ERROR: unknown category '{cat}' for '{label}'")
    if key in seen:
        sys.exit(f"ERROR: duplicate brand key '{key}'")
    seen.add(key)
    rows.append((key, label, cat, abv))

# Most-specific-first: longer keys win so 'corona light' beats 'corona'.
rows.sort(key=lambda r: len(r[0]), reverse=True)

def esc(s): return s.replace("\\", "\\\\").replace('"', '\\"')

lines = []
lines.append("import CoreModel")
lines.append("")
lines.append("// AUTO-GENERATED — DO NOT EDIT BY HAND.")
lines.append("// Source of truth: Tooling/Data/beverages.json")
lines.append("// Regenerate: bash Tooling/generate_brand_table.sh")
lines.append(f"// {len(rows)} brands, sorted by descending match-key length (most specific wins).")
lines.append("")
lines.append("struct BrandEntry: Sendable {")
lines.append("    let key: String        // lowercased substring matched against the drink name")
lines.append("    let label: String      // display name shown in the estimate note")
lines.append("    let category: BeverageCategory")
lines.append("    let abv: Double        // percent")
lines.append("}")
lines.append("")
lines.append("let generatedBrandTable: [BrandEntry] = [")
for key, label, cat, abv in rows:
    lines.append(f'    BrandEntry(key: "{esc(key)}", label: "{esc(label)}", category: .{cat}, abv: {abv}),')
lines.append("]")

open(out_path, "w").write("\n".join(lines) + "\n")
print(f"wrote {out_path} ({len(rows)} brands)")
PY