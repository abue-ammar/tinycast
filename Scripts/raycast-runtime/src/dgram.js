// `dgram` exists for one case: multicast-dns resolving a `.local` host. The socket never reaches the
// network — mDNSResponder already answers those, so the query goes to the system resolver instead.

import { Buffer } from "./buffer.js";
import { EventEmitter } from "./events.js";
import { hostCall } from "./host.js";

const MDNS_PORT = 5353;
const A_RECORD = 1;
const ANY_RECORD = 255;
const IN_CLASS = 1;

class NameLookupSocket extends EventEmitter {
  constructor() {
    super();
    this.port = MDNS_PORT;
    this.closed = false;
  }

  bind(port, address, callback) {
    if (typeof port === "function") return this.bind(undefined, undefined, port);
    if (typeof address === "function") return this.bind(port, undefined, address);
    if (typeof port === "number") this.port = port;
    if (callback) this.once("listening", callback);
    setTimeout(() => this.emit("listening"), 0);
    return this;
  }

  address() {
    return { address: "0.0.0.0", port: this.port, family: "IPv4" };
  }

  send(buffer, offset = 0, length, port, address, callback) {
    if (port !== MDNS_PORT) {
      throw new Error("dgram only answers mDNS name lookups in Tinycast extensions. See docs/extensions.md.");
    }
    const packet = Buffer.from(buffer);
    this.answer(packet.subarray(offset, offset + (length ?? packet.length)));
    callback?.(null);
    return this;
  }

  close(callback) {
    if (this.closed) return this;
    this.closed = true;
    if (callback) this.once("close", callback);
    setTimeout(() => this.emit("close"), 0);
    return this;
  }

  // The resolver does the multicasting, so joining a group is nothing.
  addMembership() {}
  dropMembership() {}
  setMulticastTTL() {}
  setMulticastLoopback() {}
  setMulticastInterface() {}
  setTTL() {}
  ref() {
    return this;
  }
  unref() {
    return this;
  }

  async answer(packet) {
    const query = decodeQuery(packet);
    if (!query) return;
    const answers = [];
    for (const question of query.questions) {
      if (question.class !== IN_CLASS) continue;
      if (question.type !== A_RECORD && question.type !== ANY_RECORD) continue;
      const addresses = await hostCall("dns", "resolve", [question.name]).catch(() => []);
      for (const address of addresses) answers.push({ name: question.name, address });
    }
    // Silence, the same as a name nothing on the network claims.
    if (this.closed || !answers.length) return;
    const response = encodeResponse(packet, query, answers);
    this.emit("message", response, {
      address: "127.0.0.1", family: "IPv4", port: this.port, size: response.length
    });
  }
}

function decodeQuery(packet) {
  if (packet.length < 12) return null;
  const count = packet.readUInt16BE(4);
  const questions = [];
  let offset = 12;
  for (let index = 0; index < count; index++) {
    const labels = [];
    for (;;) {
      if (offset >= packet.length) return null;
      const size = packet[offset];
      // A query never compresses a name, so a pointer means this is not ours to answer.
      if (size >= 0xc0) return null;
      offset += 1;
      if (size === 0) break;
      labels.push(packet.subarray(offset, offset + size).toString("utf8"));
      offset += size;
    }
    if (offset + 4 > packet.length) return null;
    questions.push({
      name: labels.join("."),
      type: packet.readUInt16BE(offset),
      class: packet.readUInt16BE(offset + 2) & 0x7fff,
    });
    offset += 4;
  }
  return questions.length ? { id: packet.readUInt16BE(0), questions, end: offset } : null;
}

function encodeResponse(packet, query, answers) {
  const header = Buffer.alloc(12);
  header.writeUInt16BE(query.id, 0);
  header.writeUInt16BE(0x8400, 2);
  header.writeUInt16BE(query.questions.length, 4);
  header.writeUInt16BE(answers.length, 6);
  return Buffer.concat([header, packet.subarray(12, query.end), ...answers.map(encodeRecord)]);
}

function encodeRecord({ name, address }) {
  const record = Buffer.alloc(14);
  record.writeUInt16BE(A_RECORD, 0);
  record.writeUInt16BE(1, 2);
  record.writeUInt32BE(120, 4);
  record.writeUInt16BE(4, 8);
  address.split(".").forEach((part, index) => (record[10 + index] = Number(part)));
  return Buffer.concat([encodeName(name), record]);
}

function encodeName(name) {
  const labels = name.split(".").filter(Boolean);
  const out = Buffer.alloc(labels.reduce((total, label) => total + label.length + 1, 1));
  let offset = 0;
  for (const label of labels) {
    out[offset] = label.length;
    out.write(label, offset + 1);
    offset += label.length + 1;
  }
  return out;
}

export const dgram = {
  createSocket(options, listener) {
    const socket = new NameLookupSocket();
    const handler = typeof options === "function" ? options : listener;
    if (handler) socket.on("message", handler);
    return socket;
  },
  Socket: NameLookupSocket,
};
