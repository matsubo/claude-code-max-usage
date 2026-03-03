#!/usr/bin/env bash
# claude-usage.tmux — TPM plugin entry point
# Registers #{claude_usage} and #{claude_usage_compact} interpolation strings

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/scripts/helpers.sh"

claude_usage_interpolation="#($CURRENT_DIR/scripts/claude_usage.sh)"
claude_usage_compact_interpolation="#($CURRENT_DIR/scripts/claude_usage_compact.sh)"

do_interpolation() {
    local string="$1"
    # Replace longer string first to prevent partial matching
    string="${string//\#{claude_usage_compact\}/$claude_usage_compact_interpolation}"
    string="${string//\#{claude_usage\}/$claude_usage_interpolation}"
    echo "$string"
}

update_tmux_option() {
    local option="$1"
    local option_value
    option_value=$(get_tmux_option "$option")
    local new_option_value
    new_option_value=$(do_interpolation "$option_value")
    set_tmux_option "$option" "$new_option_value"
}

main() {
    update_tmux_option "status-right"
    update_tmux_option "status-left"
}

main
