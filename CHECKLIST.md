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
- [x] Enforce single app instance — focus existing window instead of opening duplicates (`tauri-plugin-single-instance`)
- [x] Fix window size restore — preserve non-maximized geometry when window is maximized, prevent fullscreen-on-restart
- [x] Improve window state persistence — debounced saves (500ms) to avoid excessive disk writes during drag/resize, multi-monitor awareness with overlap validation on restore, fullscreen state tracking, explicit store flush for crash safety
- [x] Persist session state to Tauri disk store — auth token, onboarding status, display name survive webview localStorage resets
- [x] Add retry logic to auth token verification — tolerate backend warm-up during cold start
- [x] Fix workspace onboarding in browser mode — Choose button now opens prompt dialog, auto-detect existing backend workspaces, reuse instead of always creating
- [x] Fix tilde (~) expansion in Rust IPC — all filesystem commands (scan, scaffold, list, watch) now resolve ~ to $HOME
- [x] Fix workspace directory never created — scaffold runs when backend knows the workspace but disk directory is missing
- [x] Fix duplicate org creation error on restart — check for existing org before creating
- [x] Fix sidebar brand icon — add SVG fallback when image fails to load
- [x] Fix sidebar collapsed layout — brand icon stacked above hamburger toggle (was side-by-side), hamburger now aligned with nav icons
- [x] Fix blank white window on Tauri dev restart — Rust-side dev server readiness poller reloads webviews if Vite wasn't ready at launch; `just app` pre-starts Vite and waits before launching Tauri
- [x] Fix auth bounce on restart — token verification now distinguishes 401 (clear token) from transient errors (trust stored token); increased retry attempts (4) with longer back-off; runtime 401s now clear persisted token from Tauri store + localStorage
- [x] Fix settings save "no_valid_keys" error — split client-only settings (theme, font_size, sidebar, notifications) into localStorage/Tauri store, only send server-recognized keys to PATCH /config
- [x] Fix CORS 404 on /health — added root-level `/health` route to Phoenix router, fixed frontend OSA probes to try `/api/v1/health` before bare `/health` on port 9089
- [x] Remove redundant "Config" nav item from System section — `/app/config` was just a redirect to Settings, which is already pinned in the sidebar footer
- [x] Fix "not_found" error on page load (alerts, etc.) — WorkspaceAuth plug now falls back to user's workspaces instead of 404-ing when workspace_id is missing from DB (mock/stale IDs)
- [x] Fix startup CORS/500 errors — CORS plug now uses `register_before_send` to guarantee headers on error responses; HealthController resilient to DB unavailability; Auth plug/controller rescue exceptions during cold start (503 instead of 500)
- [x] Harden footer resource monitor and environment page — null-safe access for all SystemResources and SystemHealth properties, fix crash when API returns partial/empty data, fix mock fallback `system_health` shape mismatch
- [x] Add workspace delete from WorkspaceSwitcher dropdown — hover-reveal trash icon per workspace item, confirmation modal with "remove from list" vs "also delete .bizforge/ files" options, Rust `remove_dir_recursive` IPC command with .bizforge safety guard
- [x] Fix Environment page system resources showing all zeros — API client now unwraps `{ resources: ... }` wrapper, environment store prefers real OS metrics from Tauri IPC (`get_system_resources`), added disk space (total/free) to Rust `SystemResourceInfo` via `sysinfo::Disks`

### 10b. Adapter Info & Footer Enhancements

- [x] Add adapter comparison matrix to README (Sessions, Concurrent, Capabilities, Best For, Requires columns)
- [x] Create centralized adapter registry (`desktop/src/lib/constants/adapters.ts`) — single source of truth for all adapter metadata
- [x] Add per-adapter info icon popover to onboarding adapter picker and hire agent adapter picker (capabilities, session/concurrent support, install hint)
- [x] Add OSA runtime indicator to app footer with StatusDot (green/red) and label
- [x] Add OSA start/stop/restart dropdown from footer (start via `setup_osa`, stop via new `stop_osa` Tauri command)
- [x] Add `stop_osa` Tauri command — finds OSA PID via lsof, sends SIGTERM, verifies shutdown
- [x] Add `sysinfo` crate and `get_system_resources` Tauri command — real OS memory, CPU, cores, arch, hostname, PID, uptime
- [x] Add Resource Monitor popover from footer memory label — system memory, BizForge memory (with heap breakdown), CPU usage, recent AI calls list
- [x] Add `/dashboard/recent-ai-calls` backend endpoint — queries CostEvent with model, tokens, cost, agent name, timestamp
- [x] Add heap breakdown (`heap_mb`, `heap_total_mb`) to dashboard system_health API response
- [x] Add UI Zoom control to app footer — popover with slider (50%–150%), +/- buttons, numeric input, preset buttons (75/90/100/110/125%), Reset button, persisted to localStorage

