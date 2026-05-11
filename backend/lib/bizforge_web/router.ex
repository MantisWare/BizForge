defmodule BizforgeWeb.Router do
  use BizforgeWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug BizforgeWeb.Plugs.SecurityHeaders
    plug BizforgeWeb.Plugs.CORS
  end

  pipeline :authenticated do
    plug BizforgeWeb.Plugs.Auth
    plug BizforgeWeb.Plugs.RateLimiter
    plug BizforgeWeb.Plugs.WorkspaceAuth
    plug BizforgeWeb.Plugs.Governance
    plug BizforgeWeb.Plugs.Idempotency
    plug BizforgeWeb.Plugs.Audit
  end

  pipeline :streaming do
    plug :accepts, ["event-stream", "json"]
    plug :fetch_query_params
    plug BizforgeWeb.Plugs.SecurityHeaders
    plug BizforgeWeb.Plugs.CORS
  end

  pipeline :public_rate_limited do
    plug BizforgeWeb.Plugs.RateLimiter
  end

  pipeline :headless_auth do
    plug BizforgeWeb.Plugs.ApiKeyAuth
  end

  # Root-level health check — convenience alias so /health works without /api/v1 prefix
  scope "/", BizforgeWeb do
    pipe_through [:api, :public_rate_limited]
    get "/health", HealthController, :show
  end

  # Health check — no auth
  scope "/api/v1", BizforgeWeb do
    pipe_through [:api, :public_rate_limited]

    get "/health", HealthController, :show
    get "/metrics", MetricsController, :show
    post "/auth/login", AuthController, :login
    post "/auth/refresh", AuthController, :refresh
    post "/auth/register", AuthController, :register
    get "/auth/status", AuthController, :status
  end

  # Authenticated API routes
  scope "/api/v1", BizforgeWeb do
    pipe_through [:api, :authenticated]

    get "/dashboard", DashboardController, :show
    get "/dashboard/recent-ai-calls", DashboardController, :recent_ai_calls
    get "/adapters", AdapterController, :index

    # Workspaces
    resources "/workspaces", WorkspaceController, except: [:new, :edit] do
      post "/activate", WorkspaceController, :activate, as: :activate
      get "/agents", WorkspaceController, :agents, as: :agents
      get "/skills", WorkspaceController, :skills, as: :skills
      get "/config", WorkspaceController, :config, as: :config
    end

    # Agents
    get  "/agents/hierarchy", AgentController, :hierarchy
    post "/agents/batch",     AgentController, :batch_create

    resources "/agents", AgentController, except: [:new, :edit] do
      post "/wake", AgentController, :wake, as: :wake
      post "/sleep", AgentController, :sleep, as: :sleep
      post "/pause", AgentController, :pause, as: :pause
      post "/resume", AgentController, :resume, as: :resume
      post "/focus", AgentController, :focus, as: :focus
      post "/terminate", AgentController, :terminate, as: :terminate
      get "/runs", AgentController, :runs, as: :runs
      get "/inbox", AgentController, :inbox, as: :inbox
    end

    # Sessions
    resources "/sessions", SessionController, only: [:index, :show, :create, :delete] do
      get "/transcript", SessionController, :transcript, as: :transcript
      post "/message", SessionController, :message, as: :message
      get "/chain", SessionController, :chain, as: :chain
      post "/compact", SessionController, :compact, as: :compact
    end

    # Browser automation (Playwright sidecar)
    post "/browser/:method", BrowserController, :call

    # QA report ingestion
    post "/qa-reports", QaReportController, :create

    # Sprints
    resources "/sprints", SprintController, except: [:new, :edit] do
      post "/start", SprintController, :start, as: :start
      post "/complete", SprintController, :complete, as: :complete
      post "/assign-tasks", SprintController, :assign_tasks, as: :assign_tasks
      post "/unassign-tasks", SprintController, :unassign_tasks, as: :unassign_tasks
    end

    # Workflows
    resources "/workflows", WorkflowController, except: [:new, :edit] do
      get "/steps", WorkflowController, :steps, as: :steps
      post "/steps", WorkflowController, :add_step, as: :add_step
      delete "/steps/:step_id", WorkflowController, :remove_step, as: :remove_step
      get "/runs", WorkflowController, :runs, as: :runs
      post "/trigger", WorkflowController, :trigger, as: :trigger

      # Run lifecycle
      post "/runs/:run_id/pause", WorkflowController, :pause, as: :pause_run
      post "/runs/:run_id/resume", WorkflowController, :resume, as: :resume_run
      post "/runs/:run_id/cancel", WorkflowController, :cancel, as: :cancel_run
      get "/runs/:run_id/steps", WorkflowController, :step_status, as: :step_status
    end

    # Schedules
    get "/schedules/queue", ScheduleController, :queue
    post "/schedules/wake-all", ScheduleController, :wake_all
    post "/schedules/pause-all", ScheduleController, :pause_all

    resources "/schedules", ScheduleController, except: [:new, :edit] do
      post "/trigger", ScheduleController, :trigger, as: :trigger
    end

    # Costs + Budgets
    get "/costs/summary", CostController, :summary
    get "/costs/by-agent", CostController, :by_agent
    get "/costs/by-model", CostController, :by_model
    get "/costs/daily", CostController, :daily
    get "/costs/events", CostController, :events
    get "/budgets", BudgetController, :index
    put "/budgets/:scope_type/:scope_id", BudgetController, :upsert
    get "/budgets/incidents", BudgetController, :incidents
    post "/budgets/incidents/:id/resolve", BudgetController, :resolve

    # Spawn
    post "/spawn", SpawnController, :create
    get "/spawn/active", SpawnController, :active
    delete "/spawn/:id", SpawnController, :kill
    get "/spawn/history", SpawnController, :history

    # Delegation + Dispatch
    post "/delegations", DelegationController, :create
    get "/dispatch/routes", DelegationController, :routes
    post "/dispatch/preview", DelegationController, :preview

    # Tasks
    resources "/tasks", TaskController, except: [:new, :edit] do
      post "/assign", TaskController, :assign, as: :assign
      resources "/comments", CommentController, only: [:index, :create]
      post "/checkout", TaskController, :checkout, as: :checkout
      post "/dispatch", TaskController, :dispatch, as: :dispatch
      post "/labels", TaskController, :add_label, as: :add_label
      delete "/labels/:label_id", TaskController, :remove_label, as: :remove_label
    end

    # Phases
    resources "/phases", PhaseController, except: [:new, :edit] do
      get "/ancestry", PhaseController, :ancestry, as: :ancestry
      post "/decompose", PhaseController, :decompose, as: :decompose
    end

    # Projects
    get "/projects/lifecycle-templates", ProjectController, :lifecycle_templates
    resources "/projects", ProjectController, except: [:new, :edit] do
      get "/phases", ProjectController, :phases, as: :phases
      get "/workspaces", ProjectController, :workspaces, as: :workspaces

      # ForgeMap — codebase scanning & indexing
      post "/forgemap/detect", ForgeMapController, :detect, as: :forgemap_detect
      post "/forgemap/scan", ForgeMapController, :scan, as: :forgemap_scan
      get "/forgemap", ForgeMapController, :index, as: :forgemap_index
      patch "/forgemap/:file_path", ForgeMapController, :update_entry, as: :forgemap_update
    end

    # Task dependency resolution
    post "/projects/:project_id/resolve-execution-order", TaskController, :resolve_execution_order
    get "/projects/:project_id/ready-tasks", TaskController, :ready_tasks

    # Documents
    get "/documents", DocumentController, :index
    get "/document-revisions", DocumentController, :revisions
    get "/documents/*path", DocumentController, :show
    put "/documents/*path", DocumentController, :update
    delete "/documents/*path", DocumentController, :delete
    post "/documents", DocumentController, :create

    # Inbox (unified — notifications-based)
    get "/inbox", InboxController, :index
    post "/inbox/read-all", InboxController, :read_all
    post "/inbox/:id/read", InboxController, :read
    post "/inbox/:id/action", InboxController, :perform_action
    post "/inbox/:id/reply", InboxController, :reply

    # Notifications
    get "/notifications/badges", NotificationController, :badges
    post "/notifications/mark-all-read", NotificationController, :mark_all_read

    resources "/notifications", NotificationController, only: [:index, :show, :create] do
      post "/read", NotificationController, :mark_read, as: :read
      post "/dismiss", NotificationController, :dismiss, as: :dismiss
    end

    # Activity + Logs
    get "/activity", ActivityController, :index
    get "/logs", LogController, :index

    # Memory
    get "/memory/search", MemoryController, :search
    get "/memory/namespaces", MemoryController, :namespaces
    get "/memory/company", MemoryController, :company
    get "/memory/project/:project_id", MemoryController, :by_project
    get "/memory/resolve/:project_id", MemoryController, :resolve
    resources "/memory", MemoryController, except: [:new, :edit]

    # Signals
    post "/signals/classify", SignalController, :classify
    get "/signals/feed", SignalController, :feed
    get "/signals/patterns", SignalController, :patterns
    get "/signals/stats", SignalController, :stats

    # Skills
    post "/skills/bulk-enable", SkillController, :bulk_enable
    post "/skills/bulk-disable", SkillController, :bulk_disable
    get "/skills/categories", SkillController, :categories
    post "/skills/import", SkillController, :import_skill

    resources "/skills", SkillController, only: [:index, :show] do
      post "/toggle", SkillController, :toggle, as: :toggle
      post "/inject", SkillController, :inject, as: :inject
    end

    # Agent–Skill assignment
    post "/agents/:agent_id/skills/:skill_id", SkillController, :assign_to_agent
    delete "/agents/:agent_id/skills/:skill_id", SkillController, :remove_from_agent

    # Webhooks
    resources "/webhooks", WebhookController, except: [:new, :edit] do
      post "/test", WebhookController, :test, as: :test
      get "/deliveries", WebhookController, :deliveries, as: :deliveries
    end

    # Alerts
    get "/alerts/rules", AlertController, :index_rules
    post "/alerts/rules", AlertController, :create_rule
    get "/alerts/rules/:id", AlertController, :show_rule
    patch "/alerts/rules/:id", AlertController, :update_rule
    delete "/alerts/rules/:id", AlertController, :delete_rule
    post "/alerts/evaluate", AlertController, :evaluate
    get "/alerts/history", AlertController, :history

    # Integrations
    get "/integrations", IntegrationController, :index
    post "/integrations/pull-all", IntegrationController, :pull_all
    post "/integrations/:slug/connect", IntegrationController, :connect
    delete "/integrations/:slug", IntegrationController, :disconnect
    get "/integrations/:slug/status", IntegrationController, :status

    # Slack integration config
    post "/integrations/slack/configure", IntegrationController, :connect_slack
    delete "/integrations/slack/configure", IntegrationController, :disconnect_slack
    get "/integrations/slack/config-status", IntegrationController, :slack_status

    # Integration Bindings
    get "/integration-bindings", IntegrationBindingController, :index
    post "/integration-bindings", IntegrationBindingController, :create
    delete "/integration-bindings/by-owner/:owner_type/:owner_id/:provider", IntegrationBindingController, :delete_by_owner
    get "/integration-bindings/resolve/:agent_id", IntegrationBindingController, :resolve
    delete "/integration-bindings/:id", IntegrationBindingController, :delete

    # Admin
    resources "/users", UserController, except: [:new, :edit]
    get "/audit", AuditController, :index

    resources "/gateways", GatewayController, only: [:index, :show, :create, :update, :delete] do
      post "/probe", GatewayController, :probe, as: :probe
    end

    post "/providers/discover-models", ProviderController, :discover_models

    resources "/providers", ProviderController, only: [:index, :show, :create, :update, :delete] do
      post "/test", ProviderController, :test, as: :test
      post "/discover-models", ProviderController, :discover_models, as: :discover_models
    end

    get "/config", ConfigController, :show
    patch "/config", ConfigController, :update
    get "/templates", TemplateController, :index
    post "/templates", TemplateController, :create

    # Library / Marketplace
    get "/library/installed", LibraryController, :installed
    get "/library/categories", LibraryController, :categories

    resources "/library", LibraryController, except: [:new, :edit] do
      post "/install", LibraryController, :install, as: :install
      post "/uninstall", LibraryController, :uninstall, as: :uninstall
      post "/rate", LibraryController, :rate, as: :rate
    end

    # Secrets
    resources "/secrets", SecretController, except: [:new, :edit] do
      post "/rotate", SecretController, :rotate, as: :rotate
    end

    # Approvals
    resources "/approvals", ApprovalController, except: [:new, :edit] do
      post "/approve", ApprovalController, :approve, as: :approve
      post "/reject", ApprovalController, :reject, as: :reject
      post "/comments", ApprovalController, :comment, as: :comments
    end

    # Organizations
    resources "/organizations", OrganizationController, except: [:new, :edit] do
      get "/members", OrganizationController, :members, as: :members
    end

    # Divisions
    resources "/divisions", DivisionController, except: [:new, :edit] do
      get "/departments", DivisionController, :departments, as: :departments
    end

    # Departments
    resources "/departments", DepartmentController, except: [:new, :edit] do
      get "/teams", DepartmentController, :teams, as: :teams
    end

    # Teams
    resources "/teams", TeamController, except: [:new, :edit] do
      get "/agents", TeamController, :agents, as: :agents
      post "/members", TeamController, :add_member, as: :members
      delete "/members/:agent_id", TeamController, :remove_member, as: :remove_member
    end

    # Hierarchy (full org tree)
    get "/hierarchy", HierarchyController, :show

    # Environment
    get "/environment/apps", EnvironmentController, :apps
    get "/environment/agent-apps", EnvironmentController, :agent_apps
    get "/environment/resources", EnvironmentController, :resources
    get "/environment/capabilities", EnvironmentController, :capabilities
    post "/environment/apps/:id/grant", EnvironmentController, :grant_access
    post "/environment/apps/:id/revoke", EnvironmentController, :revoke_access

    # Invitations
    resources "/invitations", InvitationController, only: [:index, :create]
    post "/invitations/:token/accept", InvitationController, :accept

    # Labels
    resources "/labels", LabelController, only: [:index, :create, :delete]

    # Task Attachments
    get "/tasks/:task_id/attachments", AttachmentController, :index
    post "/tasks/:task_id/attachments", AttachmentController, :create
    delete "/tasks/:task_id/attachments/:id", AttachmentController, :delete

    # Work Products
    get "/tasks/:task_id/work-products", WorkProductController, :index
    resources "/work-products", WorkProductController, except: [:new, :edit]
    post "/work-products/:id/archive", WorkProductController, :archive

    # Analytics
    get "/analytics/summary", AnalyticsController, :summary
    get "/analytics/agents", AnalyticsController, :agents
    get "/analytics/teams", AnalyticsController, :teams
    delete "/analytics/reset", AnalyticsController, :reset

    # Config Revisions
    get "/config/revisions", ConfigRevisionController, :index
    post "/config/revisions/:id/restore", ConfigRevisionController, :restore

    # Sidebar Badges
    get "/sidebar-badges", SidebarBadgeController, :show

    # Access Control (RBAC)
    get "/access", AccessController, :index
    post "/access/assign", AccessController, :assign
    delete "/access/:id", AccessController, :revoke

    # Conversations
    resources "/conversations", ConversationController, except: [:new, :edit, :update] do
      get "/messages", ConversationController, :messages, as: :messages
      post "/messages", ConversationController, :send_message, as: :send_message
      post "/archive", ConversationController, :archive, as: :archive
    end

    # Execution Workspaces
    resources "/execution-workspaces", ExecutionWorkspaceController,
      only: [:index, :create, :delete]

    # Plugins
    resources "/plugins", PluginController, except: [:new, :edit] do
      get "/logs", PluginController, :logs, as: :logs
    end

    # Datasets
    resources "/datasets", DatasetController, except: [:new, :edit] do
      get "/preview", DatasetController, :preview, as: :preview
      post "/refresh", DatasetController, :refresh, as: :refresh
      post "/grant", DatasetController, :grant_access, as: :grant
      post "/revoke", DatasetController, :revoke_access, as: :revoke
    end

    # Reports
    resources "/reports", ReportController, except: [:new, :edit] do
      post "/generate", ReportController, :generate, as: :generate
      get "/export", ReportController, :export, as: :export
    end
  end

  # SSE streaming endpoints (accept text/event-stream)
  scope "/api/v1", BizforgeWeb do
    pipe_through [:streaming, :authenticated]

    get "/activity/stream", ActivityController, :stream
    get "/logs/stream", LogController, :stream
    get "/sessions/:session_id/stream", SessionController, :stream
    get "/inbox/stream", InboxController, :stream
  end

  # Incoming webhook receiver (no JWT — uses webhook secret)
  scope "/api/v1", BizforgeWeb do
    pipe_through :api
    post "/hooks/:webhook_id", WebhookController, :receive
  end

  # Slack integration endpoints (no JWT — Slack signs requests via HMAC)
  scope "/api/v1/slack", BizforgeWeb do
    pipe_through :api
    post "/events", SlackController, :events
    post "/interactive", SlackController, :interactive
  end
end
