<!-- src/routes/app/wiki/+page.svelte -->
<script lang="ts">
  import { page } from '$app/stores';
  import PageShell from '$lib/components/layout/PageShell.svelte';
  import AgentIcon from '$lib/components/shared/AgentIcon.svelte';

  interface WikiSection {
    id: string;
    title: string;
    icon: string;
    articles: WikiArticle[];
  }

  interface WikiArticle {
    id: string;
    title: string;
    route?: string;
    description: string;
    useCase: string;
    configuration: string[];
    capabilities: string[];
    tips?: string[];
  }

  const SECTIONS: WikiSection[] = [
    {
      id: 'getting-started',
      title: 'Getting Started',
      icon: 'rocket',
      articles: [
        {
          id: 'overview',
          title: 'What is BizForge?',
          description:
            'BizForge is a workspace protocol that turns plain markdown into fully operational AI companies. Agents, skills, teams, budgets, governance — all defined in files. Connect any AI backend and watch them run autonomously on heartbeat schedules.',
          useCase:
            'Use BizForge when you want to orchestrate multiple AI agents as a team, with proper governance, budgets, and organizational structure — not just one-off prompts.',
          configuration: [],
          capabilities: [
            'Markdown-first workspace protocol',
            'Multi-agent orchestration with heartbeat scheduling',
            'Desktop command center with pixel-art virtual office',
            'Support for Claude Code, OSA, Codex, Gemini, Cursor, Aider, Windsurf',
            'Real-time token cost monitoring',
            'Human-in-the-loop approval gates',
            '330+ deployable agent templates',
          ],
        },
        {
          id: 'onboarding',
          title: 'Onboarding Wizard',
          route: '/onboarding',
          description:
            'The onboarding wizard runs the first time you launch BizForge. It walks you through naming your workspace, choosing a local directory, selecting an AI provider, and picking a team template.',
          useCase:
            'Complete onboarding to scaffold your workspace directory structure, configure your preferred AI adapter, and deploy an initial team of agents.',
          configuration: [
            'Workspace name and local directory path',
            'AI provider selection (OSA, Claude Code, Codex, Gemini, etc.)',
            'API key for your chosen provider',
            'Team template (Solo Dev, Dev Team, Research Lab, Content Studio, Ops Center, Sales Engine, Data Science, Custom)',
            'MIOSA Cloud sandboxing toggle',
          ],
          capabilities: [
            'Scaffolds ~/.bizforge directory structure',
            'Registers workspace with the backend',
            'Creates initial organization',
            'Deploys agents from selected team template',
          ],
        },
      ],
    },
    {
      id: 'daily-drivers',
      title: 'Daily Drivers',
      icon: 'office-building',
      articles: [
        {
          id: 'dashboard',
          title: 'Dashboard',
          route: '/app',
          description:
            'The dashboard is your workspace command center. It shows key performance indicators, active agent runs, a live activity feed, financial summaries, and system health — all at a glance.',
          useCase:
            'Start here every session to see what your agents are doing, how much they\'re spending, and whether any issues need attention.',
          configuration: [
            'Auto-refreshes every 30 seconds (configurable in Settings → Advanced)',
          ],
          capabilities: [
            'KPI grid: active agents, running sessions, total cost, task completion rate',
            'Quick actions: spawn an agent, create a project, deploy from library',
            'Live runs panel showing currently executing sessions',
            'Activity feed with real-time SSE streaming',
            'Finance summary: daily spend, budget utilization, cost trends',
            'System health: backend status, adapter connectivity, queue depth',
          ],
          tips: [
            'Click any KPI card to navigate to the related detailed page',
            'Use ⌘1 (Mac) or Ctrl+1 to jump to the dashboard from anywhere',
          ],
        },
        {
          id: 'inbox',
          title: 'Inbox',
          route: '/app/inbox',
          description:
            'The inbox is your bidirectional notification and messaging center. It combines approval requests, system alerts, agent mentions, failure notifications, reports, budget warnings, and Slack messages into a unified feed. Reply directly to messages from the inbox.',
          useCase:
            'Check the inbox when you see a badge count in the sidebar — it means agents need your attention, approvals are pending, Slack messages arrived, or something requires human intervention. Reply inline without leaving the app.',
          configuration: [
            'Filter by type: approval, alert, mention, failure, report, budget_warning, message',
            'Filter by status: unread, read, actioned, dismissed',
            'Tab parameter via URL: ?tab=all|messages|approvals|notifications',
            'Slack integration for inbound/outbound messaging',
          ],
          capabilities: [
            'Approve or reject pending actions with optional comments',
            'Mark individual or all items as read',
            'Dismiss resolved notifications',
            'Badge count shown in sidebar (approvals + unread notifications)',
            'Inline reply composer for responding to messages directly',
            'Slack integration: receive messages from Slack channels and reply back',
            'System event notifications: heartbeat failures, governance approvals, workflow status changes',
            'Real-time SSE streaming for live inbox updates',
            'Source channel indicators (slack, system, agent)',
          ],
          tips: [
            'Use ⌘2 to jump to inbox quickly',
            'Unread items always sort to the top',
            'Messages from Slack show the source channel — replies go back to the same channel',
          ],
        },
        {
          id: 'office',
          title: 'Virtual Office',
          route: '/app/office',
          description:
            'The virtual office is a pixel-art visualization of your workspace. Each agent appears as a character in themed rooms, with real-time status indicators showing what they\'re doing.',
          useCase:
            'Use the office for a spatial, intuitive view of your agent team. It\'s especially useful to quickly see who\'s active, idle, or errored at a glance.',
          configuration: [
            'View mode: 2D pixel art (default) or 3D (experimental)',
            'Time-of-day lighting effects change automatically',
          ],
          capabilities: [
            'Agents rendered as pixel characters in themed rooms',
            'Real-time status: active (green), idle (blue), thinking (yellow), error (red)',
            'Click an agent to view their details and recent activity',
            'Speech bubbles show current task descriptions',
            'Rooms organized by division/team',
          ],
          tips: [
            'Use ⌘3 to jump to the office',
            'Hover over agents to see their name and status',
          ],
        },
      ],
    },
    {
      id: 'work',
      title: 'Work Management',
      icon: 'document-text',
      articles: [
        {
          id: 'projects',
          title: 'Projects',
          route: '/app/projects',
          description:
            'Projects are top-level containers that group goals, issues, agents, sessions, and costs together. They represent distinct workstreams or initiatives within your workspace.',
          useCase:
            'Create a project for each major initiative (e.g., "Website Redesign", "Q4 Marketing Campaign") to keep goals, issues, and agent assignments organized.',
          configuration: [
            'Status filter: all, active, completed, archived',
            'Search by project name',
          ],
          capabilities: [
            'Create projects with name, description, and status',
            'Project detail view with tabs: Overview, Goals, Issues, Agents, Sessions, Costs',
            'Track goal progress and issue resolution per project',
            'View agent assignments and session history scoped to the project',
            'Monitor per-project cost breakdown',
          ],
        },
        {
          id: 'goals',
          title: 'Goals',
          route: '/app/goals',
          description:
            'Goals form a hierarchical tree under each project. They can be decomposed into sub-goals, and each goal can have associated issues. Progress aggregates upward through the tree.',
          useCase:
            'Define high-level objectives, then let agents decompose them into actionable sub-goals. Track progress as issues are completed against each goal.',
          configuration: [
            'Must select a project first — goals are always project-scoped',
            'Filter by status or priority',
          ],
          capabilities: [
            'Hierarchical goal tree with visual nesting',
            'AI-powered decomposition: break a goal into sub-goals automatically',
            'Progress tracking aggregated from child goals and linked issues',
            'Create, update, and delete goals with title, description, status, and priority',
          ],
        },
        {
          id: 'issues',
          title: 'Issues',
          route: '/app/issues',
          description:
            'Issues are discrete work items that can be assigned to agents, linked to goals and projects, tagged with labels, and tracked through a Kanban-style workflow.',
          useCase:
            'Use issues to track bugs, tasks, and feature requests. Agents can be dispatched to work on issues, and you can monitor their progress through the Kanban board.',
          configuration: [
            'View mode: Kanban board, list view, or table view',
            'Filter by status, priority, assignee, and labels',
            'Sort by date, priority, or status',
            'Create via ?new=1 URL parameter',
          ],
          capabilities: [
            'Kanban columns: open, in_progress, review, done, closed',
            'Assign issues to agents for autonomous resolution',
            'Dispatch an issue to have an agent start working on it immediately',
            'Comments thread on each issue',
            'Link issues to goals and projects',
            'Label tagging for categorization',
          ],
        },
        {
          id: 'documents',
          title: 'Documents',
          route: '/app/documents',
          description:
            'Documents is a file tree viewer and editor for workspace documentation. It organizes markdown files into a navigable tree structure with version history.',
          useCase:
            'Use documents to manage SYSTEM.md files, skill definitions, agent prompts, and any workspace documentation that agents read and write.',
          configuration: [
            'File path and content when creating new documents',
          ],
          capabilities: [
            'Tree view of all workspace documents',
            'Create, edit, and delete documents',
            'Version history with revision tracking',
            'Markdown content viewing and editing',
          ],
        },
      ],
    },
    {
      id: 'agents',
      title: 'Agent Management',
      icon: 'robot',
      articles: [
        {
          id: 'agents-roster',
          title: 'Agents Roster',
          route: '/app/agents',
          description:
            'The agents roster shows every agent in your workspace. You can view them in a grid or table layout, filter by status, search by name, and perform lifecycle actions.',
          useCase:
            'Manage your team of AI agents: hire new ones from the library, monitor their status, pause or terminate misbehaving agents, and configure their adapters and skills.',
          configuration: [
            'View mode: grid (card layout) or table (dense list)',
            'Filter by status: all, active, idle, paused, error',
            'Search by agent name',
            'Quick hire via ?hire=1 URL parameter or sidebar button',
          ],
          capabilities: [
            'View all agents with status indicators',
            'Hire individual agents with role-based skill recommendations',
            'Hire teams from templates with automatic skill installation',
            'Skills auto-resolved from agent role (e.g., engineer gets code, debug, test, deploy skills)',
            'Skills preview in hire team dialog showing what will be added',
            'Lifecycle actions: start, pause, resume, terminate',
            'Quick-view agent details by clicking a card',
            'Org hierarchy view link for team structure',
          ],
        },
        {
          id: 'agent-detail',
          title: 'Agent Detail',
          route: '/app/agents/[id]',
          description:
            'The agent detail page is a comprehensive cockpit for a single agent. It has tabs for overview, configuration, schedules, skills, run history, budget, inbox, and access control.',
          useCase:
            'Dive deep into a specific agent to tune their adapter, adjust their model, modify their system prompt, manage their skills, set budget limits, or review their session history.',
          configuration: [
            'Adapter: OSA, Claude Code, Codex, Gemini, Aider, Windsurf, etc.',
            'Model: specific model version (e.g., claude-sonnet-4-20250514)',
            'System prompt and tool configuration',
            'Gateway assignment for API routing',
            'Concurrency limits',
            'Budget policy assignment',
            'Schedule assignment for heartbeat runs',
          ],
          capabilities: [
            'Overview tab: status, token usage, recent sessions, performance metrics',
            'Config tab: adapter, model, tools, prompts, gateway, concurrency',
            'Schedules tab: attached cron schedules and heartbeat runs',
            'Skills tab: enable/disable specific skills for the agent',
            'Runs tab: session history with filtering',
            'Budget tab: spending limits, daily/monthly caps, incident history',
            'Inbox tab: messages and approvals specific to this agent',
            'Access tab: who can manage this agent',
          ],
          tips: [
            'Navigate here from the sidebar agent tree by clicking an agent name',
            'Use the lifecycle buttons in the header to start/pause/terminate',
          ],
        },
        {
          id: 'spawn',
          title: 'Spawn (One-Shot Runs)',
          route: '/app/spawn',
          description:
            'Spawn lets you run a one-off agent task without creating a persistent agent. Choose a preset or configure a custom run, and watch it execute in real-time.',
          useCase:
            'Use spawn for quick ad-hoc tasks: "summarize this document", "fix this bug", "write unit tests" — without deploying a permanent agent.',
          configuration: [
            'Presets for common tasks (summarize, review, generate, etc.)',
            'Optional model override',
            'Custom prompt input',
          ],
          capabilities: [
            'Quick-launch agent tasks from presets',
            'Active instance monitoring with polling',
            'Execution history and cost tracking',
            'Cancel running instances',
          ],
        },
      ],
    },
    {
      id: 'chat',
      title: 'Chat & Conversations',
      icon: 'chat-bubble',
      articles: [
        {
          id: 'chat-page',
          title: 'Chat',
          route: '/app/chat',
          description:
            'Chat provides a conversational interface to interact with your agents. Start a new conversation by selecting an agent, then send messages and receive streaming responses.',
          useCase:
            'Use chat when you want to interactively collaborate with an agent — ask questions, give instructions, review their work, or have a back-and-forth discussion.',
          configuration: [
            'Select which agent to chat with when starting a new conversation',
            'Send with ⌘/Ctrl+Enter',
          ],
          capabilities: [
            'Conversation list sidebar with search',
            'Real-time streaming responses via SSE',
            'Markdown rendering in messages',
            'Thinking/reasoning display for supported models',
            'Tool call visibility showing what the agent is doing',
            'Archive old conversations',
          ],
          tips: [
            'Each conversation is backed by a session, so costs are tracked automatically',
            'The streaming indicator shows token-by-token generation',
          ],
        },
      ],
    },
    {
      id: 'data',
      title: 'Data & Knowledge',
      icon: 'light-bulb',
      articles: [
        {
          id: 'memory',
          title: 'Memory',
          route: '/app/memory',
          description:
            'Memory is BizForge\'s knowledge store. Agents can read from and write to memory, storing facts, procedures, preferences, and context that persists across sessions.',
          useCase:
            'Use memory to give agents persistent knowledge — company policies, coding standards, user preferences, learned procedures. Agents reference memory to make better decisions over time.',
          configuration: [
            'Category tabs: All, Facts, Procedures, Preferences, Context, etc.',
            'Namespace organization for scoped knowledge',
            'Search across all memory entries',
          ],
          capabilities: [
            'Browse all memory entries with category filtering',
            'Full-text search across knowledge base',
            'Namespace management for organizing knowledge domains',
            'Create, update, and delete memory entries',
            'View related entries and knowledge graph connections',
            'Statistics dashboard showing memory utilization',
          ],
        },
        {
          id: 'datasets',
          title: 'Datasets',
          route: '/app/datasets',
          description:
            'Datasets is a registry for structured data sources that agents can access. Register CSV files, database connections, API endpoints, or file directories as datasets.',
          useCase:
            'Register data sources so agents can query and analyze them. Useful for data science workflows, report generation, and any task that needs structured data access.',
          configuration: [
            'Source type: file, database, api, manual',
            'Format: csv, json, parquet, sql, etc.',
            'Name, slug, and description',
            'Agent access grants (which agents can use which datasets)',
          ],
          capabilities: [
            'Dataset registry with metadata',
            'Data preview with row sampling',
            'Access control: grant/revoke per agent',
            'Refresh datasets to pull latest data',
            'Filter by source type',
          ],
        },
        {
          id: 'work-products',
          title: 'Work Products',
          route: '/app/work-products',
          description:
            'Work products are artifacts produced by agents: reports, code files, data analysis results, design documents, and more. They\'re automatically tracked and categorized.',
          useCase:
            'Review what your agents have produced. Filter by type to find specific outputs — code reviews, generated reports, data analyses, or design specs.',
          configuration: [
            'Filter by type: report, code, data, document, analysis, design, other',
            'Search by name or content',
          ],
          capabilities: [
            'Browse all agent-produced artifacts',
            'Type-based categorization and filtering',
            'Expandable detail rows for quick review',
            'Linked to originating agent and session',
          ],
        },
      ],
    },
    {
      id: 'observe',
      title: 'Observability',
      icon: 'chart-bar',
      articles: [
        {
          id: 'activity',
          title: 'Activity Feed',
          route: '/app/activity',
          description:
            'The activity feed shows a real-time stream of everything happening in your workspace: agent actions, session events, errors, warnings, and system notifications.',
          useCase:
            'Monitor your workspace in real-time. The activity feed is your live log of what every agent is doing, filtered by event type and severity.',
          configuration: [
            'Event type filters via ActivityFilters component',
            'Real-time streaming via SSE (Server-Sent Events)',
            'Refresh to reload the full feed',
          ],
          capabilities: [
            'Live event streaming with automatic updates',
            'Filter by event type, agent, severity',
            'Error and warning count badges',
            'Click events to navigate to related sessions or agents',
          ],
        },
        {
          id: 'sessions',
          title: 'Sessions',
          route: '/app/sessions',
          description:
            'Sessions track every agent execution — each heartbeat run, chat conversation, or dispatched task creates a session with a full transcript, token usage, and cost.',
          useCase:
            'Review past and active agent sessions. Inspect transcripts to understand what an agent did, how many tokens it used, and whether it succeeded.',
          configuration: [
            'Tab: sessions list (default) or ?view=logs for log viewer',
            'Filters: agent, status, date range',
            'Log level, source, and agent filtering in logs tab',
          ],
          capabilities: [
            'Session list with status, agent, duration, token count, cost',
            'Session detail: full transcript, execution workspace, session chain',
            'Live streaming for active sessions',
            'Session chain view showing continuation history',
            'Export/replay transcripts',
            'Integrated log viewer with real-time streaming',
          ],
        },
        {
          id: 'costs',
          title: 'Costs',
          route: '/app/costs',
          description:
            'The costs dashboard provides complete visibility into your AI spending — broken down by agent, model, and time period.',
          useCase:
            'Monitor and control AI spending. See which agents and models are most expensive, track daily trends, and set budget policies to prevent overspending.',
          configuration: [
            'Date range: 7 days, 30 days, or 90 days',
            'Budget policies configured in Settings → Budget',
          ],
          capabilities: [
            'Total spend summary with input/output/cache token breakdown',
            'Per-agent cost breakdown',
            'Per-model cost breakdown',
            'Daily trend chart',
            'Budget policy monitoring and incident alerts',
          ],
        },
        {
          id: 'analytics',
          title: 'Analytics',
          route: '/app/analytics',
          description:
            'Analytics provides aggregated metrics across your workspace — session counts, success rates, task completion, and per-agent/team performance.',
          useCase:
            'Use analytics for periodic reviews of team performance. Identify top-performing agents, costly workflows, and overall productivity trends.',
          configuration: [
            'Period toggle: 7 days, 30 days, or 90 days',
          ],
          capabilities: [
            'KPI cards: total sessions, success rate, total cost, tasks completed, active agents',
            'Bar charts for sessions, tasks, cost, agent performance, team metrics',
            'Top performers and highest cost agent identification',
            'ROI calculations',
          ],
        },
        {
          id: 'reports',
          title: 'Reports',
          route: '/app/reports',
          description:
            'Reports lets you define, generate, and export structured reports covering performance, costs, tasks, workflows, or custom criteria.',
          useCase:
            'Generate periodic reports for stakeholders — weekly cost summaries, agent performance reviews, or task completion reports. Schedule them for automatic generation.',
          configuration: [
            'Report type: performance, costs, tasks, workflows, custom',
            'Format: table, chart, PDF, CSV',
            'Schedule: one-time, daily, weekly, monthly, or on-demand',
            'Config: date range, metric toggles per report type',
          ],
          capabilities: [
            'Report builder with type, format, and schedule',
            'On-demand generation with progress tracking',
            'Export to PDF or CSV',
            'Scheduled automatic generation',
            'Report history and versioning',
          ],
        },
        {
          id: 'signals',
          title: 'Signals',
          route: '/app/signals',
          description:
            'Signals is a telemetry system that classifies and tracks behavioral patterns from agent executions — useful for understanding emergent behaviors and anomalies.',
          useCase:
            'Use signals to detect patterns in agent behavior that aren\'t obvious from individual sessions — repeated failures, unusual token usage spikes, or new collaboration patterns.',
          configuration: [
            'Search signals by content',
            'View top patterns and statistics',
          ],
          capabilities: [
            'Signal list with timestamped entries',
            'Pattern detection and top-N ranking',
            'Aggregate statistics (total signals, categories, trends)',
            'Search and filtering',
          ],
        },
      ],
    },
    {
      id: 'automate',
      title: 'Automation',
      icon: 'bolt',
      articles: [
        {
          id: 'skills',
          title: 'Skills',
          route: '/app/skills',
          description:
            'Skills are capabilities that agents can use — tools, integrations, and specialized behaviors. Enable or disable skills workspace-wide, or let them be auto-installed when adding agents, teams, or companies from the library.',
          useCase:
            'Control what your agents can do by toggling skills on and off. Skills are also automatically resolved and installed when hiring agents or deploying teams — the system maps agent roles to required library skills and installs them in bulk.',
          configuration: [
            'Search skills by name',
            'Toggle enable/disable per skill',
            'Per-agent skill overrides available on the agent detail page',
            'Auto-install via library import, hire dialogs, or template deploy',
          ],
          capabilities: [
            'Workspace-wide skill registry',
            'One-click enable/disable toggles',
            'Search and filter skills',
            'Skill descriptions and categories',
            'Library import: install skills directly from the 121-skill library catalog',
            'Bulk enable: re-enable existing disabled skills in one operation',
            'Auto-resolve: skills are automatically determined from agent roles and template declarations',
            'Install from library: skillsStore.installFromLibrary handles import + enable in one call',
          ],
          tips: [
            'Skills are auto-added when you hire agents or deploy teams — no manual setup needed',
            'Disabled skills are re-enabled automatically if a new agent requires them',
          ],
        },
        {
          id: 'workflows',
          title: 'Workflows',
          route: '/app/workflows',
          description:
            'Workflows let you define multi-step automated processes with conditional logic. Each step can assign a task to an agent, check a condition, or perform a system action.',
          useCase:
            'Automate complex processes: "When a new issue is created, assign it to Agent A for triage, if critical then escalate to Agent B, otherwise add to backlog." Workflows replace manual orchestration.',
          configuration: [
            'Trigger type: manual, schedule (cron), webhook, or event-based',
            'Step types: agent_task, condition, transform, notification, approval, wait',
            'Each step can reference an agent and provide context',
          ],
          capabilities: [
            'Visual workflow builder with drag-and-drop steps',
            'Multiple trigger types',
            'Conditional branching logic',
            'Run history with per-step status tracking',
            'Manual trigger for testing',
            'Delete or modify workflows and individual steps',
          ],
        },
        {
          id: 'schedules',
          title: 'Schedules',
          route: '/app/schedules',
          description:
            'Schedules define when agents run their heartbeat cycles. Use cron expressions to set recurring execution patterns — hourly, daily, or custom intervals.',
          useCase:
            'Set up recurring agent tasks: "Run the code reviewer every morning at 9am", "Execute the cost analyzer weekly on Monday", "Heartbeat every 15 minutes for the monitoring agent."',
          configuration: [
            'Agent assignment (which agent runs on this schedule)',
            'Cron expression (with presets: every 15min, hourly, daily 9am, etc.)',
            'Context payload passed to the agent each run',
            'Enable/disable toggle',
          ],
          capabilities: [
            'Timeline view of upcoming runs',
            'Schedule cards with next-run countdown',
            'Run history per schedule',
            'Wakeup queue for pending executions',
            'Trigger immediate execution',
            'Pause/resume individual schedules',
            'Cron presets for common patterns',
          ],
          tips: [
            'Use the "every 15 minutes" preset for monitoring agents',
            'The wakeup queue shows what\'s about to run next',
          ],
        },
        {
          id: 'alerts',
          title: 'Alerts',
          route: '/app/alerts',
          description:
            'Alerts let you define rules that trigger notifications or actions when specific conditions are met — agent errors, budget thresholds, system health issues, or schedule failures.',
          useCase:
            'Set up proactive monitoring: "Alert me when any agent\'s daily cost exceeds $5", "Pause the agent if error rate goes above 10%", "Send a webhook when a schedule fails."',
          configuration: [
            'Entity type: agent, system, schedule, or budget',
            'Field to monitor (e.g., error_rate, cost, status)',
            'Operator: gt, lt, eq, gte, lte',
            'Threshold value',
            'Action: notify, pause, webhook, or email',
            'Enable/disable toggle',
          ],
          capabilities: [
            'Rule-based alert definitions',
            'Multiple entity types and fields',
            'Configurable actions (notify, pause agent, webhook, email)',
            'Enable/disable without deleting',
            'Alert history for past triggers',
          ],
        },
      ],
    },
    {
      id: 'library',
      title: 'Library',
      icon: 'academic-cap',
      articles: [
        {
          id: 'library-page',
          title: 'Agent & Template Library',
          route: '/app/library',
          description:
            'The library is a marketplace-style catalog of pre-built agent templates, skills, team configurations, and company operation blueprints. Browse, search, and deploy with one click. Each entity declares its required skills, which are automatically resolved and installed when you add or deploy.',
          useCase:
            'Use the library to quickly staff your workspace. Instead of configuring agents from scratch, deploy proven templates with pre-configured skills, prompts, and team structures. Skills are auto-resolved — no manual hunting.',
          configuration: [
            'Tabs: Agents, Skills, Teams, Companies',
            'Search with debounced input',
            'Category filters per tab',
            'Sort: name ascending/descending',
            'View mode: grid or list (agents and skills tabs)',
          ],
          capabilities: [
            '157 agent templates across 12+ categories',
            '121 skill catalog entries with one-click import',
            '48 team templates that deploy multiple agents in a configured hierarchy',
            '5 company operation blueprints for entire business units',
            'Auto-resolve skill dependencies — every agent, team, and company declares required_skills',
            'Skills preview modal shows which skills will be added vs. already active before confirming',
            'One-click deploy with automatic agent provisioning and skill installation',
            'Detail pages for agents, skills, teams, and companies with Import/Deploy buttons',
          ],
          tips: [
            'Team templates are the fastest way to get started — they deploy 3-8 agents in one click',
            'Company templates deploy entire organizational units with hierarchy',
            'When adding any entity, a confirmation modal shows exactly which skills will be installed',
            'Skills that are already active in your workspace are shown separately — no duplicates',
          ],
        },
      ],
    },
    {
      id: 'system',
      title: 'System & Configuration',
      icon: 'cog',
      articles: [
        {
          id: 'hierarchy',
          title: 'Organization Hierarchy',
          route: '/app/hierarchy',
          description:
            'The organization hierarchy page shows the full org tree: Organization → Divisions → Departments → Teams → Agents. This mirrors a real company structure and determines reporting lines.',
          useCase:
            'Structure your AI company with divisions (e.g., Engineering, Marketing), departments (e.g., Frontend, Backend), and teams (e.g., Code Review Squad). Agents inherit context from their team placement.',
          configuration: [
            'Create/edit divisions, departments, and teams',
            'Assign agents to teams',
            'Manage team membership (add/remove agents)',
          ],
          capabilities: [
            'Interactive org tree with expand/collapse',
            'Division, department, and team CRUD',
            'Team membership management',
            'Agent assignment to organizational units',
            'Reporting line visualization',
          ],
        },
        {
          id: 'users',
          title: 'Users & Access',
          route: '/app/users',
          description:
            'Users shows all human users registered in BizForge. Combined with the Access page, it provides role-based access control (RBAC) for managing who can do what.',
          useCase:
            'Manage your team\'s access to BizForge. Assign admin, member, or viewer roles. Scope permissions to specific organizations or projects.',
          configuration: [
            'Role filter: all, admin, member, viewer',
            'Search by name or email',
          ],
          capabilities: [
            'User directory with role indicators',
            'User creation and profile editing',
            'Role-based access control (RBAC)',
            'Scope-based permissions: global, organization, or project level',
          ],
        },
        {
          id: 'access',
          title: 'Access Control',
          route: '/app/access',
          description:
            'Access control manages role assignments — who has what permissions and at what scope. Assign roles to users with granular scoping.',
          useCase:
            'Use RBAC to control who can manage agents, approve budgets, modify workflows, or view sensitive data. Essential for team environments.',
          configuration: [
            'Assign role: user ID/name/email, role (admin/member/viewer), scope (global/org/project)',
            'Entity ID for organization or project scoped roles',
          ],
          capabilities: [
            'Role assignment with scope selection',
            'Revoke roles with confirmation',
            'Filter assignments by role',
            'View counts per role type',
          ],
        },
        {
          id: 'integrations',
          title: 'Integrations',
          route: '/app/integrations',
          description:
            'Integrations manages connections to external services, AI adapters, and messaging platforms. Install adapters, check their health, connect Slack for bidirectional messaging, and configure the OSA setup flow.',
          useCase:
            'Connect BizForge to your AI providers, Slack workspace, and external tools. Install the OSA adapter for local model execution, or configure cloud adapters for Claude, GPT, etc.',
          configuration: [
            'Adapters tab: install/health-check AI backends',
            'Integrations tab: connect third-party services',
            'OSA setup flow for local Tauri-based execution',
            'Slack: OAuth install flow, Events API webhook, interactive message buttons',
          ],
          capabilities: [
            'Adapter installation and health monitoring',
            'Integration connect/disconnect',
            'OSA local setup wizard',
            'Status indicators for all connections',
            'Slack integration: OAuth-based installation with bot token management',
            'Slack Events API: receive messages and route to agents',
            'Slack interactive components: approval buttons in messages',
            'Bidirectional Slack messaging: agents send and receive via chat.postMessage',
          ],
        },
        {
          id: 'gateways',
          title: 'Gateways',
          route: '/app/gateways',
          description:
            'Gateways are API routing endpoints that agents use to reach AI models. Define custom endpoints with optional API keys for load balancing or provider switching.',
          useCase:
            'Use gateways to route agent API calls through custom endpoints — a local proxy, a load balancer, or different providers for different agents.',
          configuration: [
            'Name for identification',
            'Endpoint URL',
            'Optional API key for authentication',
          ],
          capabilities: [
            'Gateway creation with endpoint and credentials',
            'Health probing to verify connectivity',
            'Status display (healthy, degraded, offline)',
            'Assign gateways to individual agents via their config',
          ],
        },
        {
          id: 'webhooks',
          title: 'Webhooks',
          route: '/app/webhooks',
          description:
            'Webhooks send HTTP POST notifications to external URLs when events occur in BizForge — agent lifecycle changes, issue updates, schedule completions, etc.',
          useCase:
            'Integrate BizForge with external systems: post to Slack when an agent errors, trigger a CI pipeline when an issue is completed, or log events to a monitoring service.',
          configuration: [
            'Target URL',
            'Event selection: agent.started, agent.stopped, issue.created, schedule.completed, etc.',
            'Auto-generated signing secret for verification',
          ],
          capabilities: [
            'Create webhooks with multi-event subscription',
            'Signing secret for payload verification',
            'Test webhook to verify connectivity',
            'Delivery history and retry status',
          ],
        },
        {
          id: 'plugins',
          title: 'Plugins',
          route: '/app/plugins',
          description:
            'Plugins extend BizForge\'s functionality with custom modules. Browse installed plugins, view their logs, and manage their lifecycle.',
          useCase:
            'Use plugins to add custom behaviors — specialized integrations, data processors, or UI extensions that aren\'t covered by built-in features.',
          configuration: [
            'Plugin JSON configuration',
            'Enable/disable per plugin',
          ],
          capabilities: [
            'Plugin registry with status indicators',
            'Log viewer per plugin for debugging',
            'Create plugins with JSON config',
            'Enable/disable without removal',
          ],
        },
        {
          id: 'secrets',
          title: 'Secrets',
          route: '/app/secrets',
          description:
            'Secrets is a vault for storing sensitive credentials — API keys, tokens, passwords, and certificates. Agents can reference secrets by name without seeing raw values.',
          useCase:
            'Store API keys and credentials securely. Agents reference secrets by name in their configuration, and BizForge injects the values at runtime without exposing them in logs.',
          configuration: [
            'Secret types: api_key, password, token, certificate, other',
            'Name and value (value hidden after creation)',
          ],
          capabilities: [
            'Secure storage with masked display',
            'Secret rotation with confirmation',
            'Expiration tracking and warnings',
            'Type categorization for organization',
          ],
        },
        {
          id: 'environment',
          title: 'Environment',
          route: '/app/environment',
          description:
            'Environment shows the detected local runtime: installed applications, system resources, and agent capabilities on the host machine.',
          useCase:
            'Check what tools and resources are available on your machine for agents to use — Git, Node, Python, Docker, etc. Grant or revoke agent access to specific applications.',
          configuration: [
            'Access grants per agent per application',
          ],
          capabilities: [
            'Detected applications and tools inventory',
            'System resource monitoring (CPU, memory, disk)',
            'Capability detection',
            'Per-agent application access grants',
          ],
        },
        {
          id: 'execution-workspaces',
          title: 'Execution Workspaces',
          route: '/app/execution-workspaces',
          description:
            'Execution workspaces are sandboxed directories where agents perform their work — isolated git repos, temp directories, or project checkouts.',
          useCase:
            'Manage the sandboxed environments agents use for code execution. Each agent can have its own workspace to prevent conflicts.',
          configuration: [
            'Optional agent assignment',
            'Directory path',
          ],
          capabilities: [
            'Create sandboxed workspaces for agents',
            'View disk usage and status',
            'Link workspaces to specific agents',
            'Delete to clean up resources',
          ],
        },
        {
          id: 'audit',
          title: 'Audit Log',
          route: '/app/audit',
          description:
            'The audit log is a compliance-grade record of every action taken in BizForge — who did what, when, and from where.',
          useCase:
            'Review the audit log for compliance, debugging, or security investigations. Every user and agent action is recorded with timestamps and IP addresses.',
          configuration: [
            'Search by action, actor, or entity',
            'Paginated loading with "load more"',
          ],
          capabilities: [
            'Timestamped action records',
            'Actor identification (user or agent)',
            'Action type categorization',
            'Entity tracking (what was affected)',
            'IP address logging',
            'Searchable and paginated',
          ],
        },
        {
          id: 'settings',
          title: 'Settings',
          route: '/app/settings',
          description:
            'Settings is the central configuration hub with tabs for General, Appearance, Agents, Budget, Notifications, Integrations, and Advanced preferences.',
          useCase:
            'Configure BizForge to your preferences: set default adapters, appearance themes, agent limits, budget policies, notification channels, and advanced system options.',
          configuration: [
            'General: working directory, default adapter, default model, session settings, logout',
            'Appearance: theme (dark, light, glass, color, system), font size, sidebar width',
            'Agents: auto-approve budget threshold, max concurrent agents, session timeout, default system prompt',
            'Budget: daily/monthly spending limits, warning threshold percentage, hard stop toggle',
            'Notifications: channel preferences, event toggles',
            'Integrations: integration-specific settings',
            'Advanced: log level, telemetry, retention, cache clearing, settings export/import, reset defaults',
          ],
          capabilities: [
            'Persistent settings across sessions (Tauri store + localStorage)',
            'Budget policy management with incident monitoring',
            'Theme customization with live preview',
            'Settings export/import as JSON',
            'Reset to defaults per section',
            'Keyboard shortcut: ⌘, (Cmd+comma)',
          ],
        },
      ],
    },
    {
      id: 'headless',
      title: 'Headless Mode',
      icon: 'command-line',
      articles: [
        {
          id: 'headless-overview',
          title: 'Headless Mode Overview',
          description:
            'Headless mode lets you run any configured BizForge workspace fully autonomously via CLI — no desktop GUI required. Set up your workspace using the Command Center, then deploy it headlessly. Agents execute on their heartbeat schedules, tasks flow, budgets enforce, and governance gates fire with zero human interaction.',
          useCase:
            'Use headless mode for production deployments, CI/CD pipelines, server-based execution, or any scenario where you want agents to run autonomously without a GUI. Configure everything in the Command Center first, then switch to headless for unattended operation.',
          configuration: [
            'BIZFORGE_HEADLESS=true — enable headless mode',
            'BIZFORGE_WORKSPACE_PATH — path to workspace directory',
            'BIZFORGE_HEALTH_PORT — health check port (default: 9090)',
            'BIZFORGE_PID_DIR — PID file directory (default: .bizforge/pids)',
            'BIZFORGE_LOG_FORMAT — log format: text or json',
          ],
          capabilities: [
            'Full CLI with run, stop, status, logs, pause, resume commands',
            'Workspace validation before boot (checks SYSTEM.md, company.yaml, agents/)',
            'Automatic agent bootstrap — discovers and starts all scheduled agents on boot',
            'Watchdog process — detects stuck/crashed agents and recovers with exponential backoff',
            'Signal handling — SIGTERM triggers graceful shutdown with session compaction',
            'SIGHUP triggers configuration reload',
            'PID file management for process tracking',
            'Workspace snapshots — serialize, list, and restore workspace state',
            '--dry-run flag to validate without executing',
            '--detach flag for background daemon mode',
            'Just recipes: just headless, just headless-stop, just headless-status',
          ],
          tips: [
            'Always run "bizforge config validate" before deploying headlessly',
            'Use "bizforge snapshot create" to save workspace state before modifications',
            'The watchdog will auto-recover crashed agents up to 10 times with exponential backoff',
            'SIGTERM triggers graceful shutdown — all active sessions are compacted before exit',
          ],
        },
        {
          id: 'headless-cli',
          title: 'CLI Reference',
          description:
            'The BizForge CLI provides full control over headless workspace execution. All commands are available via the "bizforge" binary (Mix release) or through corresponding "just" recipes for development.',
          useCase:
            'Use the CLI to manage headless instances from the terminal. Start, stop, monitor, and configure workspaces without opening the desktop application.',
          configuration: [
            'bizforge run <workspace-path> — boot and start all heartbeats',
            'bizforge stop — graceful shutdown with session compaction',
            'bizforge status — print running agents, tasks, budget usage',
            'bizforge logs [-f] [-l level] [-a agent] — tail activity logs',
            'bizforge pause / resume — control heartbeat schedules',
            'bizforge config show [path] — display workspace config',
            'bizforge config validate [path] — validate workspace files',
            'bizforge snapshot create <name> — create workspace snapshot',
            'bizforge snapshot list — list available snapshots',
            'bizforge snapshot restore <name> — restore from snapshot',
            'bizforge list — show all running instances',
            'bizforge monitor — open stats dashboard',
          ],
          capabilities: [
            'OptionParser-based argument handling with short aliases',
            '--detach (-d) flag for background daemon mode',
            '--dry-run (-n) flag for validation without execution',
            '--monitor (-m) flag to open stats dashboard alongside run',
            '--port (-p) flag to override backend port',
            '--health-port flag to override health check port',
            '--env flag to specify custom .env file path',
            'Log filtering by level and agent name',
          ],
        },
        {
          id: 'headless-architecture',
          title: 'Headless Architecture',
          description:
            'In headless mode, the OTP supervision tree boots three specialized processes instead of the Phoenix HTTP endpoint: Monitor (lifecycle management), Bootstrap (agent auto-start), and Watchdog (crash recovery). The core infrastructure — Repo, BudgetEnforcer, PubSub, Scheduler, HeartbeatRunner, TaskSupervisor, Workflows — remains identical to GUI mode.',
          useCase:
            'Understand the headless architecture to debug issues, extend the system, or build integrations with the headless runtime.',
          configuration: [
            'Headless.Monitor — PID file, signal handling, graceful shutdown',
            'Headless.Bootstrap — agent discovery, schedule registration, adapter health check',
            'Headless.Watchdog — stuck agent detection (10min threshold), error recovery (exponential backoff)',
          ],
          capabilities: [
            'Conditional boot: application.ex checks BIZFORGE_HEADLESS to choose children',
            'Monitor writes PID file, handles SIGTERM/SIGHUP, compacts sessions on shutdown',
            'Bootstrap runs 3s after boot, loads agents and schedules, prints boot summary',
            'Watchdog checks every 60s for stuck agents (>10min in "working") and errored agents',
            'Crash recovery uses quadratic backoff: attempt^2 * 30s, capped at 1 hour, max 10 retries',
            'Full OTP supervision — if any headless process crashes, the supervisor restarts it',
          ],
        },
        {
          id: 'stats-dashboard',
          title: 'Stats Dashboard',
          description:
            'The stats dashboard is a secret, minimal monitoring window for headless workspaces. It provides real-time observability into agent activity, token burn, budget usage, and system health — without any editing or navigation capabilities. Pure read-only monitoring.',
          useCase:
            'Open the stats dashboard when you want visual monitoring of a headless workspace. It connects to the running instance and shows live data in an information-dense, dark-themed single window.',
          configuration: [
            'Launch via "bizforge monitor" or "bizforge run --monitor"',
            'Accessible at /monitor route in the Tauri app',
            'Auto-connects to running headless instance via health port',
          ],
          capabilities: [
            'System health overview (CPU, memory, uptime, active processes)',
            'Agent activity panel (active, idle, paused, errored with current task)',
            'Real-time task flow visualization',
            'Token/cost burn rate graph (per-agent and aggregate)',
            'Budget gauge (per-agent and workspace-level)',
            'Heartbeat timeline (visual execution history)',
            'Scrolling, filterable log stream',
            'Alert panel (governance blocks, budget breaches, adapter failures)',
            'Quick-action controls (pause all, resume all, stop, force-compact)',
            'Keyboard shortcuts for panel navigation',
          ],
          tips: [
            'The stats dashboard is planned as a Tauri window at /monitor',
            'It is read-only by design — no workspace modifications from the dashboard',
          ],
        },
      ],
    },
    {
      id: 'shortcuts',
      title: 'Keyboard Shortcuts',
      icon: 'command-line',
      articles: [
        {
          id: 'keyboard-shortcuts',
          title: 'All Keyboard Shortcuts',
          description:
            'BizForge supports keyboard shortcuts for fast navigation and common actions.',
          useCase:
            'Learn these shortcuts to navigate BizForge without reaching for the mouse.',
          configuration: [],
          capabilities: [
            '⌘K / Ctrl+K — Open command palette (search everything)',
            '⌘\\ / Ctrl+\\ — Toggle sidebar collapse',
            '⌘, / Ctrl+, — Open Settings',
            '⌘T / Ctrl+T — Open Terminal',
            '⌘1 / Ctrl+1 — Go to Dashboard',
            '⌘2 / Ctrl+2 — Go to Inbox',
            '⌘3 / Ctrl+3 — Go to Virtual Office',
            '⌘/Ctrl+Enter — Send message in Chat',
          ],
        },
      ],
    },
  ];

  let activeSection = $state(SECTIONS[0].id);
  let activeArticle = $state(SECTIONS[0].articles[0].id);
  let searchQuery = $state('');

  const flatArticles = $derived(
    SECTIONS.flatMap((s) =>
      s.articles.map((a) => ({ ...a, sectionId: s.id, sectionTitle: s.title })),
    ),
  );

  const filteredArticles = $derived(
    searchQuery.trim().length === 0
      ? flatArticles
      : flatArticles.filter(
          (a) =>
            a.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
            a.description.toLowerCase().includes(searchQuery.toLowerCase()),
        ),
  );

  const currentArticle = $derived(
    flatArticles.find((a) => a.id === activeArticle) ?? flatArticles[0],
  );

  function selectArticle(sectionId: string, articleId: string): void {
    activeSection = sectionId;
    activeArticle = articleId;
    searchQuery = '';
  }

  function handleSearchSelect(articleId: string): void {
    const match = flatArticles.find((a) => a.id === articleId);
    if (match) {
      selectArticle(match.sectionId, articleId);
    }
  }

  $effect(() => {
    const hash = $page.url.hash.replace('#', '');
    if (hash) {
      const match = flatArticles.find((a) => a.id === hash);
      if (match) selectArticle(match.sectionId, match.id);
    }
  });
