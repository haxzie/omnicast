#!/usr/bin/env bash
# Build and (re)launch Omnicast.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-debug}" ./scripts/build.sh

pkill -x Omnicast 2>/dev/null || true
open build.noindex/Omnicast.app
echo "✓ Omnicast is running — look for the hexagon in the menu bar (⌥Space to search)"
