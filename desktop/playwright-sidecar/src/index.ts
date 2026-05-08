#!/usr/bin/env node

/**
 * BizForge Playwright Sidecar
 *
 * A managed Node.js child process that owns a Playwright browser instance
 * and exposes browser automation tools via JSON-RPC over stdio.
 *
 * Tool surface mirrors cursor-ide-browser MCP for prompt portability.
 */

import { createInterface } from "readline";
import { BrowserManager } from "./browser-manager.js";
import type { JsonRpcRequest, JsonRpcResponse } from "./types.js";

const browserManager = new BrowserManager();

const rl = createInterface({ input: process.stdin, terminal: false });

function sendResponse(response: JsonRpcResponse): void {
  process.stdout.write(JSON.stringify(response) + "\n");
}

function sendError(id: string | number | null, code: number, message: string): void {
  sendResponse({ jsonrpc: "2.0", id, error: { code, message } });
}

async function handleRequest(req: JsonRpcRequest): Promise<void> {
  const { id, method, params } = req;

  try {
    const result = await browserManager.dispatch(method, params ?? {});
    sendResponse({ jsonrpc: "2.0", id, result });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    sendError(id, -32603, message);
  }
}

rl.on("line", (line) => {
  let req: JsonRpcRequest;
  try {
    req = JSON.parse(line) as JsonRpcRequest;
  } catch {
    sendError(null, -32700, "Parse error");
    return;
  }

  if (req.jsonrpc !== "2.0" || typeof req.method !== "string") {
    sendError(req.id ?? null, -32600, "Invalid JSON-RPC request");
    return;
  }

  void handleRequest(req);
});

rl.on("close", async () => {
  await browserManager.shutdown();
  process.exit(0);
});

process.on("SIGTERM", async () => {
  await browserManager.shutdown();
  process.exit(0);
});

process.on("SIGINT", async () => {
  await browserManager.shutdown();
  process.exit(0);
});

process.stderr.write("[playwright-sidecar] Ready\n");
