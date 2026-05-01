/**
 * Lightweight HTTP client for calling the BizForge backend API.
 * Used by the MCP server to proxy requests to the running backend.
 */
const DEFAULT_BASE_URL = "http://127.0.0.1:9089";
const API_PREFIX = "/api/v1";
let baseUrl = process.env.BIZFORGE_API_URL ?? DEFAULT_BASE_URL;
let authToken = process.env.BIZFORGE_API_TOKEN ?? null;
export function configure(opts) {
    if (opts.baseUrl !== undefined)
        baseUrl = opts.baseUrl;
    if (opts.token !== undefined)
        authToken = opts.token;
}
export async function api(path, opts = {}) {
    const { method = "GET", body, params } = opts;
    let url = `${baseUrl}${API_PREFIX}${path}`;
    if (params !== undefined) {
        const qs = new URLSearchParams();
        for (const [k, v] of Object.entries(params)) {
            if (v !== undefined)
                qs.set(k, String(v));
        }
        const qsStr = qs.toString();
        if (qsStr.length > 0)
            url += `?${qsStr}`;
    }
    const headers = {
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
        throw new Error(`BizForge API ${method} ${path} returned ${response.status}: ${text}`);
    }
    const contentType = response.headers.get("content-type") ?? "";
    if (contentType.includes("application/json")) {
        return (await response.json());
    }
    return (await response.text());
}
export async function healthCheck() {
    try {
        await api("/health");
        return true;
    }
    catch {
        return false;
    }
}
