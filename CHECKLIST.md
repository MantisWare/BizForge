# Bizforge Checklist

Active development phases and their progress.

---

## Phase: Headless Workspace Execution

> Run any configured workspace fully autonomously via CLI, monitor from a minimal stats dashboard.
> Full design document: [`docs/phases/headless-workspace-execution.md`](docs/phases/headless-workspace-execution.md)

### 1. CLI Foundation

- [x] Design CLI command structure (`bizforge run`, `bizforge status`, `bizforge stop`, etc.)
- [x] Implement CLI entry point (Mix release with `Bizforge.CLI` module and overlay script)
- [x] Add `bizforge run <workspace-path>` — boots the backend, loads workspace, starts all heartbeats
- [x] Add `bizforge stop` — graceful shutdown with session compaction for all active agents
- [x] Add `bizforge status` — print running agents, active tasks, budget usage, system health
- [x] Add `bizforge logs` — tail agent activity logs in the terminal (structured, filterable)
- [x] Add `bizforge pause` / `bizforge resume` — pause/resume all heartbeats without killing sessions
- [x] Add `bizforge config show` — display the loaded workspace configuration summary
- [x] Add `bizforge config validate` — validate workspace files before running
- [x] Support `.env` and CLI flags for configuration overrides (ports, database URL, adapter credentials)
- [x] Add `--detach` flag for running as a background daemon
- [x] Add `--dry-run` flag to simulate a full boot without executing any agent heartbeats

### 2. Workspace Snapshot & Locking

- [x] Design snapshot schema (what constitutes a "deployable workspace state")
- [x] Implement workspace export: serialize agents, teams, budgets, workflows, governance into a portable format
- [x] Implement workspace import: load a snapshot and hydrate the database
- [x] Add workspace lock mechanism — prevent edits while running headlessly
- [ ] Add workspace versioning (track snapshot history, allow rollback)
- [x] Add integrity check — hash-based verification that workspace files haven't drifted from snapshot
- [x] Add `bizforge snapshot create <name>` CLI command
- [x] Add `bizforge snapshot list` CLI command
- [x] Add `bizforge snapshot restore <name>` CLI command

### 3. Headless Backend Runtime

- [x] Refactor backend boot sequence to support headless mode (no Phoenix endpoint for agents-only mode)
- [x] Ensure heartbeat scheduler starts all agents automatically on boot
- [x] Ensure budget enforcement works without any GUI interaction
- [ ] Ensure governance gates can auto-resolve or queue for external review (webhook/Slack/email)
- [x] Ensure session compaction and handoff generation run autonomously
- [x] Ensure workflow engine triggers on schedule without manual intervention
- [ ] Add headless-specific health check endpoint (`/health` or Unix socket)
- [x] Implement graceful degradation — pause affected agents if adapter unavailable
- [x] Add watchdog process — auto-restart crashed agents with exponential backoff
- [x] Implement signal handling (SIGTERM, SIGINT, SIGHUP) for clean shutdown and config reload

### 4. Stats Dashboard (Secret Window)

- [x] Design stats dashboard layout (single-window, dark theme, information-dense)
- [x] Implement system health overview panel (CPU, memory, uptime, active processes)
- [x] Implement agent activity panel (active, idle, paused, errored agents)
- [x] Implement real-time task flow visualization (in progress, completed, blocked, failed)
- [x] Implement token/cost burn rate graph (per-agent and aggregate, live-updating)
- [x] Implement budget gauge (per-agent and workspace-level budget remaining)
- [x] Implement heartbeat timeline (visual timeline of agent heartbeat executions)
- [x] Implement log stream panel (scrolling, filterable log output)
- [x] Implement alert/error panel (governance blocks, budget breaches, adapter failures)
- [x] Add workspace summary header (workspace name, uptime, total agents, total tasks)
- [x] Add quick-action controls (pause all, resume all, stop workspace, force-compact sessions)
- [ ] Launch via `bizforge monitor` or `bizforge run --monitor` flag
- [x] Implement as a minimal Tauri window (separate from Command Center) or TUI (terminal UI)
- [ ] Support auto-connect to a running headless instance (via PID file or Unix socket)
- [x] Add keyboard shortcuts for navigation and actions

### 5. Process Management & Daemonization

- [x] Implement PID file management for headless instances
- [ ] Add support for running multiple workspaces concurrently (each with its own PID and port)
- [x] Implement process supervision (OTP supervisor with Monitor, Bootstrap, Watchdog)
- [x] Add `bizforge list` — show all running headless workspace instances
- [x] Add `bizforge attach <workspace>` — connect to a running instance's log stream
- [x] Add crash recovery — auto-resume from last known state on unexpected termination
- [ ] Implement resource limits (max concurrent agents, max memory, max token spend per hour)

