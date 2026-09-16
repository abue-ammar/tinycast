import { CopyButton } from "./copy-button";

// A single shell line with its own copy button — the hero's install CTA. The
// full-page Install section still owns the channel tabs and the DMG fallback.
export function CommandLine({ command }: { command: string }) {
  return (
    <div className="flex items-center gap-3 rounded-xl border border-border bg-well py-1.5 pl-3.5 pr-1.5">
      <span
        aria-hidden="true"
        className="select-none font-mono text-small text-violet-bright"
      >
        $
      </span>
      <code className="min-w-0 flex-1 overflow-x-auto whitespace-pre font-mono text-small text-fg">
        {command}
      </code>
      <CopyButton
        text={command}
        className="text-fg-muted hover:bg-tint/5 hover:text-fg"
      />
    </div>
  );
}
