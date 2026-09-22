#!/usr/bin/env node
// A fake Codex app-server that stalls exactly where Stop races the turn ID.
//
// The real server names a turn twice — once in the `turn/started` notification, once in the
// `turn/start` response — and either can be arbitrarily late. Each mode withholds one or both so
// `codex-turn-test` can Stop inside that window and watch what the runner does about it.
//
// `parallel` serves one thread per request and holds both replies until the harness releases them,
// so two turns are live at once.
//
// `TC_STUB_ROOT` is the scratch directory the harness and this process signal through;
// `TC_STUB_MODE` picks which half of the turn ID to withhold, or `parallel`.

import fs from "node:fs";
import path from "node:path";

const ROOT = process.env.TC_STUB_ROOT;
const MODE = process.env.TC_STUB_MODE ?? "hold-turn";
const THREAD = "thread-1";
const TURN = "turn-1";
const ARGV = process.argv.slice(2);

// Synchronous throughout, like the blocking script this replaces: the stalls below are the point,
// and an event loop would read the next line while one of them is still holding.
const emit = (message) => fs.writeSync(1, JSON.stringify(message) + "\n");
const record = (line) => fs.appendFileSync(path.join(ROOT, "received.log"), line + "\n");
const mark = (name) => fs.closeSync(fs.openSync(path.join(ROOT, name), "w"));

const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

/** The harness releases the stall. Bounded, so a failing assertion never hangs CI. */
function awaitMark(name, timeout = 20_000) {
    const deadline = Date.now() + timeout;
    while (Date.now() < deadline) {
        if (fs.existsSync(path.join(ROOT, name))) return true;
        sleep(5);
    }
    return false;
}

/** One line at a time off fd 0, so nothing is buffered past the stall that is meant to see it. */
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

// `mcp list --json` exits at once, so a launch learns what to disable without starting it.
if (ARGV.includes("mcp") && ARGV.includes("list")) {
    fs.appendFileSync(path.join(ROOT, "list-argv.log"), JSON.stringify(ARGV) + "\n");
    // Held open so two launches, or a launch and a Stop, can overlap inside the read.
    sleep(Number(process.env.TC_STUB_LIST_DELAY ?? 0));
    if (MODE === "list-fails") process.exit(1);
    if (MODE === "list-garbage") {
        fs.writeSync(1, "warning: this is not the list\n");
        process.exit(0);
    }
    const servers = [
        { name: "user-one", enabled: true, transport: { type: "stdio" } },
        { name: "user-two", enabled: true, transport: { type: "streamable_http" } },
        { name: "probe", enabled: true, transport: { type: "stdio" } },
    ];
    if (MODE === "list-dotted") servers.push({ name: "has.dot", enabled: true });
    fs.writeSync(1, JSON.stringify(servers) + "\n");
    process.exit(0);
}

fs.appendFileSync(path.join(ROOT, "argv.log"), JSON.stringify(ARGV) + "\n");
fs.appendFileSync(
    path.join(ROOT, "env.log"),
    JSON.stringify(
        Object.fromEntries(
            Object.entries(process.env).filter(([key]) => key.startsWith("TC_MCP_")))) + "\n");

/** One MCP call, from the item that names it to the elicitation that gates it. */
function toolCall(index, read) {
    // `mcp-foreign` asks on behalf of the reader's own `probe`, which Tinycast must never answer.
    const server = MODE === "mcp-foreign" ? "probe" : "tinycast-probe";
    const item = {
        type: "mcpToolCall",
        id: `call-${index}`,
        server,
        tool: "safe_echo",
        status: "inProgress",
        arguments: { message: "one" },
        readOnlyHint: false,
    };
    emit({ method: "item/started", params: { threadId: THREAD, item } });
    if (MODE !== "mcp" && MODE !== "mcp-foreign") return;
    emit({
        id: 900 + index,
        method: "mcpServer/elicitation/request",
        params: {
            serverName: server,
            threadId: THREAD,
            turnId: TURN,
            message: "Allow the probe MCP server to run tool “safe_echo”?",
            _meta: {
                codex_approval_kind: "mcp_tool_call",
                persist: ["session", "always"],
                tool_title: "Safe Echo",
                tool_params: { message: "one" },
            },
        },
    });
    const reply = JSON.parse(read.next().value ?? "{}");
    record(`elicitation:${JSON.stringify(reply.result ?? reply.error ?? {})}`);
    const accepted = reply.result && reply.result.action === "accept";
    emit({
        method: "item/completed",
        params: {
            threadId: THREAD,
            item: {
                ...item,
                status: accepted ? "completed" : "failed",
                error: accepted ? null : { message: "user rejected MCP tool call" },
            },
        },
    });
}

