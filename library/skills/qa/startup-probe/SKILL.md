---
name: qa/startup-probe
description: >
  Detect application type from project files, start the app with the correct
  command, and verify readiness via HTTP, TCP, or stdout probes. Manages the
  full lifecycle: install deps, start, health-check, and graceful shutdown.
  Triggers on: "startup probe", "start app", "launch app", "health check",
  "app ready", "start server", "dev server"
required_integrations: []
required_tools:
  - bash
---

# /startup-probe

> Detect, start, and health-check any application.

## Purpose

Automate the "get this app running" problem. Given a project directory, detect
what kind of application it is, install dependencies if needed, start it with
the correct command, and verify it's actually ready to accept requests or input.
Return structured metadata (PID, URL, framework, startup duration) for
downstream consumers like `/qa-automate` or any agent that needs a running app.

This skill is framework-agnostic and handles web apps, API services, CLI tools,
desktop apps, and platform-specific apps (Domo Custom Apps, Electron, Tauri).

## Usage

```bash
# Auto-detect and start
/startup-probe

# Specify app type
/startup-probe --type web

# Custom start command
/startup-probe --command "npm run preview"

# Custom health check URL
/startup-probe --health-url http://localhost:4000/api/health

# TCP port probe instead of HTTP
/startup-probe --probe tcp --port 5432

# Stdout pattern matching (for apps that don't serve HTTP)
/startup-probe --probe stdout --pattern "Ready to accept connections"

# Skip dependency install
/startup-probe --skip-install

# Just detect, don't start
/startup-probe --detect-only

# Shutdown a previously started app
/startup-probe --shutdown --pid 12345
```

## Arguments

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--type` | enum | auto-detect | `web`, `api`, `cli`, `desktop`, `domo` |
| `--command` | string | auto-detect | Custom start command |
| `--health-url` | string | auto-detect | URL to probe for readiness |
| `--probe` | enum | `http` | Probe type: `http`, `tcp`, `stdout`, `process` |
| `--port` | number | auto-detect | Port to check for TCP probe |
| `--pattern` | string | — | Stdout pattern for stdout probe |
| `--timeout` | number | 120 | Max seconds to wait for readiness |
| `--interval` | number | 2 | Seconds between probe attempts |
| `--skip-install` | flag | false | Skip dependency installation |
| `--detect-only` | flag | false | Detect app type without starting |
| `--shutdown` | flag | false | Shutdown mode — kill app by PID |
| `--pid` | number | — | PID to kill in shutdown mode |
| `--env` | string | `development` | Environment: `development`, `test`, `production` |

## Workflow

### Step 1: Detect Application Type

Scan the project directory for framework indicators. Check files in priority
order (first match wins):

| Priority | Config File | Framework | Type |
|----------|-------------|-----------|------|
| 1 | `domo-manifest.json` | Domo Custom App | domo |
| 2 | `src-tauri/tauri.conf.json` | Tauri desktop app | desktop |
| 3 | `electron.config.*` or `main.js` + electron dep | Electron | desktop |
| 4 | `playwright.config.*` | (test project, not an app) | skip |
| 5 | `next.config.*` | Next.js | web |
| 6 | `nuxt.config.*` | Nuxt | web |
| 7 | `svelte.config.*` | SvelteKit | web |
| 8 | `vite.config.*` + no framework | Vite SPA | web |
| 9 | `angular.json` | Angular | web |
| 10 | `mix.exs` + `:phoenix` dep | Phoenix | web |
| 11 | `manage.py` | Django | web |
| 12 | `requirements.txt` + flask/fastapi | Flask/FastAPI | api |
| 13 | `Cargo.toml` + actix/axum/rocket dep | Rust web | api |
| 14 | `go.mod` + net/http or gin/echo | Go web | api |
| 15 | `package.json` + `start` script | Node.js | api |
| 16 | `Makefile` | Generic | cli |
| 17 | Binary file in project root | CLI tool | cli |

For each detection, extract:
- **Framework name** and version
- **Start command** (from scripts, config, or convention)
- **Expected URL/port** (from config or convention)
- **Dependency install command**

If `--detect-only`, output detection results and stop.

### Step 2: Install Dependencies

Unless `--skip-install`, run the appropriate install command:

| Framework | Install Command | Verify |
|-----------|----------------|--------|
| Node.js (any) | `npm install` (or `yarn` / `pnpm` if lockfile present) | `node_modules/` exists |
| Elixir | `mix deps.get && mix compile` | `_build/` exists |
| Python | `pip install -r requirements.txt` (or `poetry install`) | Check import |
| Rust | `cargo build` | `target/` exists |
| Go | `go mod download` | Module cache populated |
| Domo | `npm install` | `node_modules/` exists |

Capture install output. If install fails, report the error and abort.

### Step 3: Start Application

Start the application in background and capture the PID:

```bash
# General pattern
$START_COMMAND > .qa-startup.log 2>&1 &
APP_PID=$!
echo "Started PID: $APP_PID"
```

Framework-specific start commands:

| Framework | Dev Command | Test Command | Env Vars |
|-----------|------------|--------------|----------|
| Next.js | `npm run dev` | `npm run dev` | `NODE_ENV=test` |
| SvelteKit | `npm run dev` | `npm run dev` | `NODE_ENV=test` |
| Vite | `npx vite` | `npx vite` | `NODE_ENV=test` |
| Phoenix | `mix phx.server` | `MIX_ENV=test mix phx.server` | `MIX_ENV` |
| Django | `python manage.py runserver` | `python manage.py runserver --settings=project.test_settings` | `DJANGO_SETTINGS_MODULE` |
| FastAPI | `uvicorn main:app` | `uvicorn main:app` | — |
| Domo | `domo dev` | `domo dev` | — |
| Tauri | `npm run tauri dev` | `npm run tauri dev` | — |
| Go | `go run .` | `go run .` | — |
| Rust | `cargo run` | `cargo run` | — |

### Step 4: Health Check

Probe the application for readiness using the configured probe type:

**HTTP probe** (default for web/api):
```bash
for attempt in $(seq 1 $MAX_ATTEMPTS); do
  if curl -sf --max-time 5 "$HEALTH_URL" > /dev/null 2>&1; then
    echo "App ready after ${attempt} attempts"
    break
  fi
  sleep $INTERVAL
