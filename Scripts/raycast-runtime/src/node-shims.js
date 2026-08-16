// Node built-ins that extension bundles keep external. Everything filesystem-, process- or
// crypto-shaped is a synchronous host call (Swift services these on the JS thread); the
// stream/socket-shaped modules resolve but throw on use, so a bundle that merely references them
// still loads.

import { hostCall, hostCallSync } from "./host.js";
import { Buffer, bufferModule } from "./buffer.js";
import { base64ToBytes, bytesToBase64, reportUncaught, utf8Decode, utf8Encode } from "./polyfills.js";
import { URL, URLSearchParams } from "./url.js";
import { punycode } from "./punycode.js";

// ─── path ───────────────────────────────────────────────────────────

function normalizeSegments(parts, allowAboveRoot) {
  const out = [];
  for (const part of parts) {
    if (!part || part === ".") continue;
    if (part === "..") {
      if (out.length && out[out.length - 1] !== "..") out.pop();
      else if (allowAboveRoot) out.push("..");
    } else {
      out.push(part);
    }
  }
  return out;
}

const path = {
  sep: "/",
  delimiter: ":",
  normalize(input) {
    const text = String(input);
    if (!text) return ".";
    const absolute = text.startsWith("/");
    const trailing = text.endsWith("/");
    let joined = normalizeSegments(text.split("/"), !absolute).join("/");
    if (!joined && !absolute) joined = ".";
    if (joined && trailing) joined += "/";
    return absolute ? "/" + joined : joined;
  },
  join(...parts) {
    const joined = parts.filter((part) => part !== undefined && part !== null && part !== "").join("/");
    return joined ? path.normalize(joined) : ".";
  },
  resolve(...parts) {
    let resolved = "";
    for (let i = parts.length - 1; i >= 0; i--) {
      const part = parts[i];
      if (!part) continue;
      resolved = resolved ? `${part}/${resolved}` : String(part);
      if (String(part).startsWith("/")) break;
    }
    if (!resolved.startsWith("/")) resolved = `${process.cwd()}/${resolved}`;
    const normalized = "/" + normalizeSegments(resolved.split("/"), false).join("/");
    return normalized === "/" ? "/" : normalized.replace(/\/$/, "");
  },
  isAbsolute(input) {
    return String(input).startsWith("/");
  },
  dirname(input) {
    const text = String(input).replace(/\/+$/, "");
    const index = text.lastIndexOf("/");
    if (index < 0) return ".";
    if (index === 0) return "/";
    return text.slice(0, index);
  },
  basename(input, ext) {
    const text = String(input).replace(/\/+$/, "");
    let base = text.slice(text.lastIndexOf("/") + 1);
    if (ext && base.endsWith(ext) && base !== ext) base = base.slice(0, -ext.length);
    return base;
  },
  extname(input) {
    const base = path.basename(input);
    const dot = base.lastIndexOf(".");
    return dot <= 0 ? "" : base.slice(dot);
  },
  relative(from, to) {
    const fromParts = path.resolve(from).split("/").filter(Boolean);
    const toParts = path.resolve(to).split("/").filter(Boolean);
    let shared = 0;
    while (shared < fromParts.length && shared < toParts.length && fromParts[shared] === toParts[shared]) {
      shared++;
    }
    return [...Array(fromParts.length - shared).fill(".."), ...toParts.slice(shared)].join("/");
  },
  parse(input) {
    const dir = path.dirname(input);
    const base = path.basename(input);
    const ext = path.extname(base);
    return { root: String(input).startsWith("/") ? "/" : "", dir, base, ext, name: base.slice(0, base.length - ext.length) };
  },
  format(parsed) {
    const dir = parsed.dir || parsed.root || "";
    const base = parsed.base || `${parsed.name || ""}${parsed.ext || ""}`;
    return dir ? (dir === "/" ? "/" + base : `${dir}/${base}`) : base;
  },
  toNamespacedPath: (input) => input,
};
path.posix = path;
path.win32 = path;

// ─── process ────────────────────────────────────────────────────────

let bootEnvironment = { platform: "darwin", arch: "arm64", env: {}, cwd: "/", homedir: "/", tmpdir: "/tmp", execPath: "" };

export function configureNodeShims(info) {
  bootEnvironment = { ...bootEnvironment, ...info };
  process.env = bootEnvironment.env;
  process.arch = bootEnvironment.arch;
  process.execPath = bootEnvironment.execPath;
}

const processListeners = new Map();

