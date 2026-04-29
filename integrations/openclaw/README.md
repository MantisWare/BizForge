# OpenClaw Integration

OpenClaw agents install as workspaces containing `SOUL.md`, `AGENTS.md`, and `IDENTITY.md` files. The installer copies each workspace into `~/.openclaw/bizforge/` and registers it when the `openclaw` CLI is available.

Before installing, generate the OpenClaw workspaces:

```bash
./scripts/convert.sh --tool openclaw
```

## Install

```bash
./scripts/install.sh --tool openclaw
```

## Activate an Agent

After installation, agents are available by `agentId` in OpenClaw sessions.

If the OpenClaw gateway is already running, restart it:

```bash
openclaw gateway restart
```

## Regenerate

```bash
./scripts/convert.sh --tool openclaw
```
