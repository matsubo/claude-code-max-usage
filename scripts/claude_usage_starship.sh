#!/usr/bin/env bash
# claude_usage_starship.sh — Starship module wrapper
# Output: ANSI true-color escape sequences

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$CURRENT_DIR/claude_usage.sh" --mode=ansi "$@"
