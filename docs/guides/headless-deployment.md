# Headless Deployment Guide

Deploy Bizforge workspaces as autonomous headless services — no GUI required.

---

## Prerequisites

- Elixir 1.15+ / Erlang 26+
- PostgreSQL 15+ (running and accessible)
- A configured workspace (agents, teams, budgets, schedules)
- `.env` file with `DATABASE_URL`, `SECRET_KEY_BASE`, `GUARDIAN_SECRET_KEY`

---

## Quick Start

```bash
# From project root with a configured workspace
bizforge run ./operations/sales-engine

# Or using just
just headless ./operations/sales-engine
```

---

## Environment Variables

### Core

| Variable | Default | Description |
|----------|---------|-------------|
| `BIZFORGE_HEADLESS` | `false` | Enable headless mode |
| `BIZFORGE_WORKSPACE_PATH` | `.` | Path to workspace directory |
| `BIZFORGE_HEALTH_PORT` | `9090` | Health check endpoint port |
| `BIZFORGE_PID_DIR` | `.bizforge/pids` | PID file directory |
| `BIZFORGE_LOG_FORMAT` | `text` | Log format (`text` or `json`) |
| `BIZFORGE_API_KEY` | — | API key for CLI/dashboard auth |

### Resource Limits

| Variable | Default | Description |
|----------|---------|-------------|
| `BIZFORGE_MAX_AGENTS` | unlimited | Maximum concurrent active agents |
| `BIZFORGE_MAX_MEMORY_MB` | unlimited | Memory ceiling (MB) |
| `BIZFORGE_MAX_TOKENS_PER_HOUR` | unlimited | Token spend rate limit |

### Notifications

| Variable | Default | Description |
|----------|---------|-------------|
| `BIZFORGE_WEBHOOK_URL` | — | Webhook endpoint for event notifications |
| `BIZFORGE_WEBHOOK_SECRET` | — | HMAC secret for webhook signatures |
| `BIZFORGE_SLACK_WEBHOOK_URL` | — | Slack incoming webhook URL |
| `BIZFORGE_HEARTBEAT_URL` | — | Dead man's switch ping URL |
| `BIZFORGE_HEARTBEAT_INTERVAL` | `60` | Ping interval in seconds |

### Email Digest

| Variable | Default | Description |
|----------|---------|-------------|
| `BIZFORGE_EMAIL_FROM` | — | Sender email address |
| `BIZFORGE_EMAIL_TO` | — | Recipient email address |
| `BIZFORGE_SMTP_HOST` | — | SMTP server hostname |
| `BIZFORGE_SMTP_PORT` | `587` | SMTP port |
| `BIZFORGE_SMTP_USERNAME` | — | SMTP auth username |
| `BIZFORGE_SMTP_PASSWORD` | — | SMTP auth password |
| `BIZFORGE_EMAIL_DIGEST_MODE` | `hourly` | Digest mode: `hourly`, `daily`, or `on_error` |

### Security

| Variable | Default | Description |
|----------|---------|-------------|
| `BIZFORGE_TLS_CERT` | — | TLS certificate file path |
| `BIZFORGE_TLS_KEY` | — | TLS private key file path |
| `BIZFORGE_TOKEN_ROTATION_HOURS` | `24` | API key rotation interval |
| `BIZFORGE_TOKEN_GRACE_HOURS` | `1` | Old key grace period after rotation |

---

## Deployment Modes

### Foreground (Development)

```bash
bizforge run ./operations/sales-engine
```

Runs in the current terminal. Ctrl+C to stop gracefully.

### Background (Production)

```bash
bizforge run ./operations/sales-engine --detach
```

Writes PID file and exits. Use `bizforge stop` to shut down.

### With Monitor

```bash
bizforge run ./operations/sales-engine --monitor
```

Starts the headless runtime and opens a TUI stats display.

---

## systemd Service (Linux)

Create `/etc/systemd/system/bizforge.service`:

```ini
[Unit]
Description=BizForge Headless Workspace
After=network.target postgresql.service

[Service]
Type=simple
User=bizforge
Group=bizforge
WorkingDirectory=/opt/bizforge
EnvironmentFile=/opt/bizforge/.env
ExecStart=/opt/bizforge/bin/bizforge run /opt/bizforge/operations/sales-engine
ExecStop=/opt/bizforge/bin/bizforge stop
Restart=on-failure
RestartSec=10
KillSignal=SIGTERM
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable bizforge
sudo systemctl start bizforge
sudo systemctl status bizforge
```

---

## launchd Service (macOS)

Create `~/Library/LaunchAgents/com.bizforge.headless.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.bizforge.headless</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/bizforge</string>
        <string>run</string>
        <string>/Users/you/bizforge/operations/sales-engine</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>BIZFORGE_HEADLESS</key>
        <string>true</string>
        <key>DATABASE_URL</key>
        <string>postgres://localhost/bizforge_prod</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/bizforge.out.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/bizforge.err.log</string>
</dict>
</plist>
```

```bash
launchctl load ~/Library/LaunchAgents/com.bizforge.headless.plist
```

---

## Reverse Proxy (nginx)

For remote monitoring with TLS termination:

```nginx
server {
    listen 443 ssl;
    server_name bizforge-monitor.your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    location /health {
        proxy_pass http://127.0.0.1:9090;
        proxy_set_header Host $host;
    }

    location /metrics {
        proxy_pass http://127.0.0.1:9090;
        proxy_set_header Host $host;
    }
}
```

---

## Monitoring Setup

### Prometheus

Add to `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'bizforge'
    scrape_interval: 30s
    static_configs:
      - targets: ['localhost:9090']
    metrics_path: /metrics
```

### Grafana

Import the BizForge dashboard (available metrics):

- `bizforge_agents_active` — Active agent count
- `bizforge_agents_errored` — Errored agent count
- `bizforge_sessions_active` — Active session count
- `bizforge_memory_bytes` — VM memory usage
- `bizforge_process_count` — BEAM process count

### Dead Man's Switch

Compatible services:

- [Healthchecks.io](https://healthchecks.io)
- [Cronitor](https://cronitor.io)
- [Better Uptime](https://betteruptime.com)

Set `BIZFORGE_HEARTBEAT_URL` to the check-in URL provided by your service.

---

## Multi-Workspace Deployment

Run multiple workspaces on the same machine:

```bash
BIZFORGE_HEALTH_PORT=9090 bizforge run ./operations/sales-engine --detach
BIZFORGE_HEALTH_PORT=9091 bizforge run ./operations/dev-shop --detach
BIZFORGE_HEALTH_PORT=9092 bizforge run ./operations/content-factory --detach

# List all running instances
bizforge list
```

Each workspace gets its own:
- PID file (in `.bizforge/pids/`)
- Meta file (with port and workspace info)
- Health endpoint (on its assigned port)

---

## Snapshots and Rollback

### Create a snapshot before deploying

```bash
bizforge snapshot create pre-deploy-v2 ./operations/sales-engine
```

### Roll back if something goes wrong

```bash
bizforge snapshot rollback 1
```

### View version history

```bash
bizforge snapshot versions
```

### Compare versions

```bash
bizforge snapshot diff 1 2
```
