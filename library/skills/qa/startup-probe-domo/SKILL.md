---
name: qa/startup-probe-domo
description: >
  Start Domo Custom Apps for QA testing. Authenticates with `domo login` using
  env-injected credentials (DOMO_INSTANCE, DOMO_TOKEN), starts the app via
  `domo dev`, and health-checks via TLS-tolerant HTTPS probes. Returns structured
  metadata compatible with /startup-probe output.
  Triggers on: "domo app test", "start domo", "domo dev", "domo startup",
  "launch domo app", "test domo app"
required_integrations:
  - provider: domo
required_tools:
  - bash
---

# /startup-probe-domo

> Start a Domo Custom App for QA testing.

## Purpose

Specialization of `/startup-probe` for Domo Custom Apps. Handles the unique
requirements: non-interactive `domo login` via Developer Token, `domo dev`
with TLS on `https://localhost:3000`, and proxyId-aware health checks.

## Prerequisites

The following environment variables must be available (injected by
`IntegrationResolver` from a bound `domo` integration):

| Env Var | Source | Description |
|---------|--------|-------------|
| `DOMO_INSTANCE` | integration config | Domo instance domain (e.g. `company.domo.com`) |
| `DOMO_TOKEN` | integration secret | Developer Token for authentication |
| `DOMO_PROXY_ID` | integration config | Card UUID for local dev proxy (required for AppDB/Workflows) |

## Workflow

### Step 1: Detect Domo App

Check for `domo-manifest.json` in the project root. If missing, fall back to
generic `/startup-probe`.

```bash
if [ ! -f "domo-manifest.json" ]; then
  echo '{"status": "not_domo", "fallback": "startup-probe"}'
  exit 0
fi
```

### Step 2: Authenticate

```bash
domo login --instance "$DOMO_INSTANCE" --token "$DOMO_TOKEN"
```

If `domo` CLI is not installed, install via npm:
```bash
npm install -g @domoinc/ryuu
```

### Step 3: Install Dependencies

```bash
npm install
```

### Step 4: Start App

```bash
domo dev > .qa-startup.log 2>&1 &
APP_PID=$!
echo "Started Domo dev server PID: $APP_PID"
```

### Step 5: Health Check (TLS-tolerant)

Domo dev server runs on HTTPS with self-signed cert:

```bash
MAX_ATTEMPTS=30
INTERVAL=2
URL="https://localhost:3000"

for attempt in $(seq 1 $MAX_ATTEMPTS); do
  if curl -sf --insecure --max-time 5 "$URL" > /dev/null 2>&1; then
    echo "Domo app ready after ${attempt} attempts"
    break
  fi
  sleep $INTERVAL
done
```

Fallback: check stdout for "app is running on port" pattern.

### Step 6: Output Metadata

```json
{
  "status": "ready",
  "pid": 12345,
  "framework": "domo",
  "type": "domo",
  "url": "https://localhost:3000",
  "port": 3000,
  "tls": true,
  "start_command": "domo dev",
  "startup_duration_ms": 6500,
  "instance": "company.domo.com",
  "proxy_id": "abc-123-def",
  "manifest": {
    "name": "my-domo-app",
    "version": "1.0.0",
    "size": {"width": 4, "height": 4}
  },
  "log_file": ".qa-startup.log"
}
```

## Shutdown

```bash
kill $PID
sleep 2
if kill -0 $PID 2>/dev/null; then
  kill -9 $PID
fi
rm -f .qa-startup.log
```

## Domo-Specific QA Checks After Startup

Once running, the QA agent should exercise:
1. **Card size rendering** at manifest dimensions (use Playwright viewport resize)
2. **AppDB security filters** — switch `X-DOMO-Ryuu-Token` per test profile
3. **Data binding** via `https://localhost:3000/data/v1/{alias}`
4. **Code Engine responses** — verify statusCode/body structure
5. **Embed token auth** — test with valid and expired tokens

## Dependencies

- `domo` CLI (`@domoinc/ryuu`) — auto-installed if missing
- `curl` with `--insecure` flag
- npm / node
- `/startup-probe` — fallback for non-Domo apps