### 6. Notifications & External Observability

- [x] Add webhook notifications for key events (agent error, budget breach, governance block, workspace stopped)
- [ ] Add Slack integration for headless mode alerts
- [ ] Add email digest option (periodic summary of workspace activity)
- [x] Expose Prometheus-compatible metrics endpoint for external monitoring
- [x] Add structured JSON log output mode for log aggregation (ELK, Loki, etc.)
- [ ] Add optional heartbeat ping to external URL (dead man's switch)

### 7. Security & Access Control

- [x] Implement API key authentication for CLI commands against running instances
- [ ] Add role-based access for stats dashboard (read-only vs. operator)
- [ ] Ensure secrets/credentials are never logged or exposed in stats dashboard
- [ ] Add TLS support for remote stats dashboard connections
- [ ] Implement session token rotation for long-running headless instances

### 8. Testing & Validation

- [ ] Add integration tests for full headless boot-to-shutdown lifecycle
- [ ] Add tests for workspace snapshot create/restore roundtrip
- [ ] Add tests for CLI command parsing and execution
- [ ] Add load tests — run workspace with 50+ agents headlessly and verify stability
- [ ] Add chaos tests — kill adapters, saturate budgets, trigger governance blocks during headless run
- [ ] Add tests for stats dashboard data accuracy (metrics match actual state)
- [ ] Add tests for graceful shutdown (all sessions compacted, no orphaned tasks)

### 9. Documentation

- [x] Write CLI reference documentation (all commands, flags, examples)
- [ ] Write headless deployment guide (setup, configuration, monitoring)
- [ ] Write stats dashboard user guide
- [ ] Add architecture doc for headless runtime mode
- [ ] Add troubleshooting guide for common headless issues
- [x] Update README with headless mode section
- [x] Add headless mode article to in-app Wiki

---

## Phase: Domo Developer Agent & Skills Suite

> Specialized Domo platform developer agents and skills derived from consolidated Domo documentation (382 source files).

### 1. Skills (library/skills/domo/)

- [x] Create skill directory structure (12 subdirectories)
- [x] `/domo/app-scaffold` — Scaffold Domo custom apps and DDX Bricks
- [x] `/domo/appdb-manage` — Manage AppDB collections, documents, and security filters
- [x] `/domo/app-publish` — Publish apps to instance or Appstore marketplace
- [x] `/domo/code-engine` — Write and deploy Code Engine functions (JS/Python)
- [x] `/domo/connector-build` — Build custom connectors (ingest, writeback, federated)
- [x] `/domo/dataset-manage` — Manage DataSets, Stream API, PDP policies
- [x] `/domo/magic-etl` — Design Magic ETL dataflows and scripting tiles
- [x] `/domo/workflow-automate` — Trigger and manage Domo Workflows via API
- [x] `/domo/embed-analytics` — Embed Domo content with token auth and filters
- [x] `/domo/api-integrate` — Authenticate across all three Domo API tiers
- [x] `/domo/governance` — Manage users, groups, SSO, PDP, and audit
- [x] `/domo/data-science` — Jupyter, AutoML, AI services, scripting tiles

### 2. Agents (library/agents/technology/software-engineering/platform-integration/)

- [x] Domo Platform Developer (team lead, all 12 skills)
- [x] Domo App Engineer (App Framework, AppDB, publishing, embedding)
- [x] Domo Data Engineer (connectors, datasets, ETL, data science)
- [x] Domo Automation Engineer (Code Engine, workflows, governance, API integration)

### 3. Desktop UI Registration

- [x] Register 4 agents in library mock catalog (agents.ts)
- [x] Register 12 skills in library mock catalog (skills.ts)
- [x] Add Domo skill slugs to Hire Agent dialog (AgentModelConfig.svelte)

---

> **Auto-updated by Cursor:** Created headless phase checklist on 2026-04-30.
> **Auto-updated by Cursor:** Implemented CLI Foundation, Headless Backend Runtime, Process Management, and initial Documentation on 2026-04-30.
> **Auto-updated by Cursor:** Added Domo Developer Agent & Skills Suite — 4 agents, 12 skills, and desktop UI registration on 2026-04-30.
> **Auto-updated by Cursor:** Implemented workspace snapshots (exporter, importer, lock), stats dashboard (10 panels, monitor store, Tauri window), process management (attach, crash recovery), and observability (webhook notifier, Prometheus metrics, JSON logging, API key auth) on 2026-04-30.
