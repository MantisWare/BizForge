# MCP Memory Integration

> Give any agent persistent memory across sessions using the Model Context Protocol.

## What It Does

By default, Bizforge agents start every session fresh. Context gets passed manually between agents and sessions. An MCP memory server kills that problem:

- **Cross-session memory**: Agent remembers decisions, deliverables, and context from previous sessions
- **Handoff continuity**: When one agent hands off to another, the receiving agent recalls exactly what was done — no copy-paste
- **Rollback on failure**: QA check fails? Architecture decision backfires? Roll back to a known-good state instead of starting over

## Setup

You need an MCP server that provides memory tools: `remember`, `recall`, `rollback`, and `search`. Add it to your MCP client config (Claude Code, Cursor, etc.):

```json
{
  "mcpServers": {
    "memory": {
      "command": "your-mcp-memory-server",
      "args": []
    }
  }
}
```

Any MCP server exposing `remember`, `recall`, `rollback`, and `search` tools will work. Check the [MCP ecosystem](https://modelcontextprotocol.io) for available implementations.

## How to Add Memory to Any Agent

Add a **Memory Integration** section to the agent's prompt. This tells the agent to use MCP memory tools at the right moments.

### The Pattern

```markdown
## Memory Integration

When you start a session:
- Recall relevant context from previous sessions using your role and the current project as search terms
- Review any memories tagged with your agent name to pick up where you left off

When you make key decisions or complete deliverables:
- Remember the decision or deliverable with descriptive tags (your agent name, the project, the topic)
- Include enough context that a future session — or a different agent — can understand what was done and why

When handing off to another agent:
- Remember your deliverables tagged for the receiving agent
- Include the handoff metadata: what you completed, what's pending, and what the next agent needs to know

When something fails and you need to recover:
- Search for the last known-good state
- Use rollback to restore to that point rather than rebuilding from scratch
```

### What the Agent Actually Does

The LLM uses MCP memory tools automatically when given these instructions:

- `remember` — store a decision, deliverable, or context snapshot with tags
- `recall` — search for relevant memories by keyword, tag, or semantic similarity
- `rollback` — revert to a previous state when something goes wrong
- `search` — find specific memories across sessions and agents

No code changes to agent files. No API calls to write. The MCP tools handle everything.

## Example: Enhancing the Backend Architect

See [backend-architect-with-memory.md](backend-architect-with-memory.md) for the complete example — standard Backend Architect agent with a Memory Integration section bolted on.

## Example: Memory-Powered Workflow

See [../../examples/workflow-with-memory.md](../../examples/workflow-with-memory.md) for the Startup MVP workflow enhanced with persistent memory. Shows how agents pass context through memory instead of copy-paste.

## Tips

- **Tag consistently**: Use the agent name and project name as tags on every memory. Makes recall reliable.
- **Let the LLM decide what's important**: The memory instructions are guidance, not rigid rules. The LLM figures out when to remember and what to recall.
- **Rollback is the killer feature**: When a Reality Checker fails a deliverable, the original agent rolls back to its last checkpoint instead of manually undoing changes.
