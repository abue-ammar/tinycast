import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const workflow = await readFile(new URL('../../../.github/workflows/midscene.yml', import.meta.url), 'utf8');
function job(name) {
  const start = workflow.indexOf(`\n  ${name}:\n`);
  assert.notEqual(start, -1);
  const end = workflow.slice(start + 1).search(/\n  [\w-]+:\n/);
  return workflow.slice(start, end < 0 ? undefined : start + 1 + end);
}
function runs(name, overrides = {}) {
  const expression = job(name).match(/^    if: >-\n((?:      .+\n)+)/m)?.[1];
  assert.ok(expression);
  const context = {
    github: { repository: 'abue-ammar/tinycast', ref: 'refs/heads/main', event_name: 'push' },
    inputs: { report_source_run_id: '', publish_pages: true },
    vars: { MIDSCENE_DESKTOP_ENABLED: 'true', MIDSCENE_PUBLISH_REPO: '' },
    needs: { visual: { result: 'success' }, reports: { result: 'success', outputs: { 'report-artifact-name': 'midscene-combined-1' } } },
    ...overrides,
  };
  context.needs = { validation: { outputs: { 'upstream-repository': 'abue-ammar/tinycast' } }, ...context.needs };
  const source = expression.replace(/needs\.([\w-]+)\./g, 'needs["$1"].').replace(/outputs\.([\w-]+)/g, 'outputs["$1"]');
  return Boolean(Function('github', 'inputs', 'vars', 'needs', 'always', 'cancelled', `return (${source});`)(context.github, context.inputs, context.vars, context.needs, () => true, () => context.cancelled ?? false));
}
test('model credentials are limited to upstream main or explicit fork dispatch and never PRs', () => {
  for (const repository of ['abue-ammar/tinycast', 'quanru/tinycast']) {
    for (const event_name of ['push', 'workflow_dispatch', 'pull_request']) {
      for (const ref of ['refs/heads/main', 'refs/heads/feature', 'refs/pull/4/merge']) {
        const expected = event_name !== 'pull_request' && (repository === 'abue-ammar/tinycast' ? ref === 'refs/heads/main' : event_name === 'workflow_dispatch');
        assert.equal(runs('visual', { github: { repository, event_name, ref } }), expected);
      }
    }
  }
  assert.equal(runs('visual', { needs: { validation: { outputs: { 'upstream-repository': '' } } } }), false);
});
test('report-only dispatch skips model execution and Pages but still aggregates and displays results', () => {
  const context = { github: { repository: 'quanru/tinycast', event_name: 'workflow_dispatch', ref: 'refs/heads/feature' }, inputs: { report_source_run_id: '123', publish_pages: false }, needs: { visual: { result: 'skipped' }, reports: { outputs: { 'report-artifact-name': 'midscene-combined-1' } } } };
  assert.equal(runs('visual', context), false);
  for (const name of ['reports', 'available-results', 'report-results']) assert.equal(runs(name, context), true);
  assert.equal(runs('prepare-pages', context), false);
  for (const name of ['swift', 'build', 'desktop-capability']) assert.match(job(name), /if: inputs.report_source_run_id == ''/);
});
test('aggregation is independent of Pages and saves artifacts before enforcing completeness', () => {
  assert.doesNotMatch(job('reports'), /configure-pages|pages: write|MIDSCENE_PUBLISH_REPO|MIDSCENE_REPORT_URL/);
  assert.ok(job('reports').indexOf('Preserve all available reports') < job('reports').indexOf('Require complete reports'));
  assert.match(job('available-results'), /needs: \[visual, reports\]/);
  assert.doesNotMatch(job('available-results'), /needs:.*(?:publish|prepare-pages)/);
  assert.doesNotMatch(job('available-results'), /npm|checkout|run:.*node/);
  for (const result of ['success', 'failure']) assert.equal(runs('reports', { needs: { visual: { result } } }), true);
});
test('Pages needs exact fork opt-in, never enables repository settings, and isolates deployment authority', () => {
  const fork = { github: { repository: 'quanru/tinycast', event_name: 'workflow_dispatch', ref: 'refs/heads/feature' } };
  assert.equal(runs('prepare-pages', fork), false);
  assert.equal(runs('prepare-pages', { ...fork, vars: { MIDSCENE_PUBLISH_REPO: 'quanru/tinycast' } }), true);
  assert.match(job('prepare-pages'), /enablement: false/);
  assert.match(job('prepare-pages'), /pages: read/);
  assert.doesNotMatch(job('prepare-pages'), /pages: write|id-token: write/);
  assert.doesNotMatch(job('publish'), /checkout|npm|run:/);
  assert.match(job('prepare-pages'), /find-previous/);
  assert.match(job('prepare-pages'), /MIDSCENE_PAGES_PRESERVE_REF/);
});
test('source recovery authenticates before artifact download and post-publication summary never remerges', () => {
  for (const name of ['reports', 'report-results']) assert.match(job(name), /trusted-report-runs.mjs validate-source/);
  assert.match(job('report-results'), /inputs.report_source_run_id == '' \|\| steps.source-run.outcome == 'success'/);
  assert.match(job('report-results'), /needs.publish.result == 'success'/);
  assert.match(job('report-results'), /npm run report -- --summary-only/);
  assert.doesNotMatch(job('report-results'), /pages: write|id-token: write|secrets\./);
  assert.match(workflow, /midscene-shard-calculator-\$\{\{ steps.source-run.outputs.source_attempt \|\| github.run_attempt \}\}/);
  assert.match(workflow, /midscene-combined-\$\{\{ github.run_attempt \}\}/);
});
test('result jobs survive aggregation/publication failures but stay absent on PRs', () => {
  for (const result of ['success', 'failure', 'skipped']) assert.equal(runs('report-results', { needs: { visual: { result: 'failure' }, reports: { result } } }), true);
  for (const name of ['reports', 'available-results', 'report-results', 'prepare-pages']) assert.equal(runs(name, { github: { event_name: 'pull_request' }, inputs: { report_source_run_id: '123' } }), false);
  assert.equal(runs('report-results', { cancelled: true }), false);
});

test('visual shards retain reports without writing duplicate user case summaries', () => {
  assert.doesNotMatch(job('visual'), /GITHUB_STEP_SUMMARY|npm run report|Add shard results/);
  assert.match(job('desktop-capability'), /GITHUB_STEP_SUMMARY/);
});

test('a failed case writes the final Summary before its nonzero exit marks the job failed', () => {
  const final = job('report-results');
  assert.match(final, /\n          npm run report -- --summary-only\s*$/);
  assert.doesNotMatch(final, /if npm run report|&&.*GITHUB_STEP_SUMMARY/);
});
