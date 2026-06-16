#!/usr/bin/env bash
# install.sh — One-liner installer for hermes-agent-awooga-sfx
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/verdey/hermes-agent-awooga-sfx/main/install.sh | bash
#
# Or clone and run:
#   git clone https://github.com/verdey/hermes-agent-awooga-sfx.git
#   cd hermes-agent-awooga-sfx && bash install.sh

set -euo pipefail

REPO_OWNER="verdey"
REPO_NAME="hermes-agent-awooga-sfx"
GITHUB_REPO="https://github.com/${REPO_OWNER}/${REPO_NAME}"
DEFAULT_PACK="awooga-tugboat"

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
AWOOGA_DIR="${AWOOGA_DIR:-$HERMES_HOME/awooga-sfx}"
PACKS_DIR="${AWOOGA_DIR}/packs"

# ─── Source shared lib (register_hooks + logging) ──────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/src/_lib.sh" ]]; then
    source "$SCRIPT_DIR/src/_lib.sh"
else
    err "_lib.sh not found alongside install.sh. Cannot proceed."
    exit 1
fi

# ─── Pre-flight ────────────────────────────────────────────────────────

echo -e "${BOLD}📢 hermes-agent-awooga-sfx installer${NC}"
echo -e "${CYAN}Make your Hermes Agent LOUD — awoooga! 🚢${NC}"
echo ""

if ! command -v git &>/dev/null; then
    err "git is required but not found. Please install git first."
    exit 1
fi

# ─── Get source (local clone or curl) ──────────────────────────────────

if [[ -f "$SCRIPT_DIR/src/play-sound.sh" ]]; then
    SOURCE_DIR="$SCRIPT_DIR"
    info "Installing from local repo: $SOURCE_DIR"
else
    info "Cloning repository..."
    TMPDIR=$(mktemp -d)
    git clone --depth 1 "$GITHUB_REPO" "$TMPDIR/hermes-agent-awooga-sfx" 2>/dev/null || {
        err "Failed to clone repository. Check your internet connection."
        exit 1
    }
    SOURCE_DIR="$TMPDIR/hermes-agent-awooga-sfx"
    ok "Repository cloned"
fi

# ─── Install scripts and packs ─────────────────────────────────────────

mkdir -p "$AWOOGA_DIR/src" "$PACKS_DIR"
cp "$SOURCE_DIR/src/_lib.sh"     "$AWOOGA_DIR/src/_lib.sh"
cp "$SOURCE_DIR/src/play-sound.sh"  "$AWOOGA_DIR/src/play-sound.sh"
cp "$SOURCE_DIR/src/switch-pack.sh" "$AWOOGA_DIR/src/switch-pack.sh"
cp "$SOURCE_DIR/src/self-test.sh"   "$AWOOGA_DIR/src/self-test.sh"
chmod +x "$AWOOGA_DIR/src/"*.sh
ok "Scripts installed to $AWOOGA_DIR/src/"

for pack_dir in "$SOURCE_DIR/packs"/*/; do
    [[ -d "$pack_dir" ]] || continue
    local_name=$(basename "$pack_dir")
    mkdir -p "$PACKS_DIR/$local_name"
    cp -r "$pack_dir"/* "$PACKS_DIR/$local_name/" 2>/dev/null || true
    ok "Pack: $local_name"
done

echo "$DEFAULT_PACK" > "$AWOOGA_DIR/active-pack"
ok "Default pack set: $DEFAULT_PACK"

# ─── Register hooks ────────────────────────────────────────────────────

CONFIG_FILE="$HERMES_HOME/config.yaml"
register_hooks "$CONFIG_FILE"

# ─── Self-test (first-run sound + hook presence) ───────────────────────

echo ""
info "Running first-run self-test..."
if [[ -x "$AWOOGA_DIR/src/self-test.sh" ]]; then
    if "$AWOOGA_DIR/src/self-test.sh" --quiet 2>&1 | tail -5; then
        ok "Self-test passed. Sounds should fire on next agent run."
    else
        warn "Self-test reported issues. Run: $AWOOGA_DIR/src/self-test.sh"
    fi
fi

# ─── Cleanup ───────────────────────────────────────────────────────────

[[ -n "${TMPDIR:-}" ]] && [[ -d "$TMPDIR/hermes-agent-awooga-sfx" ]] && rm -rf "$TMPDIR"

# ─── Success ───────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}${BOLD}🔊 AWOOGA! Installation complete!${NC}"
echo ""
echo "  Installed to: $AWOOGA_DIR"
echo "  Active pack:  $DEFAULT_PACK 🚢"
echo ""
echo "  Next steps:"
echo "    1. Restart Hermes (or run: hermes gateway restart)"
echo "    2. List packs: $AWOOGA_DIR/src/switch-pack.sh --list"
echo "    3. Diagnose:   $AWOOGA_DIR/src/self-test.sh"
echo ""
echo -e "  ${CYAN}Make some noise! 📢${NC}"
echo ""
