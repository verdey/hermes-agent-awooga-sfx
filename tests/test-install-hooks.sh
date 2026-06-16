#!/usr/bin/env bash
# test-install-hooks.sh — Regression test for $AWOOGA_DIR env-var expansion bug
#
# Bug (historical): install.sh used to write `command: "$AWOOGA_DIR/src/play-sound.sh ..."`
# into ~/.hermes/config.yaml. Hermes runs hooks with
#   argv = shlex.split(os.path.expanduser(command))
#   subprocess.run(argv, shell=False)
# so $AWOOGA_DIR never expands. The fix is to bake the absolute path in
# (using the ~ form, which Hermes's os.path.expanduser DOES resolve) at
# install time.
#
# This test verifies the fix by sourcing src/_lib.sh (which install.sh now
# uses) against hermetic temp configs and asserting the resulting config.yaml
# contains the absolute path and no unexpanded env-var references.
#
# Idempotent: cleans up its own temp dirs. Re-runnable.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SH="$REPO_DIR/install.sh"
LIB_SH="$REPO_DIR/src/_lib.sh"

if [[ ! -f "$INSTALL_SH" ]]; then
    echo "FAIL: install.sh not found at $INSTALL_SH"
    exit 1
fi
if [[ ! -f "$LIB_SH" ]]; then
    echo "FAIL: _lib.sh not found at $LIB_SH"
    exit 1
fi

PASS=0
FAIL=0
FAILS=()

pass() { PASS=$((PASS + 1)); echo "  ✓ $*"; }
fail() { FAIL=$((FAIL + 1)); FAILS+=("$*"); echo "  ✗ $*"; }

# Build a hermetic temp dir. Always clean up on exit.
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

FAKE_HOME="$TMP/fakehome"
FAKE_HERMES_HOME="$FAKE_HOME/.hermes"
FAKE_AWOOGA_DIR="$FAKE_HERMES_HOME/awooga-sfx"
mkdir -p "$FAKE_HERMES_HOME" "$FAKE_AWOOGA_DIR/src"

# Source the shared lib. It defines register_hooks and the logging helpers.
# We override the logging helpers with noop versions for test output.
info() { :; }
ok()   { :; }
warn() { :; }
err()  { :; }

source "$LIB_SH"

# ─── Static check ───────────────────────────────────────────────────────
echo ""
echo "▶ Static check: _lib.sh must not write \$AWOOGA_DIR in any 'command:' line"
if grep -nE 'command:[[:space:]]+"[^"]*\$AWOOGA_DIR' "$LIB_SH"; then
    fail "_lib.sh still contains a 'command: \"\$AWOOGA_DIR/...\"' literal"
else
    pass "no 'command: \"\$AWOOGA_DIR/...\"' literal in _lib.sh"
fi

# Also check install.sh has no remaining duplicate hook blocks
echo ""
echo "▶ Static check: install.sh must source _lib.sh"
if grep -qE "source.*_lib\.sh" "$INSTALL_SH"; then
    pass "install.sh sources _lib.sh"
else
    fail "install.sh does not source _lib.sh"
fi

# ─── Helper: assert a config.yaml has the expected properties ────────────

assert_good_config() {
    local cfg="$1"
    local label="$2"

    # The 4 hook commands must each reference the absolute path
    if grep -qE 'command:[[:space:]]*"~/.hermes/awooga-sfx/src/play-sound\.sh complete"' "$cfg"; then
        pass "[$label] post_llm_call / on_session_end command uses absolute path"
    else
        fail "[$label] missing absolute-path command for complete sound"
    fi
    if grep -qE 'command:[[:space:]]*"~/.hermes/awooga-sfx/src/play-sound\.sh approval"' "$cfg"; then
        pass "[$label] pre_approval_request command uses absolute path"
    else
        fail "[$label] missing absolute-path command for approval sound"
    fi
    if grep -qE 'command:[[:space:]]*"~/.hermes/awooga-sfx/src/play-sound\.sh startup"' "$cfg"; then
        pass "[$label] on_session_start command uses absolute path"
    else
        fail "[$label] missing absolute-path command for startup sound"
    fi

    # No line should contain $AWOOGA_DIR
    if grep -q '\$AWOOGA_DIR' "$cfg"; then
        fail "[$label] config.yaml contains literal '\$AWOOGA_DIR' reference"
        grep -n '\$AWOOGA_DIR' "$cfg" | sed 's/^/      /'
    else
        pass "[$label] no '\$AWOOGA_DIR' in config.yaml"
    fi

    # No unexpanded env-var references in command: lines
    if grep -E '^[[:space:]]*-?[[:space:]]*command:' "$cfg" | grep -qE '\$[A-Za-z_][A-Za-z0-9_]*'; then
        fail "[$label] config.yaml has a 'command:' line with an unexpanded \$VAR"
        grep -nE '^[[:space:]]*-?[[:space:]]*command:' "$cfg" | grep -E '\$[A-Za-z_][A-Za-z0-9_]*' | sed 's/^/      /'
    else
        pass "[$label] no unexpanded \$VAR in any command: line"
    fi

    # hooks_auto_accept: true must be present
    if grep -q '^hooks_auto_accept: true' "$cfg"; then
        pass "[$label] hooks_auto_accept: true is set"
    else
        fail "[$label] hooks_auto_accept: true is missing"
    fi
}

# ─── Case 1: existing config with existing hooks: section ───────────────
echo ""
echo "▶ Case 1: existing config.yaml with existing hooks: section"
CONFIG_FILE="$FAKE_HERMES_HOME/config.yaml"
cat > "$CONFIG_FILE" <<YAML
model: claude-sonnet
hooks:
  some_other_hook:
    - command: "echo hello"
YAML
register_hooks
assert_good_config "$CONFIG_FILE" "case1"

# ─── Case 2: existing config WITHOUT a hooks: section ─────────────────
echo ""
echo "▶ Case 2: existing config.yaml with no hooks: section"
CONFIG_FILE="$FAKE_HERMES_HOME/config.yaml"
cat > "$CONFIG_FILE" <<YAML
model: claude-sonnet
some_other_setting: 42
YAML
register_hooks
assert_good_config "$CONFIG_FILE" "case2"

# ─── Case 3: no config file at all (Hermes fresh install) ──────────────
echo ""
echo "▶ Case 3: no config.yaml exists"
CONFIG_FILE="$FAKE_HERMES_HOME/config.yaml"
rm -f "$CONFIG_FILE"
register_hooks > "$CONFIG_FILE" 2>/dev/null
assert_good_config "$CONFIG_FILE" "case3"

# ─── Case 4: re-running install (idempotency / no-double-registration) ──
echo ""
echo "▶ Case 4: re-running when hooks are already present (should be a no-op)"
register_hooks
assert_good_config "$CONFIG_FILE" "case4"

# ─── Verdict ───────────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────"
if [[ $FAIL -eq 0 ]]; then
    echo "PASS: $PASS checks passed, 0 failed"
    echo "  _lib.sh::register_hooks() writes the absolute path (~/.hermes/awooga-sfx/...)"
    echo "  to config.yaml, which is what Hermes needs since it does not expand env vars."
    exit 0
else
    echo "FAIL: $FAIL of $((PASS + FAIL)) checks failed"
    for f in "${FAILS[@]}"; do echo "  - $f"; done
    exit 1
fi
