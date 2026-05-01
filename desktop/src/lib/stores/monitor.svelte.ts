// src/lib/stores/monitor.svelte.ts
// Aggregates data from multiple API endpoints and SSE streams for the headless stats dashboard.
// Each monitor window connects to a specific workspace.

import {
  health as healthApi,
  agents as agentsApi,
  costs as costsApi,
  issues as issuesApi,
  alerts as alertsApi,
  schedules as schedulesApi,
  workspaces as workspacesApi,
} from '$api/client';
import type {
  HealthResponse,
  BizforgeAgent,
  CostSummary,
  Issue,
  AlertRule,
  Workspace,
} from '$api/types';

interface MonitorHealth {
  status: string;
  uptime: number;
  activeAgents: number;
  version: string;
}

interface MonitorBudget {
  totalSpent: number;
  dailyLimit: number;
  monthlyLimit: number;
  utilizationPercent: number;
}

interface HeartbeatEvent {
  agentName: string;
  agentId: string;
  event: string;
  timestamp: string;
  cost?: number;
}

class MonitorStore {
  // Connection state
  connected = $state(false);
  lastUpdated = $state<string | null>(null);
  error = $state<string | null>(null);

  // Workspace selection
  workspaceId = $state<string | null>(null);
  workspaceName = $state('BizForge Workspace');
  availableWorkspaces = $state<Workspace[]>([]);
  selectingWorkspace = $state(true);
  startedAt = $state<string | null>(null);
  paused = $state(false);

  // Health
  health = $state<MonitorHealth>({
    status: 'unknown',
    uptime: 0,
    activeAgents: 0,
    version: '0.1.0',
  });

  // Agents
  agents = $state<BizforgeAgent[]>([]);
  agentCounts = $derived({
    total: this.agents.length,
    active: this.agents.filter((a) => a.status === 'running' || a.status === 'active').length,
    idle: this.agents.filter((a) => a.status === 'idle').length,
    working: this.agents.filter((a) => a.status === 'working').length,
    paused: this.agents.filter((a) => a.status === 'paused').length,
    errored: this.agents.filter((a) => a.status === 'error').length,
  });

  // Tasks
  issues = $state<Issue[]>([]);
  taskCounts = $derived({
    total: this.issues.length,
    inProgress: this.issues.filter((i) => i.status === 'in_progress').length,
    completed: this.issues.filter((i) => i.status === 'done' || i.status === 'closed').length,
    blocked: this.issues.filter((i) => i.status === 'blocked').length,
    failed: this.issues.filter((i) => i.status === 'failed').length,
    open: this.issues.filter((i) => i.status === 'open' || i.status === 'backlog').length,
  });

  // Costs
  costSummary = $state<CostSummary | null>(null);
  costHistory = $state<Array<{ date: string; cost: number }>>([]);

  // Budget
  budget = $state<MonitorBudget>({
    totalSpent: 0,
    dailyLimit: 10000,
    monthlyLimit: 500000,
    utilizationPercent: 0,
  });

  // Heartbeat timeline
  heartbeatEvents = $state<HeartbeatEvent[]>([]);

  // Logs
  logEntries = $state<Array<{ level: string; message: string; timestamp: string; agent?: string }>>([]);

  // Alerts
  alerts = $state<AlertRule[]>([]);
  activeAlertCount = $derived(this.alerts.filter((a) => a.enabled).length);

  // Internals
  private _pollTimer: ReturnType<typeof setInterval> | null = null;
  private _eventSource: EventSource | null = null;
  private _pollInterval = 5000;

  async loadAvailableWorkspaces(): Promise<void> {
    try {
      this.availableWorkspaces = await workspacesApi.list();
    } catch {
      this.availableWorkspaces = [];
    }
  }

  selectWorkspace(workspace: Workspace): void {
    this.workspaceId = workspace.id;
    this.workspaceName = workspace.name;
    this.selectingWorkspace = false;
    this.startPolling();
  }

  backToSelector(): void {
    this.stopPolling();
    this.selectingWorkspace = true;
    this.workspaceId = null;
    this.agents = [];
    this.issues = [];
    this.alerts = [];
    this.heartbeatEvents = [];
    this.logEntries = [];
    this.connected = false;
  }

