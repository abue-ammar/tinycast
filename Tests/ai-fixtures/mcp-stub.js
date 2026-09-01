#!/usr/bin/env node
// A minimal MCP server over stdio. `TC_MCP_MODE` picks which way it misbehaves.

import fs from "node:fs";

const MODE = process.env.TC_MCP_MODE ?? "normal";

const TOOLS = [
    {
        name: "read_file",
        description: "Reads a file.",
        inputSchema: { type: "object", properties: { path: { type: "string" } } }
    },
    { name: "write_file", description: "Writes a file." }
];

// Synchronous writes, so a reply is on the pipe before a mode below exits out from under it.
const send = (message) => fs.writeSync(1, JSON.stringify(message) + "\n");
const reply = (id, result) => send({ jsonrpc: "2.0", id, result });

const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

function* lines() {
    const chunk = Buffer.alloc(65_536);
    let pending = "";
    for (;;) {
        let read = 0;
        try {
            read = fs.readSync(0, chunk, 0, chunk.length, null);
        } catch (error) {
            if (error.code === "EAGAIN") { sleep(5); continue; }
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
}

for (const line of lines()) {
    if (!line.trim()) continue;
    const message = JSON.parse(line);
    const { method, id } = message;

    if (method === "initialize") {
        if (MODE === "die-on-initialize") {
            fs.writeSync(2, "the server refused to start\n");
            process.exit(3);
        }
        reply(id, { protocolVersion: "2025-06-18", capabilities: { tools: {} } });
    } else if (method === "notifications/initialized") {
        if (MODE === "unsolicited-request") {
            send({ jsonrpc: "2.0", id: "srv-1", method: "sampling/createMessage" });
        }
    } else if (method === "tools/list") {
        reply(id, { tools: TOOLS });
    } else if (method === "tools/call") {
        if (MODE === "die-on-call") process.exit(4);
        if (MODE === "hang-on-call") continue;
        if (message.params.name === "write_file") {
            reply(id, { isError: true, content: [{ type: "text", text: "read only" }] });
        } else {
            const echoed = JSON.stringify(message.params.arguments ?? {});
            reply(id, { content: [{ type: "text", text: echoed }] });
        }
    } else if (id !== undefined && id !== null) {
        send({ jsonrpc: "2.0", id, error: { code: -32601, message: "no" } });
    }
}
