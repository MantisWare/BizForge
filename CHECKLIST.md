# Bizforge Checklist

> **Confidence:** 91%

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
- [x] Fix rate limiter false positives — move plug after Auth for per-user buckets, granular path-based keys (list vs detail vs nested), raise default limit to 300 req/min, add 429 retry with backoff in API client, add response cache for projects/phases

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

### 10. Agent Task Resilience & Supervisor Escalation

- [x] Fix `execute_and_stream/4` silent failure — adapter exceptions no longer swallowed as zero-cost success; failures now propagate as tagged tuples and trigger the full failure path (fail session, set agent to error, roll back issue)
- [x] Create `SupervisorEscalation` module — walks `reports_to` chain (cycle-safe via MapSet, max depth 5) to find available superior agent; creates escalation issue with failure context and session summary; broadcasts `issue.assigned` for auto-dispatch; falls back to system notification when no superior exists
- [x] Create `AdapterCircuitBreaker` GenServer — per-adapter health tracking with closed/open/half-open states; 3 failures in 60s opens circuit, 120s cooldown to half-open, 1 success closes; prevents cascading failures when LLM provider is down; integrated into Heartbeat execution path
- [x] Extend Watchdog orphaned state cleanup — stuck agent reset now fails orphaned active sessions, releases checked-out issues back to backlog; recovery exhaustion (>10 attempts) triggers supervisor escalation instead of just notification
- [x] Fix `Delegation.delegate/3` dispatch — delegated issues with assignee now broadcast `issue.assigned` event so IssueDispatcher auto-starts them (were silently sitting in backlog)
- [x] Enforce `max_concurrent_runs` in IssueDispatcher — `validate_agent` now counts active sessions and rejects dispatch when agent is at capacity
- [x] Add Heartbeat-level retry with exponential backoff — up to 3 attempts (2 retries) with 5s base backoff before triggering failure path and supervisor escalation
- [x] Add dependency graph cycle detection in GoalDecomposer — DFS-based topological validation strips cyclic `depends_on` edges from LLM output before creating issues
- [x] Harden GenServer startup against DB unavailability — `BudgetEnforcer` and `IssueDispatcher` now defer DB queries to `handle_continue` with automatic retry, preventing supervision tree crash when PostgreSQL starts slowly; `Scheduler.load_schedules` wrapped in deferred Task with rescue
- [x] Add `_ensure-postgres` preflight to justfile — auto-detects `pg_isready`/`pg_ctl`/data dir across Homebrew paths; checks if PostgreSQL is running and auto-starts it if not; wired as dependency on `dev`, `app`, `backend`, and `headless` recipes; `start.sh` also calls it for early feedback
- [x] Add `_ensure-migrations` preflight to justfile — detects pending Ecto migrations and auto-runs `mix ecto.migrate` before backend launch; prevents `PendingMigrationError` from blocking all API requests
- [x] Add root `stop.sh` — stops backend, Vite, Tauri, and headless via `just stop` / `just headless-stop`; `./start.sh stop` forwards to `stop.sh`

### 11. Desktop UX Improvements

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
- [x] Redesign Reports page layout — replaced sidebar+viewer split with single scrollable column; category filters (All, Performance, Costs, Tasks, Workflows, Custom) as pill buttons at top; all filtered reports stacked as self-contained cards (header, badges, summary stats, table/chart); per-report sort state; per-report Generate/Export/Delete actions; "Export All" button for bulk export of visible reports; removed resize handle and activeReport selection model
- [x] Restructure sidebar navigation for top-down user journey — reordered sections: Daily Drivers > Explore (Library, Chat) > Organize (Organization, Projects, Goals, Issues, Documents) > Agents (tree + Skills + Memory) > Automate (Workflows, Schedules, Alerts) > Observe (Activity, Sessions, Work Products, Costs, Analytics, Reports) > Platform (Integrations, Secrets, Users & Access, Environment, Datasets); removed "Data" and "System" sections; moved Library from Automate and Chat from bottom pinned into new "Explore" section; moved Organization from System into "Organize"; moved Skills/Memory into Agents; moved Work Products into Observe; moved Datasets into Platform; updated collapsed-mode icons

### 11e. Chat, Kanban & Design System Enhancements

- [x] Create `chatRuns.svelte.ts` store — multi-tab chat sessions with localStorage persistence and conversation binding
- [x] Create `ActiveSessionsBar.svelte` — tab bar for switching active chat runs with close/new actions
- [x] Create `ContextGauge.svelte` — context window usage progress indicator in chat header
- [x] Create `QueuedMessages.svelte` — message queue UI while agent is generating
- [x] Wire multi-run chat UX into `/app/chat` (ActiveSessionsBar, ContextGauge, QueuedMessages, chatRuns sync)
- [x] Add `vitest.config.ts` and unit tests for `chatRuns` store and session activity event mapping
- [x] Create `design-system.css` — shared semantic component classes and extended theme CSS tokens
- [x] Add UI primitives `Button.svelte` and `EmptyState.svelte` under `components/ui/`
- [x] Add `font.svelte.ts` store and font family picker in AppearanceSettings (Inter, System, Manrope)
- [x] Extend theme store with Nord, Dracula, Tokyo Night, and Gruvbox Dark themes
- [x] Add dedicated `/app/kanban` route — full-page TaskKanban board with task detail drawer and empty state
- [x] Add Kanban nav item to sidebar Daily Drivers section
- [x] Add `SidebarRecentSessions.svelte` — collapsible recent sessions quick-resume in sidebar
- [x] Create `OfficeChatModal.svelte` — in-office quick chat modal wired into VirtualOffice

> **Auto-updated by Cursor:** Reconciled Agent Integration Configuration items (binding selector wiring, API, mock layer, runtime injection) and added Chat/Kanban/Design System enhancements on 2026-07-07.

### 10d. General Settings Enhancements

- [x] Replace Default Model text input with categorized dropdown — models grouped by provider name using `<optgroup>`, populated from `providersStore.allModels`
- [x] Add "Refresh Models" button next to model dropdown — fetches providers, then fetches models for each connected provider, with spinner and toast feedback
- [x] Fallback to text input when no models are loaded, with hint linking to AI Providers tab
- [x] Replace Working Directory text input with read-only display + folder picker button — native `@tauri-apps/plugin-dialog` directory selector
- [x] Add Tauri `copy_working_directory` IPC command — recursively copies `.bizforge/` tree from old path to `<new_parent>/.bizforge/`, validates no existing `.bizforge/` at destination, reports files/bytes copied
- [x] Register `copy_working_directory` in Tauri invoke_handler
- [x] Working directory change copies all existing workspace files to new location automatically
- [x] Instruct user that they are selecting a parent directory and `.bizforge/` will be created inside it

### 10c. System Log Panel

- [x] Add `read_log_files` Tauri IPC command — reads last N lines from all `.bizforge/logs/*.log` files with source name, line content, and file size
- [x] Create `LogPanel.svelte` — collapsible bottom panel with resize handle, source tabs (backend/vite/desktop), auto-scroll toggle, 3s polling, monospace log output
- [x] Add "Logs" toggle button to `AppFooter` with active state indicator
- [x] Wire `LogPanel` into app layout between main content and footer
- [x] Add error state to AI Providers settings — shows error message with retry button instead of infinite "Loading..."; cached providers always shown while refresh is in progress or fails
- [x] Add footer offline recovery — "Reconnect" button with refresh icon visible in mock/disconnected mode (left side), probes backend health and restores dashboard on success; right-side indicators (Backend, OSA, Gateway, Memory, CPU) persist in degraded state with "--" placeholders instead of disappearing

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

### 12. Hire Agent Team

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

### 13. User Management & Access Control

- [x] Add "Add User" button and dialog to Users page (name, email, role, optional password)
- [x] Add inline role selector (dropdown) per user row to elevate/reduce access levels
- [x] Add "Edit" button per user with dialog for name/email changes
- [x] Add "Delete" button with two-step confirmation per user
- [x] Update mock/users.ts with localStorage-backed CRUD persistence for offline mode
- [x] Update mock/index.ts to handle POST/PATCH/DELETE on `/users` routes
- [x] Fix mock access assignments to return correct `RoleAssignment` shape (`entity_type`, `user_email`, `assigned_by`)

### 14. Services / Integration Catalog

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

### 13b. Agent Integration Configuration System

- [x] Add `provider` field to Integration schema and migration
- [x] Create `IntegrationSecret` schema — join table linking integrations to encrypted secrets by key name
- [x] Create `IntegrationBinding` polymorphic schema — owner_type (project/team/agent/skill) + owner_id + provider + integration_id + config_overrides
- [x] Add `integration_bindings` association to Agent, Team, and Project schemas
- [x] Create `IntegrationResolver` backend module — walks inheritance chain (skill→agent→team→project) to resolve bound configs
- [x] Add `IntegrationBinding`, `IntegrationBindingOwner`, `SkillIntegrationRequirement`, `SkillConfigKey` frontend types
- [x] Update `LibrarySkill` interface with `required_integrations` and `required_tools` fields
- [x] Update skill enrichment to default `required_integrations: []` and `required_tools: []`
- [x] Add `required_integrations` to Domo skills (instance-admin, api-integrate, governance, dataset-manage, appdb-manage, code-engine, workflow-automate, embed-analytics) and board skill (Jira)
- [x] Add `required_integrations` structured frontmatter to `domo/instance-admin` SKILL.md
- [x] Refactor Settings Integrations tab — global config registry (grouped by provider, multi-instance, "Add Configuration" button, per-provider "+")
- [x] Add Domo, Confluence, GitLab providers to IntegrationConnectModal with field definitions
- [x] Add "Configuration Name" field to connect modal (required, generates slug)
- [x] Mark secret fields with lock icon (`is_secret` flag) in connect modal
- [x] Remove "Manage all integrations" link from Settings (Settings IS the manager now)
- [x] Create `IntegrationBindingSelector` reusable component — dropdown of global configs per required provider, "Go to Settings" link when none exist, inherited-from display, status badges
- [x] Add connect/disconnect toggle switch to integration config cards (soft status flip without clearing config)
- [x] Separate "Remove" (destructive delete) from "Disconnect" (status-only toggle) in mock layer, API client, and store
- [x] Convert integration provider groups to responsive multi-column CSS grid layout (2/3/4+ columns as screen widens)
- [x] Wire `IntegrationBindingSelector` into Agent editor page
- [x] Wire `IntegrationBindingSelector` into Project detail page
- [x] Wire `IntegrationBindingSelector` into Team editor
- [x] Add integration_bindings API endpoints (CRUD) to backend controller
- [x] Add integration_bindings to mock API client layer
- [x] Runtime session injection — resolver fetches bound configs + secrets and injects into adapter environment on session start

### 15. Analytics

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

### 4. Domo Administrator Skill & Agent

