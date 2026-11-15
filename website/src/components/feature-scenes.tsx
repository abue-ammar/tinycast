import { Search } from "lucide-react";
import { useId, type CSSProperties, type ReactNode } from "react";
import type { FeaturePreview } from "../data/features";
import { cn } from "../lib/cn";

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

// The palette scenes copy HeroPalette's measurements one unit per point, in the
// same 640×360 space as Stage, so the shell's corner sits at (12, 12).
const shell = { left: 12, top: 12, right: 628, bottom: 348 };
const listTop = shell.top + 46;
const rowHeight = 38;
const footerCenter = shell.bottom - 26;

// The real window draws no outline and no rule; spacing alone separates its parts.
function PaletteStage({
  query,
  footer,
  children,
}: {
  query: ReactNode;
  footer: ReactNode;
  children: ReactNode;
}) {
  const dissolve = useId();
  return (
    <div aria-hidden="true" className="@container size-full p-[1.875%]">
      <div className="glass-palette size-full rounded-[4.22cqw]">
        <span aria-hidden="true" className="glass-grain" />
        <svg viewBox="12 12 616 336" className="scene relative size-full">
          <defs>
            <linearGradient
              id={`${dissolve}-fade`}
              gradientUnits="userSpaceOnUse"
              x1="0"
              x2="0"
              y1={shell.bottom - 80}
              y2={shell.bottom}
            >
              <stop offset="0" stopColor="white" />
              <stop offset="0.5" stopColor="white" stopOpacity="0.25" />
              <stop offset="1" stopColor="white" stopOpacity="0" />
            </linearGradient>
            <mask id={dissolve} maskUnits="userSpaceOnUse">
              <rect
                x={shell.left}
                y={shell.top}
                width={shell.right - shell.left}
                height={shell.bottom - shell.top}
                fill={`url(#${dissolve}-fade)`}
              />
            </mask>
          </defs>
          {query}
          <g mask={`url(#${dissolve})`}>{children}</g>
          {footer}
        </svg>
      </div>
    </div>
  );
}

function PaletteQuery({ children }: { children: ReactNode }) {
  return (
    <>
      <Search
        x={28}
        y={27}
        size={22}
        strokeWidth={1.75}
        className="text-(--glass-fg-muted)"
      />
      <text x="58" y="45" fontSize="20" className="fill-(--glass-fg)">
        {children}
      </text>
    </>
  );
}

function PaletteKeycap({ x, label }: { x: number; label: string }) {
  return (
    <g>
      <rect
        x={x + 0.5}
        y={footerCenter - 8.5}
        width="17"
        height="17"
        rx="5.5"
        className="fill-none stroke-(--glass-border)"
      />
      <text
        x={x + 9}
        y={footerCenter + 3.5}
        fontSize="10"
        textAnchor="middle"
        className="fill-(--glass-fg-muted)"
      >
        {label}
      </text>
    </g>
  );
}

// SVG text cannot be measured before layout, so the capsule sizes each label from
// an average glyph width and pins it there with textLength.
const footerTextWidth = (label: string) => Math.round(label.length * 6.1);

function PaletteFooter({ action, start }: { action: string; start: number }) {
  const actionWidth = footerTextWidth(action);
  const actionsWidth = footerTextWidth("Actions");
  const width = actionWidth + actionsWidth + 110;
  const left = shell.right - 8 - width;
  const actionsLeft = left + actionWidth + 54;
  return (
    <g className="scene-in" style={at(start)}>
      <circle
        cx={shell.left + 26}
        cy={footerCenter}
        r="17.5"
        className="fill-(--glass-control) stroke-(--glass-control-rim)"
      />
      <path
        d={`M${shell.left + 19} ${footerCenter - 2.25}h14M${shell.left + 19} ${footerCenter + 2.25}h8`}
        className="fill-none stroke-(--glass-fg-muted)"
        strokeWidth="1.5"
        strokeLinecap="round"
      />
      <rect
        x={left + 0.5}
        y={footerCenter - 17.5}
        width={width - 1}
        height="35"
        rx="17.5"
        className="fill-(--glass-control) stroke-(--glass-control-rim)"
      />
      <g fontSize="12" fontWeight="500">
        <text
          x={left + 12}
          y={footerCenter + 4}
          textLength={actionWidth}
          lengthAdjust="spacing"
          className="fill-(--glass-fg)"
        >
          {action}
        </text>
        <text
          x={actionsLeft}
          y={footerCenter + 4}
          textLength={actionsWidth}
          lengthAdjust="spacing"
          className="fill-(--glass-fg-muted)"
        >
          Actions
        </text>
      </g>
      <PaletteKeycap x={left + actionWidth + 18} label="↵" />
      <PaletteKeycap x={actionsLeft + actionsWidth + 6} label="⌘" />
      <PaletteKeycap x={actionsLeft + actionsWidth + 26} label="K" />
    </g>
  );
}

