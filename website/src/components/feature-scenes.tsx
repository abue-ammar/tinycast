import type { CSSProperties, ReactNode } from "react";
import type { FeaturePreview } from "../data/features";

// Each scene's resting state is its last frame; the `scene-*` animations in
// index.css only replay the steps that lead there, so reduced motion still
// shows a finished picture. Every label is a real string from the app or docs.

const at = (ms: number) => ({ "--d": `${ms}ms` }) as CSSProperties;

function Stage({ children }: { children: ReactNode }) {
  return (
    <svg viewBox="0 0 640 360" className="scene size-full" aria-hidden="true">
      <rect
        x="12"
        y="12"
        width="616"
        height="336"
        rx="14"
        className="fill-surface stroke-border-strong"
      />
      {children}
    </svg>
  );
}

// Per-letter tspans, so a line can type itself out.
function Typed({
  text,
  start,
  step,
}: {
  text: string;
  start: number;
  step: number;
}) {
  return [...text].map((char, i) => (
    <tspan key={i} className="scene-type" style={at(start + i * step)}>
      {char}
    </tspan>
  ));
}

function Caret({ start }: { start: number }) {
  return (
    <tspan className="scene-caret fill-violet-bright" style={at(start)}>
      |
    </tspan>
  );
}

function Query({ children }: { children: ReactNode }) {
  return (
    <>
      <g
        className="fill-none stroke-fg-subtle"
        strokeWidth="1.8"
        strokeLinecap="round"
      >
        <circle cx="38" cy="37" r="6.5" />
        <path d="m42.8 41.8 4.4 4.4" />
      </g>
      <text x="58" y="44" fontSize="18" className="fill-fg font-rounded">
        {children}
      </text>
      <line x1="12" x2="628" y1="62" y2="62" className="stroke-border" />
    </>
  );
}

function Keycap({ x, y, label }: { x: number; y: number; label: string }) {
  return (
    <g>
      <rect x={x} y={y} width="20" height="18" rx="5" className="fill-tint/8" />
      <text
        x={x + 10}
        y={y + 13}
        fontSize="11"
        textAnchor="middle"
        className="fill-fg-muted"
      >
        {label}
      </text>
    </g>
  );
}

// The palette's bottom bar: the mark on the left, the default action on the right.
function ActionBar({ action, start }: { action: string; start: number }) {
  return (
    <g className="scene-in" style={at(start)}>
      <line x1="12" x2="628" y1="312" y2="312" className="stroke-border" />
      <rect
        x="26"
        y="323"
        width="14"
        height="14"
        rx="4"
        className="fill-violet"
      />
      <text
        x="582"
        y="334"
        fontSize="12"
        textAnchor="end"
        className="fill-fg-muted"
      >
        {action}
      </text>
      <Keycap x={592} y={321} label="↩" />
    </g>
  );
}

function SectionLabel({
  y,
  start,
  children,
}: {
  y: number;
  start: number;
  children: ReactNode;
}) {
  return (
    <text
      x="28"
      y={y}
      fontSize="11"
      className="scene-in fill-fg-subtle"
      style={at(start)}
    >
      {children}
    </text>
  );
}

function ResultRow({
  y,
  name,
  kind,
  tint,
  start,
}: {
  y: number;
  name: string;
  kind: string;
  tint: string;
  start: number;
}) {
  return (
    <g className="scene-in" style={at(start)}>
      <rect x="30" y={y + 7} width="22" height="22" rx="6" className={tint} />
      <text x="64" y={y + 23} fontSize="14" className="fill-fg font-rounded">
        {name}
      </text>
      <text
        x="610"
        y={y + 23}
        fontSize="12"
        textAnchor="end"
        className="fill-fg-subtle"
      >
        {kind}
      </text>
    </g>
  );
}