const process = {
  platform: "darwin",
  arch: "arm64",
  version: "v22.0.0",
  versions: { node: "22.0.0", v8: "12.0.0", tinycast: "1" },
  argv: ["node", "extension"],
  argv0: "node",
  execPath: "",
  pid: 1,
  ppid: 0,
  env: {},
  title: "tinycast-extension",
  stdout: { write: (text) => console.log(String(text).replace(/\n$/, "")), isTTY: false, columns: 80 },
  stderr: { write: (text) => console.error(String(text).replace(/\n$/, "")), isTTY: false, columns: 80 },
  stdin: { on: () => {}, resume: () => {}, pause: () => {}, isTTY: false },
  cwd: () => bootEnvironment.cwd,
  chdir: () => {
    throw new Error("process.chdir is not supported in Tinycast extensions.");
  },
  exit: () => {
    throw new Error("process.exit is not supported in Tinycast extensions.");
  },
  nextTick: (callback, ...args) => {
    queueMicrotask(() => {
      try {
        callback(...args);
      } catch (error) {
        reportUncaught(error);
      }
    });
  },
  hrtime: Object.assign(
    (previous) => {
      const now = Date.now() * 1e6;
      const seconds = Math.floor(now / 1e9);
      const nanos = now % 1e9;
      if (!previous) return [seconds, nanos];
      return [seconds - previous[0], nanos - previous[1]];
    },
    { bigint: () => BigInt(Math.round(Date.now() * 1e6)) },
  ),
  uptime: () => Date.now() / 1000,
  memoryUsage: () => ({ rss: 0, heapTotal: 0, heapUsed: 0, external: 0, arrayBuffers: 0 }),
  emitWarning: (warning) => console.warn(String(warning)),
  on(event, listener) {
    if (!processListeners.has(event)) processListeners.set(event, new Set());
    processListeners.get(event).add(listener);
    return process;
  },
  once(event, listener) {
    return process.on(event, listener);
  },
  off(event, listener) {
    processListeners.get(event)?.delete(listener);
    return process;
  },
  removeListener(event, listener) {
    return process.off(event, listener);
  },
  removeAllListeners(event) {
    if (event) processListeners.delete(event);
    else processListeners.clear();
    return process;
  },
  listeners: (event) => Array.from(processListeners.get(event) ?? []),
  emit(event, ...args) {
    const listeners = processListeners.get(event);
    if (!listeners?.size) return false;
    for (const listener of listeners) {
      try {
        listener(...args);
      } catch (error) {
        reportUncaught(error);
      }
    }
    return true;
  },
};

// ─── os ─────────────────────────────────────────────────────────────

const os = {
  EOL: "\n",
  platform: () => "darwin",
  type: () => "Darwin",
  arch: () => bootEnvironment.arch,
  release: () => bootEnvironment.release || "",
  homedir: () => bootEnvironment.homedir,
  tmpdir: () => bootEnvironment.tmpdir,
  hostname: () => bootEnvironment.hostname || "localhost",
  userInfo: () => ({
    username: bootEnvironment.username || "",
    homedir: bootEnvironment.homedir,
    shell: bootEnvironment.shell || "/bin/zsh",
    uid: 501,
    gid: 20,
  }),
  cpus: () => Array.from({ length: bootEnvironment.cpus || 8 }, () => ({ model: "Apple Silicon", speed: 0, times: {} })),
  totalmem: () => bootEnvironment.totalmem || 0,
  freemem: () => 0,
  uptime: () => 0,
  networkInterfaces: () => ({}),
  endianness: () => "LE",
  devNull: "/dev/null",
  constants: { signals: {}, errno: {} },
};

// ─── fs ─────────────────────────────────────────────────────────────

function decodeFileResult(result, options) {
  const encoding = typeof options === "string" ? options : options?.encoding;
  const bytes = base64ToBytes(result);
  return encoding ? Buffer.from(bytes).toString(encoding) : Buffer.from(bytes);
}

function encodeFileData(data, options) {
  if (typeof data === "string") {
    const encoding = typeof options === "string" ? options : options?.encoding;
    return bytesToBase64(Buffer.from(data, encoding || "utf8"));
  }
  if (data instanceof Uint8Array) return bytesToBase64(data);
  if (data instanceof ArrayBuffer) return bytesToBase64(new Uint8Array(data));
  return bytesToBase64(utf8Encode(String(data)));
}

class Stats {
  constructor(raw) {
    Object.assign(this, raw);
    this.atime = new Date(raw.atimeMs || 0);
    this.mtime = new Date(raw.mtimeMs || 0);
    this.ctime = new Date(raw.ctimeMs || 0);
    this.birthtime = new Date(raw.birthtimeMs || 0);
  }
  isFile() {
    return !!this._isFile;
  }
  isDirectory() {
    return !!this._isDirectory;
  }
  isSymbolicLink() {
    return !!this._isSymbolicLink;
  }
  isBlockDevice() {
    return false;
  }
  isCharacterDevice() {
    return false;
  }
  isFIFO() {
    return false;
  }
  isSocket() {
    return false;
  }
}

class Dirent {
  constructor(raw) {
    this.name = raw.name;
    this.parentPath = raw.parentPath;
    this.path = raw.parentPath;
    this._isFile = raw._isFile;
    this._isDirectory = raw._isDirectory;
    this._isSymbolicLink = raw._isSymbolicLink;
  }
  isFile() {
    return !!this._isFile;
  }
  isDirectory() {
    return !!this._isDirectory;
  }
  isSymbolicLink() {
    return !!this._isSymbolicLink;
  }
}

function fsPath(input) {
  if (input instanceof URL) return decodeURIComponent(input.pathname);
  if (input instanceof Uint8Array) return utf8Decode(input);
  return String(input);
}

