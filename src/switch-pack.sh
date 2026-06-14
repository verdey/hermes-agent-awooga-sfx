#!/usr/bin/env bash
# switch-pack.sh — Switch the active sound pack
#
# Usage:
#   switch-pack.sh <pack-name>    # Switch to a specific pack
#   switch-pack.sh --off          # Disable sounds
#   switch-pack.sh --list         # List available packs
#   switch-pack.sh --current      # Show current pack
#   switch-pack.sh --on           # Re-enable sounds (if disabled)

set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
AWOOGA_DIR="${AWOOGA_DIR:-$HERMES_HOME/awooga-sfx}"
ACTIVE_PACK_FILE="$AWOOGA_DIR/active-pack"
DISABLED_FILE="$AWOOGA_DIR/disabled"
PACKS_DIR="$AWOOGA_DIR/packs"
DEFAULT_PACK="awooga-tugboat"

list_packs() {
    echo "📋 Available sound packs:"
    echo ""
    local active_pack="$DEFAULT_PACK"
    if [[ -f "$ACTIVE_PACK_FILE" ]]; then
        active_pack=$(cat "$ACTIVE_PACK_FILE" 2>/dev/null || echo "$DEFAULT_PACK")
    fi
    if [[ -d "$PACKS_DIR" ]]; then
        for pack_dir in "$PACKS_DIR"/*/; do
            local name
            name=$(basename "$pack_dir")
            local marker="  "
            if [[ "$name" == "$active_pack" ]]; then
                marker="← "
            fi
            local desc=""
            if [[ -f "$pack_dir/pack.yaml" ]]; then
                desc=$(grep '^description:' "$pack_dir/pack.yaml" 2>/dev/null | sed 's/description: *//' | tr -d '"' || true)
            fi
            echo "  ${marker}${name}  ${desc}"
        done
    fi
    echo ""
    if [[ -f "$DISABLED_FILE" ]]; then
        echo "  ⚠️  Sounds are currently DISABLED"
    fi
}

show_current() {
    local active_pack="$DEFAULT_PACK"
    if [[ -f "$ACTIVE_PACK_FILE" ]]; then
        active_pack=$(cat "$ACTIVE_PACK_FILE" 2>/dev/null || echo "$DEFAULT_PACK")
    fi
    echo "$active_pack"
}

switch_to() {
    local pack_name="$1"

    if [[ ! -d "$PACKS_DIR/$pack_name" ]]; then
        echo "❌ Pack not found: $pack_name"
        echo "   Available packs:"
        ls -1 "$PACKS_DIR" 2>/dev/null | sed 's/^/     /'
        exit 1
    fi

    mkdir -p "$AWOOGA_DIR"
    echo "$pack_name" > "$ACTIVE_PACK_FILE"

    # Play startup sound as confirmation
    PLAY_SCRIPT="$(cd "$(dirname "$0")" && pwd)/play-sound.sh"
    if [[ -x "$PLAY_SCRIPT" ]]; then
        AWOOGA_DIR="$AWOOGA_DIR" "$PLAY_SCRIPT" startup &>/dev/null &
    fi

    local desc=""
    if [[ -f "$PACKS_DIR/$pack_name/pack.yaml" ]]; then
        desc=$(grep '^description:' "$PACKS_DIR/$pack_name/pack.yaml" 2>/dev/null | sed 's/description: *//' | tr -d '"' || true)
    fi
    echo "✅ Switched to: $pack_name ${desc:+— $desc}"
}

disable_sounds() {
    mkdir -p "$AWOOGA_DIR"
    touch "$DISABLED_FILE"
    echo "🔇 Sounds disabled. Use --on to re-enable."
}

enable_sounds() {
    rm -f "$DISABLED_FILE"
    echo "🔊 Sounds enabled."
}

# ─── Main ───────────────────────────────────────────────────────────

case "${1:-}" in
    --list|-l)
        list_packs
        ;;
    --current|-c)
        show_current
        ;;
    --off)
        disable_sounds
        ;;
    --on)
        enable_sounds
        ;;
    --help|-h)
        echo "Usage: switch-pack.sh <pack-name>"
        echo "       switch-pack.sh --off      # Disable sounds"
        echo "       switch-pack.sh --on       # Re-enable sounds"
        echo "       switch-pack.sh --list     # List available packs"
        echo "       switch-pack.sh --current  # Show current pack"
        ;;
    "")
        echo "❌ Please specify a pack name. Use --list to see available packs."
        exit 1
        ;;
    *)
        switch_to "$1"
        ;;
esac