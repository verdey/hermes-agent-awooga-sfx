#!/usr/bin/env bash
# self-test.sh — Verify the awooga install is wired correctly
# @anchor self-test
# @web_safe yes
# @cron_safe yes
# @timeout 30
# @param verbose:select:no:no,yes:Show detailed output
#
# Checks:
#   1. AWOOGA_DIR exists and has scripts
#   2. At least one sound pack is installed
#   3. Active pack points at an installed pack
#   4. play-sound.sh can resolve every required event to a WAV file
#   5. Hermes config.yaml has the awooga hook entries
#   6. Audio player is available (or silent fallback is in place)

set -eo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
AWOOGA_DIR="${AWOOGA_DIR:-$HERMES_HOME/awooga-sfx}"
ACTIVE_PACK_FILE="$AWOOGA_DIR/active-pack"
PACKS_DIR="$AWOOGA_DIR/packs"
CONFIG_FILE="$HERMES_HOME/config.yaml"

REQUIRED_EVENTS=(complete approval error startup tool_done)
HERMES_HOOKS=(post_llm_call on_session_end pre_approval_request on_session_start post_tool_call)

VERBOSE="${1:-no}"
[[ "${2:-}" == "yes" ]] && VERBOSE="yes"
[[ "${AWOOGA_QUIET:-0}" == "1" ]] && VERBOSE="no"

# Color setup (mirror _lib.sh so this works standalone too)
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
    BLUE='\033[0;34m'; NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

PASS=0; FAIL=0
log()  { echo -e "  $*"; }
ok()   { log "${GREEN}✅ $*${NC}"; PASS=$((PASS + 1)); }
err()  { log "${RED}❌ $*${NC}"; FAIL=$((FAIL + 1)); }
warn() { log "${YELLOW}⚠️  $*${NC}"; }
info() { log "${BLUE}ℹ️  $*${NC}"; }

# ─── 1. Install layout ─────────────────────────────────────────────────

echo "▶ Install layout"
[[ -d "$AWOOGA_DIR" ]] && ok "AWOOGA_DIR exists: $AWOOGA_DIR" || {
    err "AWOOGA_DIR missing: $AWOOGA_DIR (run install.sh)"
    exit 1
}
for s in play-sound.sh switch-pack.sh _lib.sh; do
    [[ -x "$AWOOGA_DIR/src/$s" ]] && ok "src/$s present" || err "src/$s missing"
done

# ─── 2. Sound packs ────────────────────────────────────────────────────

echo ""
echo "▶ Sound packs"
[[ -d "$PACKS_DIR" ]] || { err "packs/ directory missing"; exit 1; }
local_count=$(find "$PACKS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
if [[ "$local_count" -gt 0 ]]; then
    ok "$local_count pack(s) installed"
else
    err "no packs installed"
fi

# ─── 3. Active pack points at a real install ──────────────────────────

echo ""
echo "▶ Active pack"
active=$([[ -f "$ACTIVE_PACK_FILE" ]] && cat "$ACTIVE_PACK_FILE" 2>/dev/null || echo "")
if [[ -z "$active" ]]; then
    err "active-pack file empty or missing"
elif [[ -d "$PACKS_DIR/$active" ]]; then
    ok "active pack: $active"
else
    err "active pack '$active' not found in packs/"
fi

# ─── 4. Every required event resolves to a WAV ─────────────────────────

echo ""
echo "▶ Event resolution"
if [[ -d "$PACKS_DIR/$active" ]]; then
    pack_yaml="$PACKS_DIR/$active/pack.yaml"
    for ev in "${REQUIRED_EVENTS[@]}"; do
        wav="$PACKS_DIR/$active/$ev.wav"
        if [[ -f "$wav" ]]; then
            ok "event '$ev' → ${ev}.wav"
        elif [[ -f "$pack_yaml" ]] && grep -qE "^  ${ev}:" "$pack_yaml"; then
            mapped=$(grep -E "^  ${ev}:" "$pack_yaml" | sed 's/.*:[[:space:]]*//' | tr -d '"')
            if [[ -f "$PACKS_DIR/$active/$mapped" ]]; then
                ok "event '$ev' → $mapped (via pack.yaml)"
            else
                err "event '$ev' pack.yaml references missing file: $mapped"
            fi
        else
            err "event '$ev' has no WAV (will be silent)"
        fi
    done
fi

# ─── 5. Hook entries in Hermes config ──────────────────────────────────

echo ""
echo "▶ Hermes hooks"
if [[ ! -f "$CONFIG_FILE" ]]; then
    err "config.yaml not found: $CONFIG_FILE"
else
    # Parse and check via PyYAML
    if python3 -c "import yaml" &>/dev/null; then
        python3 - "$CONFIG_FILE" <<'PYEOF' && ok "config.yaml parses as YAML" || err "config.yaml is invalid YAML"
import sys, yaml
with open(sys.argv[1]) as f: yaml.safe_load(f)
PYEOF
    fi
    # Check each hook entry
    for hook in "${HERMES_HOOKS[@]}"; do
        if grep -qE "^[[:space:]]*${hook}:[[:space:]]*$" "$CONFIG_FILE" 2>/dev/null; then
            # Verify it references play-sound.sh
            # Read the next 1-3 lines for a - command: ...
            if grep -A 3 "^[[:space:]]*${hook}:" "$CONFIG_FILE" | grep -qE 'play-sound\.sh'; then
                ok "hook '$hook' wired to play-sound.sh"
            else
                warn "hook '$hook' present but no play-sound.sh reference"
            fi
        elif [[ "$hook" == "post_tool_call" ]]; then
            info "hook '$hook' not registered (optional)"
        else
            err "hook '$hook' missing from config.yaml"
        fi
    done
    if grep -qE '^hooks_auto_accept:[[:space:]]*true' "$CONFIG_FILE"; then
        ok "hooks_auto_accept: true"
    else
        err "hooks_auto_accept: true missing"
    fi
fi

# ─── 6. Audio player ──────────────────────────────────────────────────

echo ""
echo "▶ Audio player"
if [[ -f "/tmp/hermes-awooga-audio-player" ]]; then
    ok "detected: $(cat /tmp/hermes-awooga-audio-player)"
else
    # Trigger detection
    for cmd in afplay aplay paplay pw-play powershell.exe; do
        if command -v "$cmd" &>/dev/null; then
            ok "detected: $cmd"
            break
        fi
    done || err "no audio player found (sounds will be silent)"
fi

# ─── Verdict ──────────────────────────────────────────────────────────

echo ""
echo "──────────────────────────────────────"
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}PASS: $PASS checks passed, 0 failed${NC}"
    exit 0
else
    echo -e "${RED}FAIL: $FAIL of $((PASS + FAIL)) checks failed${NC}"
    exit 1
fi
