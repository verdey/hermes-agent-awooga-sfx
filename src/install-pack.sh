#!/usr/bin/env bash
# install-pack.sh — Download and install a CDN sound pack
# @category awooga
# @web_safe yes
# @cron_safe yes
# @timeout 120
# @param pack_id:text::Pack ID to install from GitHub Releases
#
# Usage:
#   install-pack.sh <pack-id>              # Install a pack from GitHub Releases
#   install-pack.sh --list                  # List available CDN packs
#   install-pack.sh --list --all            # List ALL packs (local + CDN)
#
# Reads the packs.json manifest from the repo to find available CDN packs.

set -euo pipefail

REPO_OWNER="verdey"
REPO_NAME="hermes-agent-awooga-sfx"
GITHUB_RELEASES_BASE="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download"

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
AWOOGA_DIR="${AWOOGA_DIR:-$HERMES_HOME/awooga-sfx}"
PACKS_DIR="${AWOOGA_DIR}/packs"

# ─── Helpers ────────────────────────────────────────────────────────

info()  { echo -e "\033[0;34mℹ️  $*\033[0m"; }
ok()    { echo -e "\033[0;32m✅ $*\033[0m"; }
warn()  { echo -e "\033[0;33m⚠️  $*\033[0m"; }
err()   { echo -e "\033[0;31m❌ $*\033[0m"; }

fetch_manifest() {
    # Try local packs.json first, then remote
    local local_manifest
    local_manifest="$(cd "$(dirname "$0")/.." && pwd)/packs.json"
    if [[ -f "$local_manifest" ]]; then
        cat "$local_manifest"
        return 0
    fi

    # Try fetching from GitHub raw
    local url="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/packs.json"
    local tmp
    tmp=$(mktemp)
    if curl -fsSL "$url" -o "$tmp" 2>/dev/null; then
        cat "$tmp"
        rm -f "$tmp"
        return 0
    fi
    rm -f "$tmp"
    return 1
}

# ─── Commands ───────────────────────────────────────────────────────

cmd_list() {
    local manifest
    manifest=$(fetch_manifest) || {
        echo "No CDN packs manifest available."
        echo "Check your internet connection or make sure packs.json exists."
        return 1
    }

    echo ""
    echo "📦 Available CDN Packs:"
    echo ""

    # Parse packs.json (simple grep-based, no jq dependency)
    local count
    count=$(echo "$manifest" | grep -c '"id"' 2>/dev/null || echo 0)

    if [[ "$count" -eq 0 ]]; then
        echo "  No CDN packs available yet."
        echo "  Check back later or contribute one!"
        return 0
    fi

    # Extract pack info using grep and sed
    local in_pack=false
    local pack_id="" pack_name="" pack_desc="" pack_version=""
    while IFS= read -r line; do
        if echo "$line" | grep -q '"id"'; then
            pack_id=$(echo "$line" | sed 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        fi
        if echo "$line" | grep -q '"name"'; then
            pack_name=$(echo "$line" | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        fi
        if echo "$line" | grep -q '"description"'; then
            pack_desc=$(echo "$line" | sed 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        fi
        if echo "$line" | grep -q '"version"'; then
            pack_version=$(echo "$line" | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        fi
        if echo "$line" | grep -q '^\s*}' || echo "$line" | grep -q '^\s*},\s*$'; then
            # End of pack object — print it
            local installed="  "
            if [[ -d "$PACKS_DIR/$pack_id" ]]; then
                installed="← "
            fi
            echo -e "  ${installed}${pack_id} v${pack_version} — ${pack_name}"
            echo -e "     ${pack_desc}"
            echo ""
            pack_id="" pack_name="" pack_desc="" pack_version=""
        fi
    done <<< "$manifest"
}

cmd_install() {
    local pack_id="$1"

    # Check if already installed
    if [[ -d "$PACKS_DIR/$pack_id" ]]; then
        warn "Pack '$pack_id' is already installed."
        echo "  Reinstall? [y/N] "
        read -r confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            info "Cancelled."
            return 0
        fi
        rm -rf "$PACKS_DIR/$pack_id"
    fi

    # Fetch manifest
    local manifest
    manifest=$(fetch_manifest) || {
        err "Could not fetch packs manifest."
        return 1
    }

    # Find the pack in the manifest
    local url="" sha256="" found=false
    local in_target=false
    while IFS= read -r line; do
        if echo "$line" | grep -q "\"id\"[[:space:]]*:[[:space:]]*\"${pack_id}\""; then
            in_target=true
            found=true
        fi
        if $in_target && echo "$line" | grep -q '"url"'; then
            url=$(echo "$line" | sed 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        fi
        if $in_target && echo "$line" | grep -q '"sha256"'; then
            sha256=$(echo "$line" | sed 's/.*"sha256"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        fi
        if $in_target && (echo "$line" | grep -q '^\s*}' || echo "$line" | grep -q '^\s*},\s*$'); then
            in_target=false
        fi
    done <<< "$manifest"

    if ! $found; then
        err "Pack '$pack_id' not found in manifest."
        echo "  Use --list to see available packs."
        return 1
    fi

    # Download
    info "Downloading $pack_id..."
    mkdir -p "$PACKS_DIR"
    local tmp_tar
    tmp_tar=$(mktemp /tmp/awooga-pack-XXXXXX.tar.gz)

    if ! curl -fsSL "$url" -o "$tmp_tar"; then
        err "Download failed."
        rm -f "$tmp_tar"
        return 1
    fi

    # Verify checksum (if provided)
    if [[ -n "$sha256" ]]; then
        local actual_sha
        actual_sha=$(shasum -a 256 "$tmp_tar" | awk '{print $1}')
        if [[ "$actual_sha" != "$sha256" ]]; then
            err "Checksum mismatch! Expected: $sha256"
            err "Got: $actual_sha"
            rm -f "$tmp_tar"
            return 1
        fi
        ok "Checksum verified."
    fi

    # Extract
    info "Extracting..."
    mkdir -p "$PACKS_DIR/$pack_id"
    tar -xzf "$tmp_tar" -C "$PACKS_DIR/$pack_id" --strip-components=1
    rm -f "$tmp_tar"

    ok "Pack '$pack_id' installed to $PACKS_DIR/$pack_id/"
    echo ""
    echo "  Switch to it with: switch-pack.sh $pack_id"
}

# ─── Main ───────────────────────────────────────────────────────────

case "${1:-}" in
    --list|-l)
        cmd_list
        ;;
    --help|-h)
        echo "Usage: install-pack.sh <pack-id>"
        echo "       install-pack.sh --list"
        echo ""
        echo "Download and install sound packs from GitHub Releases."
        ;;
    "")
        echo "❌ Please specify a pack ID. Use --list to see available packs."
        exit 1
        ;;
    *)
        cmd_install "$1"
        ;;
esac