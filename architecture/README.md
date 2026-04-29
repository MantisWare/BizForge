# Bizforge owns the architecture layer

> This is the control plane spec for Bizforge. Heartbeat, adapters, governance, budgets,
> task routing, sessions, workspaces, marketplace, Signal Theory — all spelled out so
> nobody has to guess how the system actually runs.
>
> Specs, not implementation. OSA, Claude Code, Cursor, OpenClaw — any runtime can wire
> these up. Single source of truth: Bizforge’s control plane model, Signal Theory on top.

---

## Table of Contents

| # | File | What It Defines |
|---|------|----------------|
| 1 | [heartbeat.md](heartbeat.md) | Wake agents, run work, lock queues, kill orphans — the execution pulse |
| 2 | [adapters.md](adapters.md) | Invoke, status, cancel. Who implements what. Context in, session codec out. |
| 3 | [governance.md](governance.md) | Humans stay in charge. Board powers, gates, escalation, audit trail. |
| 4 | [budgets.md](budgets.md) | Money stops runaway agents. Hierarchy, tiers, billing codes, delegation. |
| 5 | [tasks.md](tasks.md) | Work graph. Checkouts, lifecycle, agent-to-agent comms, inbox rules. |
| 6 | [sessions.md](sessions.md) | State survives restarts. Serialize, compact, scope by task, migrate clean. |
| 7 | [workspaces.md](workspaces.md) | Where code actually lands. Resolution order, isolation, teardown. |
| 8 | [marketplace.md](marketplace.md) | Ship the bundle. Export modes, import, version tags, pricing. |
| 9 | [signal-integration.md](signal-integration.md) | Signal Theory on the wire. S/N gates, genre fit, tiers, graph, learning loop. |
| 10 | [basement.md](basement.md) | Primitives underneath everything. Resource types, memory, skills, taxonomy. |
| 11 | [tiered-loading.md](tiered-loading.md) | L0/L1/L2 — token caps, cache, triggers, relevance so context doesn’t explode. |
| 12 | [proactive-agents.md](proactive-agents.md) | Agents that fire themselves — heartbeat, events, conditions, schedules. |
| 13 | [memory-architecture.md](memory-architecture.md) | Four layers: working, episodic, semantic, procedural. |
| 14 | [spec-layer.md](spec-layer.md) | Markdown that runs. PROCEDURES, WORKFLOW FSMs, MODULES DAGs. |
| 15 | [pipelines.md](pipelines.md) | Stream it. Producers, filters, consumers, live composition. |
| 16 | [verification.md](verification.md) | Workspaces prove they match spec. Drift detection, strength levels, ADRs. |
| 17 | [processing-pipeline.md](processing-pipeline.md) | 6R knowledge run — Record through Rethink, fresh context each hop. |
| 18 | [three-space-model.md](three-space-model.md) | Split the world: self vs growing graph vs throwaway ops shell. |
| 19 | [team-coordination.md](team-coordination.md) | Many agents, one mission. Leader/worker, filesystem inbox, git worktrees. |
| 20 | [optimal-system-mapping.md](optimal-system-mapping.md) | Bizforge mapped clean onto Signal Theory’s seven-layer Optimal System. |
| 21 | [context-mesh.md](context-mesh.md) | Per-team GenServers hold overflow context — three pull modes, four staleness factors, token budgets. |
| 22 | [decision-graph.md](decision-graph.md) | Decisions as a DAG — five node types, ten edge types, confidence cascades, pivots, merges, narratives. |
| 23 | [self-healing.md](self-healing.md) | Stuff breaks; the stack fixes it. Eight error classes, four severities, cheap heal agents, retries, escalation. |
| 24 | [conversations.md](conversations.md) | Multi-agent talk with structure — four conversation shapes, three turn strategies, debate → convergence, Weaver, personas. |
| 25 | [peer-protocol.md](peer-protocol.md) | Agent ↔ agent without drama. Handoffs, review gates, negotiation, cross-team find, region locks. |
| 26 | [speculative-execution.md](speculative-execution.md) | Bet on the next task. Track assumptions, sandbox runs, promote or trash atomically. |

---

## Stack this mentally before you touch prod