/** Two calls started together and asked about together, as a parallel turn would. */
function toolPair(read) {
    const tools = ["first_tool", "second_tool"];
    const items = tools.map((tool, index) => ({
        type: "mcpToolCall", id: `call-${index + 1}`, server: "tinycast-probe", tool,
        status: "inProgress", arguments: {},
    }));
    for (const item of items) emit({ method: "item/started", params: { threadId: THREAD, item } });
    tools.forEach((tool, index) => emit({
        id: 900 + index,
        method: "mcpServer/elicitation/request",
        params: {
            serverName: "tinycast-probe", threadId: THREAD, turnId: TURN,
            message: `Allow the probe MCP server to run tool “${tool}”?`,
            _meta: { codex_approval_kind: "mcp_tool_call", tool_name: tool },
        },
    }));
    for (const _ of tools) {
        const reply = JSON.parse(read.next().value ?? "{}");
        record(`elicitation:${JSON.stringify(reply.result ?? reply.error ?? {})}`);
    }
    for (const item of items) {
        emit({
            method: "item/completed",
            params: { threadId: THREAD, item: { ...item, status: "completed" } },
        });
    }
}

// The real server refuses every request before `initialize`.
let initialized = false;
let threads = 0;
let turns = 0;

/** Answers at once, then holds the second turn until `release` and finishes both. */
function parallelTurn(message) {
    turns += 1;
    const thread = message.params?.threadId;
    const turn = `turn-${turns}`;
    record(`turn-params:${JSON.stringify(message.params ?? {})}`);
    emit({ id: message.id, result: { turn: { id: turn } } });
    emit({ method: "turn/started", params: { threadId: thread, turn: { id: turn } } });
    // Two summary parts, the first split across deltas: only the part change is a paragraph.
    for (const [summaryIndex, delta] of [[0, "**Planning**"], [0, " done."], [1, "**Checking**"]]) {
        emit({
            method: "item/reasoning/summaryTextDelta",
            params: { threadId: thread, itemId: "rs-1", summaryIndex, delta }
        });
    }
    emit({ method: "item/agentMessage/delta", params: { threadId: thread, delta: `from ${thread}` } });
    if (turns < 2) return;
    awaitMark("release");
    for (let index = 1; index <= 2; index += 1) {
        emit({
            method: "turn/completed",
            params: { threadId: `thread-${index}`, turn: { id: `turn-${index}`, status: "completed" } }
        });
    }
}

const input = lines();
for (;;) {
    const next = input.next();
    if (next.done) break;
    const line = next.value;
    if (!line.trim()) continue;
    const message = JSON.parse(line);
    const method = message.method;
    const requestID = message.id;
    record(method ?? "?");

    if (method === "initialize") {
        initialized = true;
        emit({ id: requestID, result: {} });
    } else if (!initialized && requestID !== undefined && requestID !== null) {
        emit({ id: requestID, error: { code: -32600, message: "Not initialized" } });
    } else if (method === "thread/start") {
        record(`thread-params:${JSON.stringify(message.params ?? {})}`);
        threads += 1;
        const thread = MODE === "parallel" ? `thread-${threads}` : THREAD;
        emit({ id: requestID, result: { thread: { id: thread } } });
    } else if (method === "turn/start" && MODE === "parallel") {
        parallelTurn(message);
    } else if (method === "turn/start") {
        record(`turn-params:${JSON.stringify(message.params ?? {})}`);
        if (MODE.startsWith("mcp")) {
            emit({ method: "turn/started", params: { threadId: THREAD, turn: { id: TURN } } });
            emit({ id: requestID, result: { turn: { id: TURN } } });
            // `mcp-many` calls past the largest step Settings offers, then answers.
            const calls = { "mcp-rounds": 3, "mcp-many": 120 }[MODE] ?? 1;
            if (MODE === "mcp-pair") toolPair(input);
            else for (let index = 1; index <= calls; index += 1) toolCall(index, input);
            if (MODE === "mcp-many") {
                emit({
                    method: "item/agentMessage/delta",
                    params: { threadId: THREAD, delta: "done" },
                });
            }
            emit({
                method: "turn/completed",
                params: { threadId: THREAD, turn: { id: TURN, status: "completed" } },
            });
            continue;
        }
        mark("turn-start-received");
        awaitMark("stop-landed");
        emit({ method: "turn/started", params: { threadId: THREAD, turn: { id: TURN } } });
        // `hold-turn` never answers the request: the interrupt has to come from the notification
        // alone. `hold-both` answers it too, so a turn named twice is still interrupted once.
        if (MODE === "hold-both") emit({ id: requestID, result: { turn: { id: TURN } } });
    } else if (method === "account/read") {
        emit({ id: requestID, result: { account: { type: "chatgpt", planType: "plus" } } });
    } else if (method === "turn/interrupt") {
        const params = message.params ?? {};
        record(`interrupt:${params.threadId}:${params.turnId}`);
        emit({ id: requestID, result: {} });
    } else if (requestID !== undefined && requestID !== null) {
        emit({ id: requestID, result: {} });
    }
}
record("stdin-closed");
