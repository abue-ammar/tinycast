// Entry point. Installs the polyfills and the module registry, then exposes `__tinycast` — the only
// thing Swift calls into.

import "./polyfills.js";
import "./url.js";
import { createElement } from "react";
import * as React from "react";
import * as JSXRuntime from "react/jsx-runtime";
import { describeError, log, settle } from "./host.js";
import { fireTimer, setUncaughtHandler } from "./polyfills.js";
import { configureNodeShims } from "./node-shims.js";
import { defineModule, evaluateCommonJS } from "./modules.js";
import { NavigationRoot, setFieldCommandHandler } from "./api/components.js";
import { Surface } from "./reconciler.js";
import { raycastApi } from "./api/index.js";
import { configureSystem, runToastAction } from "./api/system.js";

defineModule("react", React);
defineModule("react/jsx-runtime", JSXRuntime);
defineModule("react/jsx-dev-runtime", JSXRuntime);
defineModule("@raycast/api", raycastApi);
// react-dom only appears in bundles defensively; make the import resolve and the calls explain.
defineModule("react-dom", {
  render: () => {
    throw new Error("react-dom is not available — Tinycast renders extensions natively.");
  },
  createPortal: (children) => children,
  flushSync: (fn) => fn?.(),
  version: React.version,
});

const sessions = new Map();

/// One running command. A view command mounts a React tree through `Surface`; a no-view command just
/// awaits its default export.
class Session {
  constructor(id, host) {
    this.id = id;
    this.host = host;
    this.surface = null;
    this.navigationDepth = 1;
    this.navigation = {};
  }

  mountView(element) {
    this.surface = new Surface(
      (tree) => this.host.render(this.id, JSON.stringify(tree)),
      (error) => this.fail(error),
    );
    this.surface.render(
      createElement(NavigationRoot, {
        initial: element,
        controls: this.navigation,
        onStackChange: (depth) => {
          this.navigationDepth = depth;
          this.host.navigationDepthChanged(this.id, depth);
        },
      }),
    );
  }

  fail(error) {
    this.host.failed(this.id, describeError(error));
  }

  unmount() {
    this.surface?.unmount();
    this.surface = null;
  }
}


const hostCalls = {
  render: (sessionId, json) => globalThis.__tinycastHost.render(sessionId, json),
  failed: (sessionId, message) => globalThis.__tinycastHost.failed(sessionId, message),
  navigationDepthChanged: (sessionId, depth) =>
    globalThis.__tinycastHost.navigationDepthChanged(sessionId, String(depth)),
  finished: (sessionId) => globalThis.__tinycastHost.finished(sessionId),
};

setUncaughtHandler((error) => {
  const message = describeError(error);
  log("error", [message]);
  // Attribute an unhandled rejection to the only running session when there is exactly one, so the
  // palette can show it instead of failing silently.
  if (sessions.size === 1) {
    const [session] = sessions.values();
    session.fail(error);
  }
});

setFieldCommandHandler((command, fieldId) => {
  globalThis.__tinycastHost.fieldCommand(String(command), String(fieldId ?? ""));
});

globalThis.__tinycast = {
  /// Called once, before any command runs.
  boot(configJson) {
    const config = JSON.parse(configJson);
    configureNodeShims(config.node ?? {});
    configureSystem(config);
    return "ok";
  },

  /// Load and start one command. `mode` is "view" or "no-view"; a view command's default export is a
  /// component, a no-view command's is an async function.
  start(sessionId, code, filename, dirname, mode, contextJson) {
    const context = JSON.parse(contextJson || "{}");
    configureSystem(context);
    const session = new Session(sessionId, hostCalls);
    sessions.set(sessionId, session);
    // Commands declaring `arguments` read `props.arguments.<name>` unguarded, so the bag always exists.
    const launchProps = {
      launchType: "userInitiated",
      arguments: {},
      ...(context.launchProps ?? {}),
    };
    try {
      const exports = evaluateCommonJS(code, filename, dirname);
      const entry = exports?.default ?? exports;
      if (mode === "view") {
        if (typeof entry !== "function") {
          throw new Error("A view command must default-export a React component.");
        }
        session.mountView(createElement(entry, launchProps));
      } else {
        if (typeof entry !== "function") {
          throw new Error("A no-view command must default-export a function.");
        }
        Promise.resolve(entry(launchProps)).then(
          () => hostCalls.finished(sessionId),
          (error) => session.fail(error),
        );
      }
    } catch (error) {
      session.fail(error);
    }
    return "ok";
  },

  /// Route a UI event back to the callback it came from.
  dispatch(sessionId, handlerId, argsJson) {
    const session = sessions.get(sessionId);
    if (!session?.surface) return "0";
    try {
      const args = JSON.parse(argsJson || "[]").map(reviveArg);
      return session.surface.dispatch(handlerId, args) ? "1" : "0";
    } catch (error) {
      session.fail(error);
      return "0";
    }
  },

  /// Escape / the back chevron in a pushed screen.
  popNavigation(sessionId) {
    const session = sessions.get(sessionId);
    if (!session?.surface || session.navigationDepth <= 1) return "0";
    session.navigation.pop?.();
    return "1";
  },

  settle,
  fireTimer,
  runToastAction,

  stop(sessionId) {
    sessions.get(sessionId)?.unmount();
    sessions.delete(sessionId);
    return "ok";
  },
};

/// `{"$date": …}` is how a Form.DatePicker value crosses back from Swift.
function reviveArg(value) {
  if (value && typeof value === "object") {
    if (typeof value.$date === "string") return new Date(value.$date);
    if (Array.isArray(value)) return value.map(reviveArg);
  }
  return value;
}