const fs = {
  constants: { F_OK: 0, R_OK: 4, W_OK: 2, X_OK: 1 },

  readFileSync(file, options) {
    return decodeFileResult(hostCallSync("fs", "readFile", [fsPath(file)]), options);
  },
  writeFileSync(file, data, options) {
    hostCallSync("fs", "writeFile", [fsPath(file), encodeFileData(data, options), false]);
  },
  appendFileSync(file, data, options) {
    hostCallSync("fs", "writeFile", [fsPath(file), encodeFileData(data, options), true]);
  },
  existsSync(file) {
    try {
      return hostCallSync("fs", "exists", [fsPath(file)]);
    } catch {
      return false;
    }
  },
  statSync(file, options) {
    try {
      return new Stats(hostCallSync("fs", "stat", [fsPath(file), false]));
    } catch (error) {
      if (options?.throwIfNoEntry === false) return undefined;
      throw error;
    }
  },
  lstatSync(file, options) {
    try {
      return new Stats(hostCallSync("fs", "stat", [fsPath(file), true]));
    } catch (error) {
      if (options?.throwIfNoEntry === false) return undefined;
      throw error;
    }
  },
  readdirSync(dir, options) {
    const entries = hostCallSync("fs", "readdir", [fsPath(dir)]);
    if (options?.withFileTypes) return entries.map((entry) => new Dirent(entry));
    return entries.map((entry) => entry.name);
  },
  mkdirSync(dir, options) {
    return hostCallSync("fs", "mkdir", [fsPath(dir), !!(options === true || options?.recursive)]);
  },
  rmSync(target, options) {
    hostCallSync("fs", "remove", [fsPath(target), !!options?.recursive, !!options?.force]);
  },
  rmdirSync(target, options) {
    hostCallSync("fs", "remove", [fsPath(target), !!options?.recursive, false]);
  },
  unlinkSync(target) {
    hostCallSync("fs", "remove", [fsPath(target), false, false]);
  },
  renameSync(from, to) {
    hostCallSync("fs", "rename", [fsPath(from), fsPath(to)]);
  },
  copyFileSync(from, to) {
    hostCallSync("fs", "copyFile", [fsPath(from), fsPath(to)]);
  },
  realpathSync(target) {
    return hostCallSync("fs", "realpath", [fsPath(target)]);
  },
  accessSync(target) {
    if (!fs.existsSync(target)) {
      const error = new Error(`ENOENT: no such file or directory, access '${fsPath(target)}'`);
      error.code = "ENOENT";
      throw error;
    }
  },
  mkdtempSync(prefix) {
    return hostCallSync("fs", "mkdtemp", [String(prefix)]);
  },
  chmodSync() {},
  utimesSync() {},
  watch() {
    throw new Error("fs.watch is not supported in Tinycast extensions.");
  },
  createReadStream() {
    throw new Error("fs.createReadStream is not supported in Tinycast extensions.");
  },
  createWriteStream() {
    throw new Error("fs.createWriteStream is not supported in Tinycast extensions.");
  },
  Stats,
  Dirent,
};

// Callback forms: run the same sync host call, hand the result back on a microtask.
function callbackify(syncFn) {
  return (...args) => {
    const callback = typeof args[args.length - 1] === "function" ? args.pop() : null;
    let value;
    let error = null;
    try {
      value = syncFn(...args);
    } catch (thrown) {
      error = thrown;
    }
    if (!callback) return;
    queueMicrotask(() => callback(error, error ? undefined : value));
  };
}

for (const [name, sync] of [
  ["readFile", fs.readFileSync],
  ["writeFile", fs.writeFileSync],
  ["appendFile", fs.appendFileSync],
  ["stat", fs.statSync],
  ["lstat", fs.lstatSync],
  ["readdir", fs.readdirSync],
  ["mkdir", fs.mkdirSync],
  ["rm", fs.rmSync],
  ["rmdir", fs.rmdirSync],
  ["unlink", fs.unlinkSync],
  ["rename", fs.renameSync],
  ["copyFile", fs.copyFileSync],
  ["realpath", fs.realpathSync],
  ["access", fs.accessSync],
  ["mkdtemp", fs.mkdtempSync],
  ["chmod", fs.chmodSync],
]) {
  fs[name] = callbackify(sync);
}
fs.exists = (file, callback) => queueMicrotask(() => callback(fs.existsSync(file)));

function promisify1(syncFn) {
  return async (...args) => syncFn(...args);
}

const fsPromises = {
  readFile: promisify1(fs.readFileSync),
  writeFile: promisify1(fs.writeFileSync),
  appendFile: promisify1(fs.appendFileSync),
  stat: promisify1(fs.statSync),
  lstat: promisify1(fs.lstatSync),
  readdir: promisify1(fs.readdirSync),
  mkdir: promisify1(fs.mkdirSync),
  rm: promisify1(fs.rmSync),
  rmdir: promisify1(fs.rmdirSync),
  unlink: promisify1(fs.unlinkSync),
  rename: promisify1(fs.renameSync),
  copyFile: promisify1(fs.copyFileSync),
  realpath: promisify1(fs.realpathSync),
  access: promisify1(fs.accessSync),
  mkdtemp: promisify1(fs.mkdtempSync),
  chmod: promisify1(fs.chmodSync),
  constants: fs.constants,
};
fs.promises = fsPromises;

// ─── child_process ──────────────────────────────────────────────────

function normalizeExecResult(raw, options) {
  const wantsBuffer = options?.encoding === "buffer" || options?.encoding === null;
  const decode = (base64) => (wantsBuffer ? Buffer.from(base64ToBytes(base64)) : utf8Decode(base64ToBytes(base64)));
  return { stdout: decode(raw.stdout), stderr: decode(raw.stderr), status: raw.status, signal: raw.signal ?? null };
}