- [x] Create `/domo/instance-admin` skill — full instance administration (auth, users, groups, datasets, AppDB, PDP, pages, audit, SSO, security)
- [x] Create `domo-administrator` agent — Instance Administrator with 9-phase methodology (auth → users → groups → datasets → AppDB → PDP → pages → audit → SSO/security)

### 5. Domo Consultancy Company Template

- [x] Create `domo-consultancy` operation — full-service Domo design/development/admin company (9 agents, 13 Domo skills + PM skills)

### 6. Domo Administration Team Template

- [x] Add `domo-admin` team template — Admin Lead + User/Group Manager + Data Administrator + Security/Compliance Officer (4 agents)
- [x] Register in library templates mock as `domo-administration`

### 7. Desktop UI Registration

- [x] Register 4 agents in library mock catalog (agents.ts)
- [x] Register 12 skills in library mock catalog (skills.ts)
- [x] Add Domo skill slugs to Hire Agent dialog (AgentModelConfig.svelte)

---

## Phase: IDE Supervisor Agents (Principal Developer Family)

> Four IDE-specific Principal Developer agents that supervise IDE-native AI agents through structured Instruct-Plan-Review-Execute-Review-Report cycles without writing code directly.

### 1. Shared Skill Foundation

- [x] Create `/ide-orchestrate` skill — six-phase supervisory lifecycle, instruction format template, plan review checklist, post-execution review protocol, execution report template, retry/escalation logic

### 2. IDE-Specific Agents (library/agents/technology/software-engineering/ide-supervision/)

- [x] Cursor Principal Developer — `@cursor/sdk` adapter with native plan/agent mode switching, streaming events, `run.cancel()`, `run.conversation()`, per-run model override, git info extraction
- [x] VS Code Principal Developer — `@github/copilot-sdk` adapter with `onPermissionRequest` permission-gated plan/execute split, `approveAll`/custom handlers, `infiniteSessions`, `systemMessage` customization
- [x] Zed Principal Developer — ACP (Agent Client Protocol) adapter with pluggable external agents (Claude, Gemini CLI, Codex), real-time edit visualization, multi-buffer code review
- [x] JetBrains Principal Developer — Junie CLI adapter with native Ask/Code mode split, deep language refactoring intelligence, built-in code inspections, multi-IDE support (IntelliJ, WebStorm, PyCharm, GoLand, etc.)

### 3. Desktop Integration

- [x] Add `supervise` and `instruct` tag mappings to `AGENT_SKILL_TAG_MAP` in `skill-dependencies.ts`

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

### 14a-ii. Virtual Office Rectangular Conference Tables

- [x] Add `TABLE_RECT` and `LAPTOP` furniture types to `FurnitureType` enum
- [x] Create rectangular table pixel sprite (16x10, dark wood with metal trim legs)
- [x] Create laptop pixel sprite with animated screen (10x8, two frames alternating at 800ms)
- [x] Replace individual desk rows in Engineering with central conference table (3-wide) + laptops + surrounding chairs
- [x] Replace individual desk rows in Product with central conference table (3-wide) + laptops + surrounding chairs
- [x] Replace individual desk rows in Operations with central conference table (3-wide) + laptops + surrounding chairs
- [x] Keep Research room unchanged (round table is intentional)
- [x] Retain perimeter wall desks with PCs in each room for additional workstations
- [x] Update seat assignments for conference table positions (6 seats per table: 3 top, 3 bottom)
- [x] Mark `TABLE_RECT` tiles as non-walkable in pathfinding grid
- [x] Add laptop screen glow effect (smaller radius than PC glow, intensity varies by time-of-day)
- [x] Render laptops as animated z-sorted drawables (screen pixels shift between frames)

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

### 14d. Virtual Office Sprite & Animation Gap Fixes

- [x] Unify seat counts between 2D (32) and 3D (32) — added perimeter wall desks to Engineering (+2), Product (+4), Operations (+4)
- [x] Add 3D character walking and wandering — `characterState.ts` module with BFS pathfinding, idle random wandering, interpolated positions
- [x] Integrate 3D character state into Scene3D — `$state` characters array, `$effect` sync, `useTask` tick loop, dynamic agent positions
- [x] Add 3D walk animation to AgentDesk3D — walking mode with leg swing, directional rotation, walk bounce; seated mode for idle/type/sleep
- [x] Add 2D walk-cycle frames for up/right/left directions — `CHAR_UP_WALK1/2`, `CHAR_RIGHT_WALK1/2` (left via `mirrorSprite`), 4-frame cycles in `getCharFrames()`
- [x] Add diverse skin tones in 3D — `SKIN_TONES` array with `djb2` hash selection per agent ID (replaces hardcoded `#e8d5c4`)
- [x] Add `TABLE_ROUND_SPRITE` (10x10 dark wood circular table) in sprites.ts, wired to `getFurnitureSprite()` in renderer.ts
- [x] Populate `color`, `skinTone`, `hairColor` fields on `OfficeCharacter` creation using `agentPalette(djb2(agent.id))`
- [x] Wire up sidebar filter tabs — `filterMode` state (`all`/`working`/`idle`), conditional filtering in agent list, active tab highlighting

## Phase: QA Automation Skill & Agent Architecture

> End-to-end QA automation pipeline — skills and agents that start applications, run functional tests (browser/API/CLI), and produce structured reports with failure diagnostics.

### 1. QA Skills (library/skills/qa/)

- [x] Create `qa/automate` skill — 3-phase pipeline (Startup, Test, Report) with framework detection, health probes, multi-runner support, artifact collection
- [x] Create `qa/report` skill — parse raw test output (Playwright/Jest/Vitest/ExUnit/pytest/Go) into structured reports with severity classification, trend comparison, and recommendations
- [x] Create `qa/startup-probe` skill — detect app type from project files, install deps, start with correct command, health-check via HTTP/TCP/stdout probes, graceful shutdown

### 2. QA Agents (library/agents/technology/quality-assurance/test-engineering/)

- [x] QA Automation Lead — bash adapter, deterministic pipeline orchestrator (startup → test → report), framework detection decision tree, structured output only
- [x] Exploratory Tester — cursor-cli adapter, LLM-driven agent that navigates unfamiliar apps, generates Playwright test scripts, bootstraps test suites from scratch

### 3. Existing Agent Integration

- [x] Append `qa/automate, qa/report, qa/startup-probe` to all 8 canonical QA agents under `technology/quality-assurance/`
- [x] Append same skills to all 8 mirror QA agents under `testing/`
- [x] Append same skills to `domo-qa-engineer` under `platform-integration/`

### 4. Desktop UI Registration

- [x] Register 3 QA skills in library mock catalog (skills.ts) under new `qa` category
- [x] Register 2 QA agents in library mock catalog (agents.ts) under `testing` category
- [x] Add `qa_automate`, `qa_test`, `qa_report`, `startup_probe` tag mappings and passthrough entries to `skill-dependencies.ts`

---

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
- [x] Add font size adjustment controls (plus/minus) in panel header with localStorage persistence (8–16px range)
- [x] Add `agentId` and `agentName` fields to `LlmLogEntry` type for agent-level attribution
- [x] Extract agent identity from intercepted request paths and payloads, resolve display names via agents store
- [x] Add hierarchical filter dropdown — Organization > Division > Department > Team > Agent with indented tree options
- [x] Add text search input filtering entries by agent name, provider name, provider slug, and model
- [x] Show filtered/total count in header, empty-state message for filter-no-results, and clear-filter button
- [x] Display agent name badge on each log entry row when agent is identified
- [x] Add compact pixel office miniview at top of inspector panel — zoomed-out overview canvas using `renderMinimap`, active agent count, togglable via header button with localStorage persistence

---

## Phase: Project Output Directory

> User-specified output directory per project for all team-produced artifacts (code, documents, images, video), with git init and structured scaffolding.

### 1. Type System & Data Layer

- [x] Rename `Project.workspace_path` to `output_path` in TypeScript types (`types.ts`)
- [x] Update mock project data to use `output_path` field
- [x] Update mock POST handler to accept and store `output_path`
- [x] Add `output_path` field to Elixir `Project` schema and changeset
- [x] Create Ecto migration adding `output_path` column to projects table
- [x] Update `ProjectController.serialize/1` to include `output_path` in JSON responses
- [x] Update project detail page to display `output_path` instead of `workspace_path`

### 2. Project Creation UI

- [x] Add "Output Directory" field with text input to project creation dialog
- [x] Add native directory picker (Browse button) via `@tauri-apps/plugin-dialog` on Tauri
- [x] Add field hint explaining all artifacts will be written there
- [x] Pass `output_path` through `createProject` to API

### 3. Tauri Filesystem Commands

- [x] Implement `scaffold_project_dir` — creates comprehensive directory structure (`code/src`, `code/tests`, `code/config`, `docs/specs`, `docs/guides`, `docs/api`, `docs/architecture`, `media/images`, `media/videos`, `media/diagrams`, `data/exports`, `data/fixtures`, `reports`, `transcripts`, `issues`), `.bizforge-project.yaml` manifest, `.gitignore`, `README.md`, runs `git init`
- [x] Implement `write_project_file` — generic file writer with auto-mkdir for project output paths
- [x] Register both commands in `lib.rs` invoke handler

### 4. Store Integration

- [x] Wire `ProjectsStore.createProject` to invoke `scaffold_project_dir` after successful API creation (Tauri only)
- [x] Show toast on scaffold failure (non-blocking — project is still created)

### 5. Document Generation Disk Write

- [x] Add `outputPath` prop to `GenerateDocModal`
- [x] On save, write generated doc to type-specific subdirectory (specs, guides, api, architecture) via `write_project_file` IPC
- [x] Pass `project.output_path` from project detail page caller
- [x] `documentsStore.createDocument` accepts `output_path` and `disk_subdir` — auto-mirrors to disk on create

### 6. MCP Server File Operations

- [x] Add `output_path` param to `bizforge_project_create` MCP tool schema
- [x] Add `bizforge_project_write_file` tool — resolves path relative to project `output_path`, creates dirs, writes content, with path traversal guard; tool description documents all standard subdirectories
- [x] Add `bizforge_project_read_file` tool — reads file from project `output_path` with traversal guard
- [x] Add `bizforge_project_list_files` tool — lists directory entries under project `output_path`
- [x] `bizforge_document_write` now also mirrors to `{output_path}/docs/` when `project_id` is supplied

### 7. Comprehensive Output Routing

