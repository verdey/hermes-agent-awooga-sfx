#!/usr/bin/env bash
# _lib.sh — Shared helpers for hermes-agent-awooga-sfx
#
# Sourced by install.sh and test-install-hooks.sh. Do NOT execute directly.
# Provides: register_hooks, info, ok, warn, err

# ─── Logging helpers (noop when sourced by test-install-hooks.sh) ──────

if [[ -z "${_AWOOGA_LIB_SOURCED:-}" ]]; then
  _AWOOGA_LIB_SOURCED=1

  if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
  else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
  fi

  info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
  ok()   { echo -e "${GREEN}✅ $*${NC}"; }
  warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
  err()  { echo -e "${RED}❌ $*${NC}"; }
fi

# ─── Hook entries (shared across all registration paths) ───────────────

AWOOGA_HOOK_ENTRIES='
  post_llm_call:
    - command: "~/.hermes/awooga-sfx/src/play-sound.sh complete"
  on_session_end:
    - command: "~/.hermes/awooga-sfx/src/play-sound.sh complete"
  pre_approval_request:
    - command: "~/.hermes/awooga-sfx/src/play-sound.sh approval"
  on_session_start:
    - command: "~/.hermes/awooga-sfx/src/play-sound.sh startup"
'

# ─── Register hooks into config.yaml ───────────────────────────────────
#
# Called with:
#   CONFIG_FILE   — path to ~/.hermes/config.yaml
#   HERMES_HOME   — Hermes home dir (for hooks_auto_accept)
#   HERMES_BIN    — path to hermes binary (optional, for the warn message)
#
# Three scenarios handled internally:
#   1. config exists + has hooks: section   → Python YAML patch
#   2. config exists + no hooks: section   → Python YAML patch + hooks block
#   3. config does not exist                → cat heredoc to stdout

register_hooks() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # Check idempotency — look for specific hook entry, not just "play-sound"
        if grep -qE 'post_llm_call.*play-sound' "$CONFIG_FILE" 2>/dev/null; then
            warn "Hooks already registered in config.yaml. Skipping."
            # Still ensure hooks_auto_accept is set
            if ! grep -q '^hooks_auto_accept: true' "$CONFIG_FILE" 2>/dev/null; then
                echo "hooks_auto_accept: true" >> "$CONFIG_FILE"
                ok "Set hooks_auto_accept: true"
            fi
            return 0
        fi

        if grep -qE '^hooks:' "$CONFIG_FILE" 2>/dev/null; then
            # Case 1: hooks: section exists — Python patch
            python3 << PYEOF
import re, sys

with open("$CONFIG_FILE", "r") as f:
    content = f.read()

hook_entries = """$AWOOGA_HOOK_ENTRIES"""

lines = content.split("\n")
new_lines = []
in_hooks = False
hooks_indent = None
for line in lines:
    new_lines.append(line)
    stripped = line.strip()
    if stripped == "hooks:" or stripped.startswith("hooks:"):
        in_hooks = True
        hooks_indent = len(line) - len(line.lstrip())
        for entry in hook_entries.strip().split("\n"):
            new_lines.append(" " * hooks_indent + entry)
        in_hooks = False
    elif in_hooks and line and not line.startswith(" " * (hooks_indent + 1)) and not line.startswith("\t"):
        for entry in hook_entries.strip().split("\n"):
            new_lines.append(" " * hooks_indent + entry)
        in_hooks = False

with open("$CONFIG_FILE", "w") as f:
    f.write("\n".join(new_lines))
PYEOF
            ok "Hooks registered in config.yaml"
        else
            # Case 2: no hooks: section — append the whole block
            cat >> "$CONFIG_FILE" << HOOKS

hooks:
$AWOOGA_HOOK_ENTRIES
hooks_auto_accept: true
HOOKS
            ok "Hooks registered in config.yaml"
        fi

        # Ensure hooks_auto_accept is set
        if ! grep -q '^hooks_auto_accept: true' "$CONFIG_FILE" 2>/dev/null; then
            echo "hooks_auto_accept: true" >> "$CONFIG_FILE"
            ok "Set hooks_auto_accept: true"
        fi
    else
        # Case 3: no config file at all
        warn "Hermes config.yaml not found at $CONFIG_FILE"
        warn "To register hooks manually, add this to your config.yaml:"
        echo ""
        cat << HOOKS
hooks:
$AWOOGA_HOOK_ENTRIES
hooks_auto_accept: true
HOOKS
    fi
}
