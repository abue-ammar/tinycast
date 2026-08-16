// URL / URLSearchParams for JavaScriptCore, which ships neither. Covers the hierarchical http(s)-
// style URLs extensions build and parse; it is not a full WHATWG implementation (no IDNA, no
// percent-encoding normalization of the host).

const SPECIAL_PORTS = { "http:": "80", "https:": "443", "ws:": "80", "wss:": "443", "ftp:": "21" };

export class URLSearchParams {
  constructor(init) {
    this._pairs = [];
    this._owner = null;
    if (init === undefined || init === null) return;
    if (init instanceof URLSearchParams) {
      this._pairs = init._pairs.map((pair) => [pair[0], pair[1]]);
    } else if (typeof init === "string") {
      this._parse(init);
    } else if (Array.isArray(init)) {
      for (const pair of init) this._pairs.push([String(pair[0]), String(pair[1])]);
    } else if (typeof init[Symbol.iterator] === "function") {
      for (const pair of init) this._pairs.push([String(pair[0]), String(pair[1])]);
    } else if (typeof init === "object") {
      for (const key of Object.keys(init)) this._pairs.push([key, String(init[key])]);
    }
  }

  _parse(text) {
    const body = String(text).replace(/^[?]/, "");
    if (!body) return;
    for (const chunk of body.split("&")) {
      if (!chunk) continue;
      const eq = chunk.indexOf("=");
      const key = eq < 0 ? chunk : chunk.slice(0, eq);
      const value = eq < 0 ? "" : chunk.slice(eq + 1);
      this._pairs.push([decodeComponent(key), decodeComponent(value)]);
    }
  }

  _changed() {
    if (this._owner) this._owner._syncSearchFromParams();
  }

  append(key, value) {
    this._pairs.push([String(key), String(value)]);
    this._changed();
  }
  delete(key, value) {
    const name = String(key);
    this._pairs = this._pairs.filter(
      (pair) => pair[0] !== name || (value !== undefined && pair[1] !== String(value)),
    );
    this._changed();
  }
  get(key) {
    const hit = this._pairs.find((pair) => pair[0] === String(key));
    return hit ? hit[1] : null;
  }
  getAll(key) {
    return this._pairs.filter((pair) => pair[0] === String(key)).map((pair) => pair[1]);
  }
  has(key, value) {
    const name = String(key);
    return this._pairs.some(
      (pair) => pair[0] === name && (value === undefined || pair[1] === String(value)),
    );
  }
  set(key, value) {
    const name = String(key);
    const index = this._pairs.findIndex((pair) => pair[0] === name);
    if (index < 0) {
      this._pairs.push([name, String(value)]);
    } else {
      this._pairs[index] = [name, String(value)];
      this._pairs = this._pairs.filter((pair, i) => i <= index || pair[0] !== name);
    }
    this._changed();
  }
  sort() {
    this._pairs.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
    this._changed();
  }
  get size() {
    return this._pairs.length;
  }
  forEach(fn, thisArg) {
    for (const [key, value] of this._pairs.slice()) fn.call(thisArg, value, key, this);
  }
  *keys() {
    for (const pair of this._pairs.slice()) yield pair[0];
  }
  *values() {
    for (const pair of this._pairs.slice()) yield pair[1];
  }
  *entries() {
    for (const pair of this._pairs.slice()) yield [pair[0], pair[1]];
  }
  [Symbol.iterator]() {
    return this.entries();
  }
  toString() {
    return this._pairs
      .map(([key, value]) => `${encodeComponent(key)}=${encodeComponent(value)}`)
      .join("&");
  }
}

