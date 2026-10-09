// The single seam between the JS runtime and Swift. Swift installs `__tinycastHost` on the global
// before evaluating the bundle; everything else in here goes through these helpers.

const raw = globalThis.__tinycastHost;
if (!raw) throw new Error("__tinycastHost missing — the runtime was evaluated outside Tinycast.");

export const hostRaw = raw;

let nextCallId = 1;
const pending = new Map();

/// Every Raycast API that touches the system is an async host call: Swift answers later via
/// `__tinycast.settle`, so the JS thread never blocks waiting on the main actor.
export function hostCall(api, method, args) {
  return hostCallStreaming(api, method, args).promise;
}

/// A host call that may report progress before it settles (`AI.ask`'s chunks). `onProgress` gets
/// each JSON payload Swift sends through `__tinycast.progress`, always ahead of the settle.
export function hostCallStreaming(api, method, args, onProgress) {
  const callId = nextCallId++;
  const promise = new Promise((resolve, reject) => {
    pending.set(callId, { resolve, reject, onProgress });
    try {
      raw.invoke(String(callId), api, method, JSON.stringify(args === undefined ? [] : args));
    } catch (error) {
      pending.delete(callId);
      reject(error);
    }
  });
  return { callId, promise };
}

/// Forgets a call and asks Swift to cancel its task; a settle that still arrives is dropped.
export function cancelHostCall(callId) {
  if (!pending.delete(Number(callId))) return;
  try {
    raw.cancel?.(String(callId));
  } catch {
    // A host without cancellation simply finishes the work and its answer is ignored.
  }
}

export function progress(callId, payload) {
  const entry = pending.get(Number(callId));
  if (!entry?.onProgress) return;
  try {
    entry.onProgress(payload === undefined || payload === "" ? undefined : JSON.parse(payload));
  } catch (error) {
    log("error", [error]);
  }
}

/// The blocking counterpart, for the node shims only (fs, child_process, crypto, zlib). Safe because
/// Swift services these entirely on the JS thread — nothing here ever hops to the main actor, so a
/// synchronous answer can't deadlock against the UI.
export function hostCallSync(api, method, args) {
  const json = hostRaw.invokeSync(api, method, JSON.stringify(args === undefined ? [] : args));
  const result = json ? JSON.parse(json) : { ok: true };
  if (result.ok) return result.value;
  const error = new Error(String(result.error || `${api}.${method} failed`));
  if (result.code) error.code = result.code;
  if (result.errno !== undefined) error.errno = result.errno;
  if (result.path) error.path = result.path;
  throw error;
}

export function settle(callId, ok, payload) {
  const entry = pending.get(Number(callId));
  if (!entry) return;
  pending.delete(Number(callId));
  if (ok) {
    entry.resolve(payload === undefined || payload === "" ? undefined : JSON.parse(payload));
  } else {
    entry.reject(new Error(String(payload || "Host call failed")));
  }
}

export function log(level, parts) {
  let text;
  try {
    text = parts.map(formatLogArg).join(" ");
  } catch {
    text = "[unserializable log argument]";
  }
  raw.log(level, text);
}

function formatLogArg(value) {
  if (typeof value === "string") return value;
  if (value instanceof Error) return describeError(value);
  if (value === undefined) return "undefined";
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

/// JavaScriptCore's `Error.stack` is frames only — unlike V8 it does not repeat the message — so the
/// headline has to be prepended or a logged error arrives as a bare stack.
export function describeError(error) {
  if (!(error instanceof Error)) return String(error);
  const headline = `${error.name || "Error"}: ${error.message}`;
  const stack = String(error.stack || "");
  if (!stack) return headline;
  return stack.startsWith(headline) ? stack : `${headline}\n${stack}`;
}
