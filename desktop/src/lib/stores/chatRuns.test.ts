import { describe, expect, it, beforeEach } from 'vitest';

// Minimal localStorage mock for node environment
const store = new Map<string, string>();
globalThis.localStorage = {
  getItem: (k) => store.get(k) ?? null,
  setItem: (k, v) => { store.set(k, v); },
  removeItem: (k) => { store.delete(k); },
  clear: () => { store.clear(); },
  key: () => null,
  length: 0,
};

describe('chatRunsStore patterns', () => {
  beforeEach(() => {
    store.clear();
  });

  it('mints runs with unique ids', async () => {
    const { chatRunsStore } = await import('./chatRuns.svelte.ts');
    const a = chatRunsStore.mintRun('agent-1', 'Test');
    const b = chatRunsStore.mintRun('agent-2', 'Test 2');
    expect(a.runId).not.toBe(b.runId);
    expect(chatRunsStore.activeRunId).toBe(b.runId);
  });

  it('patches run title', async () => {
    const { chatRunsStore } = await import('./chatRuns.svelte.ts');
    const run = chatRunsStore.mintRun('agent-1', 'Hello');
    chatRunsStore.setTitle(run.runId, 'Updated title');
    expect(chatRunsStore.runs.find((r) => r.runId === run.runId)?.title).toBe('Updated title');
  });

  it('closes run and selects neighbor', async () => {
    const { chatRunsStore } = await import('./chatRuns.svelte.ts');
    const a = chatRunsStore.mintRun('agent-1', 'A');
    const b = chatRunsStore.mintRun('agent-2', 'B');
    chatRunsStore.setActive(a.runId);
    chatRunsStore.closeRun(a.runId);
    expect(chatRunsStore.runs.some((r) => r.runId === a.runId)).toBe(false);
    expect(chatRunsStore.activeRunId).toBe(b.runId);
  });
});
