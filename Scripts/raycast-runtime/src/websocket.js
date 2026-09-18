// WebSockets over `URLSessionWebSocketTask`: Swift owns the wire, JS reads by keeping one `receive`
// outstanding.

import { Buffer } from "./buffer.js";
import { hostCall } from "./host.js";
import { Duplex } from "./streams.js";

/// Sends are chained: two host calls can otherwise settle out of order.
class NativeSocket {
  constructor(handlers) {
    this.id = 0;
    this.protocol = "";
    this.closed = false;
    this.tail = Promise.resolve();
    this.handlers = handlers;
  }

  async open(spec) {
    const opened = await hostCall("websocket", "open", [spec]);
    this.id = opened.id;
    this.protocol = opened.protocol ?? "";
    this.pump();
    return this;
  }

  send(message) {
    return this.enqueue("send", { ...message });
  }

  /// Outside the queue: a pong that never arrives must not hold a later `close` back.
  ping() {
    if (this.closed) return Promise.resolve();
    return hostCall("websocket", "ping", [{ id: this.id }]);
  }

  close(code, reason) {
    if (this.closed) return;
    this.closed = true;
    this.enqueue("close", { code: code ?? 1000, reason: reason ?? "" }, { whenClosed: true });
  }

  enqueue(method, payload, { whenClosed = false } = {}) {
    const result = this.tail.then(() =>
      this.closed && !whenClosed ? undefined : hostCall("websocket", method, [{ id: this.id, ...payload }]),
    );
    this.tail = result.catch(() => {});
    return result;
  }

  async pump() {
    for (;;) {
      let event;
      try {
        event = await hostCall("websocket", "receive", [this.id]);
      } catch (error) {
        this.closed = true;
        this.handlers.closed(1006, String(error?.message ?? error), true);
        return;
      }
      if (event.type === "close") {
        this.closed = true;
        this.handlers.closed(event.code ?? 1006, event.reason ?? "", Boolean(event.abnormal));
        return;
      }
      const binary = event.type === "binary";
      this.handlers.message(
        binary ? Buffer.from(event.base64 ?? "", "base64") : String(event.text ?? ""),
        binary,
      );
    }
  }
}

function protocolList(protocols) {
  if (!protocols) return [];
  return (Array.isArray(protocols) ? protocols : [protocols]).map(String);
}

// ─── The WHATWG global ──────────────────────────────────────────────

export class WebSocket {
  static CONNECTING = 0;
  static OPEN = 1;
  static CLOSING = 2;
  static CLOSED = 3;

  constructor(url, protocols) {
    this.url = String(url);
    this.readyState = WebSocket.CONNECTING;
    this.protocol = "";
    this.extensions = "";
    this.binaryType = "arraybuffer";
    this.bufferedAmount = 0;
    this.onopen = null;
    this.onmessage = null;
    this.onerror = null;
    this.onclose = null;
    this._listeners = new Map();
    this._socket = null;
    new NativeSocket({
      message: (data, binary) => {
        this._fire("message", { data: binary && this.binaryType === "arraybuffer" ? toArrayBuffer(data) : data });
      },
      closed: (code, reason, abnormal) => this._end(code, reason, abnormal),
    })
      .open({ url: this.url, protocols: protocolList(protocols), headers: {} })
      .then(
        (socket) => {
          this._socket = socket;
          this.protocol = socket.protocol;
          // A `close()` during the handshake has to win over the open that lands after it.
          if (this.readyState !== WebSocket.CONNECTING) return socket.close(1000, "");
          this.readyState = WebSocket.OPEN;
          this._fire("open", {});
        },
        (error) => this._end(1006, String(error?.message ?? error), true),
      );
  }

  send(data) {
    if (this.readyState !== WebSocket.OPEN) throw new Error("WebSocket is not open");
    if (typeof data === "string") return void this.transmit({ text: data });
    const bytes = ArrayBuffer.isView(data)
      ? Buffer.from(data.buffer, data.byteOffset, data.byteLength)
      : Buffer.from(data);
    this.transmit({ base64: bytes.toString("base64") });
  }

  transmit(message) {
    this._socket.send(message).catch((error) => this._end(1006, String(error?.message ?? error), true));
  }

  close(code, reason) {
    if (this.readyState === WebSocket.CLOSED || this.readyState === WebSocket.CLOSING) return;
    const connecting = this.readyState === WebSocket.CONNECTING;
    this.readyState = WebSocket.CLOSING;
    this._socket?.close(code, reason);
    if (connecting && !this._socket) this._end(code ?? 1000, reason ?? "", false);
  }

  addEventListener(type, listener) {
    if (!this._listeners.has(type)) this._listeners.set(type, new Set());
    this._listeners.get(type).add(listener);
  }

  removeEventListener(type, listener) {
    this._listeners.get(type)?.delete(listener);
  }

  _end(code, reason, abnormal) {
    if (this.readyState === WebSocket.CLOSED) return;
    if (abnormal) this._fire("error", { message: reason });
    this.readyState = WebSocket.CLOSED;
    this._fire("close", { code, reason, wasClean: !abnormal });
  }

