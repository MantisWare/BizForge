# Canopy

![Canopy Command Center](desktop/static/canopy-screenshot.png)

> Open-source workspace protocol and command center for AI agent systems.
> Build autonomous AI companies — not chatbots.

Canopy is a workspace protocol that turns folders of markdown into fully operational AI companies. Define agents, skills, teams, budgets, and governance in plain files — then connect any AI backend (Claude Code, OSA, Codex, Gemini, Cursor, Aider, Windsurf) and watch them work autonomously on heartbeat schedules.

The desktop command center gives you a native app to hire from 330+ agents, watch them collaborate in a pixel-art virtual office, monitor token costs in real-time, and intervene when needed.

**Manage AI systems, not prompts.**

---

## Quick Start

```bash
# macOS: recommended installer (handles keg-only Homebrew, PG user detection)
cd canopy && ./install_mac.sh

# Cross-platform: install and launch in one command
curl -fsSL https://raw.githubusercontent.com/Miosa-osa/canopy/main/install.sh | bash
```

Installs prerequisites, clones the repo, sets up the database, and opens the app.

```bash
# Already cloned? Manual setup
brew install just            # one-time: install the command runner
cd canopy && just setup && just dev
```

```bash
# Just want the protocol? No app needed
cd canopy/operations/sales-engine
# Claude Code, Cursor, OSA, Codex — any agent reads SYSTEM.md and starts working
```

---

## How It Works

| Step | What Happens |
|------|-------------|
| **01** | Pick a workspace: `sales-engine/`, `dev-shop/`, `content-factory/`, `cognitive-os/`, or build your own |
| **02** | Connect your agent: Claude Code, OSA, Cursor, Codex, Gemini, Aider, Windsurf, or OpenClaw |
| **03** | Run: agent reads `SYSTEM.md`, discovers skills and specialists, operates autonomously |

**If it can read markdown, it's hired.**

---

## Architecture

```
Pick Workspace (sales-engine, dev-shop, content-factory, cognitive-os, custom)
        |
        v
Backend API  (Elixir + Phoenix on :9089)
        |-- 54 controllers, 56 schemas, 67 migrations, ~151 routes
        |-- Agent lifecycle (heartbeat, sessions, budgets, governance)
        |-- Workflow engine (7 step types, DAG execution, cron scheduling)
        |-- Dynamic dispatch (content-based adapter routing)
        |-- 5-layer org hierarchy (Company → Division → Department → Team → Agent)
        |
        v
Desktop Command Center  (SvelteKit 2 + Tauri 2 on :5200)
        |-- 56 pages, 20 component groups, 48 stores
        |-- Dashboard (KPIs, active agents, budget burn)
        |-- Virtual Office (pixel-art 2D + 3D team visualization)
        |-- Agent Roster (hire from 330+ agents across 19 categories)
        |-- Sessions (live chat, tool inspection, session chains)
        |-- Workflow Designer (multi-step DAG workflows)
        |-- Cost Console (per-agent token spend, budget enforcement)
        |-- Library & Marketplace (agents, skills, templates, companies)
        |-- Reports & Analytics (6 report types, scheduled generation)
        |-- Governance (approval gates, audit trail, access control)
        |
        v
Connected Agents (Claude Code, OSA, Cursor, Codex, Gemini, Aider, Windsurf, OpenClaw)
```

### Stack

| Layer | Technology |
|-------|-----------|
| Backend | Elixir 1.15 + Phoenix 1.8.5 |
| Database | PostgreSQL (67 migrations, 56 schemas) |
| Frontend | SvelteKit 2 + Svelte 5 + Tauri 2 |
| Auth | Guardian + JWT + Bcrypt |
| Scheduler | Quantum |
| Real-time | Phoenix PubSub + SSE |
| Backend port | `:9089` |
| Desktop port | `:5200` |
| OSA port | `:8089` |

---

## Features

### Workspace Protocol

The Canopy workspace is a folder of plain markdown files. No proprietary server, no lock-in. The directory structure is the architecture:

```
L0  SYSTEM.md + company.yaml          Always loaded (~2K tokens)
L1  agents/ + skills/                 On-demand (~2K tokens per item)
L2  reference/ + workflows/ + spec/   Deep context (full content, via search)
L3  engine/                           Invisible (0 tokens, powers skills)
```

