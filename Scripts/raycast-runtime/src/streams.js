// Node's stream core. Extensions that parse a large JSON index ship `stream-chain` + `stream-json`,
// which build real object-mode pipelines: a `Duplex` from an options bag, `Transform` subclasses
// that `push` from `_transform`, `pipe` chains, and `push()` returning false to stop the source.
// Nothing short of the actual contract carries that, so this is the contract, not a stand-in.
//
// One deliberate shortcut: a `Transform` acknowledges a write as soon as `_transform` calls back
// rather than waiting for room on its readable side. `pipe` still pauses a source whose destination
// is full, so a chain stays bounded; only a transform nobody reads from grows.

import { Buffer } from "./buffer.js";
import { EventEmitter } from "./events.js";
import { ReadableStream } from "./web-streams.js";

const ignore = () => {};

function sizeOf(chunk, objectMode) {
  if (objectMode) return 1;
  return typeof chunk === "string" ? chunk.length : (chunk?.length ?? 0);
}

/// Node's legacy base. `module.exports = Stream`, and bundles lean on that: node-fetch tests
/// `body instanceof stream.default` on every Request it builds.
export class Stream extends EventEmitter {}

export class Readable extends Stream {
  constructor(options = {}) {
    super();
    const objectMode = options.readableObjectMode ?? options.objectMode ?? false;
    this._readableState = {
      readable: true,
      objectMode,
      highWaterMark: options.highWaterMark ?? (objectMode ? 16 : 16 * 1024),
      buffer: [],
      length: 0,
      encoding: options.encoding ?? null,
      flowing: false,
      reading: false,
      ended: false,
      endEmitted: false,
      destroyed: false,
      scheduled: false,
      waiter: null,
    };
    if (options.read) this._read = options.read;
    if (options.destroy) this._destroy = options.destroy;
  }

  get readable() {
    return !this._readableState.endEmitted && !this._readableState.destroyed;
  }
  get readableEnded() {
    return this._readableState.endEmitted;
  }
  get readableFlowing() {
    return this._readableState.flowing;
  }
  get readableObjectMode() {
    return this._readableState.objectMode;
  }
  get readableLength() {
    return this._readableState.length;
  }
  get destroyed() {
    return this._readableState.destroyed;
  }

  _read() {}

  push(chunk, encoding) {
    const state = this._readableState;
    state.reading = false;
    if (state.ended || state.destroyed) return false;
    if (chunk === null || chunk === undefined) {
      state.ended = true;
      this._schedule();
      return false;
    }
    if (!state.objectMode) {
      if (typeof chunk === "string") chunk = Buffer.from(chunk, encoding || "utf8");
      else if (!(chunk instanceof Buffer)) chunk = Buffer.from(chunk);
      if (state.encoding) chunk = chunk.toString(state.encoding);
    }
    state.buffer.push(chunk);
    state.length += sizeOf(chunk, state.objectMode);
    this._schedule();
    return state.length < state.highWaterMark;
  }

  read() {
    const state = this._readableState;
    if (!state.buffer.length) {
      this._pull();
      return null;
    }
    const chunk = state.buffer.shift();
    state.length -= sizeOf(chunk, state.objectMode);
    this._pull();
    return chunk;
  }

  setEncoding(encoding) {
    this._readableState.encoding = encoding;
    return this;
  }

  resume() {
    this._readableState.flowing = true;
    this._schedule();
    return this;
  }

  pause() {
    this._readableState.flowing = false;
    return this;
  }

  isPaused() {
    return !this._readableState.flowing;
  }

  on(event, listener) {
    super.on(event, listener);
    if (event === "data") this.resume();
    else if (event === "readable") this._schedule();
    return this;
  }

  pipe(destination) {
    const resume = () => this.resume();
    this.on("data", (chunk) => {
      if (destination.write(chunk) === false) {
        this.pause();
        destination.once("drain", resume);
      }
    });
    this.on("end", () => destination.end?.());
    this.on("error", (error) => destination.destroy?.(error));
    return destination;
  }

  unpipe() {
    return this.pause();
  }

  destroy(error) {
    const state = this._readableState;
    if (state.destroyed) return this;
    state.destroyed = true;
    state.readable = false;
    state.buffer.length = 0;
    state.length = 0;
    this._wake();
    const close = (reason) => {
      if (reason) this.emit("error", reason);
      this.emit("close");
    };
    if (this._destroy) this._destroy(error ?? null, close);
    else close(error);
    return this;
  }

  async *[Symbol.asyncIterator]() {
    const state = this._readableState;
    for (;;) {
      if (state.buffer.length) {
        yield this.read();
        continue;
      }
      if (state.ended || state.destroyed) return;
      this._pull();
      if (!state.buffer.length && !state.ended && !state.destroyed) {
        await new Promise((resolve) => (state.waiter = resolve));
      }
    }
  }

