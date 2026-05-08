export interface JsonRpcRequest {
  jsonrpc: "2.0";
  id: string | number;
  method: string;
  params?: Record<string, unknown>;
}

export interface JsonRpcResponse {
  jsonrpc: "2.0";
  id: string | number | null;
  result?: unknown;
  error?: { code: number; message: string; data?: unknown };
}

export interface TabInfo {
  id: string;
  url: string;
  title: string;
}

export interface SnapshotResult {
  snapshot: string;
  url: string;
  title: string;
  screenshot?: string;
}

export interface ScreenshotResult {
  base64: string;
  width: number;
  height: number;
}

export interface NetworkEntry {
  method: string;
  url: string;
  status: number | null;
  content_type: string | null;
  timestamp: number;
}

export interface ConsoleEntry {
  type: string;
  text: string;
  timestamp: number;
}

export interface BrowserToolSpec {
  name: string;
  description: string;
  parameters: Record<string, unknown>;
}
