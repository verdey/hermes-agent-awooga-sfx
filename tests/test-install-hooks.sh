#!/usr/bin/env bash
# test-install-hooks.sh — Regression test for hook registration
#
# Verifies that register_hooks() handles all observable forms of the
# `hooks:` key in ~/.hermes/config.yaml without producing invalid YAML
# or leaving duplicate keys:
#
#   - missing entirely
#   - hooks: {}                  (inline empty dict — the historical bug)
#   - hooks: false               (boolean false — Hermes's default)
#   - hooks: null                (null value)
#   - hooks: with content        (populated block — append entries)
#   - hooks: with nothing after  (empty block — append entries)
#
# Also asserts idempotency (re-running is a no-op).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SH="$REPO_DIR/install.sh"
LIB_SH="$REPO_DIR/src/_lib.sh"

[[ -f "$INSTALL_SH" ]] || { echo "FAIL: install.sh not found"; exit 1; }
[[ -f "$LIB_SH" ]]    || { echo "FAIL: _lib.sh not found"; exit 1; }

PASS=0; FAIL=0; FAILS=()
pass() { PASS=$((PASS + 1)); echo "  ✓ $*"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$*"); echo "  ✗ $*"; }

# Hermetic temp dir.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Stub the logging helpers; source the lib.
info() { :; }
ok()   { :; }
warn() { :; }
err()  { :; }
source "$LIB_SH"

# ─── Static checks ──────────────────────────────────────────────────────
echo ""
echo "▶ Static checks"
if grep -nE 'command:[[:space:]]+"[^"]*\$AWOOGA_DIR' "$LIB_SH" "$INSTALL_SH"; then
    fail "literal '\$AWOOGA_DIR' in command: line"
else
    pass "no '\$AWOOGA_DIR' in any command: line"
fi
if grep -qE "source.*_lib\.sh" "$INSTALL_SH"; then
    pass "install.sh sources _lib.sh"
else
    fail "install.sh does not source _lib.sh"
fi

# ─── Assertion helper ───────────────────────────────────────────────────

assert_valid_yaml() {
    local cfg="$1" label="$2"
    if python3 -c "import yaml; yaml.safe_load(open('$cfg'))" 2>/dev/null; then
        pass "[$label] config.yaml is valid YAML"
    else
        fail "[$label] config.yaml is INVALID YAML"
        python3 -c "import yaml; yaml.safe_load(open('$cfg'))" 2>&1 | sed 's/^/      /' || true
    fi
}

assert_hooks_present() {
    local cfg="$1" label="$2"
    # Each hook's event name and its command can land on different lines
    # (e.g. PyYAML's `key:\n  - command: "..."` form). Use awk-style
    # multi-line matching via python to assert both halves are present.
    if python3 - "$cfg" <<'PYEOF' 2>/dev/null
import sys, yaml
cfg = sys.argv[1]
with open(cfg) as f:
    data = yaml.safe_load(f)
hooks = data.get("hooks") if isinstance(data, dict) else None
required = {
    "post_llm_call": "complete",
    "on_session_end": "complete",
    "pre_approval_request": "approval",
    "on_session_start": "startup",
}
if not isinstance(hooks, dict):
    sys.exit(1)
for key, want in required.items():
    cmds = hooks.get(key, [])
    if not any("play-sound.sh" in c.get("command", "") and want in c.get("command", "") for c in cmds):
        sys.exit(1)
sys.exit(0)
PYEOF
    then
        pass "[$label] all 4 hook entries present with correct event → command mapping"
    else
        fail "[$label] one or more hook entries are missing or mapped to wrong command"
    fi
    if grep -qE '^hooks_auto_accept:[[:space:]]*true[[:space:]]*$' "$cfg"; then
        pass "[$label] hooks_auto_accept: true is set"
    else
        fail "[$label] hooks_auto_accept: true is missing"
    fi
    # No literal $AWOOGA_DIR
    if grep -qE 'command:.*\$AWOOGA_DIR' "$cfg"; then
        fail "[$label] config.yaml contains '\$AWOOGA_DIR' in a command line"
    else
        pass "[$label] no '\$AWOOGA_DIR' in command: lines"
    fi
    # No duplicate top-level hooks_auto_accept
    local dup
    dup=$(grep -cE '^hooks_auto_accept:' "$cfg" || true)
    if [[ "$dup" -eq 1 ]]; then
        pass "[$label] exactly one hooks_auto_accept key"
    else
        fail "[$label] hooks_auto_accept appears $dup times (expected 1)"
    fi
}

run_case() {
    local label="$1" input="$2" path_strategy="$3"
    local cfg="$TMP/$label-config.yaml"
    echo "$input" > "$cfg"
    case "$path_strategy" in
        write) register_hooks "$cfg" >/dev/null 2>&1 || true ;;
        cat)   register_hooks "$cfg" > "$cfg.new" 2>/dev/null; mv "$cfg.new" "$cfg" ;;
    esac
    assert_valid_yaml "$cfg" "$label"
    assert_hooks_present "$cfg" "$label"
}

