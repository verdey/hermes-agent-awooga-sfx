#!/usr/bin/env bash
# play-sound.sh — Cross-platform sound player for Hermes Agent hooks
# @anchor play-sound
# @web_safe yes
# @cron_safe yes
# @timeout 30
# @param event:select:complete:complete,approval,error,startup,tool_done:Event sound to play
#
# Usage:
#   play-sound.sh <event>           # Play a specific event sound
#   echo '<json>' | play-sound.sh   # Read event from Hermes hook JSON stdin
#
# Events: complete, approval, error, startup, tool_done
#
# Environment:
#   AWOOGA_DIR    — Base directory (default: $HERMES_HOME/awooga-sfx)
#   HERMES_HOME   — Hermes config directory (default: ~/.hermes)
#   AWOOGA_VOLUME — Volume multiplier 0.0-1.0 (default: from pack.yaml or 0.8)
#   AWOOGA_COOLDOWN_MS — Cooldown between identical events in ms (default: from pack.yaml or 3000)

set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
AWOOGA_DIR="${AWOOGA_DIR:-$HERMES_HOME/awooga-sfx}"
ACTIVE_PACK_FILE="$AWOOGA_DIR/active-pack"
COOLDOWN_DIR="$AWOOGA_DIR/cooldown"
PACKS_DIR="$AWOOGA_DIR/packs"

DEFAULT_PACK="awooga-tugboat"
DEFAULT_VOLUME=0.8
DEFAULT_COOLDOWN_MS=3000

# ─── Audio player detection (cached) ───────────────────────────────────

detect_audio_player() {
    local cache_file="/tmp/hermes-awooga-audio-player"
    if [[ -f "$cache_file" ]]; then cat "$cache_file"; return; fi
    local p=""
    for cmd in afplay aplay paplay pw-play powershell.exe; do
        if command -v "$cmd" &>/dev/null; then p="$cmd"; break; fi
    done
    if [[ -n "$p" ]]; then echo "$p" | tee "$cache_file"; return; fi
    return 1
}

# ─── Play WAV asynchronously ───────────────────────────────────────────

play_wav() {
    local file="$1" volume="${2:-$DEFAULT_VOLUME}"
    local player
    player=$(detect_audio_player) || return 0  # silent fallback
    case "$player" in
        afplay)       nohup afplay -v "$volume" "$file" &>/dev/null & ;;
        aplay)        nohup aplay -q "$file" &>/dev/null & ;;
        paplay)       nohup paplay "$file" &>/dev/null & ;;
        pw-play)      nohup pw-play "$file" &>/dev/null & ;;
        powershell*)  nohup powershell.exe -Command "[Console]::Beep(800,200)" &>/dev/null & ;;
    esac
    disown 2>/dev/null || true
}

# ─── Pack config helpers ───────────────────────────────────────────────

read_pack_yaml_key() {
    # Usage: read_pack_yaml_key <pack.yaml> <key> <default>
    local yaml="$1" key="$2" default="$3"
    if [[ -f "$yaml" ]]; then
        local v
        v=$(grep -E "^${key}:" "$yaml" 2>/dev/null | head -1 | sed "s/^${key}:[[:space:]]*//" | tr -d '"' || true)
        [[ -n "$v" ]] && echo "$v" || echo "$default"
    else
        echo "$default"
    fi
}

# ─── Cooldown ──────────────────────────────────────────────────────────

check_cooldown() {
    local event="$1" cooldown_ms="$2"
    mkdir -p "$COOLDOWN_DIR"
    local f="$COOLDOWN_DIR/$event"
    local now_ms=$(( $(date +%s) * 1000 ))
    if [[ -f "$f" ]]; then
        local last_ms elapsed_ms
        last_ms=$(cat "$f" 2>/dev/null || echo 0)
        elapsed_ms=$(( now_ms - last_ms ))
        if [[ $elapsed_ms -lt $cooldown_ms ]]; then return 1; fi
    fi
    echo "$now_ms" > "$f"
    return 0
}

# ─── Event resolution ──────────────────────────────────────────────────

resolve_event() {
    # 1) explicit argument
    if [[ $# -gt 0 && -n "$1" ]]; then echo "$1"; return; fi
    # 2) Hermes hook JSON on stdin
    local stdin_data
    stdin_data=$(cat 2>/dev/null) || true
    if [[ -n "$stdin_data" ]]; then
        local e
        e=$(echo "$stdin_data" | grep -oE '"hook_event_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
        if [[ -n "$e" ]]; then echo "$e"; return; fi
    fi
    # 3) default
    echo "complete"
}

map_event() {
    case "$1" in
        post_llm_call)        echo "complete" ;;
        on_session_end)       echo "complete" ;;
        pre_approval_request) echo "approval" ;;
        on_session_start)     echo "startup" ;;
        post_tool_call)       echo "tool_done" ;;
        complete|approval|error|startup|tool_done) echo "$1" ;;
        *)                    echo "complete" ;;
    esac
}

# ─── Main ──────────────────────────────────────────────────────────────

main() {
    # Disabled? Silent no-op.
    [[ -f "$AWOOGA_DIR/disabled" ]] && { echo "{}"; return 0; }

    # Active pack.
    local pack_name
    if [[ -f "$ACTIVE_PACK_FILE" ]]; then
        pack_name=$(cat "$ACTIVE_PACK_FILE" 2>/dev/null || echo "$DEFAULT_PACK")
    else
        pack_name="$DEFAULT_PACK"
    fi

    local pack_dir="$PACKS_DIR/$pack_name"
    local pack_yaml="$pack_dir/pack.yaml"
    [[ ! -d "$pack_dir" ]] && { echo "{}"; return 0; }

    # Resolve event.
    local raw_event sound_event
    raw_event=$(resolve_event "$@")
    sound_event=$(map_event "$raw_event")

    # Find WAV (pack.yaml mapping wins, else convention).
    local wav_file="$pack_dir/$sound_event.wav"
    if [[ ! -f "$wav_file" && -f "$pack_yaml" ]]; then
        local mapped
        mapped=$(grep -E "^  ${sound_event}:" "$pack_yaml" | sed 's/.*:[[:space:]]*//' | tr -d '"' || true)
        if [[ -n "$mapped" && -f "$pack_dir/$mapped" ]]; then
            wav_file="$pack_dir/$mapped"
        else
            echo "{}"; return 0  # no sound for this event
        fi
    fi

    # Cooldown.
    local cooldown_ms
    cooldown_ms=$(read_pack_yaml_key "$pack_yaml" "cooldown_ms" "$DEFAULT_COOLDOWN_MS")
    check_cooldown "$sound_event" "$cooldown_ms" || { echo "{}"; return 0; }

    # Play.
    local volume
    volume=$(read_pack_yaml_key "$pack_yaml" "volume" "$DEFAULT_VOLUME")
    play_wav "$wav_file" "$volume"

    # Hermes shell hooks require valid JSON on stdout.
    echo "{}"
}

main "$@"