```
                    ┌─────────────┐
                    │  GOVERNANCE │  Human oversight layer
                    │  (board)    │  Approval gates, escalation, audit
                    └──────┬──────┘
                           │ controls
                    ┌──────▼──────┐
                    │   BUDGETS   │  Cost enforcement
                    │  (company → │  Per agent, task, project
                    │   agent)    │
                    └──────┬──────┘
                           │ gates
                    ┌──────▼──────┐
                    │  HEARTBEAT  │  Wake → Execute → Persist cycle
                    │  (protocol) │  The core execution loop
                    └──┬───┬───┬──┘
                       │   │   │
            ┌──────────┘   │   └──────────┐
            ▼              ▼              ▼
     ┌───────────┐  ┌───────────┐  ┌───────────┐
     │  ADAPTERS │  │  SESSIONS │  │ WORKSPACES│
     │ (runtime) │  │ (state)   │  │ (where)   │
     └───────────┘  └───────────┘  └───────────┘
            │              │              │
            └──────┬───────┘              │
                   ▼                      │
            ┌───────────┐                 │
            │   TASKS   │◄────────────────┘
            │ (work +   │  Tasks drive workspace selection
            │  comms)   │  and session scoping
            └───────────┘
                   │
            ┌──────▼──────┐
            │   SIGNAL    │  Quality layer over all outputs
            │ INTEGRATION │  S/N gates, genre alignment,
            │             │  knowledge graph, learning
            └─────────────┘
                   │
            ┌──────▼──────┐
            │ MARKETPLACE │  Distribution of the whole stack
            │ (bundles)   │  Export, version, price, deploy
            └─────────────┘

   KNOWLEDGE LAYER                    COORDINATION LAYER

   ┌─────────────┐                   ┌───────────────┐
   │  PROCESSING │  6R pipeline:     │     TEAM      │  Leader-worker,
   │  PIPELINE   │  Record→Reduce→   │ COORDINATION  │  filesystem inbox,
   │  (6R)       │  Reflect→Reweave  │               │  git worktree
   └──────┬──────┘  →Verify→Rethink  └───────────────┘  isolation
          │
   ┌──────▼──────┐
   │ THREE-SPACE │  self/ = identity
   │    MODEL    │  knowledge/ = growing graph
   │             │  ops/ = ephemeral scaffolding
   └─────────────┘
```

Entry 20 — `optimal-system-mapping.md` — ties every spec in this index to the Optimal System’s seven layers. One map. Bizforge docs ↔ Signal Theory model. Done.

## Six subsystems that keep long jobs from melting down

```
   RUNTIME LAYER

   ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
   │  CONTEXT MESH   │   │ DECISION GRAPH  │   │  SELF-HEALING   │
   │  Per-team keeper│   │  DAG: decisions,│   │  Error classify,│
   │  3 retrieval    │   │  goals, pivots  │   │  ephemeral fix  │
   │  modes, 4-factor│   │  confidence     │   │  agents, escal. │
   │  staleness score│   │  cascade        │   │                 │
   └────────┬────────┘   └────────┬────────┘   └────────┬────────┘
            │                     │                      │
            │  feeds context       │  tracks decisions    │  repairs failures
            │                     │                      │
   ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
   │  CONVERSATIONS  │   │  PEER PROTOCOL  │   │  SPECULATIVE    │
   │  Brainstorm,    │   │  Handoffs, peer │   │  EXECUTION      │
   │  design_review, │   │  review gates,  │   │  Predict, isolate│
   │  red_team,      │   │  negotiation,   │   │  promote/discard│
   │  user_panel     │   │  file locking   │   │                 │
   └─────────────────┘   └─────────────────┘   └─────────────────┘

   ↕ all 6 subsystems sit above HEARTBEAT (execution) and below GOVERNANCE (oversight)
```

## Four layers of org spec — know where your agent lives

These protocols nail the hierarchy. Every agent file hangs off this tree.

| Layer | Spec | Instance Files | Count |
|-------|------|----------------|-------|
| Division | `protocol/division-format.md` | `library/divisions/{id}.md` | 5 |
| Department | `protocol/department-format.md` | `library/departments/{division-id}/{id}.md` | 20 |
| Team | `protocol/team-format.md` | `library/teams/{id}.md` | 43 |
| Agent | `protocol/agent-format.md` | `library/agents/{division}/{department}/{team}/{id}.md` | 330+ |

Shape of the tree lives in `docs/hierarchy.md`.

## Three pillars of source material

1. **Control Plane** — Company orchestration, agents, heartbeat, tasks, budgets, adapters, governance.
2. **Organizational Hierarchy** — Divisions, departments, teams, agents, reporting chains, budget rollup (330+ agents in the library).
3. **Signal Theory** — Quality gates, tiered loading, knowledge graph, learning loop.

`protocol/operations-spec.md` bundles the big picture. Everything under `architecture/` slices that into subsystem specs you can implement without hand-waving.

## operations-spec vs architecture/

`operations-spec.md` says WHAT ships in an Operation (portable bundle).
`architecture/` says HOW the plane flies at runtime.

| operations-spec.md | architecture/ |
|--------------------|--------------|
| Company YAML schema | Budget enforcement when the meter runs |
| Agent frontmatter format | Wake, run, persist — the agent loop |
| Workflow YAML schema | Task routing and tracking |
| Session state schema | Session continuity across runs |
| Adapter capability matrix | Full adapter contract |
| Governance rules | Board powers, gates, escalation |
| Marketplace bundle format | Export, import, pricing |

---

*Architecture Layer v2.0 — Bizforge control plane specifications*