function encodeComponent(text) {
  return encodeURIComponent(text).replace(/%20/g, "+").replace(/[!'()~]/g, (c) =>
    "%" + c.charCodeAt(0).toString(16).toUpperCase(),
  );
}

function decodeComponent(text) {
  try {
    return decodeURIComponent(String(text).replace(/\+/g, " "));
  } catch {
    return String(text);
  }
}

const URL_RE = /^([A-Za-z][A-Za-z0-9+.-]*:)(\/\/)?([^/?#]*)?([^?#]*)(\?[^#]*)?(#.*)?$/;

export class URL {
  constructor(input, base) {
    let text = String(input).trim();
    if (base !== undefined && !/^[A-Za-z][A-Za-z0-9+.-]*:/.test(text)) {
      text = resolveRelative(String(base), text);
    }
    const match = URL_RE.exec(text);
    if (!match) throw new TypeError(`Invalid URL: ${input}`);

    this.protocol = match[1].toLowerCase();
    const authority = match[2] ? match[3] || "" : "";
    this.username = "";
    this.password = "";
    let hostPort = authority;
    const at = authority.lastIndexOf("@");
    if (at >= 0) {
      const credentials = authority.slice(0, at);
      hostPort = authority.slice(at + 1);
      const colon = credentials.indexOf(":");
      this.username = colon < 0 ? credentials : credentials.slice(0, colon);
      this.password = colon < 0 ? "" : credentials.slice(colon + 1);
    }
    // IPv6 literals keep their brackets and must not be split on their inner colons.
    if (hostPort.startsWith("[")) {
      const close = hostPort.indexOf("]");
      this.hostname = hostPort.slice(0, close + 1);
      this.port = hostPort.slice(close + 1).replace(/^:/, "");
    } else {
      const colon = hostPort.lastIndexOf(":");
      this.hostname = (colon < 0 ? hostPort : hostPort.slice(0, colon)).toLowerCase();
      this.port = colon < 0 ? "" : hostPort.slice(colon + 1);
    }
    if (this.port && SPECIAL_PORTS[this.protocol] === this.port) this.port = "";

    let path = match[4] || "";
    if (match[2] && !path.startsWith("/")) path = "/" + path;
    this.pathname = match[2] ? normalizePath(path) || "/" : path;
    this.hash = match[6] || "";
    this._search = match[5] || "";
    this.searchParams = new URLSearchParams(this._search);
    this.searchParams._owner = this;
  }

  get search() {
    return this._search;
  }
  set search(value) {
    const text = String(value);
    this._search = !text || text === "?" ? "" : text.startsWith("?") ? text : "?" + text;
    this.searchParams._owner = null;
    this.searchParams = new URLSearchParams(this._search);
    this.searchParams._owner = this;
  }
  _syncSearchFromParams() {
    const text = this.searchParams.toString();
    this._search = text ? "?" + text : "";
  }

  get host() {
    return this.port ? `${this.hostname}:${this.port}` : this.hostname;
  }
  set host(value) {
    const text = String(value);
    const colon = text.lastIndexOf(":");
    if (colon > 0 && !text.endsWith("]")) {
      this.hostname = text.slice(0, colon).toLowerCase();
      this.port = text.slice(colon + 1);
    } else {
      this.hostname = text.toLowerCase();
      this.port = "";
    }
  }

  get origin() {
    return this.hostname ? `${this.protocol}//${this.host}` : "null";
  }

  get href() {
    let out = this.protocol;
    if (this.hostname || this.protocol === "file:") {
      out += "//";
      if (this.username) {
        out += this.username;
        if (this.password) out += ":" + this.password;
        out += "@";
      }
      out += this.host;
    }
    return out + this.pathname + this._search + this.hash;
  }
  set href(value) {
    const replacement = new URL(value);
    for (const key of ["protocol", "username", "password", "hostname", "port", "pathname", "hash"]) {
      this[key] = replacement[key];
    }
    this.search = replacement.search;
  }

  toString() {
    return this.href;
  }
  toJSON() {
    return this.href;
  }

  static canParse(input, base) {
    try {
      new URL(input, base);
      return true;
    } catch {
      return false;
    }
  }
}

function resolveRelative(base, relative) {
  const parsed = new URL(base);
  if (relative.startsWith("//")) return parsed.protocol + relative;
  if (relative.startsWith("/")) return `${parsed.protocol}//${parsed.host}${relative}`;
  if (relative.startsWith("?")) return `${parsed.protocol}//${parsed.host}${parsed.pathname}${relative}`;
  if (relative.startsWith("#")) {
    return `${parsed.protocol}//${parsed.host}${parsed.pathname}${parsed.search}${relative}`;
  }
  const dir = parsed.pathname.replace(/[^/]*$/, "");
  return `${parsed.protocol}//${parsed.host}${normalizePath(dir + relative)}`;
}

function normalizePath(path) {
  const leadingSlash = path.startsWith("/");
  const trailingSlash = path.endsWith("/") && path.length > 1;
  const out = [];
  for (const segment of path.split("/")) {
    if (segment === "" || segment === ".") continue;
    if (segment === "..") out.pop();
    else out.push(segment);
  }
  let joined = out.join("/");
  if (leadingSlash) joined = "/" + joined;
  if (trailingSlash && !joined.endsWith("/")) joined += "/";
  return joined;
}

if (!globalThis.URL) globalThis.URL = URL;
if (!globalThis.URLSearchParams) globalThis.URLSearchParams = URLSearchParams;
