import { cp, mkdir, readdir, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

async function exists(file) { try { await stat(file); return true; } catch { return false; } }
async function copyTree(source, destination) {
  if (!source || !await exists(source)) return;
  await mkdir(destination, { recursive: true });
  for (const entry of await readdir(source, { withFileTypes: true })) {
    if (entry.name === '.git') continue;
    const from = path.join(source, entry.name), to = path.join(destination, entry.name);
    if (entry.isSymbolicLink()) throw new Error(`Pages assets must not contain symlinks: ${entry.name}`);
    if (entry.isDirectory()) await copyTree(from, to);
    else if (entry.isFile()) await cp(from, to);
  }
}
async function bytesIn(directory) {
  let bytes = 0;
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) bytes += await bytesIn(file);
    else if (entry.isFile()) bytes += (await stat(file)).size;
  }
  return bytes;
}
export async function preparePages({ site, reports, runId, attempt, previous, baseline, maxBytes = 900 * 1024 * 1024, maxRuns = 3 }) {
  if (!/^\d+$/.test(String(runId)) || !/^[1-9]\d*$/.test(String(attempt))) throw new Error('Numeric run ID and positive attempt are required');
  const resolvedSite = path.resolve(site);
  for (const input of [reports, previous, baseline].filter(Boolean)) {
    const relative = path.relative(resolvedSite, path.resolve(input));
    if (!relative || (!relative.startsWith('..') && !path.isAbsolute(relative))) throw new Error('Pages inputs must live outside the output site');
  }
  await rm(site, { recursive: true, force: true });
  await copyTree(previous, site);
  await copyTree(baseline, site);
  await mkdir(site, { recursive: true });
  const runs = path.join(site, 'midscene/runs');
  const current = path.join(runs, String(runId), String(attempt));
  await rm(current, { recursive: true, force: true });
  await copyTree(reports, current);
  await mkdir(runs, { recursive: true });
  let retained = (await readdir(runs, { withFileTypes: true })).filter(entry => entry.isDirectory() && /^\d+$/.test(entry.name)).map(entry => entry.name).sort((a, b) => Number(a) - Number(b));
  for (const old of retained.slice(0, -maxRuns)) await rm(path.join(runs, old), { recursive: true });
  retained = retained.slice(-maxRuns);
  while (await bytesIn(site) > maxBytes && retained.length > 1) await rm(path.join(runs, retained.shift()), { recursive: true });
  const links = [];
  for (const id of retained) {
    const attempts = (await readdir(path.join(runs, id), { withFileTypes: true })).filter(entry => entry.isDirectory() && /^\d+$/.test(entry.name)).map(entry => entry.name).sort((a, b) => Number(b) - Number(a));
    for (const value of attempts) {
      let report;
      for (const candidate of ['native/index.html', 'native.html']) if (await exists(path.join(runs, id, value, candidate))) { report = candidate; break; }
      links.push(report ? `<li><a href="runs/${id}/${value}/${report}">Run ${id}, attempt ${value}</a></li>` : `<li>Run ${id}, attempt ${value}: partial reports are available in workflow artifacts.</li>`);
    }
  }
  await writeFile(path.join(site, 'midscene/index.html'), `<!doctype html><meta charset="utf-8"><title>Tinycast Midscene reports</title><h1>Tinycast Midscene reports</h1><ul>${links.join('')}</ul>`);
  if (!await exists(path.join(site, 'index.html'))) await writeFile(path.join(site, 'index.html'), '<!doctype html><meta charset="utf-8"><a href="midscene/">Tinycast Midscene reports</a>');
  await writeFile(path.join(site, '.nojekyll'), '');
  const bytes = await bytesIn(site);
  if (bytes > maxBytes) throw new Error('Pages site exceeds its size limit; original artifacts remain available');
  return { bytes, retained };
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await preparePages({ site: process.env.PAGES_SITE, reports: process.env.PAGES_REPORTS, runId: process.env.GITHUB_RUN_ID, attempt: process.env.GITHUB_RUN_ATTEMPT, previous: process.env.PAGES_PREVIOUS, baseline: process.env.PAGES_BASELINE });
}
