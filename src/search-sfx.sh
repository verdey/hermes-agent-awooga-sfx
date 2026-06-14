#!/usr/bin/env bash
# search-sfx.sh — Search Freesound API and create custom sound packs
#
# Usage:
#   search-sfx.sh <query>                  # Search Freesound for sounds
#   search-sfx.sh --download <sound-id>    # Download a specific sound
#   search-sfx.sh --create-pack <name>     # Create a pack from downloaded sounds
#
# Requires FREESOUND_API_KEY environment variable.
# Get one at: https://freesound.org/apiv2/apply/

set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
AWOOGA_DIR="${AWOOGA_DIR:-$HERMES_HOME/awooga-sfx}"
PACKS_DIR="${AWOOGA_DIR}/packs"
FREESOUND_API_KEY="${FREESOUND_API_KEY:-}"
FREESOUND_BASE="https://freesound.org/apiv2"

# ─── Helpers ────────────────────────────────────────────────────────

info()  { echo -e "\033[0;34mℹ️  $*\033[0m"; }
ok()    { echo -e "\033[0;32m✅ $*\033[0m"; }
warn()  { echo -e "\033[0;33m⚠️  $*\033[0m"; }
err()   { echo -e "\033[0;31m❌ $*\033[0m"; }

check_api_key() {
    if [[ -z "$FREESOUND_API_KEY" ]]; then
        err "FREESOUND_API_KEY not set."
        echo ""
        echo "  Get a free API key at: https://freesound.org/apiv2/apply/"
        echo "  Then set it in your environment:"
        echo "    export FREESOUND_API_KEY=your_key_here"
        echo ""
        echo "  Or add it to ~/.hermes/.env:"
        echo "    FREESOUND_API_KEY=your_key_here"
        return 1
    fi
}

# ─── Search ─────────────────────────────────────────────────────────

