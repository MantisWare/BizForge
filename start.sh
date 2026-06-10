#!/bin/bash
set -euo pipefail

# Start backend + native Tauri desktop app.
#
# Usage:
#   ./start.sh        Start the full stack
#   ./stop.sh         Stop all services (use this instead of passing "stop" here)
#
# Passing "stop" is forwarded to stop.sh for convenience.

if [ "${1:-}" = "stop" ]; then
  exec "$(dirname "$0")/stop.sh"
fi

# Preflight: ensure PostgreSQL is running and migrations are applied.
# `just app` runs the same checks again, but doing them here surfaces DB issues early.
just _ensure-postgres
just _ensure-migrations

# Start backend + Vite + Tauri; waits for health before opening the main window.
printf "Starting Bizforge (backend, Vite, desktop) — first launch may take a minute…\n"
just app

# Start Web
# just stop && just dev
