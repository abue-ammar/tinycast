// Checks for `AI` from @raycast/api and `useAI` from @raycast/utils against a mock host: the
// streaming progress channel, the resolved text, abort, canAccess and the failure toast.
//
//   node ai-fixtures.mjs

import { build, transformSync } from "esbuild";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { bootConfig, createHarness, describeTree } from "./test.mjs";

const here = dirname(fileURLToPath(import.meta.url));
let passes = 0;
let failures = 0;

function check(label, condition, extra = "") {
  if (condition) {
    passes++;
    console.log(`  ✓ ${label}`);
  } else {
    failures++;
    console.log(`  ✗ ${label}${extra ? ` — ${extra}` : ""}`);
  }
}

const wait = (ms = 60) => new Promise((resolve) => setTimeout(resolve, ms));

function compile(source) {
  return transformSync(source, {
    loader: "jsx",
    jsx: "automatic",
    format: "cjs",
    target: "es2022",
  }).code;
}

/// Bundled exactly the way `ray build` does it: @raycast/utils inside, the API, React and Node
/// builtins left for the runtime's `require`.
async function bundle(source) {
  const result = await build({
    stdin: { contents: source, loader: "jsx", resolveDir: here },
    bundle: true,
    write: false,
    format: "cjs",
    platform: "node",
    target: "es2022",
    jsx: "automatic",
    external: ["@raycast/api", "react", "react/jsx-runtime", "react-dom"],
    logLevel: "silent",
  });
  return result.outputFiles[0].text;
}

async function run(name, code, mode, verify, { stubs = {}, ai = true, settle = 120 } = {}) {
  console.log(`\n▶ ${name}`);
  const harness = createHarness({ stubs });
  harness.boot(bootConfig({ ai: { available: ai } }));
  harness.start("s1", code, "/fixtures/cmd.js", "/fixtures", mode, {});
  await wait(settle);
  await verify(harness);
  harness.stop("s1");
}

/// A host answer that streams its chunks as progress and then settles with the whole text.
function streamingAsk(chunks, { delay = 5, requests } = {}) {
  return async (args, { progress }) => {
    requests?.push(args[0]);
    for (const chunk of chunks) {
      await wait(delay);
      progress(chunk);
    }
    return chunks.join("");
  };
}

const accessSource = `
import { AI, BrowserExtension, environment } from "@raycast/api";
export default async function Command() {
  globalThis.__access = {
    ai: environment.canAccess(AI),
    browser: environment.canAccess(BrowserExtension),
    nothing: environment.canAccess(undefined),
  };
}
`;

const askSource = `
import { AI } from "@raycast/api";
export default async function Command() {
  const chunks = [];
  const answer = AI.ask("Say hello", { creativity: "low", model: AI.Model["OpenAI_GPT-4o_mini"] });
  answer.on("data", (chunk) => chunks.push(chunk));
  const text = await answer;
  const legacy = await AI.ask("again", { creativity: 7, model: AI.Model["Anthropic_Claude_Imaginary_9"] });
  const custom = await AI.ask("third", { model: { id: "deepseek-chat" } });
  globalThis.__ask = { chunks, text, legacy, custom, creativity: AI.Creativity.Maximum };
}
`;

const abortSource = `
import { AI } from "@raycast/api";
export default async function Command() {
  const controller = new AbortController();
  const chunks = [];
  const answer = AI.ask("long story", { signal: controller.signal });
  answer.on("data", (chunk) => {
    chunks.push(chunk);
    controller.abort();
  });
  try {
    await answer;
    globalThis.__abort = { resolved: true };
  } catch (error) {
    globalThis.__abort = { name: error.name, chunks };
  }
  const early = new AbortController();
  early.abort();
  try {
    await AI.ask("never", { signal: early.signal });
  } catch (error) {
    globalThis.__abort.early = error.name;
  }
}
`;

const failureSource = `
import { AI } from "@raycast/api";
export default async function Command() {
  try {
    await AI.ask("hi");
  } catch (error) {
    globalThis.__failure = error.message;
  }
}
`;

const useAISource = `
import { Detail } from "@raycast/api";
import { useAI } from "@raycast/utils";
export default function Command() {
  const { data, isLoading } = useAI("Explain MCP", { creativity: "none" });
  return <Detail isLoading={isLoading} markdown={data} />;
}
`;

const useAIFailureSource = `
import { Detail } from "@raycast/api";
import { useAI } from "@raycast/utils";
export default function Command() {
  const { data, isLoading, error } = useAI("Explain MCP");
  return <Detail isLoading={isLoading} markdown={error ? "failed: " + error.message : data} />;
}
`;

function findNode(tree, type) {
  const stack = [...(tree?.children ?? [])];
  while (stack.length) {
    const node = stack.shift();
    if (node.type === type) return node;
    stack.push(...(node.children ?? []));
  }
  return undefined;
}

