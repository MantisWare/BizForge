/**
 * Lightweight HTTP client for calling the BizForge backend API.
 * Used by the MCP server to proxy requests to the running backend.
 */

const DEFAULT_BASE_URL = "http://127.0.0.1:9089";
const API_PREFIX = "/api/v1";

let baseUrl = process.env.BIZFORGE_API_URL ?? DEFAULT_BASE_URL;
let authToken: string | null = process.env.BIZFORGE_API_TOKEN ?? null;

export function configure(opts: { baseUrl?: string; token?: string }): void {
  if (opts.baseUrl !== undefined) baseUrl = opts.baseUrl;
  if (opts.token !== undefined) authToken = opts.token;
}

interface RequestOptions {
  method?: string;
  body?: unknown;
  params?: Record<string, string | number | boolean | undefined>;
}

export async function api<T = unknown>(
  path: string,
  opts: RequestOptions = {},
): Promise<T> {
  const { method = "GET", body, params } = opts;
  let url = `${baseUrl}${API_PREFIX}${path}`;

  if (params !== undefined) {
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(params)) {
      if (v !== undefined) qs.set(k, String(v));
    }
    const qsStr = qs.toString();
    if (qsStr.length > 0) url += `?${qsStr}`;
  }

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    Accept: "application/json",
  };

  if (authToken !== null) {
    headers["Authorization"] = `Bearer ${authToken}`;
  }

  const response = await fetch(url, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });

  if (!response.ok) {
    const text = await response.text().catch(() => "");
    throw new Error(
      `BizForge API ${method} ${path} returned ${response.status}: ${text}`,
    );
  }

  const contentType = response.headers.get("content-type") ?? "";
  if (contentType.includes("application/json")) {
    return (await response.json()) as T;
  }

  return (await response.text()) as unknown as T;
}

export async function healthCheck(): Promise<boolean> {
  try {
    await api("/health");
    return true;
  } catch {
    return false;
  }
}
