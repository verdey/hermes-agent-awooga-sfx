#!/usr/bin/env bash
# _lib.sh — Shared helpers for hermes-agent-awooga-sfx
#
# Sourced by install.sh and tests. Do NOT execute directly.

set -euo pipefail

# ─── Logging helpers (no-op when overridden by test) ────────────────────

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

# ─── Hook entries (single source of truth) ──────────────────────────────

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

# ─── register_hooks ─────────────────────────────────────────────────────
#
# Idempotent. Handles all observable forms of the `hooks:` key in
# ~/.hermes/config.yaml:
#   - missing entirely
#   - hooks: {}                  (inline empty dict)
#   - hooks: null / hooks: []    (inline empty value)
#   - hooks: with content        (populated block — append)
#   - hooks: with nothing after  (empty block — append)
#
# Strategy: try PyYAML first (handles arbitrarily nested state safely).
# Fall back to text-based merge if PyYAML is missing or the file is
# unparseable.

register_hooks() {
    local cfg="${1:-${CONFIG_FILE:-$HERMES_HOME/config.yaml}}"

    if [[ ! -f "$cfg" ]]; then
        # Print the warning to stderr, the hook block to stdout.
        # This way callers can do `register_hooks "$cfg" > new-config.yaml`
        # to seed a fresh config, with the warning still visible.
        warn "Hermes config.yaml not found at $cfg" >&2
        warn "Add this to your config.yaml manually:" >&2
        cat <<HOOKS
hooks:
$AWOOGA_HOOK_ENTRIES
hooks_auto_accept: true
HOOKS
        return 0
    fi

    # Idempotency check: if all 4 hook entries are present, skip.
    if grep -qE 'post_llm_call.*play-sound' "$cfg" 2>/dev/null \
       && grep -qE 'pre_approval_request.*play-sound' "$cfg" 2>/dev/null \
       && grep -qE 'on_session_start.*play-sound' "$cfg" 2>/dev/null; then
        # Force hooks_auto_accept: true regardless.
        _ensure_auto_accept "$cfg"
        warn "Hooks already registered. Skipping."
        return 0
    fi

    # Try PyYAML path.
    if python3 -c "import yaml" &>/dev/null; then
        if _register_via_yaml "$cfg"; then
            ok "Hooks registered (PyYAML merge)."
            return 0
        fi
        warn "PyYAML merge failed; falling back to text merge."
    fi

    _register_via_text "$cfg"
    ok "Hooks registered (text merge)."
}

_ensure_auto_accept() {
    local cfg="$1"
    if grep -qE '^hooks_auto_accept:\s*true\s*$' "$cfg" 2>/dev/null; then
        return 0
    fi
    # Replace false → true if present; otherwise append.
    if grep -qE '^hooks_auto_accept:' "$cfg" 2>/dev/null; then
        python3 -c "
import re, sys
p = sys.argv[1]
with open(p) as f: t = f.read()
t = re.sub(r'^hooks_auto_accept:.*$', 'hooks_auto_accept: true', t, flags=re.MULTILINE)
with open(p, 'w') as f: f.write(t)
" "$cfg"
    else
        echo "" >> "$cfg"
        echo "hooks_auto_accept: true" >> "$cfg"
    fi
}

_register_via_yaml() {
    local cfg="$1"
    python3 - "$cfg" <<'PYEOF' || return 1
import sys, yaml

cfg = sys.argv[1]
with open(cfg) as f:
    data = yaml.safe_load(f) or {}

if not isinstance(data, dict):
    sys.exit(1)

hooks = data.get("hooks")
if not isinstance(hooks, dict):
    hooks = {}

entries = [
    ("post_llm_call",        "~/.hermes/awooga-sfx/src/play-sound.sh complete"),
    ("on_session_end",       "~/.hermes/awooga-sfx/src/play-sound.sh complete"),
    ("pre_approval_request", "~/.hermes/awooga-sfx/src/play-sound.sh approval"),
    ("on_session_start",     "~/.hermes/awooga-sfx/src/play-sound.sh startup"),
]
for key, cmd in entries:
    hooks[key] = [{"command": cmd}]

data["hooks"] = hooks
data["hooks_auto_accept"] = True

with open(cfg, "w") as f:
    yaml.safe_dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
PYEOF
}

_register_via_text() {
    local cfg="$1"
    python3 - "$cfg" <<'PYEOF'
import sys, re

cfg = sys.argv[1]
with open(cfg) as f:
    text = f.read()

entries = [
    ("post_llm_call",        "~/.hermes/awooga-sfx/src/play-sound.sh complete"),
    ("on_session_end",       "~/.hermes/awooga-sfx/src/play-sound.sh complete"),
    ("pre_approval_request", "~/.hermes/awooga-sfx/src/play-sound.sh approval"),
    ("on_session_start",     "~/.hermes/awooga-sfx/src/play-sound.sh startup"),
]

def render(indent):
    sp = " " * indent
    out = []
    for k, c in entries:
        out.append(f"{sp}{k}:")
        out.append(f'{sp}  - command: "{c}"')
    return out

hooks_re = re.compile(r"^(\s*)hooks:(\s*.*)$")
lines = text.split("\n")
idx = indent = 0
value = ""
for i, ln in enumerate(lines):
    m = hooks_re.match(ln)
    if m:
        idx, indent, value = i, len(m.group(1)), m.group(2).strip()
        break

if idx == 0 and not hooks_re.match(lines[0] if lines else ""):
    # No hooks: at all — append a fresh block.
    if lines and lines[-1] != "":
        lines.append("")
    lines.append("hooks:")
    lines.extend(render(2))
elif value == "{}":
    # hooks: {} — replace the one-liner.
    new = lines[:idx] + ["hooks:"] + render(indent + 2) + lines[idx + 1:]
    lines = new
else:
    # Find the end of any existing block.
    block_end = len(lines)
    has_content = False
    for j in range(idx + 1, len(lines)):
        ln = lines[j]
        if not ln.strip():
            continue
        li = len(ln) - len(ln.lstrip())
        if li > indent:
            has_content = True
        else:
            block_end = j
            break
    if value and not has_content:
        # hooks: null / hooks: [] / hooks: <inline> — replace.
        new = lines[:idx] + ["hooks:"] + render(indent + 2) + lines[idx + 1:]
        lines = new
    elif has_content:
        # Populated block — splice entries in at end of block.
        new = lines[:block_end] + render(indent + 2) + lines[block_end:]
        lines = new
    else:
        # Empty block (hooks: with nothing after) — append.
        new = lines[:idx + 1] + render(indent + 2) + lines[idx + 1:]
        lines = new

text = "\n".join(lines)
if not re.search(r"^hooks_auto_accept:\s*true\s*$", text, re.MULTILINE):
    text = re.sub(r"^hooks_auto_accept:.*$", "hooks_auto_accept: true", text, flags=re.MULTILINE)
    if "hooks_auto_accept" not in text:
        if text and not text.endswith("\n"):
            text += "\n"
        text += "hooks_auto_accept: true\n"

with open(cfg, "w") as f:
    f.write(text)
PYEOF
}
