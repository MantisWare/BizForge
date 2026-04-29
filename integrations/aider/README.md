# Aider Integration

All 330+ agents consolidated into a single `CONVENTIONS.md` file. Aider reads this file automatically when it's present in your project root.

## Install

```bash
# Run from your project root
cd /your/project
/path/to/bizforge/scripts/install.sh --tool aider
```

## Activate an Agent

In your Aider session, reference the agent by name:

```
Use the Frontend Developer agent to refactor this component.
```

```
Apply the Reality Checker agent to verify this is production-ready.
```

## Manual Usage

Pass the conventions file directly:

```bash
aider --read CONVENTIONS.md
```

## Regenerate

```bash
./scripts/convert.sh --tool aider
```
