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
- [x] Persistent authentication — save user credentials to Tauri disk store on login/register, auto re-login when token expires or localStorage is cleared, credentials cleared on explicit logout
- [x] Fix auth session permanence — runtime 401s now trigger silent re-login with saved credentials (singleton promise prevents stampede from 30+ stores), redirect to /auth only when re-login fails, no more "unauthorized" toast errors surfacing to the user
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
- [x] Make Reports left panel resizable — drag handle between list panel and viewer, keyboard accessible (Arrow keys), min/max constraints (220–600px), centered empty state CTA, tabs wrap instead of scrolling off-screen
- [x] Restructure sidebar navigation for top-down user journey — reordered sections: Daily Drivers > Explore (Library, Chat) > Organize (Organization, Projects, Goals, Issues, Documents) > Agents (tree + Skills + Memory) > Automate (Workflows, Schedules, Alerts) > Observe (Activity, Sessions, Work Products, Costs, Analytics, Reports) > Platform (Integrations, Secrets, Users & Access, Environment, Datasets); removed "Data" and "System" sections; moved Library from Automate and Chat from bottom pinned into new "Explore" section; moved Organization from System into "Organize"; moved Skills/Memory into Agents; moved Work Products into Observe; moved Datasets into Platform; updated collapsed-mode icons

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
- [x] Register all 43 `library/teams/*.md` definitions as Library Teams entries — visible in Library > Teams tab with size, agent count, deploy support
- [x] Auto-assign role-matched system prompts to all team agents on template select (agents with short stub prompts get the best match from `prompt-templates.ts`)
- [x] Fix agent name/role column alignment in TeamAgentReview — switched from flex to CSS grid with fixed proportional columns
- [x] Fix "Next: Configure" button unclickable on review step — added `stopPropagation` on modal and button clicks, `type="button"`, and `z-index` stacking on footer
- [x] Rebrand Hire Agent and Hire Team dialogs from blue (`rgba(59,130,246)`) to orange (`rgba(249,115,22)`) accent — buttons, step dots, skill chips, template hover, adapter selection, schedule presets

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
- [x] Wire Settings > Integrations tab Connect/Disconnect/Configure buttons to integrationsStore actions with loading states
- [x] Integration Connect Modal — per-service config fields (API key, tokens, domain), validation, loading spinner
- [x] Fix mock layer connect/disconnect to persist state changes (no more `validation_failed` in mock mode)

### 14. Analytics

- [x] Add "Reset Analytics" button to analytics page header (positioned before period selector)
- [x] Add confirmation modal before resetting (warns action cannot be undone)
- [x] Add `DELETE /analytics/reset` backend endpoint — marks workspace analytics as reset via `:persistent_term`
- [x] Backend `summary`, `agents`, `teams` endpoints return zeroed data after reset
- [x] Add `analytics.reset()` to frontend API client
- [x] Add `resetAnalytics()` method to analytics store
- [x] Mock layer supports reset — returns zeroed analytics after reset called

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

### 3. Agent Documentation Standards (from Domo Consolidated RAG Documentation)

- [x] Domo UI Developer — Domo Design Guide (Material Design, color palette, 6px typography grid), card size px mappings (1–6 scale), `da new` scaffolding, domo.js/ryuu.js patterns, @domoinc/toolkit clients, Phoenix charting, DDX Brick→Pro-Code conversion, `domo.navigate()` limitation
- [x] Domo App Engineer — Complete manifest spec (all properties: mapping, collections, workflowMapping, packageMapping, proxyId, flags, ignore), `da new` + BYOS templates (React/Angular/Vue), AppDB STRING-only constraint, Redux Toolkit state management, environment-specific builds with manifestOverrides
- [x] Domo Backend Developer — `codeengine` library methods (sendRequest, getAccount, getExecutionDetails, axios), JS libraries (codeengine, axios, googleAuthLibrary), Python packages (requests, pandas, numpy, boto3), package lifecycle (save→deploy→version), manifest `packageMapping` wiring, Code Engine limits (1GB/5min)
- [x] Domo QA Engineer — 8-layer test strategy (scaffolding, data binding, AppDB, security, Code Engine, card rendering, publishing, regression), card size test matrix with pixel dimensions, AppDB STRING-only validation, troubleshooting checklist (sync failures, proxy issues, publish errors)
- [x] Domo Platform Developer — Full manifest specification table, MCP tool catalog (7 servers, 80+ tools), dashboard/Beast Mode/page layout patterns (60-unit grid), DDX Bricks + Pro-Code Editor, all @domoinc/toolkit clients listed
- [x] Domo Data Engineer — DataSet vs AppDB type distinction (DataSet: STRING/LONG/DOUBLE/DATE/DATETIME; AppDB: STRING only), Stream API gzip procedure with sequential part IDs, Federated queries, Workbench agent, PDP at source dataset only, RFC-4180 CSV format, volume-based ingestion strategy table
- [x] Domo Automation Engineer — `codeengine` library API table (5 methods), global vs custom packages, scheduled AppDB sync via Code Engine + Workflow pattern, cross-instance orchestration, workflow input parameter types (12 types), Code Engine resource limits

