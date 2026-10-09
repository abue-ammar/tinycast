import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { collectWorkflowDocument } from '@midscene/test';
import { loadTestProject, discoverTestFiles } from '@midscene/test/config';
export function validateAISteps(name, steps) {
  if (!steps.some(s => s.node === 'aiAct') || !steps.some(s => s.node === 'aiAssert')) throw new Error(`AI-native actions/assertions required: ${name}`);
  if (steps.at(-1)?.node !== 'aiAssert') throw new Error(`Case must end with aiAssert to verify the final visible result: ${name}`);
}
export async function collect(shard) {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const manifest = JSON.parse(await readFile(path.join(root, 'cases.json'), 'utf8'));
  const loaded = await loadTestProject(path.join(root, 'midscene.config.ts'));
  const found = new Map();
  for (const project of loaded.projects) {
    for (const absolutePath of discoverTestFiles(root, project.files)) {
      const doc = collectWorkflowDocument({ projectId: project.projectId, projectName: project.name, sourcePath: path.relative(root, absolutePath), absolutePath }, { resolveNode: project.nodes.get.bind(project.nodes), variables: project.variables, env: process.env });
      for (const c of doc.cases) {
        const { name, tags, steps } = c.definition;
        if (found.has(name)) throw new Error(`Duplicate case: ${name}`);
        const expected = manifest.find(c => c.id === name);
        if (!expected || !tags?.includes(expected.shard)) throw new Error(`Case/shard differs from manifest: ${name}`);
        if (steps[0]?.node !== 'app.open' || steps.filter(s => s.node === 'app.open').length !== 1 || steps[0].input.id !== name) throw new Error(`Case must open its own world: ${name}`);
        validateAISteps(name, steps);
        if (steps.some(s => !['app.open', 'aiAct', 'aiAssert'].includes(s.node))) throw new Error(`Unexpected node: ${name}`);
        found.set(name, expected);
      }
    }
  }
  if (found.size !== manifest.length) throw new Error('Manifest differs from collected YAML cases');
  const selected = [...found.values()].filter(c => !shard || c.shard === shard);
  if (!selected.length) throw new Error(`No cases for shard: ${shard}`);
  return selected;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) console.log(JSON.stringify(await collect(process.env.MIDSCENE_SHARD), null, 2));
