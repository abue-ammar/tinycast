// Globals JavaScriptCore doesn't ship that extension bundles (and React's scheduler) assume.

import { hostCall, hostRaw, log } from "./host.js";

const g = globalThis;

if (!g.console) g.console = {};
for (const level of ["log", "info", "warn", "error", "debug", "trace"]) {
  g.console[level] = (...args) => log(level === "debug" || level === "trace" ? "log" : level, args);
}
// Extensions occasionally call these; make them harmless instead of a TypeError.
for (const noop of ["group", "groupEnd", "table", "time", "timeEnd", "dir", "assert", "count"]) {
  if (!g.console[noop]) g.console[noop] = () => {};
}

if (!g.performance) g.performance = { now: () => Date.now() };
else if (!g.performance.now) g.performance.now = () => Date.now();

// ─── Timers ─────────────────────────────────────────────────────────
// Swift owns the clock: it schedules on its runloop and calls back into `fireTimer`.

let nextTimerId = 1;
const timers = new Map();

function schedule(callback, delay, repeats, args) {
  if (typeof callback !== "function") return 0;
  const id = nextTimerId++;
  timers.set(id, { callback, args, repeats });
  hostRaw.startTimer(String(id), Math.max(0, Number(delay) || 0), repeats);
  return id;
}

function unschedule(id) {
  const key = Number(id);
  if (!timers.has(key)) return;
  timers.delete(key);
  hostRaw.clearTimer(String(key));
}

export function fireTimer(id) {
  const key = Number(id);
  const timer = timers.get(key);
  if (!timer) return;
  if (!timer.repeats) timers.delete(key);
  try {
    timer.callback(...timer.args);
  } catch (error) {
    reportUncaught(error);
  }
}

g.setTimeout = (cb, delay, ...args) => schedule(cb, delay, false, args);
g.setInterval = (cb, delay, ...args) => schedule(cb, delay, true, args);
g.clearTimeout = unschedule;
g.clearInterval = unschedule;
// Node's immediate/tick APIs, used by bundled deps.
g.setImmediate = (cb, ...args) => schedule(cb, 0, false, args);
g.clearImmediate = unschedule;

if (!g.queueMicrotask) {
  const resolved = Promise.resolve();
  g.queueMicrotask = (cb) => {
    resolved.then(cb).catch(reportUncaught);
  };
}

// ─── Error reporting ────────────────────────────────────────────────

let uncaughtSink = (error) => log("error", ["Uncaught:", error]);

export function setUncaughtHandler(handler) {
  uncaughtSink = handler;
}

export function reportUncaught(error) {
  try {
    uncaughtSink(error);
  } catch {
    log("error", ["Uncaught (and the handler threw):", error]);
  }
}

// ─── fetch ──────────────────────────────────────────────────────────
// Backed by URLSession on the Swift side. Bodies cross the bridge base64-encoded so binary
// responses survive; text/JSON go through the same path.

class TinycastHeaders {
  constructor(init) {
    this._map = new Map();
    if (init instanceof TinycastHeaders) {
      for (const [key, value] of init._map) this._map.set(key, value);
    } else if (Array.isArray(init)) {
      for (const [key, value] of init) this.append(key, value);
    } else if (init && typeof init === "object") {
      for (const key of Object.keys(init)) this.append(key, init[key]);
    }
  }
  _key(name) {
    return String(name).toLowerCase();
  }
  append(name, value) {
    const key = this._key(name);
    const existing = this._map.get(key);
    this._map.set(key, existing === undefined ? String(value) : `${existing}, ${value}`);
  }
  set(name, value) {
    this._map.set(this._key(name), String(value));
  }
  get(name) {
    const value = this._map.get(this._key(name));
    return value === undefined ? null : value;
  }
  has(name) {
    return this._map.has(this._key(name));
  }
  delete(name) {
    this._map.delete(this._key(name));
  }
  forEach(fn, thisArg) {
    for (const [key, value] of this._map) fn.call(thisArg, value, key, this);
  }
  keys() {
    return this._map.keys();
  }
  values() {
    return this._map.values();
  }
  entries() {
    return this._map.entries();
  }
  [Symbol.iterator]() {
    return this._map.entries();
  }
  toJSON() {
    return Object.fromEntries(this._map);
  }
}

