import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm, access, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { preparePages } from './prepare-pages.mjs';
async function fixture(run) {
  const root = await mkdtemp(path.join(tmpdir(), 'tinycast-pages-'));
  try {
    const reports = path.join(root, 'reports'), baseline = path.join(root, 'baseline'), previous = path.join(root, 'previous'), site = path.join(root, 'site');
    for (const directory of [reports, baseline, previous, site]) await mkdir(directory);
    await writeFile(path.join(baseline, 'index.html'), 'Existing user website');
    await writeFile(path.join(baseline, 'CNAME'), 'existing.example.test');
    await mkdir(path.join(baseline, '.git')); await writeFile(path.join(baseline, '.git/config'), 'must not publish');
    await writeFile(path.join(reports, 'native.html'), 'Native HTML');
    await run({ site, reports, baseline, previous, runId: '12', attempt: '2' });
  } finally { await rm(root, { recursive: true, force: true }); }
}
test('publication preserves the root site, exact run/attempt paths and trusted history', () => fixture(async options => {
  const old = path.join(options.previous, 'midscene/runs/11/1');
  await mkdir(old, { recursive: true }); await writeFile(path.join(old, 'native.html'), 'Previous report');
  await preparePages(options);
  assert.equal(await readFile(path.join(options.site, 'index.html'), 'utf8'), 'Existing user website');
  assert.equal(await readFile(path.join(options.site, 'CNAME'), 'utf8'), 'existing.example.test');
  await assert.rejects(access(path.join(options.site, '.git/config')));
  await access(path.join(options.site, 'midscene/runs/11/1/native.html'));
  await access(path.join(options.site, 'midscene/runs/12/2/native.html'));
}));
test('rerun removes stale current content while retaining partial case reports on merge failure', () => fixture(async options => {
  await preparePages(options);
  await rm(path.join(options.reports, 'native.html'));
  await writeFile(path.join(options.reports, 'calculator-expression.html'), 'Available original case');
  await preparePages(options);
  await assert.rejects(access(path.join(options.site, 'midscene/runs/12/2/native.html')));
  await access(path.join(options.site, 'midscene/runs/12/2/calculator-expression.html'));
  assert.equal(await readFile(path.join(options.site, 'index.html'), 'utf8'), 'Existing user website');
}));
test('size limits and unsafe inputs fail without deleting original artifacts', () => fixture(async options => {
  await assert.rejects(preparePages({ ...options, maxBytes: 1 }), /size limit/);
  await access(path.join(options.reports, 'native.html'));
  await assert.rejects(preparePages({ ...options, runId: '../escape' }), /Numeric/);
  await assert.rejects(preparePages({ ...options, site: options.reports }), /outside/);
  await symlink('/tmp', path.join(options.baseline, 'outside'));
  await assert.rejects(preparePages(options), /symlinks/);
}));
