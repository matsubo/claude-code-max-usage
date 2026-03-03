#!/usr/bin/env bash
# claude_usage_compact.sh — Compact format wrapper
# Output: 22%/14%

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$CURRENT_DIR/claude_usage.sh" --compact "$@"
