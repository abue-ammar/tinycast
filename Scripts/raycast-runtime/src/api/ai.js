// `AI` from @raycast/api, answered by the routes the reader configured in Settings → AI rather
// than by Raycast's hosted models. Swift streams the reply as progress and settles with the whole
// text, so `await AI.ask(…)` and `.on("data")` both behave as they do in Raycast.

import { cancelHostCall, hostCallStreaming } from "../host.js";
import { nestedEnums } from "./enums.generated.js";

/// Raycast's 0–2 creativity scale, kept as-is; each route maps it onto its own temperature.
const creativityScale = Object.freeze({ none: 0, low: 0.5, medium: 1, high: 1.5, maximum: 2 });

const Creativity = Object.freeze({
  None: "none",
  Low: "low",
  Medium: "medium",
  High: "high",
  Maximum: "maximum",
});

/// Names from an older or newer @raycast/api than the one generated still resolve to an id that
/// names their vendor, which is all Tinycast needs to pick a matching route.
const Model = new Proxy(nestedEnums.AI?.Model ?? {}, {
  get(target, key) {
    if (typeof key !== "string") return target[key];
    if (key in target) return target[key];
    return derivedModelID(key);
  },
});

function derivedModelID(name) {
  const separator = name.indexOf("_");
  if (separator <= 0) return name.toLowerCase();
  const vendor = name.slice(0, separator).toLowerCase();
  const rest = name.slice(separator + 1).replace(/_/g, "-").toLowerCase();
  return `${vendor}-${rest}`;
}

export function normalizeCreativity(creativity) {
  if (creativity === undefined || creativity === null) return null;
  if (typeof creativity === "number") {
    if (!Number.isFinite(creativity)) return null;
    return Math.min(2, Math.max(0, creativity));
  }
  const value = creativityScale[String(creativity).toLowerCase()];
  return value === undefined ? null : value;
}

export function normalizeModel(model) {
  if (typeof model === "string" && model) return model;
  if (model && typeof model === "object" && typeof model.id === "string" && model.id) return model.id;
  return null;
}

function abortError(signal) {
  const reason = signal?.reason;
  if (reason instanceof Error) return reason;
  const error = new Error(typeof reason === "string" ? reason : "The operation was aborted.");
  error.name = "AbortError";
  return error;
}

function ask(prompt, options = {}) {
  const listeners = [];
  let streamed = "";
  let settled = false;
  let callId = null;
  let removeAbort = () => {};

  const promise = new Promise((resolve, reject) => {
    const signal = options?.signal;
    if (signal?.aborted) {
      settled = true;
      reject(abortError(signal));
      return;
    }
    const request = {
      prompt: String(prompt ?? ""),
      creativity: normalizeCreativity(options?.creativity),
      model: normalizeModel(options?.model),
    };
    const call = hostCallStreaming("ai", "ask", [request], (chunk) => {
      if (settled || typeof chunk !== "string" || !chunk) return;
      streamed += chunk;
      for (const listener of [...listeners]) {
        try {
          listener(chunk);
        } catch {
          // One throwing listener must not starve the others or fail the whole answer.
        }
      }
    });
    callId = call.callId;
    if (signal?.addEventListener) {
      const onAbort = () => {
        if (settled) return;
        settled = true;
        cancelHostCall(callId);
        reject(abortError(signal));
      };
      signal.addEventListener("abort", onAbort, { once: true });
      removeAbort = () => signal.removeEventListener?.("abort", onAbort);
    }
    call.promise.then(
      (text) => {
        removeAbort();
        if (settled) return;
        settled = true;
        resolve(typeof text === "string" ? text : streamed);
      },
      (error) => {
        removeAbort();
        if (settled) return;
        settled = true;
        reject(error instanceof Error ? error : new Error(String(error)));
      },
    );
  });

  promise.on = (event, listener) => {
    if (event === "data" && typeof listener === "function") {
      // A listener attached after the first chunks still sees the answer from its start.
      if (streamed) {
        try {
          listener(streamed);
        } catch {
          // Same as a live chunk: the listener's failure is its own.
        }
      }
      listeners.push(listener);
    }
    return promise;
  };
  promise.off = (event, listener) => {
    const index = listeners.indexOf(listener);
    if (index >= 0) listeners.splice(index, 1);
    return promise;
  };
  return promise;
}

export const AI = {
  ask,
  Model,
  Creativity,
  refreshModels: () => Promise.resolve(),
  experimental_decide: () =>
    Promise.reject(new Error("AI.experimental_decide is not supported in Tinycast extensions yet.")),
};
