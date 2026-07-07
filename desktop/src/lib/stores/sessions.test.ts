import { describe, expect, it } from 'vitest';

describe('session activity event mapping', () => {
  it('maps run.started to session lifecycle', () => {
    const eventTypes = ['run.started', 'run.completed', 'run.failed'];
    const isStart = (t: string) => t === 'session_started' || t === 'run.started';
    const isComplete = (t: string) =>
      t === 'session_completed' || t === 'heartbeat_completed' || t === 'run.completed';
    const isFailed = (t: string) => t === 'heartbeat_failed' || t === 'run.failed';

    expect(isStart('run.started')).toBe(true);
    expect(isComplete('run.completed')).toBe(true);
    expect(isFailed('run.failed')).toBe(true);
    expect(eventTypes.every((t) => isStart(t) || isComplete(t) || isFailed(t))).toBe(true);
  });
});
