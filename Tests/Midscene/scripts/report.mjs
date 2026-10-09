import { mkdir, readdir, readFile, rm, writeFile, access } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { collect } from './collect.mjs';
import { artifactUrl, evidenceFor, renderSummary, safeReason } from './summary.mjs';
export async function assemble({ directory, baseUrl = '', summary, merge, shard, runUrl = '', producerResult = 'success', reportResult, publicationResult, sourceRunId }) {
  await mkdir(directory, { recursive: true });
  // Remove only generated merge output; original case artifacts always survive.
  const native = path.join(directory, 'native');
  if (merge) {
    await rm(native, { recursive: true, force: true });
    await rm(`${native}.html`, { force: true });
  }
  const cases = await collect(shard);
  const knownArtifacts = new Set(cases.flatMap(c => [`${c.id}.html`, `${c.id}.png`]));
  const candidates = new Map();
  const warnings = [];
  const results = new Map();
  const durations = new Map();
  const models = new Set();
  const frameworkReports = [];
  async function findFrameworkReports(dir) {
    for (const entry of await readdir(dir, { withFileTypes: true })) {
      const file = path.join(dir, entry.name);
      if (entry.isDirectory() && entry.name !== 'screenshots') await findFrameworkReports(file);
      else if (entry.isFile() && entry.name === 'index.html') frameworkReports.push(file);
    }
  }
  async function walk(dir) {
    for (const e of await readdir(dir, { withFileTypes: true })) {
      const file = path.join(dir, e.name);
      if (e.isDirectory() && e.name === 'framework') await findFrameworkReports(file);
      else if (e.isDirectory() && e.name !== 'report') await walk(file);
      else if (e.isFile() && e.name === 'model.json') {
        try {
          const model = JSON.parse(await readFile(file, 'utf8'));
          if (typeof model.modelName === 'string' && model.modelName) models.add(`${model.modelName}${typeof model.modelFamily === 'string' && model.modelFamily ? ` (${model.modelFamily})` : ''}`);
        } catch { warnings.push(`Unreadable model metadata: ${path.relative(directory, file)}`); }
      } else if (e.isFile() && e.name === 'framework-result.json') {
        try {
          for (const c of JSON.parse(await readFile(file, 'utf8')).cases ?? []) durations.set(c.name, c.run?.durationMs);
        } catch { warnings.push(`Unreadable framework result: ${path.relative(directory, file)}`); }
      } else if (e.name === 'results.json') {
        try {
          for (const r of JSON.parse(await readFile(file, 'utf8'))) {
            if (!cases.some(c => c.id === r.id)) warnings.push(`Unexpected case result: ${r.id}`);
            if (results.has(r.id)) {
              warnings.push(`Duplicate case result: ${r.id}`);
              results.set(r.id, { id: r.id, status: 'incomplete', reason: 'Duplicate case result' });
              continue;
            }
            results.set(r.id, { ...r, dir });
          }
        } catch { warnings.push(`Unreadable case results: ${path.relative(directory, file)}`); }
      } else if (e.isFile() && knownArtifacts.has(e.name)) {
        candidates.set(e.name, [...(candidates.get(e.name) ?? []), file]);
      }
    }
  }
  await walk(directory);
  let complete = results.size === cases.length;
  const htmlPaths = [];
  const nativeFrameworkPaths = new Set();
  let nativeCaseCount = 0;
  const url = file => artifactUrl(baseUrl, directory, file);
  function artifact(id, extension) {
    const files = candidates.get(`${id}.${extension}`) ?? [];
    if (files.length > 1) {
      warnings.push(`Ambiguous ${id}.${extension}: ${files.map(file => path.relative(directory, file)).join(', ')}. Files are retained; no report was selected.`);
      return null;
    }
    return files[0] ?? null;
  }
  const rows = [];
  for (const c of cases) {
    const r = results.get(c.id);
    const report = artifact(c.id, 'html');
    let screenshot = artifact(c.id, 'png');
    if (report) htmlPaths.push(report);
    if (r?.status !== 'passed' || !report || !screenshot) complete = false;
    const matches = [];
    for (const file of frameworkReports) {
      try {
        const evidence = await evidenceFor(file, c.id, r?.status === 'passed', directory);
        if (evidence) matches.push(evidence);
      } catch { warnings.push(`Unreadable native framework report: ${path.relative(directory, file)}`); }
    }
    if (matches.length > 1) warnings.push(`Ambiguous native framework case: ${c.id}`);
    const evidence = matches.length === 1 ? matches[0] : undefined;
    if (evidence) { nativeFrameworkPaths.add(evidence.report); nativeCaseCount += 1; }
    screenshot = evidence?.screenshot ?? screenshot;
    const target = evidence?.report ?? report;
    const reportUrl = target && baseUrl ? `${url(target)}${evidence?.stepId ? `#${new URLSearchParams({ 'runner-step': evidence.stepId })}` : ''}` : undefined;
    let status = r?.status ?? 'missing';
    let reason = r?.reason || evidence?.reason || '';
    if (status === 'passed' && (!report || !screenshot)) { status = 'incomplete'; reason = 'Native report or screenshot missing'; }
    if (status === 'passed' && evidence?.status && evidence.status !== 'success') { status = 'incomplete'; reason = 'Case metadata differs from the native framework result'; }
    if (status !== 'passed') complete = false;
    if (status === 'missing' && !reason) reason = 'No case result was recorded; inspect shard setup and job logs';
    rows.push({ ...c, status, reason, durationMs: r?.durationMs ?? evidence?.durationMs ?? durations.get(c.id), reportUrl, screenshotUrl: screenshot && baseUrl ? url(screenshot) : undefined });
  }
  let merged;
  try {
    if (merge) {
      if (!htmlPaths.length) throw new Error('No native HTML reports');
      const selected = nativeCaseCount === cases.length ? [...nativeFrameworkPaths] : htmlPaths;
      merged = await merge({ htmlPaths: selected, outputDir: directory, outputName: 'native', overwrite: true });
      await access(merged.mergedReportPath);
    }
  } catch (error) {
    merged = undefined;
    complete = false;
    await rm(native, { recursive: true, force: true });
    await rm(`${native}.html`, { force: true });
    warnings.push(`Native report merge failed: ${safeReason(error.message ?? error)}. Individual reports remain available.`);
  }
  let headerReport = merged?.mergedReportPath;
  if (!merge) {
    for (const file of [path.join(native, 'index.html'), `${native}.html`]) {
      try { await access(file); headerReport = file; break; } catch {}
    }
  }
  headerReport ??= shard && frameworkReports.length === 1 ? frameworkReports[0] : undefined;
  if (producerResult !== 'success' || warnings.length) complete = false;
  await writeFile(summary, renderSummary({ product: 'Tinycast', cases: rows, models: [...models].sort(), nativeReportUrl: headerReport && baseUrl ? url(headerReport) : undefined, nativeReportAvailable: Boolean(headerReport), runUrl, producerResult, issues: warnings, reportResult, publicationResult, sourceRunId }));
  return complete;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { mergeReportFiles } = await import('@midscene/core');
  const shard = process.env.MIDSCENE_SUMMARY_SHARD;
  const runUrl = process.env.GITHUB_REPOSITORY ? `${process.env.GITHUB_SERVER_URL ?? 'https://github.com'}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}` : '';
  const ok = await assemble({ directory: path.resolve(process.argv.slice(2).find(value => !value.startsWith('--')) ?? 'midscene_run'), baseUrl: process.env.MIDSCENE_REPORT_URL ?? '', summary: process.env.MIDSCENE_SUMMARY_OUTPUT ?? process.env.GITHUB_STEP_SUMMARY ?? 'summary.md', merge: shard || process.argv.includes('--summary-only') ? undefined : mergeReportFiles, shard, runUrl, producerResult: process.env.MIDSCENE_PRODUCER_RESULT ?? 'success', reportResult: process.env.MIDSCENE_REPORT_RESULT, publicationResult: process.env.MIDSCENE_PUBLICATION_RESULT, sourceRunId: process.env.REPORT_SOURCE_RUN_ID });
  if (!ok) process.exitCode = 1;
}
