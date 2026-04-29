# Operations — AI Businesses in a Folder

> An Operation is a self-contained AI business. Agents with defined roles.
> Skills they execute. Reference knowledge they pull from. Workflows that govern
> process. One `SYSTEM.md` that ties it all together. Drop it into any agent runtime
> and it runs. Period.

---

## What Is an Operation?

A directory. Everything an AI agent (or a team of them) needs to run a business function autonomously. Not a chatbot. Not a prompt template. A complete operational unit:

- **Identity**: Who the system is and what it does (SYSTEM.md)
- **Agents**: Specialists with defined roles, skills, and communication styles
- **Skills**: Executable commands the agents can invoke
- **Reference**: Domain knowledge loaded on demand
- **Workflows**: Multi-phase processes with handoff gates between agents
- **Handoffs**: Structured transition protocols between agents/phases
- **Spec** (optional): Executable FSMs, typed procedures, and module topology

```
my-operation/
├── SYSTEM.md           ← Entry point. Any agent reads this first.
├── company.yaml        ← Org chart, budget, mission
├── agents/             ← Specialist definitions (markdown + YAML frontmatter)
├── skills/             ← Slash commands the agents can run
├── reference/          ← Domain knowledge (loaded on-demand, not at boot)
├── workflows/          ← Multi-phase process definitions
├── handoffs/           ← Structured transition protocols
└── spec/               ← (Optional) FSMs, procedures, topology
```

The key insight: **SYSTEM.md is the only file the runtime needs to discover.** Everything else is referenced from there. Agent reads SYSTEM.md, discovers skills, finds agents, loads reference, starts operating.

---

## The 5-Layer Stack

Operations live at Layer 3. Each layer is independently swappable.

```
┌─────────────────────────────────────────────────┐
│  Layer 5: COMPANY ORCHESTRATION                 │
│  Org charts, budgets, goals, agent hiring,      │
│  cross-team governance, board oversight          │
│  (company.yaml + governance rules)               │
├─────────────────────────────────────────────────┤
│  Layer 4: RUNTIME                               │
│  The engine that reads SYSTEM.md and executes.  │
│  OSA, Claude Code, Cursor, any agent framework. │
├─────────────────────────────────────────────────┤
│  Layer 3: OPERATIONS          ◄── YOU ARE HERE  │
│  Complete business functions in a folder.        │
│  Sales engines, dev shops, content factories.    │
├─────────────────────────────────────────────────┤
│  Layer 2: AGENT LIBRARIES                       │
│  Reusable personality templates. Markdown files  │
│  that define agent identity, rules, style.       │
│  Imported into Operations as agents/.            │
├─────────────────────────────────────────────────┤
│  Layer 1: COMPUTE                               │
│  Infrastructure. VMs, containers, sandboxes.     │
│  Where the runtime physically executes.          │
└─────────────────────────────────────────────────┘
```

### Layer 2: Agent Libraries

Character sheets for AI agents. Each template defines identity, core rules, communication style, and domain expertise — stored as markdown.

An Operation imports what it needs into `agents/`. Sales operation pulls a prospector, closer, researcher. Dev shop pulls a tech lead, frontend dev, QA engineer. Same library, different compositions.

Agent libraries give you:
- **Consistency**: The same "closer" personality works across different sales operations
- **Versioning**: Update a template in the library, propagate everywhere
- **Marketplace**: Share and sell agent templates independently of full operations
- **Specialization**: Deep domain experts that carry knowledge across deployments

### Layer 5: Company Orchestration

The human layer. Org charts defining reporting hierarchies. Budgets constraining spend per agent and per project. Goals cascading from company mission to individual agent objectives. Governance rules requiring human approval for high-stakes actions.

This layer answers the questions Operations alone can't:
- "How much can this agent spend before it needs approval?"
- "Who does this agent escalate to when it's stuck?"
- "What's the company-wide priority when two operations compete for resources?"
- "Which actions require human sign-off before execution?"

Defined in `company.yaml` at the operation level and in governance policies at the platform level. Optional for simple operations. Essential for multi-agent, multi-team deployments.

---

## Connecting to a Runtime

An Operation is runtime-agnostic. Same directory, any agent that reads markdown and executes shell commands. Here's how:

### With OSA (Native Runtime)

```bash
osa connect /path/to/sales-engine
# OSA reads SYSTEM.md → discovers skills/ → loads agents/ → ready to operate
# Skills become executable commands in the agent loop
# Agents become dispatchable specialists
# Reference files are loaded on-demand via tiered loading
# company.yaml configures budgets, org chart, governance
```

OSA is the native runtime. It understands the full spec: heartbeat protocol, session persistence, workspace management, budget enforcement, governance gates, and the spec layer (FSMs, procedures, topology). Everything just works.

### With Claude Code

```bash
# 1. Copy SYSTEM.md content into your project's CLAUDE.md
cp /path/to/sales-engine/SYSTEM.md ./CLAUDE.md

# 2. Skills become slash commands
#    /prospect <company>  → runs the prospect skill
#    /pipeline            → shows pipeline status
#    /qualify <deal>      → MEDDPICC scoring

# 3. Agents become subagent dispatches
#    "Activate the prospector agent" → Claude Code reads agents/prospector.md

# 4. Reference files loaded on-demand
#    Claude Code reads reference/icp.md when it needs ICP scoring criteria

# 5. Spec layer (if present) becomes behavioral constraints
#    FSM states → Claude Code follows the declared state machine
#    Procedures → Claude Code invokes the declared implementations
```

Claude Code supports most of the format natively. Main difference: session persistence (Claude Code manages its own context window) and governance (approval gates are manual, not automated).