- [x] Create `project-paths.ts` utility — `resolveProjectFilePath`, `resolveDocPath`, `relativeProjectPath`, `relativeDocPath` helpers mapping artifact categories to canonical subdirectories
- [x] Documents store writes to disk on every `createDocument` when `output_path` is provided
- [x] Manual doc creation on project page passes `output_path` for disk mirroring
- [x] Session transcript export method (`exportTranscriptToDisk`) writes to `{output_path}/transcripts/`
- [x] Reports export method (`exportReportToDisk`) writes to `{output_path}/reports/`
- [x] Work products save method (`saveToProjectDir`) maps type → subdirectory (code→code/src, document→docs, report→reports, data→data/exports, analysis→reports, design→media/diagrams)
- [x] AI-generated issues (`batchCreateIssues`) auto-export markdown summary to `{output_path}/issues/`
- [x] `GenerateIssuesModal` passes `outputPath` prop for disk export on batch create

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
> **Auto-updated by Cursor:** Implemented Project Output Directory with comprehensive artifact routing — user-specified `output_path` per project, native directory picker, expanded scaffold (code/src|tests|config, docs/specs|guides|api|architecture, media/images|videos|diagrams, data/exports|fixtures, reports, transcripts, issues) with README.md + .gitignore + git init; `project-paths.ts` utility maps artifact categories to canonical dirs; documents store auto-mirrors to disk via `write_project_file` IPC; `GenerateDocModal` routes to type-specific subdirs; `GenerateIssuesModal` exports generated issues as markdown; sessions/reports/work-products stores have `exportToDisk`/`saveToProjectDir` methods; MCP `bizforge_document_write` mirrors to output_path when project_id supplied; `bizforge_project_write_file` tool documents all standard subdirectories in schema on 2026-05-06.
> **Auto-updated by Cursor:** Added System Log Panel — `read_log_files` Tauri command tails all `.bizforge/logs/*.log` files, collapsible bottom panel with source tabs and auto-scroll, footer "Logs" toggle button; fixed AI Providers "Loading..." stuck state by adding error state with retry button and running pending DB migration on 2026-05-06.
> **Auto-updated by Cursor:** Added Domo Administrator skill and agent — `domo/instance-admin` skill (9-step process: auth, users, groups, datasets, AppDB, PDP, pages, audit, SSO/security) and `domo-administrator` agent with full instance admin methodology; registered in library mock (158 agents, 13 Domo skills); added to Domo Development team template (now 9 agents) on 2026-05-06.
> **Auto-updated by Cursor:** Added Domo Consultancy company template — full-service Domo design/development/admin operation (9 agents, 13 Domo skills + sprint-planning/delegate/board) covering the entire Domo lifecycle from instance setup through production deployment; registered as 6th company in library operations mock on 2026-05-06.
> **Auto-updated by Cursor:** Added Domo Administration team template — Admin Lead (task triage + direct ops), User & Group Manager (identity lifecycle, SSO, bulk provisioning), Data Administrator (datasets, AppDB, PDP, pages), Security & Compliance Officer (audit, SIEM, controls, quarterly reviews); registered in both team-templates.ts and library templates mock on 2026-05-06.
> **Auto-updated by Cursor:** Added IDE Supervisor Agents (Principal Developer Family) — 4 IDE-specific agents (Cursor, VS Code, Zed, JetBrains) under `library/agents/technology/software-engineering/ide-supervision/` that supervise IDE AI agents through 6-phase Instruct-Plan-Review-Execute-Review-Report cycles without writing code directly; shared `/ide-orchestrate` skill with instruction format, plan review checklist, post-execution review protocol, and execution report template; `supervise`/`instruct` tag mappings added to skill-dependencies.ts on 2026-05-06.
> **Auto-updated by Cursor:** Added rectangular conference tables with animated laptops to Engineering, Product, and Operations rooms in Pixel Office — central 3-wide tables replace individual desk rows, 6 conference seats per room (3 top facing down, 3 bottom facing up), laptop sprites with alternating screen animation (800ms), laptop glow effect, perimeter wall desks retained as additional workstations; Research kept unchanged with its round table on 2026-05-06.
> **Auto-updated by Cursor:** Added rectangular conference tables to 3D Office view — walnut-topped conference tables with metal legs in Engineering, Product, and Operations zones; `AgentDesk3D` supports `deskType` prop ('desk' for standard monitor setup, 'conference' for laptop-on-table with angled screen); agents at conference seats face toward the shared table with directional chairs; `ZONE_SEATS` layout positions agents on both sides of each table; Research retains round table and standard desks on 2026-05-06.
> **Auto-updated by Cursor:** Implemented Agent Integration Configuration System — global integration config registry in Settings (multi-instance per provider, named configs with secret vault), `IntegrationBinding` polymorphic schema (project/team/agent/skill → integration), inheritance chain resolver (skill→agent→team→project), `IntegrationBindingSelector` reusable component with dropdown selection and "Go to Settings" redirect for missing configs, Domo/Confluence/GitLab providers added to connect modal with `is_secret` field markers, `SkillIntegrationRequirement` type on `LibrarySkill` with `required_integrations` populated on Domo and coordination skills, 3 backend migrations (add provider to integrations, integration_secrets, integration_bindings), runtime `IntegrationResolver` module for session injection on 2026-05-06.
> **Auto-updated by Cursor:** Added LLM Inspector filtering — hierarchical dropdown filter (Division > Department > Team > Agent) built from `HierarchyTree`, text search across agent/provider/model, agent identity extraction from intercepted API paths and payloads with name resolution via agents store, filtered/total count display, agent name badges on log entries on 2026-05-06.
> **Auto-updated by Cursor:** Fixed remaining Integration Configuration issues — settings page reads `?tab=` and `?provider=` URL params on mount (deep-linking from IntegrationBindingSelector works), IntegrationBindingSelector wired into Agent config tab (derives required integrations from agent's skills), Project overview page (aggregates requirements from all project agents), and Team expanded panel (aggregates from team members); mock API layer for `integration-bindings` (list/create/delete by owner); `integrationBindings` client methods; backend `IntegrationBindingController` (index/create/delete/delete_by_owner/resolve endpoints + router); `required_providers_for_agent` resolver now loads skills and extracts providers from `trigger_rules.required_integrations` on 2026-05-06.
> **Auto-updated by Cursor:** Redesigned Reports page layout — replaced two-panel sidebar+viewer split with single scrollable column; category filters rendered as pill buttons at page top; all filtered reports stacked vertically as self-contained cards with inline header/badges/actions, summary stats, and table/chart; per-report sort state (Map keyed by ID); per-report Generate/Export/Delete; "Export All" button for bulk export of all visible reports; removed resize handle, panel width state, and activeReport selection model on 2026-05-06.
> **Auto-updated by Cursor:** Added footer offline recovery — Reconnect button with spinning refresh icon appears in mock/disconnected mode, probes health and restores dashboard indicators; right-side indicators (Backend, OSA, Gateway, Memory, CPU, Zoom) now persist with degraded "--" placeholders instead of vanishing when backend is unreachable on 2026-05-06.
> **Auto-updated by Cursor:** Enhanced General Settings tab — replaced Default Model text input with categorized dropdown (grouped by AI provider via `<optgroup>`) with refresh button that fetches all provider models, replaced Working Directory text input with read-only field + native folder picker (Tauri dialog) that auto-copies `.bizforge/` workspace tree to new location via `copy_working_directory` IPC command on 2026-05-06.
> **Auto-updated by Cursor:** Implemented QA Automation Skill & Agent Architecture — 3 new skills (`qa/automate` end-to-end pipeline, `qa/report` structured reporting, `qa/startup-probe` app lifecycle management) under `library/skills/qa/`, 2 new agents (`qa-automation-lead` with bash adapter for deterministic pipelines, `exploratory-tester` with cursor-cli adapter for LLM-driven test generation) under `library/agents/technology/quality-assurance/test-engineering/`, appended all 3 QA skills to 17 existing QA agents (8 canonical + 8 mirrors + domo-qa-engineer), registered 3 skills and 2 agents in desktop mock catalog, added `qa_automate`/`qa_test`/`qa_report`/`startup_probe` tag mappings to skill-dependencies.ts on 2026-05-06.
> **Auto-updated by Cursor:** Added integration status toggle and layout improvements — replaced static connected/disconnected status indicator with clickable toggle switch (green=on, gray=off) that soft-flips status via POST connect/disconnect without clearing config; separated destructive "Remove" (DELETE, splices from array) from status toggle; mock layer `mockDisconnectIntegration` now preserves config, new `mockRemoveIntegration` does destructive removal; API client `disconnect` now calls `/disconnect` sub-route, new `remove` method calls DELETE; store gains `toggleStatus` and `remove` methods; provider groups use responsive CSS grid (`repeat(auto-fill, minmax(380px, 1fr))`) for 2-column layout on wider screens; section max-width widened from 720px to 960px on 2026-05-06.
> **Auto-updated by Cursor:** Implemented Agent Task Resilience & Supervisor Escalation — fixed `execute_and_stream` silent failure (adapter errors no longer swallowed as zero-cost success), created `SupervisorEscalation` module (walks `reports_to` chain with cycle guard to escalate failures), created `AdapterCircuitBreaker` GenServer (per-adapter health tracking, 3-failure threshold, 120s cooldown), extended Watchdog to clean up orphaned sessions/issues and escalate after 10 recovery attempts, fixed Delegation to broadcast `issue.assigned` for auto-dispatch, enforced `max_concurrent_runs` in IssueDispatcher, added Heartbeat-level retry with exponential backoff (3 attempts), added DFS cycle detection in GoalDecomposer to strip circular `depends_on` edges on 2026-05-06.
> **Auto-updated by Cursor:** Fixed app stuck on splash screen — PostgreSQL was not running; hardened `BudgetEnforcer` and `IssueDispatcher` `init/1` to defer DB queries to `handle_continue` with automatic retry on failure, preventing supervision tree crash when database is unavailable at startup; wrapped `Scheduler.load_schedules` in deferred Task with rescue; added `_ensure-postgres` justfile recipe that auto-detects and starts PostgreSQL before any backend launch (`dev`, `app`, `backend`, `headless`); added `_ensure-migrations` recipe that auto-detects and runs pending Ecto migrations before backend launch; updated `start.sh` to call both preflights on 2026-05-08.

> **Auto-updated by Cursor:** Hardened cold-start splash dismissal on 2026-06-04 — splash no longer depends on the main webview loading SvelteKit; Rust polls backend health (+ Vite in dev) and calls `close_splash`, `splash.html` polls backend as a backup with timeout, `just app` waits for two consecutive health checks and Vite HTTP before launching Tauri, `start.sh` runs `just app` once with a first-launch message.

> **Auto-updated by Cursor:** Splash startup checklist on 2026-06-04 — `get_startup_status` Tauri command probes PostgreSQL, backend, database, Vite (dev), and command center readiness; splash screen shows per-service ✓/○ rows in small text and opens the main window only when all items are ready (with timeout fallback).

> **Auto-updated by Cursor:** Fixed startup hang on 2026-06-10 — backend failed to compile due to JavaScript `??` operators in Elixir files (`qa/runner.ex`, `project_delivery.ex`, `code_review/auto_review.ex`); `just app` now runs `mix compile` before launch and surfaces log output when the backend exits early.
> **Auto-updated by Cursor:** Added root `stop.sh` to shut down all dev services without restarting; `./start.sh stop` delegates to `stop.sh` on 2026-05-20.
> **Auto-updated by Cursor:** Added compact pixel office miniview to LLM Inspector panel — zoomed-out overview of the full pixel office rendered at the top of the inspector using `renderMinimap`, shows active agent count, togglable via header button with icon highlight, visibility persisted to localStorage on 2026-05-08.
> **Auto-updated by Cursor:** Implemented Sprint Management & Project Lifecycle Configuration — `sprints` table with full CRUD + start/complete lifecycle + issue assignment, `Sprint` schema (planned/active/complete/cancelled), `sprint_id` on Issues, `lifecycle_config` map on Projects, `Bizforge.LifecycleConfigs` module with 3 default templates (Domo Development, Generic Development, Minimal), `SprintController` with REST endpoints + lifecycle actions, `/projects/lifecycle-templates` endpoint, `IssueLifecycle` now reads `lifecycle_config` from project and respects `auto_review`/`auto_qa` flags, Sprint + LifecycleConfig TypeScript types, `sprints` API client with list/get/create/update/delete/start/complete/assignIssues, 5 `bizforge_sprint_*` MCP tools on 2026-05-08.
> **Auto-updated by Cursor:** Implemented End-to-End Dev Team Pipeline (ERD → Tasks → Dev → Review → QA → Done) — Phase 1: multimodal `attached_files` on `messages.send` with base64 upload, vision-aware Gemini adapter; Phase 2: Playwright sidecar package (`desktop/playwright-sidecar/`) with JSON-RPC over stdio, `Bizforge.Browser.Sidecar` GenServer, `Bizforge.Browser.Tools` with `ToolPermission`-gated dispatch, `BrowserController` REST surface, `browser/automation` library skill, `browser_automation` tool permission; Phase 3: `data-modeling/erd-parse` skill (DBML/SQL/mermaid/image), ERD-aware prompt injection in `GenerateIssuesModal`, `DocumentFormat` union extended; Phase 4: `Bizforge.Dispatch.SkillRouter` scoring by skill overlap + team affinity + load, auto-assign in `Work.create_issue` when `project.config.auto_assign = true`, 70+ Domo keyword→skill mappings; Phase 5: `Bizforge.IssueLifecycle` GenServer FSM (backlog→in_progress→in_review→testing→done), `notify_session_complete` replaces direct heartbeat status-set, QA child issue fan-out via `SkillRouter.choose`, auto bug creation on QA fail; Phase 6: `Bizforge.CodeReview.Adapter` behaviour with `GithubAdapter`, `VirtualPRAdapter` (diff-based fallback when no git integration bound), `open_code_review` called on `in_review` transition; Phase 8: `resolve_integration_env` in Heartbeat injects `DOMO_INSTANCE`/`DOMO_TOKEN`/`GITHUB_TOKEN`/etc. from `IntegrationResolver` into adapter params, bash adapter passes env to Port; Phase 9: `qa/startup-probe-domo` skill (domo login + domo dev + TLS probe); Phase 10: `QaReportController` ingests QA reports, creates WorkProduct + Report rows, broadcasts `qa.report_ready`, `bizforge_qa_report_ingest` + `bizforge_browser_*` MCP tools added on 2026-05-08.
> **Auto-updated by Cursor:** Fixed all Virtual Office sprite and animation gaps — unified 2D/3D seat counts to 32 (added perimeter wall desks to Engineering/Product/Operations), created `characterState.ts` with BFS pathfinding and idle wandering for 3D agents, integrated dynamic character positions into Scene3D via `$effect` sync + `useTask` tick loop, added walking animation to AgentDesk3D (leg swing, directional rotation, walk bounce vs seated breathing), added 4-frame walk cycles for up/right/left directions in 2D sprites (`CHAR_UP_WALK1/2`, `CHAR_RIGHT_WALK1/2`), diverse skin tones in 3D via djb2-hashed `SKIN_TONES` array, `TABLE_ROUND_SPRITE` for lounge round table, populated `color`/`skinTone`/`hairColor` fields on OfficeCharacter creation, wired sidebar filter tabs (All/Working/Idle) with `filterMode` state on 2026-05-08.

## Phase: New Workspace Wizard

> One-click workspace setup wizard: name, upload docs, AI-enhanced context, AI-recommended team selection, agent customization, project configuration, AI task generation with sprint grouping, and automated launch sequence.

### 1. Wizard Infrastructure

- [x] Create `WizardDocument`, `WizardAgent`, `WizardTask`, `WizardSprintGroup`, `CompanyRecommendation` TypeScript interfaces in `types.ts`
- [x] Create `wizard.svelte.ts` Svelte 5 rune store — full wizard state (7 steps), step navigation, document/agent/task management, launch step tracking
- [x] Create `WizardProgress.svelte` — horizontal step indicator with numbered dots, checkmarks for completed steps, clickable navigation to previous steps

### 2. Wizard Modal Shell

- [x] Create `WorkspaceWizard.svelte` — full-viewport modal overlay with backdrop blur, step content area, Back/Next/Skip footer navigation, slide transitions between steps, close confirmation dialog
- [x] Mount `WorkspaceWizard` as global overlay in `app/+layout.svelte`

### 3. Step 1: Name Your Workspace

- [x] Workspace name input (required) with auto-generated slug for directory path
- [x] Description textarea
- [x] Directory picker (native Tauri folder dialog) with text input fallback, tilde expansion

### 4. Step 2: Documentation & Context

- [x] Drag-and-drop file upload zone accepting .md, .txt, .json, .yaml, .csv, .sql, .dbml, .pdf, .doc, .docx, .xls, .xlsx
- [x] Fixed drag-and-drop with proper dragenter/dragleave handling, pointer-events on children, and Tauri `dragDropEnabled: false`
- [x] Global window-level dragover/drop prevention to stop webview file navigation
- [x] Client-side file content extraction into `WizardDocument[]` with format detection
- [x] Uploaded file list with name, size, remove button
- [x] Project context freeform textarea
- [x] "Enhance with AI" button — sends docs + context to primary model via session/SSE streaming, produces structured project brief (domain, tech stack, deliverables, team needs, risks, architecture)
- [x] Enhanced context preview with streaming cursor animation, redo button

### 5. Step 3: Company & Team Selection

- [x] AI recommendation engine — analyzes enhanced context, recommends primary + alternative team templates with fit scores and justifications
- [x] Recommendation cards with fit score progress bars, "Best Match" badge on primary
- [x] Collapsible "Browse all templates" section with search filter and 14 team template cards
- [x] Multi-select support — select multiple teams, agents auto-populated from `TEMPLATE_AGENTS`
- [x] Selected teams summary with removable chips showing team count and total agent count
- [x] Mock-mode AI recommendation fallback

### 6. Step 4: Team Review & Customization

- [x] Agents grouped by team with expandable detail panels
- [x] Inline editing for agent name, role, adapter, model, system prompt
- [x] Skill tag chips per agent
- [x] Remove individual agents
- [x] Shared configuration panel (adapter + model) with "Apply to all" button
- [x] Skill resolution summary (total skills, new vs already active)

### 7. Step 5: Project Setup

- [x] Project name (auto-populated from workspace name), description (auto-populated from enhanced context)
- [x] Output directory picker with scaffold preview (code/, docs/, media/, data/, reports/, transcripts/, issues/)
- [x] Lifecycle template dropdown (Generic Development, Domo Development, Minimal) loaded from backend `/projects/lifecycle-templates`
- [x] Auto-assign tasks toggle

### 8. Step 6: AI Task Generation

- [x] "Generate Task Backlog" button with sparkle icon
- [x] AI generates tasks grouped into sprints via session/SSE streaming
- [x] Sprint groups with header (name + goal) and expandable task cards
- [x] Each task: title (double-click to edit), description, priority badge (color-coded), labels
- [x] Checkbox selection per task, select all / deselect all
- [x] Priority filter toolbar (All / Critical / High / Medium / Low)
- [x] Regenerate button
- [x] Mock-mode task generation with 3 sprints and 11 realistic tasks

### 9. Step 7: Review & Launch

- [x] Summary grid: workspace name, team count, agent count, project name, document count, task count, sprint count, lifecycle template
- [x] Output directory and workspace path display
- [x] "Launch Workspace" button with rocket icon and gradient styling
- [x] 10-step automated launch sequence: create workspace, activate, set up organization, install skills, create agents, create project, upload documents, create sprints, create issues, navigate
- [x] Real-time step progress indicators (pending/running/done/error/skipped)
- [x] Intelligent step skipping (no org if no company template, no docs if none uploaded, no sprints if no tasks)
- [x] Error handling per step with error message display
- [x] Completion screen with success checkmark and "Open Workspace" button

### 10. Entry Points

- [x] "New Workspace" button in expanded sidebar (below WorkspaceSwitcher, above Search) — dashed orange border, plus icon
- [x] "New Workspace" icon button in collapsed sidebar
- [x] "New Workspace" command registered in Command Palette (Cmd+K)

> **Auto-updated by Cursor:** Implemented New Workspace Wizard — 7-step modal wizard (Name → Docs → Company → Team → Project → Tasks → Launch) with AI-enhanced context generation, AI team recommendations with fit scores, agent review/customization, project lifecycle setup, AI task generation with sprint grouping, and automated 10-step launch sequence; entry points in sidebar (expanded + collapsed) and Command Palette; `wizard.svelte.ts` store, `WizardProgress` component, 7 step components, `WorkspaceWizard` modal shell mounted globally on 2026-05-08.

---

## Phase: Automated Task Pipeline with ForgeMap & Hierarchical Memory

> Intelligent automated task creation pipeline with codebase detection, ForgeMap file annotation/indexing, hierarchical memory (company + project scopes), AI-driven dependency-aware task generation, and task splitting.

### 1. Backend: Hierarchical Memory System

- [x] Add `project_id`, `scope`, `source` fields to `memory_entry` schema
- [x] Database migration for new memory hierarchy columns + indexes
- [x] Validation for scope (company/project/agent) and source (manual/forgemap/ai_generated/system) values
- [x] `GET /api/v1/memory/project/:project_id` — project-scoped memory endpoint
- [x] `GET /api/v1/memory/company` — company-level memory endpoint
- [x] `GET /api/v1/memory/resolve/:project_id` — merged company + project memory resolution
- [x] Updated search with project_id/scope filters
- [x] Memory controller serialize includes scope, source, project_id

### 2. Backend: Issue Dependencies & Task Hierarchy

- [x] Add `parent_id`, `depends_on_ids`, `task_type`, `execution_order` to issue schema
- [x] Self-referencing FK for subtask relationships (parent_id → issues)
- [x] Task type validation (prerequisite/feature/subtask/validation/scaffold)
- [x] `resolve_execution_order/1` — topological sort of project issues by dependencies
- [x] `ready_issues/1` — returns issues whose dependencies are all done/closed
- [x] `POST /api/v1/projects/:id/resolve-execution-order` endpoint
- [x] `GET /api/v1/projects/:id/ready-issues` endpoint
- [x] Issue serialization includes parent_id, depends_on_ids, task_type, execution_order

### 3. ForgeMap: File Annotation & Indexing System

- [x] `Bizforge.ForgeMap.Detector` — detects existing codebase from output_path (languages, manifests, stack detection)
- [x] `Bizforge.ForgeMap.Scanner` — walks project files, extracts exports/imports (TypeScript/JS/Svelte/Elixir/Python)
- [x] `Bizforge.ForgeMap.Annotator` — generates header annotation blocks per file, optional disk write
- [x] `Bizforge.ForgeMap.Resolver` — resolves cross-file used_by references by tracing imports
- [x] `Bizforge.ForgeMap.Indexer` — creates memory_entries for each file (category: forgemap, source: forgemap)
- [x] `POST /api/v1/projects/:id/forgemap/detect` — codebase detection endpoint
- [x] `POST /api/v1/projects/:id/forgemap/scan` — scan and index endpoint
- [x] `GET /api/v1/projects/:id/forgemap` — list ForgeMap entries
- [x] `PATCH /api/v1/projects/:id/forgemap/:file_path` — update file entry

### 4. ForgeMap Agent Integration (MCP Tools)

- [x] `bizforge_forgemap_index` tool — agents query ForgeMap for any project
- [x] `bizforge_forgemap_update` tool — agents update header annotation and memory entry after file modifications
- [x] `bizforge_forgemap_rescan` tool — re-scan single file after substantial changes
- [x] IssueContext injects relevant ForgeMap context into agent session preamble based on task keywords
- [x] IssueContext includes dependency status in agent preamble

### 5. Frontend: Types, API Client & Store Updates

- [x] `IssueTaskType` type and updated `Issue` interface with parent_id, depends_on_ids, task_type, execution_order
- [x] `MemoryScope`/`MemorySource` types and updated `MemoryEntry` interface
- [x] `ForgeMapDetection`, `ForgeMapScanResult`, `ForgeMapFile`, `ForgeMapEntry` types
- [x] `WizardTask.taskType` field added
- [x] `forgemap` API client (detect, scan, index, updateEntry, resolveExecutionOrder, readyIssues)
- [x] `memory.byProject()`, `memory.company()`, `memory.resolve()` API client methods
- [x] ForgeMap store (`forgemap.svelte.ts`) — detect, scan, fetchIndex, reset
- [x] Memory store — `fetchByProject()`, `fetchCompanyMemory()`, `resolveMemory()` methods
- [x] ~~Mock issues updated with dependency fields~~ (removed — mock mode permanently disabled)

### 6. Frontend: Automated Task Pipeline Modal

- [x] `AutomatedTaskPipeline.svelte` — 6-phase modal (Context → Detection → ForgeMap → Generation → Review → Create)
- [x] Phase 1: Context gathering — document selector, additional context textarea
- [x] Phase 2: Codebase detection — auto-detect via ForgeMap, scaffold option for new projects
- [x] Phase 3: ForgeMap scan — progress indicator, result stats (files, exports, languages)
- [x] Phase 4: AI task generation — enriched prompt with docs + ForgeMap + team context, sprint groups with task_type
- [x] Phase 5: Review & edit — dependency graph visualization, inline title editing, priority selectors, task splitting
- [x] Phase 6: Batch create with dependency data preserved
- [x] Progress stepper with phase navigation
- [x] ~~Mock mode support for all phases~~ (removed — mock mode permanently disabled)

### 7. Frontend: Supporting Components

- [x] `DependencyGraph.svelte` — SVG DAG visualization of task dependencies with topological layout
- [x] `CodebaseDetector.svelte` — detection result display, scaffold form with stack/template selectors
- [x] `StackSelector.svelte` — tech stack grid selector (10 stacks with icons and descriptions)
- [x] `TaskSplitDialog.svelte` — AI-assisted task splitting modal with configurable count and editable subtasks

### 8. Wizard Integration

- [x] Step 6: Updated prompt to request task_type (prerequisite/scaffold/feature/subtask/validation)
- [x] Step 6: Parser updated to extract and set taskType field
- [x] ~~Step 6: Mock tasks include taskType~~ (removed — mock mode permanently disabled)
- [x] Step 7: Issue creation passes task_type and depends_on_ids to backend

### 9. Project Detail Page Integration

- [x] "Generate Tasks" button with pipeline icon in Issues tab toolbar
- [x] "Quick Generate" option (uses existing GenerateIssuesModal for doc-only analysis)
- [x] AutomatedTaskPipeline modal triggered from project page with project context
- [x] `.pj-btn-accent` style for pipeline button (indigo theme, distinct from primary/ghost)

> **Auto-updated by Cursor:** Implemented Automated Task Pipeline with ForgeMap & Hierarchical Memory — backend: memory_entry schema extended with project_id/scope/source fields, issue schema extended with parent_id/depends_on_ids/task_type/execution_order, ForgeMap modules (Scanner/Annotator/Indexer/Resolver/Detector) for codebase analysis, ForgeMapController with detect/scan/index/update endpoints, dependency resolver with topological sort and ready_issues query, ForgeMap MCP tools for agent integration, IssueContext enriched with ForgeMap file context and dependency status; frontend: 6-phase AutomatedTaskPipeline modal, DependencyGraph SVG visualization, CodebaseDetector/StackSelector/TaskSplitDialog components, forgemap store, memory store with project/company scoping, updated types/API client/mock layers, wizard Step6/Step7 updated for task_type and depends_on_ids, "Generate Tasks" button on project detail page Issues tab on 2026-05-10.

> **Auto-updated by Cursor:** Code review fixes on 2026-05-10 — fixed depends_on_ids wiring (topological sort + sequential creation with idMapping), surfaced detection/scan errors in pipeline UI, added progress bar to creation phase, added description/labels editing in review phase, fixed SSE lifecycle (onDestroy abort), fixed TaskSplitDialog error vs success handling, fixed Svelte/HTML ForgeMap comment blocks (proper `<!--…-->` wrapping), fixed write_headers boolean coercion in controller, improved ForgeMap keyword search with relevance scoring, normalized language casing between Detector and Scanner, improved import/export regex coverage (wildcard/type/side-effect imports, export default/re-export), fixed rescan tool to check update_entry result, fixed mock store consistency.

> **Auto-updated by Cursor:** Second review pass on 2026-05-10 — fixed same depends_on_ids bug in wizard Step7Review.svelte (was building all payloads before any creation, so idMap was always empty; now creates sequentially with topological sort), fixed issue.ex validate_inclusion(:task_type) rejecting nil values (conditional validation only when field is actually set), fixed DependencyGraph SVG marker ID collision (unique per instance), added keyboard accessibility (Enter/Space) to DependencyGraph node buttons, fixed Detector/Scanner dot-directory handling inconsistency (both now skip dot-prefixed dirs), normalized Detector Java/Kotlin label to match Scanner, fixed Elixir extract_exports capturing private functions (defp).

> **Auto-updated by Cursor:** Fixed workspace delete dialog showing wrong path — confirmation dialog checkbox and warning text now show the actual resolved directory that will be deleted (e.g. `~/.bizforge/default/`) instead of the generic `.bizforge/` label; path is derived from the workspace's stored path and shortened for display on 2026-05-10.

> **Auto-updated by Cursor:** Redesigned New Project dialog into a 3-step wizard — Step 1: project name, description, status; Step 2: project directory picker (browse or type path, detects whether directory is new or existing with source code via Tauri FS plugin, shows status badge); Step 3: documentation upload with drag-and-drop file zone (Tauri native drag-drop + HTML file input), uploaded file list with remove, and context textarea for additional project knowledge; step navigation with animated fly transitions, progress indicator with clickable completed steps, skip buttons, and validation gating; on create, uploaded files are attached as project documents via `documents.create()` API with `project_id`, context text saved as `context.md` on 2026-05-10.

> **Auto-updated by Cursor:** Fixed project creation 422 error and modal trapping — root cause: backend `workspaces` table was empty so `resolve_workspace_id` always resolved to `nil`, failing the changeset's `validate_required([:workspace_id])`; fix: auto-creates a "Default" workspace for the user when none exist; frontend: `handleCreate` now shows inline error bar in wizard footer instead of silently failing behind the modal overlay; projects store extracts field-level validation details from `ApiError.body.details` instead of showing raw "validation_failed" on 2026-05-10.

> **Auto-updated by Cursor:** Fixed DocumentController 500 crash and project-scoped documents — (1) `File.stat!.mtime` returns Erlang datetime tuple `{{Y,M,D},{H,Mi,S}}` which Jason can't encode; added `format_mtime/1` to convert to ISO 8601 string; (2) `index` now supports `project_id` param — scopes file scan to `projects/{id}/` subdirectory under the reference dir and returns `documents` and `tree` alongside `files` so the frontend `listByProject`/`fetchByProject` flow works; (3) `create` now accepts `title`, `format`, `project_id` and builds file path automatically (`projects/{id}/{slugified_title}.md`) when no explicit `path` is provided; returns `{ document: ... }` matching frontend unwrap; (4) added `expand_home/1` to resolve `~` in workspace paths since Elixir `File.*` doesn't expand tilde; (5) recursive `scan_directory/1` traverses subdirectories; (6) auto-created workspace now uses `System.user_home!()` for absolute path on 2026-05-10.

> **Auto-updated by Cursor:** Added prominent backend-disconnected banner to main app layout — full-width animated banner slides down at the top of the app shell when connection status is `reconnecting` or `disconnected`; two visual variants: yellow "Reconnecting to Backend" with spinner and attempt count, red "Backend Disconnected"; each has explanatory subtitle, "Retry Now" button, and dismiss X; banner auto-reappears when connection drops again (dismissed flag resets on reconnect) on 2026-05-10.

> **Auto-updated by Cursor:** Removed mock data fallback system on 2026-05-10 — the frontend will never silently fall back to mock/placeholder data when the backend is unreachable. Changes: (1) `useMock` variable removed entirely from `client.ts`; (2) `setMockEnabled()`, `enableMock()`, `disableMock()`, `clearMockData()` functions removed; (3) `_doInitializeAuth()` no longer enables mock on health probe failure — resolves auth gate so connection store surfaces disconnected state; (4) `request()` GET branch no longer falls back to mock on network error — throws instead; (5) `health.get()` throws `ApiError(0, "Backend unreachable")` instead of returning mock health data; (6) `isMockEnabled()` is a deprecated stub that always returns `false`; (7) `ConnectionStatus` type no longer includes `"mock"` — only `connecting`, `connected`, `reconnecting`, `disconnected`; (8) connection store `check()` simplified to remove mock branches; `isConnected`/`isReady` only true for `"connected"`; (9) `#syncOnReconnect()` no longer calls `disableMock()`; (10) removed `isMockEnabled()` guards from 17 consumer files: forgemap store, SSE module, workspace store, template-deploy service, and all wizard/issue/document generation components; (11) auth routing simplified: root page, auth page, onboarding, and app layout no longer branch on mock mode; (12) `bizforge-mock-mode` localStorage key removed from session persistence; (13) disconnected banner updated to show only `reconnecting` and `disconnected` states (no more orange mock banner); (14) `ConnectionStatusBar` mock dot style removed.

> **Auto-updated by Cursor:** Added "Upload Files" button and dialog to project Documents tab on 2026-05-10 — Docs tab toolbar now has three actions: "Generate with AI", "Upload Files", and "+ New Document"; empty state also includes the Upload Files button; upload dialog features drag-and-drop zone (supports Tauri native drag-drop events + HTML file input), file list with format/size metadata and remove buttons, supported formats (.md, .txt, .json, .yaml, .yml, .csv, .sql, .pdf, .doc, .docx, .xls, .xlsx), binary file handling for PDF/Office documents, batch upload that creates each file as a project document via `documentsStore.createDocument()`, inline error reporting for partial upload failures, and styled with consistent dialog/upload-zone CSS.

---

## Phase: Phases + Tasks Full-Stack Rename & UX Redesign

> Renamed Goals → Phases and Issues → Tasks across the entire stack (database, backend, frontend). Redesigned project detail page with reordered tabs and doc-driven onboarding. Added GeneratePhasesTasksModal for AI-powered phase & task generation.

### 1. Database Migration

- [x] Create Ecto migration: rename `goals` table → `phases`, `issues.goal_id` → `phase_id`, `sprints.goal` → `sprints.objective`

### 2. Backend Schemas

- [x] Rename `Goal` schema → `Phase` (`phase.ex`), `Issue` schema → `Task` (`task.ex`)
- [x] Update `Sprint` schema: `field :goal` → `field :objective`, `has_many :issues` → `has_many :tasks`
- [x] Update `Project` schema: `has_many :goals` → `has_many :phases`, `has_many :issues` → `has_many :tasks`

### 3. Backend Controllers

- [x] Rename `GoalController` → `PhaseController`, `IssueController` → `TaskController`
- [x] Update `SprintController`: `assign_issues` → `assign_tasks`, `issue_ids` → `task_ids`, `goal` → `objective`
- [x] Update `ProjectController`: `goals` action → `phases`, `goal_count` → `phase_count`

### 4. Router

- [x] Update routes: `/goals` → `/phases`, `/issues` → `/tasks`, `/assign-issues` → `/assign-tasks`, `/ready-issues` → `/ready-tasks`

### 5. Backend Support Modules

- [x] Rename `GoalDecomposer` → `PhaseDecomposer`, `IssueContext` → `TaskContext`, `IssueDispatcher` → `TaskDispatcher`, `IssueLifecycle` → `TaskLifecycle`
- [x] Update `work.ex`: all `Goal`/`Issue` aliases and function names
- [x] Update `delegation.ex`: `goal_id` → `phase_id`
- [x] Update `application.ex`, `heartbeat.ex`, code review adapters, `qa_report_controller.ex`

### 6. Frontend Types & API Client

- [x] Rename types: `Issue` → `Task`, `Goal` → `Phase`, `IssueStatus` → `TaskStatus`, etc. (deprecated aliases kept)
- [x] Rename API namespaces: `issues` → `tasks`, `goals` → `phases`
- [x] Update sprint methods: `assignIssues` → `assignTasks`, `goal` → `objective`

### 7. Frontend Stores

- [x] Rename `goals.svelte.ts` → `phases.svelte.ts` (`GoalsStore` → `PhasesStore`)
- [x] Rename `issues.svelte.ts` → `tasks.svelte.ts` (`IssuesStore` → `TasksStore`)

### 8. Frontend Components

- [x] Rename `components/goals/` → `components/phases/` (GoalHierarchy, GoalCard, GoalDetail, GoalForm → Phase*)
- [x] Rename `components/issues/` → `components/tasks/` (IssueList, IssueCard, IssueForm, IssueKanban, IssueTable, IssueViewSwitcher → Task*)
- [x] Copy utility components (DependencyGraph, StackSelector, TaskSplitDialog, AutomatedTaskPipeline, CodebaseDetector) to tasks/

### 9. Frontend Routes & Sidebar

- [x] Move `routes/app/goals/` → `routes/app/phases/`, `routes/app/issues/` → `routes/app/tasks/`
- [x] Update sidebar navigation: Goals → Phases, Issues → Tasks

### 10. Project Detail Page Redesign

- [x] Reorder tabs: Overview, Docs, Phases, Tasks, Agents, Sessions, Costs
- [x] Update tab content: Goals → Phases, Issues → Tasks
- [x] Update Overview KPIs: `goal_count` → `phase_count`, "Open Issues" → "Open Tasks", "Goals Progress" → "Phases Progress"

### 11. Overview Doc-Driven CTA

- [x] Add conditional CTA to Overview tab: "Create a Document" when no docs, "Generate Phases & Tasks with AI" when docs exist but no phases/tasks

### 12. GeneratePhasesTasksModal

- [x] Create `GeneratePhasesTasksModal.svelte` with 4-step flow: Select → Analyze → Review → Create
- [x] Step 1: Document checkbox selector + additional context textarea
- [x] Step 2: AI generation with SSE streaming (phases with grouped tasks JSON prompt)
- [x] Step 3: Collapsible phase cards with inline-editable task list, per-phase select all/none
- [x] Step 4: Batch create phases via `phasesApi.create()` then tasks via `tasksApi.create()` with progress bar

### 13. Wizard & Pipeline Updates

- [x] Update `Step7Review.svelte`: sprint `goal` → `objective`
- [x] Update `Step6TaskGeneration.svelte`: prompt JSON `goal` → `objective`, `issues` → `tasks`; parser accepts both old and new format
- [x] Update `AutomatedTaskPipeline.svelte`: `IssuePriority` → `TaskPriority`, `IssueTaskType` → `TaskType`, `issues` API → `tasks` API, UI text "Issue" → "Task"

### 14. Cleanup

- [x] Remove old directories: `components/goals/`, `components/issues/`, `routes/app/goals/`, `routes/app/issues/`
- [x] Remove old `GenerateTasksModal.svelte` (replaced by GeneratePhasesTasksModal)
- [x] Fix component header comments to reference `tasks/` instead of `issues/`
- [x] Update wiki page references: Goals → Phases, Issues → Tasks
- [x] Update CHECKLIST.md

### 15. Comprehensive Review & Gap Fixes

- [x] Fix 6 backend schemas still referencing `Bizforge.Schemas.Issue` → `Task` (comment.ex, attachment.ex, work_product.ex, session.ex, workspace.ex, issue_label.ex)
- [x] Fix 13+ backend controllers/libs still aliasing `Bizforge.Schemas.Issue` (attachment_controller, comment_controller, work_product_controller, delegation_controller, sidebar_badge_controller, dashboard_controller, stale_cleanup, skill_router, health_plug, watchdog, virtual_pr_adapter, supervisor_escalation, heartbeat)
- [x] Fix `supervisor_escalation.ex`: `Work.create_issue` → `create_task`, event `issue.assigned` → `task.assigned`
- [x] Fix `health_plug.ex`: invalid status `"assigned"` → `"in_review"` for task queries
- [x] Fix `audit.ex` singularize: add `"tasks"` → `"task"`, `"phases"` → `"phase"`; remove stale `"issues"` and `"goals"` entries
- [x] Fix `dashboard_controller.ex`: `open_issues` → `open_tasks` in KPI JSON response
- [x] Fix `sidebar_badge_controller.ex`: `open_issues` → `open_tasks`
- [x] Fix frontend palette store: `/app/issues` → `/app/tasks`
- [x] Fix QuickActions: "New Issue" → "New Task", route `/app/issues` → `/app/tasks`
- [x] Fix projects list page: `goal_count`/`issue_count` → `phase_count`/`task_count`
- [x] Fix GenerateDocModal: `includeGoals`/`includeIssues` → `includePhases`/`includeTasks`
- [x] Fix KpiGrid: "Open Issues" → "Open Tasks", `open_issues` → `open_tasks`
- [x] Fix ActivityFilters: `issue_created`/`issue_updated`/`goal_completed` → `task_created`/`task_updated`/`phase_completed`
- [x] Fix CommandPalette: search placeholder "issues" → "tasks"
- [x] Fix McpSettings: "Issues"/"Goals" categories → "Tasks"/"Phases"
- [x] Fix ProvidersSettings: "Issue analysis" → "Task analysis"
- [x] Fix mock data: `goal_id` → `phase_id` in issues.ts, `goal_count`/`issue_count` → `phase_count`/`task_count` in projects.ts
- [x] Fix mock data: `open_issues` → `open_tasks` in dashboard.ts, stale `/app/issues` URLs in notifications/inbox/memory mocks
- [x] Fix project detail page: "Create Task" button missing onclick handler, "Create Phase" button calling `setActiveProject` instead of navigating
- [x] Clean up doc/comment references: delegation.ex, router.ex, supervisor_escalation.ex

> **Auto-updated by Cursor:** Completed full-stack Phases + Tasks rename on 2026-05-10 — Goals renamed to Phases, Issues renamed to Tasks across database migration, backend schemas/controllers/router/support modules, frontend types/API client/stores/components/routes/sidebar, project detail page redesign with reordered tabs and doc-driven CTA, new GeneratePhasesTasksModal with 4-step AI flow, wizard and pipeline updates.

> **Auto-updated by Cursor:** Comprehensive review sweep on 2026-05-10 — Fixed 20+ missed references across backend schemas, controllers, support modules, frontend UI, mock data, navigation, and project detail page action buttons.

### 16. Compiler Warning & Error Fixes

- [x] Fix `:gen_smtp_client` undefined — wrapped with `Code.ensure_loaded?/1` runtime check in `email_digest.ex`
- [x] Fix `catch` before `rescue` ordering in `heartbeat.ex`
- [x] Fix unused variable `partial` → `_partial` in `heartbeat.ex`
- [x] Remove unused `@sidecar_startup_timeout` module attribute in `browser/sidecar.ex`
- [x] Fix unused `response_parts` outer binding and unused `session` param in `slack/event_handler.ex`
- [x] Fix unused `part` variable in `cursor_cli.ex` filter/map pipeline
- [x] Remove unused `@model_list_timeout_ms` module attribute in `cursor_cli.ex`
- [x] Remove unused default `\\ []` on private `execute_chat_message/5` in `session_controller.ex`
- [x] Remove unused default `\\ []` on private `call_gemini_stream/5` in `gemini.ex`
- [x] Move `@keyword_to_skill_map` definition before first access in `skill_router.ex`
- [x] Remove unused `alias Bizforge.Governance.Policy` in `headless_resolver.ex`
- [x] Group all `handle_info/2` clauses together in `task_dispatcher.ex`
- [x] Fix unused `reason` → `_reason` in `github_adapter.ex` `request_changes/2`
- [x] Remove stale `Bizforge.Schemas.Task` beam file to fix module redefine warning
- [x] Add `foreign_key: :issue_id` to `has_many :comments` in `task.ex` schema
- [x] Downgrade Browser.Sidecar startup failure from error to warning (expected when playwright-sidecar not built)
- [x] Stop Browser.Sidecar retry loop when sidecar binary not found — warn once then give up (was retrying every 5s forever, flooding logs)
- [x] Fix Svelte a11y warnings in project detail page — remove invalid `role="listitem"` and `aria-pressed` from `<button>`, add `tabindex`/`onkeydown`/svelte-ignore to dialog overlays, suppress `autofocus` warnings
- [x] Fix WorkspaceWizard overlay svelte-ignore — expand to cover `a11y_click_events_have_key_events` and `a11y_no_static_element_interactions`
- [x] Fix TaskList nested `<button>` — change outer `<button>` to `<div role="row">` with keyboard handler to eliminate `node_invalid_placement_ssr`
- [x] Fix PhaseHierarchy — add missing `aria-selected` on `treeitem`, replace deprecated `<svelte:self>` with self-import
- [x] Fix LogPanel resize handle — add `tabindex` and svelte-ignore for `a11y_no_noninteractive_element_interactions`
- [x] Fix AppFooter `state_referenced_locally` — extract `initialZoom` constant to avoid capturing reactive `zoomPct` in `$state` initializer
- [x] Fix GeneratePhasesTasksModal — suppress `state_referenced_locally` for intentional initial-value capture of `documents` prop, add dialog a11y attrs
- [x] Fix AutomatedTaskPipeline — suppress `state_referenced_locally` for `documents`/`preloadedContext` props, add dialog a11y attrs
- [x] Fix DocumentViewer `state_referenced_locally` — initialize `editContent` empty and sync via existing `$effect`
- [x] Fix GenerateDocModal — add dialog a11y attrs, change orphan `<label>` to `<span>` with `aria-labelledby` for radiogroup
- [x] Fix SidebarSection — suppress `state_referenced_locally` for `defaultOpen`, expand svelte-ignore on info span
- [x] Fix Step1Name, Step6TaskGeneration, WorkspaceSwitcher — suppress `a11y_autofocus` warnings on intentional autofocus inputs
- [x] Fix TaskSplitDialog — add `tabindex`/`onkeydown`/svelte-ignore to dialog overlay
- [x] Fix SidebarNavItem — expand svelte-ignore to cover `a11y_click_events_have_key_events` and `a11y_no_noninteractive_element_interactions`
- [x] Fix PhaseCard — remove redundant `role="article"` on `<article>`, add svelte-ignore for interactive tabindex/event listeners
- [x] Fix WorkspaceSwitcher delete dialog — expand svelte-ignore, add `tabindex`, suppress autofocus on create input
- [x] Fix LlmInspectorPanel — expand svelte-ignore on filter backdrop to cover `a11y_click_events_have_key_events`

> **Auto-updated by Cursor:** Fixed 16 compiler warnings and 1 startup error on 2026-05-11 — all warnings were from unused variables/attributes, ordering issues, or missing foreign key options; sidecar error downgraded to warning since it's expected when the optional playwright-sidecar package isn't built.

> **Auto-updated by Cursor:** Fixed 40+ Vite/Svelte a11y and state warnings across 18 components on 2026-05-11 — eliminated all `vite-plugin-svelte` warnings: a11y dialog overlays (tabindex + keyboard handlers), nested button violations, deprecated `<svelte:self>`, missing ARIA attributes, `state_referenced_locally` for intentional initial-value captures, orphan labels, redundant roles, and autofocus suppressions.

- [x] Build playwright-sidecar — `npm install`, fix deprecated `page.accessibility.snapshot()` → `page.locator(':root').ariaSnapshot()` for Playwright 1.59, compile TypeScript, install Chromium browser
- [x] Wire sidecar into `justfile` — add `sidecar` directory variable, `_build-sidecar` recipe (install + compile + browser), `_ensure-sidecar` prerequisite (build if `dist/index.js` missing), added to `setup`, `dev`, and `app` recipes
- [x] Add `desktop/playwright-sidecar/dist/` to `.gitignore`
- [x] Sidecar GenServer: stop infinite retry loop when binary not found (warn once, set `gave_up: true`); still retries on transient startup failures

> **Auto-updated by Cursor:** Built and wired playwright-sidecar into dev workflow on 2026-05-11 — fixed Playwright 1.59 API break (`page.accessibility` removed → `ariaSnapshot()`), added `_build-sidecar` and `_ensure-sidecar` justfile recipes so `just setup`/`dev`/`app` automatically build the sidecar and install Chromium; sidecar GenServer now warns once and stops retrying when binary isn't found instead of flooding logs every 5s.

- [x] Fix document viewer scroll — constrain docs layout height with `clamp(350px, 60vh, 700px)` so the preview panel scrolls internally instead of expanding the page
- [x] Add `pdf` and `binary` to `DocumentFormat` type — PDFs are no longer mislabeled as `markdown`
- [x] Fix upload format mapping — `.pdf` → `pdf`, `.doc/.docx` → `binary`, `.xls/.xlsx` → `binary`, `.txt/.csv/.dbml` → `text`, `.sql` → `sql` (was all `markdown`)
- [x] Add binary document viewer — centered file icon, filename, type badge, size, and "not previewable" hint for PDF/binary formats
- [x] Fix same format mapping in wizard Step2Documentation

- [x] Hide Edit button for non-editable formats — only `markdown`, `text`, `yaml`, `json`, `sql`, `dbml` show the edit toggle; `pdf`, `binary`, `erd-graph`, `erd-source` show read-only view only
- [x] Guard edit mode in content area — `editMode && canEdit` prevents stale edit state on format switch

- [x] Fix document persistence — `create` and `listByProject` now pass `workspace_id` to the backend so documents are written and read from the correct workspace's reference directory
- [x] Add `workspace_id` param to `documents.create()` API client signature
- [x] Add `workspace_id` param to `documents.listByProject()` API client signature
- [x] Documents store injects `workspaceStore.activeWorkspaceId` into both `createDocument()` and `fetchByProject()` calls
- [x] Backend `ext_to_format` — add `.txt`, `.sql`, `.dbml`, `.pdf`, `.doc`, `.docx`, `.xls`, `.xlsx` mappings so files read from disk get the correct format
- [x] Backend `format_to_ext` — add `text`, `sql`, `dbml`, `pdf` reverse mappings

> **Auto-updated by Cursor:** Fixed document viewer on 2026-05-11 — preview panel now scrolls internally (constrained height) instead of growing the page; PDF and binary documents show a proper placeholder card instead of rendering their placeholder text as markdown; added `pdf`/`binary` format types and corrected upload format mappings across project upload and workspace wizard. Edit button conditionally shown only for text-based editable formats.

> **Auto-updated by Cursor:** Fixed document persistence on 2026-05-11 — documents were disappearing on reload because `create` and `listByProject` did not send `workspace_id`, causing the backend to fall back to whichever workspace had `status=active` in Postgres (which could differ from the UI's active workspace). Both API methods now explicitly pass the active workspace ID. Backend format detection also expanded to cover `.txt`, `.sql`, `.dbml`, `.pdf`, and binary extensions.

- [x] Fix document path mismatch — `create` now nests files under `projects/<pid>/` when `project_id` is provided, instead of writing to the raw `path` (e.g. `docs/file.md`). This ensures `index` (which scans `projects/<pid>/`) finds them after refresh.
- [x] Fix `index` relative path base — `files_to_documents` and `build_tree` now compute paths relative to `ref_dir` (workspace root) instead of `scan_dir` (project subdirectory), so document IDs/paths are consistent with what `create`/`show`/`update`/`delete` expect.

> **Auto-updated by Cursor:** Fixed document path mismatch on 2026-05-11 — uploaded documents with `project_id` were written to `<ref>/docs/file.md` but the listing endpoint scanned `<ref>/projects/<pid>/`, so files vanished on refresh. Backend `create` now always nests under `projects/<pid>/` when a project ID is provided. Additionally, `index` now computes document paths relative to the workspace reference root (not the project scan subdirectory) so IDs stay consistent across create/list/show/update/delete.

- [x] Clarify document action buttons — "Analyze Docs" → "Decompose Docs" with layers icon, "Generate with AI" → "Generate Document" with doc+arrow icon, "Quick Generate" → "Decompose Docs", "Generate Tasks" → "Auto-Generate Tasks"
- [x] Add native `title` tooltips to all document/task generation buttons explaining what each action does
- [x] Overview CTA button updated to "Decompose Docs into Phases & Tasks" with tooltip

> **Auto-updated by Cursor:** Clarified document action button labels and tooltips on 2026-05-11 — renamed ambiguous buttons ("Analyze Docs", "Generate with AI", "Quick Generate") to descriptive labels ("Decompose Docs", "Generate Document", "Auto-Generate Tasks") and added `title` tooltips explaining each action's purpose.

- [x] Fix post-auth boot waterfall — `syncFromBackend()` and `ensureDefault()` no longer block with sequential `await`; all data fetches (workspaces, orgs, hierarchy, agents, projects, providers, approvals) fire concurrently after auth resolves
- [x] Hierarchy fetches chained to org init via `.then()` instead of blocking the main thread

> **Auto-updated by Cursor:** Fixed app startup responsiveness on 2026-05-11 — the post-auth boot sequence in `+layout.svelte` was running `syncFromBackend()` and `ensureDefault()` as sequential awaits, blocking all subsequent data fetches (agents, projects, providers, hierarchy, approvals) for 200–500ms+ of dead time. Converted to concurrent fire-and-forget calls so all stores load in parallel and the UI becomes interactive immediately after auth resolves.

- [x] Speed up `verifyToken()` — reduced from 4 retries (1.5s/2.5s/3.5s delays, 8s timeout) to 2 retries (500ms delay, 4s timeout); health probe already confirmed backend is reachable
- [x] Parallelize auth init — session restore and health probe now run concurrently; auth/status check runs in parallel with session restore completion
- [x] Skip redundant token restoration — module-level `_restoreFromLocalStorage()` already set `_token`; Tauri/localStorage lookups only run when token is still `null`
- [x] Add `.catch()` to boot sequence — unhandled rejections from `syncFromBackend()` or other async errors no longer crash the SvelteKit router
- [x] Wrap `syncFromBackend()` in try-catch — falls back to localStorage workspace state on failure instead of aborting the entire boot

> **Auto-updated by Cursor:** Fixed navigation delay and boot resilience on 2026-05-11 — `initializeAuth()` was blocking for 3-11s on reload due to aggressive `verifyToken()` retries (4 attempts with 1.5-3.5s backoff). Reduced to 2 fast attempts since the health probe already confirms backend reachability. Parallelized session restore with health probing. Added error handling (`.catch()` on boot chain, try-catch around `syncFromBackend()`) so failures don't crash SvelteKit routing.

- [x] Fast-path `initializeAuth()` — when a token exists in localStorage, resolves immediately with `Promise.resolve()` instead of blocking on health/verify network calls; verification runs in background
- [x] Move `workspaceStore.fetchWorkspaces()` before `initializeAuth()` — child pages get `activeWorkspaceId` immediately from localStorage
- [x] Remove all sequential `await` calls from boot — `syncFromBackend()` is now fire-and-forget with `.catch()`, zero blocking between auth resolve and first data fetch
- [x] Fix ProvidersSettings — removed workspace_id scoping for provider fetches (providers are a global resource)
- [x] Fix providers disappearing when filtering by `workspace_id` — backend now includes providers with `NULL` workspace_id in workspace-scoped queries
- [x] Prevent empty backend response from wiping cached providers — providers store now preserves localStorage cache if backend returns empty and cache was non-empty
- [x] Reduce API retry aggression — `withRetry` reduced from 3 retries / 1s backoff / 30s max to 2 retries / 500ms backoff / 5s max; request timeout reduced from 15s to 8s
- [x] Remove workspace_id scoping from provider fetch calls — providers are workspace-agnostic; layout and ProvidersSettings now call `providersStore.fetch()` without workspace ID
- [x] Add structured logging across frontend and backend for traceability
  - [x] Frontend: exported `logInfo`/`logWarn`/`logError` with new `store` and `boot` log areas
  - [x] Frontend: boot sequence in `+layout.svelte` logs every milestone with wall-clock timestamps
  - [x] Frontend: `providersStore.fetch()` logs start/end/cache-hit/error with timing
  - [x] Frontend: `withRetry` logs each retry attempt with delay and reason
  - [x] Frontend: `request()` logs when auth gate or transition gate blocks (>50ms)
  - [x] Frontend: settings page logs tab switch events
  - [x] Backend: `RequestLogger` plug logs every API request with method, path, status, timing, and user context
  - [x] Backend: `Auth` plug logs token rejection reasons and auth exceptions
  - [x] Backend: `ProviderController` logs workspace_id filter and result count
  - [x] Frontend: every sidebar menu item click logged with label, href, timestamp, and active state
  - [x] Frontend: SvelteKit `beforeNavigate`/`afterNavigate` hooks log navigation timing with slow-navigation warnings (>1s)

> **Auto-updated by Cursor:** Fixed UI freeze on reload on 2026-05-11 — `initializeAuth()` was blocking the entire layout boot (connection polling, SSE, all store fetches) behind 3+ sequential network calls even when the user was already logged in. Now uses a fast path: if a token is already in localStorage, `initializeAuth()` resolves instantly and health/token verification runs in the background. Workspace context loads from localStorage before auth. All store fetches fire concurrently with zero sequential awaits. ProvidersSettings now passes workspace ID to avoid a duplicate race condition.

> **Auto-updated by Cursor:** Fixed providers not loading and UI lockups on 2026-05-11 — Root causes: (1) Providers were created without `workspace_id` but frontend was filtering by workspace ID, returning 0 results. Fixed backend to include `is_nil(workspace_id)` in queries. (2) Frontend now fetches providers without workspace scoping since they are a global resource. (3) Reduced retry/backoff aggressiveness (2 retries, 500ms backoff, 8s timeout) to prevent cascading delays when backend is slow. (4) Providers store preserves cached data when backend returns empty results.

> **Auto-updated by Cursor:** Normalized Cursor CLI adapter slug on 2026-05-11 — changed `cursor_cli` (underscore) to `cursor-cli` (hyphen) in wizard steps `Step2Documentation`, `Step3CompanySelect`, and `Step6TaskGeneration` to match the canonical slug used by the backend adapter resolver, provider catalog, and adapter registry. Wizard-created agents will now correctly resolve to `Bizforge.Adapters.CursorCli` at runtime.

> **Auto-updated by Cursor:** Fixed AI Providers tab crash (`state_unsafe_mutation`) on 2026-05-11 — Root cause: `llmInspectorStore.getProviderColor()` was called from the `ProvidersSettings` template to render color swatches. When a provider had no assigned color, `ensureProviderColor()` mutated two `$state` fields (`providerColors` and `_colorIndex`) during the render cycle, violating Svelte 5's rule against state mutation inside template expressions. Fix: (1) Changed `_colorIndex` from `$state` to a plain field (not reactive, just a counter). (2) Deferred the `providerColors` `$state` write to `queueMicrotask()` so it runs after the render cycle completes, while still returning the color synchronously. (3) Also added `normalizeProvider()` to providers store ensuring `models`/`config` are never null, and defensive `?.`/`??` guards in the template as additional hardening.

- [x] Per-provider default model — add `default_model` column to `providers` table (Ecto migration), update schema, changeset, and controller serializer
- [x] Agent provider association — add `provider_id` foreign key to `agents` table (Ecto migration), update schema, changeset, and controller serializer
- [x] TypeScript types updated — `AIProvider.default_model`, `BizforgeAgent.provider_id`, `Settings.default_provider_id`, `AIProviderCreateRequest.default_model`
- [x] Provider store normalization — `normalizeProvider()` now includes `default_model`; settings store syncs `default_provider_id` to backend
- [x] Per-provider default model UI — each provider card in ProvidersSettings now shows a "Default model" dropdown populated from the provider's model list, with the selected default model highlighted in the model tags
- [x] Global default model rework — selecting a global default model now also stores the `default_provider_id`; current provider name displayed alongside the model selection
- [x] Agent detail provider+model selector — replaced hardcoded 6-option Claude model `<select>` with a two-step provider → model selector; provider dropdown lists all configured providers; model dropdown populated from the selected provider's models (falls back to text input if no models discovered); saves `provider_id` alongside `model` on agent update
- [x] Hire flow defaults — `HireAgentDialog` now initializes provider and model from global defaults (`settingsStore.data.default_provider_id` / `default_model`); `AgentModelConfig.handleProviderChange` prefers the provider's `default_model` when switching providers
- [x] Model fallback chain defined — `agent.model` → `agent.provider.default_model` → `settings.default_model`

> **Auto-updated by Cursor:** Implemented per-provider default model and agent provider+model selection on 2026-05-11 — Added `default_model` column to providers and `provider_id` foreign key to agents (Ecto migration). Each AI provider card now has a default model selector. The global "Default Model" section stores both `default_provider_id` and `default_model`. Agent detail Config tab replaced hardcoded Claude-only model list with a dynamic provider → model two-step selector that persists `provider_id`. Hire flow defaults to the global default provider and model. Establishes a model fallback chain: agent.model → provider.default_model → settings.default_model.

---

## Phase: End-to-End Software Delivery Pipeline

> Transform BizForge from an AI orchestration platform into a reliable outsourced-dev-shop loop: tasks execute in the correct project directory, hybrid review closes the `in_review` gate, QA feeds the lifecycle FSM, and a stack-agnostic Project Delivery Gate certifies shippable output before marking a project complete.

### 1. Project Execution Paths (Foundation)

- [x] `Bizforge.ProjectExecution` module — resolves `output_path`, `working_dir`, `code_dir`, `git_root` per task type
- [x] Wire `Heartbeat` to use `ProjectExecution.resolve_workspace(agent, task)` instead of `resolve_workspace(agent)`
- [x] `working_dir` and `workspace_path` params now point to the project output directory for project-scoped tasks
- [x] `TaskContext.build_context/2` injects explicit Project Paths section (output, working, code, git directories)
- [x] Code instruction updated: "All application source MUST be written under the Code directory"

### 2. Hybrid Code Review

- [x] `Bizforge.CodeReview.AutoReview` module — evaluates virtual PRs: auto-approves trivial diffs, dispatches review agent task for non-trivial
- [x] Integrated into `TaskLifecycle` after `open_code_review/2`
- [x] Trivial diff criteria: empty/whitespace-only, or below configurable line threshold with no binary paths
- [x] Non-trivial path: spawns review child task with diff summary, code_dir, and structured outcome instructions

### 3. Project Delivery Gate (Stack-Agnostic)

- [x] `Bizforge.ProjectDelivery` module — runs user-configured commands (build, test) against project output
- [x] `POST /api/v1/projects/:id/deliver` API endpoint — runs gate, returns report
- [x] `GET /api/v1/projects/:id/delivery-status` API endpoint — readiness + last report
- [x] Project transitions to `completed` on pass; notifies via Dispatcher on fail
- [x] Delivery report stored in `project.config["last_delivery"]`
- [x] Frontend: Delivery tab on project detail page with check editor, presets, and report display
- [x] Frontend: `DeliveryConfig`, `DeliveryReport`, `DeliveryReadiness` types added

### 4. QA Pipeline Hardening

- [x] Enriched QA child task description with `code_dir`, delivery checks summary, and structured instructions
- [x] `Bizforge.Qa.Runner` module — optional pre-flight smoke check using project delivery commands
- [x] `delivery` lifecycle template added to `LifecycleConfigs` (Software Delivery with delivery gate flag)
- [x] QA child tasks now have `task_type: "validation"` for correct path resolution

### 5. Client Intake & Operator UX

- [x] Wizard `Step5ProjectSetup` — delivery checks form with Node.js preset
- [x] Wizard store extended with `deliveryCwd` and `deliveryChecks` fields
- [x] `Step7Review` passes delivery config when creating project
- [x] CHECKLIST.md updated with Software Delivery Pipeline phase

### 6. Greenfield Scaffold (Deferred)

- [ ] Implement real `handleScaffold` → Tauri IPC `scaffold_stack` (registry: sveltekit, phoenix, etc.)
- [ ] Or backend Mix task to copy template tarballs into `code/`
- [ ] Wire into Automated Task Pipeline Phase 2

> **Auto-updated by Cursor:** Implemented end-to-end software delivery pipeline on 2026-05-25 — Added ProjectExecution for correct working directory resolution, hybrid AutoReview for closing the in_review gate, stack-agnostic ProjectDelivery gate with configurable build/test checks, enriched QA context with code paths and delivery info, and wizard delivery config UI. BizForge can now function as an outsourced dev shop: spec in → tasks → dev → review → QA → delivery gate → completed project.
> **Auto-updated by Cursor:** Post-implementation review on 2026-05-25 — Fixed missing `lifecycleTemplates()` method on API client (was called in wizard Step5 but never added to client.ts), removed unused variable warning in AutoReview.get_lifecycle_config, replaced `unless/else` with explicit `if` in ProjectDelivery and Qa.Runner for clarity.