### 11. Hire Agent Team

- [x] Extract shared team template data (`TEAM_TEMPLATES`, `TEMPLATE_AGENTS`) into `desktop/src/lib/data/team-templates.ts`
- [x] Refactor onboarding `Team.svelte` to import from shared module
- [x] Add `createAgentBatch` method to `AgentsStore` for bulk agent creation
- [x] Create `TeamTemplateGrid.svelte` — template selection card grid (step 1)
- [x] Create `TeamAgentReview.svelte` — agent list with inline edit/remove (step 2)
- [x] Create `HireTeamDialog.svelte` — multi-step modal (template select → review agents → shared config → bulk hire)
- [x] Add "Hire Team" button to `AgentRosterHeader` alongside existing "Hire Agent"
- [x] Wire `HireTeamDialog` into agents roster page with open/close state
- [x] Support optional backend Team entity creation and agent membership assignment
- [x] Add 5 new team templates: Domo Platform (4 agents), Product Squad (4), Customer Success (3), Legal & Compliance (3), Creative Agency (4)
- [x] Add SVG icon to each team template card (using agent-icons registry) in both Hire Team modal and onboarding
- [x] Add embedded domain-tailored PM agent to all 9 execution teams (Dev, Domo, Ops, Data Science, Sales, Content, Creative, Customer Success, Legal)
- [x] System prompt template quick-fill buttons: 8 categories (Engineering, PM, Research, Writing, Strategy, Design, Specialist, General) with 4-5 templates each, role-auto-matched in both Hire Agent and Hire Team dialogs
- [x] "From Template" button on Teams page: pick a team template, select department, instantly create team entity + batch-create all agents + assign them as members

### 12. User Management & Access Control

- [x] Add "Add User" button and dialog to Users page (name, email, role, optional password)
- [x] Add inline role selector (dropdown) per user row to elevate/reduce access levels
- [x] Add "Edit" button per user with dialog for name/email changes
- [x] Add "Delete" button with two-step confirmation per user
- [x] Update mock/users.ts with localStorage-backed CRUD persistence for offline mode
- [x] Update mock/index.ts to handle POST/PATCH/DELETE on `/users` routes
- [x] Fix mock access assignments to return correct `RoleAssignment` shape (`entity_type`, `user_email`, `assigned_by`)

### 13. Services / Integration Catalog

- [x] Expand `Integration` type with `description`, `features[]`, `docs_url` fields
- [x] Add 12 new `IntegrationCategory` values (project_management, analytics, design, cloud, database)
- [x] Add `INTEGRATION_CATEGORY_LABELS` constant for human-readable category names
- [x] Enrich mock integrations — 28 services across 12 categories with descriptions, feature tags, and docs links
- [x] Add search and category filter to IntegrationsStore (`searchQuery`, `filterCategory`, `filtered`, `grouped`, `categories` derived state)
- [x] Redesign Services tab — search bar, category filter pills, grouped sections with rich service cards
- [x] Service cards show icon/initial, name, provider, description, feature tags, status pill, connect/disconnect button, docs link
- [x] Category groups show header with connected count
- [x] Context-aware PageShell subtitle (adapters count vs services connected)

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

### 5. Provider Persistence & Startup Loading

- [x] Load providers on app startup in `+layout.svelte` (fetched alongside agents/projects)
- [x] Add localStorage cache to ProvidersStore — instant hydration on load, survives page refresh
- [x] Persist provider state after every mutation (create, update, delete, test, model fetch)
- [x] Mock API layer persists providers to localStorage (survives reload in dev/offline mode)
- [x] Providers associated with workspace via `workspace_id` (user-scoped in backend)

---

## Phase: Claude Code Provider Support