function LauncherScene() {
  const groups = [
    {
      label: "Favorites",
      y: 82,
      first: 0,
      rows: [
        { name: "Safari", tint: "fill-cyan" },
        { name: "Slack", tint: "fill-violet-deep" },
      ],
    },
    {
      label: "Applications",
      y: 182,
      first: 2,
      rows: [
        { name: "Spotify", tint: "fill-violet" },
        { name: "System Settings", tint: "fill-tint/20" },
        { name: "Sublime Text", tint: "fill-violet-bright" },
      ],
    },
  ];
  return (
    <Stage>
      <Query>
        <Typed text="s" start={300} step={0} />
        <Caret start={300} />
      </Query>
      <rect
        x="20"
        y="88"
        width="600"
        height="36"
        rx="9"
        className="scene-launcher-select fill-tint/8"
        style={at(900)}
      />
      <rect
        x="20"
        y="88"
        width="600"
        height="36"
        rx="9"
        className="scene-flash fill-violet/30"
        style={at(4600)}
      />
      {groups.map((group) => (
        <g key={group.label}>
          <SectionLabel y={group.y} start={500 + group.first * 70}>
            {group.label}
          </SectionLabel>
          {group.rows.map((row, i) => (
            <ResultRow
              key={row.name}
              y={group.y + 6 + i * 38}
              name={row.name}
              kind="Application"
              tint={row.tint}
              start={550 + (group.first + i) * 70}
            />
          ))}
        </g>
      ))}
      <ActionBar action="Open Application" start={1000} />
    </Stage>
  );
}

function CalculatorScene() {
  const cards = [
    { x: 28, value: "560 km", unit: "Kilometers", start: 1150 },
    { x: 340, value: "347.97 mi", unit: "Miles", start: 1500 },
  ];
  return (
    <Stage>
      <Query>
        <Typed text="560 km to mi" start={250} step={70} />
        <Caret start={1020} />
      </Query>
      {cards.map((card) => (
        <g key={card.unit} className="scene-in" style={at(card.start)}>
          <rect
            x={card.x}
            y="84"
            width="272"
            height="170"
            rx="12"
            className="fill-well"
          />
          <text
            x={card.x + 136}
            y="196"
            fontSize="32"
            textAnchor="middle"
            className="fill-fg font-rounded font-bold"
          >
            {card.value}
          </text>
          <text
            x={card.x + 136}
            y="222"
            fontSize="12"
            textAnchor="middle"
            className="fill-fg-subtle"
          >
            {card.unit}
          </text>
        </g>
      ))}
      <g className="scene-pop" style={at(1350)}>
        <circle
          cx="320"
          cy="190"
          r="15"
          className="fill-surface stroke-border-strong"
        />
        <path
          d="M313 190h14m-5-5 5 5-5 5"
          className="fill-none stroke-fg-muted"
          strokeWidth="1.6"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </g>
      <ActionBar action="Copy Answer" start={2300} />
    </Stage>
  );
}

function ClipboardScene() {
  const rows = [
    { label: "brew install --cask…", tint: "fill-tint/10", isMono: true },
    { label: "#863BFF", tint: "fill-violet", isMono: true },
    { label: "Screenshot.png", tint: "fill-cyan/70", isMono: false },
    { label: "tinycast.app", tint: "fill-tint/10", isMono: false },
  ];
  return (
    <Stage>
      <Query>
        <tspan className="fill-fg-subtle">Search clipboard history</tspan>
      </Query>
      <line x1="262" x2="262" y1="62" y2="312" className="stroke-border" />
      <SectionLabel y={81} start={150}>
        Today
      </SectionLabel>
      <rect
        x="20"
        y="88"
        width="234"
        height="36"
        rx="9"
        className="scene-clip-select fill-tint/8"
        style={at(1500)}
      />
      {rows.map((row, i) => (
        <g key={row.label} className="scene-in" style={at(200 + i * 80)}>
          <rect
            x="30"
            y={99 + i * 50}
            width="18"
            height="18"
            rx="5"
            className={row.tint}
          />
          <text
            x="60"
            y={113 + i * 50}
            fontSize="12.5"
            className={
              row.isMono ? "fill-fg font-mono" : "fill-fg font-rounded"
            }
          >
            {row.label}
          </text>
        </g>
      ))}
      <text
        x="286"
        y="100"
        fontSize="13"
        className="scene-out fill-fg-muted font-mono"
        style={at(1500)}
      >
        brew install --cask tinycast
      </text>
      <rect
        x="286"
        y="86"
        width="156"
        height="156"
        rx="24"
        className="scene-pop fill-violet"
        style={at(1650)}
      />
      <g className="scene-in" style={at(1850)}>
        <text x="466" y="150" fontSize="22" className="fill-fg font-mono">
          #863BFF
        </text>
        <text
          x="466"
          y="176"
          fontSize="12"
          className="fill-fg-subtle font-mono"
        >
          rgb(134, 59, 255)
        </text>
      </g>
      <ActionBar action="Paste" start={2500} />
    </Stage>
  );
}

