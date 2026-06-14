#!/usr/bin/env bash
# admin.sh — Interactive admin menu for hermes-agent-awooga-sfx
#
# Usage: admin.sh
#
# Provides an interactive menu for:
#   1. Listing packs
#   2. Switching packs
#   3. Previewing sounds
#   4. Installing CDN packs
#   5. Searching SFX (Freesound)
#   6. Volume control
#   7. Enable/disable sounds
#   8. Diagnostics

set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
AWOOGA_DIR="${AWOOGA_DIR:-$HERMES_HOME/awooga-sfx}"
ACTIVE_PACK_FILE="$AWOOGA_DIR/active-pack"
DISABLED_FILE="$AWOOGA_DIR/disabled"
PACKS_DIR="$AWOOGA_DIR/packs"
DEFAULT_PACK="awooga-tugboat"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PLAY_SCRIPT="$SCRIPT_DIR/play-sound.sh"
SWITCH_SCRIPT="$SCRIPT_DIR/switch-pack.sh"

# ─── Colors ─────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
fi

# ─── Helpers ────────────────────────────────────────────────────────

get_active_pack() {
    if [[ -f "$ACTIVE_PACK_FILE" ]]; then
        cat "$ACTIVE_PACK_FILE" 2>/dev/null || echo "$DEFAULT_PACK"
    else
        echo "$DEFAULT_PACK"
    fi
}

is_enabled() {
    [[ ! -f "$DISABLED_FILE" ]]
}

get_volume() {
    local pack_yaml="$PACKS_DIR/$(get_active_pack)/pack.yaml"
    if [[ -f "$pack_yaml" ]]; then
        grep '^volume:' "$pack_yaml" 2>/dev/null | sed 's/volume: *//' || echo "0.8"
    else
        echo "0.8"
    fi
}

detect_audio_player() {
    if command -v afplay &>/dev/null; then echo "afplay (macOS)"
    elif command -v aplay &>/dev/null; then echo "aplay (ALSA)"
    elif command -v paplay &>/dev/null; then echo "paplay (PulseAudio)"
    elif command -v pw-play &>/dev/null; then echo "pw-play (PipeWire)"
    elif command -v powershell.exe &>/dev/null; then echo "powershell (WSL beep)"
    else echo "none"
    fi
}

# ─── Menu Actions ──────────────────────────────────────────────────

do_list_packs() {
    echo ""
    echo -e "${BOLD}📋 Available Sound Packs${NC}"
    echo ""
    local active_pack
    active_pack=$(get_active_pack)
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
            local sound_count
            sound_count=$(find "$pack_dir" -name '*.wav' 2>/dev/null | wc -l | tr -d ' ')
            echo -e "  ${GREEN}${marker}${NC}${name} ${CYAN}(${sound_count} sounds)${NC} ${desc:+— $desc}"
        done
    else
        echo "  No packs found. Run install.sh first."
    fi
    echo ""
}