### 4. Desktop UI Registration

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

### 14. Virtual Office Pixel View Visual Upgrade

- [x] Expand office grid from 21x15 to 26x19 for more breathing room between areas
- [x] Reposition all rooms, furniture, and seats to use wider layout
- [x] Widen corridors from 2 tiles to 3 tiles
- [x] Add per-department floor patterns (grid for Engineering, checker for Product, herringbone for Operations, dot for Research, carpet for Lounge)
- [x] Replace checkered void with stone/paving ground texture using seeded pseudo-random variation
- [x] Add thick beveled walls with bevel highlight on north/west edges
- [x] Implement doorway cutouts where corridors meet room walls
- [x] Add inner floor shadow near walls for depth
- [x] Add styled corridor tiles with edge lines and runner pattern
- [x] Replace floating room labels with rendered sign plates (dark pill with accent border and department dot)
- [x] Add drop shadow ellipse beneath characters for grounding
- [x] Add department color pip to character name labels
- [x] Add environmental decorations: rugs, water cooler, entrance mat, wall art, ceiling lights
- [x] Add new FurnitureType enum values (RUG, WATERCOOLER, CEILING_LIGHT, WALL_ART, ENTRANCE_MAT)
- [x] Add ambient PC monitor glow (radial gradient, intensity varies by time-of-day)
- [x] Add warm Lounge lamp glow with subtle pulse animation
- [x] Update minimap to show corridors and improved room borders
- [x] Per-time-of-day themed wall/ground/corridor colors (dawn/day/dusk/night)

### 14b. Virtual Office 3D View Visual Upgrade

- [x] Restructure 3D scene zones to match pixel view departments (Engineering, Product, Operations, Research, Lounge)
- [x] Add colored floor planes per department with accent-colored border edges
- [x] Add zone sign plates (floating dark pill with accent border + label text)
- [x] Add per-zone accent spot lights for colored ambient illumination
- [x] Brighten overall lighting (ambient, directional, hemisphere light, point lights)
- [x] Add corridor floor planes with center runner between zones
- [x] Add environmental props: plants (pot + foliage), whiteboards, bookshelf with book spines, water cooler, coffee table
- [x] Brighten desk materials (birch wood), add monitor bezel and base, chair legs
- [x] Add department color pip sphere next to agent name labels
- [x] Add monitor glow point light when agent is running
- [x] Lighten fog density and background color
- [x] Add front wall with entrance opening
- [x] Zone-based agent positioning (agents distributed across department zones by index)
- [x] Pass `zoneColor` prop from Scene3D to AgentDesk3D for per-zone theming

### 14c. Virtual Office Team & Division Indicators

- [x] Create `orgColors.ts` utility — deterministic `teamColor(id)` and `divisionColor(id)` HSL generators with `AgentOrgInfo` type
- [x] Fetch hierarchy tree in office page — resolve agent → team → department → division chain into `agentOrgMap`
- [x] Thread `agentOrgMap` through VirtualOffice → PixelOffice / Office3D / OfficeDetailPanel
- [x] Add `teamColor` and `divisionColor` fields to `OfficeCharacter` type, populate during agent-to-character sync
- [x] 2D Pixel: team-colored underline bar at bottom of name label background + division-colored pip replacing old status pip
- [x] 3D: team-colored backdrop plane + underline bar behind floating name text, division-colored pip replacing zone-based pip
- [x] OfficeDetailPanel: Organization section showing team/division name with color pips, "Assign to Team" / "Change Team" / "Remove from Team" buttons with team picker dropdown
- [x] Collapsible team/division legend overlay (bottom-left) — groups teams by division with color swatches and agent counts