  startPolling(): void {
    this.fetchAll();
    this._pollTimer = setInterval(() => this.fetchAll(), this._pollInterval);
    this.connectSSE();
  }

  stopPolling(): void {
    if (this._pollTimer !== null) {
      clearInterval(this._pollTimer);
      this._pollTimer = null;
    }
    if (this._eventSource !== null) {
      this._eventSource.close();
      this._eventSource = null;
    }
  }

  async fetchAll(): Promise<void> {
    const wsId = this.workspaceId ?? undefined;

    try {
      const [healthData, agentsData, costData, issuesData, alertsData] = await Promise.allSettled([
        healthApi.get(),
        agentsApi.list(wsId),
        costsApi.summary(),
        issuesApi.list(),
        alertsApi.list(wsId),
      ]);

      if (healthData.status === 'fulfilled') {
        const h = healthData.value as HealthResponse;
        this.health = {
          status: h.status ?? 'ok',
          uptime: h.uptime_seconds ?? 0,
          activeAgents: h.agents_active ?? 0,
          version: h.version ?? '0.1.0',
        };
      }

      if (agentsData.status === 'fulfilled') {
        this.agents = agentsData.value as BizforgeAgent[];
      }

      if (costData.status === 'fulfilled') {
        const c = costData.value as CostSummary;
        this.costSummary = c;
        const spent = c.month_cents ?? 0;
        const limit = c.monthly_budget_cents ?? 0;
        this.budget = {
          totalSpent: spent,
          dailyLimit: c.daily_budget_cents ?? 0,
          monthlyLimit: limit,
          utilizationPercent: limit > 0 ? Math.round((spent / limit) * 100) : 0,
        };
      }

      if (issuesData.status === 'fulfilled') {
        this.issues = issuesData.value as Issue[];
      }

      if (alertsData.status === 'fulfilled') {
        this.alerts = alertsData.value as AlertRule[];
      }

      this.connected = true;
      this.lastUpdated = new Date().toISOString();
      this.error = null;
    } catch (e) {
      this.connected = false;
      this.error = (e as Error).message;
    }
  }

  private connectSSE(): void {
    const apiUrl = import.meta.env.VITE_API_URL ?? 'http://127.0.0.1:9089';
    const token = localStorage.getItem('bizforge-auth-token');

    if (token === null) return;

    try {
      const url = `${apiUrl}/api/v1/activity/stream?token=${encodeURIComponent(token)}`;
      this._eventSource = new EventSource(url);

      this._eventSource.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);
          this.handleSSEEvent(data);
        } catch {
          // skip unparseable events
        }
      };

      this._eventSource.onerror = () => {
        this._eventSource?.close();
        this._eventSource = null;
        setTimeout(() => this.connectSSE(), 10000);
      };
    } catch {
      // SSE unavailable — polling handles data
    }
  }

  private handleSSEEvent(data: Record<string, unknown>): void {
    const event = data.event as string;
    const agentId = data.agent_id as string;
    const agentName = (data.agent_name as string) ?? 'Unknown';
    const timestamp = (data.timestamp as string) ?? new Date().toISOString();

    if (event === 'run.started' || event === 'run.completed' || event === 'run.failed') {
      const he: HeartbeatEvent = {
        agentName,
        agentId,
        event,
        timestamp,
        cost: data.cost_cents as number | undefined,
      };

      this.heartbeatEvents = [he, ...this.heartbeatEvents.slice(0, 99)];
    }

    const logEntry = {
      level: event.includes('failed') || event.includes('error') ? 'error' : 'info',
      message: `[${agentName}] ${event}`,
      timestamp,
      agent: agentName,
    };

    this.logEntries = [logEntry, ...this.logEntries.slice(0, 199)];
  }

  async pauseAll(): Promise<void> {
    try {
      await schedulesApi.pauseAll();
      this.paused = true;
    } catch (e) {
      console.error('[monitor] Failed to pause:', (e as Error).message);
    }
  }

  async resumeAll(): Promise<void> {
    try {
      await schedulesApi.wakeAll();
      this.paused = false;
    } catch (e) {
      console.error('[monitor] Failed to resume:', (e as Error).message);
    }
  }
}

export const monitorStore = new MonitorStore();