  /// Ask the source for more only when there is room and no request already outstanding.
  _pull() {
    const state = this._readableState;
    if (state.reading || state.ended || state.destroyed) return;
    if (state.length >= state.highWaterMark) return;
    state.reading = true;
    try {
      this._read(state.highWaterMark);
    } catch (error) {
      state.reading = false;
      this.destroy(error);
    }
  }

  _wake() {
    const waiter = this._readableState.waiter;
    if (!waiter) return;
    this._readableState.waiter = null;
    waiter();
  }

  /// Deliver a tick late, as Node does: a producer that pushes then ends must not outrun its listeners.
  _schedule() {
    const state = this._readableState;
    this._wake();
    if (state.scheduled || state.destroyed) return;
    state.scheduled = true;
    queueMicrotask(() => {
      state.scheduled = false;
      if (state.destroyed) return;
      while (state.flowing && state.buffer.length) this.emit("data", this.read());
      if (state.buffer.length) this.emit("readable");
      if (state.ended && !state.buffer.length && !state.endEmitted) {
        state.endEmitted = true;
        state.readable = false;
        this.emit("end");
        this.emit("close");
      } else {
        this._pull();
      }
    });
  }
}

Readable.from = (iterable, options) => {
  const iterator = iterable[Symbol.asyncIterator]?.() ?? iterable[Symbol.iterator]();
  return new Readable({
    objectMode: true,
    ...options,
    async read() {
      try {
        const { value, done } = await iterator.next();
        this.push(done ? null : value);
      } catch (error) {
        this.destroy(error);
      }
    },
  });
};

Readable.fromWeb = (stream, options) => {
  const reader = stream.getReader();
  return new Readable({
    ...options,
    async read() {
      try {
        const { value, done } = await reader.read();
        this.push(done ? null : value);
      } catch (error) {
        this.destroy(error);
      }
    },
    destroy(error, close) {
      reader.cancel(error ?? undefined).catch(ignore);
      close(error);
    },
  });
};

Readable.toWeb = (readable) =>
  new ReadableStream({
    start(controller) {
      readable.on("data", (chunk) => controller.enqueue(chunk));
      readable.on("end", () => controller.close());
      readable.on("error", (error) => controller.error(error));
    },
    cancel: (reason) => readable.destroy(reason),
  });

function initWritable(stream, options) {
  const objectMode = options.writableObjectMode ?? options.objectMode ?? false;
  stream._writableState = {
    writable: true,
    objectMode,
    highWaterMark: options.highWaterMark ?? (objectMode ? 16 : 16 * 1024),
    buffer: [],
    length: 0,
    defaultEncoding: options.defaultEncoding ?? "utf8",
    pumping: false,
    needDrain: false,
    ending: false,
    ended: false,
    finished: false,
    destroyed: false,
  };
  if (options.write) stream._write = options.write;
  if (options.final) stream._final = options.final;
  if (options.destroy) stream._destroy = options.destroy;
}

export class Writable extends Stream {
  constructor(options = {}) {
    super();
    initWritable(this, options);
  }

  get writable() {
    return !this._writableState.ending && !this._writableState.destroyed;
  }
  get writableEnded() {
    return this._writableState.ending;
  }
  get writableFinished() {
    return this._writableState.finished;
  }
  get writableObjectMode() {
    return this._writableState.objectMode;
  }
  get writableLength() {
    return this._writableState.length;
  }

  _write(chunk, encoding, callback) {
    callback(new Error("_write() is not implemented on this stream."));
  }

  _final(callback) {
    callback(null);
  }

  write(chunk, encoding, callback) {
    if (typeof encoding === "function") {
      callback = encoding;
      encoding = null;
    }
    const state = this._writableState;
    if (state.ending || state.destroyed) {
      queueMicrotask(() => callback?.(new Error("write after end")));
      return false;
    }
    state.buffer.push({ chunk, encoding: encoding ?? state.defaultEncoding, callback });
    state.length += sizeOf(chunk, state.objectMode);
    // Claim the drain before pumping: a synchronous `_write` empties the queue inside this call.
    const room = state.length < state.highWaterMark;
    state.needDrain = state.needDrain || !room;
    this._pump();
    return room;
  }

  end(chunk, encoding, callback) {
    if (typeof chunk === "function") return this.end(null, null, chunk);
    if (typeof encoding === "function") return this.end(chunk, null, encoding);
    if (chunk !== null && chunk !== undefined) this.write(chunk, encoding);
    if (callback) this.once("finish", () => callback(null));
    this._writableState.ending = true;
    this._pump();
    return this;
  }

  cork() {}
  uncork() {}

  destroy(error) {
    const state = this._writableState;
    if (state.destroyed) return this;
    state.destroyed = true;
    state.writable = false;
    state.buffer.length = 0;
    const close = (reason) => {
      if (reason) this.emit("error", reason);
      this.emit("close");
    };
    if (this._destroy) this._destroy(error ?? null, close);
    else close(error);
    return this;
  }