`SYSTEM.md` is the entry point: identity, boot sequence, core loop, skills list, agents list, routing table, and handoff protocol — approximately 120 lines that define the entire operating system.

`company.yaml` carries mission, budget, governance rules, org chart, and goal hierarchy with evidence gates.

### Progressive Disclosure

Every entity — agents, skills, teams, projects, tasks — exposes itself in three tiers. The agent requests only what it needs, when it needs it.

```
Tier 0 (Catalog)     Name + one-line description only. ~100 tokens per entity.
Tier 1 (Activation)  Full manifest body loaded on demand. ~2K tokens per entity.
Tier 2 (Full)        All referenced assets: scripts, linked docs, evidence schemas.
```

The catalog is always cheap. Full manifests cost only when actually used. This achieves 96% context reduction versus systems that load everything upfront.

### Agent Hiring

Browse and hire from a library of 330+ pre-built agents across 19 categories — or define your own in a markdown file. Agents are behavioral templates, not binaries.

Each agent file defines role, tools, coordination rules, escalation path, and heartbeat behavior. One-click hire from the Command Center or drop the file into `agents/`.

### Heartbeat Protocol

Agents wake on schedule, check for work, execute, and delegate autonomously. The heartbeat is a 9-step GenServer cycle with atomic checkout, governance gate checks, and session continuity:

```
Agent wakes (schedule, task assignment, or mention)
  -> Retrieves identity and role
  -> Checks governance gates (pending approvals block execution)
  -> Loads continuation context from previous session
  -> Resolves adapter (override → content router → agent default)
  -> Fetches assigned tasks (sorted by priority)
  -> Atomic checkout (prevents double-work)
  -> Executes via resolved adapter
  -> Comments on progress, delegates subtasks
  -> Compacts session (summary + handoff for next heartbeat)
  -> Sleeps until next heartbeat
```

### Session Persistence & Continuity

Agents resume context across heartbeats instead of starting cold:

- **Session chains** — linked sessions with `parent_session_id` and `sequence_number` tracking full execution history
- **Automatic compaction** — after each heartbeat, the Compactor extracts structured facts (tools used, errors, outputs, decisions) into a summary
- **Handoff generation** — markdown handoff document with pending items, key decisions, blockers, and continuation state
- **Cross-heartbeat injection** — next heartbeat loads the previous session's handoff as context preamble
- **Chain queries** — `GET /sessions/:id/chain` returns full session lineage with cumulative token usage
- **Manual compaction** — `POST /sessions/:id/compact` triggers on-demand summarization

### Multi-Agent Coordination

Tasks are the communication protocol. No agent-to-agent messaging required.

- **Delegation** — create a child task assigned to a report, with adapter-aware routing
- **Status** — modify task fields
- **Escalation** — traverse parent chain up to orchestrator
- **Atomic checkout** — only one agent works on a task at a time (409 = move on)

Task hierarchy: Initiatives → Projects → Milestones → Issues → Sub-issues. Every task traces back to a company goal.

### Dynamic Adapter Dispatch

One orchestrator dispatches work to different runtimes based on task content. The dispatch router uses a three-tier priority waterfall:

```
1. Task adapter_override   (explicit per-task)
2. Content-based routing   (label + regex matching)
3. Agent default adapter   (fallback)
```

Content patterns route automatically:

```
/delegate "Write the API spec"    → Claude Code (deep reasoning)
/delegate "Refactor 50 files"     → Codex (bulk code changes)
/delegate "Analyze screenshots"   → Gemini (multimodal)
/delegate "Run test suite"        → Bash (shell process)
/delegate "Check production"      → HTTP (webhook)
```

The delegation system creates subtasks with automatic adapter selection, finding idle agents that match the inferred adapter type. Preview endpoint available at `POST /dispatch/preview` for dry-run routing.

### Budget Enforcement

Three tiers — visibility, soft alert, hard ceiling:

| Threshold | Behavior |
|-----------|---------|
| Always | Dashboard shows spend per agent, task, project, goal |
| 80% | Soft alert — agent warned to focus on critical tasks only |
| 100% | Hard stop — auto-pause, approval required to resume |

Tracks tokens and dollars. Rollup at any level (agent, team, department, division, organization). Enforced at every execution boundary — scheduler, manual invoke, task checkout. ETS atomic counters for lock-free performance.

