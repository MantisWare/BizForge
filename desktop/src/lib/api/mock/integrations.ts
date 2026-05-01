import type { Integration, IntegrationCategory, Adapter } from "../types";

let mockIntegrationState: Integration[] | null = null;

function getIntegrationState(): Integration[] {
  if (mockIntegrationState === null) {
    mockIntegrationState = structuredClone(SEED_INTEGRATIONS);
  }
  return mockIntegrationState;
}

const SEED_INTEGRATIONS: Integration[] = [
  // ── AI Providers & Auth ─────────────────────────────────────────────────────
  {
    id: "int-anthropic",
    name: "Anthropic",
    category: "auth",
    provider: "anthropic",
    description:
      "Connect your Anthropic account to power agents with Claude models. Enables direct API access for all agent interactions, code generation, and reasoning tasks.",
    features: [
      "Claude Opus / Sonnet / Haiku",
      "Tool use & function calling",
      "200k context window",
      "Vision & multimodal",
    ],
    icon_url: null,
    status: "connected",
    config: { api_key_set: true, default_model: "claude-opus-4-6" },
    docs_url: "https://docs.anthropic.com",
    last_sync_at: "2026-03-21T08:00:00Z",
    created_at: "2026-03-01T00:00:00Z",
  },
  {
    id: "int-openai",
    name: "OpenAI",
    category: "auth",
    provider: "openai",
    description:
      "Connect OpenAI to access GPT-4o, o3, and embedding models. Use for agents that need strong general reasoning, coding, or image understanding.",
    features: [
      "GPT-4o & o3 reasoning",
      "Function calling & JSON mode",
      "Embeddings API",
      "DALL-E image gen",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: "https://platform.openai.com/docs",
    last_sync_at: null,
    created_at: "2026-03-01T00:00:00Z",
  },

  // ── Version Control ─────────────────────────────────────────────────────────
  {
    id: "int-github",
    name: "GitHub",
    category: "version_control",
    provider: "github",
    description:
      "Sync repositories, pull requests, and issues. Agents can commit code, review PRs, manage issues, and trigger CI workflows through the GitHub API.",
    features: [
      "Repository sync",
      "PR review & merge",
      "Issue management",
      "Actions & CI triggers",
      "Code search",
    ],
    icon_url: null,
    status: "connected",
    config: { org: "Miosa-osa", default_branch: "main" },
    docs_url: "https://docs.github.com",
    last_sync_at: "2026-03-21T07:45:00Z",
    created_at: "2026-03-01T00:00:00Z",
  },
  {
    id: "int-gitlab",
    name: "GitLab",
    category: "version_control",
    provider: "gitlab",
    description:
      "Connect GitLab for repository management, merge requests, and CI/CD pipeline integration. Supports both self-hosted and SaaS instances.",
    features: [
      "Merge request automation",
      "Pipeline triggers",
      "Container registry",
      "Issue boards",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: "https://docs.gitlab.com",
    last_sync_at: null,
    created_at: "2026-03-01T00:00:00Z",
  },

  // ── Communication ───────────────────────────────────────────────────────────
  {
    id: "int-slack",
    name: "Slack",
    category: "communication",
    provider: "slack",
    description:
      "Send agent updates, alerts, and reports to Slack channels. Agents can receive commands via slash commands and respond to mentions in real-time.",
    features: [
      "Channel notifications",
      "Slash commands",
      "Thread replies",
      "File uploads",
      "Interactive blocks",
    ],
    icon_url: null,
    status: "connected",
    config: { workspace: "miosa", default_channel: "#agents" },
    docs_url: "https://api.slack.com",
    last_sync_at: "2026-03-21T08:10:00Z",
    created_at: "2026-03-05T00:00:00Z",
  },
  {
    id: "int-discord",
    name: "Discord",
    category: "communication",
    provider: "discord",
    description:
      "Integrate agents with Discord servers. Post updates, respond to commands, and manage channels for team coordination and community engagement.",
    features: [
      "Bot commands",
      "Channel messages",
      "Embed rich content",
      "Thread management",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: "https://discord.com/developers/docs",
    last_sync_at: null,
    created_at: "2026-03-10T00:00:00Z",
  },
  {
    id: "int-email",
    name: "Email (SMTP)",
    category: "communication",
    provider: "smtp",
    description:
      "Send and receive emails through your mail server. Agents can compose reports, send notifications, and process incoming mail for task creation.",
    features: [
      "Send & receive emails",
      "HTML templates",
      "Attachment handling",
      "Inbox monitoring",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: null,
    last_sync_at: null,
    created_at: "2026-03-10T00:00:00Z",
  },

  // ── Project Management ──────────────────────────────────────────────────────
  {
    id: "int-linear",
    name: "Linear",
    category: "project_management",
    provider: "linear",
    description:
      "Sync issues, projects, and cycles from Linear. Agents can create tickets, update status, assign work, and track sprint progress automatically.",
    features: [
      "Issue sync",
      "Cycle tracking",
      "Label & priority management",
      "Webhook events",
      "GraphQL API",
    ],
    icon_url: null,
    status: "connected",
    config: { team_id: "MIOSA", sync_issues: true },
    docs_url: "https://linear.app/docs",
    last_sync_at: "2026-03-21T06:00:00Z",
    created_at: "2026-03-07T00:00:00Z",
  },
  {
    id: "int-jira",
    name: "Jira",
    category: "project_management",
    provider: "atlassian",
    description:
      "Connect Atlassian Jira for enterprise issue tracking. Agents can create and update tickets, transition statuses, and manage sprints and backlogs.",
    features: [
      "Issue CRUD",
      "Sprint management",
      "JQL queries",
      "Workflow transitions",
      "Custom fields",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: "https://developer.atlassian.com/cloud/jira/platform/rest/v3/",
    last_sync_at: null,
    created_at: "2026-03-10T00:00:00Z",
  },
  {
    id: "int-asana",
    name: "Asana",
    category: "project_management",
    provider: "asana",
    description:
      "Manage tasks, projects, and portfolios in Asana. Agents can create tasks, update assignees, track deadlines, and maintain project timelines.",
    features: [
      "Task creation & updates",
      "Project timelines",
      "Custom fields",
      "Webhook subscriptions",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: "https://developers.asana.com",
    last_sync_at: null,
    created_at: "2026-03-10T00:00:00Z",
  },

  // ── Storage & Documents ─────────────────────────────────────────────────────
  {
    id: "int-notion",
    name: "Notion",
    category: "storage",
    provider: "notion",
    description:
      "Read and write Notion pages, databases, and wikis. Agents can research knowledge bases, create documentation, and sync structured data bidirectionally.",
    features: [
      "Page read/write",
      "Database queries",
      "Block manipulation",
      "Search across workspace",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: "https://developers.notion.com",
    last_sync_at: null,
    created_at: "2026-03-10T00:00:00Z",
  },
  {
    id: "int-confluence",
    name: "Confluence",
    category: "storage",
    provider: "atlassian",
    description:
      "Access and manage Confluence spaces, pages, and templates. Agents can publish documentation, search knowledge bases, and maintain team wikis.",
    features: [
      "Page CRUD",
      "Space management",
      "Template rendering",
      "CQL search",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: "https://developer.atlassian.com/cloud/confluence/rest/v2/",
    last_sync_at: null,
    created_at: "2026-03-10T00:00:00Z",
  },
  {
    id: "int-google-drive",
    name: "Google Drive",
    category: "storage",
    provider: "google",
    description:
      "Connect Google Drive to read, create, and share files. Agents can generate documents, spreadsheets, and presentations, or ingest files for processing.",
    features: [
      "File upload & download",
      "Docs/Sheets/Slides creation",
      "Permission management",
      "Full-text search",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: "https://developers.google.com/drive",
    last_sync_at: null,
    created_at: "2026-03-10T00:00:00Z",
  },
  {
    id: "int-s3",
    name: "Amazon S3",
    category: "storage",
    provider: "aws",
    description:
      "Store and retrieve files from S3 buckets. Useful for agent-generated artifacts, backups, data lake integration, and large file handling.",
    features: [
      "Bucket management",
      "Object upload/download",
      "Presigned URLs",
      "Lifecycle policies",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: "https://docs.aws.amazon.com/s3/",
    last_sync_at: null,
    created_at: "2026-03-10T00:00:00Z",
  },

  // ── CI/CD & Deployment ──────────────────────────────────────────────────────
  {
    id: "int-vercel",
    name: "Vercel",
    category: "ci_cd",
    provider: "vercel",
    description:
      "Deploy and manage projects on Vercel. Agents can trigger deployments, check build status, manage environment variables, and roll back releases.",
    features: [
      "Auto deployments",
      "Preview URLs",
      "Environment variables",
      "Serverless functions",
      "Edge config",
    ],
    icon_url: null,
    status: "connected",
    config: { team_slug: "miosa", auto_deploy: true },
    docs_url: "https://vercel.com/docs",
    last_sync_at: "2026-03-21T05:30:00Z",
    created_at: "2026-03-03T00:00:00Z",
  },
  {
    id: "int-netlify",
    name: "Netlify",
    category: "ci_cd",
    provider: "netlify",
    description:
      "Deploy sites and serverless functions on Netlify. Agents can trigger builds, manage DNS, configure redirects, and monitor deploy logs.",
    features: [
      "Site deployments",
      "Serverless functions",
      "Form handling",
      "Split testing",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: "https://docs.netlify.com",
    last_sync_at: null,
    created_at: "2026-03-10T00:00:00Z",
  },
  {
    id: "int-docker",
    name: "Docker Hub",
    category: "ci_cd",
    provider: "docker",
    description:
      "Pull and push container images. Agents can manage registries, trigger image builds, and coordinate container-based deployment pipelines.",
    features: [
      "Image pull/push",
      "Automated builds",
      "Vulnerability scanning",
      "Webhook triggers",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: "https://docs.docker.com",
    last_sync_at: null,
    created_at: "2026-03-10T00:00:00Z",
  },

  // ── Monitoring & Observability ──────────────────────────────────────────────
  {
    id: "int-sentry",
    name: "Sentry",
    category: "monitoring",
    provider: "sentry",
    description:
      "Monitor application errors and performance. Agents can query error trends, resolve issues, and correlate exceptions with recent deployments.",
    features: [
      "Error tracking",
      "Performance monitoring",
      "Release tracking",
      "Issue assignment",
      "Alert rules",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: "https://docs.sentry.io",
    last_sync_at: null,
    created_at: "2026-03-10T00:00:00Z",
  },
  {
    id: "int-datadog",
    name: "Datadog",
    category: "monitoring",
    provider: "datadog",
    description:
      "Collect metrics, traces, and logs from your infrastructure. Agents can query dashboards, create monitors, and respond to alerts automatically.",
    features: [
      "Infrastructure metrics",
      "APM traces",
      "Log management",
      "Synthetic monitoring",
      "Incident management",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: "https://docs.datadoghq.com",
    last_sync_at: null,
    created_at: "2026-03-10T00:00:00Z",
  },
  {
    id: "int-pagerduty",
    name: "PagerDuty",
    category: "monitoring",
    provider: "pagerduty",
    description:
      "Manage on-call schedules and incident response. Agents can trigger, acknowledge, and resolve incidents, and escalate to the right responders.",
    features: [
      "Incident triggers",
      "Escalation policies",
      "On-call schedules",
      "Event routing",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: "https://developer.pagerduty.com",
    last_sync_at: null,
    created_at: "2026-03-10T00:00:00Z",
  },

  // ── Analytics & Data ────────────────────────────────────────────────────────
  {
    id: "int-posthog",
    name: "PostHog",
    category: "analytics",
    provider: "posthog",
    description:
      "Product analytics, feature flags, and session replay. Agents can query funnels, analyze user behavior, and toggle feature flags programmatically.",
    features: [
      "Event analytics",
      "Feature flags",
      "Session replay",
      "A/B testing",
      "Data pipelines",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: "https://posthog.com/docs",
    last_sync_at: null,
    created_at: "2026-03-10T00:00:00Z",
  },
  {
    id: "int-domo",
    name: "Domo",
    category: "analytics",
    provider: "domo",
    description:
      "Connect to the Domo BI platform for dashboards, datasets, and data pipelines. Agents can query datasets, manage ETL flows, and embed analytics.",
    features: [
      "Dataset management",
      "Dashboard embedding",
      "Magic ETL pipelines",
      "Code Engine functions",
      "AppDB collections",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: "https://developer.domo.com",
    last_sync_at: null,
    created_at: "2026-03-10T00:00:00Z",
  },

  // ── Design & Creative ───────────────────────────────────────────────────────
  {
    id: "int-figma",
    name: "Figma",
    category: "design",
    provider: "figma",
    description:
      "Access Figma files, components, and design tokens. Agents can extract design specs, export assets, and generate code from design files.",
    features: [
      "File inspection",
      "Component extraction",
      "Design token export",
      "Comment threads",
      "Version history",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: "https://www.figma.com/developers",
    last_sync_at: null,
    created_at: "2026-03-10T00:00:00Z",
  },

  // ── Cloud Infrastructure ────────────────────────────────────────────────────
  {
    id: "int-aws",
    name: "AWS",
    category: "cloud",
    provider: "aws",
    description:
      "Manage AWS cloud resources. Agents can provision infrastructure, query CloudWatch, manage Lambda functions, and interact with 200+ AWS services.",
    features: [
      "EC2 / Lambda / ECS",
      "CloudWatch metrics",
      "IAM management",
      "CloudFormation",
      "Cost Explorer",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: "https://docs.aws.amazon.com",
    last_sync_at: null,
    created_at: "2026-03-10T00:00:00Z",
  },
  {
    id: "int-gcp",
    name: "Google Cloud",
    category: "cloud",
    provider: "google",
    description:
      "Connect Google Cloud Platform for compute, storage, BigQuery, and AI services. Agents can manage resources and run queries across GCP projects.",
    features: [
      "Compute Engine",
      "BigQuery",
      "Cloud Functions",
      "Vertex AI",
      "Cloud Storage",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: "https://cloud.google.com/docs",
    last_sync_at: null,
    created_at: "2026-03-10T00:00:00Z",
  },

  // ── Databases ───────────────────────────────────────────────────────────────
  {
    id: "int-supabase",
    name: "Supabase",
    category: "database",
    provider: "supabase",
    description:
      "Postgres database, auth, storage, and edge functions as a service. Agents can query tables, manage schemas, and use the real-time API.",
    features: [
      "Postgres queries",
      "Row-level security",
      "Auth & users",
      "Realtime subscriptions",
      "Edge functions",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: "https://supabase.com/docs",
    last_sync_at: null,
    created_at: "2026-03-10T00:00:00Z",
  },
  {
    id: "int-planetscale",
    name: "PlanetScale",
    category: "database",
    provider: "planetscale",
    description:
      "Serverless MySQL with branching and deploy requests. Agents can manage schema changes, query data, and coordinate database migrations safely.",
    features: [
      "Schema branching",
      "Deploy requests",
      "Query insights",
      "Connection pooling",
    ],
    icon_url: null,
    status: "disconnected",
    config: {},
    docs_url: "https://planetscale.com/docs",
    last_sync_at: null,
    created_at: "2026-03-10T00:00:00Z",
  },
];

const MOCK_ADAPTERS: Adapter[] = [
  {
    id: "osa",
    type: "osa",
    name: "OSA Runtime",
    description: "Native OSA Elixir agent runtime",
    status: "available",
    config: {},
    agent_count: 1,
  },
  {
    id: "claude_code",
    type: "claude_code",
    name: "Claude Code",
    description: "Claude Code CLI subprocess",
    status: "available",
    config: {},
    agent_count: 3,
  },
  {
    id: "bash",
    type: "bash",
    name: "Bash",
    description: "Raw shell execution",
    status: "available",
    config: {},
    agent_count: 1,
  },
  {
    id: "http",
    type: "http",
    name: "HTTP",
    description: "External HTTP service",
    status: "available",
    config: {},
    agent_count: 1,
  },
];

export function mockIntegrations(): Integration[] {
  return getIntegrationState();
}

export function mockAdapters(): Adapter[] {
  return MOCK_ADAPTERS;
}

const INTEGRATION_NAME_MAP: Record<string, { name: string; category: IntegrationCategory; description: string }> = {
  github:  { name: 'GitHub',  category: 'version_control',    description: 'Repository sync, PR review, issue management' },
  linear:  { name: 'Linear',  category: 'project_management', description: 'Issue and project sync' },
  slack:   { name: 'Slack',   category: 'communication',      description: 'Notifications and commands' },
  notion:  { name: 'Notion',  category: 'storage',            description: 'Document and database access' },
  jira:    { name: 'Jira',    category: 'project_management', description: 'Issue tracking and sprint management' },
  datadog: { name: 'Datadog', category: 'monitoring',         description: 'Metrics ingestion and alerts' },
};

export function mockConnectIntegration(slug: string, config?: Record<string, unknown>): Integration {
  const state = getIntegrationState();
  const existing = state.find((i) => i.provider === slug);
  if (existing !== undefined) {
    existing.status = 'connected';
    existing.config = { ...existing.config, ...(config ?? {}) };
    existing.last_sync_at = new Date().toISOString();
    return existing;
  }
  const meta = INTEGRATION_NAME_MAP[slug];
  const newIntegration: Integration = {
    id: `int-${slug}-${Date.now()}`,
    name: meta?.name ?? slug,
    category: meta?.category ?? 'custom',
    provider: slug,
    description: meta?.description ?? `${slug} integration`,
    features: [],
    icon_url: null,
    status: 'connected',
    config: config ?? {},
    docs_url: null,
    last_sync_at: new Date().toISOString(),
    created_at: new Date().toISOString(),
  };
  state.push(newIntegration);
  return newIntegration;
}

export function mockDisconnectIntegration(slug: string): boolean {
  const state = getIntegrationState();
  const existing = state.find((i) => i.provider === slug);
  if (existing === undefined) return false;
  existing.status = 'disconnected';
  existing.config = {};
  return true;
}