do_switch_pack() {
    echo ""
    echo -e "${BOLD}🔀 Switch Sound Pack${NC}"
    echo ""
    local active_pack
    active_pack=$(get_active_pack)
    local packs=()
    if [[ -d "$PACKS_DIR" ]]; then
        for pack_dir in "$PACKS_DIR"/*/; do
            packs+=("$(basename "$pack_dir")")
        done
    fi

    if [[ ${#packs[@]} -eq 0 ]]; then
        echo "  No packs available. Install one first."
        return
    fi

    echo -e "  Current: ${GREEN}${active_pack}${NC}"
    echo ""
    for i in "${!packs[@]}"; do
        local marker="  "
        if [[ "${packs[$i]}" == "$active_pack" ]]; then
            marker="← "
        fi
        echo -e "  ${marker}$((i+1))) ${packs[$i]}"
    done
    echo ""
    echo -n "  Choose pack number (or Enter to cancel): "
    read -r choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#packs[@]}" ]]; then
        "$SWITCH_SCRIPT" "${packs[$((choice-1))]}"
    else
        echo "  Cancelled."
    fi
}

do_preview() {
    echo ""
    echo -e "${BOLD}🔊 Preview Sounds${NC}"
    echo ""
    local active_pack
    active_pack=$(get_active_pack)
    local pack_dir="$PACKS_DIR/$active_pack"

    if [[ ! -d "$pack_dir" ]]; then
        echo "  Pack not found: $active_pack"
        return
    fi

    echo -e "  Pack: ${GREEN}${active_pack}${NC}"
    echo ""

    # Find all WAV files
    for wav in "$pack_dir"/*.wav; do
        [[ -f "$wav" ]] || continue
        local event_name
        event_name=$(basename "$wav" .wav)
        echo -ne "  🔊 Playing ${event_name}... "

        # Use the actual player directly for preview (no cooldown, no hook JSON)
        local player
        player=$(detect_audio_player | awk '{print $1}')
        case "$player" in
            afplay) afplay "$wav" 2>/dev/null ;;
            aplay) aplay -q "$wav" 2>/dev/null ;;
            paplay) paplay "$wav" 2>/dev/null ;;
            pw-play) pw-play "$wav" 2>/dev/null ;;
            powershell) powershell.exe -Command "[Console]::Beep(800,200)" 2>/dev/null ;;
            *) echo "(no audio player)" ;;
        esac
        echo "✅"
    done
    echo ""
}

do_volume() {
    echo ""
    echo -e "${BOLD}🔉 Volume Control${NC}"
    echo ""
    local current_volume
    current_volume=$(get_volume)
    echo -e "  Current volume: ${GREEN}${current_volume}${NC}"
    echo ""
    echo -n "  New volume (0.0 - 1.0, or Enter to cancel): "
    read -r new_volume
    if [[ -n "$new_volume" ]] && [[ "$new_volume" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        # Update volume in active pack's pack.yaml
        local active_pack
        active_pack=$(get_active_pack)
        local pack_yaml="$PACKS_DIR/$active_pack/pack.yaml"
        if [[ -f "$pack_yaml" ]]; then
            if [[ "$(uname)" == "Darwin" ]]; then
                sed -i '' "s/^volume:.*/volume: ${new_volume}/" "$pack_yaml"
            else
                sed -i "s/^volume:.*/volume: ${new_volume}/" "$pack_yaml"
            fi
            echo -e "  ${GREEN}✅ Volume set to ${new_volume}${NC}"
        else
            echo "  Pack config not found."
        fi
    else
        echo "  Cancelled."
    fi
}

do_toggle() {
    echo ""
    if is_enabled; then
        "$SWITCH_SCRIPT" --off
    else
        "$SWITCH_SCRIPT" --on
    fi
}

