# Pick a tier. Copy it. Ship.

> Workspace starters scaled to how big your setup actually is. Grab the folder that fits. Wire `SYSTEM.md`. Done.

---

## Four tiers — stop over-building

| Tier | Files | Use Case | Time to Customize |
|------|-------|----------|-------------------|
| **micro** | ~5 | Single-purpose agent (email responder, code reviewer, content writer) | 15 minutes |
| **small** | ~15 | Small team or product (2-3 agents, focused domain) | 1 hour |
| **full** | ~30 | Multi-team operation (4+ agents, workflows, governance) | 2-3 hours |
| **enterprise** | ~40+ | Large organization (teams, budgets, governance, compliance) | Half day |

Bizforge’s agent library clocks in at **330+** definitions when you want to pull more firepower than these starters give you.

---

## Run this playbook

### 1. Grab the tier

```bash
# Start with the tier that matches your scale
cp -r templates/micro/ my-operation/

# Or for a full setup
cp -r templates/full/ my-operation/
```

### 2. Own `SYSTEM.md`

Every template ships a `SYSTEM.md` full of placeholders. Swap them:

- `{{OPERATION_NAME}}` → your operation name
- `{{MISSION}}` → one line that states the mission
- `{{DOMAIN}}` → engineering, sales, consulting, whatever
- Agent names and roles → mirror your real team

### 3. Tune the agents

Each agent file runs YAML frontmatter plus markdown body — spec lives in `protocol/agent-format.md`. Dial in:

- Identity and voice
- Non-negotiable rules for your domain
- Process that matches how you actually work
- Deliverable templates your people really use

### 4. Wire the skills

Skills are slash commands your agents hit. Every skill packs a `SKILL.md` with usage, steps, examples. Point them at your repos, your toolchain, your deploy targets.

### 5. Prove it

```bash
/validate my-operation/
```

That run checks `SYSTEM.md` shape, YAML frontmatter, agent cross-refs, Signal encoding, workflow phase pointers. Green means you didn’t phone it in.

---

## What each tier gives you

### micro (~5 files)

```
micro/
├── SYSTEM.md              # Minimal system prompt
├── agents/
│   └── worker.md          # Single agent definition
└── skills/
    └── do/
        └── SKILL.md       # One skill: the agent's primary action
```

One job. One agent. Email triage, code review, meeting notes — whatever. No governance theater. No workflow YAML. Just execution.

### small (~15 files)

```
small/
├── SYSTEM.md              # System prompt with routing
├── company.yaml           # Basic company config
├── agents/
│   ├── lead.md            # Lead agent (orchestrator)
│   └── specialist.md      # Specialist agent
├── skills/
│   ├── primary/
│   │   └── SKILL.md       # Main workflow skill
│   ├── search/
│   │   └── SKILL.md       # Knowledge search
│   └── report/
│       └── SKILL.md       # Reporting skill
├── reference/
│   ├── domain.md          # Domain knowledge
│   └── standards.md       # Quality standards
├── handoffs/
│   └── lead-to-specialist.md
└── workflows/
    └── default.yaml       # Single workflow
```

Lead plus specialist. Routing lives in `SYSTEM.md`. Lead holds the line on governance. One workflow. This is the smallest setup that still feels like a team.

### full (~30 files)

```
full/
├── SYSTEM.md              # Full system prompt
├── company.yaml           # Company config with budgets
├── agents/
│   ├── director.md        # Director (orchestrator)
│   ├── engineer.md        # Engineering agent
│   ├── analyst.md         # Analysis agent
│   └── writer.md          # Content/docs agent
├── skills/
│   ├── primary/
│   │   └── SKILL.md
│   ├── search/
│   │   └── SKILL.md
│   ├── build/
│   │   └── SKILL.md
│   ├── review/
│   │   └── SKILL.md
│   ├── report/
│   │   └── SKILL.md
│   ├── deploy/
│   │   └── SKILL.md
│   ├── analyze/
│   │   └── SKILL.md
│   └── summarize/
│       └── SKILL.md
├── reference/
│   ├── domain.md
│   ├── standards.md
│   ├── architecture.md
│   └── glossary.md
├── handoffs/
│   └── inter-agent.md
└── workflows/
    ├── sprint.yaml
    └── review.yaml
```

Multi-team energy. Four agents with clean ownership. Eight skills cover the loop from build to deploy. Sprint and review workflows ship in the box.

### enterprise (~40+ files)

```
enterprise/
├── SYSTEM.md              # Enterprise system prompt
├── company.yaml           # Full company config
├── agents/
│   ├── cto.md             # CTO (top-level orchestrator)
│   ├── engineering-lead.md
│   ├── product-lead.md
│   ├── security-lead.md
│   ├── engineer.md
│   └── analyst.md
├── skills/
│   ├── (8 skill directories)
│   └── ...
├── reference/
│   ├── domain.md
│   ├── standards.md
│   ├── architecture.md
│   ├── glossary.md
│   ├── compliance.md
│   └── runbooks.md
├── governance/
│   ├── approval-gates.md
│   ├── escalation.md
│   └── audit-policy.md
├── budgets/
│   ├── company.yaml
│   └── team-allocations.yaml
├── handoffs/
│   └── inter-agent.md
└── workflows/
    ├── sprint.yaml
    ├── review.yaml
    ├── incident.yaml
    └── onboarding.yaml
```

You run compliance, multiple teams, real budget numbers, and processes auditors can read. Approval gates, audit policy, escalation — all first-class. This tier is for when “move fast” still has to pass legal.

---

## Level up without nuking your folder

Start where you are. Grow when the org catches up.

1. **micro → small**: Drop in `company.yaml`, add a second agent, teach `SYSTEM.md` to route.
2. **small → full**: Stack agents, skills, reference docs, second workflow.
3. **full → enterprise**: Add `governance/`, `budgets/`, compliance reference, security lead.

Every tier is a superset of the last one. You extend. You don’t rip out structure.

---

*Templates v1.0 — Bizforge workspace starters*
