#!/usr/bin/env node
// A stand-in dictation worker speaking DictationWire's frames. Its first argument is its mode:
// `crash` exits after the ready frame, `wait` reads the samples and then waits for its input to end.

import fs from "node:fs";

const MODE = process.argv[2] ?? "normal";

const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

// `null` once the input ends before `count` bytes arrive.
function readExactly(count) {
    const buffer = Buffer.alloc(count);
    let offset = 0;
    while (offset < count) {
        let read = 0;
        try {
            read = fs.readSync(0, buffer, offset, count - offset, null);
        } catch (error) {
            if (error.code === "EAGAIN") { sleep(5); continue; }
            if (error.code === "EOF") return null;
            throw error;
        }
        if (read === 0) return null;
        offset += read;
    }
    return buffer;
}

function send(message) {
    const payload = Buffer.from(JSON.stringify(message));
    const header = Buffer.alloc(4);
    header.writeUInt32LE(payload.length);
    fs.writeSync(1, Buffer.concat([header, payload]));
}

for (;;) {
    const header = readExactly(4);
    if (!header) break;
    const body = readExactly(header.readUInt32LE());
    if (!body) break;
    const request = JSON.parse(body.toString("utf8"));
    send({ id: request.id, status: "ready", text: "" });
    if (MODE === "crash") process.exit(1);
    if (!readExactly(request.sampleCount * 4)) break;
    if (MODE === "wait") {
        readExactly(1);
        break;
    }
    send({ id: request.id, status: "result", text: request.model });
}
