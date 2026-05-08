#!/bin/bash
set -euo pipefail

# Preflight: ensure PostgreSQL is running and migrations are applied.
# The justfile recipes also run these, but checking here gives early feedback.
just _ensure-postgres
just _ensure-migrations

# Start the desktop command center
just stop && just app

# Start Web
# just stop && just dev
