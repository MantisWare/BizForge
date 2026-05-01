# Phase: Headless Workspace Execution

> Run any Bizforge workspace fully autonomously — no GUI required.
> Set up in the Command Center, deploy via CLI, monitor from a minimal stats dashboard.

---

## Overview

This phase adds the ability to take a fully configured Bizforge workspace (agents, teams, budgets, governance, workflows — everything) and run it **headlessly** via a CLI or a lightweight stats-only window. The workflow is:

1. **Configure** — Use the Desktop Command Center to create your workspace, hire agents, define teams, set budgets, wire up workflows, and configure governance. Everything you already do today.
2. **Export / Lock** — Freeze the workspace configuration into a deployable snapshot.
3. **Run Headless** — Launch the workspace from the CLI. All agents execute on their heartbeat schedules, tasks flow, budgets enforce, governance gates fire — zero GUI interaction required.
4. **Monitor** — Optionally open a secret, minimal stats dashboard window that shows real-time system health, agent activity, token burn, and key metrics. No editing, no navigation — just observability.

---

## CLI Command Reference

| Command | Description |
|---------|-------------|
| `bizforge run <workspace-path>` | Boot backend, load workspace, start all heartbeats |
| `bizforge stop` | Graceful shutdown with session compaction |
| `bizforge status` | Print running agents, active tasks, budget usage, system health |
| `bizforge logs` | Tail agent activity logs (structured, filterable) |
| `bizforge pause` / `resume` | Pause/resume heartbeats without killing sessions |
| `bizforge config show` | Display loaded workspace configuration summary |
| `bizforge config validate` | Validate workspace files before running |
| `bizforge snapshot create <name>` | Serialize workspace into a deployable snapshot |
| `bizforge snapshot list` | List available snapshots |
| `bizforge snapshot restore <name>` | Restore workspace from a snapshot |
| `bizforge monitor` | Open the stats dashboard (TUI or Tauri window) |
| `bizforge list` | Show all running headless workspace instances |
| `bizforge attach <workspace>` | Connect to a running instance's log stream |

### Flags

| Flag | Description |
|------|-------------|
| `--detach` | Run as a background daemon |
| `--dry-run` | Simulate boot without executing heartbeats |
| `--monitor` | Open stats dashboard alongside `bizforge run` |

---

## Stats Dashboard

A secret, minimal single-window application (or TUI) designed purely for observability. No editing, no navigation — just live data.

### Panels

| Panel | Content |
|-------|---------|
| **System Health** | CPU, memory, uptime, active processes |
| **Agent Activity** | Active, idle, paused, errored agents with current task |
| **Task Flow** | Tasks in progress, completed, blocked, failed |
| **Token Burn** | Per-agent and aggregate cost graph, live-updating |
| **Budget Gauge** | Per-agent and workspace-level budget remaining |
| **Heartbeat Timeline** | Visual timeline of agent heartbeat executions |
| **Log Stream** | Scrolling, filterable log output |
| **Alerts** | Governance blocks, budget breaches, adapter failures |

### Controls

- Pause all / Resume all / Stop workspace / Force-compact sessions
- Keyboard shortcuts for panel navigation

---

## Architecture Notes

### Headless Boot Sequence

```
bizforge run <workspace-path>
  -> Load .env + CLI overrides
  -> Validate workspace (SYSTEM.md, company.yaml, agent manifests)
  -> Boot Elixir runtime (Mix release or Burrito binary)
  -> Connect to PostgreSQL
  -> Hydrate workspace state from snapshot or live files
  -> Lock workspace (prevent concurrent edits)
  -> Start heartbeat scheduler for all agents
  -> Start workflow scheduler
  -> Start budget enforcement (ETS counters)
  -> Start governance gate listeners
  -> Write PID file
  -> Enter main loop (agents run autonomously)
  -> On SIGTERM/SIGINT: compact all sessions, unlock workspace, clean up PID
```

### Workspace Snapshots

A snapshot captures everything needed to reproduce a workspace state:

- Agent manifests and configurations
- Team structures and memberships
- Budget allocations and current spend
- Workflow definitions and schedules
- Governance rules and pending approvals
- Adapter configurations
- Organizational hierarchy

Snapshots are versioned and integrity-checked (SHA-256 hash of all constituent files).

### Process Management

- **PID files** — one per headless instance, stored in `.bizforge/pids/`
- **Multi-workspace** — each workspace runs as its own process with its own port
- **Supervision** — launchd plist (macOS), systemd unit (Linux), or built-in OTP supervisor
- **Crash recovery** — auto-resume from last compacted session state
- **Resource limits** — configurable max concurrent agents, memory ceiling, token spend per hour

### External Observability

- Prometheus-compatible `/metrics` endpoint
- Structured JSON log mode for log aggregation (ELK, Loki)
- Webhook notifications for key events
- Slack integration for alerts
- Email digest for periodic summaries
- Dead man's switch (heartbeat ping to external URL)

---

## Open Questions

- **TUI vs. Tauri window for stats dashboard?** A TUI (e.g., Ratatui for Rust, or a terminal app) keeps everything in the terminal. A minimal Tauri window allows richer graphs but adds a dependency. Could support both.
- **Remote monitoring?** Should the stats dashboard be able to connect to a headless instance running on another machine? If so, we need a lightweight API and auth.
- **Workspace hot-reload?** Should modifying workspace files (e.g., adding a new agent) while running headlessly trigger a live reload, or require a restart?
- **Multi-workspace orchestration?** Should `bizforge run` support launching multiple workspaces in a single process, or always one-per-process?

---

## Dependencies

