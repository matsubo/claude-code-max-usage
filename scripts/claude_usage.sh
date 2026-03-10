#!/usr/bin/env bash
# claude_usage.sh — Claude Code (Max Plan) usage display
# Supports tmux status bar and ANSI terminal output (Starship, standalone)
# Format: 󰚩 ██░░░22% █░░░░14%

set -uo pipefail

# --- Argument parsing ---
MODE="tmux"
COMPACT=false
COMPACT_EXPLICIT=false

for arg in "$@"; do
    case "$arg" in
        --mode=*) MODE="${arg#--mode=}" ;;
        --compact) COMPACT=true; COMPACT_EXPLICIT=true ;;
    esac
done

# --- Configuration ---
# Read from tmux options (if inside tmux) with env var fallback

opt() {
    local tmux_opt="$1"
    local env_var="$2"
    local default="$3"

    # Try tmux option first (if tmux is available and we're attached)
    if [ -n "${TMUX:-}" ] && command -v tmux &>/dev/null; then
        local val
        val=$(tmux show-option -gqv "$tmux_opt" 2>/dev/null || true)
        if [ -n "$val" ]; then
            echo "$val"
            return
        fi
    fi

    # Fall back to env var
    local env_val="${!env_var:-}"
    if [ -n "$env_val" ]; then
        echo "$env_val"
        return
    fi

    echo "$default"
}

CACHE_TTL=$(opt "@claude_usage_cache_ttl" "CLAUDE_USAGE_CACHE_TTL" "600")
BAR_WIDTH=$(opt "@claude_usage_bar_width" "CLAUDE_USAGE_BAR_WIDTH" "5")
GREEN=$(opt "@claude_usage_green" "CLAUDE_USAGE_GREEN" "#a6da95")
YELLOW=$(opt "@claude_usage_yellow" "CLAUDE_USAGE_YELLOW" "#eed49f")
RED=$(opt "@claude_usage_red" "CLAUDE_USAGE_RED" "#ed8796")
DIM=$(opt "@claude_usage_dim" "CLAUDE_USAGE_DIM" "#7a839e")
LABEL=$(opt "@claude_usage_label" "CLAUDE_USAGE_LABEL" "#769ff0")
THRESHOLD_WARN=$(opt "@claude_usage_threshold_warn" "CLAUDE_USAGE_THRESHOLD_WARN" "50")
THRESHOLD_CRIT=$(opt "@claude_usage_threshold_crit" "CLAUDE_USAGE_THRESHOLD_CRIT" "80")
CREDS=$(opt "@claude_usage_credentials" "CLAUDE_USAGE_CREDENTIALS" "$HOME/.claude/.credentials.json")
ICON=$(opt "@claude_usage_icon" "CLAUDE_USAGE_ICON" "󰚩")
COMPACT_WIDTH=$(opt "@claude_usage_compact_width" "CLAUDE_USAGE_COMPACT_WIDTH" "120")

# --- Auto-compact based on terminal width ---
if ! $COMPACT_EXPLICIT && [ -n "${TMUX:-}" ] && command -v tmux &>/dev/null; then
    client_width=$(tmux display-message -p '#{client_width}' 2>/dev/null || echo "0")
    if [ "$client_width" -gt 0 ] && [ "$client_width" -lt "$COMPACT_WIDTH" ]; then
        COMPACT=true
    fi
fi

CACHE_DIR="${XDG_RUNTIME_DIR:-/tmp}/tmux-claude-${UID}"
mkdir -p "$CACHE_DIR" 2>/dev/null && chmod 700 "$CACHE_DIR" 2>/dev/null
CACHE="$CACHE_DIR/cache-${MODE}"
LOCK="$CACHE_DIR/lock"
PCT_CACHE="$CACHE_DIR/pct"

# --- Color abstraction ---

