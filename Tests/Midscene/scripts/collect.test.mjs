import { test } from 'node:test';
import assert from 'node:assert/strict';
import { collect, validateAISteps } from './collect.mjs';

const steps = (...nodes) => nodes.map(node => ({ node }));

test('an action-only journey cannot pass collection', () => {
  assert.throws(() => validateAISteps('missing-assertion', steps('app.open', 'aiAct')), /AI-native actions\/assertions required: missing-assertion/);
});

test('an earlier assertion cannot cover a later unverified action', () => {
  assert.throws(() => validateAISteps('unverified-action', steps('app.open', 'aiAct', 'aiAssert', 'aiAct')), /must end with aiAssert.*unverified-action/);
});

test('multi-action journeys and intermediate assertions can end with a visible result assertion', () => {
  assert.doesNotThrow(() => validateAISteps('complete-flow', steps('app.open', 'aiAct', 'aiAct', 'aiAssert', 'aiAct', 'aiAssert')));
});

test('all executable project cases satisfy the assertion policy', async () => {
  const cases = await collect();
  assert.ok(cases.length > 0);
});
