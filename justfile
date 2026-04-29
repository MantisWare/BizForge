# Canopy — Command Runner
# Install: brew install just
# Usage:  just --list        (show all recipes)
#         just dev           (start full stack)
#         just stop          (stop all services)

set dotenv-load := true
set positional-arguments := true

# Directories
root    := justfile_directory()
backend := root / "backend"
desktop := root / "desktop"
pid_dir := root / ".canopy" / "pids"
log_dir := root / ".canopy" / "logs"

# ── Setup ────────────────────────────────────────────────────────────────────

# Install all dependencies (backend + desktop)
setup:
    @echo "Installing backend dependencies..."
    cd {{backend}} && mix deps.get
    @echo ""
    @echo "Installing desktop dependencies..."
    cd {{desktop}} && npm install
    @echo ""
    @echo "Ready. Run 'just dev' to launch."

# Check prerequisites and port availability
doctor:
    #!/usr/bin/env bash
    set -euo pipefail
    printf "Checking prerequisites...\n"
    command -v just   >/dev/null 2>&1 && printf "  just:     %s\n" "$(just --version)" || printf "  just:     MISSING (brew install just)\n"
    command -v node   >/dev/null 2>&1 && printf "  Node.js:  %s\n" "$(node --version)"  || printf "  Node.js:  MISSING (brew install node)\n"
    command -v npm    >/dev/null 2>&1 && printf "  npm:      %s\n" "$(npm --version)"   || printf "  npm:      MISSING\n"
    command -v rustc  >/dev/null 2>&1 && printf "  Rust:     %s\n" "$(rustc --version)"  || printf "  Rust:     MISSING (curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh)\n"
    command -v elixir >/dev/null 2>&1 && printf "  Elixir:   %s\n" "$(elixir --version 2>/dev/null | head -1)" || printf "  Elixir:   MISSING (brew install elixir)\n"
    command -v mix    >/dev/null 2>&1 && printf "  Mix:      OK\n" || printf "  Mix:      MISSING\n"
    command -v psql   >/dev/null 2>&1 && printf "  Postgres:  %s\n" "$(psql --version)" || printf "  Postgres:  MISSING (brew install postgresql@15)\n"
    printf "\nChecking ports...\n"
    lsof -ti:9089 >/dev/null 2>&1 && printf "  Port 9089: IN USE (backend)\n"  || printf "  Port 9089: free\n"
    lsof -ti:5200 >/dev/null 2>&1 && printf "  Port 5200: IN USE (desktop)\n"  || printf "  Port 5200: free\n"
    lsof -ti:8089 >/dev/null 2>&1 && printf "  Port 8089: IN USE (OSA)\n"      || printf "  Port 8089: free\n"

# ── Development ──────────────────────────────────────────────────────────────

# Start full stack (backend :9089 + desktop :5200)
dev: _ensure-dirs
    #!/usr/bin/env bash
    set -euo pipefail

    # Stop anything already running
    just stop 2>/dev/null || true

    printf "Starting backend on :9089...\n"
    cd {{backend}} && mix phx.server > {{log_dir}}/backend.log 2>&1 &
    echo $! > {{pid_dir}}/backend.pid
    printf "  Backend PID: %s\n" "$(cat {{pid_dir}}/backend.pid)"

    # Wait for backend health
    for i in $(seq 1 30); do
        if curl -sf http://127.0.0.1:9089/api/v1/health >/dev/null 2>&1; then
            printf "  Backend ready.\n"
            break
        fi
        if [ "$i" -eq 30 ]; then
            printf "  Backend may still be starting (continuing anyway).\n"
        fi
        sleep 1
    done

    printf "\nStarting desktop on :5200...\n"
    cd {{desktop}} && npm run dev > {{log_dir}}/desktop.log 2>&1 &
    echo $! > {{pid_dir}}/desktop.pid
    printf "  Desktop PID: %s\n" "$(cat {{pid_dir}}/desktop.pid)"

    for i in $(seq 1 15); do
        if curl -sf http://127.0.0.1:5200 >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done
    printf "  Desktop ready.\n"

    # Open in browser (macOS)
    command -v open >/dev/null 2>&1 && open "http://127.0.0.1:5200/app" || true

    printf "\nCanopy is running.\n"
    printf "  Backend:  http://127.0.0.1:9089\n"
    printf "  Desktop:  http://127.0.0.1:5200/app\n"
    printf "\nUse 'just status' to check, 'just logs backend' to tail, 'just stop' to shut down.\n"

