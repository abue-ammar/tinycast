export function waitForOwnedWindow(options: {
  pid: number;
  inspect: () => Record<string, unknown> | Promise<Record<string, unknown>>;
  raise: () => void | Promise<void>;
  timeoutMs?: number;
  now?: () => number;
  pause?: (milliseconds: number) => Promise<void>;
}): Promise<{ ready: boolean; inspection?: Record<string, unknown>; attempts: unknown[]; warnings: unknown[]; elapsedMs: number }>;