  _fire(type, detail) {
    const event = { type, target: this, ...detail };
    const handler = this[`on${type}`];
    if (typeof handler === "function") handler.call(this, event);
    for (const listener of this._listeners.get(type) ?? []) listener.call(this, event);
  }
}

function toArrayBuffer(bytes) {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
}

// ─── The `ws` adapter ───────────────────────────────────────────────

const CONTINUATION = 0x0;
const TEXT = 0x1;
const BINARY = 0x2;
const CLOSE = 0x8;
const PING = 0x9;
const PONG = 0xa;

/// A bundled `ws` frames its own traffic, so the socket it gets re-frames over the native task.
export async function upgradeToWebSocket({ url, protocols, headers }) {
  const socket = new WebSocketSocket();
  const native = await new NativeSocket({
    message: (data, binary) => socket.deliver(data, binary),
    closed: (code, reason, abnormal) => socket.conclude(code, reason, abnormal),
  }).open({ url, protocols, headers });
  socket.native = native;
  return { socket, protocol: native.protocol };
}

class WebSocketSocket extends Duplex {
  constructor() {
    super({ read() {} });
    this.native = null;
    this.fragments = [];
    this.fragmentOpcode = TEXT;
    this.pending = Buffer.alloc(0);
  }

  _write(chunk, encoding, callback) {
    this.pending = Buffer.concat([this.pending, Buffer.from(chunk)]);
    while (this.readFrame());
    callback(null);
  }

  /// `ws` destroys on every error path; the native task goes with it.
  _destroy(error, callback) {
    this.native?.close(1000, "");
    callback?.(error ?? null);
  }

  setTimeout() {
    return this;
  }

  setNoDelay() {
    return this;
  }

  setKeepAlive() {
    return this;
  }

  deliver(data, binary) {
    const payload = binary ? data : Buffer.from(data, "utf8");
    this.push(encodeFrame(binary ? BINARY : TEXT, payload));
  }

  conclude(code, reason, abnormal) {
    // A frame may never carry 1005 or 1006; ending the socket is how `ws` reads them.
    if (!abnormal && code !== 1005 && code !== 1006) {
      const payload = Buffer.concat([Buffer.alloc(2), Buffer.from(String(reason ?? ""), "utf8")]);
      payload.writeUInt16BE(code, 0);
      this.push(encodeFrame(CLOSE, payload));
    }
    this.push(null);
  }

  /// False when `pending` is short of a whole frame.
  readFrame() {
    const buffer = this.pending;
    if (buffer.length < 2) return false;
    const masked = (buffer[1] & 0x80) !== 0;
    const indicator = buffer[1] & 0x7f;
    let offset = 2;
    let length = indicator;
    if (indicator === 126) {
      if (buffer.length < 4) return false;
      length = buffer.readUInt16BE(2);
      offset = 4;
    } else if (indicator === 127) {
      if (buffer.length < 10) return false;
      length = buffer.readUInt32BE(2) * 2 ** 32 + buffer.readUInt32BE(6);
      offset = 10;
    }
    const mask = masked ? buffer.subarray(offset, offset + 4) : null;
    if (masked) offset += 4;
    if (buffer.length < offset + length) return false;
    const payload = Buffer.from(buffer.subarray(offset, offset + length));
    if (mask) for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i % 4];
    this.pending = Buffer.from(buffer.subarray(offset + length));
    this.handleFrame((buffer[0] & 0x80) !== 0, buffer[0] & 0x0f, payload);
    return true;
  }

  handleFrame(final, opcode, payload) {
    if (opcode === PONG) return;
    if (opcode === PING) {
      this.native?.ping().then(
        () => this.push(encodeFrame(PONG, payload)),
        (error) => this.destroy(error),
      );
      return;
    }
    if (opcode === CLOSE) {
      const code = payload.length >= 2 ? payload.readUInt16BE(0) : 1000;
      return void this.native?.close(code, payload.subarray(2).toString("utf8"));
    }
    if (!final) {
      if (opcode !== CONTINUATION) this.fragmentOpcode = opcode;
      this.fragments.push(payload);
      return;
    }
    if (opcode === CONTINUATION) {
      this.fragments.push(payload);
      const whole = Buffer.concat(this.fragments);
      this.fragments = [];
      return void this.transmit(this.fragmentOpcode, whole);
    }
    this.transmit(opcode, payload);
  }

  transmit(opcode, payload) {
    const message = opcode === BINARY ? { base64: payload.toString("base64") } : { text: payload.toString("utf8") };
    this.native?.send(message)?.catch((error) => this.destroy(error));
  }
}

function encodeFrame(opcode, payload) {
  const length = payload.length;
  const header = Buffer.alloc(length < 126 ? 2 : length < 65536 ? 4 : 10);
  header[0] = 0x80 | opcode;
  if (length < 126) {
    header[1] = length;
  } else if (length < 65536) {
    header[1] = 126;
    header.writeUInt16BE(length, 2);
  } else {
    header[1] = 127;
    header.writeUInt32BE(0, 2);
    header.writeUInt32BE(length, 6);
  }
  return Buffer.concat([header, payload]);
}
