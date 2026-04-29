# Windsurf Integration

All 330+ agents consolidated into a single `.windsurfrules` file. Rules are **project-scoped** — install from your project root.

## Install

```bash
# Run from your project root
cd /your/project
/path/to/bizforge/scripts/install.sh --tool windsurf
```

## Activate an Agent

In Windsurf, reference an agent by name in your prompt:

```
Use the Frontend Developer agent to build this component.
```

## Regenerate

```bash
./scripts/convert.sh --tool windsurf
```
