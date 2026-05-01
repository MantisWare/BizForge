# Headless Runtime Architecture

Technical reference for BizForge's headless execution mode — the OTP supervision tree, boot sequence, process responsibilities, and data flow.

---

## OTP Supervision Tree

When `BIZFORGE_HEADLESS=true`, the application starts a modified supervision tree:

```
Bizforge.Supervisor (one_for_one)
├── BizforgeWeb.Telemetry
├── Bizforge.Repo
├── Bizforge.BudgetEnforcer
├── Phoenix.PubSub (name: Bizforge.PubSub)
├── Bizforge.IssueDispatcher
├── Bizforge.Scheduler (Quantum)
├── Bizforge.AdapterSupervisor (DynamicSupervisor)
├── Bizforge.HeartbeatRunner (Task.Supervisor)
├── Bizforge.TaskSupervisor (Task.Supervisor)
├── Bizforge.AlertEvaluator
├── Bizforge.StaleCleanup
├── Bizforge.IdempotencyCleanup
├── Bizforge.Workflows.Supervisor
│
│── [Headless-specific processes below]
│
├── Bizforge.Headless.Monitor
├── Bizforge.Headless.Bootstrap
├── Bizforge.Headless.Watchdog
├── Bizforge.Headless.Notifier
├── Bizforge.Headless.Notifications.EmailDigest
├── Bizforge.Headless.Notifications.DeadManSwitch
├── Bizforge.Headless.ResourceLimiter
├── Bizforge.Headless.TokenRotator
├── Bizforge.Governance.HeadlessResolver
└── Bandit (HealthPlug on health_port)
```

In non-headless mode, the headless processes are replaced by `BizforgeWeb.Endpoint`.

---

## Boot Sequence

```
1. Application.start/2
   └── Read :headless config from runtime.exs (env vars)

2. Start core children (Repo, PubSub, Scheduler, etc.)

3. Start headless-specific children:
   a. Monitor       → Write PID file, write meta file, register signals
   b. Bootstrap     → (delayed 3s) Clean orphans, recover stuck, register schedules
   c. Watchdog      → Begin periodic agent health checks (60s interval)
   d. Notifier      → Load webhook config from env/file
   e. EmailDigest   → Load SMTP config, schedule digests
   f. DeadManSwitch → Begin periodic heartbeat pings
   g. ResourceLimiter → Load limits, begin enforcement checks
   h. TokenRotator  → Load/generate API key, schedule rotation
   i. HeadlessResolver → Subscribe to governance PubSub, begin sweep
   j. Bandit        → Start HTTP server on health_port

4. Scheduler.load_schedules/0
   └── Register all enabled schedules in Quantum

5. Bootstrap fires :bootstrap message (after 3s delay)
   └── Load workspace agents
   └── Register Quantum jobs
   └── Check adapter availability
   └── Notify: workspace.boot_complete

6. System enters steady state
   └── Agents execute on heartbeat schedules
   └── Watchdog monitors every 60s
   └── ResourceLimiter checks every 30s
   └── HeadlessResolver sweeps every 30s
```

---

## Process Responsibilities

### Monitor (`Bizforge.Headless.Monitor`)

**Lifecycle manager for the headless instance.**

- Writes `<workspace>.pid` and `<workspace>.meta.json` to PID directory
- Handles OS signals (SIGTERM → graceful shutdown, SIGHUP → reload config)
- Provides `pause_all/0` and `resume_all/0` for schedule control
- On shutdown: compacts all active sessions, pauses all agents, removes PID/meta files
- Periodic health check logging (30s interval)

### Bootstrap (`Bizforge.Headless.Bootstrap`)

**One-shot initialization after boot.**

- Cleans up orphaned PID files from crashed instances
- Resets agents stuck in "working" state (from previous crash)
- Loads all workspace agents and enabled schedules from DB
- Registers each schedule as a Quantum job
- Checks adapter availability (health probes)
- Fires `workspace.boot_complete` notification

