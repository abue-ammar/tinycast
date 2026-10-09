import { setTimeout as delay } from 'node:timers/promises';

export async function waitForOwnedWindow({ pid, inspect, raise, timeoutMs = 30_000, now = Date.now, pause = delay, checkAlive = () => {} }) {
  const started = now();
  const attempts = [];
  const warnings = [];
  let inspection;
  const ready = sample => Number(sample?.windowCount) > 0 && sample?.focusedApplicationPID === pid;
  while (now() - started < timeoutMs) {
    checkAlive();
    try {
      inspection = await inspect();
      if (ready(inspection)) return { ready: true, inspection, attempts, warnings, elapsedMs: now() - started };
      attempts.push({ phase: 'inspect', elapsedMs: now() - started, inspection });
    } catch (error) { warnings.push({ phase: 'inspect', elapsedMs: now() - started, error: String(error) }); }
    try {
      const raised = await raise();
      if (raised) {
        inspection = raised;
        attempts.push({ phase: 'raise', elapsedMs: now() - started, inspection });
        if (ready(inspection)) return { ready: true, inspection, attempts, warnings, elapsedMs: now() - started };
      }
    } catch (error) { warnings.push({ phase: 'raise', elapsedMs: now() - started, error: String(error) }); }
    await pause(100);
  }
  return { ready: false, inspection, attempts, warnings, elapsedMs: now() - started };
}