hex_to_rgb() {
    local hex="${1#\#}"
    printf "%d;%d;%d" "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

color_start() {
    local hex="$1"
    if [ "$MODE" = "ansi" ]; then
        printf '\033[38;2;%sm' "$(hex_to_rgb "$hex")"
    else
        printf '#[fg=%s]' "$hex"
    fi
}

color_reset() {
    if [ "$MODE" = "ansi" ]; then
        printf '\033[0m'
    else
        printf '#[fg=default]'
    fi
}

# --- Usage logic ---

color_for_pct() {
    local pct=$1
    if [ "$pct" -lt "$THRESHOLD_WARN" ]; then echo "$GREEN"
    elif [ "$pct" -lt "$THRESHOLD_CRIT" ]; then echo "$YELLOW"
    else echo "$RED"
    fi
}

make_bar() {
    local pct=$1 width=$BAR_WIDTH
    local filled=$(( (pct * width + 50) / 100 ))
    [ "$filled" -gt "$width" ] && filled=$width
    local empty=$((width - filled))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo "$bar"
}

format_segment() {
    local pct=$1
    local color bar filled empty fill_part empty_part
    color=$(color_for_pct "$pct")
    bar=$(make_bar "$pct")
    filled=$(( (pct * BAR_WIDTH + 50) / 100 ))
    [ "$filled" -gt "$BAR_WIDTH" ] && filled=$BAR_WIDTH
    empty=$((BAR_WIDTH - filled))
    fill_part="${bar:0:$filled}"
    empty_part="${bar:$filled:$empty}"
    printf "%s%s%s%s%s%d%%" \
        "$(color_start "$color")" "$fill_part" \
        "$(color_start "$DIM")" "$empty_part" \
        "$(color_start "$color")" "$pct"
}

fetch_usage() {
    local token

    if [ -f "$CREDS" ]; then
        token=$(jq -r '.claudeAiOauth.accessToken // empty' "$CREDS")
    fi

    # Fallback: macOS Keychain (Google OAuth users)
    if [ -z "$token" ] && command -v security &>/dev/null; then
        local keychain_data
        keychain_data=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
        if [ -n "$keychain_data" ]; then
            token=$(echo "$keychain_data" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
        fi
    fi

    if [ -z "$token" ]; then echo "-"; return; fi

    local json
    json=$(curl -s --max-time 5 \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H "Content-Type: application/json" \
        "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)

    if [ -z "$json" ]; then echo "-"; return; fi

    local s_pct w_pct
    s_pct=$(echo "$json" | jq -r '.five_hour.utilization // empty' | awk '{printf "%.0f", $1}' 2>/dev/null)
    w_pct=$(echo "$json" | jq -r '.seven_day.utilization // empty' | awk '{printf "%.0f", $1}' 2>/dev/null)

    if [ -z "$s_pct" ] || [ -z "$w_pct" ]; then echo "-"; return; fi

    echo "$s_pct $w_pct" > "$PCT_CACHE"

    printf "%s%s %s %s%s\n" \
        "$(color_start "$LABEL")" "$ICON" \
        "$(format_segment "$s_pct")" \
        "$(format_segment "$w_pct")" \
        "$(color_reset)"
}

compact_output() {
    if [ -f "$PCT_CACHE" ]; then
        local s_pct w_pct
        read -r s_pct w_pct < "$PCT_CACHE"
        if [ -n "$s_pct" ] && [ -n "$w_pct" ]; then
            local s_color w_color
            s_color=$(color_for_pct "$s_pct")
            w_color=$(color_for_pct "$w_pct")
            printf "%s%d%%%s/%s%d%%%s" \
                "$(color_start "$s_color")" "$s_pct" \
                "$(color_start "$DIM")" \
                "$(color_start "$w_color")" "$w_pct" \
                "$(color_reset)"
            return
        fi
    fi
    echo "-"
}

# --- Cache logic (stale-while-revalidate) ---

if [ -f "$CACHE" ]; then
    cached=$(cat "$CACHE")
    file_mtime=$(stat -c %Y "$CACHE" 2>/dev/null || stat -f %m "$CACHE" 2>/dev/null || echo "0")
    age=$(( $(date +%s) - file_mtime ))
else
    cached=""
    age=$((CACHE_TTL + 1))
fi

output_result() {
    local data="$1"
    if $COMPACT; then
        compact_output
    else
        echo "$data"
    fi
}

if [ "$age" -le "$CACHE_TTL" ]; then
    output_result "$cached"
elif [ -n "$cached" ]; then
    output_result "$cached"
    # Clean stale locks (older than 60 seconds)
    if [ -d "$LOCK" ]; then
        lock_age=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || stat -f %m "$LOCK" 2>/dev/null || echo "0") ))
        if [ "$lock_age" -gt 60 ]; then
            rmdir "$LOCK" 2>/dev/null
        fi
    fi
    # Background refresh
    if mkdir "$LOCK" 2>/dev/null; then
        (
            trap 'rmdir "$LOCK" 2>/dev/null' EXIT
            result=$(fetch_usage)
            if [ "$result" != "-" ]; then
                echo "$result" > "$CACHE"
            fi
        ) &
    fi
else
    result=$(fetch_usage)
    if [ "$result" != "-" ]; then
        echo "$result" > "$CACHE"
    fi
    output_result "$result"
fi
