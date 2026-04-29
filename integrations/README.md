# Integrations

This folder ships converted formats and installers so **330+** agents land cleanly on every major runtime. Pick your weapon.

## Your stack, your call

- **[OSA](#osa)** — Workspace Protocol native. Point it at a workspace. It finds everything. No conversion drama.
- **[Claude Code](#claude-code)** — Plain `.md` agents. Clone the repo and go.
- **[GitHub Copilot](#github-copilot)** — Same `.md` deal. Repo is the source of truth.
- **[Antigravity](#antigravity)** — One `SKILL.md` per agent under `antigravity/`.
- **[Gemini CLI](#gemini-cli)** — Extension plus `SKILL.md` files in `gemini-cli/`.
- **[OpenCode](#opencode)** — `.md` agent files in `opencode/`.
- **[OpenClaw](#openclaw)** — Full workspaces: `SOUL.md`, `AGENTS.md`, `IDENTITY.md`.
- **[Cursor](#cursor)** — `.mdc` rules in `cursor/`.
- **[Aider](#aider)** — `CONVENTIONS.md` in `aider/`.
- **[Windsurf](#windsurf)** — `.windsurfrules` in `windsurf/`.

## Ship it in one shot

```bash
# Install for all detected tools automatically
./scripts/install.sh

# Install a specific home-scoped tool
./scripts/install.sh --tool antigravity
./scripts/install.sh --tool copilot
./scripts/install.sh --tool openclaw
./scripts/install.sh --tool claude-code

# Gemini CLI needs generated integration files on a fresh clone
./scripts/convert.sh --tool gemini-cli
./scripts/install.sh --tool gemini-cli
```

OpenCode, Cursor, Aider, and Windsurf are **project-scoped**. Run the installer from that project’s root. The per-tool sections spell it out.

## Blow away stale exports — regenerate

You touch the **330+** agent library, you rerun conversion. Non-negotiable.

```bash
./scripts/convert.sh
```

---

## OSA

OSA speaks Workspace Protocol fluently. Hand it a workspace path. It pulls in `SYSTEM.md`, agents, skills, references. Zero conversion layer.

```bash
# Connect to a workspace
osa connect /path/to/workspace

# Install library agents into your OSA base config
./scripts/install.sh --tool osa
```

Workspace agents and skills stack on your base at `~/.osa/`. Swap workspaces, domain context follows you. Base config — global agents, memory, channels — stays put.

Full story: [osa/README.md](osa/README.md).

---

## Claude Code

We built the agent format for Claude Code first. It still runs **330+** agents raw — no transform step.

```bash
cp -r <category>/*.md ~/.claude/agents/
# or install everything at once:
./scripts/install.sh --tool claude-code
```

Dig in: [claude-code/README.md](claude-code/README.md).

---

## GitHub Copilot

Copilot eats the same `.md` agents. Copy straight into `~/.github/agents/` and `~/.copilot/agents/`. Still no conversion.

```bash
./scripts/install.sh --tool copilot
```

Details: [github-copilot/README.md](github-copilot/README.md).

---

## Antigravity

Skills land in `~/.gemini/antigravity/skills/`. Each agent is its own skill, prefixed `agency-` so names never collide.

```bash
./scripts/install.sh --tool antigravity
```

More: [antigravity/README.md](antigravity/README.md).

---

## Gemini CLI

Bizforge packs agents as a Gemini CLI extension with per-agent skill files. Install target: `~/.gemini/extensions/bizforge/`. Manifest and skill folders are generated — run `./scripts/convert.sh --tool gemini-cli` once after a fresh clone, **then** install.

```bash
./scripts/convert.sh --tool gemini-cli
./scripts/install.sh --tool gemini-cli
```

Read this: [gemini-cli/README.md](gemini-cli/README.md).

---

## OpenCode

Every agent becomes a project-scoped `.md` under `.opencode/agents/`.

```bash
cd /your/project && /path/to/bizforge/scripts/install.sh --tool opencode
```

[opencode/README.md](opencode/README.md) has the rest.

---

## OpenClaw

Each agent spins up an OpenClaw workspace: `SOUL.md`, `AGENTS.md`, `IDENTITY.md`.

Generate workspaces first:

```bash
./scripts/convert.sh --tool openclaw
```

Then install:

```bash
./scripts/install.sh --tool openclaw
```

[openclaw/README.md](openclaw/README.md) walks through it.

---

## Cursor

Each agent maps to a `.mdc` rule. Rules stick to the project — run from project root.

```bash
cd /your/project && /path/to/bizforge/scripts/install.sh --tool cursor
```

[cursor/README.md](cursor/README.md).

---

## Aider

All **330+** agents collapse into one `CONVENTIONS.md`. Aider picks it up automatically from project root.

```bash
cd /your/project && /path/to/bizforge/scripts/install.sh --tool aider
```

[aider/README.md](aider/README.md).

---

## Windsurf

Same idea — one `.windsurfrules` at project root, whole library inside.

```bash
cd /your/project && /path/to/bizforge/scripts/install.sh --tool windsurf
```

[windsurf/README.md](windsurf/README.md).