### Watchdog (`Bizforge.Headless.Watchdog`)

**Continuous agent health monitor.**

- Checks for agents stuck in "working" beyond 600s threshold → reset to idle
- Checks for agents in "error" state → attempt recovery with exponential backoff
- Backoff formula: `min(count² × 30, 3600)` seconds
- Max 10 recovery attempts before notification `agent.recovery_exhausted`
- Notifies on every stuck recovery and recovery attempt

### Notifier (`Bizforge.Headless.Notifier`)

**Multi-channel event notification dispatcher.**

- Delivers webhook HTTP POSTs with HMAC signatures
- Dispatches to Slack (Block Kit messages) when configured
- Feeds events to EmailDigest accumulator
- Retry with delays: 1s, 5s, 15s (3 attempts)
- Uses Req HTTP client

### ResourceLimiter (`Bizforge.Headless.ResourceLimiter`)

**Enforces configurable resource ceilings.**

- Agent limit: pauses excess agents (LIFO — most recently updated first)
- Memory limit: triggers GC, notifies operator
- Token limit: pauses all agents when hourly spend exceeded
- Check interval: 30 seconds

### HeadlessResolver (`Bizforge.Governance.HeadlessResolver`)

**Automatic governance gate resolution.**

- Subscribes to `governance:approvals` PubSub topic
- Sweeps pending approvals every 30s
- If workspace config has `auto_approve: true` → auto-approves and triggers Executor
- Otherwise → notifies via webhook/Slack for external review
- Tracks notified IDs to avoid duplicate notifications

### TokenRotator (`Bizforge.Headless.TokenRotator`)

**API key lifecycle management.**

- Generates cryptographically secure keys (32 bytes, URL-safe base64)
- Rotates on schedule (default 24h)
- Maintains grace period for old key (default 1h)
- Updates runtime config and writes to `.bizforge/auth`

---

## Data Flow

```
Agent Heartbeat Execution:
  Scheduler (Quantum) → HeartbeatRunner → Adapter.execute/2
                                        → Session created
                                        → Task status updated
                                        → Budget counters incremented
                                        → PubSub broadcast

Monitoring:
  Health Endpoint ← DB queries (agents, sessions, issues)
                 ← :erlang.memory()
                 ← Monitor GenServer state (uptime)

Notifications:
  Event Source (Watchdog/Bootstrap/ResourceLimiter/Gate)
    → Notifier.notify/2
      → Webhook HTTP POST (async Task)
      → Slack Block Kit (async Task)
      → EmailDigest accumulator (cast)

Governance:
  Gate.check/3 → create Approval record → PubSub "governance:approvals"
    → HeadlessResolver picks up
      → auto-approve OR notify for external review
```

---

## File Layout

```
.bizforge/
├── pids/
│   ├── sales-engine.pid         # OS PID of running instance
│   └── sales-engine.meta.json   # Port, path, start time metadata
├── snapshots/
│   ├── versions.json            # Version manifest
│   ├── pre-deploy.json          # Snapshot data file
│   └── initial.json             # Another snapshot
├── auth                         # Current API key (plain text)
├── auth.json                    # Multi-key RBAC config
├── webhooks.json                # Webhook targets
└── lock                         # Workspace lock (during headless run)
```

---

## Configuration Precedence

For most settings, precedence is:

1. CLI flags (`--health-port 9091`)
2. Environment variables (`BIZFORGE_HEALTH_PORT=9091`)
3. `.env` file in project root
4. Defaults in `config/runtime.exs`

---

## Graceful Shutdown Sequence

Triggered by SIGTERM, `bizforge stop`, or Ctrl+C:

```
1. Monitor receives :sigterm signal
2. Compact all active sessions (Compactor.compact/2)
3. Pause all active/working/idle agents → "paused"
4. Remove PID file
5. Remove meta file
6. Process exits normally
7. Supervisor terminates remaining children
```

Session compaction ensures no context is lost — the next boot can resume from handoffs.
