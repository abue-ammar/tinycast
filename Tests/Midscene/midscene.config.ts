import { defineNode, z } from '@midscene/test';
import { defineProjectSetup, defineTestProject } from '@midscene/test/config';
import { createMidsceneNodes } from '@midscene/test/midscene';
import { ComputerAgent } from '@midscene/computer';
import { openCase, type DesktopAgent } from './scripts/desktop.ts';
interface Context { agent?: DesktopAgent }
const openInput = z.strictObject({ id: z.enum(['calculator-expression', 'calculator-units', 'launcher-fixture']) });
const appOpen = defineNode<typeof openInput, void, Context>({
  name: 'app.open',
  description: 'Prepare synthetic app fixtures and open a visible Tinycast process with a private bundle, defaults and storage.',
  inputSchema: openInput,
  async execute({ context, input, onTeardown, signal }) {
    context.agent = undefined;
    context.agent = await openCase(input.id, onTeardown, signal);
  },
});
export default defineTestProject<Context>({
  test: { maxConcurrency: 1, testTimeout: 10 * 60_000 },
  output: { reportDir: 'midscene_run/framework' },
  projects: [{
    name: process.env.MIDSCENE_SHARD ? `desktop-${process.env.MIDSCENE_SHARD}` : 'desktop',
    retry: 0,
    setup: defineProjectSetup<Context>({ name: 'desktop', setup: async () => ({}) }),
    files: { include: ['cases/*.yaml'] },
    tags: { include: process.env.MIDSCENE_SHARD ? [process.env.MIDSCENE_SHARD] : [] },
  }],
  nodes: [appOpen, ...createMidsceneNodes<Context>({
    agentClass: ComputerAgent,
    getAgent: ({ context }) => {
      if (!context.agent) throw new Error('Call app.open before AI steps');
      return context.agent;
    },
  })],
});
