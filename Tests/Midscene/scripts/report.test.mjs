import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm, access } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { assemble } from './report.mjs';
import { collect } from './collect.mjs';
async function fixture(fn) {
  const root = await mkdtemp(path.join(tmpdir(), 'tinycast-report-'));
  try {
    const dir = path.join(root, 'shard'); await mkdir(dir);
    const cases = await collect();
    for (const c of cases) {
      await writeFile(path.join(dir, `${c.id}.html`), 'native placeholder');
      await writeFile(path.join(dir, `${c.id}.png`), 'png placeholder');
    }
    await writeFile(path.join(dir, 'results.json'), JSON.stringify(cases.map(c => ({ id: c.id, status: 'passed', report: `${c.id}.html`, screenshot: `${c.id}.png` }))));
    await fn(root, dir);
  } finally { await rm(root, { recursive: true, force: true }); }
}
const opts = root => ({ directory: root, baseUrl: 'https://example.test/runs/123/2', summary: path.join(root, 'summary.md') });
const merge = async ({ outputDir }) => {
  const mergedReportPath = path.join(outputDir, 'native.html');
  await mkdir(path.dirname(mergedReportPath), { recursive: true }); await writeFile(mergedReportPath, 'merged');
  return { mergedReportPath };
};
test('complete table links to exact reports and screenshots', () => fixture(async root => {
  assert.equal(await assemble({ ...opts(root), merge }), true);
  const summary = await readFile(opts(root).summary, 'utf8');
  const [first] = await collect();
  assert.ok(summary.includes(`https://example.test/runs/123/2/shard/${first.id}.html`));
  assert.match(summary, /<a href="[^"]+\.html"><img src="[^"]+\.png"[^>]+width="160">/);
}));
test('failed merge keeps per-case files and deletes partial output', () => fixture(async (root, dir) => {
  assert.equal(await assemble({ ...opts(root), merge: async args => { await merge(args); throw new Error('merge failed'); } }), false);
  const [first] = await collect();
  await access(path.join(dir, `${first.id}.html`));
  await assert.rejects(access(path.join(root, 'native.html')));
  assert.match(await readFile(opts(root).summary, 'utf8'), /Individual reports remain/);
}));
test('incomplete rerun removes old merge and reports missing cases', () => fixture(async (root, dir) => {
  await assemble({ ...opts(root), merge });
  await writeFile(path.join(dir, 'results.json'), '[]');
  for (const c of await collect()) {
    await rm(path.join(dir, `${c.id}.html`));
    await rm(path.join(dir, `${c.id}.png`));
  }
  assert.equal(await assemble({ ...opts(root), merge }), false);
  await assert.rejects(access(path.join(root, 'native.html')));
  assert.match(await readFile(opts(root).summary, 'utf8'), /Missing/);
}));
test('unknown shards fail rather than silently running nothing', async () => {
  await assert.rejects(collect('typo'), /No cases/);
});
test('failed case retains a usable combined report and exact case links', () => fixture(async (root, dir) => {
  const results = JSON.parse(await readFile(path.join(dir, 'results.json'), 'utf8'));
  results[0].status = 'failed';
  await writeFile(path.join(dir, 'results.json'), JSON.stringify(results));
  assert.equal(await assemble({ ...opts(root), merge }), false);
  await access(path.join(root, 'native.html'));
  const summary = await readFile(opts(root).summary, 'utf8');
  assert.ok(summary.includes(`/shard/${results[0].id}.html`));
  assert.match(summary, /Failed/);
}));
test('missing result metadata still publishes native reports and screenshots without passing', () => fixture(async (root, dir) => {
  await rm(path.join(dir, 'results.json'));
  const cases = await collect();
  const [first] = cases;
  const framework = path.join(dir, 'framework');
  await mkdir(framework);
  await writeFile(path.join(framework, 'results.json'), 'not harness metadata');
  await writeFile(path.join(framework, `${first.id}.html`), 'nested framework output');
  await writeFile(path.join(dir, 'unrelated.html'), 'unrelated report');
  let selected;
  assert.equal(await assemble({ ...opts(root), merge: async args => {
    selected = args.htmlPaths;
    return merge(args);
  } }), false);
  assert.equal(selected.length, cases.length);
  assert.ok(selected.every(file => path.dirname(file) === dir));
  await access(path.join(root, 'native.html'));
  const summary = await readFile(opts(root).summary, 'utf8');
  assert.ok(summary.includes(`/shard/${first.id}.html`));
  assert.ok(summary.includes(`/shard/${first.id}.png`));
  assert.match(summary, /\| ⚠️ Missing: No case result was recorded/);
}));
test('SDK automatic report copies do not conflict with canonical exports', () => fixture(async (root, dir) => {
  const [first] = await collect();
  const automatic = path.join(dir, 'report');
  await mkdir(automatic);
  await writeFile(path.join(automatic, `${first.id}.html`), 'SDK automatic report copy');
  await writeFile(path.join(automatic, `${first.id}.png`), 'SDK screenshot copy');
  let selected;
  assert.equal(await assemble({ ...opts(root), merge: async args => {
    selected = args.htmlPaths;
    return merge(args);
  } }), true);
  assert.ok(selected.every(file => path.dirname(file) === dir));
  await access(path.join(automatic, `${first.id}.html`));
  assert.doesNotMatch(await readFile(opts(root).summary, 'utf8'), /Ambiguous/);
}));
test('ambiguous artifacts remain intact and are never silently selected', () => fixture(async (root, dir) => {
  const [first] = await collect();
  const duplicate = path.join(root, 'duplicate-shard');
  await mkdir(duplicate);
  await writeFile(path.join(duplicate, `${first.id}.html`), 'duplicate native report');
  let selected;
  assert.equal(await assemble({ ...opts(root), merge: async args => {
    selected = args.htmlPaths;
    return merge(args);
  } }), false);
  assert.ok(selected.every(file => path.basename(file) !== `${first.id}.html`));
  await access(path.join(dir, `${first.id}.html`));
  await access(path.join(duplicate, `${first.id}.html`));
  const summary = await readFile(opts(root).summary, 'utf8');
  assert.match(summary, /Ambiguous/);
  assert.match(summary, /Files are retained; no report was selected/);
}));
test('SDK native standalone HTML merges without a model or desktop', () => fixture(async (root, dir) => {
  const { Agent, mergeReportFiles } = await import('@midscene/core');
  const agent = new Agent({ interfaceType: 'static', actionSpace: () => [], destroy: async () => {} }, { generateReport: false });
  try {
    // Record a synthetic log using the SDK rather than inventing its HTML schema.
    await agent.recordToReport('Synthetic harness entry', { content: 'No model call', screenshots: [{ base64: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aC9sAAAAASUVORK5CYII=' }] });
    const html = agent.reportHTMLString({ inlineScreenshots: true });
    for (const c of await collect()) await writeFile(path.join(dir, `${c.id}.html`), html);
    assert.equal(await assemble({ ...opts(root), merge: mergeReportFiles }), true);
    const merged = await readFile(path.join(root, 'native.html'), 'utf8');
    assert.match(merged, /Synthetic harness entry/);
  } finally { await agent.destroy(); }
}));
test('native framework steps supply exact case links and durations', () => fixture(async (root, dir) => {
  const [first] = await collect();
  const framework = path.join(dir, 'framework', 'native');
  await mkdir(framework, { recursive: true });
  const dump = { projects: [{ documents: [{ cases: [{ name: first.id, attempts: [{ durationMs: 65000, steps: [{ id: 'real-step:4', status: 'success', agentDetails: [{ executionId: 'execution' }] }] }] }] }] }] };
  await writeFile(path.join(framework, 'index.html'), `<script type="midscene_test_run_dump">${JSON.stringify(dump)}</script>`);
  await writeFile(path.join(dir, 'model.json'), JSON.stringify({ modelName: 'test-model' }));
  assert.equal(await assemble({ ...opts(root), runUrl: 'https://github.com/example/repo/actions/runs/123', merge }), true);
  const summary = await readFile(opts(root).summary, 'utf8');
  assert.match(summary, /framework\/native\/index\.html#runner-step=real-step%3A4/);
  assert.match(summary, /<a href="[^\"]+#runner-step=real-step%3A4"><img/);
  assert.match(summary, /\*\*Models:\*\* test-model/);
  assert.match(summary, /1m 5s/);
  assert.match(summary, /actions\/runs\/123#artifacts/);
}));
test('failed and not-run cases precede the collapsed passed appendix', () => fixture(async (root, dir) => {
  const results = JSON.parse(await readFile(path.join(dir, 'results.json'), 'utf8'));
  results[1] = { ...results[1], status: 'failed', reason: 'Visible result differs', durationMs: 1200 };
  results[2].status = 'not-run';
  await writeFile(path.join(dir, 'results.json'), JSON.stringify(results));
  assert.equal(await assemble({ ...opts(root), merge }), false);
  const summary = await readFile(opts(root).summary, 'utf8');
  assert.match(summary, /2 need attention · 1 passed/);
  assert.match(summary, /❌ Failed: Visible result differs/);
  assert.match(summary, /⏭️ Not run/);
  const appendix = summary.indexOf('<summary>Appendix: passed cases (1)</summary>');
  assert.ok(summary.indexOf('Visible result differs') < appendix);
  assert.ok(summary.indexOf('⏭️ Not run') < appendix);
}));
test('single shard summary does not claim other shards are missing or run a merger', () => fixture(async (root, dir) => {
  const cases = await collect('calculator');
  await writeFile(path.join(dir, 'results.json'), JSON.stringify(cases.map(c => ({ id: c.id, status: 'passed' }))));
  assert.equal(await assemble({ ...opts(root), shard: 'calculator' }), true);
  const summary = await readFile(opts(root).summary, 'utf8');
  assert.match(summary, /0 need attention · 2 passed/);
  assert.doesNotMatch(summary, /launcher-fixture|Merge failed/);
  await assert.rejects(access(path.join(root, 'native.html')));
}));
test('producer failure and duplicate results cannot render a false all-pass summary', () => fixture(async (root, dir) => {
  const results = JSON.parse(await readFile(path.join(dir, 'results.json'), 'utf8'));
  results.push(results[0]);
  await writeFile(path.join(dir, 'results.json'), JSON.stringify(results));
  assert.equal(await assemble({ ...opts(root), producerResult: 'failure', merge }), false);
  const summary = await readFile(opts(root).summary, 'utf8');
  assert.match(summary, /Duplicate case result/);
  assert.doesNotMatch(summary, /🎉 All/);
}));
test('complete framework inventory merges native Test reports once instead of standalone exports', () => fixture(async (root, dir) => {
  const cases = await collect();
  const framework = path.join(dir, 'framework', 'native');
  await mkdir(framework, { recursive: true });
  const dump = { projects: [{ documents: [{ cases: cases.map(c => ({ name: c.id, status: 'success', attempts: [{ steps: [{ id: `recorded-${c.id}`, status: 'success', agentDetails: [{}] }] }] })) }] }] };
  const index = path.join(framework, 'index.html');
  await writeFile(index, `<script type="midscene_test_run_dump">${JSON.stringify(dump)}</script>`);
  let selected;
  assert.equal(await assemble({ ...opts(root), merge: async args => { selected = args.htmlPaths; return merge(args); } }), true);
  assert.deepEqual(selected, [index]);
}));
test('read-only publication summaries preserve merged reports and expose aggregation/source/status', () => fixture(async root => {
  await mkdir(path.join(root, 'native'));
  const native = path.join(root, 'native/index.html');
  await writeFile(native, 'native report must stay byte-for-byte unchanged');
  assert.equal(await assemble({ ...opts(root), runUrl: 'https://github.com/example/tinycast/actions/runs/456', sourceRunId: '123', reportResult: 'success', publicationResult: 'skipped' }), true);
  assert.equal(await readFile(native, 'utf8'), 'native report must stay byte-for-byte unchanged');
  const summary = await readFile(opts(root).summary, 'utf8');
  assert.match(summary, /runs\/123#artifacts/);
  assert.match(summary, /no new model calls/);
  assert.match(summary, /Report aggregation: \*\*success\*\*/);
  assert.match(summary, /Pages publication: \*\*skipped\*\*/);
}));
test('publication-independent Summary acknowledges the native artifact without claiming hosted links', () => fixture(async root => {
  await writeFile(path.join(root, 'native.html'), 'retained native report');
  assert.equal(await assemble({ ...opts(root), baseUrl: '', publicationResult: 'pending' }), true);
  const summary = await readFile(opts(root).summary, 'utf8');
  assert.match(summary, /Native Midscene Test report included in the artifact/);
  assert.match(summary, /Pages publication: \*\*pending\*\*/);
  assert.doesNotMatch(summary, /<img|Open the Midscene Test report|\| Shard \||<details>|Appendix: passed/);
}));

test('published Summary exposes shard counts and an explicit report column with exact screenshots', () => fixture(async (root, dir) => {
  await assemble(opts(root));
  const summary = await readFile(opts(root).summary, 'utf8');
  assert.match(summary, /### Shard results/);
  assert.match(summary, /\| Shard \| Case \| Report \| Screenshot \| Status \| Duration \|/);
  assert.match(summary, /\[Report\]\(https:\/\/example.test\/runs\/123\/2\/shard\/calculator-expression.html\)/);
  assert.match(summary, /<img src="https:\/\/example.test\/runs\/123\/2\/shard\/calculator-expression.png"[^>]+width="160"/);
}));
