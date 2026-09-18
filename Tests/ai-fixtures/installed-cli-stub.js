#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");

const root = process.env.TC_INSTALLED_STUB_ROOT;
const command = path.basename(process.argv[1]);
const args = process.argv.slice(2);

function record(name, value) {
  fs.appendFileSync(path.join(root, name), value + "\n");
}

record(command + "-args.log", JSON.stringify(args));

if (command === "opencode" && args.slice(0, 2).join(" ") === "session delete") {
  record("deleted.log", args[2]);
  process.exit(0);
}

if (command === "agent") {
  if (args.includes("--version")) {
    console.log("2026.1.0");
    process.exit(0);
  }
  if (args[0] === "status") {
    console.log(JSON.stringify({ isAuthenticated: true }));
    process.exit(0);
  }
  if (args.includes("--list-models")) {
    console.log(`Available models

auto - Auto (current, default)
composer-2.5 - Composer 2.5
`);
    process.exit(0);
  }
}

if (command === "grok" && args.slice(0, 2).join(" ") === "sessions delete") {
  record("grok-deleted.log", args[2]);
  process.exit(0);
}

const promptFile = args.indexOf("--prompt-file");
const prompt = promptFile >= 0 && args[promptFile + 1]
  ? fs.readFileSync(args[promptFile + 1], "utf8")
  : fs.readFileSync(0, "utf8");
record(command + "-prompt.log", prompt);
record(command + "-environment.log", process.env.OPENCODE_CONFIG_CONTENT ?? "");
record(command + "-grok-environment.log", process.env.GROK_DISABLE_AUTOUPDATER ?? "");

const modelIndex = args.indexOf("--model");
const model = modelIndex >= 0 ? args[modelIndex + 1] : "";
if (model === "oversized-frame") {
  const limit = Number(process.env.TC_INSTALLED_MAX_LINE_BYTES || 8 * 1_048_576);
  // One byte past the runner's complete-frame limit, terminated so the
  // partial-line guard never sees it.
  process.stdout.write("x".repeat(limit + 1) + "\n");
  process.exit(0);
}

if (command === "opencode") {
  console.log(JSON.stringify({ type: "step_start", sessionID: "ses_stub", part: {} }));
  console.log(JSON.stringify({
    type: "text", sessionID: "ses_stub", part: { text: "OpenCode reply" }
  }));
  console.log(JSON.stringify({
    type: "step_finish", sessionID: "ses_stub",
    part: { tokens: { input: 9, output: 2 } }
  }));
} else if (command === "agent") {
  const chatsRoot = process.env.TC_CURSOR_CHATS_ROOT;
  if (chatsRoot) {
    fs.mkdirSync(path.join(chatsRoot, "ws", "ses_cursor"), { recursive: true });
  }
  console.log(JSON.stringify({
    type: "system", subtype: "init", session_id: "ses_cursor"
  }));
  console.log(JSON.stringify({
    type: "assistant",
    timestamp_ms: 1,
    message: { content: [{ type: "text", text: "Cursor " }] }
  }));
  console.log(JSON.stringify({
    type: "assistant",
    model_call_id: "call_1",
    message: { content: [{ type: "text", text: "Cursor reply" }] }
  }));
  console.log(JSON.stringify({
    type: "assistant",
    message: { content: [{ type: "text", text: "Cursor reply" }] }
  }));
  console.log(JSON.stringify({
    type: "result", subtype: "success", result: "Cursor reply"
  }));
} else if (command === "grok") {
  console.log(JSON.stringify({
    type: "system", subtype: "init", session_id: "ses_stub"
  }));
  console.log(JSON.stringify({
    type: "stream_event", session_id: "ses_stub",
    event: { delta: { type: "text_delta", text: "Grok reply" } }
  }));
  console.log(JSON.stringify({
    type: "result", is_error: false, session_id: "ses_stub",
    usage: { input_tokens: 8, output_tokens: 2 }
  }));
} else {
  console.log(JSON.stringify({
    type: "stream_event", event: { delta: { type: "text_delta", text: "Claude reply" } }
  }));
  console.log(JSON.stringify({
    type: "result", is_error: false, usage: { input_tokens: 8, output_tokens: 2 }
  }));
}
