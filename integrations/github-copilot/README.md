# GitHub Copilot Integration

Bizforge agents work with GitHub Copilot out of the box. No conversion needed — agents use the native `.md` + YAML frontmatter format.

## Install

```bash
# Copy all agents to your GitHub Copilot agents directories
./scripts/install.sh --tool copilot

# Or manually copy a category
cp engineering/*.md ~/.github/agents/
cp engineering/*.md ~/.copilot/agents/
```

## Activate an Agent

In any GitHub Copilot session, reference an agent by name:

```
Activate Frontend Developer and help me build a React component.
```

```
Use the Reality Checker agent to verify this feature is production-ready.
```

## Agent Directory

330+ agents organized into 19 categories. See the [main README](../../README.md) for the full roster.
