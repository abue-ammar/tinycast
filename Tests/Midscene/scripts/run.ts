import { mkdir, rm, writeFile } from 'node:fs/promises';
import { runTestProject } from '@midscene/test/config';
import { collect } from './collect.mjs';
// Thin publication adapter: all collection, execution, cancellation, lifecycle,
// step traces and test results are owned by Midscene Test.
await collect(process.env.MIDSCENE_SHARD);
await rm('midscene_run', { recursive: true, force: true });
await mkdir('midscene_run', { recursive: true });
await writeFile('midscene_run/model.json', JSON.stringify({ modelName: process.env.MIDSCENE_MODEL_NAME ?? null, modelFamily: process.env.MIDSCENE_MODEL_FAMILY ?? null }));
const result = await runTestProject({ resultDir: 'midscene_run/framework', onProgress: console.log });
await writeFile('midscene_run/framework-result.json', JSON.stringify(result, null, 2));
const manifest = await collect();
await writeFile('midscene_run/results.json', JSON.stringify(result.cases.map(c => ({
  id: c.name,
  title: manifest.find(item => item.id === c.name)?.title ?? c.name,
  status: c.status === 'success' ? 'passed' : c.status,
  durationMs: c.run?.durationMs ?? null,
  report: `${c.name}.html`,
  screenshot: `${c.name}.png`,
})), null, 2));
process.exitCode = result.exitCode;