do_diagnostics() {
    echo ""
    echo -e "${BOLD}🩺 Diagnostics${NC}"
    echo ""

    # Audio player
    echo -ne "  Audio player: "
    local player
    player=$(detect_audio_player)
    if [[ "$player" == "none" ]]; then
        echo -e "${RED}❌ No audio player found${NC}"
    else
        echo -e "${GREEN}✅ ${player}${NC}"
    fi

    # Hermes home
    echo -ne "  HERMES_HOME: "
    if [[ -d "$HERMES_HOME" ]]; then
        echo -e "${GREEN}✅ ${HERMES_HOME}${NC}"
    else
        echo -e "${YELLOW}⚠️  ${HERMES_HOME} not found${NC}"
    fi

    # Awoooga dir
    echo -ne "  AWOOGA_DIR: "
    if [[ -d "$AWOOGA_DIR" ]]; then
        echo -e "${GREEN}✅ ${AWOOGA_DIR}${NC}"
    else
        echo -e "${YELLOW}⚠️  ${AWOOGA_DIR} not found (run install.sh)${NC}"
    fi

    # Packs
    echo -ne "  Sound packs: "
    local pack_count=0
    if [[ -d "$PACKS_DIR" ]]; then
        pack_count=$(find "$PACKS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
    fi
    echo -e "${GREEN}${pack_count} installed${NC}"

    # Active pack
    echo -ne "  Active pack: "
    local active_pack
    active_pack=$(get_active_pack)
    if [[ -d "$PACKS_DIR/$active_pack" ]]; then
        echo -e "${GREEN}✅ ${active_pack}${NC}"
    else
        echo -e "${RED}❌ ${active_pack} (not found)${NC}"
    fi

    # Hooks config
    echo -ne "  Hermes hooks: "
    local config="$HERMES_HOME/config.yaml"
    if [[ -f "$config" ]]; then
        if grep -q 'play-sound' "$config" 2>/dev/null; then
            echo -e "${GREEN}✅ registered in config.yaml${NC}"
        else
            echo -e "${YELLOW}⚠️  not found in config.yaml${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  config.yaml not found${NC}"
    fi

    # Status
    echo -ne "  Sounds: "
    if is_enabled; then
        echo -e "${GREEN}ENABLED${NC}"
    else
        echo -e "${RED}DISABLED${NC}"
    fi

    # Allowlist
    echo -ne "  Hooks allowlist: "
    local allowlist="$HERMES_HOME/shell-hooks-allowlist.json"
    if [[ -f "$allowlist" ]]; then
        local count
        count=$(grep -c 'play-sound' "$allowlist" 2>/dev/null || echo "0")
        echo -e "${GREEN}${count} awoooga entries${NC}"
    else
        echo -e "${YELLOW}not found (will be created on first run)${NC}"
    fi
    echo ""
}

# ─── Main Menu ──────────────────────────────────────────────────────

show_menu() {
    local active_pack
    active_pack=$(get_active_pack)
    local status
    if is_enabled; then
        status="${GREEN}ENABLED${NC}"
    else
        status="${RED}DISABLED${NC}"
    fi
    local volume
    volume=$(get_volume)

    echo ""
    echo -e "${BOLD}🔊 AWOOGA SFX — Sound Pack Manager for Hermes Agent${NC}"
    echo ""
    echo -e "  1) 📋 List packs"
    echo -e "  2) 🔀 Switch pack"
    echo -e "  3) 🔊 Preview sounds"
    echo -e "  4) 📥 Install CDN pack"
    echo -e "  5) 🔍 Search SFX (Freesound)"
    echo -e "  6) 🔉 Volume control"
    echo -e "  7) ✅ Enable/Disable"
    echo -e "  8) 🩺 Diagnostics"
    echo -e "  q) Quit"
    echo ""
    echo -e "  Active pack: ${GREEN}${active_pack}${NC}  |  Volume: ${volume}  |  Status: ${status}"
    echo ""
}

# ─── Main Loop ───────────────────────────────────────────────────────

main() {
    # Ensure we have the minimum directory structure
    mkdir -p "$AWOOGA_DIR" "$PACKS_DIR"

    # If no active pack is set, set the default
    if [[ ! -f "$ACTIVE_PACK_FILE" ]]; then
        echo "$DEFAULT_PACK" > "$ACTIVE_PACK_FILE"
    fi

    while true; do
        show_menu
        echo -n "  Choose [1-8, q]: "
        read -r choice
        case "$choice" in
            1) do_list_packs ;;
            2) do_switch_pack ;;
            3) do_preview ;;
            4)
                echo ""
                echo -e "  ${YELLOW}📥 Install CDN Pack${NC}"
                echo "  Coming soon — use install-pack.sh directly for now."
                echo "  Usage: install-pack.sh <pack-id>"
                echo ""
                ;;
            5)
                echo ""
                echo -e "  ${YELLOW}🔍 Search SFX (Freesound)${NC}"
                echo "  Coming soon — use search-sfx.sh directly for now."
                echo "  Usage: search-sfx.sh <query>"
                echo ""
                ;;
            6) do_volume ;;
            7) do_toggle ;;
            8) do_diagnostics ;;
            q|Q) echo "Bye! 🔊"; exit 0 ;;
            *) echo "  Invalid choice." ;;
        esac
        echo ""
        echo -n "  Press Enter to continue..."
        read -r
    done
}

main