### Governance Gates

Approval enforcement integrated into the controller pipeline:

- **Spawn gate** — agents cannot be created without approval (configurable per workspace)
- **Delete gate** — agent termination requires authorization
- **Budget override gate** — exceeding limits requires explicit approval
- **Strategy gate** — proposals require board review before execution
- **Heartbeat blocking** — agents with pending approvals are blocked from execution
- **Auto-execution** — approved actions replay automatically via the Executor
- **Idempotent** — duplicate pending approvals are deduplicated

Governance is a Phoenix plug (`CanopyWeb.Plugs.Governance`) that halts with HTTP 202 when an action requires approval. The workspace's `governance` config determines which actions need approval and which roles are auto-approved.

```
POST /spawn  →  Governance plug  →  Gate.check(:spawn_agent)
                                      |
                         requires_approval?  →  yes  →  202 {pending_approval}
                                             →  no   →  :allowed (continue)
```

### Organizational Hierarchy

Five-layer structure with cascading budgets:

```
Organization (billing entity, governance config)
  └── Division (business unit, head agent, budget)
        └── Department (functional area, head agent, budget)
              └── Team (execution unit, manager agent, budget)
                    └── Agent (individual worker, budget)
```

Full CRUD at every level. `GET /hierarchy?organization_id=X` returns the complete tree assembled from flat queries. Team memberships tracked via join table with role assignment.

### Workflow Engine

DAG-based workflow execution with 7 step types:

| Step Type | Description |
|-----------|------------|
| `agent_task` | Assign work to a specific agent |
| `approval` | Block until human approves |
| `condition` | Branch based on previous step output |
| `transform` | Reshape data between steps |
| `webhook` | Call external HTTP endpoint |
| `delay` | Wait for specified duration |
| `parallel` | Execute multiple steps concurrently |

Workflows support:
- Topological sort for dependency resolution
- Retry with configurable backoff (constant, linear, exponential)
- Cron-based scheduled execution via `Canopy.Workflows.Scheduler`
- Step-level status tracking (pending → running → completed/failed/skipped)
- OTP supervision for fault tolerance

### Agent Commerce _(Planned — requires Stripe MPP integration)_

Agents will be able to buy things. Stripe's Machine Payments Protocol (MPP) lets agents transact autonomously — pay for APIs, buy compute, purchase services from other agent workspaces.

Canopy's budget enforcement will wrap around MPP:

- **Under threshold** — agent pays autonomously, logged to budget
- **Over threshold** — payment queued for human approval
- **Over budget** — hard stop, no payment authorized

---

## Desktop Command Center

56 pages organized into functional clusters:

| Cluster | Pages |
|---------|-------|
| **Daily** | Dashboard, Inbox, Chat, Virtual Office |
| **Work** | Issues, Projects, Goals, Work Products, Workflows |
| **Agents** | Agent Roster, Agent Detail, Spawn, Sessions, Schedules |
| **Data** | Memory, Documents, Datasets, Signals, Templates |
| **Observe** | Activity, Logs, Analytics, Costs, Reports, Alerts, Audit |
| **Automate** | Skills, Integrations, Webhooks, Plugins, Gateways |
| **Library** | Agent Marketplace, Skills, Companies, Teams (with detail pages) |
| **System** | Organizations, Hierarchy, Divisions, Departments, Teams, Users, Access, Config, Secrets, Environment |

### Virtual Office

Pixel-art 2D grid view and optional 3D scene (Three.js via Threlte) showing agents at desks. Agents glow when active, bob when working, and display current task in a speech bubble. Click to inspect or intervene.

### Mock-First Development

57 mock API modules provide complete frontend functionality without a backend connection. Every API endpoint has a corresponding mock handler with realistic data, enabling offline development and demo mode.

---

## Workspace Protocol

### File Structure

A complete workspace — using the B2B sales engine as example:

