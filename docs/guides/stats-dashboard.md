# Stats Dashboard User Guide

The Stats Dashboard is a minimal, information-dense monitoring interface for headless BizForge instances. It provides real-time observability without any editing or navigation — just live data.

---

## Accessing the Dashboard

### From the Desktop App

Click the "Monitor" button in the Command Center, or use the keyboard shortcut. The dashboard opens in a separate Tauri window.

### From the CLI

```bash
# Auto-discovers running instance and opens TUI
bizforge monitor

# Force TUI mode (no Tauri window)
bizforge monitor --tui

# Connect to a specific workspace
bizforge monitor --workspace sales-engine
```

### Via Browser

Navigate to `http://localhost:5200/monitor?workspace=<name>` when the desktop dev server is running.

---

## Dashboard Panels

### Workspace Header

Displays the workspace name, total uptime, active agent count, and total tasks. Provides at-a-glance workspace identity.

### System Health

| Metric | Description |
|--------|-------------|
| Status | Overall health: healthy, degraded, or critical |
| Memory | Current VM memory usage in MB |
| Processes | BEAM process count |
| Schedulers | Active CPU schedulers |

### Agent Activity

Shows all agents grouped by status:
- **Active** (green) — Currently executing or ready for work
- **Idle** (blue) — Waiting for next heartbeat
- **Working** (yellow) — Currently in a heartbeat execution
- **Paused** (gray) — Suspended by operator or resource limit
- **Error** (red) — Failed and awaiting recovery

Each agent shows its name, current task (if any), and time in current state.

### Task Flow

Visual breakdown of task pipeline:
- In Progress — Being worked on right now
- Completed — Successfully finished
- Blocked — Awaiting dependency or approval
- Failed — Errored during execution

### Token Burn

Live-updating cost graph showing:
- Per-agent token consumption
- Aggregate workspace spend rate
- Projected daily/monthly cost at current rate

### Budget Gauge

SVG radial gauge showing budget utilization:
- Green zone (0-79%) — Normal operation
- Yellow zone (80-99%) — Soft alert territory
- Red zone (100%) — Hard stop enforced

Displayed per-agent and at workspace level.

### Heartbeat Timeline

Chronological view of agent heartbeat executions:
- Green markers — Successful heartbeats
- Red markers — Failed heartbeats
- Gray markers — Skipped (paused or blocked)

Scroll horizontally to see history.

### Log Stream

Scrolling, filterable log output from all headless processes:
- Filter by level: debug, info, warning, error
- Filter by source: agent name, module name
- Auto-scroll to latest (toggle off to inspect history)

### Alert Panel

Active alerts requiring attention:
- Governance blocks (pending approvals)
- Budget breaches (approaching or at limit)
- Adapter failures (unreachable backends)
- Agent errors (recovery exhausted)

---

## Quick Actions

Controls available in the dashboard header:

| Action | Effect |
|--------|--------|
| **Pause All** | Deactivate all heartbeat schedules |
| **Resume All** | Reactivate all heartbeat schedules |
| **Stop Workspace** | Initiate graceful shutdown |
| **Force Compact** | Compact all active sessions immediately |

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `p` | Pause all agents |
| `r` | Resume all agents |
| `q` | Quit / close dashboard |
| `l` | Focus log stream |
| `a` | Focus agent panel |
| `t` | Focus task panel |
| `h` | Focus heartbeat timeline |
| `Esc` | Unfocus / back to overview |

---

## TUI Mode

When running `bizforge monitor --tui`, the terminal displays a simplified text-based dashboard:

```
  BizForge Headless Monitor
  ─────────────────────────
  Status:    healthy
  Uptime:    2h 15m 33s

  Agents
    Active:  12
    Errored: 0
    Paused:  2

  Tasks
    Active:    5
    Completed: 47

  System
    Memory:     256 MB
    Processes:  1,203
    Schedulers: 8

  Last update: 2026-04-30T19:45:12Z
```

Refreshes every 5 seconds. Press Ctrl+C to exit.

---

## Connecting to Remote Instances

The dashboard can monitor headless instances running on other machines:

1. Ensure the remote instance has `BIZFORGE_HEALTH_PORT` accessible (firewall/security group)
2. Optionally enable TLS: set `BIZFORGE_TLS_CERT` and `BIZFORGE_TLS_KEY` on the remote
3. Set `BIZFORGE_API_KEY` on the remote for authentication
4. Connect from the desktop app by entering the remote URL in monitor settings

For production deployments, always use a reverse proxy with TLS termination rather than exposing the health port directly.

---

## Data Sources

The dashboard pulls data from:

| Source | Endpoint | Update Interval |
|--------|----------|-----------------|
| Health status | `GET /health` (port 9090) | 5 seconds |
| Agent list | `GET /api/v1/agents` (port 9089) | 10 seconds |
| Cost data | `GET /api/v1/costs` (port 9089) | 30 seconds |
| Tasks | `GET /api/v1/issues` (port 9089) | 10 seconds |
| Activity stream | SSE `/api/v1/activity/stream` | Real-time |

In pure headless mode (no Phoenix endpoint), only the `/health` endpoint on the health port is available. The TUI monitor uses this single endpoint.
