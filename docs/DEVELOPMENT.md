# Bizforge — Development Guide (macOS)

> Complete setup, architecture reference, and day-to-day workflow for developing Bizforge on macOS.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Environment Variables](#environment-variables)
- [Running the Application](#running-the-application)
- [Project Layout](#project-layout)
- [How Everything Works Together](#how-everything-works-together)
- [Desktop App (SvelteKit + Tauri)](#desktop-app-sveltekit--tauri)
- [Backend (Elixir / Phoenix)](#backend-elixir--phoenix)
- [Command Reference](#command-reference)
- [Common Workflows](#common-workflows)
- [Ports](#ports)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

Install the following via [Homebrew](https://brew.sh). If you don't have Homebrew yet:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

| Dependency | Minimum Version | Install Command |
|------------|----------------|-----------------|
| **just** | latest | `brew install just` |
| **Node.js** | 20+ | `brew install node` |
| **Elixir** (includes Erlang/OTP) | 1.15+ | `brew install elixir` |
| **PostgreSQL** | 15+ | `brew install postgresql@15` |
| **Rust** | latest stable | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |

Start PostgreSQL if it isn't running:

```bash
brew services start postgresql@15
```

Verify everything is installed:

```bash
just doctor
```

This prints the version of each tool and checks whether the required ports are free.

---

## Installation

### Option A — macOS Installer (recommended)

From the project root:

```bash
./install_mac.sh              # Full install + setup + launch
./install_mac.sh --check      # Dry run: check prerequisites only
./install_mac.sh --no-launch  # Install everything but don't start the app
```

This macOS-specific script:
- Detects your Homebrew prefix (Apple Silicon `/opt/homebrew` vs Intel `/usr/local`)
- Finds existing PostgreSQL keg-only installs (`@14`, `@15`, `@16`, `@17`) and adds them to PATH
- Auto-detects your macOS username and updates `backend/config/dev.exs` if the hardcoded DB user doesn't match
- Verifies PostgreSQL is running and starts it if needed
- Installs missing prerequisites via Homebrew
- Creates the database, runs migrations, and seeds data
- Installs backend and desktop dependencies
- Prints a full system summary before launching

### Option B — Cross-platform Installer

From anywhere on your machine (also works via curl for first-time setup):

```bash
curl -fsSL https://raw.githubusercontent.com/MantisWare/BizForge/main/install.sh | bash
```

> **Note:** The cross-platform `install.sh` may not correctly detect keg-only Homebrew formulas
> or match your PostgreSQL username. Prefer `install_mac.sh` on macOS.

### Option C — Manual

```bash
# 1. Clone the repository
git clone https://github.com/MantisWare/BizForge.git
cd bizforge

# 2. Install just (command runner)
brew install just

# 3. Install all dependencies (backend + desktop)
just setup

# 4. Create and migrate the database
just db-setup

# 5. Launch the full stack
just dev
```

### PostgreSQL User Configuration

The backend defaults to PostgreSQL username `symac` in `backend/config/dev.exs`. If your local Postgres uses a different role (commonly your macOS username or `postgres`), either:

1. Override via environment variable:

```bash
export PGUSER=your_username
```

2. Or edit `backend/config/dev.exs` directly:

```elixir
config :bizforge, Bizforge.Repo,
  username: "your_username",
  ...
```

---

## Environment Variables

The backend reads environment variables from a `.env` file at the **project root**.

### Required (production / runtime)

```bash
DATABASE_URL=postgres://localhost/bizforge_dev
SECRET_KEY_BASE=...         # Generate with: mix phx.gen.secret
GUARDIAN_SECRET_KEY=...     # Generate with: mix guardian.gen.secret
```

### Optional (adapter credentials)

Place adapter API keys in `.env.local` (gitignored, never committed):

```bash
ANTHROPIC_API_KEY=sk-...
OPENAI_API_KEY=sk-...
GEMINI_API_KEY=...
```

> For development, `dev.exs` hardcodes sensible defaults so `.env` is not strictly required locally.

---

## Running the Application

This project uses [`just`](https://github.com/casey/just) as its command runner. Install it with `brew install just`. Run `just --list` to see all available commands.

### Full Stack (recommended)

```bash
just dev
```

This starts the Phoenix backend on `:9089` and the SvelteKit dev server on `:5200`, waits for the backend health check, opens your browser to `http://127.0.0.1:5200/app`, and writes PID files so you can manage processes independently.

### Native Tauri Desktop App

```bash
just app
```

Same as above, but launches the Tauri native window instead of the browser.

### Backend Only

```bash
just backend
```

### Desktop Only (mock mode)

```bash
just desktop
```

The desktop app has 57 mock API modules that provide complete frontend functionality without a backend connection, making offline development possible.

### Stopping Services

```bash
./stop.sh              # Stop all running services (root launcher)
just stop              # Same as above via just
just stop-backend      # Stop backend only
just stop-desktop      # Stop desktop only
```

### Managing Running Services

```bash
just status            # Show what's running and which ports are in use
just logs backend      # Tail backend logs
just logs desktop      # Tail desktop logs
just restart-backend   # Restart backend without touching desktop
just restart-desktop   # Restart desktop without touching backend
```

---

## Project Layout

```
bizforge/
│
│  ── Core Application ──────────────────────────────────────────────
│
├── backend/                    Elixir/Phoenix API server
│   ├── config/                 Environment configs (dev, test, prod, runtime)
│   ├── lib/
│   │   ├── bizforge/             Business logic, schemas, contexts
│   │   └── bizforge_web/         Controllers, plugs, router, channels
│   ├── priv/
│   │   └── repo/
│   │       ├── migrations/     67 Ecto migrations
│   │       └── seeds.exs       Sample data seeder
│   ├── test/                   ExUnit test suite
│   ├── mix.exs                 Elixir dependencies & project config
│   └── mix.lock                Locked dependency versions
│
├── desktop/                    SvelteKit 2 + Tauri 2 desktop app
│   ├── src/
│   │   ├── routes/             SvelteKit file-based routing (56 pages)
│   │   │   ├── +layout.svelte  Root layout (Tauri drag region, global styles)
│   │   │   ├── +page.svelte    Landing router (auth → onboarding → /app)
│   │   │   ├── app/            Main application routes
│   │   │   ├── auth/           Login / registration
│   │   │   └── onboarding/     First-run setup wizard
│   │   ├── lib/
│   │   │   ├── api/            API client, SSE, mock handlers
│   │   │   ├── components/     Reusable UI components (20 groups)
│   │   │   ├── stores/         Svelte 5 reactive stores (48 stores)
│   │   │   ├── services/       Business logic services
│   │   │   ├── types/          TypeScript type definitions
│   │   │   └── utils/          Shared utility functions
│   │   ├── app.css             Global Tailwind styles
│   │   └── app.html            HTML shell template
│   ├── src-tauri/              Rust/Tauri native shell
│   │   ├── src/                Rust source (main.rs, lib.rs)
│   │   ├── tauri.conf.json     Tauri window & plugin config
│   │   └── Cargo.toml          Rust dependencies
│   ├── static/                 Static assets (favicon, screenshots)
│   ├── package.json            Node.js dependencies & scripts
│   ├── vite.config.ts          Vite dev server & proxy config
│   ├── svelte.config.js        SvelteKit adapter config
│   └── tsconfig.json           TypeScript compiler options
│
│  ── Workspace Protocol ────────────────────────────────────────────
│
├── SYSTEM.md                   Meta-system entry point (factory identity)
├── .bizforge/                    Runtime workspace state
│   ├── workspace.yaml          Workspace configuration
│   ├── agents/                 Active agent definitions
│   ├── projects/               Active project configs
│   └── schedules/              Heartbeat schedule definitions
│
├── operations/                 Pre-built workspace examples
│   ├── sales-engine/           B2B sales pipeline workspace
│   ├── dev-shop/               Software agency workspace
│   ├── content-factory/        Content production workspace
│   └── cognitive-os/           Personal knowledge workspace
│
├── library/                    Agent & skill template library
│   ├── agents/                 330+ agent markdown definitions
│   └── skills/                 Reusable skill definitions
│
├── templates/                  Workspace scaffolding templates
│   ├── full/                   Full-featured workspace template
│   ├── enterprise/             Enterprise workspace template
│   ├── small/                  Small team template
│   └── micro/                  Single-agent template
│
│  ── Specifications & Architecture ─────────────────────────────────
│
├── architecture/               31 architecture reference docs
│   ├── heartbeat.md            9-step agent execution cycle
│   ├── adapters.md             Runtime adapter interface
│   ├── budgets.md              Budget enforcement model
│   ├── governance.md           Approval gate system
│   ├── sessions.md             Session persistence & compaction
│   ├── dispatch.md             Dynamic adapter routing (content-based)
│   ├── workflows.md            DAG workflow engine
│   ├── tasks.md                Task coordination protocol
│   └── ...                     (+23 more architecture docs)
│
├── protocol/                   Formal specification files
│   ├── workspace-protocol.md   Workspace structure spec
│   ├── agent-format.md         Agent definition standard
│   ├── company-format.md       Company definition standard
│   ├── operations-spec.md      Full operation specification
│   └── ...                     (+10 more protocol specs)
│
│  ── Documentation & Guides ────────────────────────────────────────
│
├── docs/                       All project documentation
│   ├── DEVELOPMENT.md          This file
│   ├── getting-started.md      End-user getting started guide
│   ├── MODULE_SPECS.md         Module specification reference
│   ├── KNOWN-ISSUES.md         Known issues tracker
│   ├── hierarchy.md            Organizational hierarchy docs
│   ├── SIDEBAR_RESTRUCTURE_PLAN.md  UI restructure plan
│   ├── guides/                 How-to guides
│   │   ├── agent-design.md     Designing agents
│   │   ├── skill-design.md     Building skills
│   │   ├── workflow-design.md  Creating workflows
│   │   ├── company-setup.md    Company configuration
│   │   ├── data-architecture.md  Data layer design
│   │   ├── proactive-agents.md Proactive agent patterns
│   │   ├── signal-theory-quickstart.md  Signal theory intro
│   │   └── writing-skills.md   Writing effective skills
│   └── strategy/               Strategy & planning docs
│       ├── executive-brief.md
│       ├── nexus-strategy.md
│       ├── quickstart.md
│       ├── playbooks/
│       ├── runbooks/
│       └── coordination/
│
│  ── Integrations & Tooling ────────────────────────────────────────
│
├── integrations/               Adapter-specific exports
│   ├── claude-code/            Claude Code integration
│   ├── cursor/                 Cursor integration
│   ├── gemini-cli/             Gemini CLI integration
│   ├── github-copilot/         GitHub Copilot integration
│   ├── aider/                  Aider integration
│   ├── windsurf/               Windsurf integration
│   ├── openclaw/               OpenClaw integration
│   ├── osa/                    OSA integration
│   └── ...                     (+3 more integrations)
│
├── start.sh                    Root launcher (backend + Tauri)
├── stop.sh                     Root stop script (all dev services)
├── scripts/                    Developer & CI tooling
│   ├── start.sh                Full-stack launcher (legacy)
│   ├── convert.sh              Agent → integration converter
│   ├── install.sh              Integration installer
│   ├── lint-agents.sh          Agent file linter
│   └── *.py                    Code generation scripts
│
│  ── Project Meta ──────────────────────────────────────────────────
│
├── README.md                   Project overview & quick start
├── justfile                    Command runner (just dev, just stop, etc.)
├── Makefile                    Legacy passthrough → delegates to just
├── install.sh                  One-command cross-platform installer
├── install_mac.sh              macOS-specific installer
└── .gitignore                  Git ignore rules
```

---

## How Everything Works Together

### System Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Bizforge Architecture                           │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌─────────────────────────────────────────────────────────┐       │
│   │  Desktop Command Center (SvelteKit 2 + Tauri 2)        │       │
│   │  http://127.0.0.1:5200                                  │       │
│   │                                                         │       │
│   │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───────────┐ │       │
│   │  │Dashboard │ │ Agents   │ │Sessions  │ │ Virtual   │ │       │
│   │  │ & KPIs   │ │ Roster   │ │& Chat    │ │ Office    │ │       │
│   │  └──────────┘ └──────────┘ └──────────┘ └───────────┘ │       │
│   │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───────────┐ │       │
│   │  │Workflow  │ │ Cost     │ │ Library  │ │Governance │ │       │
│   │  │Designer  │ │ Console  │ │& Market  │ │& Audit    │ │       │
│   │  └──────────┘ └──────────┘ └──────────┘ └───────────┘ │       │
│   │                                                         │       │
│   │  48 Svelte stores  ──  57 mock modules  ──  20 groups  │       │
│   └────────────────────────────┬────────────────────────────┘       │
│                                │                                     │
│                    REST + SSE  │  Vite proxy /api → :9089            │
│                                │  Vite proxy /stream → :9089         │
│                                │                                     │
│   ┌────────────────────────────┴────────────────────────────┐       │
│   │  Backend API (Elixir + Phoenix 1.8)                     │       │
│   │  http://127.0.0.1:9089                                  │       │
│   │                                                         │       │
│   │  54 controllers  ──  ~151 routes  ──  56 schemas        │       │
│   │                                                         │       │
│   │  ┌──────────────────────────────────────────────┐      │       │
│   │  │  Core Subsystems                              │      │       │
│   │  │                                               │      │       │
│   │  │  Heartbeat ─── Budget ─── Governance ─── SSE  │      │       │
│   │  │  Sessions ──── Dispatch ── Workflows ─── Auth │      │       │
│   │  │  EventBus ──── Tasks ───── Hierarchy ─── Cron │      │       │
│   │  └──────────────────────────────────────────────┘      │       │
│   │                                                         │       │
│   │  Guardian + JWT auth  ──  Quantum scheduler             │       │
│   └────────────────────────────┬────────────────────────────┘       │
│                                │                                     │
│                     Ecto SQL   │                                     │
│                                │                                     │
│   ┌────────────────────────────┴────────────────────────────┐       │
│   │  PostgreSQL                                              │       │
│   │  67 migrations  ──  56 schemas  ──  bizforge_dev database │       │
│   └─────────────────────────────────────────────────────────┘       │
│                                                                      │
│   ┌─────────────────────────────────────────────────────────┐       │
│   │  Connected Adapters (dispatched from backend)            │       │
│   │                                                         │       │
│   │  OSA  ──  Claude Code  ──  Codex  ──  Cursor            │       │
│   │  Gemini  ──  Aider  ──  Windsurf  ──  Bash/HTTP         │       │
│   └─────────────────────────────────────────────────────────┘       │
│                                                                      │
│   ┌─────────────────────────────────────────────────────────┐       │
│   │  Workspace Protocol (plain markdown files on disk)       │       │
│   │                                                         │       │
│   │  SYSTEM.md → agents/ → skills/ → teams/ → projects/    │       │
│   │  L0 (always)  L1 (on-demand)  L2 (deep)  L3 (engine)  │       │
│   └─────────────────────────────────────────────────────────┘       │
└──────────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **User opens the app** — SvelteKit serves the desktop UI at `:5200`
2. **API requests** — Vite proxies `/api/*` and `/stream/*` to the Phoenix backend at `:9089`
3. **Backend processes requests** — Phoenix controllers validate, apply governance gates, and dispatch to business logic
4. **Agent heartbeats** — The Quantum scheduler wakes agents on their configured schedules. Each heartbeat:
   - Loads identity → checks governance → loads continuation context → resolves adapter → fetches tasks → executes → compacts session
5. **Adapter dispatch** — The Dispatch Router selects the right adapter (Claude Code, Codex, etc.) based on task content, agent default, or explicit override
6. **Real-time updates** — Phoenix PubSub broadcasts events. The desktop subscribes via SSE (Server-Sent Events) for live dashboard updates
7. **Workspace protocol** — Agents read `SYSTEM.md` and the markdown file hierarchy to understand their role, discover skills, and execute autonomously

### Technology Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Desktop UI | SvelteKit 2 + Svelte 5 | Component framework & routing |
| Desktop Native | Tauri 2 (Rust) | Native window, OS APIs, secure store |
| Styling | Tailwind CSS 4 | Utility-first CSS |
| 3D Visualization | Three.js + Threlte | Virtual office 3D scene |
| Terminal Emulation | xterm.js | In-app terminal |
| Markdown Rendering | marked + highlight.js | Content display |
| Input Sanitization | DOMPurify | XSS protection |
| Backend Framework | Phoenix 1.8 (Elixir) | API server, PubSub, channels |
| ORM | Ecto 3.13 | Database queries, migrations, schemas |
| Database | PostgreSQL 15+ | Persistent storage |
| Auth | Guardian + JWT + bcrypt | Token-based authentication |
| Job Scheduling | Quantum | Cron-based agent heartbeats |
| HTTP Client | Req | Adapter communication |
| Build Tool | Vite 5 | Desktop dev server & bundler |
| Command Runner | just | Task runner (replaces Make) |
| Package Manager | npm (desktop), Mix (backend) | Dependency management |

---

## Desktop App (SvelteKit + Tauri)

### Key Configuration

**`desktop/vite.config.ts`** — Dev server on port `5200`, proxies `/api` and `/stream` to the backend, enables HMR over WebSocket.

**`desktop/svelte.config.js`** — Uses `adapter-static` for Tauri (no SSR).

**`desktop/tsconfig.json`** — Strict TypeScript with `noImplicitAny`, `noUnusedLocals`, and `noUnusedParameters`.

### Route Structure

The app uses SvelteKit's file-based routing. The root layout disables SSR (`ssr = false`) and prerendering. The landing page at `/` resolves auth state and redirects to `/app` (the main shell) or `/auth` / `/onboarding`.

### Stores

48 Svelte 5 reactive stores (`.svelte.ts` files) manage application state — agents, sessions, budgets, workflows, notifications, and more.

### Mock Mode

57 mock API modules provide full frontend functionality without a backend. Useful for UI development, demos, and offline work. The API client (`desktop/src/lib/api/client.ts`) can switch between real and mock backends.

---

## Backend (Elixir / Phoenix)

### Key Subsystems

| Module | Responsibility |
|--------|---------------|
| `Bizforge.Heartbeat` | 9-step agent execution cycle with Quantum scheduling |
| `Bizforge.BudgetEnforcer` | ETS atomic counters, 5-level cascade, hard stop at 100% |
| `Bizforge.Governance.Gate` | Plug-based approval enforcement (spawn, delete, budget, strategy) |
| `Bizforge.Governance.Executor` | Replays approved actions automatically |
| `Bizforge.Dispatch.Router` | Content-based adapter routing (label + regex matching) |
| `Bizforge.Dispatch.Delegation` | Subtask creation with adapter-aware agent selection |
| `Bizforge.Sessions.Compactor` | Session summarization, handoff generation, context injection |
| `Bizforge.Sessions.Chain` | Linked session chains with cumulative token tracking |
| `Bizforge.Workflows.Engine` | DAG workflow execution with topological sort and retry |
| `Bizforge.Workflows.Scheduler` | Cron-based workflow triggering |
| `Bizforge.Notifications.Dispatcher` | Multi-channel notification broadcasting |
| `Bizforge.EventBus` | Phoenix PubSub topic management |
| `Bizforge.IssueDispatcher` | Task assignment with priority queue and team routing |

### Database

- **67 migrations** defining the schema evolution
- **56 Ecto schemas** modeling agents, sessions, tasks, budgets, workflows, organizations, and more
- Default dev database: `bizforge_dev`

### Config Files

| File | Purpose |
|------|---------|
| `config/config.exs` | Base application config |
| `config/dev.exs` | Development overrides (port 9089, debug, Postgres credentials) |
| `config/test.exs` | Test environment config |
| `config/runtime.exs` | Production runtime config (reads env vars) |

---

## Command Reference

All commands use `just` (install: `brew install just`). Run `just --list` for the full list.

```bash
# ── Setup ──────────────────────────
just setup              # Install all deps (backend + desktop)
just doctor             # Check prerequisites and port availability

# ── Development ────────────────────
just dev                # Full stack: backend (:9089) + desktop (:5200)
just app                # Full stack with native Tauri window
just backend            # Backend only (Phoenix on :9089)
just desktop            # Desktop only (Vite on :5200, mock mode)

# ── Process Management ─────────────
just stop               # Stop all running services
just stop-backend       # Stop backend only
just stop-desktop       # Stop desktop only
just restart-backend    # Restart backend (stop + start)
just restart-desktop    # Restart desktop (stop + start)
just status             # Show running services and ports
just logs backend       # Tail backend logs
just logs desktop       # Tail desktop logs

# ── Database ───────────────────────
just db-setup           # Create, migrate, and seed
just db-migrate         # Run pending Ecto migrations
just db-reset           # Drop → create → migrate → seed
just db-seed            # Run seeds only
just db-gen my_table    # Generate a new migration file

# ── Quality ────────────────────────
just check              # SvelteKit type check + Elixir compile warnings-as-errors
just test               # Run backend (mix test) + desktop (vitest) test suites
just test-backend       # Backend tests only (pass args: just test-backend test/my_test.exs)
just test-desktop       # Desktop tests only
just lint               # Elixir credo --strict + ESLint on desktop src/
just format             # Auto-format: mix format + prettier

# ── Build ──────────────────────────
just build              # Production Tauri app bundle (.app on macOS)
just release            # Same as build (alias)

# ── Cleanup ────────────────────────
just clean              # Stop services + remove all build artifacts
```

> **Legacy:** `make` commands still work — the Makefile delegates to `just` automatically.

---

## Common Workflows

### Adding a new backend feature

1. Generate a migration: `just db-gen add_my_table`
2. Define the schema in `lib/bizforge/`
3. Create the context module
4. Add the controller in `lib/bizforge_web/controllers/`
5. Add the route in `lib/bizforge_web/router.ex`
6. Run the migration: `just db-migrate`
7. Write tests in `backend/test/`

### Adding a new desktop page

1. Create a route directory under `desktop/src/routes/app/`
2. Add `+page.svelte` (and optionally `+page.ts` for data loading)
3. Create components in `desktop/src/lib/components/`
4. Add a store in `desktop/src/lib/stores/` if needed
5. Add the API client method in `desktop/src/lib/api/`
6. Add a mock handler in the mock API modules

### Running tests

```bash
# Backend only
just test-backend

# Specific backend test file
just test-backend test/bizforge/my_test.exs

# Desktop only
just test-desktop

# Both
just test
```

### Formatting & linting

```bash
# Auto-format everything
just format

# Check for issues without fixing
just lint
just check
```

---

## Ports

| Service | Port | URL |
|---------|------|-----|
| Phoenix backend | `9089` | `http://127.0.0.1:9089` |
| SvelteKit desktop | `5200` | `http://127.0.0.1:5200/app` |
| OSA integration | `8089` | `http://127.0.0.1:8089` |

---

## Troubleshooting

### `just doctor` reports missing tools

Install them via the commands shown in the doctor output. Most tools install via Homebrew:

```bash
brew install just node elixir postgresql@15
brew services start postgresql@15
```

For Rust, use rustup:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### Port already in use

Use `just stop` to cleanly shut down services, or force-kill:

```bash
just stop                        # graceful shutdown
lsof -ti:9089 | xargs kill -9   # force-kill backend port
lsof -ti:5200 | xargs kill -9   # force-kill desktop port
```

### PostgreSQL connection refused

Ensure PostgreSQL is running:

```bash
brew services list | grep postgresql
brew services start postgresql@15
```

### Database user mismatch

If you see authentication errors, your Postgres username likely differs from the default `symac` in `backend/config/dev.exs`. Update it to match your system user:

```bash
whoami  # shows your macOS username
```

Then edit `backend/config/dev.exs` and set `username` to match.

### Backend won't compile

Try a clean rebuild:

```bash
cd backend && mix deps.get && mix deps.compile
```

### Desktop won't start

Clear the build cache:

```bash
cd desktop && rm -rf .svelte-kit node_modules && npm install
```

### Tauri build fails

Ensure Xcode Command Line Tools are installed:

```bash
xcode-select --install
```

And that Rust is up to date:

```bash
rustup update stable
```