function AiChatScene() {
  const lines = [380, 320, 410, 240];
  return (
    <Stage>
      <text
        x="28"
        y="42"
        fontSize="14"
        className="fill-fg font-rounded font-semibold"
      >
        AI Chat
      </text>
      <rect
        x="532"
        y="26"
        width="84"
        height="22"
        rx="11"
        className="fill-tint/8"
      />
      <g fontSize="11" textAnchor="middle" className="fill-fg-muted">
        <text x="574" y="41" className="scene-out" style={at(1300)}>
          Codex
        </text>
        <g className="scene-out" style={at(2500)}>
          <text x="574" y="41" className="scene-in" style={at(1400)}>
            Grok
          </text>
        </g>
        <text x="574" y="41" className="scene-in" style={at(2600)}>
          Claude
        </text>
      </g>
      <line x1="12" x2="628" y1="62" y2="62" className="stroke-border" />
      <g className="scene-in" style={at(200)}>
        <rect
          x="514"
          y="76"
          width="96"
          height="22"
          rx="11"
          className="fill-tint/8"
        />
        <text
          x="562"
          y="91"
          fontSize="11"
          textAnchor="middle"
          className="fill-fg-muted"
        >
          notes.pdf
        </text>
      </g>
      <g className="scene-pop" style={at(500)}>
        <rect
          x="486"
          y="106"
          width="124"
          height="30"
          rx="15"
          className="fill-violet"
        />
        <text
          x="548"
          y="125"
          fontSize="13"
          textAnchor="middle"
          className="fill-fg font-medium"
        >
          Summarize this
        </text>
      </g>
      <path
        d="M38 150c1.2 6.2 3.8 8.8 10 10-6.2 1.2-8.8 3.8-10 10-1.2-6.2-3.8-8.8-10-10 6.2-1.2 8.8-3.8 10-10Z"
        className="scene-spin fill-violet-bright"
        style={at(1000)}
      />
      {lines.map((width, i) => (
        <rect
          key={width}
          x="62"
          y={154 + i * 18}
          width={width}
          height="8"
          rx="4"
          className="scene-grow fill-tint/12"
          style={at(1250 + i * 150)}
        />
      ))}
      <rect
        x="24"
        y="292"
        width="592"
        height="40"
        rx="11"
        className="fill-well"
      />
      <text x="42" y="316" fontSize="13" className="fill-fg-subtle">
        Ask anything
      </text>
      <Keycap x={584} y={303} label="↩" />
    </Stage>
  );
}

