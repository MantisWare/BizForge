---
name: ide-orchestrate
description: >
  Orchestrate IDE-native AI agents through structured Instruct-Plan-Review-Execute-Review-Report
  cycles without performing implementation directly. Defines the shared supervisory lifecycle,
  instruction format, review protocol, and execution report template used by all IDE Principal
  Developer agents (Cursor, VS Code, Zed, JetBrains).
  Triggers on: "ide orchestrate", "supervise ide", "principal developer", "instruct ide agent", "ide supervision"
---

# /ide-orchestrate

> Drive an IDE agent through a supervised development cycle: instruct, plan, review, execute, review, report.

## Purpose

Define and execute the six-phase supervisory lifecycle for IDE Principal Developer agents. This skill provides the shared foundation — instruction format, plan review checklist, post-execution review protocol, execution report template, and retry/escalation logic — that all IDE-specific agents use. The IDE-specific adapter logic (how to connect to Cursor's SDK, VS Code's Copilot SDK, Zed's ACP, or JetBrains' Junie CLI) lives in each agent's definition, not here.

This skill is about **supervision, not implementation**. The agent using this skill never writes code. It formulates precise instructions, validates plans, audits execution results, and produces formal reports.

## Usage

```bash
# Full supervised cycle
/ide-orchestrate --task "Implement user auth middleware" --acceptance-criteria ./criteria.md

# Plan only — stop after plan review
/ide-orchestrate --task "Fix N+1 query in reports" --plan-only

# Resume from a previous session
/ide-orchestrate --resume task-2026-05-06-143500

# Limit revision cycles
/ide-orchestrate --task "Add pagination to API" --max-revisions 2

# Provide explicit file scope
/ide-orchestrate --task "Refactor auth module" --scope "src/auth/**"
```

## Arguments

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--task` | string | required | Task description or path to task specification |
| `--acceptance-criteria` | path | — | Path to a file containing numbered acceptance criteria |
| `--plan-only` | flag | false | Stop after the Plan Review phase (do not execute) |
| `--resume` | string | — | Task ID to resume from a previous session |
| `--max-revisions` | int | `3` | Maximum plan revision cycles before escalation |
| `--scope` | string | — | File glob pattern limiting which files the IDE agent should touch |
| `--context` | path[] | — | Additional context files (specs, PRs, architecture docs) |

## Workflow: Six-Phase Supervisory Lifecycle

### Phase 1: Instruct

Receive the task, analyze requirements, and produce a structured instruction for the IDE agent.

**Input**: Task description, project context, coding conventions
**Output**: Structured instruction in the Instruction Format Template

The instruction must be self-contained. The IDE agent should be able to execute based solely on the instruction without additional clarification.

### Phase 2: Plan (IDE Agent)

The IDE agent receives the instruction and produces an implementation plan. During this phase, the IDE agent should only read and analyze — no code modifications.

**Input**: Structured instruction from Phase 1
**Output**: Implementation plan document

### Phase 3: Review Plan

Validate the plan against the Plan Review Checklist. Approve, request revision, or escalate.

**Input**: Plan document from Phase 2
**Output**: APPROVE / REVISE (with specific feedback) / ESCALATE

### Phase 4: Execute (IDE Agent)

The IDE agent implements the approved plan. The supervisor monitors execution.

**Input**: Approved plan + execution authorization
**Output**: Code changes + execution summary

### Phase 5: Comprehensive Review

Instruct the IDE agent to self-review, then independently verify all changes against acceptance criteria.

**Input**: Code changes from Phase 4
**Output**: Review findings with pass/fail per criterion

### Phase 6: Report

Produce a formal execution report for QA handoff.

**Input**: All prior phase outputs
**Output**: Execution Report in the Report Template format

## Instruction Format Template

Every instruction sent to the IDE agent must follow this structure:

```markdown
## Task Instruction — {task-id}

### Objective
{Single sentence describing what needs to be accomplished}

### Acceptance Criteria
1. {Specific, verifiable criterion}
2. {Specific, verifiable criterion}
3. {Specific, verifiable criterion}
...

### Constraints
- DO NOT modify files outside: {file scope}
- DO NOT change: {protected patterns, APIs, interfaces}
- MUST follow: {coding conventions, style guide reference}
- MUST NOT: {specific anti-patterns to avoid}

### File Scope
- Primary: {files/directories that should be modified}
- Context: {files/directories to read for understanding, not modify}

### Context
- Related PR/issue: {reference}
- Architecture decision: {reference}
- Prior implementation: {reference}
- Dependencies: {packages, services affected}