export async function runAIFixtures() {
  passes = 0;
  failures = 0;

  await run("environment.canAccess(AI) follows Settings → AI", compile(accessSource), "no-view", (harness) => {
    const access = harness.call("globalThis.__access");
    check("true when a route is configured", access?.ai === true, JSON.stringify(access));
    check("other gated APIs stay false", access?.browser === false && access?.nothing === false);
  });

  await run("…and is false without one", compile(accessSource), "no-view", (harness) => {
    check("false when nothing is configured", harness.call("globalThis.__access")?.ai === false);
  }, { ai: false });

  const requests = [];
  await run("AI.ask streams data events and resolves the whole text", compile(askSource), "no-view", (harness) => {
    const result = harness.call("globalThis.__ask");
    check("data events carry each chunk in order", JSON.stringify(result?.chunks) === JSON.stringify(["Hel", "lo"]), JSON.stringify(result?.chunks));
    check("await resolves the full answer", result?.text === "Hello", JSON.stringify(result?.text));
    check("creativity names map onto Raycast's 0–2 scale", requests[0]?.creativity === 0.5, JSON.stringify(requests[0]));
    check("an out-of-range number is clamped to 2", requests[1]?.creativity === 2, JSON.stringify(requests[1]));
    check("an AI.Model member crosses as its id", requests[0]?.model === "openai-gpt-4o-mini", JSON.stringify(requests[0]));
    check("an unknown AI.Model name still names its vendor", requests[1]?.model === "anthropic-claude-imaginary-9", JSON.stringify(requests[1]));
    check("{ id } selects a model by its own id", requests[2]?.model === "deepseek-chat", JSON.stringify(requests[2]));
    check("the prompt crosses verbatim", requests[0]?.prompt === "Say hello");
    check("AI.Creativity is populated", result?.creativity === "maximum");
  }, { stubs: { "ai.ask": streamingAsk(["Hel", "lo"], { requests }) } });

  await run("AbortSignal cancels the host call", compile(abortSource), "no-view", (harness) => {
    const result = harness.call("globalThis.__abort");
    check("the promise rejects with AbortError", result?.name === "AbortError", JSON.stringify(result));
    check("no chunk arrives after the abort", result?.chunks?.length === 1, JSON.stringify(result?.chunks));
    check("Swift is asked to cancel the task", (harness.state.cancelled ?? []).length === 1, JSON.stringify(harness.state.cancelled));
    check("an already-aborted signal never reaches Swift", result?.early === "AbortError" && harness.state.hostCalls.filter((name) => name === "ai.ask").length === 1);
  }, { stubs: { "ai.ask": streamingAsk(["one ", "two ", "three"], { delay: 40 }) }, settle: 400 });

  await run("A host failure rejects with its message", compile(failureSource), "no-view", (harness) => {
    check("the reason reaches the extension", harness.call("globalThis.__failure") === "Choose a model in Settings → AI.", String(harness.call("globalThis.__failure")));
  }, {
    stubs: {
      "ai.ask": () => {
        throw new Error("Choose a model in Settings → AI.");
      },
    },
  });

  await run("useAI from @raycast/utils streams into the view", await bundle(useAISource), "view", (harness) => {
    const detail = findNode(harness.state.trees.at(-1), "Detail");
    check("the markdown is the whole answer", detail?.props.markdown === "Hello, MCP", describeTree(harness.state.trees.at(-1) ?? {}));
    check("loading ends once the answer settles", detail?.props.isLoading === false);
    const partial = harness.state.trees.some((tree) => findNode(tree, "Detail")?.props.markdown === "Hello");
    check("a partial answer renders while streaming", partial);
  }, { stubs: { "ai.ask": streamingAsk(["Hello", ", MCP"], { delay: 20 }) }, settle: 400 });

  await run("useAI turns a failure into a Raycast failure toast", await bundle(useAIFailureSource), "view", (harness) => {
    check("showToast is called", harness.state.hostCalls.includes("feedback.showToast"), harness.state.hostCalls.join(","));
    const detail = findNode(harness.state.trees.at(-1), "Detail");
    check("the error reaches the hook", detail?.props.markdown === "failed: Choose a model in Settings → AI.", String(detail?.props.markdown));
  }, {
    stubs: {
      "ai.ask": () => {
        throw new Error("Choose a model in Settings → AI.");
      },
    },
    settle: 300,
  });

  console.log(failures === 0 ? `\nAll ${passes} AI fixtures passed.` : `\n${failures} AI check(s) failed.`);
  return failures;
}

if (import.meta.url === `file://${process.argv[1]}`) process.exit((await runAIFixtures()) === 0 ? 0 : 1);