## Phase: Bidirectional Inbox & Slack Integration

> Unify the inbox around the notifications table, wire system event producers, build bidirectional Slack integration with inbound messages, agent replies, and interactive approvals.

### 1. Inbox Foundation

- [x] Rewrite `InboxController` to query `notifications` table instead of broken `activity_events` query
- [x] Fix `SidebarBadgeController` to count unread notifications (was counting non-existent `activity_events` with `level == "notification"`)
- [x] Add `source_channel` and `reply_to` fields to `Notification` schema and migration
- [x] Add `"message"` and `"integration"` to notification categories and `"integration"` to sender types
- [x] Update frontend `InboxItem` type with `source_channel` and `reply_to` fields
- [x] Add `"message"` and `"integration"` to `InboxItemType` union
- [x] Update inbox store type groups to include new types
- [x] Add channel badge (Slack, Email, etc.) to `InboxItem` component
- [x] Add Slack message mock items to mock inbox data
- [x] Update inbox API client `read` method to use correct HTTP method (POST)
- [x] Add `reply` endpoint to inbox API client

### 2. System Event Producers

- [x] Wire `Dispatcher.notify_system_alert` on heartbeat failure in `Heartbeat` module
- [x] Wire `Dispatcher.notify_approval_required` when governance gate creates an approval
- [x] Wire `Dispatcher.notify_workflow_status` on workflow run completion and failure
- [x] Add `notify_integration_message` helper to `Dispatcher` for external integration messages

### 3. Slack Bidirectional Integration

- [x] Create `SlackInstallation` schema (team_id, bot_token, signing_secret, channel_mappings, default_agent_id)
- [x] Create `slack_installations` migration with workspace FK and unique team_id constraint
- [x] Add `connect_slack`, `disconnect_slack`, `slack_status` endpoints to `IntegrationController`
- [x] Add Slack config routes to router (authenticated scope)
- [x] Create `SlackController` with Events API endpoint (URL verification, `event_callback` dispatch)
- [x] Implement Slack request signature verification (`x-slack-signature` HMAC-SHA256)
- [x] Create `Slack.EventHandler` — processes `message` and `app_mention` events
- [x] EventHandler creates notifications with `source_channel: "slack"` and `reply_to` metadata
- [x] EventHandler routes messages to target agent via channel-to-agent mappings
- [x] EventHandler creates sessions and dispatches to adapter for agent processing
- [x] Create `Slack.Client` — wraps Slack Web API (`chat.postMessage`) using Req
- [x] `Client.send_reply` — posts to specific Slack thread from `reply_to` metadata
- [x] `Client.send_approval_message` — sends Block Kit interactive approval messages
- [x] Create `Slack.ReplyHandler` — monitors session events and relays agent responses to Slack threads
- [x] Add Slack Events API and Interactive Message routes outside authenticated scope
- [x] `SlackController.interactive` handles `block_actions` for approve/reject button clicks
- [x] Wire `HeadlessResolver.notify_pending` to send interactive Slack approval buttons
- [x] Add Slack event routes to Phoenix router

### 4. Inbox Reply from Desktop

- [x] Create `InboxReply` component (textarea, send button, Cmd+Enter shortcut, Escape to close)
- [x] Add Reply button to `InboxItem` for items with `source_channel`
- [x] Wire `InboxReply` into `InboxFeed` (inline below the item being replied to)
- [x] Add `replyToItem` method to inbox store
- [x] Add `POST /inbox/:id/reply` backend endpoint that dispatches via `Slack.Client`
- [x] Add reply mock route

### 5. Realtime Inbox Updates

- [x] Add `GET /inbox/stream` SSE endpoint subscribing to `notifications:<workspace_id>` PubSub topic
- [x] Add inbox stream route to SSE streaming scope in router
- [x] Add `connectStream` / `disconnectStream` methods to inbox store
- [x] SSE integration via `connectSSE` with auto-reconnect

## Phase: Auto-Resolve Skill Dependencies for Library Entities

> Automatically install required workspace skills when adding agents, teams, or companies — from library catalog, hire dialogs, and template deploy flows.

### 1. Data Layer

