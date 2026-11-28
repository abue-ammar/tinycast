#!/usr/bin/env node
// Stands in for `codex`. `mcp list` reports no servers of the reader's own. `app-server` logs each
// method to $TC_CODEX_STUB_ROOT/received, answers every request with an empty result, holds after
// `pause` until a `resume` file appears, and logs `eof` once its input ends.

import fs from "node:fs";
import path from "node:path";

if (process.argv.includes("mcp")) {
    fs.writeSync(1, "[]\n");
    process.exit(0);
}

const root = process.env.TC_CODEX_STUB_ROOT;
const record = (entry) => fs.appendFileSync(path.join(root, "received"), entry + "\n");
const send = (message) => fs.writeSync(1, JSON.stringify(message) + "\n");
const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

function* lines() {
    const chunk = Buffer.alloc(65_536);
    let pending = "";
    for (;;) {
        let read = 0;
        try {
            read = fs.readSync(0, chunk, 0, chunk.length, null);
        } catch (error) {
            if (error.code === "EAGAIN") { sleep(2); continue; }
            if (error.code === "EOF") break;
            throw error;
        }
        if (read === 0) break;
        pending += chunk.toString("utf8", 0, read);
        let newline;
        while ((newline = pending.indexOf("\n")) !== -1) {
            yield pending.slice(0, newline);
            pending = pending.slice(newline + 1);
        }
    }
    // A frame cut short by a closed input is logged, so a test can tell it from a whole one.
    if (pending) record("partial");
}

for (const line of lines()) {
    let message;
    try {
        message = JSON.parse(line);
    } catch {
        record("garbled");
        continue;
    }
    if (typeof message.method !== "string") continue;
    record(message.method);
    if (message.id !== undefined && message.id !== null) send({ id: message.id, result: {} });
    if (message.method === "pause") {
        while (!fs.existsSync(path.join(root, "resume"))) sleep(2);
    }
}
record("eof");
