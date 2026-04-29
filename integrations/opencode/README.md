# OpenCode Integration

OpenCode agents are `.md` files with YAML frontmatter stored in `.opencode/agents/`. The converter maps named colors to hex codes and adds `mode: subagent` so agents are invoked on-demand via `@agent-name` — not cluttering the primary agent picker.

## Install

```bash
# Run from your project root
cd /your/project
/path/to/bizforge/scripts/install.sh --tool opencode
```

Creates `.opencode/agents/<slug>.md` files in your project directory. Done.

## Activate an Agent

In OpenCode, invoke a subagent with the `@` prefix:

```
@frontend-developer help build this component.
```

```
@reality-checker review this PR.
```

Or select agents from the OpenCode UI's agent picker.

## Agent Format

Each generated agent file contains:

```yaml
---
name: Frontend Developer
description: Expert frontend developer specializing in modern web technologies...
mode: subagent
color: "#00FFFF"
---
```

- **mode: subagent** — available on-demand, not shown in the primary Tab-cycle list
- **color** — hex code (named colors from source files are converted automatically)

## Project vs Global

Agents in `.opencode/agents/` are **project-scoped**. To make them available globally:

```bash
mkdir -p ~/.config/opencode/agents
cp integrations/opencode/agents/*.md ~/.config/opencode/agents/
```

## Regenerate

```bash
./scripts/convert.sh --tool opencode
```