### With Cursor / Windsurf

```bash
# 1. Copy SYSTEM.md into .cursorrules (Cursor) or rules file (Windsurf)
cp /path/to/sales-engine/SYSTEM.md ./.cursorrules

# 2. Skills become @commands or inline instructions
#    The agent reads the skill definitions and executes them when invoked

# 3. Reference files loaded via @file mentions
#    @reference/icp.md → loads the ICP framework into context

# 4. Agents are described in SYSTEM.md
#    The IDE agent reads agent definitions and adopts the persona when needed
```

### With Any Agent Framework

```bash
# Any agent that can:
#   1. Read a markdown file         → Read SYSTEM.md for instructions
#   2. List a directory             → Discover skills/, agents/, reference/
#   3. Execute shell commands       → Run skill implementations
#   4. Read files on-demand         → Load reference when needed
# ...can operate any workspace.

# The minimum viable integration:
agent.load_instructions("SYSTEM.md")
agent.discover_skills("skills/")
agent.discover_agents("agents/")
agent.set_reference_path("reference/")
agent.run()
```

The format is intentionally simple. SYSTEM.md is plain markdown. Skills are markdown files describing shell commands. Agents are markdown with YAML frontmatter. Reference files are markdown. No proprietary format. No SDK required. If it reads files, it runs Bizforge.

---

## Example Operations

### [Sales Engine](./sales-engine/)

B2B SaaS sales. Full pipeline from prospect identification to closed-won deals. Five specialist agents (VP Sales, SDR, AE, Research Analyst, Sales Copywriter) executing a 7-phase deal cycle governed by MEDDPICC qualification, ICP scoring, and multi-threaded account strategy. Skills: `/prospect`, `/pipeline`, `/qualify`, `/close-plan`, `/battlecard`. Every deal scored at every phase gate. Structured handoffs between agents.

### [Dev Shop](./dev-shop/)

Software development operation delivering production-grade software through a disciplined pipeline. Six specialist agents (Tech Lead, Solutions Architect, Frontend Dev, Backend Dev, QA Engineer, DevOps Engineer) running a 7-phase feature cycle with a parallel fast-track bug fix pipeline. QA defaults to NEEDS WORK — nothing ships without QA approval. Skills: `/build`, `/test`, `/review`, `/deploy`, `/spec`, `/debug`. Dev-QA loop enforces quality with retry limits and tech lead escalation.

### [Content Factory](./content-factory/)

Content production turning ideas into published, optimized, multi-platform content. Five specialist agents (Editor-in-Chief, Writer, Social Media Manager, SEO Specialist, Visual Designer) running a 7-phase content cycle from ideation through performance analysis. Every piece is audience-targeted, SEO-optimized, and repurposed across platforms. Skills: `/ideate`, `/write`, `/repurpose`, `/schedule`, `/analyze`. Brand voice enforced at every editorial gate.

### [Cognitive OS](./cognitive-os/)

Personal cognitive operating system — an externalized decision tree library stored as markdown files, searched by an Elixir engine, processed by an AI agent. Four specialist agents (Knowledge Guide, Signal Processor, Context Assembler, Health Monitor) managing 12 numbered knowledge nodes with tiered loading (L0/L1/L2) and a daily rhythm layer (boot, operate, build, break, shutdown). Skills: `/ingest`, `/search`, `/assemble`, `/health`, `/reweave`, `/simulate`, and 8 more. The most complex example — demonstrates how the Workspace Protocol models an entire personal knowledge management system.

### [Agency Workflows](./agency-workflows/)

Multi-agent workflow examples showing how Operations compose agents for real-world tasks: landing page generation, startup MVP planning, book chapter writing, and workflows with persistent memory. Demonstrates the breadth of agent collaboration patterns — linear handoffs, parallel fan-out, memory-augmented iteration.

---

## The Spec Layer (Optional Power)

Operations that need deterministic behavior beyond agent judgment add a `spec/` directory with three file types:

| File | What It Declares | When You Need It |
|------|-----------------|-----------------|
| `PROCEDURES.md` | Typed action & query bindings (Say, Execute, Analyze, Score) | When you want a capability registry with caching, sandboxing, and hot-swap |
| `WORKFLOW.md` | Finite state machines with triggers, pipelines, and branching | When your process has mandatory ordering and phase gates |
| `MODULES.md` | DAG topology with composition, event bus, and circuit breakers | When you need fault-tolerant module wiring and backpressure |

The spec layer is optional. Most Operations work fine with just agents, skills, and reference files. Add spec files when you need:
- FSM workflows that MUST follow a specific path (sales pipeline, deployment, compliance)
- Typed procedure bindings with runtime hot-swap (switch email providers without changing workflows)
- Module composition with circuit breakers (fault tolerance for external integrations)
- Event-driven pipelines with filtering and routing (webhook intake, scheduled processing)

See `architecture/spec-layer.md` for the full specification and format reference.
See `architecture/pipelines.md` for event stream processing patterns.

---

## Creating a New Operation

```bash
# From this repository:
# 1. Copy an example as a starting point
cp -r operations/sales-engine my-new-operation

# 2. Edit SYSTEM.md to define your operation's identity and behavior
# 3. Customize agents/ for your domain's specialists
# 4. Write skills/ for the commands your agents need
# 5. Add reference/ files for domain knowledge
# 6. (Optional) Add spec/ for deterministic workflows

# Or use the scaffolding skill:
# /create-operation my-new-operation --agents engineering,sales --workflow sprint
```

Only hard requirement: SYSTEM.md. Everything else is discovered from there. Start minimal, add layers as your operation grows.

---

*Operations v1.0 — The portable AI business unit format for Bizforge*
