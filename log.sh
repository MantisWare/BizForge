#!/bin/bash
# watch-logs-color.sh

# Statically configured log files
BACKEND_LOG=".bizforge/logs/backend.log"
DESKTOP_LOG=".bizforge/logs/desktop.log"
FRONTEND_LOG=".bizforge/logs/frontend.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

tail_with_color() {
  local file="$1"
  local color="$2"
  tail -f "$file" | while IFS= read -r line; do
    echo -e "${color}[$(basename "$file")] ${NC}${line}"
  done
}

tail_with_color "$BACKEND_LOG" "$RED"   &
tail_with_color "$DESKTOP_LOG" "$GREEN" &
tail_with_color "$FRONTEND_LOG" "$YELLOW" &

# Kill background jobs cleanly on Ctrl+C
trap "kill 0" EXIT
wait