### Planning Phase
Produce a detailed implementation plan before making any changes. The plan must:
1. List every file you will create, modify, or delete
2. Describe each change with enough detail to review
3. Identify risks and breaking change potential
4. Estimate the impact surface (which other files/tests may be affected)
```

## Plan Review Checklist

When reviewing the IDE agent's plan, verify every item:

### Coverage
- [ ] Every acceptance criterion has a corresponding planned change
- [ ] No acceptance criterion is unaddressed or vaguely addressed

### Scope
- [ ] No changes to files outside the defined file scope
- [ ] No unrelated refactoring or "while I'm here" changes
- [ ] No dependency additions that weren't requested

### Risk
- [ ] Breaking changes identified and mitigated
- [ ] Migration steps documented (if applicable)
- [ ] Rollback strategy identified for high-risk changes

### Completeness
- [ ] Tests planned for new/changed behavior
- [ ] Error handling addressed
- [ ] Edge cases considered
- [ ] Documentation updates planned (if applicable)

### Impact Surface
- [ ] Affected downstream files/modules identified
- [ ] Integration points validated
- [ ] Performance implications assessed

## Post-Execution Review Protocol

After the IDE agent executes, perform this comprehensive review:

### 1. Diff Analysis
- Review `git diff` of all changed files
- Verify changes match the approved plan
- Identify any unplanned changes (drift from plan)

### 2. Acceptance Criteria Verification
For each acceptance criterion:
- Locate the implementation in the diff
- Verify it meets the criterion's requirements
- Note the specific file and line range as evidence
- Mark as PASS, PARTIAL, or MISSING

### 3. Regression Risk Assessment
- Check for removed or modified existing functionality
- Verify existing tests still pass (or were updated appropriately)
- Identify potential side effects in dependent code

### 4. Style & Convention Compliance
- Verify naming conventions followed
- Check import organization
- Validate error handling patterns
- Confirm TypeScript strict compliance (if applicable)

### 5. Test Coverage Verification
- New behavior has corresponding tests
- Edge cases covered
- Test naming follows project conventions
- No test-only code leaked into production files

### 6. Security Surface Check
- No secrets, tokens, or credentials in code
- Input validation on boundaries (API, user input)
- No SQL injection, XSS, or auth bypass vectors introduced
- Sanitization applied where required

## Execution Report Template

The formal output of every `/ide-orchestrate` cycle:

```markdown
## Execution Report — {task-id}

### Task
{Original task description}

### IDE Agent
{Which IDE and agent was used — e.g., "Cursor via @cursor/sdk"}

### Plan Summary
{2-3 sentence summary of what was planned}

### Execution Result
PASS | PARTIAL | FAIL

### Acceptance Criteria
- [x] Criterion 1 — verified at {file}:{line-range}
- [x] Criterion 2 — verified at {file}:{line-range}
- [ ] Criterion 3 — MISSING: {explanation of what's missing}

### Changes Made
| File | Action | Lines Changed | Description |
|------|--------|---------------|-------------|
| src/auth/middleware.ts | created | +45 | Auth middleware implementation |
| src/routes/api.ts | modified | +3 -1 | Added middleware to route chain |
| tests/auth.test.ts | created | +62 | Middleware unit tests |

### Plan Adherence
- Planned changes: {N}
- Executed as planned: {N}
- Unplanned changes: {N} — {explanation if any}
- Omitted changes: {N} — {explanation if any}

### Review Findings
| # | Severity | File | Line | Finding |
|---|----------|------|------|---------|
| 1 | BLOCKER | src/auth/middleware.ts | 23 | Missing rate limiting |
| 2 | SUGGESTION | src/auth/middleware.ts | 31 | Consider extracting token validation |

### Revision History
| Cycle | Phase | Action | Detail |
|-------|-------|--------|--------|
| 1 | Plan Review | REVISE | Missing criterion #3 |
| 2 | Plan Review | APPROVE | All criteria addressed |
| 1 | Execution Review | PASS | All criteria verified |

### Recommendation
READY FOR QA | NEEDS REVISION ({N} issues)

### QA Focus Areas
- {Specific areas QA should test}
- {Edge cases to verify}
- {Integration points to validate}

### Known Limitations
- {Any constraints or incomplete areas}
- {Follow-up tasks identified}
```

## Retry & Escalation Logic

### Plan Revision
- **Attempt 1-3**: Send specific feedback listing missing criteria and concerns. Include the criterion number, what's missing, and what the revision should address.
- **After 3 failed revisions**: Escalate with a failure report containing all plan versions and feedback history.

### Execution Revision
- **Attempt 1-3**: Send specific fix instructions referencing file paths, line numbers, and acceptance criteria numbers.
- **After 3 failed revisions**: Escalate with a failure report containing all execution attempts and review findings.

### Escalation Report Format

```markdown
## Escalation Report — {task-id}

### Reason
PLAN_REVISION_LIMIT | EXECUTION_REVISION_LIMIT

### Attempts
{Number of revision cycles attempted}

### History
{Chronological list of each attempt with feedback given and response received}

### Recommendation
{What a human should look at to unblock this task}
```

## Dependencies

- `/plan` — Structuring objectives and acceptance criteria for the instruction
- `/code-review` — Review methodology for plan and post-execution review phases
- `/delegate` — Delegating execution to the IDE agent
- Git — Diff analysis for post-execution review

## Notes

This skill defines the **lifecycle and templates only**. IDE-specific adapter logic (how to connect, authenticate, send prompts, stream responses, and extract results) lives in each IDE Principal Developer agent definition:

- Cursor: `@cursor/sdk` — see `cursor-principal-developer`
- VS Code: `@github/copilot-sdk` — see `vscode-principal-developer`
- Zed: ACP (Agent Client Protocol) — see `zed-principal-developer`
- JetBrains: Junie CLI + ACP — see `jetbrains-principal-developer`