function execError(result, command) {
  const error = new Error(
    `Command failed: ${command}\n${typeof result.stderr === "string" ? result.stderr : ""}`.trim(),
  );
  error.code = result.status;
  error.status = result.status;
  error.stdout = result.stdout;
  error.stderr = result.stderr;
  error.killed = false;
  return error;
}

const childProcess = {
  execSync(command, options = {}) {
    const raw = hostCallSync("proc", "run", [
      { shell: true, command: String(command), args: [], cwd: options.cwd, env: options.env, timeout: options.timeout, input: options.input ? bytesToBase64(Buffer.from(options.input)) : null },
    ]);
    const result = normalizeExecResult(raw, options);
    if (result.status !== 0) throw execError(result, command);
    return result.stdout;
  },
  execFileSync(file, args = [], options = {}) {
    if (!Array.isArray(args)) {
      options = args;
      args = [];
    }
    const raw = hostCallSync("proc", "run", [
      { shell: false, command: String(file), args: args.map(String), cwd: options.cwd, env: options.env, timeout: options.timeout, input: options.input ? bytesToBase64(Buffer.from(options.input)) : null },
    ]);
    const result = normalizeExecResult(raw, options);
    if (result.status !== 0) throw execError(result, file);
    return result.stdout;
  },
  spawnSync(file, args = [], options = {}) {
    if (!Array.isArray(args)) {
      options = args;
      args = [];
    }
    const raw = hostCallSync("proc", "run", [
      { shell: !!options.shell, command: String(file), args: args.map(String), cwd: options.cwd, env: options.env, timeout: options.timeout, input: options.input ? bytesToBase64(Buffer.from(options.input)) : null },
    ]);
    const result = normalizeExecResult(raw, options);
    return { ...result, pid: 0, output: [null, result.stdout, result.stderr], error: undefined };
  },
  exec(command, options, callback) {
    if (typeof options === "function") {
      callback = options;
      options = {};
    }
    return runAsync({ shell: true, command: String(command), args: [], ...pickRunOptions(options) }, options, callback, command);
  },
  execFile(file, args, options, callback) {
    if (typeof args === "function") {
      callback = args;
      args = [];
      options = {};
    } else if (typeof options === "function") {
      callback = options;
      options = {};
    }
    if (!Array.isArray(args)) args = [];
    return runAsync(
      { shell: false, command: String(file), args: args.map(String), ...pickRunOptions(options) },
      options,
      callback,
      file,
    );
  },
  /// A buffered `spawn`: the child runs to completion and its output is then emitted as one `data`
  /// event. That covers the write-query-then-read-all pattern (`@raycast/utils`' `useSQL` spawns
  /// `sqlite3` exactly this way), which is what extensions actually do with it — true streaming would
  /// need a duplex channel across the bridge.
  spawn(file, args = [], options = {}) {
    if (!Array.isArray(args)) {
      options = args;
      args = [];
    }
    return new BufferedChildProcess(String(file), args.map(String), options);
  },
  fork() {
    throw new Error("child_process.fork is not supported in Tinycast extensions.");
  },
};

// ─── crypto ─────────────────────────────────────────────────────────

class Hash {
  constructor(algorithm, hmacKeyBase64) {
    this._algorithm = String(algorithm).toLowerCase().replace(/-/g, "");
    this._key = hmacKeyBase64;
    this._chunks = [];
  }
  update(data, encoding) {
    this._chunks.push(typeof data === "string" ? Buffer.from(data, encoding || "utf8") : Buffer.from(data));
    return this;
  }
  digest(encoding) {
    const base64 = hostCallSync("crypto", this._key ? "hmac" : "hash", [
      this._algorithm,
      bytesToBase64(Buffer.concat(this._chunks)),
      this._key ?? null,
    ]);
    const bytes = Buffer.from(base64ToBytes(base64));
    return encoding ? bytes.toString(encoding) : bytes;
  }
}

const cryptoModule = {
  randomUUID: () => hostCallSync("crypto", "uuid", []),
  randomBytes(size, callback) {
    const bytes = Buffer.from(base64ToBytes(hostCallSync("crypto", "random", [size | 0])));
    if (callback) {
      queueMicrotask(() => callback(null, bytes));
      return;
    }
    return bytes;
  },
  randomFillSync(target) {
    const bytes = base64ToBytes(hostCallSync("crypto", "random", [target.length]));
    target.set(bytes.subarray(0, target.length));
    return target;
  },
  randomInt(min, max) {
    if (max === undefined) {
      max = min;
      min = 0;
    }
    const bytes = base64ToBytes(hostCallSync("crypto", "random", [4]));
    const value = ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) >>> 0;
    return min + (value % (max - min));
  },
  createHash: (algorithm) => new Hash(algorithm),
  createHmac: (algorithm, key) => new Hash(algorithm, bytesToBase64(typeof key === "string" ? Buffer.from(key, "utf8") : Buffer.from(key))),
  timingSafeEqual: (a, b) => Buffer.from(a).equals(Buffer.from(b)),
  getRandomValues: (target) => cryptoModule.randomFillSync(target),
  webcrypto: null,
  constants: {},
};
cryptoModule.webcrypto = { randomUUID: cryptoModule.randomUUID, getRandomValues: cryptoModule.getRandomValues, subtle: undefined };
if (!globalThis.crypto) globalThis.crypto = cryptoModule.webcrypto;

// ─── zlib ───────────────────────────────────────────────────────────

function zlibSync(method) {
  return (data) => Buffer.from(base64ToBytes(hostCallSync("zlib", method, [bytesToBase64(Buffer.from(data))])));
}