```
sales-engine/
|
|  L0 — ALWAYS LOADED
|
+-- SYSTEM.md                 Entry point: identity, boot sequence, core loop,
|                             skills list, agents list, routing table
|
+-- company.yaml              Mission, budget ($5K/mo), governance rules,
|                             org chart, goal hierarchy with evidence gates
|
|  L1 — LOADED ON DEMAND
|
+-- agents/
|   +-- director.md           Pipeline review, deal strategy, forecasting
|   +-- prospector.md         Lead generation, ICP matching, outbound sequences
|   +-- closer.md             Discovery calls, demos, negotiation, close
|   +-- researcher.md         Market intel, competitive analysis, account research
|   +-- copywriter.md         Email sequences, proposals, case studies
|
+-- skills/
|   +-- prospect/SKILL.md    /prospect — find and qualify leads
|   +-- pipeline/SKILL.md    /pipeline — view pipeline status, forecasting
|   +-- qualify/SKILL.md     /qualify — run MEDDPICC qualification
|   +-- close-plan/SKILL.md  /close-plan — build deal close strategy
|   +-- battlecard/SKILL.md  /battlecard — competitive intel for a deal
|
|  L2 — DEEP CONTEXT
|
+-- reference/
|   +-- icp.md                Ideal customer profile, scoring rubric
|   +-- meddpicc.md           Full qualification methodology
|   +-- objections.md         20+ objections with response scripts
|   +-- sequences.md          Email templates with A/B variants
|
+-- workflows/
|   +-- deal-cycle.md         7 phases: Research -> Outreach -> Discovery ->
|                             Demo -> Proposal -> Negotiate -> Close
|
+-- handoffs/
|   +-- standard.md           Task clarity, constraints, expected genre
|   +-- escalation.md         When to escalate, who to, with what evidence
|
+-- spec/
|   +-- PROCEDURES.md         Action bindings with typed parameters
|   +-- WORKFLOW.md           FSM: lead states, deal states, triggers
|   +-- contracts/
|       +-- workspace.spec.md Self-validation and drift detection
|
+-- teams/
|   +-- outbound/TEAM.md      Members, shared budget, coordination rules
|
+-- projects/
|   +-- q2-pipeline/PROJECT.md Goals, milestones, budget envelope, assigned teams
|
+-- tasks/
|   +-- qualify-lead/TASK.md  Schedule, evidence gates, default assignee
|
|  L3 — ENGINE (invisible to agent, 0 tokens)
|
+-- engine/
|   +-- (CRM integration, email API, SQLite pipeline DB, lead scoring model)
|      Pluggable: SQLite FTS5, sqlite-vec, Qdrant, Ollama, OpenAI, Neo4j
|
|  PROJECT LAYER — What agents BUILD
|
+-- output/
|   +-- proposals/
|   +-- analyses/
|   +-- reports/
|   +-- sequences/
|
+-- data/
|   +-- leads.csv
|   +-- pipeline.json
|   +-- call-notes/
|
+-- .canopy/                  Runtime state (gitignored)
    +-- tasks/
    +-- sessions/
    +-- observations/
```

### Manifest Types

**`TEAM.md`** — Defines an org subtree. Teams group agents, own a shared budget slice, and declare their coordination protocol.

**`PROJECT.md`** — Defines planned work with milestones, budget allocation, and resource assignments. Carries explicit evidence gates.

**`TASK.md`** — Portable, reusable task definition. Assigned to agents, tracked through the task hierarchy.

---

## Agent Library

330+ pre-built agents across 19 categories:

| Category | Examples |
|----------|---------|
| Engineering | backend, frontend, devops, security, performance, database |
| Sales | director, prospector, closer, researcher, copywriter |
| Marketing | strategist, content writer, SEO, growth, analyst |
| Operations | project manager, coordinator, HR, finance |
| Research | analyst, scientist, intelligence, competitive |
| Design | UI/UX, brand, product |
| Legal | contract review, compliance, IP |
| Finance | CFO, controller, FP&A |
| Customer Success | CSM, support, onboarding |
| Product | PM, roadmap, discovery |
| Executive | CEO, CTO, CPO, CMO |
| Infrastructure | SRE, platform, cloud |
| AI/ML | data scientist, model trainer, ML engineer |

Browse the library in the Command Center or drop any agent file into your `agents/` folder.

---

## Adapters

Canopy dispatches work to any connected runtime. Eleven adapters — five fully functional, six in beta:

