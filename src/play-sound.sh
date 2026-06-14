#!/usr/bin/env bash
# play-sound.sh — Cross-platform sound player for Hermes Agent hooks
#
# Usage:
#   play-sound.sh <event>           # Play a specific event sound
#   echo '<json>' | play-sound.sh   # Read event from Hermes hook JSON stdin
#
# Events: complete, approval, error, startup, tool_done
#
# Environment:
#   AWOOGA_DIR    — Base directory for awoooga-sfx (default: $HERMES_HOME/awooga-sfx)
#   HERMES_HOME   — Hermes config directory (default: ~/.hermes)
#   AWOOGA_VOLUME — Volume multiplier 0.0-1.0 (default: from pack.yaml or 0.8)
#   AWOOGA_COOLDOWN_MS — Cooldown between identical events in ms (default: from pack.yaml or 3000)

set -euo pipefail

# ─── Paths ──────────────────────────────────────────────────────────

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
AWOOGA_DIR="${AWOOGA_DIR:-$HERMES_HOME/awooga-sfx}"
ACTIVE_PACK_FILE="$AWOOGA_DIR/active-pack"
COOLDOWN_DIR="$AWOOGA_DIR/cooldown"
PACKS_DIR="$AWOOGA_DIR/packs"

# ─── Defaults ────────────────────────────────────────────────────────

DEFAULT_VOLUME=0.8
DEFAULT_COOLDOWN_MS=3000
DEFAULT_PACK="awooga-tugboat"

# ─── Detect audio player ────────────────────────────────────────────

detect_audio_player() {
    # Check cache first
    local cache_file="/tmp/hermes-awooga-audio-player"
    if [[ -f "$cache_file" ]]; then
        cat "$cache_file"
        return 0
    fi

    local player=""
    if command -v afplay &>/dev/null; then
        player="afplay"
    elif command -v aplay &>/dev/null; then
        player="aplay"
    elif command -v paplay &>/dev/null; then
        player="paplay"
    elif command -v pw-play &>/dev/null; then
        player="pw-play"
    elif command -v powershell.exe &>/dev/null; then
        player="powershell"
    fi

    if [[ -n "$player" ]]; then
        echo "$player" | tee "$cache_file"
        return 0
    fi

    return 1
}

# ─── Play a WAV file ────────────────────────────────────────────────

play_wav() {
    local file="$1"
    local player

    player=$(detect_audio_player) || {
        # No audio player found — silent fallback
        echo "{}"  # Required: Hermes hooks expect valid JSON on stdout
        return 0
    }

    # Play asynchronously so we never block the agent
    case "$player" in
        afplay)
            # afplay supports volume flag directly
            nohup afplay "$file" &>/dev/null &
            ;;
        aplay)
            nohup aplay -q "$file" &>/dev/null &
            ;;
        paplay)
            nohup paplay "$file" &>/dev/null &
            ;;
        pw-play)
            nohup pw-play "$file" &>/dev/null &
            ;;
        powershell)
            # WSL fallback — use PowerShell to play a system beep
            # Full WAV playback in WSL requires PulseAudio bridge; just beep
            nohup powershell.exe -Command "[Console]::Beep(800,200)" &>/dev/null &
            ;;
    esac

    disown 2>/dev/null || true
}

# ─── Read pack config ───────────────────────────────────────────────

read_pack_volume() {
    local pack_yaml="$1"
    if [[ -f "$pack_yaml" ]]; then
        # Extract volume from pack.yaml (simple grep, no yaml parser needed)
        grep -E '^volume:' "$pack_yaml" 2>/dev/null | head -1 | sed 's/volume: *//' || echo "$DEFAULT_VOLUME"
    else
        echo "$DEFAULT_VOLUME"
    fi
}

read_pack_cooldown() {
    local pack_yaml="$1"
    if [[ -f "$pack_yaml" ]]; then
        grep -E '^cooldown_ms:' "$pack_yaml" 2>/dev/null | head -1 | sed 's/cooldown_ms: *//' || echo "$DEFAULT_COOLDOWN_MS"
    else
        echo "$DEFAULT_COOLDOWN_MS"
    fi
}

