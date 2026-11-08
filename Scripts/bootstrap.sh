#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if command -v xcodegen >/dev/null 2>&1; then
  echo "Running xcodegen generate…"
  xcodegen generate
else
  echo "xcodegen not found; install with: brew install xcodegen" >&2
  exit 1
fi

echo "Done. Open Velora.xcodeproj in Xcode."
