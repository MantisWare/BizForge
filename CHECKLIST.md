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
- [x] Add integrity check — hash-based verification that workspace files haven't drifted from snapshot
- [x] Add `bizforge snapshot create <name>` CLI command
- [x] Add `bizforge snapshot list` CLI command
- [x] Add `bizforge snapshot restore <name>` CLI command
- [x] Add workspace versioning (track snapshot history, allow rollback)

### 3. Headless Backend Runtime

- [x] Refactor backend boot sequence to support headless mode (no Phoenix endpoint for agents-only mode)
- [x] Ensure heartbeat scheduler starts all agents automatically on boot
- [x] Ensure budget enforcement works without any GUI interaction
- [x] Ensure governance gates can auto-resolve or queue for external review (webhook/Slack/email)
- [x] Ensure session compaction and handoff generation run autonomously
- [x] Ensure workflow engine triggers on schedule without manual intervention
- [x] Add headless-specific health check endpoint (`/health` or Unix socket)
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
- [x] Launch via `bizforge monitor` or `bizforge run --monitor` flag
- [x] Implement as a minimal Tauri window (separate from Command Center) or TUI (terminal UI)
- [x] Support auto-connect to a running headless instance (via PID file or Unix socket)
- [x] Add keyboard shortcuts for navigation and actions

### 5. Process Management & Daemonization

- [x] Implement PID file management for headless instances
- [x] Add support for running multiple workspaces concurrently (each with its own PID and port)
- [x] Implement process supervision (OTP supervisor with Monitor, Bootstrap, Watchdog)
- [x] Add `bizforge list` — show all running headless workspace instances
- [x] Add `bizforge attach <workspace>` — connect to a running instance's log stream
- [x] Add crash recovery — auto-resume from last known state on unexpected termination
- [x] Implement resource limits (max concurrent agents, max memory, max token spend per hour)

### 6. Notifications & External Observability