function PaletteSectionLabel({
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
      fontWeight="500"
      className="scene-in fill-(--glass-fg-muted)"
      style={at(start)}
    >
      {children}
    </text>
  );
}

function PaletteRow({
  top,
  name,
  kind,
  tint,
  start,
}: {
  top: number;
  name: string;
  kind: string;
  tint: string;
  start: number;
}) {
  return (
    <g className="scene-in" style={at(start)}>
      <rect x="30" y={top + 8} width="22" height="22" rx="5" className={tint} />
      <text x="64" y={top + 23.5} fontSize="13" className="fill-(--glass-fg)">
        {name}
      </text>
      <text
        x="612"
        y={top + 23}
        fontSize="12"
        textAnchor="end"
        className="fill-(--glass-fg-muted)"
      >
        {kind}
      </text>
    </g>
  );
}

// A section header is 4pt above its 11pt line and 4pt below; every later one adds 12pt.
const firstRowTop = listTop + 22;
const laterSectionHeader = 30;

function LauncherScene() {
  const secondHeader = firstRowTop + rowHeight * 2;
  const groups = [
    {
      label: "Favorites",
      labelY: listTop + 15,
      firstTop: firstRowTop,
      first: 0,
      rows: [
        { name: "Safari", tint: "fill-cyan" },
        { name: "Slack", tint: "fill-violet-deep" },
      ],
    },
    {
      label: "Applications",
      labelY: secondHeader + 23,
      firstTop: secondHeader + laterSectionHeader,
      first: 2,
      rows: [
        { name: "Spotify", tint: "fill-violet" },
        { name: "System Settings", tint: "fill-tint/20" },
        { name: "Sublime Text", tint: "fill-violet-bright" },
      ],
    },
  ];
  return (
    <PaletteStage
      query={
        <PaletteQuery>
          <Typed text="s" start={300} step={0} />
          <Caret start={300} />
        </PaletteQuery>
      }
      footer={<PaletteFooter action="Open Application" start={1000} />}
    >
      <rect
        x="20"
        y={firstRowTop}
        width="600"
        height={rowHeight}
        rx="10"
        className="scene-launcher-select fill-(--glass-selection)"
        style={at(900)}
      />
      <rect
        x="20"
        y={firstRowTop}
        width="600"
        height={rowHeight}
        rx="10"
        className="scene-flash fill-violet/30"
        style={at(4600)}
      />
      {groups.map((group) => (
        <g key={group.label}>
          <PaletteSectionLabel y={group.labelY} start={500 + group.first * 70}>
            {group.label}
          </PaletteSectionLabel>
          {group.rows.map((row, i) => (
            <PaletteRow
              key={row.name}
              top={group.firstTop + i * rowHeight}
              name={row.name}
              kind="Application"
              tint={row.tint}
              start={550 + (group.first + i) * 70}
            />
          ))}
        </g>
      ))}
    </PaletteStage>
  );
}

