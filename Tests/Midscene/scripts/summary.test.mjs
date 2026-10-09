import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { renderSummary, evidenceFor } from './summary.mjs';
test('Rome layout places attention first and collapses passes with exact screenshot links and duration', () => {
  const markdown = renderSummary({ product: 'Tinycast', models: ['fixture-model (fixture-family)'], runUrl: 'https://github.test/actions/runs/12', nativeReportUrl: 'https://reports.test/native.html', cases: [
    { id: 'pass', title: 'Passed case', shard: 'import', status: 'passed', durationMs: 61000 },
    { id: 'fail', title: 'Failed | <case>', shard: 'navigation', status: 'failed', reason: 'Visible result absent', durationMs: 2500, reportUrl: 'https://reports.test/framework/index.html#runner-step=actual%3Astep', screenshotUrl: 'https://reports.test/screenshots/fail.png' },
    { id: 'missing', title: 'Missing case', shard: 'import', status: 'missing' },
  ] });
  assert.ok(markdown.indexOf('Failed \\| &lt;case&gt;') < markdown.indexOf('<details>'));
  assert.ok(markdown.indexOf('Missing case') < markdown.indexOf('<details>'));
  assert.ok(markdown.indexOf('Passed case') > markdown.indexOf('<details>'));
  assert.match(markdown, /Shard \| Case \| Report \| Screenshot \| Status \/ reason \| Duration/);
  assert.match(markdown, /width="160"/);
  assert.match(markdown, /href="https:\/\/reports.test\/framework\/index.html#runner-step=actual%3Astep"/);
  assert.match(markdown, /1m 1s/);
  assert.match(markdown, /fixture-model \(fixture-family\)/);
  assert.match(markdown, /actions\/runs\/12#artifacts/);
});
test('framework evidence selects the failed step screenshot; standalone exports get no invented runner-step', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'tinycast-summary-'));
  try {
    const screenshot = path.join(root, 'screenshots/failure.png');
    await mkdir(path.dirname(screenshot)); await writeFile(screenshot, 'fixture');
    const file = path.join(root, 'index.html');
    const steps = [
      { id: 'recorded-first', status: 'success', agentDetails: [{ executionId: 'before' }] },
      { id: 'recorded-failure', status: 'failed', error: { message: 'Visible result absent' }, agentDetails: [{ executionId: 'failed' }] },
      { id: 'recorded-last', status: 'success', agentDetails: [{ executionId: 'after' }] },
    ];
    const run = { projects: [{ documents: [{ cases: [{ name: 'case', status: 'failed', attempts: [{ durationMs: 1200, steps }] }] }] }] };
    const dump = { executions: [{ id: 'failed', tasks: [{ uiContext: { screenshot: { path: './screenshots/failure.png' } } }] }] };
    await writeFile(file, `<script type="midscene_test_run_dump">${JSON.stringify(run)}</script><script type="midscene_web_dump">${JSON.stringify(dump)}</script>`);
    const evidence = await evidenceFor(file, 'case', false, root);
    assert.equal(evidence.stepId, 'recorded-failure');
    assert.equal(evidence.screenshot, screenshot);
    assert.equal(evidence.reason, 'Visible result absent');
    assert.equal(evidence.durationMs, 1200);
    await writeFile(file, `<script type="midscene_web_dump">${JSON.stringify(dump)}</script>`);
    assert.equal(await evidenceFor(file, 'case', false, root), null);
  } finally { await rm(root, { recursive: true, force: true }); }
});
test('producer and merge failures remain attention items even with passed case records', () => {
  const markdown = renderSummary({ cases: [{ title: 'Case', shard: 'import', status: 'passed' }], producerResult: 'failure', issues: ['Native merge unavailable'] });
  assert.match(markdown, /failure captured/);
  assert.match(markdown, /2 need attention/);
  assert.match(markdown, /Native merge unavailable/);
  assert.match(markdown, /Workflow failure/);
});
test('empty inventories cannot render an all-passed message', () => {
  const markdown = renderSummary({ cases: [] });
  assert.match(markdown, /failure captured/);
  assert.match(markdown, /No cases were reported/);
  assert.doesNotMatch(markdown, /All 0 cases passed/);
});