function QuickActionsScene() {
  const items = ["Fix Grammar", "Rewrite", "Translate", "Summarize"];
  const paragraph = [
    { y: 92, width: 520 },
    { y: 172, width: 430 },
    { y: 196, width: 480 },
    { y: 220, width: 300 },
  ];
  return (
    <Stage>
      <text
        x="28"
        y="42"
        fontSize="14"
        className="fill-fg font-rounded font-semibold"
      >
        Release notes
      </text>
      <line x1="12" x2="628" y1="62" y2="62" className="stroke-border" />
      {paragraph.map((line) => (
        <rect
          key={line.y}
          x="28"
          y={line.y}
          width={line.width}
          height="8"
          rx="4"
          className="fill-tint/10"
        />
      ))}
      <g className="scene-out" style={at(2500)}>
        <rect
          x="22"
          y="114"
          width="197"
          height="32"
          rx="6"
          className="scene-grow fill-violet/30"
          style={at(350)}
        />
        <text x="28" y="136" fontSize="18" className="fill-fg font-rounded">
          their shipping it tomorow
        </text>
      </g>
      <text
        x="28"
        y="136"
        fontSize="18"
        className="scene-in fill-fg font-rounded"
        style={at(2600)}
      >
        They’re shipping it tomorrow.
      </text>
      <path
        d="M28 148h217"
        pathLength="1"
        className="scene-draw fill-none stroke-violet-bright"
        strokeWidth="2"
        strokeLinecap="round"
        style={at(2900)}
      />
      <g className="scene-pop" style={at(1000)}>
        <rect
          x="400"
          y="100"
          width="212"
          height="156"
          rx="12"
          className="fill-well stroke-border-strong"
        />
        <rect
          x="408"
          y="108"
          width="196"
          height="32"
          rx="8"
          className="fill-violet/25"
        />
        <rect
          x="408"
          y="108"
          width="196"
          height="32"
          rx="8"
          className="scene-flash fill-violet/40"
          style={at(1900)}
        />
        {items.map((item, i) => (
          <text
            key={item}
            x="422"
            y={129 + i * 36}
            fontSize="13"
            className={i === 0 ? "fill-fg font-medium" : "fill-fg-muted"}
          >
            {item}
          </text>
        ))}
        <path
          d="m580 124 4 4 8-8"
          pathLength="1"
          className="scene-draw fill-none stroke-violet-bright"
          strokeWidth="1.8"
          strokeLinecap="round"
          strokeLinejoin="round"
          style={at(2700)}
        />
      </g>
    </Stage>
  );
}

function ExtensionsScene() {
  const nodes = [
    { x: 40, label: "Extension", glyph: "{ }", start: 200 },
    { x: 245, label: "JavaScriptCore", glyph: "JS", start: 900 },
    { x: 450, label: "SwiftUI", glyph: "▤", start: 1700 },
  ];
  return (
    <Stage>
      {nodes.map((node) => (
        <g key={node.label} className="scene-in" style={at(node.start)}>
          <rect
            x={node.x}
            y="44"
            width="150"
            height="96"
            rx="14"
            className="fill-well stroke-border-strong"
          />
          <text
            x={node.x + 75}
            y="96"
            fontSize="22"
            textAnchor="middle"
            className="fill-fg font-mono"
          >
            {node.glyph}
          </text>
          <text
            x={node.x + 75}
            y="124"
            fontSize="12"
            textAnchor="middle"
            className="fill-fg-muted"
          >
            {node.label}
          </text>
        </g>
      ))}
      {[190, 395].map((x, i) => (
        <g key={x}>
          <path
            d={`M${x} 92h55`}
            pathLength="1"
            className="scene-draw fill-none stroke-border-strong"
            strokeWidth="1.5"
            style={at(600 + i * 800)}
          />
          <circle
            cx={x}
            cy="92"
            r="3"
            className="scene-travel fill-violet-bright"
            style={at(700 + i * 800)}
          />
        </g>
      ))}
      <rect
        x="450"
        y="44"
        width="150"
        height="96"
        rx="14"
        className="scene-in fill-none stroke-violet-bright"
        strokeWidth="1.5"
        style={at(2100)}
      />
      <g className="scene-pop" style={at(2400)}>
        <rect
          x="40"
          y="164"
          width="560"
          height="160"
          rx="12"
          className="fill-canvas stroke-border"
        />
        {[220, 170, 250, 190].map((width, i) => (
          <g key={width}>
            <rect
              x="58"
              y={182 + i * 36}
              width="20"
              height="20"
              rx="6"
              className="fill-violet/40"
            />
            <rect
              x="90"
              y={188 + i * 36}
              width={width}
              height="8"
              rx="4"
              className="scene-grow fill-tint/12"
              style={at(2600 + i * 120)}
            />
            <rect
              x="520"
              y={188 + i * 36}
              width="62"
              height="8"
              rx="4"
              className="fill-tint/6"
            />
          </g>
        ))}
      </g>
    </Stage>
  );
}

