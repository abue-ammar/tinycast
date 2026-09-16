#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");

const root = process.env.TC_INSTALLED_STUB_ROOT;
const command = path.basename(process.argv[1]);

function record(name, value) {
  fs.appendFileSync(path.join(root, name), value + "\n");
}

record(command + "-args.log", JSON.stringify(process.argv.slice(2)));

if (command === "opencode" && process.argv.slice(2, 4).join(" ") === "session delete") {
  record("deleted.log", process.argv[4]);
  process.exit(0);
}

if (command === "grok" && process.argv.slice(2, 4).join(" ") === "sessions delete") {
  record("grok-deleted.log", process.argv[4]);
  process.exit(0);
}

const promptFile = process.argv.indexOf("--prompt-file");
const prompt = promptFile >= 0 && process.argv[promptFile + 1]
  ? fs.readFileSync(process.argv[promptFile + 1], "utf8")
  : fs.readFileSync(0, "utf8");
record(command + "-prompt.log", prompt);
record(command + "-environment.log", process.env.OPENCODE_CONFIG_CONTENT ?? "");
record(command + "-grok-environment.log", process.env.GROK_DISABLE_AUTOUPDATER ?? "");

if (command === "opencode") {
  console.log(JSON.stringify({ type: "step_start", sessionID: "ses_stub", part: {} }));
  console.log(JSON.stringify({
    type: "text", sessionID: "ses_stub", part: { text: "OpenCode reply" }
  }));
  console.log(JSON.stringify({
    type: "step_finish", sessionID: "ses_stub",
    part: { tokens: { input: 9, output: 2 } }
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
