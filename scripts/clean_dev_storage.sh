#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGGRESSIVE=0

case "${1:-}" in
  --aggressive)
    AGGRESSIVE=1
    ;;
  -h|--help)
    cat <<'USAGE'
Usage: scripts/clean_dev_storage.sh [--aggressive]

Default cleanup:
  - Flutter project build output
  - Xcode DerivedData
  - unavailable simulators

Aggressive cleanup also removes:
  - Xcode iOS DeviceSupport caches
  - Xcode Archives
USAGE
    exit 0
    ;;
  "")
    ;;
  *)
    echo "Unknown option: $1" >&2
    exit 2
    ;;
esac

echo "Before cleanup:"
df -h /System/Volumes/Data || true

echo "Removing Flutter build output..."
if command -v flutter >/dev/null 2>&1; then
  (cd "$PROJECT_ROOT" && flutter clean)
else
  rm -rf "$PROJECT_ROOT/build" "$PROJECT_ROOT/.dart_tool"
fi

echo "Removing Xcode DerivedData..."
rm -rf "$HOME/Library/Developer/Xcode/DerivedData"/*

echo "Removing unavailable simulators..."
xcrun simctl delete unavailable >/dev/null 2>&1 || true

if [[ "$AGGRESSIVE" == "1" ]]; then
  echo "Removing Xcode iOS DeviceSupport caches..."
  rm -rf "$HOME/Library/Developer/Xcode/iOS DeviceSupport"/*

  echo "Removing Xcode Archives..."
  rm -rf "$HOME/Library/Developer/Xcode/Archives"/*
fi

echo "After cleanup:"
df -h /System/Volumes/Data || true
