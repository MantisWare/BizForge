# Headless Troubleshooting Guide

Common issues when running BizForge in headless mode and how to resolve them.

---

## Port Conflicts

### Symptom

```
** (Bandit.TransportError) address already in use
```

### Cause

Another process (or another BizForge instance) is already using the health port.

### Solution

```bash
# Check what's using the port
lsof -i :9090

# Use a different port
BIZFORGE_HEALTH_PORT=9091 bizforge run ./workspace

# Or stop the conflicting instance
bizforge list
bizforge stop
```

---

## Database Connection Failures

### Symptom

```
** (DBConnection.ConnectionError) tcp connect: connection refused
```

### Cause

PostgreSQL is not running, or `DATABASE_URL` is incorrect.

### Solution

```bash
# Check PostgreSQL status
pg_isready

# Start PostgreSQL
brew services start postgresql  # macOS
sudo systemctl start postgresql  # Linux

# Verify DATABASE_URL
echo $DATABASE_URL

# Test connection
psql $DATABASE_URL -c "SELECT 1"
```

---

## Agents Stuck in "Working" State

### Symptom

Agents show as "working" indefinitely in `bizforge status` or the monitor.

### Cause

A previous instance crashed without clean shutdown, leaving agents in "working" state.

### Solution

The Watchdog automatically resets stuck agents after 600 seconds. To fix immediately:

```bash
# The Bootstrap process resets stuck agents on boot
bizforge stop
bizforge run ./workspace

# Or manually via psql
psql $DATABASE_URL -c "UPDATE agents SET status = 'idle' WHERE status = 'working'"
```

---

## Stale PID Files

### Symptom

```
bizforge list
  sales-engine  PID=12345  [dead — stale PID file]
```

### Cause

Instance crashed without graceful shutdown (kill -9, OOM, etc.).

### Solution

```bash
# bizforge list auto-cleans stale PID files
bizforge list

# Or manually
rm .bizforge/pids/sales-engine.pid
rm .bizforge/pids/sales-engine.meta.json
```

---

## Health Endpoint Returns 401

### Symptom

```bash
curl http://localhost:9090/health
{"error":"API key required"}
```

### Cause

`BIZFORGE_API_KEY` is set, requiring authentication for health checks.

### Solution

```bash
# Include the API key
curl -H "Authorization: Bearer YOUR_API_KEY" http://localhost:9090/health

# Or check the key
cat .bizforge/auth

# For Prometheus scraping, add the key to prometheus.yml:
# authorization:
#   type: Bearer
#   credentials: YOUR_API_KEY
```

---

## Snapshot Corruption

### Symptom

```
bizforge snapshot list
  my-snapshot  Status: corrupt
```

### Cause

Snapshot JSON file is malformed (interrupted write, disk full, etc.).

### Solution

```bash
# Check the file
cat .bizforge/snapshots/my-snapshot.json | python3 -m json.tool

# If unrecoverable, delete and re-create
rm .bizforge/snapshots/my-snapshot.json
bizforge snapshot create my-snapshot ./workspace
```

---

## Webhook Delivery Failures

### Symptom

Log output shows:

```
[Headless.Notifier] Exhausted retries for agent.error to https://hooks.example.com
```

### Cause

Webhook endpoint is down, unreachable, or returning errors.

### Solution

1. Verify the URL is correct: `curl -X POST $BIZFORGE_WEBHOOK_URL`
2. Check for network issues (firewalls, DNS)
3. Verify the endpoint accepts JSON POSTs
4. Check webhook secret matches both sides

---

## Out of Memory

### Symptom

Instance killed by OS OOM killer, or:

```
[ResourceLimiter] Memory limit exceeded: 512MB / 256MB
```

### Cause

Too many agents, large session contexts, or memory leak.

### Solution

```bash
# Set a memory limit to get early warning
BIZFORGE_MAX_MEMORY_MB=512 bizforge run ./workspace

# Reduce concurrent agents
BIZFORGE_MAX_AGENTS=20 bizforge run ./workspace

# Check which agents use most memory
bizforge status
```

---

## Governance Blocks in Headless Mode

### Symptom

Agents are blocked and not executing. Log shows:

```
[Governance.HeadlessResolver] Pending approval queued for external review
```

### Cause

Actions require approval but no one is approving them.

### Solution

Option 1: Enable auto-approve for headless mode in workspace config:

```yaml
# company.yaml
governance:
  headless:
    auto_approve: true
```

Option 2: Approve via API:

```bash
curl -X PUT http://localhost:9089/api/v1/approvals/APPROVAL_ID \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"status": "approved"}'
```

---

## Token Rotation Issues

### Symptom

CLI commands fail with "Invalid API key" after the instance has been running for a while.

### Cause

The API key was rotated by `TokenRotator`, and your local key is stale.

### Solution

```bash
# Get the current key
cat .bizforge/auth

# Or disable rotation
unset BIZFORGE_API_KEY  # No key = no auth = no rotation

# Or increase rotation interval
BIZFORGE_TOKEN_ROTATION_HOURS=168 bizforge run ./workspace  # Weekly
```

---

## Adapter Not Found

### Symptom

Bootstrap log shows:

```
[Headless.Bootstrap] Adapter 'claude_code' not found
```

### Cause

The adapter binary is not installed or not in PATH.

### Solution

```bash
# Check adapter availability
which claude  # Claude Code
which codex   # Codex
which osa     # OSA

# Install missing adapter
npm install -g @anthropic-ai/claude-code
```

---

## No Schedules Firing

### Symptom

Agents are bootstrapped but heartbeats never execute.

### Cause

- No schedules defined for agents
- Schedules have `enabled: false`
- Scheduler failed to register jobs

### Solution

```bash
# Check loaded schedules
bizforge config show

# Verify schedules in database
psql $DATABASE_URL -c "SELECT name, agent_id, enabled, cron_expression FROM schedules"

# Force a manual heartbeat
curl -X POST http://localhost:9089/api/v1/agents/AGENT_ID/wake \
  -H "Authorization: Bearer YOUR_TOKEN"
```

---

## Diagnostic Commands

```bash
# Overall system health
bizforge status

# View logs (filterable)
bizforge logs
bizforge logs --level error
bizforge logs --agent prospector

# List running instances
bizforge list

# Validate workspace before running
bizforge config validate

# Check snapshot integrity
bizforge snapshot list

# Monitor with live stats
bizforge monitor --tui
```

---

## Getting Help

If issues persist:

1. Check logs: `bizforge logs --level error`
2. Enable JSON logging for structured analysis: `BIZFORGE_LOG_FORMAT=json`
3. Check the health endpoint: `curl http://localhost:9090/health`
4. Review the architecture doc: `docs/architecture/headless-runtime.md`
5. Open an issue: [github.com/MantisWare/BizForge/issues](https://github.com/MantisWare/BizForge/issues)
