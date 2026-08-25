#!/usr/bin/env bash
# run_checks — the single pre-flight gate (§9). Green gate = safe to build/ship.
# Order: refresh the structure doc -> full Core test suite -> app schemes (macOS). Wire into CI.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "== [0/2] Refresh docs/ProjectStructure.md =="
bash "$ROOT/Tooling/print_structure.sh"

echo "== [1/2] Core package tests (pure, runs on Linux or macOS) =="
( cd "$ROOT/Core" && swift test )

# [2/2] App scheme tests — only on macOS with Xcode. Added once AppTarget exists (Week 1).
if command -v xcodebuild >/dev/null 2>&1; then
  echo "== [2/2] App scheme tests (xcodebuild) =="
  echo "   (placeholder — wired up when AppTarget lands in Week 1)"
else
  echo "== [2/2] Skipping xcodebuild (not on macOS) =="
fi

echo "GATE GREEN."
