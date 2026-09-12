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

const prompt = fs.readFileSync(0, "utf8");
record(command + "-prompt.log", prompt);
record(command + "-environment.log", process.env.OPENCODE_CONFIG_CONTENT ?? "");

if (command === "opencode") {
  console.log(JSON.stringify({ type: "step_start", sessionID: "ses_stub", part: {} }));
  console.log(JSON.stringify({
    type: "text", sessionID: "ses_stub", part: { text: "OpenCode reply" }
  }));
  console.log(JSON.stringify({
    type: "step_finish", sessionID: "ses_stub",
    part: { tokens: { input: 9, output: 2 } }
  }));
} else {
  console.log(JSON.stringify({
    type: "stream_event", event: { delta: { type: "text_delta", text: "Claude reply" } }
  }));
  console.log(JSON.stringify({
    type: "result", is_error: false, usage: { input_tokens: 8, output_tokens: 2 }
  }));
}
