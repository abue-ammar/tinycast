import { test } from 'node:test';
import assert from 'node:assert/strict';
import { waitForOwnedWindow } from './startup.mjs';
const ready = { windowCount: 1, focusedApplicationPID: 7 };
test('an already focused owned window returns without raising or pausing', async () => {
  const result = await waitForOwnedWindow({ pid: 7, inspect: () => ready, raise: () => assert.fail('unnecessary raise'), pause: () => assert.fail('unnecessary wait') });
  assert.equal(result.ready, true);
  assert.deepEqual(result.warnings, []);
});
test('historical inspection and raise errors remain warnings after readiness succeeds', async () => {
  let count = 0, time = 0;
  const result = await waitForOwnedWindow({ pid: 7, now: () => time, pause: async ms => { time += ms; }, inspect: () => {
    if (++count === 1) throw new Error('temporarily unavailable');
    return count === 2 ? { windowCount: 1, focusedApplicationPID: 8 } : ready;
  }, raise: () => { if (count === 2) throw new Error('raise unavailable'); } });
  assert.equal(result.ready, true);
  assert.equal(result.warnings.length, 2);
  assert.deepEqual(result.inspection, ready);
});
test('an absent owned window cannot pass readiness even after activation', async () => {
  let time = 0;
  const result = await waitForOwnedWindow({ pid: 7, timeoutMs: 200, now: () => time, pause: async ms => { time += ms; }, inspect: () => ({ windowCount: 0, focusedApplicationPID: 7 }), raise: () => ({ windowCount: 0, focusedApplicationPID: 7 }) });
  assert.equal(result.ready, false);
  assert.equal(result.attempts.length, 4);
});

test('an exited owned process aborts immediately instead of becoming a retry warning', async () => {
  await assert.rejects(waitForOwnedWindow({ pid: 7, checkAlive: () => { throw new Error('process exited'); }, inspect: () => assert.fail('process already exited'), raise: () => assert.fail('process already exited') }), /process exited/);
});

test('native activation readiness is retained without a second inspection or AppleScript wait', async () => {
  let inspections = 0;
  const result = await waitForOwnedWindow({ pid: 7, inspect: () => {
    assert.equal(++inspections, 1);
    return { windowCount: 1, focusedApplicationPID: 0 };
  }, raise: () => ready, pause: () => assert.fail('native activation already confirmed focus') });
  assert.equal(result.ready, true);
  assert.deepEqual(result.inspection, ready);
  assert.equal(result.attempts.at(-1).phase, 'raise');
});

test('a transient inspection error cannot prevent a guarded native activation from confirming readiness', async () => {
  const result = await waitForOwnedWindow({ pid: 7, inspect: () => { throw new Error('inspection unavailable'); }, raise: () => ready, pause: () => assert.fail('activation already ready') });
  assert.equal(result.ready, true);
  assert.equal(result.warnings.length, 1);
});