done
```

**TCP probe** (for non-HTTP services):
```bash
for attempt in $(seq 1 $MAX_ATTEMPTS); do
  if nc -z localhost $PORT 2>/dev/null; then
    echo "Port $PORT open after ${attempt} attempts"
    break
  fi
  sleep $INTERVAL
done
```

**Stdout probe** (for apps that log readiness):
```bash
timeout $TIMEOUT tail -f .qa-startup.log | grep -m1 "$PATTERN"
```

**Process probe** (just verify the process is running):
```bash
if kill -0 $APP_PID 2>/dev/null; then
  echo "Process $APP_PID is running"
fi
```

If the probe fails after `--timeout` seconds:
- Capture last 50 lines of stdout/stderr
- Check if process is still running or crashed
- Report failure with diagnostics

### Step 5: Output Metadata

Return structured startup metadata:

```json
{
  "status": "ready",
  "pid": 12345,
  "framework": "sveltekit",
  "type": "web",
  "url": "http://localhost:5173",
  "port": 5173,
  "start_command": "npm run dev",
  "startup_duration_ms": 4200,
  "install_duration_ms": 8500,
  "probe_type": "http",
  "probe_attempts": 3,
  "log_file": ".qa-startup.log"
}
```

On failure:

```json
{
  "status": "failed",
  "error": "Startup timeout after 120s",
  "exit_code": null,
  "last_output": "Error: Cannot find module 'svelte'...",
  "framework": "sveltekit",
  "type": "web",
  "start_command": "npm run dev",
  "startup_duration_ms": 120000
}
```

## Shutdown

When invoked with `--shutdown`:

```bash
# Graceful shutdown
kill $PID
sleep 2

# Force kill if still running
if kill -0 $PID 2>/dev/null; then
  kill -9 $PID
fi

# Cleanup
rm -f .qa-startup.log
```

## Examples

```bash
# Start a SvelteKit app and get the URL
/startup-probe
# Output: { "status": "ready", "url": "http://localhost:5173", "pid": 12345 }

# Start a Phoenix API server
/startup-probe --type api --health-url http://localhost:4000/api/health
# Output: { "status": "ready", "url": "http://localhost:4000", "pid": 12346 }

# Start a Domo app
/startup-probe --type domo
# Output: { "status": "ready", "url": "https://localhost:3000", "pid": 12347 }

# Check if Redis is running
/startup-probe --probe tcp --port 6379 --skip-install
# Output: { "status": "ready", "port": 6379 }

# Detect only — don't start
/startup-probe --detect-only
# Output: { "framework": "sveltekit", "type": "web", "start_command": "npm run dev" }
```

## Dependencies

- `curl` — HTTP health checks
- `nc` (netcat) — TCP port checks
- Package managers: npm/yarn/pnpm, mix, pip/poetry, cargo, go
- Process management: bash job control, `kill`
