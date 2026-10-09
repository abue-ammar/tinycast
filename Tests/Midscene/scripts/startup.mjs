import { setTimeout as delay } from 'node:timers/promises';

export async function waitForOwnedWindow({ pid, inspect, raise, timeoutMs = 30_000, now = Date.now, pause = delay }) {
  const started = now();
  const attempts = [];
  const warnings = [];
  let inspection;
  while (now() - started < timeoutMs) {
    try {
      inspection = await inspect();
      if (Number(inspection.windowCount) > 0 && inspection.focusedApplicationPID === pid) {
        return { ready: true, inspection, attempts, warnings, elapsedMs: now() - started };
      }
      attempts.push({ phase: 'inspect', elapsedMs: now() - started, inspection });
      if (Number(inspection.windowCount) > 0) {
        try { await raise(); }
        catch (error) { warnings.push({ phase: 'raise', elapsedMs: now() - started, error: String(error) }); }
      }
    } catch (error) { warnings.push({ phase: 'inspect', elapsedMs: now() - started, error: String(error) }); }
    await pause(100);
  }
  return { ready: false, inspection, attempts, warnings, elapsedMs: now() - started };
}