- [x] Add `required_skills: string[]` field to `LibraryAgent`, `LibraryTemplate`, `LibraryOperation` types
- [x] Update `RawAgent`, `RawTemplate`, `RawOperation` enrichment types and defaults
- [x] Create `skill-dependencies.ts` — `AGENT_SKILL_TAG_MAP`, `resolveSkillsForAgent`, `resolveSkillsForTeam`, `resolveSkillsForLibraryEntity`, `partitionSkills`, `lookupLibrarySkills`
- [x] Populate `required_skills` on all 157 library agents (2–6 skills each, matched to role/category)
- [x] Populate `required_skills` on all 48 library team templates
- [x] Populate `required_skills` on all 5 library company operations

### 2. Workspace Skill Installation

- [x] Add `installFromLibrary(librarySkills)` method to `SkillsStore` — imports new skills, bulk-enables existing disabled ones
- [x] Add `addSkill`, `bulkEnableSkills`, `importSkill` exports to mock skills module
- [x] Wire mock router to process `POST /skills/import` and `POST /skills/bulk-enable` with actual data

### 3. Confirmation Modal

- [x] Create `SkillsPreviewModal.svelte` — reusable dialog showing skills to add (grouped by category) and already-active skills, with Confirm/Cancel actions

### 4. Library Page & Detail Page Integration

- [x] Wire library page `handleAgentAdd`, `handleOperationUse`, `handleTemplateCreate` through skill resolver and preview modal
- [x] Wire "Import to Workspace" button on agent detail page (resolve → modal → install)
- [x] Wire "Import to Workspace" button on skill detail page (direct install)
- [x] Wire Deploy button on team detail page through skill resolver and preview modal
- [x] Wire Deploy button on company detail page through skill resolver and preview modal

### 5. Hire Dialog Integration

- [x] Add role-based recommended skills to `HireAgentDialog` (auto-populated chips from `ROLE_SKILL_TAGS` → `AGENT_SKILL_TAG_MAP` → library skills)
- [x] Auto-select recommended skills when role changes, allow user toggle
- [x] Install selected library skills on agent hire submit
- [x] Add collapsible "Skills that will be added" summary to `HireTeamDialog` review step (shows new vs. existing)
- [x] Install resolved team skills before creating agents in `HireTeamDialog` submit

### 6. Template Deploy Service

- [x] Install resolved skills for all deployed agents in `template-deploy.ts` after agent registration (Step 3b)

---

## Phase: Project Documentation & AI Task Generation

> Project-scoped documentation management with AI-powered document generation and automatic issue/task extraction from documentation.

### 1. Project Documents Tab

- [x] Add `listByProject(projectId)` to API client for project-scoped document queries
- [x] Add `fetchByProject()` and `projectDocuments` state to documents store
- [x] Update mock router to filter documents by `project_id` query param
- [x] Add "Docs" tab to project detail page (`/app/projects/[id]`) between Goals and Issues
- [x] Document list with title, path, format badge, and date in split-pane layout
- [x] Inline `DocumentViewer` for selected documents
- [x] Create-document dialog with pre-filled `project_id`
- [x] Empty state with CTAs for manual creation and AI generation

### 2. AI Document Generation

- [x] Create `GenerateDocModal.svelte` — document type selector (PRD, Tech Spec, Architecture, API Docs, User Guide, Runbook, Custom)
- [x] Context input with project metadata toggles (include description, goals, issues)
- [x] Agent selector for choosing which AI agent generates the document
- [x] SSE streaming integration via `sessions.create` + `messages.send` + `connectSSE`
- [x] Mock-mode word-by-word simulated streaming with realistic document template
- [x] Streaming markdown preview with inline cursor animation
- [x] Edit, regenerate, and save-as-document flow

### 3. AI Issue Generation from Documentation

- [x] Create `GenerateIssuesModal.svelte` — multi-phase modal (select docs → analyze → review)
- [x] Document selection checklist with select-all/deselect-all
- [x] Structured AI prompt requesting JSON-formatted issue proposals
- [x] Mock-mode analysis with 8 realistic proposed issues
- [x] Review panel with editable title, description, priority, and labels per issue
- [x] Expandable/collapsible issue cards with select/deselect checkboxes
- [x] Add `batchCreateIssues()` to issues store for bulk creation
- [x] Trigger buttons on both Docs tab ("Analyze Docs") and Issues tab ("Generate from Docs")

### 4. Agent/MCP Layer

