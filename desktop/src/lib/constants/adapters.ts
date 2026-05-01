// src/lib/constants/adapters.ts
// Centralized adapter registry — single source of truth for all adapter metadata.
// Consumed by onboarding, hire picker, agent detail, and info popovers.

import type { AdapterType } from '$api/types';

export interface AdapterCapability {
  readonly key: string;
  readonly label: string;
}

export interface AdapterDef {
  readonly id: AdapterType;
  readonly name: string;
  readonly description: string;
  readonly benefits: string;
  readonly capabilities: readonly AdapterCapability[];
  readonly supportsSession: boolean;
  readonly supportsConcurrent: boolean;
  readonly installHint: string;
  readonly recommended?: boolean;
}

const cap = (key: string, label: string): AdapterCapability => ({ key, label });

export const ADAPTER_REGISTRY: readonly AdapterDef[] = [
  {
    id: 'osa',
    name: 'OSA Agent',
    description: 'Elixir/OTP agent runtime by MIOSA — full orchestration, tools, budgets',
    benefits: 'Native BizForge runtime with budgets, memory, tool calls, and agent-to-agent delegation. The most feature-complete adapter.',
    capabilities: [
      cap('chat', 'Chat'),
      cap('tools', 'Tools'),
      cap('code_execution', 'Code Execution'),
      cap('web_search', 'Web Search'),
      cap('memory', 'Memory'),
      cap('delegation', 'Delegation'),
    ],
    supportsSession: true,
    supportsConcurrent: true,
    installHint: 'Requires a running OSA instance (port 9090)',
    recommended: true,
  },
  {
    id: 'claude-code',
    name: 'Claude Code',
    description: "Anthropic's CLI coding agent — terminal-based pair programming",
    benefits: 'Rich stream-json output with token tracking and web search. Strong at code editing with full project context awareness.',
    capabilities: [
      cap('chat', 'Chat'),
      cap('tools', 'Tools'),
      cap('code_execution', 'Code Execution'),
      cap('file_edit', 'File Edit'),
      cap('web_search', 'Web Search'),
    ],
    supportsSession: true,
    supportsConcurrent: true,
    installHint: 'npm install -g @anthropic-ai/claude-code',
  },
  {
    id: 'codex',
    name: 'Codex',
    description: "OpenAI's autonomous coding agent",
    benefits: 'Autonomous code generation and editing powered by OpenAI. Simpler integration than Claude Code, ideal for isolated tasks.',
    capabilities: [
      cap('chat', 'Chat'),
      cap('tools', 'Tools'),
      cap('code_execution', 'Code Execution'),
      cap('file_edit', 'File Edit'),
    ],
    supportsSession: true,
    supportsConcurrent: true,
    installHint: 'npm install -g @openai/codex',
  },
  {
    id: 'openclaw',
    name: 'OpenClaw',
    description: 'Open-source multi-agent coordination framework',
    benefits: 'Multi-agent coordination with code editing, shell execution, and web search. Open-source and framework-agnostic.',
    capabilities: [
      cap('code_edit', 'Code Edit'),
      cap('file_read', 'File Read'),
      cap('file_write', 'File Write'),
      cap('shell_execution', 'Shell'),
      cap('web_search', 'Web Search'),
    ],
    supportsSession: true,
    supportsConcurrent: false,
    installHint: 'npm install -g openclaw',
  },
  {
    id: 'jidoclaw',
    name: 'JidoClaw',
    description: 'Elixir-native agent framework — lightweight, composable workflows',
    benefits: 'Runs inside the BEAM VM without spawning external processes (library mode). Lightweight and composable for Elixir/Phoenix projects.',
    capabilities: [
      cap('code_edit', 'Code Edit'),
      cap('file_read', 'File Read'),
      cap('file_write', 'File Write'),
      cap('shell_execution', 'Shell'),
      cap('elixir_native', 'Elixir Native'),
    ],
    supportsSession: true,
    supportsConcurrent: true,
    installHint: '{:jido_claw, "~> 0.1"} in mix.exs',
  },
  {
    id: 'hermes',
    name: 'Hermes Agent',
    description: 'Fast message-passing agent runtime for real-time systems',
    benefits: 'Optimized for low-latency message passing and real-time event-driven systems.',
    capabilities: [
      cap('chat', 'Chat'),
      cap('tools', 'Tools'),
    ],
    supportsSession: false,
    supportsConcurrent: true,
    installHint: 'cargo install hermes-agent',
  },
  {
    id: 'bash',
    name: 'Bash Shell',
    description: 'Simple shell script executor — run commands directly',
    benefits: 'Deterministic shell execution with zero AI overhead. Always available, lightest-weight adapter.',
    capabilities: [
      cap('code_execution', 'Code Execution'),
      cap('file_edit', 'File Edit'),
    ],
    supportsSession: false,
    supportsConcurrent: true,
    installHint: 'Built-in — always available',
  },
  {
    id: 'http',
    name: 'HTTP API',
    description: 'Generic HTTP/REST adapter — connect any API endpoint',
    benefits: 'Universal glue adapter — wrap any REST service, webhook, or custom microservice as an agent.',
    capabilities: [
      cap('chat', 'Chat'),
    ],
    supportsSession: false,
    supportsConcurrent: true,
    installHint: 'Built-in — requires a url in agent config',
  },
  {
    id: 'cursor',
    name: 'Cursor',
    description: 'Cursor IDE agent runtime — AI-powered code editing',
    benefits: 'IDE-grade context awareness with code completion. Leverages Cursor\'s AI engine programmatically.',
    capabilities: [
      cap('code_edit', 'Code Edit'),
      cap('file_read', 'File Read'),
      cap('file_write', 'File Write'),
      cap('code_completion', 'Code Completion'),
    ],
    supportsSession: true,
    supportsConcurrent: false,
    installHint: 'Install Cursor IDE, then add CLI to PATH',
  },
  {
    id: 'gemini',
    name: 'Gemini',
    description: 'Google Gemini — multimodal text and code generation',
    benefits: 'Multimodal AI (text + images) via API key only — no binary install needed. Good for analysis, content, and code generation.',
    capabilities: [
      cap('text_generation', 'Text Gen'),
      cap('multimodal', 'Multimodal'),
      cap('code_generation', 'Code Gen'),
      cap('analysis', 'Analysis'),
    ],
    supportsSession: true,
    supportsConcurrent: true,
    installHint: 'Set GEMINI_API_KEY env var',
  },
  {
    id: 'custom',
    name: 'Custom',
    description: 'Custom adapter — bring your own implementation',
    benefits: 'Full control over execution with a custom adapter configuration.',
    capabilities: [],
    supportsSession: false,
    supportsConcurrent: false,
    installHint: 'Configure in agent settings',
  },
] as const;

export function getAdapter(id: string): AdapterDef | undefined {
  const normalized = id.replace(/_/g, '-');
  return ADAPTER_REGISTRY.find(
    (a) => a.id === id || a.id === normalized || a.id.replace(/-/g, '_') === id,
  );
}

export function getAdapterLabel(id: string): string {
  return getAdapter(id)?.name ?? id;
}

export function getAdapterDescription(id: string): string {
  return getAdapter(id)?.description ?? '';
}

export const ADAPTER_OPTIONS = ADAPTER_REGISTRY.map((a) => ({
  value: a.id,
  label: a.name,
  description: a.description,
}));
