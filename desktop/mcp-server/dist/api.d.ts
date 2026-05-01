/**
 * Lightweight HTTP client for calling the BizForge backend API.
 * Used by the MCP server to proxy requests to the running backend.
 */
export declare function configure(opts: {
    baseUrl?: string;
    token?: string;
}): void;
interface RequestOptions {
    method?: string;
    body?: unknown;
    params?: Record<string, string | number | boolean | undefined>;
}
export declare function api<T = unknown>(path: string, opts?: RequestOptions): Promise<T>;
export declare function healthCheck(): Promise<boolean>;
export {};
