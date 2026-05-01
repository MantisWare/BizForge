#!/usr/bin/env node
/**
 * BizForge MCP Server
 *
 * Exposes BizForge capabilities to external AI agents and LLMs via the
 * Model Context Protocol. Connects to the running BizForge backend over
 * its REST API and translates MCP tool calls into API requests.
 */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { api, configure, healthCheck } from "./api.js";
// ── Configuration ────────────────────────────────────────────────────────────
const mcpServer = new McpServer({
    name: "bizforge",
    version: "0.1.0",
}, {
    capabilities: {
        tools: {},
        resources: {},
    },
    instructions: [
        "BizForge MCP Server — interact with a running BizForge instance.",
        "Use these tools to manage AI agents, run tasks, query projects/issues,",
        "read and write documents, search memory, trigger workflows, and more.",
        "The BizForge backend must be running (default: http://127.0.0.1:9089).",
    ].join(" "),
});
// ── Helper ───────────────────────────────────────────────────────────────────
function textResult(data) {
    return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
    };
}
function errorResult(message) {
    return {
        content: [{ type: "text", text: message }],
        isError: true,
    };
}
async function safeTool(fn) {
    try {
        const result = await fn();
        return textResult(result);
    }
    catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return errorResult(message);
    }
}
// ── Resources ────────────────────────────────────────────────────────────────
mcpServer.resource("bizforge-status", "bizforge://status", { description: "Current BizForge system health and connection status" }, async () => {
    const healthy = await healthCheck();
    return {
        contents: [
            {
                uri: "bizforge://status",
                mimeType: "application/json",
                text: JSON.stringify({ connected: healthy, timestamp: new Date().toISOString() }),
            },
        ],
    };
});
// ── Tool: System Health & Dashboard ──────────────────────────────────────────
mcpServer.tool("bizforge_health", "Check if the BizForge backend is running and responsive", async () => safeTool(() => api("/health")));
mcpServer.tool("bizforge_dashboard", "Get the BizForge dashboard summary (agents, tasks, costs, activity)", async () => safeTool(() => api("/dashboard")));
// ── Tools: Agent Management ──────────────────────────────────────────────────
mcpServer.tool("bizforge_agents_list", "List all agents in the current BizForge workspace", async () => safeTool(() => api("/agents")));
mcpServer.tool("bizforge_agent_get", "Get details of a specific agent by ID", { agent_id: z.string().describe("The agent's unique ID") }, async ({ agent_id }) => safeTool(() => api(`/agents/${agent_id}`)));
mcpServer.tool("bizforge_agent_create", "Create a new AI agent in the workspace", {
    name: z.string().describe("Agent name"),
    role: z.string().describe("Agent role/job title"),
    adapter: z.string().optional().describe("Adapter type (osa, claude_code, codex, etc.)"),
    model: z.string().optional().describe("LLM model to use (e.g. claude-sonnet-4-6)"),
    system_prompt: z.string().optional().describe("Custom system prompt for the agent"),
    skills: z.array(z.string()).optional().describe("List of skill IDs to assign"),
    emoji: z.string().optional().describe("Emoji icon for the agent"),
}, async (args) => safeTool(() => api("/agents", { method: "POST", body: args })));
mcpServer.tool("bizforge_agent_update", "Update an existing agent's configuration", {
    agent_id: z.string().describe("The agent's unique ID"),
    name: z.string().optional().describe("New name"),
    role: z.string().optional().describe("New role"),
    system_prompt: z.string().optional().describe("New system prompt"),
    model: z.string().optional().describe("New model"),
    skills: z.array(z.string()).optional().describe("Updated skill IDs"),
}, async ({ agent_id, ...body }) => safeTool(() => api(`/agents/${agent_id}`, { method: "PATCH", body })));
mcpServer.tool("bizforge_agent_wake", "Wake an agent (transition from sleeping to active)", { agent_id: z.string().describe("The agent's unique ID") }, async ({ agent_id }) => safeTool(() => api(`/agents/${agent_id}/wake`, { method: "POST" })));
mcpServer.tool("bizforge_agent_sleep", "Put an agent to sleep (transition from active to sleeping)", { agent_id: z.string().describe("The agent's unique ID") }, async ({ agent_id }) => safeTool(() => api(`/agents/${agent_id}/sleep`, { method: "POST" })));
mcpServer.tool("bizforge_agent_pause", "Pause an active agent", { agent_id: z.string().describe("The agent's unique ID") }, async ({ agent_id }) => safeTool(() => api(`/agents/${agent_id}/pause`, { method: "POST" })));
mcpServer.tool("bizforge_agent_resume", "Resume a paused agent", { agent_id: z.string().describe("The agent's unique ID") }, async ({ agent_id }) => safeTool(() => api(`/agents/${agent_id}/resume`, { method: "POST" })));
mcpServer.tool("bizforge_agent_terminate", "Terminate an agent's current session", { agent_id: z.string().describe("The agent's unique ID") }, async ({ agent_id }) => safeTool(() => api(`/agents/${agent_id}/terminate`, { method: "POST" })));
mcpServer.tool("bizforge_agent_hierarchy", "Get the full agent organizational hierarchy (divisions, departments, teams)", async () => safeTool(() => api("/agents/hierarchy")));
// ── Tools: Sessions & Chat ───────────────────────────────────────────────────
mcpServer.tool("bizforge_sessions_list", "List all agent sessions", async () => safeTool(() => api("/sessions")));
mcpServer.tool("bizforge_session_create", "Create a new agent session (start a conversation with an agent)", {
    agent_id: z.string().describe("ID of the agent to start a session with"),
    message: z.string().optional().describe("Optional initial message to send"),
}, async (args) => safeTool(() => api("/sessions", { method: "POST", body: args })));
mcpServer.tool("bizforge_session_message", "Send a message to an active agent session", {
    session_id: z.string().describe("The session ID"),
    content: z.string().describe("Message content to send"),
    role: z.string().optional().describe("Message role (defaults to 'user')"),
}, async ({ session_id, ...body }) => safeTool(() => api(`/sessions/${session_id}/message`, { method: "POST", body })));
mcpServer.tool("bizforge_session_transcript", "Get the full transcript of a session", { session_id: z.string().describe("The session ID") }, async ({ session_id }) => safeTool(() => api(`/sessions/${session_id}/transcript`)));
// ── Tools: Spawn (Task Dispatch) ────────────────────────────────────────────
mcpServer.tool("bizforge_spawn", "Spawn a task — dispatch work to an agent for autonomous execution", {
    agent_id: z.string().describe("ID of the agent to assign the task to"),
    task: z.string().describe("Task description / prompt for the agent"),
    context: z.string().optional().describe("Additional context or instructions"),
    priority: z.enum(["low", "normal", "high", "critical"]).optional().describe("Task priority"),
}, async (args) => safeTool(() => api("/spawn", { method: "POST", body: args })));
mcpServer.tool("bizforge_spawn_active", "List all currently active spawned tasks", async () => safeTool(() => api("/spawn/active")));
mcpServer.tool("bizforge_spawn_kill", "Kill/cancel a running spawned task", { spawn_id: z.string().describe("The spawn instance ID to kill") }, async ({ spawn_id }) => safeTool(() => api(`/spawn/${spawn_id}`, { method: "DELETE" })));
mcpServer.tool("bizforge_spawn_history", "Get the history of completed spawned tasks", async () => safeTool(() => api("/spawn/history")));
// ── Tools: Workflows ─────────────────────────────────────────────────────────
mcpServer.tool("bizforge_workflows_list", "List all workflows defined in the workspace", async () => safeTool(() => api("/workflows")));
mcpServer.tool("bizforge_workflow_get", "Get details and steps of a specific workflow", { workflow_id: z.string().describe("The workflow ID") }, async ({ workflow_id }) => safeTool(async () => {
    const workflow = await api(`/workflows/${workflow_id}`);
    const steps = await api(`/workflows/${workflow_id}/steps`);
    return { workflow, steps };
}));
mcpServer.tool("bizforge_workflow_trigger", "Trigger a workflow to start running", {
    workflow_id: z.string().describe("The workflow ID to trigger"),
    params: z.record(z.string(), z.any()).optional().describe("Optional parameters to pass to the workflow"),
}, async ({ workflow_id, params }) => safeTool(() => api(`/workflows/${workflow_id}/trigger`, {
    method: "POST",
    body: params ?? {},
})));
mcpServer.tool("bizforge_workflow_runs", "List runs (executions) of a workflow", { workflow_id: z.string().describe("The workflow ID") }, async ({ workflow_id }) => safeTool(() => api(`/workflows/${workflow_id}/runs`)));
// ── Tools: Projects ──────────────────────────────────────────────────────────
mcpServer.tool("bizforge_projects_list", "List all projects in the workspace", async () => safeTool(() => api("/projects")));
mcpServer.tool("bizforge_project_get", "Get details of a specific project", { project_id: z.string().describe("The project ID") }, async ({ project_id }) => safeTool(() => api(`/projects/${project_id}`)));
mcpServer.tool("bizforge_project_create", "Create a new project", {
    name: z.string().describe("Project name"),
    description: z.string().optional().describe("Project description"),
    status: z.string().optional().describe("Initial status"),
}, async (args) => safeTool(() => api("/projects", { method: "POST", body: args })));
// ── Tools: Issues ────────────────────────────────────────────────────────────
mcpServer.tool("bizforge_issues_list", "List all issues in the workspace (supports filtering)", {
    status: z.string().optional().describe("Filter by status (open, in_progress, closed, etc.)"),
    assignee_id: z.string().optional().describe("Filter by assigned agent ID"),
    project_id: z.string().optional().describe("Filter by project ID"),
}, async (params) => safeTool(() => api("/issues", { params })));
mcpServer.tool("bizforge_issue_create", "Create a new issue/task", {
    title: z.string().describe("Issue title"),
    description: z.string().optional().describe("Issue description/body"),
    priority: z.enum(["low", "medium", "high", "critical"]).optional().describe("Issue priority"),
    project_id: z.string().optional().describe("Project to assign to"),
    assignee_id: z.string().optional().describe("Agent to assign to"),
    labels: z.array(z.string()).optional().describe("Labels to apply"),
}, async (args) => safeTool(() => api("/issues", { method: "POST", body: args })));
mcpServer.tool("bizforge_issue_update", "Update an existing issue", {
    issue_id: z.string().describe("The issue ID"),
    title: z.string().optional().describe("New title"),
    description: z.string().optional().describe("New description"),
    status: z.string().optional().describe("New status"),
    priority: z.string().optional().describe("New priority"),
    assignee_id: z.string().optional().describe("New assignee agent ID"),
}, async ({ issue_id, ...body }) => safeTool(() => api(`/issues/${issue_id}`, { method: "PATCH", body })));
mcpServer.tool("bizforge_issue_assign", "Assign an issue to an agent for execution", {
    issue_id: z.string().describe("The issue ID"),
    agent_id: z.string().describe("The agent ID to assign to"),
}, async ({ issue_id, agent_id }) => safeTool(() => api(`/issues/${issue_id}/assign`, {
    method: "POST",
    body: { agent_id },
})));
mcpServer.tool("bizforge_issue_dispatch", "Dispatch an issue directly to an agent for autonomous work", {
    issue_id: z.string().describe("The issue ID to dispatch"),
}, async ({ issue_id }) => safeTool(() => api(`/issues/${issue_id}/dispatch`, { method: "POST" })));
// ── Tools: Goals ─────────────────────────────────────────────────────────────
mcpServer.tool("bizforge_goals_list", "List all goals in the workspace", async () => safeTool(() => api("/goals")));
mcpServer.tool("bizforge_goal_create", "Create a new goal", {
    title: z.string().describe("Goal title"),
    description: z.string().optional().describe("Goal description"),
    parent_id: z.string().optional().describe("Parent goal ID for sub-goals"),
    project_id: z.string().optional().describe("Project to associate with"),
}, async (args) => safeTool(() => api("/goals", { method: "POST", body: args })));
// ── Tools: Documents ─────────────────────────────────────────────────────────
mcpServer.tool("bizforge_documents_list", "List all documents in the workspace document tree", async () => safeTool(() => api("/documents")));
mcpServer.tool("bizforge_document_read", "Read the contents of a document by its path", { path: z.string().describe("Document path (e.g. 'notes/design.md')") }, async ({ path }) => safeTool(() => api(`/documents/${path}`)));
mcpServer.tool("bizforge_document_write", "Create or update a document", {
    path: z.string().describe("Document path"),
    content: z.string().describe("Document content (markdown)"),
    title: z.string().optional().describe("Document title"),
}, async ({ path, ...body }) => safeTool(() => api(`/documents/${path}`, { method: "PUT", body })));
// ── Tools: Memory ────────────────────────────────────────────────────────────
mcpServer.tool("bizforge_memory_search", "Search the workspace memory store (semantic search across stored knowledge)", {
    query: z.string().describe("Search query"),
    namespace: z.string().optional().describe("Memory namespace to search within"),
    limit: z.number().optional().describe("Max results to return"),
}, async (params) => safeTool(() => api("/memory/search", { params })));
mcpServer.tool("bizforge_memory_store", "Store a new entry in the workspace memory", {
    key: z.string().describe("Memory key/identifier"),
    content: z.string().describe("Content to store"),
    namespace: z.string().optional().describe("Namespace to store in"),
    metadata: z.record(z.string(), z.any()).optional().describe("Additional metadata"),
}, async (args) => safeTool(() => api("/memory", { method: "POST", body: args })));
mcpServer.tool("bizforge_memory_namespaces", "List all memory namespaces", async () => safeTool(() => api("/memory/namespaces")));
// ── Tools: Skills ────────────────────────────────────────────────────────────
mcpServer.tool("bizforge_skills_list", "List all available skills in the workspace", async () => safeTool(() => api("/skills")));
mcpServer.tool("bizforge_skill_assign", "Assign a skill to an agent", {
    agent_id: z.string().describe("The agent ID"),
    skill_id: z.string().describe("The skill ID to assign"),
}, async ({ agent_id, skill_id }) => safeTool(() => api(`/agents/${agent_id}/skills/${skill_id}`, { method: "POST" })));
// ── Tools: Schedules ─────────────────────────────────────────────────────────
mcpServer.tool("bizforge_schedules_list", "List all agent schedules", async () => safeTool(() => api("/schedules")));
mcpServer.tool("bizforge_schedule_create", "Create a new agent schedule (cron-based recurring task)", {
    agent_id: z.string().describe("Agent to schedule"),
    cron: z.string().describe("Cron expression (e.g. '0 9 * * 1-5' for weekdays at 9am)"),
    description: z.string().optional().describe("Description of what the schedule does"),
    context: z.string().optional().describe("Context/prompt for each scheduled run"),
    enabled: z.boolean().optional().describe("Whether the schedule is active"),
}, async (args) => safeTool(() => api("/schedules", { method: "POST", body: args })));
// ── Tools: Costs & Budget ────────────────────────────────────────────────────
mcpServer.tool("bizforge_costs_summary", "Get a summary of token/API costs across the workspace", async () => safeTool(() => api("/costs/summary")));
mcpServer.tool("bizforge_costs_by_agent", "Get cost breakdown per agent", async () => safeTool(() => api("/costs/by-agent")));
mcpServer.tool("bizforge_budgets_list", "List all budget policies", async () => safeTool(() => api("/budgets")));
// ── Tools: Activity & Logs ───────────────────────────────────────────────────
mcpServer.tool("bizforge_activity", "Get recent activity events from the workspace", {
    limit: z.number().optional().describe("Max events to return (default 50)"),
}, async (params) => safeTool(() => api("/activity", { params })));
mcpServer.tool("bizforge_logs", "Get recent log entries", {
    level: z.string().optional().describe("Filter by log level (debug, info, warn, error)"),
    limit: z.number().optional().describe("Max entries to return"),
}, async (params) => safeTool(() => api("/logs", { params })));
// ── Tools: Configuration ─────────────────────────────────────────────────────
mcpServer.tool("bizforge_config_get", "Get the current workspace configuration/settings", async () => safeTool(() => api("/config")));
mcpServer.tool("bizforge_config_update", "Update workspace configuration settings", {
    settings: z.record(z.string(), z.any()).describe("Key-value pairs of settings to update"),
}, async ({ settings }) => safeTool(() => api("/config", { method: "PATCH", body: settings })));
// ── Tools: Teams & Hierarchy ─────────────────────────────────────────────────
mcpServer.tool("bizforge_teams_list", "List all teams in the organization", async () => safeTool(() => api("/teams")));
mcpServer.tool("bizforge_team_agents", "List agents belonging to a specific team", { team_id: z.string().describe("The team ID") }, async ({ team_id }) => safeTool(() => api(`/teams/${team_id}/agents`)));
mcpServer.tool("bizforge_hierarchy", "Get the full organizational hierarchy tree", async () => safeTool(() => api("/hierarchy")));
// ── Tools: Conversations ─────────────────────────────────────────────────────
mcpServer.tool("bizforge_conversations_list", "List all conversations", async () => safeTool(() => api("/conversations")));
mcpServer.tool("bizforge_conversation_messages", "Get messages from a conversation", { conversation_id: z.string().describe("The conversation ID") }, async ({ conversation_id }) => safeTool(() => api(`/conversations/${conversation_id}/messages`)));
mcpServer.tool("bizforge_conversation_send", "Send a message to a conversation", {
    conversation_id: z.string().describe("The conversation ID"),
    content: z.string().describe("Message content"),
}, async ({ conversation_id, ...body }) => safeTool(() => api(`/conversations/${conversation_id}/messages`, {
    method: "POST",
    body,
})));
// ── Tools: Webhooks & Integrations ───────────────────────────────────────────
mcpServer.tool("bizforge_webhooks_list", "List all configured webhooks", async () => safeTool(() => api("/webhooks")));
mcpServer.tool("bizforge_integrations_list", "List all external integrations and their status", async () => safeTool(() => api("/integrations")));
// ── Main ─────────────────────────────────────────────────────────────────────
async function main() {
    const args = process.argv.slice(2);
    for (let i = 0; i < args.length; i++) {
        const arg = args[i];
        if (arg === "--api-url" && i + 1 < args.length) {
            configure({ baseUrl: args[++i] });
        }
        else if (arg === "--token" && i + 1 < args.length) {
            configure({ token: args[++i] });
        }
    }
    const transport = new StdioServerTransport();
    await mcpServer.connect(transport);
    process.stderr.write("[bizforge-mcp] Server started. 59 tools registered.\n");
}
main().catch((err) => {
    process.stderr.write(`[bizforge-mcp] Fatal error: ${err}\n`);
    process.exit(1);
});