const zlibImpl = {
  gzipSync: zlibSync("gzip"),
  gunzipSync: zlibSync("gunzip"),
  deflateSync: zlibSync("deflate"),
  inflateSync: zlibSync("inflate"),
  deflateRawSync: zlibSync("deflateRaw"),
  inflateRawSync: zlibSync("inflateRaw"),
  brotliCompressSync: () => {
    throw new Error("zlib brotli is not supported in Tinycast extensions.");
  },
  brotliDecompressSync: () => {
    throw new Error("zlib brotli is not supported in Tinycast extensions.");
  },
  constants: {},
};
for (const name of ["gzip", "gunzip", "deflate", "inflate", "deflateRaw", "inflateRaw"]) {
  zlibImpl[name] = callbackify(zlibImpl[`${name}Sync`]);
}
// The one-shot functions above are real; the stream classes (`zlib.Inflate`, …) are not, and bundles
// subclass them at load time — so unknown members fall through to a throwing constructor.
const zlib = unsupportedModule("zlib", zlibImpl);

// ─── events ─────────────────────────────────────────────────────────

class EventEmitter {
  constructor() {
    this._events = new Map();
    this._maxListeners = 10;
  }
  _list(event) {
    if (!this._events.has(event)) this._events.set(event, []);
    return this._events.get(event);
  }
  on(event, listener) {
    this._list(event).push(listener);
    return this;
  }
  addListener(event, listener) {
    return this.on(event, listener);
  }
  prependListener(event, listener) {
    this._list(event).unshift(listener);
    return this;
  }
  once(event, listener) {
    const wrapper = (...args) => {
      this.off(event, wrapper);
      listener(...args);
    };
    wrapper.listener = listener;
    return this.on(event, wrapper);
  }
  off(event, listener) {
    const list = this._events.get(event);
    if (!list) return this;
    const index = list.findIndex((entry) => entry === listener || entry.listener === listener);
    if (index >= 0) list.splice(index, 1);
    return this;
  }
  removeListener(event, listener) {
    return this.off(event, listener);
  }
  removeAllListeners(event) {
    if (event === undefined) this._events.clear();
    else this._events.delete(event);
    return this;
  }
  emit(event, ...args) {
    const list = this._events.get(event);
    if (!list?.length) return false;
    for (const listener of list.slice()) listener.apply(this, args);
    return true;
  }
  listenerCount(event) {
    return this._events.get(event)?.length ?? 0;
  }
  listeners(event) {
    return (this._events.get(event) ?? []).slice();
  }
  eventNames() {
    return Array.from(this._events.keys());
  }
  setMaxListeners(count) {
    this._maxListeners = count;
    return this;
  }
  getMaxListeners() {
    return this._maxListeners;
  }
}
EventEmitter.EventEmitter = EventEmitter;
EventEmitter.defaultMaxListeners = 10;
EventEmitter.once = (emitter, event) =>
  new Promise((resolve) => emitter.once(event, (...args) => resolve(args)));

class BufferedStream extends EventEmitter {
  constructor() {
    super();
    this.readable = true;
    this.readableEnded = false;
    this.encoding = null;
    // `get-stream` (and therefore execa) consumes stdout by async iteration, not by `data` events.
    this._delivered = new Promise((resolve) => {
      this._resolveDelivered = resolve;
    });
  }

  async *[Symbol.asyncIterator]() {
    const bytes = await this._delivered;
    if (bytes.length) yield this.encoding ? bytes.toString(this.encoding) : bytes;
  }
  setEncoding(encoding) {
    this.encoding = encoding;
    return this;
  }
  pipe(destination) {
    this.on("data", (chunk) => destination.write?.(chunk));
    this.on("end", () => destination.end?.());
    return destination;
  }
  resume() {
    return this;
  }
  pause() {
    return this;
  }
  destroy() {
    return this;
  }
  _deliver(bytes) {
    this._resolveDelivered(bytes);
    if (bytes.length) this.emit("data", this.encoding ? bytes.toString(this.encoding) : bytes);
    this.readableEnded = true;
    this.emit("end");
    this.emit("close");
  }
}

class BufferedChildProcess extends EventEmitter {
  constructor(file, args, options) {
    super();
    this.pid = 0;
    this.killed = false;
    this.exitCode = null;
    this.stdout = new BufferedStream();
    this.stderr = new BufferedStream();
    this._input = [];
    this._started = false;

    const self = this;
    this.stdin = {
      writable: true,
      write(chunk) {
        self._input.push(typeof chunk === "string" ? Buffer.from(chunk, "utf8") : Buffer.from(chunk));
        return true;
      },
      end(chunk) {
        if (chunk !== undefined) this.write(chunk);
        self._start(file, args, options);
      },
      destroy() {},
      on() {},
      once() {},
      emit() {},
    };

    // Start on a microtask, not a timer. Callers write stdin synchronously right after `spawn()`
    // (`p.stdin.write(q); p.stdin.end()`), so a microtask still collects it — but unlike a timer it is
    // guaranteed to drain before control returns to Swift. A fire-and-forget `spawn(...).unref()` in a
    // no-view command would otherwise still be pending when the command finishes and its context is
    // torn down, and the child would never launch at all.
    queueMicrotask(() => this._start(file, args, options));
  }