cmd_search() {
    local query="$1"
    check_api_key || return 1

    info "Searching Freesound for: $query"
    echo ""

    # Search Freesound API
    local response
    response=$(curl -fsSL "${FREESOUND_BASE}/search/text/?query=${query}&filter=duration:[0+TO+5]&sort=rating_desc&fields=id,name,description,duration,previews,license,username&token=${FREESOUND_API_KEY}&page_size=10" 2>/dev/null) || {
        err "Search failed. Check your API key and internet connection."
        return 1
    }

    # Parse results (simple grep-based, no jq dependency)
    local count
    count=$(echo "$response" | grep -o '"count":[0-9]*' | head -1 | grep -o '[0-9]*' || echo "0")

    if [[ "$count" -eq 0 ]]; then
        warn "No results found for '$query'."
        return 0
    fi

    echo "  Found $count results (showing top 10):"
    echo ""

    # Extract results
    local result_num=0
    local in_result=false
    local sound_id="" sound_name="" sound_desc="" sound_dur="" sound_user="" sound_license=""

    while IFS= read -r line; do
        if echo "$line" | grep -q '"id"'; then
            sound_id=$(echo "$line" | sed 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/')
        fi
        if echo "$line" | grep -q '"name"'; then
            sound_name=$(echo "$line" | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        fi
        if echo "$line" | grep -q '"duration"'; then
            sound_dur=$(echo "$line" | sed 's/.*"duration"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/')
        fi
        if echo "$line" | grep -q '"username"'; then
            sound_user=$(echo "$line" | sed 's/.*"username"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        fi
        if echo "$line" | grep -q '"license"'; then
            sound_license=$(echo "$line" | sed 's/.*"license"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        fi
    done <<< "$response"

    # Since simple line-by-line parsing is fragile with JSON, use a more robust approach
    # Try using python3 for JSON parsing if available
    if command -v python3 &>/dev/null; then
        python3 << PYEOF
import json, sys

try:
    data = json.loads("""$(echo "$response" | sed "s/'/'\\\\''/g")""")
except:
    print("  Error parsing results.")
    sys.exit(0)

results = data.get("results", [])
if not results:
    print("  No results found.")
    sys.exit(0)

for i, r in enumerate(results[:10], 1):
    sid = r.get("id", "?")
    name = r.get("name", "Unknown")
    dur = r.get("duration", 0)
    user = r.get("username", "Unknown")
    lic = r.get("license", "Unknown")
    desc = r.get("description", "")[:80]
    print(f"  {i}) 🔊 ID:{sid} — {name}")
    print(f"     Duration: {dur:.1f}s | By: {user} | License: {lic}")
    if desc:
        print(f"     {desc}")
    print()
PYEOF
    else
        # Fallback: raw output
        echo "$response" | head -100
    fi
}

# ─── Download ────────────────────────────────────────────────────────

cmd_download() {
    local sound_id="$1"
    check_api_key || return 1

    info "Downloading sound $sound_id from Freesound..."

    # Get sound info
    local info_response
    info_response=$(curl -fsSL "${FREESOUND_BASE}/sounds/${sound_id}/?fields=id,name,previews,license,username&token=${FREESOUND_API_KEY}" 2>/dev/null) || {
        err "Failed to fetch sound info."
        return 1
    }

    # Get preview URL (MP3 preview — for full WAV you need OAuth)
    local preview_url
    if command -v python3 &>/dev/null; then
        preview_url=$(python3 -c "import json; d=json.loads('''$(echo "$info_response" | sed "s/'/'\\\\''/g")'''); print(d.get('previews',{}).get('preview-hq-mp3',''))" 2>/dev/null) || {
            err "Failed to parse sound info."
            return 1
        }
    else
        err "python3 required for downloading. Install it and try again."
        return 1
    fi

    if [[ -z "$preview_url" ]]; then
        err "No preview URL found for sound $sound_id."
        return 1
    fi

    # Download to a staging area
    local staging="$AWOOGA_DIR/staging"
    mkdir -p "$staging"

    local filename="freesound_${sound_id}.mp3"
    info "Downloading preview MP3..."

    if ! curl -fsSL "${preview_url}?token=${FREESOUND_API_KEY}" -o "$staging/$filename"; then
        err "Download failed."
        return 1
    fi

    ok "Downloaded to $staging/$filename"
    echo ""
    echo "  To create a sound pack from downloaded sounds, use:"
    echo "    search-sfx.sh --create-pack <pack-name>"
}

# ─── Create Pack ─────────────────────────────────────────────────────

cmd_create_pack() {
    local pack_name="$1"
    local staging="$AWOOGA_DIR/staging"
    local pack_dir="$PACKS_DIR/$pack_name"

    if [[ ! -d "$staging" ]] || [[ -z "$(ls -A "$staging" 2>/dev/null)" ]]; then
        err "No staged sounds found. Download sounds first with --download."
        return 1
    fi

    if [[ -d "$pack_dir" ]]; then
        warn "Pack '$pack_name' already exists. Overwrite? [y/N]"
        read -r confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            info "Cancelled."
            return 0
        fi
        rm -rf "$pack_dir"
    fi

    mkdir -p "$pack_dir"

    # List staged sounds and let user assign them to events
    echo ""
    echo -e "\033[1m🎵 Create Pack: $pack_name\033[0m"
    echo ""
    echo "  Assign each downloaded sound to a sound event:"
    echo ""

    local events=("complete" "approval" "error" "startup" "tool_done")
    local event_descriptions=(
        "Agent completes a response"
        "Agent needs user approval"
        "Error occurred"
        "New session starts"
        "Tool call completes"
    )

    local staged_files=()
    for f in "$staging"/*; do
        [[ -f "$f" ]] && staged_files+=("$(basename "$f")")
    done

    # For each event, ask user to pick a file
    local attributions=""
    for i in "${!events[@]}"; do
        local event="${events[$i]}"
        local desc="${event_descriptions[$i]}"
        echo -e "  \033[1m${event}\033[0m (${desc})"
        echo "  Available sounds:"
        for j in "${!staged_files[@]}"; do
            echo "    $((j+1))) ${staged_files[$j]}"
        done
        echo "    s) Skip this event"
        echo -n "  Choose [1-${#staged_files[@]}, s]: "
        read -r choice

        if [[ "$choice" == "s" ]]; then
            continue
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#staged_files[@]}" ]]; then
            local src="$staging/${staged_files[$((choice-1))]}"
            local dest="$pack_dir/${event}.mp3"
            cp "$src" "$dest"
            echo -e "  ${GREEN}✅ ${event} → ${staged_files[$((choice-1))]}${NC}"
            attributions+="${event}: ${staged_files[$((choice-1))]} (Freesound)\n"
        fi
        echo ""
    done

    # Create pack.yaml
    cat > "$pack_dir/pack.yaml" << EOF
name: $pack_name
version: "1.0.0"
description: "Custom pack created from Freesound search"
author: custom
license: varies
events:
  complete: complete.mp3
  approval: approval.mp3
  error: error.mp3
  startup: startup.mp3
  tool_done: tool_done.mp3
volume: 0.8
cooldown_ms: 3000
EOF

    # Create attributions
    cat > "$pack_dir/ATTRIBUTIONS.md" << EOF
# Attributions for $pack_name

This pack was created from sounds downloaded from Freesound (https://freesound.org).
Check individual sound pages for specific license terms.

$attributions
EOF

    # Clean up staging
    rm -rf "$staging"

    ok "Pack '$pack_name' created at $pack_dir/"
    echo "  Switch to it with: switch-pack.sh $pack_name"
}

# ─── Main ───────────────────────────────────────────────────────────

case "${1:-}" in
    --list|-l)
        cmd_search "${2:-foghorn}"
        ;;
    --download|-d)
        if [[ -z "${2:-}" ]]; then
            err "Please specify a sound ID. Use search first."
            exit 1
        fi
        cmd_download "$2"
        ;;
    --create-pack|-c)
        if [[ -z "${2:-}" ]]; then
            err "Please specify a pack name."
            exit 1
        fi
        cmd_create_pack "$2"
        ;;
    --help|-h)
        echo "Usage: search-sfx.sh <query>              # Search Freesound"
        echo "       search-sfx.sh --download <sound-id> # Download a sound"
        echo "       search-sfx.sh --create-pack <name> # Create pack from downloads"
        echo ""
        echo "Requires FREESOUND_API_KEY environment variable."
        echo "Get one at: https://freesound.org/apiv2/apply/"
        ;;
    *)
        cmd_search "$1"
        ;;
esac