</script>

<PageShell title="Wiki" subtitle="BizForge Feature Guide">
  <div class="wiki-layout">
    <!-- Sidebar TOC -->
    <nav class="wiki-nav" aria-label="Wiki navigation">
      <div class="wiki-search">
        <svg class="wiki-search-icon" viewBox="0 0 20 20" fill="currentColor" width="16" height="16">
          <path fill-rule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clip-rule="evenodd" />
        </svg>
        <input
          type="text"
          placeholder="Search features…"
          autocomplete="off"
          bind:value={searchQuery}
        />
      </div>

      {#if searchQuery.trim().length > 0}
        <div class="wiki-search-results">
          {#each filteredArticles as article (article.id)}
            <button
              class="wiki-search-hit"
              onclick={() => handleSearchSelect(article.id)}
            >
              <span class="wiki-search-hit-title">{article.title}</span>
              <span class="wiki-search-hit-section">{article.sectionTitle}</span>
            </button>
          {:else}
            <div class="wiki-search-empty">No results found</div>
          {/each}
        </div>
      {:else}
        {#each SECTIONS as section (section.id)}
          <div class="wiki-nav-section">
            <button
              class="wiki-nav-heading"
              class:active={activeSection === section.id}
              onclick={() => { activeSection = section.id; activeArticle = section.articles[0].id; }}
            >
              <span class="wiki-nav-icon"><AgentIcon value={section.icon} size={18} /></span>
              {section.title}
            </button>
            {#if activeSection === section.id}
              <ul class="wiki-nav-list">
                {#each section.articles as article (article.id)}
                  <li>
                    <button
                      class="wiki-nav-item"
                      class:active={activeArticle === article.id}
                      onclick={() => selectArticle(section.id, article.id)}
                    >
                      {article.title}
                    </button>
                  </li>
                {/each}
              </ul>
            {/if}
          </div>
        {/each}
      {/if}
    </nav>

    <!-- Article Content -->
    <article class="wiki-article">
      {#if currentArticle}
        <h2 class="wiki-article-title">{currentArticle.title}</h2>

        {#if currentArticle.route}
          <a class="wiki-route-link" href={currentArticle.route}>
            <svg viewBox="0 0 20 20" fill="currentColor" width="14" height="14">
              <path fill-rule="evenodd" d="M12.586 4.586a2 2 0 112.828 2.828l-3 3a2 2 0 01-2.828 0 1 1 0 00-1.414 1.414 4 4 0 005.656 0l3-3a4 4 0 00-5.656-5.656l-1.5 1.5a1 1 0 101.414 1.414l1.5-1.5zm-5 5a2 2 0 012.828 0 1 1 0 101.414-1.414 4 4 0 00-5.656 0l-3 3a4 4 0 105.656 5.656l1.5-1.5a1 1 0 10-1.414-1.414l-1.5 1.5a2 2 0 11-2.828-2.828l3-3z" clip-rule="evenodd" />
            </svg>
            Open {currentArticle.title}
          </a>
        {/if}

        <section class="wiki-section">
          <h3>Overview</h3>
          <p>{currentArticle.description}</p>
        </section>

        <section class="wiki-section">
          <h3>Use Case</h3>
          <p>{currentArticle.useCase}</p>
        </section>

        {#if currentArticle.capabilities.length > 0}
          <section class="wiki-section">
            <h3>Capabilities</h3>
            <ul class="wiki-list">
              {#each currentArticle.capabilities as cap}
                <li>{cap}</li>
              {/each}
            </ul>
          </section>
        {/if}

        {#if currentArticle.configuration.length > 0}
          <section class="wiki-section">
            <h3>Configuration</h3>
            <ul class="wiki-list wiki-list--config">
              {#each currentArticle.configuration as cfg}
                <li>{cfg}</li>
              {/each}
            </ul>
          </section>
        {/if}

        {#if currentArticle.tips && currentArticle.tips.length > 0}
          <section class="wiki-section wiki-tips">
            <h3>Tips</h3>
            <ul class="wiki-list">
              {#each currentArticle.tips as tip}
                <li>{tip}</li>
              {/each}
            </ul>
          </section>
        {/if}
      {/if}
    </article>
  </div>
</PageShell>

<style>
  .wiki-layout {
    display: flex;
    gap: 0;
    height: 100%;
    overflow: hidden;
  }

  /* ── Navigation Sidebar ───────────────────────────────────────────────── */

  .wiki-nav {
    width: 260px;
    min-width: 260px;
    border-right: 1px solid var(--border-default);
    overflow-y: auto;
    padding: 16px 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .wiki-search {
    display: flex;
    align-items: center;
    gap: 8px;
    margin: 0 12px 12px;
    padding: 6px 10px;
    background: var(--bg-elevated, #1e2433);
    border: 1px solid var(--border-default);
    border-radius: 6px;
  }

  .wiki-search-icon {
    color: var(--text-tertiary);
    flex-shrink: 0;
  }

  .wiki-search input {
    background: transparent;
    border: none;
    outline: none;
    color: var(--text-primary);
    font-size: 13px;
    width: 100%;
  }

  .wiki-search input::placeholder {
    color: var(--text-tertiary);
  }

  .wiki-search-results {
    display: flex;
    flex-direction: column;
    padding: 0 8px;
    gap: 2px;
  }

  .wiki-search-hit {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 8px 10px;
    border: none;
    background: transparent;
    border-radius: 6px;
    cursor: pointer;
    text-align: left;
  }

  .wiki-search-hit:hover {
    background: var(--bg-elevated, #262e3f);
  }

  .wiki-search-hit-title {
    font-size: 13px;
    font-weight: 500;
    color: var(--text-primary);
  }

  .wiki-search-hit-section {
    font-size: 11px;
    color: var(--text-tertiary);
  }

  .wiki-search-empty {
    padding: 16px 12px;
    font-size: 13px;
    color: var(--text-tertiary);
    text-align: center;
  }

  .wiki-nav-section {
    margin-bottom: 2px;
  }

  .wiki-nav-heading {
    display: flex;
    align-items: center;
    gap: 8px;
    width: 100%;
    padding: 7px 16px;
    border: none;
    background: transparent;
    color: var(--text-secondary);
    font-size: 12px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    cursor: pointer;
    border-radius: 0;
    transition: color 0.15s;
  }

  .wiki-nav-heading:hover {
    color: var(--text-primary);
  }

  .wiki-nav-heading.active {
    color: var(--text-primary);
  }

  .wiki-nav-icon {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 18px;
    flex-shrink: 0;
    color: inherit;
  }

  .wiki-nav-heading .wiki-nav-icon :global(.agent-icon) {
    color: var(--text-secondary);
  }

  .wiki-nav-heading:hover .wiki-nav-icon :global(.agent-icon),
  .wiki-nav-heading.active .wiki-nav-icon :global(.agent-icon) {
    color: var(--text-primary);
  }

  .wiki-nav-list {
    list-style: none;
    margin: 0;
    padding: 0 0 4px;
  }

  .wiki-nav-item {
    display: block;
    width: 100%;
    padding: 5px 16px 5px 42px;
    border: none;
    background: transparent;
    color: var(--text-tertiary);
    font-size: 13px;
    text-align: left;
    cursor: pointer;
    border-radius: 0;
    transition: color 0.12s, background 0.12s;
  }

  .wiki-nav-item:hover {
    color: var(--text-primary);
    background: var(--bg-elevated, #262e3f);
  }

  .wiki-nav-item.active {
    color: #f26522;
    font-weight: 500;
    background: color-mix(in srgb, #f26522 8%, transparent);
  }

  /* ── Article ──────────────────────────────────────────────────────────── */

  .wiki-article {
    flex: 1;
    overflow-y: auto;
    padding: 28px 36px 48px;
    min-width: 0;
  }

  .wiki-article-title {
    font-size: 22px;
    font-weight: 700;
    color: var(--text-primary);
    margin: 0 0 12px;
  }

  .wiki-route-link {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 4px 12px;
    border-radius: 6px;
    font-size: 12px;
    font-weight: 500;
    color: #f26522;
    background: color-mix(in srgb, #f26522 10%, transparent);
    text-decoration: none;
    margin-bottom: 20px;
    transition: background 0.15s;
  }

  .wiki-route-link:hover {
    background: color-mix(in srgb, #f26522 18%, transparent);
  }

  .wiki-section {
    margin-bottom: 24px;
  }

  .wiki-section h3 {
    font-size: 14px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0 0 8px;
    padding-bottom: 6px;
    border-bottom: 1px solid var(--border-default);
  }

  .wiki-section p {
    font-size: 14px;
    line-height: 1.65;
    color: var(--text-secondary);
    margin: 0;
  }

  .wiki-list {
    margin: 0;
    padding: 0 0 0 18px;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .wiki-list li {
    font-size: 13px;
    line-height: 1.55;
    color: var(--text-secondary);
  }

  .wiki-list li::marker {
    color: var(--text-tertiary);
  }

  .wiki-list--config li::marker {
    color: #f26522;
  }

  .wiki-tips {
    padding: 14px 16px;
    background: color-mix(in srgb, #f26522 6%, transparent);
    border: 1px solid color-mix(in srgb, #f26522 15%, transparent);
    border-radius: 8px;
  }

  .wiki-tips h3 {
    border-bottom-color: color-mix(in srgb, #f26522 20%, transparent);
    color: #f26522;
  }

  /* ── Scrollbar ────────────────────────────────────────────────────────── */

  .wiki-nav::-webkit-scrollbar,
  .wiki-article::-webkit-scrollbar {
    width: 5px;
  }

  .wiki-nav::-webkit-scrollbar-track,
  .wiki-article::-webkit-scrollbar-track {
    background: transparent;
  }

  .wiki-nav::-webkit-scrollbar-thumb,
  .wiki-article::-webkit-scrollbar-thumb {
    background: var(--border-default);
    border-radius: 3px;
  }

  /* ── Responsive ───────────────────────────────────────────────────────── */

  @media (max-width: 700px) {
    .wiki-layout {
      flex-direction: column;
    }

    .wiki-nav {
      width: 100%;
      min-width: 0;
      max-height: 220px;
      border-right: none;
      border-bottom: 1px solid var(--border-default);
    }

    .wiki-article {
      padding: 20px 16px 40px;
    }
  }
</style>