  /// One `_write` in flight; the next starts from its callback, so writes stay in order.
  _pump() {
    const state = this._writableState;
    if (state.pumping) return;
    state.pumping = true;
    const step = () => {
      if (state.destroyed) {
        state.pumping = false;
        return;
      }
      const entry = state.buffer.shift();
      if (!entry) {
        state.pumping = false;
        // A tick late, as Node does: `pipe` only attaches its drain listener after `write` returns.
        if (state.needDrain) {
          state.needDrain = false;
          queueMicrotask(() => this.emit("drain"));
        }
        if (state.ending && !state.ended) this._finishWrites();
        return;
      }
      state.length -= sizeOf(entry.chunk, state.objectMode);
      let settled = false;
      const done = (error) => {
        if (settled) return;
        settled = true;
        entry.callback?.(error ?? null);
        if (error) {
          state.pumping = false;
          this.destroy(error);
          return;
        }
        step();
      };
      try {
        this._write(entry.chunk, entry.encoding, done);
      } catch (error) {
        done(error);
      }
    };
    step();
  }

  _finishWrites() {
    const state = this._writableState;
    state.ended = true;
    this._final((error) => {
      if (error) return this.destroy(error);
      state.finished = true;
      state.writable = false;
      this.emit("finish");
    });
  }
}

Writable.fromWeb = (stream, options) => {
  const writer = stream.getWriter();
  return new Writable({
    ...options,
    write(chunk, encoding, callback) {
      writer.write(chunk).then(() => callback(null), callback);
    },
    final(callback) {
      writer.close().then(() => callback(null), callback);
    },
  });
};

// Node builds `Duplex` the same way: extend `Readable`, then borrow the writable half wholesale.
export class Duplex extends Readable {
  constructor(options = {}) {
    super(options);
    initWritable(this, options);
    if (options.read) this._read = options.read;
  }

  destroy(error) {
    this._writableState.destroyed = true;
    this._writableState.writable = false;
    this._writableState.buffer.length = 0;
    return Readable.prototype.destroy.call(this, error);
  }
}

for (const name of ["_write", "_final", "write", "end", "cork", "uncork", "_pump", "_finishWrites"]) {
  Duplex.prototype[name] = Writable.prototype[name];
}
for (const name of ["writable", "writableEnded", "writableFinished", "writableObjectMode", "writableLength"]) {
  Object.defineProperty(Duplex.prototype, name, Object.getOwnPropertyDescriptor(Writable.prototype, name));
}

Duplex.fromWeb = (pair, options) => {
  const source = Readable.fromWeb(pair.readable, options);
  const writer = pair.writable.getWriter();
  const duplex = new Duplex({
    ...options,
    read: () => source.resume(),
    write(chunk, encoding, callback) {
      writer.write(chunk).then(() => callback(null), callback);
    },
    final(callback) {
      writer.close().then(() => callback(null), callback);
    },
  });
  source.on("data", (chunk) => duplex.push(chunk));
  source.on("end", () => duplex.push(null));
  source.on("error", (error) => duplex.destroy(error));
  return duplex;
};

export class Transform extends Duplex {
  constructor(options = {}) {
    super(options);
    if (options.transform) this._transform = options.transform;
    if (options.flush) this._flush = options.flush;
  }

  _transform(chunk, encoding, callback) {
    callback(null, chunk);
  }

  _flush(callback) {
    callback(null);
  }

  _write(chunk, encoding, callback) {
    this._transform(chunk, encoding, (error, data) => {
      if (data !== null && data !== undefined) this.push(data);
      callback(error ?? null);
    });
  }

  _final(callback) {
    this._flush((error, data) => {
      if (data !== null && data !== undefined) this.push(data);
      if (!error) this.push(null);
      callback(error ?? null);
    });
  }
}

export class PassThrough extends Transform {}

export function pipelinePromise(stages) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const fail = (error) => {
      if (settled) return;
      settled = true;
      for (const stage of stages) stage.destroy?.();
      reject(error instanceof Error ? error : new Error(String(error)));
    };
    for (const stage of stages) stage.on?.("error", fail);
    const last = stages.reduce((from, to) => from.pipe(to));
    const done = () => {
      if (settled) return;
      settled = true;
      resolve();
    };
    if (last._writableState) last.on("finish", done);
    else last.on("end", done);
  });
}

/// Callback-last, so `util.promisify(stream.pipeline)` works; `stream/promises` awaits the same core.
export function pipeline(...stages) {
  const callback = typeof stages[stages.length - 1] === "function" ? stages.pop() : ignore;
  const last = stages[stages.length - 1];
  pipelinePromise(stages).then(() => callback(null), callback);
  return last;
}

function onFinished(stream, settle) {
  stream.on("error", settle);
  stream.on("close", () => settle(null));
  stream.on("finish", () => settle(null));
  stream.on("end", () => settle(null));
}

export function finished(stream, callback) {
  let settled = false;
  onFinished(stream, (error) => {
    if (settled) return;
    settled = true;
    callback?.(error ?? null);
  });
}

export function finishedPromise(stream) {
  return new Promise((resolve, reject) => onFinished(stream, (error) => (error ? reject(error) : resolve())));
}
