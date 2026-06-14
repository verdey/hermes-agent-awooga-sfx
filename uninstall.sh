#!/usr/bin/env bash
# uninstall.sh — Clean removal of hermes-agent-awooga-sfx
#
# Usage: bash uninstall.sh

set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
AWOOGA_DIR="${AWOOGA_DIR:-$HERMES_HOME/awooga-sfx}"
CONFIG_FILE="$HERMES_HOME/config.yaml"

# ─── Colors ──────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
fi

info()  { echo -e "${BLUE}ℹ️  $*${NC}"; }
ok()    { echo -e "${GREEN}✅ $*${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $*${NC}"; }

echo ""
echo -e "${BOLD}📢 Uninstalling hermes-agent-awooga-sfx${NC}"
echo ""

# ─── Remove AWOOGA_DIR ──────────────────────────────────────────────

if [[ -d "$AWOOGA_DIR" ]]; then
    echo -e "  Remove ${YELLOW}$AWOOGA_DIR${NC}? [y/N]"
    read -r confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        rm -rf "$AWOOGA_DIR"
        ok "Removed $AWOOGA_DIR"
    else
        info "Kept $AWOOGA_DIR"
    fi
else
    info "$AWOOGA_DIR not found (already removed)"
fi

# ─── Remove hooks from config.yaml ───────────────────────────────────

if [[ -f "$CONFIG_FILE" ]]; then
    if grep -q 'play-sound' "$CONFIG_FILE" 2>/dev/null; then
        info "Removing hooks from config.yaml..."
        # Use python3 to safely remove our hook entries
        python3 << PYEOF
import re

with open("$CONFIG_FILE", "r") as f:
    content = f.read()

# Remove hook entries that reference play-sound
lines = content.split("\n")
new_lines = []
skip_until_next_entry = False
for line in lines:
    if "play-sound.sh" in line:
        # Skip this line (it's a - command: line referencing play-sound)
        skip_until_next_entry = True
        continue
    elif skip_until_next_entry and line.strip().startswith("- "):
        # Next list entry — stop skipping
        skip_until_next_entry = False
        new_lines.append(line)
    elif skip_until_next_entry and line.strip() == "":
        # Blank line — might be between entries, stop skipping
        skip_until_next_entry = False
        new_lines.append(line)
    else:
        skip_until_next_entry = False
        new_lines.append(line)

# Clean up empty hooks sections
result = "\n".join(new_lines)
# Remove hook sections that are now empty (e.g., "post_llm_call:\n" with no entries)
result = re.sub(r'(\s+\w+:\n)(\s+\n|\s*$)', '', result, flags=re.MULTILINE)

with open("$CONFIG_FILE", "w") as f:
    f.write(result)
PYEOF
        ok "Hooks removed from config.yaml"
    else
        info "No awoooga hooks found in config.yaml"
    fi

    # Remove hooks_auto_accept if we added it
    if grep -q '^hooks_auto_accept: true' "$CONFIG_FILE" 2>/dev/null; then
        info "Removing hooks_auto_accept from config.yaml..."
        # Only remove if it's the only hooks_auto_accept line and looks auto-added
        python3 -c "
with open('$CONFIG_FILE', 'r') as f:
    lines = f.readlines()
with open('$CONFIG_FILE', 'w') as f:
    f.writelines(l for l in lines if l.strip() != 'hooks_auto_accept: true')
"
        ok "Removed hooks_auto_accept"
    fi
else
    info "Hermes config.yaml not found"
fi

# ─── Remove allowlist entries ─────────────────────────────────────────

ALLOWLIST="$HERMES_HOME/shell-hooks-allowlist.json"
if [[ -f "$ALLOWLIST" ]] && grep -q 'play-sound' "$ALLOWLIST" 2>/dev/null; then
    info "Removing awoooga entries from shell-hooks-allowlist.json..."
    python3 -c "
import json
with open('$ALLOWLIST', 'r') as f:
    data = json.load(f)
if isinstance(data, list):
    data = [e for e in data if 'play-sound' not in str(e)]
with open('$ALLOWLIST', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || warn "Could not clean allowlist (may need manual cleanup)"
    ok "Allowlist cleaned"
fi

# ─── Remove audio player cache ────────────────────────────────────────

rm -f /tmp/hermes-awooga-audio-player 2>/dev/null

echo ""
echo -e "${GREEN}${BOLD}🔇 Uninstall complete!${NC}"
echo ""
echo "  Sound effects have been removed from Hermes."
echo "  Restart Hermes to apply: hermes gateway restart"
echo ""