- [x] Verify existing MCP tools: `bizforge_issue_create`, `bizforge_issues_list`, `bizforge_document_write`, `bizforge_document_read`
- [x] Add `bizforge_project_documents` MCP tool for project-scoped document listing
- [x] Existing ChatPanel and agent sessions support free-form doc/task requests without additional UI

### 5. Default Model Setting

- [x] Add `allModels` derived to `providersStore` — flat list of models across connected providers
- [x] Add "Default Model" section to AI Providers settings with grouped `<optgroup>` dropdown
- [x] Auto-save default model to `settingsStore` (persisted server-side and locally)
- [x] Wire `GenerateDocModal` to pass `settingsStore.data.default_model` via `messages.send()` model param
- [x] Wire `GenerateIssuesModal` to pass `settingsStore.data.default_model` via `messages.send()` model param
- [x] Display current default model in both modals with "Change in Settings → AI Providers" hint
- [x] Fix error handling: show "No agents available" message instead of hardcoded fallback agent ID
- [x] Pre-fetch agents on modal mount if not already loaded

### 6. LLM Inspector Panel

- [x] Add `LlmLogEntry` type and optional `color` field to `AIProvider` in `types.ts`
- [x] Add inspector panel CSS variables and 16-color pastel provider palette to `app.css`
- [x] Create `llmInspector.svelte.ts` store — ring buffer (500 entries), panel open/width/provider-color persistence via localStorage
- [x] Create `LlmInspectorPanel.svelte` — right-side collapsible panel with drag-resize gutter, provider color dots, direction arrows, 3-line preview, expandable full payload view
- [x] Integrate panel into `+layout.svelte` app body flex row alongside Sidebar and main content
- [x] Add `⌘⇧I` / `Ctrl+Shift+I` keyboard shortcut to toggle inspector panel
- [x] Add LLM request/response interception in `client.ts` — pub/sub hook on `request()` captures AI-bound traffic (sessions, providers, agents, conversations, reports)
- [x] Wire inspector store to client interceptor — auto-captures sent/received payloads with provider resolution
- [x] Add color picker to Providers Settings — per-provider color swatch with native color input, persisted to localStorage
- [x] Panel defaults to 50% viewport width on first open, resizable between 300px and 80vw, width persisted across sessions

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
> **Auto-updated by Cursor:** Virtual Office pixel view visual upgrade — expanded grid (26x19), beveled walls with doorway cutouts, stone ground texture, styled corridors with runner, per-department floor patterns, sign plate labels, character shadows, environmental decorations (rugs, water cooler, wall art, ceiling lights), ambient lighting (PC glow, lounge lamp), and themed colors per time-of-day on 2026-05-01.
> **Auto-updated by Cursor:** Virtual Office 3D view visual upgrade — restructured zones to match pixel departments (Engineering, Product, Operations, Research, Lounge), colored floor planes with accent borders, zone sign plates, per-zone accent lights, brighter materials (birch desks, upholstered chairs), environmental props (plants, whiteboards, bookshelf, water cooler), corridor with runner, monitor glow, department pip on labels, lighter fog/background on 2026-05-01.
> **Auto-updated by Cursor:** Added "Reset Analytics" button to analytics page — confirmation modal, backend DELETE /analytics/reset endpoint (marks workspace as reset via persistent_term, returns zeroed data thereafter), frontend API client + store method, mock layer support on 2026-05-01.
> **Auto-updated by Cursor:** Added playful lounge extras to Pixel and 3D views — second sofa facing first sofa, mini kitchen (counter, microwave, coffee machine, fridge), wall-mounted TV; pixel view has 5 new FurnitureType enums + sprites; 3D view has matching meshes with emissive TV screen and kitchen detail; lounge widened in both views on 2026-05-01.
> **Auto-updated by Cursor:** Made Reports left panel resizable with drag handle, keyboard support, centered empty state CTA, and wrapping tabs on 2026-05-01.
> **Auto-updated by Cursor:** Improved unauthorized error handling on Users and Organization pages — auth errors now show "Authentication required" with lock icon, session expiry explanation, and "Sign in" button linking to /auth; non-auth errors show generic message with retry; added /hierarchy mock route so mock mode returns valid hierarchy data instead of empty object on 2026-05-01.
> **Auto-updated by Cursor:** Registered all 43 library/teams/ definitions in Library Teams mock — teams tab now shows 48 entries (43 domain teams + 5 generic size templates) with correct agent counts, size categories, descriptions, and deploy support on 2026-05-01.
> **Auto-updated by Cursor:** Removed synthetic library metrics (downloads, favorites, forks, rating, potency, added_at) from all Library types, enrichment, card components, detail pages, and sort options — version field retained as real data element on each item on 2026-05-01.
> **Auto-updated by Cursor:** Moved version numbers next to item labels (left of visibility icon) on all library cards (agents, skills, teams, companies); added tooltip to visibility eye icon explaining Public/Unlisted/Private states on 2026-05-01.
> **Auto-updated by Cursor:** Implemented Bidirectional Inbox & Slack Integration — rewrote InboxController to use notifications table (fixing empty Messages tab), wired system event producers (heartbeat failures, governance approvals, workflow status), built full Slack integration (Events API inbound, agent routing, chat.postMessage outbound, interactive approval buttons), desktop reply composer, and SSE realtime inbox stream on 2026-05-01.
> **Auto-updated by Cursor:** Implemented Auto-Resolve Skill Dependencies — `required_skills` on all 157 agents, 48 teams, 5 companies; `skill-dependencies.ts` resolver with tag-to-skill mapping; `SkillsStore.installFromLibrary` with mock layer support; `SkillsPreviewModal` confirmation UI; wired into library page, all 4 detail pages, HireAgentDialog (role-based recommendations), HireTeamDialog (review step summary), and template-deploy service on 2026-05-01.
> **Auto-updated by Cursor:** Updated Wiki to reflect current application state — Library article updated with auto-resolve skill dependencies and 157/121/48/5 entity counts; Skills article updated with library import, bulk enable, and auto-resolve capabilities; Inbox article updated with bidirectional messaging, Slack integration, and reply composer; Agents Roster article updated with role-based skill recommendations in hire dialogs; Integrations article updated with full Slack integration details on 2026-05-01.
> **Auto-updated by Cursor:** Fixed Hire Team dialog bugs — auto-assign role-matched system prompts from prompt-templates.ts to all team agents (not just the first), fixed agent name/role column alignment with CSS grid layout, fixed "Next: Configure" button unclickable (stopPropagation on modal/button clicks + z-index stacking), rebranded all hire dialog accent colors from blue to orange across 7 components on 2026-05-01.
> **Auto-updated by Cursor:** Wired Settings > Integrations tab — Connect buttons now open IntegrationConnectModal with per-service config fields (GitHub: PAT/org/webhook, Slack: bot token/signing secret/channel, Linear: API key/team ID, Notion: integration token/root page, Jira: email/API token/domain/project key, Datadog: API key/app key/site); modal validates required fields before submitting; Disconnect/Configure buttons work inline; mock layer now persists connect/disconnect state changes; fixed `validation_failed` error on 2026-05-01.
> **Auto-updated by Cursor:** Restructured sidebar navigation for intuitive top-down user journey — 7 sections: Explore (Library + Chat), Organize (Org + Projects + Goals + Issues + Docs), Agents (tree + Skills + Memory), Automate (Workflows + Schedules + Alerts), Observe (Activity + Sessions + Work Products + Costs + Analytics + Reports), Platform (Integrations + Secrets + Users + Environment + Datasets); removed orphaned "Data" section and renamed "System" to "Platform"; updated collapsed-mode icons on 2026-05-05.
> **Auto-updated by Cursor:** Fixed division creation "validation_failed" error — hierarchy store now extracts and displays field-level error details from backend changeset validation (was only showing generic "validation_failed"); fixed `budget_enforcement` type mismatch between frontend (`"soft"|"hard"`) and backend (`"visibility"|"warning"|"stop"`) across Organization, Division, Department, and Team types; replaced `||` with explicit empty-string checks per project nullish-coalescing rules on 2026-05-05.
> **Auto-updated by Cursor:** Fixed hierarchy tree showing empty despite divisions existing in database — `hierarchy.get()` API client was not unwrapping the backend response (divisions were nested inside `organization` object but frontend expected them at the top level); added response transformation to destructure `divisions` out of `organization` and return the correct `HierarchyTree` shape on 2026-05-05.
> **Auto-updated by Cursor:** Added persistent authentication — user credentials saved to Tauri disk store (with base64-obfuscated localStorage fallback in browser mode) on login/register; `initializeAuth()` automatically re-logs in with saved credentials when JWT is expired or localStorage is cleared; explicit logout clears saved credentials; eliminates repeated sign-in on app restart on 2026-05-05.
> **Auto-updated by Cursor:** Fixed auth session permanence — runtime 401 errors now trigger silent re-login via saved credentials with a singleton promise (prevents 30+ stores from stampeding parallel re-logins); `request()` no-token guard also attempts re-auth before failing; if re-login fails (password changed, credentials cleared), user is redirected to `/auth` page instead of seeing "unauthorized" error toasts; auth redirect flag reset when `/auth` page mounts so fresh login proceeds normally on 2026-05-06.
> **Auto-updated by Cursor:** Implemented Project Documentation & AI Task Generation — Docs tab on project detail page with project-scoped CRUD, GenerateDocModal with 7 doc types and SSE streaming preview, GenerateIssuesModal with doc analysis and batch issue creation, `batchCreateIssues` store method, `listByProject` API client method, mock project_id filtering, `bizforge_project_documents` MCP tool on 2026-05-05.
> **Auto-updated by Cursor:** Added Default Model setting to AI Providers — grouped dropdown of all models from connected providers, auto-saved to settings store; both AI generation modals now pass `default_model` via `messages.send()` and display current model with settings link; removed hardcoded agent fallbacks; added `allModels` derived to providers store on 2026-05-05.
> **Auto-updated by Cursor:** Added LLM Inspector Panel — global right-side collapsible panel logging all LLM requests/responses with provider color-coding (16-color pastel palette), 3-line collapsed preview, expandable full payload view, drag-resizable width (50% default, 300px–80vw range), direction arrows for sent/received, provider color picker in Settings, localStorage persistence for panel state/width/colors, and ⌘⇧I keyboard shortcut on 2026-05-05.
> **Auto-updated by Cursor:** Added composition member lists to Library company and team detail pages — Composition section now shows individual agent and skill names below the count tiles, with hover tooltips displaying each member's description; data resolved from library agent/skill pools by matching `required_skills` on 2026-05-06.
> **Auto-updated by Cursor:** Added Domo Development team template — full end-to-end 8-agent team (PM, Platform Lead, UI Developer, Backend Developer, App Engineer, Data Engineer, Automation Engineer, QA Engineer) with all 12 Domo skills; added 3 new library agents (Domo UI Developer, Domo Backend Developer, Domo QA Engineer) with full `.md` definitions referencing Domo-specific documentation and patterns; strengthened existing Domo Platform team agent prompts to explicitly reference Domo CLI commands, API tier selection, manifest conventions, and Code Engine patterns on 2026-05-06.
> **Auto-updated by Cursor:** Added Virtual Office team & division visual indicators — `orgColors.ts` utility for deterministic team/division colors, hierarchy tree fetch in office page builds `agentOrgMap` (agent→team→division chain), 2D pixel name labels now show team-colored underline bar + division pip, 3D name labels have team-colored backdrop plane + division pip, OfficeDetailPanel shows org info with assign/change/remove team controls, collapsible legend overlay groups teams by division with color swatches on 2026-05-06.
> **Auto-updated by Cursor:** Enhanced all 7 Domo demo agents with comprehensive Domo documentation standards — domo-ui-developer (Domo Design Guide with color palette, 6px typography grid, card size px mappings, da new scaffolding, domo.js/ryuu.js patterns, Phoenix charting, DDX Brick→Pro-Code conversion), domo-app-engineer (complete manifest spec with all properties, da new + BYOS templates for React/Angular/Vue, AppDB STRING-only constraint, @domoinc/toolkit all clients, Redux Toolkit state management), domo-backend-developer (codeengine library methods: sendRequest/getAccount/axios, JS/Python package lists, package lifecycle, packageMapping manifest wiring), domo-qa-engineer (8-layer test strategy covering scaffolding, data binding, AppDB, security, Code Engine, card rendering, publishing, regression), domo-platform-developer (full manifest specification, MCP tool catalog with 7 servers, dashboard/Beast Mode/page layout patterns), domo-data-engineer (DataSet vs AppDB type distinction, Stream API gzip procedure, Federated queries, Workbench, PDP at source only), domo-automation-engineer (codeengine library API table, global vs custom packages, scheduled AppDB sync pattern, cross-instance orchestration) on 2026-05-06.
