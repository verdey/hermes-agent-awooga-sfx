#!/usr/bin/env bash
# switch-pack.sh — Switch the active sound pack
# @anchor switch-pack
# @web_safe yes
# @cron_safe no
# @timeout 30
# @param pack_name:text:awooga-tugboat:Pack name to switch to
#
# Usage:
#   switch-pack.sh <pack-name>    # Switch to a specific pack
#   switch-pack.sh --list         # List available packs
#   switch-pack.sh --current      # Show current pack
#   switch-pack.sh --off          # Disable sounds
#   switch-pack.sh --on           # Re-enable sounds

set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
AWOOGA_DIR="${AWOOGA_DIR:-$HERMES_HOME/awooga-sfx}"
ACTIVE_PACK_FILE="$AWOOGA_DIR/active-pack"
DISABLED_FILE="$AWOOGA_DIR/disabled"
PACKS_DIR="$AWOOGA_DIR/packs"
DEFAULT_PACK="awooga-tugboat"

current_pack() {
    [[ -f "$ACTIVE_PACK_FILE" ]] && cat "$ACTIVE_PACK_FILE" 2>/dev/null || echo "$DEFAULT_PACK"
}

list_packs() {
    echo "📋 Available sound packs:"
    local active
    active=$(current_pack)
    [[ -d "$PACKS_DIR" ]] || { echo "  (none installed)"; return; }
    for d in "$PACKS_DIR"/*/; do
        [[ -d "$d" ]] || continue
        local name marker desc=""
        name=$(basename "$d")
        marker="  "
        [[ "$name" == "$active" ]] && marker="← "
        [[ -f "$d/pack.yaml" ]] && desc=$(grep '^description:' "$d/pack.yaml" | sed 's/description:[[:space:]]*//' | tr -d '"' || true)
        echo "  ${marker}${name}  ${desc}"
    done
    [[ -f "$DISABLED_FILE" ]] && echo "  ⚠️  Sounds are currently DISABLED"
}

switch_to() {
    local name="$1"
    [[ -d "$PACKS_DIR/$name" ]] || {
        echo "❌ Pack not found: $name"
        echo "   Use --list to see available packs."
        exit 1
    }
    mkdir -p "$AWOOGA_DIR"
    echo "$name" > "$ACTIVE_PACK_FILE"
    echo "✅ Switched to: $name"
    # Confirmation sound
    local play="$AWOOGA_DIR/src/play-sound.sh"
    [[ -x "$play" ]] && AWOOGA_DIR="$AWOOGA_DIR" "$play" startup &>/dev/null &
}

case "${1:-}" in
    --list|-l)      list_packs ;;
    --current|-c)   current_pack ;;
    --off)          mkdir -p "$AWOOGA_DIR"; touch "$DISABLED_FILE"; echo "🔇 Sounds disabled." ;;
    --on)           rm -f "$DISABLED_FILE"; echo "🔊 Sounds enabled." ;;
    --help|-h)
        echo "Usage: switch-pack.sh <pack-name>"
        echo "       switch-pack.sh --list        # List packs"
        echo "       switch-pack.sh --current     # Show current"
        echo "       switch-pack.sh --off | --on  # Mute / unmute"
        ;;
    "")             echo "❌ Specify a pack name. Use --list to see available." ; exit 1 ;;
    *)              switch_to "$1" ;;
esac