- Existing heartbeat system (already functional)
- Existing budget enforcement (already functional)
- Existing governance gates (already functional)
- Existing session compaction (already functional)
- Existing workflow engine (already functional)
- Elixir release tooling (Mix releases, Burrito, or Bakeware for standalone binary)
- Tauri or Ratatui for stats dashboard UI

---

## Implementation Status

### Completed

| Component | Files | Description |
|-----------|-------|-------------|
| Mix release config | `backend/mix.exs` | Release definition with overlay support |
| CLI entrypoint | `backend/lib/bizforge/cli.ex` | Arg parser and subcommand dispatch |
| CLI: run | `backend/lib/bizforge/cli/run.ex` | Workspace validation, headless boot, --detach/--dry-run |
| CLI: stop | `backend/lib/bizforge/cli/stop.ex` | PID-based graceful shutdown |
| CLI: status | `backend/lib/bizforge/cli/status.ex` | Instance and health endpoint status |
| CLI: logs | `backend/lib/bizforge/cli/logs.ex` | Log tailing with level/agent filters |
| CLI: config | `backend/lib/bizforge/cli/config.ex` | show and validate subcommands |
| CLI: snapshot | `backend/lib/bizforge/cli/snapshot.ex` | create/list/restore with integrity hashing |
| CLI: pause/resume | `backend/lib/bizforge/cli/pause.ex`, `resume.ex` | Schedule control |
| CLI: list | `backend/lib/bizforge/cli/list.ex` | Running instance discovery |
| CLI: monitor | `backend/lib/bizforge/cli/monitor.ex` | Stats dashboard launcher |
| Headless Monitor | `backend/lib/bizforge/headless/monitor.ex` | PID file, signals, graceful shutdown |
| Headless Bootstrap | `backend/lib/bizforge/headless/bootstrap.ex` | Agent auto-start, adapter checks |
| Headless Watchdog | `backend/lib/bizforge/headless/watchdog.ex` | Stuck/crashed agent recovery |
| Conditional boot | `backend/lib/bizforge/application.ex` | BIZFORGE_HEADLESS switches children |
| Runtime config | `backend/config/runtime.exs` | Headless env vars |
| Release overlay | `backend/rel/overlays/bin/bizforge` | CLI shell wrapper |
| Just recipes | `justfile` | headless, headless-stop, headless-status, headless-logs |
| Snapshots context | `backend/lib/bizforge/snapshots.ex` | Snapshot orchestration and workspace locking |
| Snapshot exporter | `backend/lib/bizforge/snapshots/exporter.ex` | DB + filesystem serialization |
| Snapshot importer | `backend/lib/bizforge/snapshots/importer.ex` | DB hydration and file restoration |
| CLI: attach | `backend/lib/bizforge/cli/attach.ex` | Log stream attachment to running instance |
| Webhook notifier | `backend/lib/bizforge/headless/notifier.ex` | HTTP webhook dispatch with retry |
| Prometheus metrics | `backend/lib/bizforge_web/controllers/metrics_controller.ex` | /metrics endpoint |
| JSON logger | `backend/lib/bizforge/headless/json_logger.ex` | Structured JSON log formatter |
| API key auth | `backend/lib/bizforge_web/plugs/api_key_auth.ex` | Bearer token auth for headless API |
| Monitor layout | `desktop/src/routes/monitor/+layout.svelte` | Standalone dark-theme shell |
| Monitor page | `desktop/src/routes/monitor/+page.svelte` | 9-panel grid dashboard |
| Monitor store | `desktop/src/lib/stores/monitor.svelte.ts` | API + SSE data aggregation |
| WorkspaceHeader | `desktop/src/lib/components/monitor/WorkspaceHeader.svelte` | Name, uptime, counts |
| SystemHealth | `desktop/src/lib/components/monitor/SystemHealth.svelte` | Status, version, checks |
| AgentActivity | `desktop/src/lib/components/monitor/AgentActivity.svelte` | Status badges, agent list |
| TaskFlow | `desktop/src/lib/components/monitor/TaskFlow.svelte` | Task counts and bar chart |
| TokenBurn | `desktop/src/lib/components/monitor/TokenBurn.svelte` | Cost and token breakdown |
| BudgetGauge | `desktop/src/lib/components/monitor/BudgetGauge.svelte` | SVG radial gauge |
| HeartbeatTimeline | `desktop/src/lib/components/monitor/HeartbeatTimeline.svelte` | Event timeline |
| LogStream | `desktop/src/lib/components/monitor/LogStream.svelte` | Filterable scrolling logs |
| AlertPanel | `desktop/src/lib/components/monitor/AlertPanel.svelte` | Active alert cards |
| QuickActions | `desktop/src/lib/components/monitor/QuickActions.svelte` | Pause/Resume/Stop buttons |
| Tauri window | `desktop/src-tauri/tauri.conf.json` | Monitor window definition |
| Tauri capabilities | `desktop/src-tauri/capabilities/default.json` | Monitor window permissions |

### Remaining

- Governance auto-resolution for headless mode
- Dedicated health check endpoint on separate port (currently uses main port)
- Workspace snapshot versioning and rollback
- Multi-workspace concurrent execution
- Resource limits (max concurrent agents, memory, token spend)
- Slack integration for alerts
- Email digest summaries
- Dead man's switch (external heartbeat ping)
- Role-based dashboard access
- TLS for remote dashboard
- Session token rotation

---

> **Auto-updated by Cursor:** Created headless phase document on 2026-04-30.
> **Auto-updated by Cursor:** Implemented CLI Foundation, Headless Runtime, and Process Management on 2026-04-30.
> **Auto-updated by Cursor:** Implemented snapshots (exporter/importer/lock), stats dashboard (10 panels + Tauri window), process management (attach/crash recovery), and observability (webhooks, Prometheus, JSON logging, API key auth) on 2026-04-30.
