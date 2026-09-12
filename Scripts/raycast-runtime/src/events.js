// Node's `events`. Its own module because the stream core builds on it and `node-shims` builds on
// the stream core, so leaving it there would close an import cycle.

export class EventEmitter {
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
EventEmitter.setMaxListeners = () => {};
EventEmitter.addAbortListener = (signal, listener) => (signal.addEventListener("abort", listener), { [Symbol.dispose]: () => signal.removeEventListener("abort", listener) });
EventEmitter.on = (emitter, event, { signal } = {}) => {
  const queue = [], waiters = [], listener = (...args) => waiters.length ? waiters.shift()({ value: args, done: false }) : queue.push(args);
  const stop = () => { emitter.off(event, listener); while (waiters.length) waiters.shift()({ done: true }); };
  emitter.on(event, listener);
  signal?.addEventListener("abort", stop, { once: true });
  return { [Symbol.asyncIterator]() { return this; }, next() { return queue.length ? Promise.resolve({ value: queue.shift(), done: false }) : signal?.aborted ? Promise.resolve({ done: true }) : new Promise(resolve => waiters.push(resolve)); }, return() { stop(); return Promise.resolve({ done: true }); } };
};
EventEmitter.once = (emitter, event) =>
  new Promise((resolve) => emitter.once(event, (...args) => resolve(args)));
