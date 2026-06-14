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

# ─── Colors ──────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
fi

# ─── Detect paths ────────────────────────────────────────────────────

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
AWOOGA_DIR="${AWOOGA_DIR:-$HERMES_HOME/awooga-sfx}"
PACKS_DIR="${AWOOGA_DIR}/packs"

info()  { echo -e "${BLUE}ℹ️  $*${NC}"; }
ok()    { echo -e "${GREEN}✅ $*${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $*${NC}"; }
err()   { echo -e "${RED}❌ $*${NC}"; }

# ─── Pre-flight checks ──────────────────────────────────────────────

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

# ─── Install ─────────────────────────────────────────────────────────

# If running from a cloned repo, use local files; otherwise clone
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/src/play-sound.sh" ]]; then
    # Running from a cloned repo
    SOURCE_DIR="$SCRIPT_DIR"
    info "Installing from local repo: $SOURCE_DIR"
else
    # Download via curl
    info "Cloning repository..."
    TMPDIR=$(mktemp -d)
    git clone --depth 1 "$GITHUB_REPO" "$TMPDIR/hermes-agent-awooga-sfx" 2>/dev/null || {
        err "Failed to clone repository. Check your internet connection."
        exit 1
    }
    SOURCE_DIR="$TMPDIR/hermes-agent-awooga-sfx"
    ok "Repository cloned"
fi

# Create directories
mkdir -p "$AWOOGA_DIR"
mkdir -p "$PACKS_DIR"

# Copy scripts
info "Installing scripts to $AWOOGA_DIR/src/..."
mkdir -p "$AWOOGA_DIR/src"
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

# ─── Register Hermes hooks ──────────────────────────────────────────

CONFIG_FILE="$HERMES_HOME/config.yaml"

if [[ -f "$CONFIG_FILE" ]]; then
    info "Registering hooks in Hermes config..."

    # Check if hooks already exist
    if grep -q 'play-sound' "$CONFIG_FILE" 2>/dev/null; then
        warn "Hooks already registered in config.yaml. Skipping."
    else
        # Add hooks block to config
        # Use Python to safely modify YAML (or just append if no hooks: section)
        if grep -q '^hooks:' "$CONFIG_FILE" 2>/dev/null; then
            # Append to existing hooks section
            # Find the hooks section and append after it
            python3 << PYEOF
import re, sys

with open("$CONFIG_FILE", "r") as f:
    content = f.read()

# Find the hooks section and add our entries
hook_entries = """
  post_llm_call:
    - command: "$AWOOGA_DIR/src/play-sound.sh complete"
  on_session_end:
    - command: "$AWOOGA_DIR/src/play-sound.sh complete"
  pre_approval_request:
    - command: "$AWOOGA_DIR/src/play-sound.sh approval"
  on_session_start:
    - command: "$AWOOGA_DIR/src/play-sound.sh startup"
"""

# Find the hooks: section and append after it
if "hooks:" in content:
    # Find the end of the hooks section (next top-level key or end of file)
    lines = content.split("\n")
    new_lines = []
    in_hooks = False
    hooks_indent = None
    for line in lines:
        new_lines.append(line)
        if line.strip() == "hooks:" or line.startswith("hooks:"):
            in_hooks = True
            hooks_indent = len(line) - len(line.lstrip())
            # Insert our entries right after hooks:
            for entry in hook_entries.strip().split("\n"):
                new_lines.append(" " * hooks_indent + entry)
            in_hooks = False
        elif in_hooks and line and not line.startswith(" " * (hooks_indent + 1)) and not line.startswith("\t"):
            # End of hooks section
            for entry in hook_entries.strip().split("\n"):
                new_lines.append(" " * hooks_indent + entry)
            in_hooks = False
    
    with open("$CONFIG_FILE", "w") as f:
        f.write("\n".join(new_lines))
PYEOF
        else
            # No hooks section — add one
            cat >> "$CONFIG_FILE" << HOOKS

hooks:
  post_llm_call:
    - command: "$AWOOGA_DIR/src/play-sound.sh complete"
  on_session_end:
    - command: "$AWOOGA_DIR/src/play-sound.sh complete"
  pre_approval_request:
    - command: "$AWOOGA_DIR/src/play-sound.sh approval"
  on_session_start:
    - command: "$AWOOGA_DIR/src/play-sound.sh startup"
hooks_auto_accept: true
HOOKS
        fi
        ok "Hooks registered in config.yaml"
    fi

    # Ensure hooks_auto_accept is set
    if ! grep -q 'hooks_auto_accept: true' "$CONFIG_FILE" 2>/dev/null; then
        echo "hooks_auto_accept: true" >> "$CONFIG_FILE"
        ok "Set hooks_auto_accept: true"
    fi
else
    warn "Hermes config.yaml not found at $CONFIG_FILE"
    warn "To register hooks manually, add this to your config.yaml:"
    echo ""
    cat << HOOKS
hooks:
  post_llm_call:
    - command: "$AWOOGA_DIR/src/play-sound.sh complete"
  on_session_end:
    - command: "$AWOOGA_DIR/src/play-sound.sh complete"
  pre_approval_request:
    - command: "$AWOOGA_DIR/src/play-sound.sh approval"
  on_session_start:
    - command: "$AWOOGA_DIR/src/play-sound.sh startup"
hooks_auto_accept: true
HOOKS
fi

# ─── Cleanup ─────────────────────────────────────────────────────────

if [[ -n "${TMPDIR:-}" ]] && [[ -d "$TMPDIR/hermes-agent-awooga-sfx" ]]; then
    rm -rf "$TMPDIR"
fi

# ─── Success ─────────────────────────────────────────────────────────

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