// One lead card, as the app draws an answer: both sides in it, a bare arrow between.
function CalculatorScene() {
  const cardTop = listTop + 4;
  const columns = [
    {
      x: 176,
      value: "560 km",
      unit: "Kilometers",
      weight: "500",
      start: 1150,
    },
    {
      x: 464,
      value: "347.97 mi",
      unit: "Miles",
      weight: "600",
      start: 1500,
    },
  ];
  return (
    <PaletteStage
      query={
        <PaletteQuery>
          <Typed text="560 km to mi" start={250} step={70} />
          <Caret start={1020} />
        </PaletteQuery>
      }
      footer={<PaletteFooter action="Copy Answer" start={2300} />}
    >
      <rect
        x="20"
        y={cardTop}
        width="600"
        height="116"
        rx="10"
        className="scene-in fill-(--glass-selection)"
        style={at(1100)}
      />
      {columns.map((column) => (
        <g key={column.unit} className="scene-in" style={at(column.start)}>
          <text
            x={column.x}
            y={cardTop + 56}
            fontSize="28"
            fontWeight={column.weight}
            textAnchor="middle"
            className="fill-(--glass-fg)"
          >
            {column.value}
          </text>
          <rect
            x={column.x - column.unit.length * 3.2 - 6}
            y={cardTop + 70}
            width={column.unit.length * 6.4 + 12}
            height="17"
            rx="6"
            className="fill-tint/10"
          />
          <text
            x={column.x}
            y={cardTop + 82}
            fontSize="10.5"
            textAnchor="middle"
            className="fill-(--glass-fg-muted)"
          >
            {column.unit}
          </text>
        </g>
      ))}
      <path
        d={`M311 ${cardTop + 47}h18m-6.5-6.5 6.5 6.5-6.5 6.5`}
        className="scene-pop fill-none stroke-(--glass-fg-muted) opacity-60"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        style={at(1350)}
      />
    </PaletteStage>
  );
}

function ClipboardScene() {
  const listRight = shell.left + 290;
  const rows = [
    { label: "brew install --cask…", tint: "fill-tint/10", isMono: true },
    { label: "#863BFF", tint: "fill-violet", isMono: true },
    { label: "Screenshot.png", tint: "fill-cyan/70", isMono: false },
    { label: "tinycast.app", tint: "fill-tint/10", isMono: false },
  ];
  const previewLeft = listRight + 25;
  return (
    <PaletteStage
      query={
        <PaletteQuery>
          <tspan className="fill-(--glass-fg-muted)">
            Search clipboard history
          </tspan>
        </PaletteQuery>
      }
      footer={<PaletteFooter action="Paste" start={2500} />}
    >
      <rect
        x={listRight}
        y={listTop}
        width="1"
        height={shell.bottom - listTop}
        className="fill-tint/10"
      />
      <PaletteSectionLabel y={listTop + 15} start={150}>
        Today
      </PaletteSectionLabel>
      <rect
        x="20"
        y={firstRowTop}
        width={listRight - 28}
        height={rowHeight}
        rx="10"
        className="scene-clip-select fill-(--glass-selection)"
        style={at(1500)}
      />
      {rows.map((row, i) => (
        <g key={row.label} className="scene-in" style={at(200 + i * 80)}>
          <rect
            x="30"
            y={firstRowTop + i * rowHeight + 8}
            width="22"
            height="22"
            rx="5"
            className={row.tint}
          />
          <text
            x="64"
            y={firstRowTop + i * rowHeight + 23.5}
            fontSize="13"
            className={cn(
              "fill-(--glass-fg)",
              row.isMono && "font-mono text-[12px]",
            )}
          >
            {row.label}
          </text>
        </g>
      ))}
      <text
        x={previewLeft}
        y={listTop + 30}
        fontSize="13"
        className="scene-out fill-(--glass-fg-muted) font-mono"
        style={at(1500)}
      >
        brew install --cask tinycast
      </text>
      <rect
        x={previewLeft}
        y={listTop + 16}
        width="140"
        height="140"
        rx="22"
        className="scene-pop fill-violet"
        style={at(1650)}
      />
      <g className="scene-in" style={at(1850)}>
        <text
          x={previewLeft + 160}
          y={listTop + 80}
          fontSize="22"
          className="fill-(--glass-fg) font-mono"
        >
          #863BFF
        </text>
        <text
          x={previewLeft + 160}
          y={listTop + 104}
          fontSize="12"
          className="fill-(--glass-fg-muted) font-mono"
        >
          rgb(134, 59, 255)
        </text>
      </g>
    </PaletteStage>
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
  return (
    <div aria-hidden="true" className="size-full p-[1.9%]">
      <div className="flex size-full flex-col rounded-[14px] border border-border-strong bg-surface p-2.5">
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