- [x] Add webhook notifications for key events (agent error, budget breach, governance block, workspace stopped)
- [x] Add Slack integration for headless mode alerts
- [x] Add email digest option (periodic summary of workspace activity)
- [x] Expose Prometheus-compatible metrics endpoint for external monitoring
- [x] Add structured JSON log output mode for log aggregation (ELK, Loki, etc.)
- [x] Add optional heartbeat ping to external URL (dead man's switch)

### 7. Security & Access Control

- [x] Implement API key authentication for CLI commands against running instances
- [x] Add role-based access for stats dashboard (read-only vs. operator)
- [x] Ensure secrets/credentials are never logged or exposed in stats dashboard
- [x] Add TLS support for remote stats dashboard connections
- [x] Implement session token rotation for long-running headless instances

### 8. Testing & Validation

- [x] Add integration tests for full headless boot-to-shutdown lifecycle
- [x] Add tests for workspace snapshot create/restore roundtrip
- [x] Add tests for CLI command parsing and execution
- [x] Add load tests — run workspace with 50+ agents headlessly and verify stability
- [x] Add chaos tests — kill adapters, saturate budgets, trigger governance blocks during headless run
- [x] Add tests for stats dashboard data accuracy (metrics match actual state)
- [x] Add tests for graceful shutdown (all sessions compacted, no orphaned tasks)

### 9. Documentation

- [x] Write CLI reference documentation (all commands, flags, examples)
- [x] Write headless deployment guide (setup, configuration, monitoring)
- [x] Write stats dashboard user guide
- [x] Add architecture doc for headless runtime mode
- [x] Add troubleshooting guide for common headless issues
- [x] Update README with headless mode section
- [x] Add headless mode article to in-app Wiki

### 10. Desktop UX Improvements

- [x] Persist main window position and size to local store on move/resize/close
- [x] Restore window position and size from store on app launch
- [x] Add info (ℹ) tooltip icons to Hire Agent dialog section headings (Provider, Model, Adapter, System Prompt, Skills)
- [x] Add close/dismiss button to onboarding wizard when re-opened from within the app
- [x] Rebrand accent colors from purple/violet/indigo to orange across entire app (auth, themes, CRUD pages, feature UIs, components, 3D office, pixel sprites)
- [x] Move connection status + system health bar to unified app footer spanning full window width
- [x] Implement embedded terminal with xterm.js (real shell via Tauri, simulated shell in browser mode)
- [x] Add multi-tab support for terminal with tab bar, new/close tab actions
- [x] Terminal store for tab state management and scrollback history
- [x] Fix Organization/hierarchy page — guard against undefined divisions, add error state with retry, add empty state CTA button
- [x] Add 15s fetch timeout to prevent indefinite API hangs

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

## Phase: MCP Server Integration

> Expose BizForge as an MCP (Model Context Protocol) server so external AI agents and LLMs can interact with the running workspace programmatically.

### 1. MCP Server Core

- [x] Create `desktop/mcp-server/` package with TypeScript + `@modelcontextprotocol/sdk`
- [x] Implement HTTP API client (`api.ts`) for proxying to BizForge backend
- [x] Implement stdio transport MCP server (`index.ts`)
- [x] Support `--api-url` and `--token` CLI flags and env vars

### 2. MCP Tool Catalog (50+ tools)

- [x] Agent management — list, get, create, update, wake, sleep, pause, resume, terminate, hierarchy
- [x] Sessions & chat — list, create, send message, get transcript
- [x] Task dispatch — spawn, list active, kill, history
- [x] Workflows — list, get details, trigger, list runs
- [x] Projects — list, get, create
- [x] Issues — list, create, update, assign, dispatch
- [x] Goals — list, create
- [x] Documents — list, read, write
- [x] Memory — search, store, list namespaces
- [x] Skills — list, assign to agent
- [x] Schedules — list, create
- [x] Costs & budgets — summary, per-agent breakdown, budget policies
- [x] Activity & logs — recent activity, log entries
- [x] Configuration — get settings, update settings
- [x] Organization — teams, hierarchy, conversations
- [x] Webhooks & integrations — list webhooks, list integrations

### 3. Tauri Integration

- [x] Create `mcp.rs` module with server readiness checks and build command
- [x] Register `mcp_status`, `mcp_client_config`, `mcp_build` Tauri commands
- [x] Generate client config JSON for external MCP clients (Claude Desktop, Cursor)
- [x] Resolve server path for both dev and production builds

### 4. Desktop UI (Settings Tab)

- [x] Create `McpStore` (Svelte 5 rune-based store) for MCP server state
- [x] Create `McpSettings.svelte` tab with readiness status, build button, client config copy
- [x] Add "MCP Server" tab to Settings page navigation
- [x] Display available tool catalog by category (16 categories, 59 tools)
- [x] Show step-by-step connection instructions for Claude Desktop and Cursor
- [x] Gracefully handle non-Tauri environments (browser dev mode)

---

## Phase: Provider Model Discovery & Pre-Add Testing

> Allow users to test provider connections and fetch available models before adding, and to retrieve live model lists for agent configuration.

### 1. Server-Side Model Discovery (CORS-safe)

- [x] Add `fetchModels` method to API client — proxies through backend `/providers/discover-models` endpoint
- [x] Add backend `discover_models` action — server-side HTTP to provider APIs (avoids browser CORS)
- [x] Provider-specific auth headers: Anthropic (`x-api-key` + `anthropic-version`), Google (`?key=`), others (`Bearer`)
- [x] Provider-specific model paths: Groq (`/openai/v1/models`), DeepSeek (`/models`), Google (`/v1beta/models`)
- [x] Add `fetchModelsById` for saved providers — reads API key from DB (no key leakage to client)
- [x] Add `fetchModelsFromEndpoint` to ProvidersStore with toast notifications
- [x] Add `fetchModelsForProvider` to ProvidersStore — uses `fetchModelsById` for saved providers
- [x] Handle timeouts (10s), non-200 responses, and unexpected formats gracefully
- [x] Fix catalog endpoints: Together AI (`api.together.ai`), Cohere (`api.cohere.com`), Fireworks (`/inference`)

### 2. Pre-Add Connection Testing (Settings > AI Providers)

- [x] Add "Test Connection" button to Add Provider form
- [x] Show success state with number of models and model tag list
- [x] Show error state with descriptive message
- [x] Use fetched models when adding the provider (fall back to catalog defaults if no test run)
- [x] Allow adding providers without testing (both buttons available)

### 3. Existing Provider Model Refresh

- [x] Add "Fetch Models" button to each provider card in the list
- [x] Update provider's model list in-place when fetch succeeds

### 4. Agent Model Config Integration

- [x] Add "Fetch Models" button next to model input in Hire Agent dialog
- [x] Auto-select first model if current model not in fetched list
- [x] Show model count in hint text when models are available

---

> **Auto-updated by Cursor:** Created headless phase checklist on 2026-04-30.
> **Auto-updated by Cursor:** Implemented CLI Foundation, Headless Backend Runtime, Process Management, and initial Documentation on 2026-04-30.
> **Auto-updated by Cursor:** Added Domo Developer Agent & Skills Suite — 4 agents, 12 skills, and desktop UI registration on 2026-04-30.
> **Auto-updated by Cursor:** Implemented workspace snapshots (exporter, importer, lock), stats dashboard (10 panels, monitor store, Tauri window), process management (attach, crash recovery), and observability (webhook notifier, Prometheus metrics, JSON logging, API key auth) on 2026-04-30.
> **Auto-updated by Cursor:** Added window state persistence — saves and restores main window position/size across sessions on 2026-04-30.
> **Auto-updated by Cursor:** Added info tooltip icons to all Hire Agent dialog section headings explaining Provider vs Adapter vs Model on 2026-04-30.
> **Auto-updated by Cursor:** Completed all remaining headless phase items — health endpoint (Bandit on 9090), snapshot versioning/rollback, governance auto-resolve (HeadlessResolver), multi-workspace concurrency, resource limiter, Slack/email/dead-man-switch notifications, monitor TUI + auto-connect, RBAC/secret scrubbing/TLS/token rotation, 7 test suites, and 4 documentation guides on 2026-04-30.
> **Auto-updated by Cursor:** Added close button to onboarding wizard so it can be dismissed when re-opened from within the app on 2026-04-30.
> **Auto-updated by Cursor:** Added MCP Server Integration — 50+ tools, Tauri process management, Settings tab with server toggle and client config on 2026-04-30.
> **Auto-updated by Cursor:** Moved connection status and system health bars into a unified AppFooter spanning the full window width on 2026-04-30.
> **Auto-updated by Cursor:** Implemented embedded terminal with xterm.js — real interactive shell via Tauri plugin-shell, simulated mock shell in browser dev mode, multi-tab support with tab bar on 2026-04-30.
> **Auto-updated by Cursor:** Added provider model discovery — pre-add connection testing via /v1/models, fetch models for saved providers, and live model retrieval in agent hiring on 2026-04-30.
> **Auto-updated by Cursor:** Rebranded all accent colors from purple/violet/indigo to orange — auth page buttons/halo, global CSS tokens (dark/glass/color/light themes), 40+ page and component files on 2026-04-30.
> **Auto-updated by Cursor:** Fixed cloud provider CORS errors and connection failures — model discovery now fully proxied through backend with provider-specific paths (Groq /openai/v1, DeepSeek /models, Google /v1beta), correct auth (Anthropic x-api-key, Google ?key=, others Bearer), saved-provider key from DB via fetchModelsById, and fixed catalog endpoints (Together .ai, Cohere .com, Fireworks /inference) on 2026-04-30.
> **Auto-updated by Cursor:** Fixed Organization/hierarchy page crash — divisions undefined guard, error state with retry button, empty state CTA, and 15s API fetch timeout on 2026-04-30.