class TinycastResponse {
  constructor({ status, statusText, headers, url, bodyBase64 }) {
    this.status = status;
    this.statusText = statusText || "";
    this.headers = new TinycastHeaders(headers);
    this.url = url || "";
    this.ok = status >= 200 && status < 300;
    this.redirected = false;
    this.type = "basic";
    this._bodyBase64 = bodyBase64 || "";
    this.bodyUsed = false;
  }
  clone() {
    return new TinycastResponse({
      status: this.status,
      statusText: this.statusText,
      headers: this.headers.toJSON(),
      url: this.url,
      bodyBase64: this._bodyBase64,
    });
  }
  async arrayBuffer() {
    this.bodyUsed = true;
    return base64ToBytes(this._bodyBase64).buffer;
  }
  async bytes() {
    this.bodyUsed = true;
    return base64ToBytes(this._bodyBase64);
  }
  async text() {
    this.bodyUsed = true;
    return utf8Decode(base64ToBytes(this._bodyBase64));
  }
  async json() {
    return JSON.parse(await this.text());
  }
  async blob() {
    throw new Error("Response.blob() is not supported in Tinycast extensions.");
  }
}

class TinycastRequest {
  constructor(input, init = {}) {
    if (input instanceof TinycastRequest) {
      this.url = input.url;
      this.method = init.method || input.method;
      this.headers = new TinycastHeaders(init.headers || input.headers);
      this.body = init.body !== undefined ? init.body : input.body;
    } else {
      this.url = String(input);
      this.method = (init.method || "GET").toUpperCase();
      this.headers = new TinycastHeaders(init.headers);
      this.body = init.body;
    }
    this.signal = init.signal;
  }
}

async function tinycastFetch(input, init = {}) {
  const request = input instanceof TinycastRequest ? input : new TinycastRequest(input, init);
  const signal = init.signal || request.signal;
  if (signal?.aborted) throw abortError();

  const raw = await hostCall("fetch", "request", [
    {
      url: request.url,
      method: request.method,
      headers: request.headers.toJSON(),
      bodyBase64: encodeBody(request.body),
    },
  ]);
  if (signal?.aborted) throw abortError();
  return new TinycastResponse(raw);
}

function abortError() {
  const error = new Error("The operation was aborted.");
  error.name = "AbortError";
  return error;
}

// `AbortSignal.timeout` aborts with TimeoutError, not AbortError — callers branch on the name.
function timeoutError() {
  const error = new Error("The operation timed out.");
  error.name = "TimeoutError";
  return error;
}

function encodeBody(body) {
  if (body === undefined || body === null) return null;
  if (typeof body === "string") return bytesToBase64(utf8Encode(body));
  if (body instanceof Uint8Array) return bytesToBase64(body);
  if (body instanceof ArrayBuffer) return bytesToBase64(new Uint8Array(body));
  if (g.Buffer && g.Buffer.isBuffer?.(body)) return bytesToBase64(new Uint8Array(body));
  if (body instanceof URLSearchParams) return bytesToBase64(utf8Encode(body.toString()));
  return bytesToBase64(utf8Encode(String(body)));
}

if (!g.fetch) {
  g.fetch = tinycastFetch;
  g.Headers = TinycastHeaders;
  g.Response = TinycastResponse;
  g.Request = TinycastRequest;
}

// ─── AbortController ────────────────────────────────────────────────

if (!g.AbortController) {
  class AbortSignalShim {
    constructor() {
      this.aborted = false;
      this.reason = undefined;
      this._listeners = new Set();
      this.onabort = null;
    }
    addEventListener(type, listener) {
      if (type === "abort") this._listeners.add(listener);
    }
    removeEventListener(type, listener) {
      if (type === "abort") this._listeners.delete(listener);
    }
    throwIfAborted() {
      if (this.aborted) throw this.reason ?? abortError();
    }
    // The statics, not just the instance shape: a signal missing them still reads as supported at
    // the type level, so an extension calls `AbortSignal.timeout` and gets "is not a function".
    static abort(reason) {
      const signal = new AbortSignalShim();
      signal._fire(reason);
      return signal;
    }
    static timeout(ms) {
      const signal = new AbortSignalShim();
      setTimeout(() => signal._fire(timeoutError()), ms);
      return signal;
    }
    static any(signals) {
      const merged = new AbortSignalShim();
      for (const source of signals) {
        if (source?.aborted) {
          merged._fire(source.reason);
          break;
        }
        source?.addEventListener("abort", () => merged._fire(source.reason));
      }
      return merged;
    }
    _fire(reason) {
      if (this.aborted) return;
      this.aborted = true;
      this.reason = reason ?? abortError();
      const event = { type: "abort", target: this };
      if (typeof this.onabort === "function") this.onabort(event);
      for (const listener of this._listeners) {
        try {
          listener(event);
        } catch (error) {
          reportUncaught(error);
        }
      }
    }
  }
  g.AbortSignal = AbortSignalShim;
  g.AbortController = class {
    constructor() {
      this.signal = new AbortSignalShim();
    }
    abort(reason) {
      this.signal._fire(reason);
    }
  };
}

