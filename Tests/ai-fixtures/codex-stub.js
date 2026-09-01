#!/usr/bin/env node
// A fake Codex app-server that stalls exactly where Stop races the turn ID.
//
// The real server names a turn twice — once in the `turn/started` notification, once in the
// `turn/start` response — and either can be arbitrarily late. Each mode withholds one or both so
// `codex-turn-test` can Stop inside that window and watch what the runner does about it.
//
// `TC_STUB_ROOT` is the scratch directory the harness and this process signal through;
// `TC_STUB_MODE` picks which half of the turn ID to withhold.

import fs from "node:fs";
import path from "node:path";

const ROOT = process.env.TC_STUB_ROOT;
const MODE = process.env.TC_STUB_MODE ?? "hold-turn";
const THREAD = "thread-1";
const TURN = "turn-1";

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

for (const line of lines()) {
    if (!line.trim()) continue;
    const message = JSON.parse(line);
    const method = message.method;
    const requestID = message.id;
    record(method ?? "?");

    if (method === "thread/start") {
        emit({ id: requestID, result: { thread: { id: THREAD } } });
    } else if (method === "turn/start") {
        mark("turn-start-received");
        awaitMark("stop-landed");
        emit({ method: "turn/started", params: { threadId: THREAD, turn: { id: TURN } } });
        // `hold-turn` never answers the request: the interrupt has to come from the notification
        // alone. `hold-both` answers it too, so a turn named twice is still interrupted once.
        if (MODE === "hold-both") emit({ id: requestID, result: { turn: { id: TURN } } });
    } else if (method === "turn/interrupt") {
        const params = message.params ?? {};
        record(`interrupt:${params.threadId}:${params.turnId}`);
        emit({ id: requestID, result: {} });
    } else if (requestID !== undefined && requestID !== null) {
        emit({ id: requestID, result: {} });
    }
}