# Start full stack with native Tauri app
app: _ensure-dirs
    #!/usr/bin/env bash
    set -euo pipefail
    just stop 2>/dev/null || true

    printf "Starting backend on :9089...\n"
    cd {{backend}} && mix phx.server > {{log_dir}}/backend.log 2>&1 &
    echo $! > {{pid_dir}}/backend.pid

    for i in $(seq 1 30); do
        curl -sf http://127.0.0.1:9089/api/v1/health >/dev/null 2>&1 && break
        sleep 1
    done
    printf "  Backend ready.\n"

    printf "Starting Tauri desktop app...\n"
    cd {{desktop}} && npm run tauri:dev > {{log_dir}}/desktop.log 2>&1 &
    echo $! > {{pid_dir}}/desktop.pid
    printf "  Tauri app launching (PID %s).\n" "$(cat {{pid_dir}}/desktop.pid)"

# Start backend only (Phoenix on :9089)
[group('services')]
backend: _ensure-dirs
    #!/usr/bin/env bash
    set -euo pipefail
    just stop-backend 2>/dev/null || true
    printf "Starting backend on :9089...\n"
    cd {{backend}} && mix phx.server > {{log_dir}}/backend.log 2>&1 &
    echo $! > {{pid_dir}}/backend.pid
    printf "  Backend PID: %s\n" "$(cat {{pid_dir}}/backend.pid)"
    printf "  Logs: just logs backend\n"

# Start desktop only (Vite on :5200, mock mode)
[group('services')]
desktop: _ensure-dirs
    #!/usr/bin/env bash
    set -euo pipefail
    just stop-desktop 2>/dev/null || true
    printf "Starting desktop on :5200...\n"
    cd {{desktop}} && npm run dev > {{log_dir}}/desktop.log 2>&1 &
    echo $! > {{pid_dir}}/desktop.pid
    printf "  Desktop PID: %s\n" "$(cat {{pid_dir}}/desktop.pid)"
    printf "  Logs: just logs desktop\n"

# ── Process Management ───────────────────────────────────────────────────────

# Stop all running services
stop:
    #!/usr/bin/env bash
    set -euo pipefail
    stopped=0
    for svc in backend desktop; do
        pidfile="{{pid_dir}}/${svc}.pid"
        if [ -f "$pidfile" ]; then
            pid=$(cat "$pidfile")
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
                printf "  Stopped %s (PID %s)\n" "$svc" "$pid"
                stopped=1
            fi
            rm -f "$pidfile"
        fi
    done
    # Also kill any strays on our ports
    lsof -ti:9089 2>/dev/null | xargs kill 2>/dev/null || true
    lsof -ti:5200 2>/dev/null | xargs kill 2>/dev/null || true
    if [ "$stopped" -eq 0 ]; then
        printf "  No services were running.\n"
    fi

# Stop backend only
stop-backend:
    #!/usr/bin/env bash
    set -euo pipefail
    pidfile="{{pid_dir}}/backend.pid"
    if [ -f "$pidfile" ]; then
        pid=$(cat "$pidfile")
        kill "$pid" 2>/dev/null && printf "  Stopped backend (PID %s)\n" "$pid" || true
        rm -f "$pidfile"
    fi
    lsof -ti:9089 2>/dev/null | xargs kill 2>/dev/null || true