# ─── Cooldown check ─────────────────────────────────────────────────

check_cooldown() {
    local event="$1"
    local cooldown_ms="${2:-$DEFAULT_COOLDOWN_MS}"

    mkdir -p "$COOLDOWN_DIR"
    local cooldown_file="$COOLDOWN_DIR/$event"
    local now_ms
    now_ms=$(( $(date +%s) * 1000 + $(date +%N | cut -c1-3) ))

    if [[ -f "$cooldown_file" ]]; then
        local last_ms
        last_ms=$(cat "$cooldown_file" 2>/dev/null || echo 0)
        local elapsed_ms=$(( now_ms - last_ms ))
        if [[ $elapsed_ms -lt $cooldown_ms ]]; then
            # Still in cooldown — skip this event
            return 1
        fi
    fi

    echo "$now_ms" > "$cooldown_file"
    return 0
}

# ─── Resolve event name ─────────────────────────────────────────────

resolve_event() {
    # If called with an argument, use it directly
    if [[ $# -gt 0 ]]; then
        echo "$1"
        return 0
    fi

    # Otherwise, try to read from stdin (Hermes hooks JSON)
    local stdin_data
    stdin_data=$(cat 2>/dev/null) || true
    if [[ -n "$stdin_data" ]]; then
        # Extract hook_event_name from JSON (simple grep, no jq needed)
        local event
        event=$(echo "$stdin_data" | grep -oE '"hook_event_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed 's/.*:.*"\([^"]*\)"/\1/')
        if [[ -n "$event" ]]; then
            echo "$event"
            return 0
        fi
    fi

    # Fallback: default event
    echo "complete"
}

# ─── Map Hermes hook events to sound events ─────────────────────────

map_event() {
    local hook_event="$1"
    case "$hook_event" in
        post_llm_call)       echo "complete" ;;
        on_session_end)       echo "complete" ;;
        pre_approval_request)  echo "approval" ;;
        on_session_start)      echo "startup" ;;
        post_tool_call)        echo "tool_done" ;;
        # Direct sound names pass through
        complete|approval|error|startup|tool_done) echo "$hook_event" ;;
        *)                     echo "complete" ;;  # Unknown hooks → default sound
    esac
}

# ─── Main ───────────────────────────────────────────────────────────

main() {
    # Check if sounds are disabled
    if [[ -f "$AWOOGA_DIR/disabled" ]]; then
        echo "{}"
        return 0
    fi

    # Resolve active pack
    local pack_name
    if [[ -f "$ACTIVE_PACK_FILE" ]]; then
        pack_name=$(cat "$ACTIVE_PACK_FILE" 2>/dev/null || echo "$DEFAULT_PACK")
    else
        pack_name="$DEFAULT_PACK"
    fi

    local pack_dir="$PACKS_DIR/$pack_name"
    local pack_yaml="$pack_dir/pack.yaml"

    if [[ ! -d "$pack_dir" ]]; then
        # Pack not found — silent fallback
        echo "{}"
        return 0
    fi

    # Resolve event
    local raw_event
    raw_event=$(resolve_event "$@")
    local sound_event
    sound_event=$(map_event "$raw_event")

    # Find the WAV file
    local wav_file="$pack_dir/$sound_event.wav"
    if [[ ! -f "$wav_file" ]]; then
        # Try reading from pack.yaml mapping
        local mapped_file
        mapped_file=$(grep -E "^  ${sound_event}:" "$pack_yaml" 2>/dev/null | sed 's/.*: *//' | tr -d '"')
        if [[ -n "$mapped_file" && -f "$pack_dir/$mapped_file" ]]; then
            wav_file="$pack_dir/$mapped_file"
        else
            # No sound file for this event — silent
            echo "{}"
            return 0
        fi
    fi

    # Check cooldown
    local cooldown_ms
    cooldown_ms=$(read_pack_cooldown "$pack_yaml")
    if ! check_cooldown "$sound_event" "$cooldown_ms"; then
        echo "{}"
        return 0
    fi

    # Play the sound
    play_wav "$wav_file"

    # Hermes shell hooks require valid JSON on stdout
    echo "{}"
}

main "$@"