  _start(file, args, options) {
    if (this._started) return;
    this._started = true;
    const input = this._input.length ? bytesToBase64(Buffer.concat(this._input)) : null;
    hostCall("proc", "run", [
      {
        shell: !!options.shell,
        command: file,
        args,
        cwd: options.cwd,
        env: options.env,
        timeout: options.timeout,
        input,
        // A detached child outlives the caller (`caffeinate -t 300 &`); don't wait for it to exit.
        detached: !!options.detached,
      },
    ]).then(
      (raw) => {
        this.exitCode = raw.status;
        this.stdout._deliver(Buffer.from(base64ToBytes(raw.stdout)));
        this.stderr._deliver(Buffer.from(base64ToBytes(raw.stderr)));
        this.emit("exit", raw.status, raw.signal ?? null);
        this.emit("close", raw.status, raw.signal ?? null);
      },
      (error) => {
        // Close the streams even on failure: a consumer that awaits stdout (execa does) would
        // otherwise see `undefined` where Node guarantees an empty string.
        this.exitCode = 1;
        this.stdout._deliver(Buffer.alloc(0));
        this.stderr._deliver(Buffer.from(String(error?.message ?? error), "utf8"));
        this.emit("error", error);
        this.emit("close", 1, null);
      },
    );
  }

  kill() {
    this.killed = true;
    return false;
  }

  // Node uses these to detach a child from the event loop. Nothing here keeps the runtime alive, so
  // they only need to exist and chain — `spawn(...).unref()` is a common one-liner.
  unref() {
    return this;
  }
  ref() {
    return this;
  }
}

// `util.promisify(exec)` must resolve to `{stdout, stderr}`, not to stdout alone — extensions
// destructure the result, and Node advertises that shape through this symbol.
const PROMISIFY_CUSTOM = Symbol.for("nodejs.util.promisify.custom");
childProcess.exec[PROMISIFY_CUSTOM] = (command, options) =>
  new Promise((resolve, reject) => {
    childProcess.exec(command, options, (error, stdout, stderr) => {
      if (error) {
        error.stdout = stdout;
        error.stderr = stderr;
        reject(error);
      } else {
        resolve({ stdout, stderr });
      }
    });
  });
childProcess.execFile[PROMISIFY_CUSTOM] = (file, args, options) =>
  new Promise((resolve, reject) => {
    childProcess.execFile(file, args, options, (error, stdout, stderr) => {
      if (error) {
        error.stdout = stdout;
        error.stderr = stderr;
        reject(error);
      } else {
        resolve({ stdout, stderr });
      }
    });
  });

function pickRunOptions(options = {}) {
  return { cwd: options.cwd, env: options.env, timeout: options.timeout, input: options.input ? bytesToBase64(Buffer.from(options.input)) : null };
}

/// Node guarantees `stdout` / `stderr` on a failed exec's error, and extensions inspect them (an
/// `error.stderr.match(…)` is the usual way to tell "no such table" from a real failure). A host call
/// that rejects outright has neither, so fill them in.
function decorateProcessError(error, label) {
  const decorated = error instanceof Error ? error : new Error(String(error));
  if (decorated.stdout === undefined) decorated.stdout = "";
  if (decorated.stderr === undefined) decorated.stderr = decorated.message;
  if (decorated.status === undefined) decorated.status = 1;
  if (decorated.code === undefined) decorated.code = 1;
  decorated.cmd = decorated.cmd ?? label;
  return decorated;
}

/// The async forms get a real async host call so a slow command can't stall the JS thread.
function runAsync(spec, options, callback, label) {
  const promise = hostCall("proc", "run", [spec])
    .then((raw) => normalizeExecResult(raw, options))
    .catch((error) => {
      throw decorateProcessError(error, label);
    });
  if (callback) {
    promise.then(
      (result) => callback(result.status === 0 ? null : execError(result, label), result.stdout, result.stderr),
      (error) => callback(error, error.stdout ?? "", error.stderr ?? ""),
    );
  }
  // Node returns a ChildProcess; extensions mostly ignore it or await the promisified form.
  const handle = { pid: 0, kill: () => false, on: () => handle, stdout: null, stderr: null };
  handle.then = promise.then.bind(promise);
  handle.catch = promise.catch.bind(promise);
  handle[Symbol.for("nodejs.util.promisify.custom")] = () => promise;
  return handle;
}

// ─── stream ─────────────────────────────────────────────────────────

// Only what `@raycast/utils`' `useExec` needs: it pipes a child's stdout into a `PassThrough` and
// reads back the buffered value, so `stream` cannot stay a stub or every `useExec` extension fails.
// Worse, it fails opaquely — the thrown "not supported" never reaches the extension, which reports
// the TypeError that follows from an undefined stdout instead. Everything else on the module still
// refuses to run.
class PassThrough extends EventEmitter {
  constructor() {
    super();
    this.readable = true;
    this.writable = true;
    this.writableEnded = false;
    this.encoding = null;
  }

  setEncoding(encoding) {
    this.encoding = encoding;
    return this;
  }

  write(chunk) {
    const decode = this.encoding && typeof chunk !== "string";
    this.emit("data", decode ? Buffer.from(chunk).toString(this.encoding) : chunk);
    return true;
  }

  end(chunk) {
    if (chunk !== undefined && chunk !== null) this.write(chunk);
    this.writableEnded = true;
    this.emit("end");
    this.emit("finish");
    this.emit("close");
  }