| Adapter | Status | Install |
|---------|--------|---------|
| **OSA** | Functional | `curl -fsSL https://raw.githubusercontent.com/Miosa-osa/OSA/main/install.sh \| bash` |
| **Claude Code** | Functional | `npm install -g @anthropic-ai/claude-code` |
| **Codex** | Functional | `npm install -g @openai/codex` |
| **Bash / HTTP** | Functional | Built-in |
| **Cursor** | Beta | [cursor.sh](https://cursor.sh) |
| **Gemini** | Beta | [ai.google.dev](https://ai.google.dev) |
| **OpenClaw** | Beta | `npm install -g openclaw` |
| **Aider** | Beta | `pip install aider-chat` |
| **JidoClaw** | Beta | `curl -fsSL https://raw.githubusercontent.com/robertohluna/jido_claw/main/install.sh \| bash` |
| **Windsurf** | Beta | [codeium.com/windsurf](https://codeium.com/windsurf) |

The Command Center auto-detects installed adapters and provides one-click setup wizards. Provider credentials are stored in the OS keychain via Tauri's secure store.

All adapters implement the `Canopy.Adapter` behaviour: `execute/2`, `stream/2`, `health/1`, `capabilities/0`.

---

## Pre-Built Workspaces

| Workspace | Description |
|-----------|-------------|
| `sales-engine` | B2B pipeline: prospecting, qualification, demos, close |
| `dev-shop` | Software agency: planning, coding, review, deployment |
| `content-factory` | Content production: strategy, writing, editing, publishing |
| `cognitive-os` | Personal second brain: capture, process, connect, retrieve |
| `custom` | Blank slate with full scaffolding |

---

## Backend API

### Scope

| Metric | Count |
|--------|-------|
| Controllers | 54 |
| Schemas | 56 |
| Migrations | 67 |
| Routes | ~151 |
| Adapters | 11 |

### Key Subsystems

| Module | Purpose |
|--------|---------|
| `Canopy.Heartbeat` | 9-step agent execution cycle with Quantum scheduling |
| `Canopy.BudgetEnforcer` | ETS atomic counters, 5-level cascade, hard stop enforcement |
| `Canopy.Governance.Gate` | Plug-based approval enforcement on spawn/delete/budget/strategy |
| `Canopy.Governance.Executor` | Replays approved actions (spawn, delete, budget override) |
| `Canopy.Dispatch.Router` | Content-based adapter routing with label + regex matching |
| `Canopy.Dispatch.Delegation` | Subtask creation with adapter-aware agent selection |
| `Canopy.Sessions.Compactor` | Session summarization, handoff generation, context injection |
| `Canopy.Sessions.Chain` | Linked session chains with cumulative token tracking |
| `Canopy.Workflows.Engine` | DAG workflow execution with topological sort and retry |
| `Canopy.Workflows.Scheduler` | Cron-based workflow triggering |
| `Canopy.Notifications.Dispatcher` | Multi-channel notification creation and broadcasting |
| `Canopy.EventBus` | Phoenix PubSub topic management for real-time updates |
| `Canopy.IssueDispatcher` | Task assignment with priority queue and team routing |

---

## Development

### Prerequisites

- [just](https://github.com/casey/just) (command runner — `brew install just`)
- Elixir 1.15+
- Node.js 20+
- PostgreSQL 15+
- Rust (for Tauri)

### Commands

This project uses `just` as its command runner. Run `just --list` for the full list.

```bash
just setup              # Install all dependencies
just dev                # Start backend + desktop in development mode
just stop               # Stop all running services
just status             # Show what's running
just backend            # Start Phoenix backend only (:9089)
just desktop            # Start SvelteKit desktop only (:5200)
just logs backend       # Tail backend logs
just restart-backend    # Restart backend without touching desktop
just test               # Run full test suite
just lint               # Run Elixir + TypeScript linters
just format             # Auto-format all code
just db-migrate         # Run pending migrations
just db-reset           # Drop, create, migrate, and seed the database
just build              # Production Tauri app bundle
just doctor             # Check prerequisites and ports
```

### Environment

The backend reads from `.env` in the project root. Required variables:

```bash
DATABASE_URL=postgres://localhost/canopy_dev
SECRET_KEY_BASE=...         # mix phx.gen.secret
GUARDIAN_SECRET_KEY=...     # mix guardian.gen.secret
```

Optional variables for adapter credentials live in `.env.local` and are never committed.

### Ports

| Service | Port |
|---------|------|
| Phoenix backend | `:9089` |
| SvelteKit desktop | `:5200` |
| OSA integration | `:8089` |

### Running Tests

```bash
just test-backend            # Backend tests
just test-desktop            # Frontend tests
just test                    # Both
```

---

## Theoretical Foundation

Canopy implements the **Optimal System** architecture from *Signal Theory: The Architecture of Optimal Intent Encoding* (MIOSA Research, 2026). The protocol's directory structure, agent format, progressive disclosure, and governance model directly implement the paper's 7-layer system:

1. **Network** — `company.yaml` and `reportsTo` define who connects to whom
2. **Signal** — `S=(M,G,T,F,W)` encodes intent across 5 dimensions
3. **Composition** — Agent body sections and skill steps define micro-structure
4. **Interface** — Progressive disclosure (L0/L1/L2) surfaces the right context
5. **Data** — Markdown files are the storage substrate for organizational intent
6. **Feedback** — Heartbeat cycles and quality gates close every loop
7. **Governance** — `SYSTEM.md` encodes Beer's Viable System Model recursively

Every design decision traces to one of four governing principles: **Shannon** (channel capacity), **Ashby** (requisite variety), **Beer** (viable structure), **Wiener** (feedback closure).

---

## Ecosystem

```
Canopy (protocol)   ->  Any agent reads it. Free. MIT license.
Command Center      ->  Native desktop app. Free. Open source.
MIOSA (platform)    ->  Managed VMs, marketplace, enterprise. Paid.
```

Canopy is the open-source foundation. [MIOSA](https://miosa.ai) provides managed infrastructure, a marketplace for buying and selling agent workspaces, and enterprise governance tools built on top of the same protocol.

---

## Repository

[https://github.com/Miosa-osa/canopy](https://github.com/Miosa-osa/canopy)

Architecture reference docs live in `architecture/` — see the [Architecture README](architecture/README.md) for the full index.

Key architecture docs:

- [Heartbeat](architecture/heartbeat.md) — 9-step agent execution cycle
- [Adapters](architecture/adapters.md) — runtime adapter interface
- [Budgets](architecture/budgets.md) — budget enforcement model
- [Governance](architecture/governance.md) — approval gate system
- [Tasks](architecture/tasks.md) — task coordination protocol
- [Sessions](architecture/sessions.md) — session persistence and compaction
- [Workflows](architecture/workflows.md) — DAG workflow engine

---

## Documentation

Detailed documentation lives in the `docs/` directory:

| Document | Description |
|----------|-------------|
| [Development Guide](docs/DEVELOPMENT.md) | macOS setup, install instructions, architecture diagram, project layout |
| [Getting Started](docs/getting-started.md) | End-user guide: from zero to a running AI Operation |
| [Module Specs](docs/MODULE_SPECS.md) | Module specification reference |
| [Known Issues](docs/KNOWN-ISSUES.md) | Known issues and workarounds |
| [Contributing](docs/CONTRIBUTING.md) | How to contribute to Canopy |

### Guides

| Guide | Description |
|-------|-------------|
| [Agent Design](docs/guides/agent-design.md) | How to design effective agents |
| [Skill Design](docs/guides/skill-design.md) | Building reusable skills |
| [Workflow Design](docs/guides/workflow-design.md) | Creating DAG workflows |
| [Company Setup](docs/guides/company-setup.md) | Configuring company.yaml |
| [Data Architecture](docs/guides/data-architecture.md) | Data layer design patterns |
| [Signal Theory Quickstart](docs/guides/signal-theory-quickstart.md) | Introduction to Signal Theory |
| [Writing Skills](docs/guides/writing-skills.md) | Practical skill authoring |
| [Proactive Agents](docs/guides/proactive-agents.md) | Proactive agent patterns |

### Strategy

Strategy and operational planning docs are in `docs/strategy/`:

- [Executive Brief](docs/strategy/executive-brief.md)
- [Nexus Strategy](docs/strategy/nexus-strategy.md)
- [Quickstart](docs/strategy/quickstart.md)
- Playbooks, runbooks, and coordination docs

---

## Contributing

1. Fork the repo and create a branch from `main`
2. Run `just setup && just test` to verify your environment
3. Make changes with tests
4. Submit a pull request with a clear description of what changed and why

Code style is enforced by `just lint` and `just format`. PRs that don't pass CI will not be merged.

See [Contributing Guide](docs/CONTRIBUTING.md) for full details.

---

## License

MIT — see [LICENSE](LICENSE).