function SnippetsScene() {
  const bullets = [360, 290, 330, 250];
  return (
    <Stage>
      <text x="28" y="42" fontSize="13" className="fill-fg-subtle">
        To: team
      </text>
      <line x1="12" x2="628" y1="62" y2="62" className="stroke-border" />
      <text x="28" y="96" fontSize="15" className="fill-fg-muted font-rounded">
        Hi team,
      </text>
      <text
        x="28"
        y="132"
        fontSize="16"
        className="scene-out fill-violet-bright font-mono"
        style={at(1600)}
      >
        <Typed text=";notes" start={400} step={90} />
      </text>
      <g className="scene-in" style={at(1700)}>
        <text
          x="28"
          y="132"
          fontSize="17"
          className="fill-fg font-rounded font-semibold"
        >
          Meeting notes
        </text>
        <text x="28" y="154" fontSize="12" className="fill-fg-subtle">
          Sunday, 13 September
        </text>
        <text x="28" y="188" fontSize="13" className="fill-fg-muted">
          Attendees:
        </text>
        <rect
          x="98"
          y="176"
          width="2"
          height="16"
          rx="1"
          className="scene-caret fill-violet-bright"
        />
      </g>
      {bullets.map((width, i) => (
        <g key={width}>
          <circle
            cx="34"
            cy={222 + i * 22}
            r="2.5"
            className="scene-in fill-fg-subtle"
            style={at(2000 + i * 150)}
          />
          <rect
            x="46"
            y={218 + i * 22}
            width={width}
            height="8"
            rx="4"
            className="scene-grow fill-tint/12"
            style={at(2050 + i * 150)}
          />
        </g>
      ))}
    </Stage>
  );
}

// HTML rather than SVG: the window animates its left edge and width in
// percent, which SVG geometry cannot do across every browser.
function WindowsScene() {
  const layouts = [
    "Left Half",
    "Center Third",
    "First Two Thirds",
    "Right Half",
  ];
  return (
    <div aria-hidden="true" className="size-full p-[1.9%]">
      <div className="flex size-full flex-col gap-2 rounded-[14px] border border-border-strong bg-surface p-2.5">
        <div className="relative min-h-0 flex-1 overflow-hidden rounded-lg border border-border bg-canvas">
          <div className="h-3 border-b border-border bg-tint/4" />
          <div className="scene-window absolute top-[14%] bottom-[5%] rounded-md border border-violet-bright/70 bg-violet/15">
            <div className="flex gap-1 p-2">
              {[0, 1, 2].map((i) => (
                <span key={i} className="size-1.5 rounded-full bg-tint/25" />
              ))}
            </div>
          </div>
        </div>
        <div className="grid font-rounded text-small font-medium text-fg">
          {layouts.map((layout) => (
            <span
              key={layout}
              className="scene-layout-label col-start-1 row-start-1 text-center"
            >
              {layout}
            </span>
          ))}
        </div>
      </div>
    </div>
  );
}

const scenes: Record<FeaturePreview, () => ReactNode> = {
  launcher: LauncherScene,
  calculator: CalculatorScene,
  clipboard: ClipboardScene,
  aiChat: AiChatScene,
  quickActions: QuickActionsScene,
  windows: WindowsScene,
  extensions: ExtensionsScene,
  snippets: SnippetsScene,
};

export function FeatureScene({ preview }: { preview: FeaturePreview }) {
  const Scene = scenes[preview];
  return <Scene />;
}