  pipe(destination) {
    this.on("data", (chunk) => destination.write?.(chunk));
    this.on("end", () => destination.end?.());
    return destination;
  }

  resume() {
    return this;
  }

  pause() {
    return this;
  }

  destroy() {
    return this;
  }
}

/// Callback form, so `util.promisify(stream.pipeline)` works. Completion comes from the last stage:
/// a source ends its destination when it ends, which is what `BufferedStream.pipe` wires up.
function pipeline(...stages) {
  const callback = typeof stages[stages.length - 1] === "function" ? stages.pop() : null;
  let settled = false;
  const finish = (error) => {
    if (settled) return;
    settled = true;
    callback?.(error ?? null);
  };
  const last = stages.reduce((from, to) => {
    from.on?.("error", finish);
    return from.pipe(to);
  });
  last.on("error", finish);
  last.on("finish", () => finish());
  last.on("end", () => finish());
  return last;
}

// ─── util ───────────────────────────────────────────────────────────

function inspect(value, depth = 2) {
  if (typeof value === "string") return `'${value}'`;
  if (typeof value === "function") return `[Function: ${value.name || "anonymous"}]`;
  if (value instanceof Error) return value.stack || String(value);
  if (value === null || typeof value !== "object") return String(value);
  if (depth < 0) return Array.isArray(value) ? "[Array]" : "[Object]";
  if (Array.isArray(value)) return `[ ${value.map((item) => inspect(item, depth - 1)).join(", ")} ]`;
  const body = Object.keys(value)
    .map((key) => `${key}: ${inspect(value[key], depth - 1)}`)
    .join(", ");
  return `{ ${body} }`;
}

function format(first, ...rest) {
  if (typeof first !== "string") return [first, ...rest].map((value) => inspect(value)).join(" ");
  let index = 0;
  const text = first.replace(/%[sdifjoO%]/g, (token) => {
    if (token === "%%") return "%";
    if (index >= rest.length) return token;
    const value = rest[index++];
    switch (token) {
      case "%s":
        return typeof value === "string" ? value : inspect(value);
      case "%d":
      case "%i":
        return String(parseInt(value, 10));
      case "%f":
        return String(parseFloat(value));
      case "%j":
        return JSON.stringify(value);
      default:
        return inspect(value);
    }
  });
  return [text, ...rest.slice(index).map((value) => inspect(value))].join(" ");
}

const promisifyCustom = Symbol.for("nodejs.util.promisify.custom");

const util = {
  promisify(fn) {
    if (fn[promisifyCustom]) return fn[promisifyCustom];
    return (...args) =>
      new Promise((resolve, reject) => {
        fn(...args, (error, value) => (error ? reject(error) : resolve(value)));
      });
  },
  callbackify(fn) {
    return (...args) => {
      const callback = args.pop();
      fn(...args).then((value) => callback(null, value), callback);
    };
  },
  inspect,
  format,
  /// Deliberately more forgiving than Node's: bundles call this at load time against classes from
  /// modules Tinycast only stubs, and a throw there would take down an extension that never reaches
  /// the code path.
  inherits(child, parent) {
    if (!child?.prototype || !parent?.prototype) return;
    Object.setPrototypeOf(child.prototype, parent.prototype);
    child.super_ = parent;
  },
  deprecate: (fn) => fn,
  isDeepStrictEqual: (a, b) => JSON.stringify(a) === JSON.stringify(b),
  TextEncoder: globalThis.TextEncoder,
  TextDecoder: globalThis.TextDecoder,
  types: {
    isDate: (value) => value instanceof Date,
    isRegExp: (value) => value instanceof RegExp,
    isPromise: (value) => !!value && typeof value.then === "function",
    isTypedArray: (value) => ArrayBuffer.isView(value),
    isUint8Array: (value) => value instanceof Uint8Array,
    isArrayBuffer: (value) => value instanceof ArrayBuffer,
  },
};
util.promisify.custom = promisifyCustom;

// ─── querystring / assert / string_decoder ──────────────────────────

const querystring = {
  parse(text) {
    const out = {};
    for (const [key, value] of new URLSearchParams(String(text || "").replace(/^[?]/, ""))) {
      if (out[key] === undefined) out[key] = value;
      else if (Array.isArray(out[key])) out[key].push(value);
      else out[key] = [out[key], value];
    }
    return out;
  },
  stringify(object) {
    const params = new URLSearchParams();
    for (const key of Object.keys(object || {})) {
      const value = object[key];
      if (Array.isArray(value)) for (const item of value) params.append(key, item);
      else params.append(key, value);
    }
    return params.toString();
  },
  escape: encodeURIComponent,
  unescape: decodeURIComponent,
};

function assert(value, message) {
  if (!value) throw new Error(message || "Assertion failed");
}
assert.ok = assert;
assert.equal = (a, b, message) => assert(a == b, message || `${a} != ${b}`);
assert.strictEqual = (a, b, message) => assert(a === b, message || `${a} !== ${b}`);
assert.notStrictEqual = (a, b, message) => assert(a !== b, message || `${a} === ${b}`);
assert.deepStrictEqual = (a, b, message) =>
  assert(JSON.stringify(a) === JSON.stringify(b), message || "not deeply equal");
assert.fail = (message) => assert(false, message);
assert.throws = (fn, message) => {
  try {
    fn();
  } catch {
    return;
  }
  assert(false, message || "Missing expected exception");
};