# Stop desktop only
stop-desktop:
    #!/usr/bin/env bash
    set -euo pipefail
    pidfile="{{pid_dir}}/desktop.pid"
    if [ -f "$pidfile" ]; then
        pid=$(cat "$pidfile")
        kill "$pid" 2>/dev/null && printf "  Stopped desktop (PID %s)\n" "$pid" || true
        rm -f "$pidfile"
    fi
    lsof -ti:5200 2>/dev/null | xargs kill 2>/dev/null || true

# Restart backend (stop + start)
restart-backend: stop-backend backend

# Restart desktop (stop + start)
restart-desktop: stop-desktop desktop

# Show running services and ports
status:
    #!/usr/bin/env bash
    set -euo pipefail
    printf "Services:\n"
    for svc in backend desktop; do
        pidfile="{{pid_dir}}/${svc}.pid"
        if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
            printf "  %-10s running  (PID %s)\n" "$svc" "$(cat "$pidfile")"
        else
            printf "  %-10s stopped\n" "$svc"
            rm -f "$pidfile" 2>/dev/null || true
        fi
    done
    printf "\nPorts:\n"
    lsof -ti:9089 >/dev/null 2>&1 && printf "  :9089  IN USE (backend)\n"  || printf "  :9089  free\n"
    lsof -ti:5200 >/dev/null 2>&1 && printf "  :5200  IN USE (desktop)\n"  || printf "  :5200  free\n"
    lsof -ti:8089 >/dev/null 2>&1 && printf "  :8089  IN USE (OSA)\n"      || printf "  :8089  free\n"

# Tail logs for a service (backend or desktop)
logs service:
    tail -f {{log_dir}}/{{service}}.log

# ── Database ─────────────────────────────────────────────────────────────────

# Create database, run migrations, and seed
db-setup:
    cd {{backend}} && mix ecto.create && mix ecto.migrate && mix run priv/repo/seeds.exs

# Run pending Ecto migrations
db-migrate:
    cd {{backend}} && mix ecto.migrate

# Drop, create, migrate, and seed the database
db-reset:
    cd {{backend}} && mix ecto.reset

# Run database seeds
db-seed:
    cd {{backend}} && mix run priv/repo/seeds.exs

# Generate a new migration
db-gen name:
    cd {{backend}} && mix ecto.gen.migration {{name}}

# ── Quality ──────────────────────────────────────────────────────────────────

# Type check desktop + compile backend with warnings-as-errors
check:
    cd {{desktop}} && npm run check
    cd {{backend}} && mix compile --warnings-as-errors

# Run full test suite (backend + desktop)
test:
    cd {{backend}} && mix test
    cd {{desktop}} && npm run test

# Run backend tests only
test-backend *args:
    cd {{backend}} && mix test {{args}}

# Run desktop tests only
test-desktop:
    cd {{desktop}} && npm run test

# Run Elixir + TypeScript linters
lint:
    cd {{backend}} && mix credo --strict
    cd {{desktop}} && npx eslint src/

# Auto-format all code
format:
    cd {{backend}} && mix format
    cd {{desktop}} && npx prettier --write "src/**/*.{ts,svelte,css}"

# ── Build ────────────────────────────────────────────────────────────────────

# Production Tauri app bundle (.app on macOS)
build:
    cd {{desktop}} && npm run tauri:build

# Build and package the Tauri desktop app (alias for build)
release: build

# ── Cleanup ──────────────────────────────────────────────────────────────────

# Remove all build artifacts, node_modules, deps
clean: stop
    cd {{desktop}} && rm -rf build .svelte-kit node_modules
    cd {{desktop}}/src-tauri && cargo clean
    cd {{backend}} && rm -rf _build deps
    rm -f {{pid_dir}}/*.pid {{log_dir}}/*.log

# ── Internal ─────────────────────────────────────────────────────────────────

[private]
_ensure-dirs:
    @mkdir -p {{pid_dir}} {{log_dir}}
