# Protocol — The Spec

Formal definitions for workspace structure, agent format, signal encoding, and executable spec layers. These are the standards. All workspaces, operations, and tooling conform to them.

## Files

| File | What It Defines |
|------|----------------|
| `workspace-protocol.md` | SYSTEM.md + agents/ + skills/ + reference/ standard |
| `signal-theory.md` | S=(M,G,T,F,W) universal signal encoding |
| `agent-format.md` | YAML frontmatter + 7 body sections for agent definitions |
| `company-format.md` | company.yaml schema (org chart, budgets, governance) |
| `operations-spec.md` | Complete workspace specification |
| `spec-layer.md` | PROCEDURES.md, WORKFLOW.md, MODULES.md formats |
| `verification.md` | Spec contracts, verification strength, drift detection |
| `pipelines.md` | Event stream processing (producers, filters, consumers) |

## How to Use

**Building a workspace?** Start with `workspace-protocol.md` for the directory structure and `agent-format.md` for writing agents.

**Building tooling** that reads or validates workspaces? These files are the canonical reference for every format and constraint.

---

*Protocol v1.0 — Workspace format specifications*