class StringDecoder {
  constructor(encoding = "utf8") {
    this.encoding = encoding;
  }
  write(bytes) {
    return Buffer.from(bytes).toString(this.encoding);
  }
  end(bytes) {
    return bytes ? this.write(bytes) : "";
  }
}

// ─── Modules that resolve but refuse to run ─────────────────────────

/// A module whose every member is a class that throws when constructed or called. Bundles routinely
/// do `class Foo extends stream.Readable` at load time and only reach the runtime path conditionally,
/// so the member has to be a real constructor — and unknown members must exist too, hence the Proxy.
function unsupportedModule(name, extras = {}) {
  const cache = new Map();
  return new Proxy(extras, {
    get(target, member) {
      if (member in target) return target[member];
      // Interop and probing keys must stay absent: a truthy `__esModule` makes esbuild's `__toESM`
      // skip the default-wrapping it would otherwise apply, and a truthy `then` makes the module
      // look like a thenable to `await`.
      if (typeof member !== "string" || RESERVED_MEMBERS.has(member)) return undefined;
      if (!cache.has(member)) cache.set(member, makeUnsupported(`${name}.${member}`));
      return cache.get(member);
    },
  });
}

const RESERVED_MEMBERS = new Set(["__esModule", "default", "then", "catch", "prototype", "constructor", "toJSON", "inspect", "valueOf", "toString", "length", "name"]);

function makeUnsupported(label) {
  const reason = `${label} is not supported in Tinycast extensions (no Node runtime). See docs/extensions.md.`;
  const Unsupported = class {
    constructor() {
      throw new Error(reason);
    }
  };
  // Callable as a plain function too — `stream.pipeline(...)`, `https.request(...)`.
  return new Proxy(Unsupported, {
    apply() {
      throw new Error(reason);
    },
  });
}

const httpLike = (name) =>
  unsupportedModule(name, { globalAgent: {}, STATUS_CODES: {}, METHODS: [] });

const streamStub = unsupportedModule("stream", { PassThrough, pipeline });

// ─── Registry ───────────────────────────────────────────────────────

export const nodeModules = {
  path,
  os,
  fs,
  "fs/promises": fsPromises,
  child_process: childProcess,
  crypto: cryptoModule,
  zlib,
  events: EventEmitter,
  util,
  buffer: bufferModule,
  process,
  querystring,
  punycode,
  assert,
  string_decoder: { StringDecoder },
  url: { URL, URLSearchParams, fileURLToPath: (input) => (input instanceof URL ? decodeURIComponent(input.pathname) : String(input).replace(/^file:\/\//, "")), pathToFileURL: (input) => new URL("file://" + encodeURI(String(input))), parse: (text) => new URL(text), format: (value) => String(value), resolve: (from, to) => new URL(to, from).href },
  timers: { setTimeout, clearTimeout, setInterval, clearInterval, setImmediate, clearImmediate },
  "timers/promises": { setTimeout: (ms, value) => new Promise((resolve) => setTimeout(() => resolve(value), ms)) },
  perf_hooks: { performance: globalThis.performance },
  http: httpLike("http"),
  https: httpLike("https"),
  net: unsupportedModule("net"),
  tls: unsupportedModule("tls"),
  dns: unsupportedModule("dns"),
  stream: streamStub,
  "stream/web": unsupportedModule("stream/web"),
  "stream/promises": unsupportedModule("stream/promises"),
  worker_threads: unsupportedModule("worker_threads", { isMainThread: true }),
  readline: unsupportedModule("readline"),
  tty: { isatty: () => false },
  vm: unsupportedModule("vm"),
  module: { createRequire: () => requireStub, builtinModules: [] },
  constants: {},
  cluster: { isPrimary: true, isMaster: true },
  inspector: {},
  v8: {},
  async_hooks: { AsyncLocalStorage: class { run(_store, fn) { return fn(); } getStore() { return undefined; } } },
};

function requireStub(name) {
  throw new Error(`createRequire is not supported in Tinycast extensions (tried to load "${name}").`);
}

// Every remaining Node builtin resolves to a refuse-on-use stub. Bundles reference the whole
// long tail (dgram, http2, domain, repl, …) from dependencies that only touch them on paths an
// extension never reaches, so a require-time throw would fail extensions that actually work.
const REMAINING_BUILTINS = [
  "assert/strict", "console", "dgram", "diagnostics_channel", "dns/promises", "domain", "http2",
  "inspector/promises", "path/posix", "path/win32", "readline/promises", "repl",
  "stream/consumers", "sys", "trace_events", "util/types", "wasi", "sea", "sqlite", "test",
  "test/reporters",
];
for (const name of REMAINING_BUILTINS) {
  if (!nodeModules[name]) nodeModules[name] = unsupportedModule(name);
}
nodeModules["assert/strict"] = assert;
nodeModules["path/posix"] = path;
nodeModules["path/win32"] = path;
nodeModules["util/types"] = util.types;
nodeModules["dns/promises"] = nodeModules.dns;
nodeModules["readline/promises"] = nodeModules.readline;
nodeModules.console = globalThis.console;

// Node builtins are addressable with and without the `node:` prefix.
for (const name of Object.keys(nodeModules)) {
  nodeModules[`node:${name}`] = nodeModules[name];
}

globalThis.process = process;
globalThis.Buffer = Buffer;
globalThis.global = globalThis;

export { Buffer, process, EventEmitter };
