export function validateAISteps(name: string, steps: Array<{ node: string }>): void;
export function collect(shard?: string): Promise<Array<{
  id: string;
  title: string;
  shard: string;
}>>;
