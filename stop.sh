#!/bin/bash
set -euo pipefail

# Stop all Bizforge dev services started via just/start.sh.
#
# Usage:
#   ./stop.sh
#
# Stops: backend (:9089), Vite (:5200), Tauri desktop, and headless (:9090).

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if ! command -v just >/dev/null 2>&1; then
  echo "Error: 'just' is required (brew install just)" >&2
  exit 1
fi

printf "Stopping Bizforge services...\n"
just stop
just headless-stop 2>/dev/null || true
printf "All services stopped.\n"