> Add Claude Code (Anthropic's agentic coding assistant) as a supported AI provider in the provider catalog and mock layer.

### 1. Provider Registration

- [x] Add `claude-code` slug to `FEATURED_PROVIDERS` in `provider-catalog.ts` with Anthropic endpoint and default Claude models
- [x] Add Claude Code mock provider entry in `mock/providers.ts` for dev/offline mode

---

## Phase: Workspace Health Check & Auto-Repair

> Validate .bizforge/ directory structure, detect missing/corrupt files, and auto-repair them.

### 1. Rust IPC Commands

- [x] Add `WorkspaceHealthReport`, `HealthIssue`, `RepairResult` structs to `filesystem.rs`
- [x] Implement `check_workspace_health` IPC — validates root, subdirs, SYSTEM.md, COMPANY.md, agent/schedule/skill files
- [x] Implement `repair_workspace` IPC — creates missing dirs/files, backs up corrupt files, re-checks after repair
- [x] Register both commands in `lib.rs` invoke_handler

### 2. TypeScript Types

- [x] Add `HealthIssue`, `WorkspaceHealthReport`, `RepairResult` interfaces to `bizforge.ts`

### 3. Workspace Store Integration

- [x] Add `healthReport` state to `WorkspaceStore`
- [x] Add `checkHealth()` method — invokes IPC, updates state, logs results
- [x] Add `repairWorkspace()` method — invokes IPC, updates health, shows toast, re-scans agents
- [x] Auto-check health after every `scanAndLoadAgents` call (workspace switch, file watcher, startup)

### 4. Auto-Scaffold on Scan

- [x] `scan_bizforge_dir` (Rust) auto-creates `.bizforge/` directory structure and `SYSTEM.md` when path doesn't exist
- [x] `scanWorkspace` (TS) auto-calls `repairWorkspace` on scan failure — creates dirs, retries scan, shows success toast
- [x] `createWorkspace` (TS) calls `scaffold_bizforge_dir` IPC to create `.bizforge/` on disk when creating a new workspace
- [x] `WorkspaceSwitcher` no longer shows redundant "Not a workspace" error — auto-repair handles it

### 5. Desktop UI

- [x] Create `WorkspaceHealth.svelte` panel — status summary, issue list with severity icons, repair button, re-check button
- [x] Add health dot indicator to `WorkspaceSwitcher` (green/yellow/red based on report)
- [x] Add "Workspace" tab to Settings page containing the health panel

---

> **Auto-updated by Cursor:** Fixed window size restore (non-maximized geometry preserved) and session persistence (auth token + onboarding state backed by Tauri disk store, token verification retries during cold start) on 2026-05-01.
> **Auto-updated by Cursor:** Added single-instance enforcement via tauri-plugin-single-instance — duplicate launches now focus the existing window instead of opening a new one on 2026-05-01.
> **Auto-updated by Cursor:** Added Claude Code as a featured AI provider — catalog entry with Anthropic endpoint/models and mock provider seed data on 2026-05-01.
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
> **Auto-updated by Cursor:** Added provider persistence — providers load on app startup, localStorage cache for instant hydration and offline survival, mock layer persists CRUD to localStorage on 2026-04-30.
> **Auto-updated by Cursor:** Fixed onboarding workspace selection in browser mode — Choose button now opens a prompt dialog (was silently failing without Tauri), existing workspaces are auto-detected from backend and pre-fill name/description, launch flow reuses existing workspace instead of always creating on 2026-05-01.
> **Auto-updated by Cursor:** Fixed blank white window on Tauri dev restart — added Rust-side dev server readiness poller that reloads webviews when Vite comes up late, and updated `just app` to pre-start Vite with readiness wait before launching Tauri (blanked `beforeDevCommand` to avoid double Vite) on 2026-05-01.
> **Auto-updated by Cursor:** Added Workspace Health Check & Auto-Repair — Rust IPC commands (check_workspace_health, repair_workspace) validate .bizforge/ structure and auto-fix missing dirs/files, workspace store integration with auto-check on scan, WorkspaceHealth panel in Settings, and health dot indicator in WorkspaceSwitcher on 2026-05-01.
> **Auto-updated by Cursor:** Added `just package` recipe for signed/notarized macOS distribution — validates APPLE_SIGNING_IDENTITY, APPLE_CERTIFICATE, APPLE_ID, APPLE_PASSWORD, APPLE_TEAM_ID from .env before building; created .env.example template with all signing/notarization/updater variables; added macOS bundle config (category, descriptions, minimumSystemVersion) to tauri.conf.json on 2026-05-01.
> **Auto-updated by Cursor:** Workspace auto-scaffold on scan — scan_bizforge_dir (Rust) and scanWorkspace (TS) now auto-create .bizforge/ directory structure when missing instead of failing with error toast; createWorkspace scaffolds on disk via IPC on 2026-05-01.
> **Auto-updated by Cursor:** Added Hire Agent Team feature — "Hire Team" button on agents page opens a multi-step modal to select a team template, review/customize agents, configure shared adapter/model/budget, and bulk-create all agents with optional team grouping on 2026-05-01.
> **Auto-updated by Cursor:** Added full user management — Users page now supports add/edit/delete users and inline role elevation/reduction (admin/member/viewer); mock layer updated with localStorage-backed CRUD and correct RoleAssignment shape on 2026-05-01.
> **Auto-updated by Cursor:** Expanded Hire Team templates from 7 to 12 — added Domo Platform (4 Domo-specialised agents with real skill references), Product Squad (PM, UX researcher, designer, tech writer), Customer Success (support, onboarding, retention), Legal & Compliance (contracts, compliance, policy), and Creative Agency (creative director, graphic designer, video producer, brand copywriter) on 2026-05-01.
> **Auto-updated by Cursor:** Added adapter info icons, OSA footer indicator with start/stop/restart, Resource Monitor popover (system RAM, BizForge memory, CPU, recent AI calls), centralized adapter registry, adapter comparison matrix in README, sysinfo Tauri command for real OS metrics, and recent-ai-calls backend endpoint on 2026-05-01.
> **Auto-updated by Cursor:** Added UI Zoom control to app footer — slider, +/- buttons, numeric input, preset quick-select, Reset button, persisted to localStorage, applied via document.documentElement.style.zoom on 2026-05-01.
> **Auto-updated by Cursor:** Improved window state persistence — debounced saves (500ms tokio task) to reduce disk writes during drag/resize, multi-monitor intersection check on restore (prevents off-screen windows), fullscreen state tracking, explicit store.save() flush for crash safety on 2026-05-01.
> **Auto-updated by Cursor:** Fixed sidebar collapsed layout — brand icon now stacks above hamburger toggle instead of side-by-side, hamburger aligned with nav icons on 2026-05-01.
> **Auto-updated by Cursor:** Fixed settings save "no_valid_keys" error — settings store now separates client-only keys (theme, font_size, sidebar, notifications) persisted to localStorage/Tauri store from server config keys sent to PATCH /config on 2026-05-01.
> **Auto-updated by Cursor:** Fixed CORS 404 on /health — added root-level `/health` convenience route to Phoenix router, reordered frontend OSA health probes to try `/api/v1/health` before bare `/health` on port 9089 on 2026-05-01.
> **Auto-updated by Cursor:** Removed redundant "Config" nav item from sidebar System section — /app/config was a redirect to Settings which is already pinned at the sidebar bottom on 2026-05-01.
> **Auto-updated by Cursor:** Redesigned Services tab on Integrations page — 28 services across 12 categories (AI Providers, Version Control, Communication, CI/CD, Monitoring, Project Management, Analytics, Design, Cloud, Databases, Storage, Custom) with rich cards showing descriptions, feature tags, connect/disconnect buttons, docs links, search, and category filter pills on 2026-05-01.
> **Auto-updated by Cursor:** Hardened footer resource monitor and environment page — all SystemResources and SystemHealth properties now use nullish coalescing (`?? 0`) before `.toFixed()`, fixed mock fallback `system_health` shape to match `SystemHealth` interface, and made `SystemResources` fields optional to tolerate partial API responses on 2026-05-01.
> **Auto-updated by Cursor:** Fixed "not_found" error on first page load (alerts, sessions, costs, etc.) — WorkspaceAuth plug now falls back to all user workspaces instead of returning 404 when workspace_id is not found in DB; also handles non-UUID mock IDs gracefully on 2026-05-01.
> **Auto-updated by Cursor:** Fixed startup CORS/500 console errors — CORS plug uses `register_before_send` to inject headers on all responses including 500 errors; HealthController gracefully handles DB unavailability (returns `degraded` status); Auth plug/controller rescue exceptions during cold start (returns 503 instead of unhandled 500) on 2026-05-01.
> **Auto-updated by Cursor:** Added workspace deletion from WorkspaceSwitcher dropdown — hover-reveal trash icon on each workspace row, confirmation modal with two modes (remove from list only, or also delete `.bizforge/` files from disk), `remove_dir_recursive` Rust IPC command with `.bizforge` path safety guard on 2026-05-01.
> **Auto-updated by Cursor:** Fixed Environment page system resources showing all zeros — API client wasn't unwrapping `{ resources: ... }` response wrapper; environment store now prefers real OS metrics from Tauri `get_system_resources` IPC; added disk total/free to Rust `SystemResourceInfo` via `sysinfo::Disks` on 2026-05-01.