// ─── Text encoding / base64 ─────────────────────────────────────────

export function utf8Encode(text) {
  const out = [];
  for (let i = 0; i < text.length; i++) {
    let code = text.codePointAt(i);
    if (code > 0xffff) i++;
    if (code < 0x80) out.push(code);
    else if (code < 0x800) out.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
    else if (code < 0x10000)
      out.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
    else
      out.push(
        0xf0 | (code >> 18),
        0x80 | ((code >> 12) & 0x3f),
        0x80 | ((code >> 6) & 0x3f),
        0x80 | (code & 0x3f),
      );
  }
  return new Uint8Array(out);
}

export function utf8Decode(bytes) {
  let out = "";
  for (let i = 0; i < bytes.length; ) {
    const byte = bytes[i++];
    if (byte < 0x80) out += String.fromCharCode(byte);
    else if (byte < 0xe0) out += String.fromCharCode(((byte & 0x1f) << 6) | (bytes[i++] & 0x3f));
    else if (byte < 0xf0)
      out += String.fromCharCode(
        ((byte & 0x0f) << 12) | ((bytes[i++] & 0x3f) << 6) | (bytes[i++] & 0x3f),
      );
    else {
      const code =
        ((byte & 0x07) << 18) |
        ((bytes[i++] & 0x3f) << 12) |
        ((bytes[i++] & 0x3f) << 6) |
        (bytes[i++] & 0x3f);
      out += String.fromCodePoint(code);
    }
  }
  return out;
}

const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

export function bytesToBase64(bytes) {
  let out = "";
  for (let i = 0; i < bytes.length; i += 3) {
    const a = bytes[i];
    const b = bytes[i + 1];
    const c = bytes[i + 2];
    out += B64[a >> 2];
    out += B64[((a & 3) << 4) | ((b ?? 0) >> 4)];
    out += b === undefined ? "=" : B64[((b & 15) << 2) | ((c ?? 0) >> 6)];
    out += c === undefined ? "=" : B64[c & 63];
  }
  return out;
}

export function base64ToBytes(text) {
  const clean = String(text).replace(/[^A-Za-z0-9+/]/g, "");
  const out = new Uint8Array((clean.length * 3) >> 2);
  let outIndex = 0;
  for (let i = 0; i < clean.length; i += 4) {
    const a = B64.indexOf(clean[i]);
    const b = B64.indexOf(clean[i + 1]);
    const c = B64.indexOf(clean[i + 2]);
    const d = B64.indexOf(clean[i + 3]);
    out[outIndex++] = (a << 2) | (b >> 4);
    if (c >= 0) out[outIndex++] = ((b & 15) << 4) | (c >> 2);
    if (d >= 0) out[outIndex++] = ((c & 3) << 6) | d;
  }
  return out.subarray(0, outIndex);
}

if (!g.atob) g.atob = (text) => String.fromCharCode(...base64ToBytes(text));
if (!g.btoa) {
  g.btoa = (text) => {
    const bytes = new Uint8Array(text.length);
    for (let i = 0; i < text.length; i++) bytes[i] = text.charCodeAt(i) & 0xff;
    return bytesToBase64(bytes);
  };
}

if (!g.structuredClone) {
  g.structuredClone = (value) => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)));
}

// JavaScriptCore has no TextEncoder/TextDecoder (they're WebCore APIs), and bundled deps reach for
// them freely. Only the UTF-8 path is real; an exotic requested encoding decodes as UTF-8.
if (!g.TextEncoder) {
  g.TextEncoder = class TextEncoder {
    get encoding() {
      return "utf-8";
    }
    encode(text = "") {
      return utf8Encode(String(text));
    }
    encodeInto(text, target) {
      const bytes = utf8Encode(String(text));
      const written = Math.min(bytes.length, target.length);
      target.set(bytes.subarray(0, written));
      return { read: text.length, written };
    }
  };
}

if (!g.TextDecoder) {
  g.TextDecoder = class TextDecoder {
    constructor(encoding = "utf-8", options = {}) {
      this.encoding = String(encoding).toLowerCase();
      this.fatal = !!options.fatal;
      this.ignoreBOM = !!options.ignoreBOM;
    }
    decode(input) {
      if (input === undefined) return "";
      let bytes;
      if (input instanceof Uint8Array) bytes = input;
      else if (input instanceof ArrayBuffer) bytes = new Uint8Array(input);
      else if (ArrayBuffer.isView(input))
        bytes = new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
      else throw new TypeError("TextDecoder.decode: unsupported input");
      if (!this.ignoreBOM && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
        bytes = bytes.subarray(3);
      }
      return utf8Decode(bytes);
    }
  };
}
