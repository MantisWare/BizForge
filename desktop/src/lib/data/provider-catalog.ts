// src/lib/data/provider-catalog.ts
// Shared provider catalog used by onboarding, settings, and agent hiring.

export type ProviderCategory = "cloud" | "local";

export type LocalRuntime =
  | "ollama"
  | "lm-studio"
  | "jan"
  | "gpt4all"
  | "llamacpp";

export interface ProviderCatalogEntry {
  slug: string;
  name: string;
  description: string;
  category: ProviderCategory;
  defaultEndpoint?: string;
  noKey?: boolean;
  recommended?: boolean;
  defaultModels?: string[];
}

export interface LocalRuntimeEntry {
  id: LocalRuntime;
  name: string;
  description: string;
  defaultEndpoint: string;
}

export const FEATURED_PROVIDERS: readonly ProviderCatalogEntry[] = [
  {
    slug: "anthropic",
    name: "Anthropic",
    description: "Claude models — most capable reasoning",
    category: "cloud",
    defaultEndpoint: "https://api.anthropic.com",
    defaultModels: [
      "claude-sonnet-4-6",
      "claude-opus-4-6",
      "claude-haiku-4-5-20251001",
    ],
  },
  {
    slug: "openai",
    name: "OpenAI",
    description: "GPT-4o and o-series models",
    category: "cloud",
    defaultEndpoint: "https://api.openai.com",
    defaultModels: ["gpt-4o", "gpt-4o-mini", "o3-mini"],
  },
  {
    slug: "google",
    name: "Google",
    description: "Gemini models — multimodal, long context",
    category: "cloud",
    defaultEndpoint: "https://generativelanguage.googleapis.com",
    defaultModels: ["gemini-2.0-flash", "gemini-2.0-pro"],
  },
  {
    slug: "local",
    name: "Local Provider",
    description: "Run models locally — choose your runtime",
    category: "local",
    noKey: true,
  },
  {
    slug: "groq",
    name: "Groq",
    description: "Ultra-fast inference at low cost",
    category: "cloud",
    defaultEndpoint: "https://api.groq.com",
    defaultModels: ["llama-3.3-70b-versatile", "mixtral-8x7b-32768"],
  },
  {
    slug: "deepseek",
    name: "DeepSeek",
    description: "Strong reasoning, competitive pricing",
    category: "cloud",
    defaultEndpoint: "https://api.deepseek.com",
    defaultModels: ["deepseek-v4-flash", "deepseek-v4-pro", "deepseek-chat"],
  },
  {
    slug: "claude-code",
    name: "Claude Code",
    description: "Anthropic's agentic coding assistant — terminal-native AI",
    category: "cloud",
    defaultEndpoint: "https://api.anthropic.com",
    defaultModels: [
      "claude-sonnet-4-6",
      "claude-opus-4-6",
      "claude-haiku-4-5-20251001",
    ],
  },
  {
    slug: "cursor-cli",
    name: "Cursor CLI",
    description: "Cursor AI subscription — no per-token cost",
    category: "cloud",
    noKey: true,
    defaultModels: [
      "auto",
      "claude-4.6-opus-high",
      "claude-4.6-sonnet-medium",
      "claude-4.5-sonnet",
    ],
  },
] as const;

export const MORE_PROVIDERS: readonly ProviderCatalogEntry[] = [
  {
    slug: "mistral",
    name: "Mistral",
    description: "European open-weight models",
    category: "cloud",
    defaultEndpoint: "https://api.mistral.ai",
  },
  {
    slug: "cohere",
    name: "Cohere",
    description: "Enterprise NLP and embeddings",
    category: "cloud",
    defaultEndpoint: "https://api.cohere.com",
  },
  {
    slug: "together",
    name: "Together AI",
    description: "Open-source models at scale",
    category: "cloud",
    defaultEndpoint: "https://api.together.ai",
  },
  {
    slug: "fireworks",
    name: "Fireworks AI",
    description: "Fast open-source model inference",
    category: "cloud",
    defaultEndpoint: "https://api.fireworks.ai/inference",
  },
  {
    slug: "perplexity",
    name: "Perplexity",
    description: "Search-augmented language models",
    category: "cloud",
    defaultEndpoint: "https://api.perplexity.ai",
  },
  {
    slug: "cerebras",
    name: "Cerebras",
    description: "Wafer-scale AI chip inference",
    category: "cloud",
    defaultEndpoint: "https://api.cerebras.ai",
  },
  {
    slug: "sambanova",
    name: "SambaNova",
    description: "Reconfigurable dataflow architecture",
    category: "cloud",
    defaultEndpoint: "https://api.sambanova.ai",
  },
  {
    slug: "openrouter",
    name: "OpenRouter",
    description: "Unified API for 100+ models",
    category: "cloud",
    defaultEndpoint: "https://openrouter.ai/api",
  },
  {
    slug: "replicate",
    name: "Replicate",
    description: "Run open-source models via API",
    category: "cloud",
    defaultEndpoint: "https://api.replicate.com",
  },
  {
    slug: "xai",
    name: "xAI",
    description: "Grok models from xAI",
    category: "cloud",
    defaultEndpoint: "https://api.x.ai",
  },
  {
    slug: "lambda",
    name: "Lambda",
    description: "GPU cloud for AI workloads",
    category: "cloud",
    defaultEndpoint: "https://api.lambdalabs.com",
  },
  {
    slug: "lepton",
    name: "Lepton AI",
    description: "Serverless AI inference platform",
    category: "cloud",
    defaultEndpoint: "https://api.lepton.ai",
  },
] as const;

export const LOCAL_RUNTIMES: readonly LocalRuntimeEntry[] = [
  {
    id: "ollama",
    name: "Ollama",
    description: "Most popular local model runner",
    defaultEndpoint: "http://localhost:11434",
  },
  {
    id: "lm-studio",
    name: "LM Studio",
    description: "GUI-based local inference",
    defaultEndpoint: "http://localhost:1234",
  },
  {
    id: "jan",
    name: "Jan",
    description: "Open-source ChatGPT alternative",
    defaultEndpoint: "http://localhost:1337",
  },
  {
    id: "gpt4all",
    name: "GPT4All",
    description: "Privacy-focused local models",
    defaultEndpoint: "http://localhost:4891",
  },
  {
    id: "llamacpp",
    name: "llama.cpp",
    description: "Lightweight C++ inference server",
    defaultEndpoint: "http://localhost:8080",
  },
] as const;

export const ALL_PROVIDERS: readonly ProviderCatalogEntry[] = [
  ...FEATURED_PROVIDERS,
  ...MORE_PROVIDERS,
];

export function findProvider(
  slug: string,
): ProviderCatalogEntry | undefined {
  return ALL_PROVIDERS.find((p) => p.slug === slug);
}

export function findLocalRuntime(
  id: LocalRuntime,
): LocalRuntimeEntry | undefined {
  return LOCAL_RUNTIMES.find((r) => r.id === id);
}

export function getDefaultEndpoint(
  slug: string,
  localRuntime?: LocalRuntime,
): string {
  if (slug === "local" && localRuntime !== undefined) {
    return findLocalRuntime(localRuntime)?.defaultEndpoint ?? "http://localhost:11434";
  }
  return findProvider(slug)?.defaultEndpoint ?? "";
}
