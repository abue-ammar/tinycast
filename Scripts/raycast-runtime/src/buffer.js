// A Buffer subset over Uint8Array — enough for the encode/decode work extension bundles do.
// Anything stream-shaped is deliberately absent; see docs/extensions.md for the supported surface.

import { base64ToBytes, bytesToBase64, utf8Decode, utf8Encode } from "./polyfills.js";

function hexToBytes(text) {
  const clean = String(text).replace(/[^0-9a-fA-F]/g, "");
  const out = new Uint8Array(clean.length >> 1);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(clean.substr(i * 2, 2), 16);
  return out;
}

function bytesToHex(bytes) {
  let out = "";
  for (const byte of bytes) out += byte.toString(16).padStart(2, "0");
  return out;
}

function latin1ToBytes(text) {
  const out = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) out[i] = text.charCodeAt(i) & 0xff;
  return out;
}

function bytesToLatin1(bytes) {
  let out = "";
  for (const byte of bytes) out += String.fromCharCode(byte);
  return out;
}

function normalizeEncoding(encoding) {
  const name = String(encoding || "utf8").toLowerCase();
  if (name === "utf-8" || name === "utf8") return "utf8";
  if (name === "base64" || name === "base64url") return name;
  if (name === "hex") return "hex";
  if (name === "latin1" || name === "binary" || name === "ascii") return "latin1";
  if (name === "utf16le" || name === "ucs2" || name === "ucs-2" || name === "utf-16le") return "utf16le";
  return "utf8";
}

function decode(bytes, encoding) {
  switch (normalizeEncoding(encoding)) {
    case "base64":
      return bytesToBase64(bytes);
    case "base64url":
      return bytesToBase64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    case "hex":
      return bytesToHex(bytes);
    case "latin1":
      return bytesToLatin1(bytes);
    case "utf16le": {
      let out = "";
      for (let i = 0; i + 1 < bytes.length; i += 2) out += String.fromCharCode(bytes[i] | (bytes[i + 1] << 8));
      return out;
    }
    default:
      return utf8Decode(bytes);
  }
}

function encode(text, encoding) {
  switch (normalizeEncoding(encoding)) {
    case "base64":
    case "base64url":
      return base64ToBytes(String(text).replace(/-/g, "+").replace(/_/g, "/"));
    case "hex":
      return hexToBytes(text);
    case "latin1":
      return latin1ToBytes(String(text));
    case "utf16le": {
      const source = String(text);
      const out = new Uint8Array(source.length * 2);
      for (let i = 0; i < source.length; i++) {
        const code = source.charCodeAt(i);
        out[i * 2] = code & 0xff;
        out[i * 2 + 1] = code >> 8;
      }
      return out;
    }
    default:
      return utf8Encode(String(text));
  }
}

export class Buffer extends Uint8Array {
  static from(value, encodingOrOffset, length) {
    if (typeof value === "string") return wrap(encode(value, encodingOrOffset));
    if (value instanceof ArrayBuffer) {
      return wrap(
        new Uint8Array(
          value,
          encodingOrOffset || 0,
          length === undefined ? value.byteLength - (encodingOrOffset || 0) : length,
        ),
      );
    }
    if (value instanceof Uint8Array) return wrap(new Uint8Array(value));
    if (Array.isArray(value)) return wrap(new Uint8Array(value));
    if (value && typeof value === "object" && value.type === "Buffer" && Array.isArray(value.data)) {
      return wrap(new Uint8Array(value.data));
    }
    throw new TypeError("Buffer.from: unsupported input");
  }

  static alloc(size, fill) {
    const bytes = new Uint8Array(Math.max(0, size | 0));
    if (fill !== undefined && fill !== 0) {
      const value = typeof fill === "number" ? fill : encode(String(fill), "utf8")[0] ?? 0;
      bytes.fill(value & 0xff);
    }
    return wrap(bytes);
  }

  static allocUnsafe(size) {
    return Buffer.alloc(size);
  }

  static concat(list, totalLength) {
    const parts = list.map((part) => (part instanceof Uint8Array ? part : Buffer.from(part)));
    const total = totalLength === undefined ? parts.reduce((sum, part) => sum + part.length, 0) : totalLength;
    const out = new Uint8Array(total);
    let offset = 0;
    for (const part of parts) {
      if (offset >= total) break;
      out.set(part.subarray(0, Math.min(part.length, total - offset)), offset);
      offset += part.length;
    }
    return wrap(out);
  }

  static isBuffer(value) {
    return value instanceof Uint8Array;
  }

  static byteLength(value, encoding) {
    if (typeof value === "string") return encode(value, encoding).length;
    return value?.length ?? 0;
  }

  toString(encoding, start, end) {
    const view = this.subarray(start ?? 0, end ?? this.length);
    return decode(view, encoding);
  }

  toJSON() {
    return { type: "Buffer", data: Array.from(this) };
  }

  equals(other) {
    if (!(other instanceof Uint8Array) || other.length !== this.length) return false;
    for (let i = 0; i < this.length; i++) if (this[i] !== other[i]) return false;
    return true;
  }

  write(text, offset = 0, length, encoding) {
    if (typeof length === "string") {
      encoding = length;
      length = undefined;
    }
    const bytes = encode(text, encoding);
    const count = Math.min(length ?? bytes.length, this.length - offset);
    this.set(bytes.subarray(0, count), offset);
    return count;
  }

  slice(start, end) {
    return wrap(this.subarray(start, end));
  }
}

/// `new Uint8Array(...)` results need the Buffer prototype grafted on: subclassing Uint8Array and
/// then copying would double every allocation for large payloads.
function wrap(bytes) {
  Object.setPrototypeOf(bytes, Buffer.prototype);
  return bytes;
}

export const bufferModule = {
  Buffer,
  atob: globalThis.atob,
  btoa: globalThis.btoa,
  constants: { MAX_LENGTH: 0x7fffffff, MAX_STRING_LENGTH: 0x1fffffe8 },
  kMaxLength: 0x7fffffff,
};
