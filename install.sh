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

# ─── Paths ──────────────────────────────────────────────────────────────

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
AWOOGA_DIR="${AWOOGA_DIR:-$HERMES_HOME/awooga-sfx}"
PACKS_DIR="${AWOOGA_DIR}/packs"

# ─── Pre-flight checks ─────────────────────────────────────────────────

echo ""
echo -e "${BOLD}📢 hermes-agent-awooga-sfx installer${NC}"
echo -e "${CYAN}Make your Hermes Agent LOUD — awoooga! 🚢${NC}"
echo ""

# Check for git
if ! command -v git &>/dev/null; then
    err "git is required but not found. Please install git first."
    exit 1
fi

# Check for Hermes
HERMES_BIN=""
if command -v hermes &>/dev/null; then
    HERMES_BIN="hermes"
    ok "Found Hermes CLI"
elif [[ -x "$HOME/.local/bin/hermes" ]]; then
    HERMES_BIN="$HOME/.local/bin/hermes"
    ok "Found Hermes CLI at ~/.local/bin/hermes"
else
    warn "Hermes CLI not found in PATH. Hooks will be configured but not auto-accepted."
    warn "Install Hermes first: https://hermes-agent.nousresearch.com/docs/"
fi

# ─── Source shared lib ──────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/src/_lib.sh" ]]; then
    source "$SCRIPT_DIR/src/_lib.sh"
else
    err "_lib.sh not found. Cannot proceed."
    exit 1
fi

# ─── Install ────────────────────────────────────────────────────────────

# If running from a cloned repo, use local files; otherwise clone
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

# Copy _lib.sh first (install.sh needs it; scripts need it at runtime)
mkdir -p "$AWOOGA_DIR/src"
cp "$SOURCE_DIR/src/_lib.sh" "$AWOOGA_DIR/src/_lib.sh"

# Create directories
mkdir -p "$AWOOGA_DIR"
mkdir -p "$PACKS_DIR"

# Copy scripts
info "Installing scripts to $AWOOGA_DIR/src/..."
cp "$SOURCE_DIR/src/play-sound.sh" "$AWOOGA_DIR/src/play-sound.sh"
cp "$SOURCE_DIR/src/switch-pack.sh" "$AWOOGA_DIR/src/switch-pack.sh"
cp "$SOURCE_DIR/src/admin.sh" "$AWOOGA_DIR/src/admin.sh"
cp "$SOURCE_DIR/src/install-pack.sh" "$AWOOGA_DIR/src/install-pack.sh"
cp "$SOURCE_DIR/src/search-sfx.sh" "$AWOOGA_DIR/src/search-sfx.sh"
chmod +x "$AWOOGA_DIR/src/"*.sh
ok "Scripts installed"

# Copy packs
info "Installing sound packs to $PACKS_DIR/..."
for pack_dir in "$SOURCE_DIR/packs"/*/; do
    if [[ -d "$pack_dir" ]]; then
        pack_name=$(basename "$pack_dir")
        mkdir -p "$PACKS_DIR/$pack_name"
        cp -r "$pack_dir"/* "$PACKS_DIR/$pack_name/" 2>/dev/null || true
        ok "Pack: $pack_name"
    fi
done

# Copy packs.json if it exists
if [[ -f "$SOURCE_DIR/packs.json" ]]; then
    cp "$SOURCE_DIR/packs.json" "$AWOOGA_DIR/packs.json"
fi

# Set default active pack
echo "$DEFAULT_PACK" > "$AWOOGA_DIR/active-pack"
ok "Default pack set: $DEFAULT_PACK"

# ─── Register Hermes hooks ──────────────────────────────────────────────

CONFIG_FILE="$HERMES_HOME/config.yaml"
register_hooks

# ─── Cleanup ────────────────────────────────────────────────────────────

if [[ -n "${TMPDIR:-}" ]] && [[ -d "$TMPDIR/hermes-agent-awooga-sfx" ]]; then
    rm -rf "$TMPDIR"
fi

# ─── Success ────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}${BOLD}🔊 AWOOGA! Installation complete!${NC}"
echo ""
echo "  Installed to: $AWOOGA_DIR"
echo "  Active pack:  $DEFAULT_PACK 🚢"
echo ""
echo "  Next steps:"
echo "    1. Restart Hermes (or run: hermes gateway restart)"
echo "    2. Try: $AWOOGA_DIR/src/admin.sh"
echo "    3. Switch packs: $AWOOGA_DIR/src/switch-pack.sh --list"
echo ""
echo -e "  ${CYAN}Make some noise! 📢${NC}"
echo ""