# ─── Cases ──────────────────────────────────────────────────────────────

echo ""
echo "▶ Case 1: existing config with existing hooks: section (populated)"
run_case "case1" "model: claude-sonnet
hooks:
  some_other_hook:
    - command: 'echo hello'
" "write"

echo ""
echo "▶ Case 2: existing config WITHOUT a hooks: section"
run_case "case2" "model: claude-sonnet
some_other_setting: 42
" "write"

echo ""
echo "▶ Case 3: no config file at all (Hermes fresh install)"
CFG="$TMP/case3-config.yaml"
rm -f "$CFG"
# IMPORTANT: redirect to a different file, not the same path.
# Otherwise the redirect itself creates the file and the "no config"
# branch never fires.
register_hooks "$CFG" > "$TMP/case3-out.yaml" 2>/dev/null
mv "$TMP/case3-out.yaml" "$CFG"
assert_valid_yaml "$CFG" "case3"
assert_hooks_present "$CFG" "case3"

echo ""
echo "▶ Case 4: re-running when hooks are already present (idempotency)"
register_hooks "$CFG"
assert_valid_yaml "$CFG" "case4"
assert_hooks_present "$CFG" "case4"
# Verify the file did not grow on re-run (idempotent)
local_size=$(wc -c < "$CFG")
register_hooks "$CFG"
local_size2=$(wc -c < "$CFG")
if [[ "$local_size" == "$local_size2" ]]; then
    pass "[case4] file size unchanged on re-run ($local_size bytes)"
else
    fail "[case4] file size changed: $local_size → $local_size2 (not idempotent)"
fi

echo ""
echo "▶ Case 5: hooks: {} (the historical bug — inline empty dict)"
run_case "case5" "model: claude-sonnet
hooks: {}
hooks_auto_accept: false
" "write"

echo ""
echo "▶ Case 6: hooks: false (Hermes's literal default state)"
run_case "case6" "model: claude-sonnet
hooks: false
" "write"

echo ""
echo "▶ Case 7: hooks: null"
run_case "case7" "model: claude-sonnet
hooks: null
" "write"

echo ""
echo "▶ Case 8: hooks: (empty block, no children)"
run_case "case8" "model: claude-sonnet
hooks:
" "write"

echo ""
echo "▶ Case 9: deeply nested existing hooks (mixed user + ours)"
run_case "case9" "model: claude-sonnet
hooks:
  pre_tool_call:
    - command: 'echo tool'
  post_tool_call:
    - command: 'echo done'
  on_session_start:
    - command: 'echo start'
" "write"

# ─── Verdict ────────────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────"
if [[ $FAIL -eq 0 ]]; then
    echo "PASS: $PASS checks passed, 0 failed"
    exit 0
else
    echo "FAIL: $FAIL of $((PASS + FAIL)) checks failed"
    for f in "${FAILS[@]}"; do echo "  - $f"; done
    exit 1
fi
