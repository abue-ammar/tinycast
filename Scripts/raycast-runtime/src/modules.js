// The `require` an extension bundle sees. Bundles are single-file CJS with `react`,
// `react/jsx-runtime`, `@raycast/api` and the Node builtins left external — exactly the set below.

import { nodeModules } from "./node-shims.js";

const registry = new Map();

export function defineModule(name, exports) {
  registry.set(name, exports);
}

for (const name of Object.keys(nodeModules)) defineModule(name, nodeModules[name]);

export function requireModule(name) {
  const key = String(name);
  if (registry.has(key)) return registry.get(key);
  // Deep imports into a provided package (`react-dom/client`) resolve to the package itself rather
  // than exploding, which is enough for the handful of bundles that reference them defensively.
  const root = key.startsWith("@") ? key.split("/").slice(0, 2).join("/") : key.split("/")[0];
  if (registry.has(root)) return registry.get(root);
  throw new Error(
    `Cannot find module '${key}'. Tinycast provides React, @raycast/api and a subset of Node builtins — see docs/extensions.md.`,
  );
}

/// Evaluate one CJS bundle. `filename`/`dirname` matter: extensions resolve bundled assets relative
/// to `__dirname`, and `environment.assetsPath` points at the same directory.
export function evaluateCommonJS(code, filename, dirname) {
  const module = { exports: {}, id: filename, filename, loaded: false, children: [], paths: [] };
  const factory = globalThis.__tinycastCompile(code, filename);
  factory(module.exports, requireModule, module, filename, dirname);
  module.loaded = true;
  return module.exports;
}
