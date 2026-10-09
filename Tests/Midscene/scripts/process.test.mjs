import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { stopOwnedProcess } from './process.ts';

test('cleanup finishes after an owned process already exited by signal', { timeout: 2000 }, async () => {
  const child = spawn(process.execPath, ['-e', 'process.kill(process.pid, "SIGTERM")']);
  await once(child, 'exit');
  assert.equal(child.signalCode, 'SIGTERM');
  await stopOwnedProcess(child);
});

test('cleanup terminates a live owned process and waits for exit', { timeout: 2000 }, async () => {
  const child = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)']);
  await once(child, 'spawn');
  await stopOwnedProcess(child);
  assert.equal(child.signalCode, 'SIGTERM');
});
