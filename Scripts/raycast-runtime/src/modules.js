// Builtins use the registry; store bundles also ship CommonJS packages beside the commands.

import { nodeModules } from "./node-shims.js";

const registry = new Map();

export function defineModule(name, exports) {
  registry.set(name, exports);
}

for (const name of Object.keys(nodeModules)) defineModule(name, nodeModules[name]);

const localFs = nodeModules.fs;
const localPath = nodeModules.path;
const fileModules = new Map();

function notFound(key) {
  throw new Error(
    `Cannot find module '${key}'. Tinycast provides React, @raycast/api and a subset of Node builtins — see docs/extensions.md.`,
  );
}

function isBare(request) {
  if (request === "." || request === "..") return false;
  return !request.startsWith("./") && !request.startsWith("../") && !request.startsWith("/");
}

function asFile(base) {
  for (const candidate of [base, `${base}.js`, `${base}.json`, `${base}.cjs`]) {
    if (localFs.statSync(candidate, { throwIfNoEntry: false })?.isFile()) return candidate;
  }
  return null;
}

function conditionalTarget(value) {
  if (typeof value === "string") return value;
  if (value && typeof value === "object") {
    for (const [condition, target] of Object.entries(value)) {
      if (!["require", "node", "default"].includes(condition)) continue;
      const resolved = conditionalTarget(target);
      if (resolved) return resolved;
    }
  }
  return null;
}

function exportsTarget(exportsField, subpath) {
  const key = subpath.length ? `./${subpath.join("/")}` : ".";
  if (typeof exportsField === "string") return key === "." ? exportsField : null;
  if (!exportsField || typeof exportsField !== "object" || Array.isArray(exportsField)) return null;

  if (!Object.keys(exportsField).some((entry) => entry === "." || entry.startsWith("./"))) {
    return key === "." ? conditionalTarget(exportsField) : null;
  }

  if (Object.hasOwn(exportsField, key)) return conditionalTarget(exportsField[key]);
  const patterns = Object.keys(exportsField).filter((pattern) => pattern.includes("*"));
  patterns.sort((a, b) => b.indexOf("*") - a.indexOf("*") || b.length - a.length);
  for (const pattern of patterns) {
    const prefix = pattern.slice(0, pattern.indexOf("*"));
    const suffix = pattern.slice(pattern.indexOf("*") + 1);
    if (key.startsWith(prefix) && key.endsWith(suffix) && key.length >= prefix.length + suffix.length) {
      const replacement = key.slice(prefix.length, key.length - suffix.length);
      const resolved = conditionalTarget(exportsField[pattern]);
      if (resolved) return resolved.replace("*", replacement);
    }
  }
  return null;
}

function loadPackageJson(packageDir) {
  const manifestPath = localPath.join(packageDir, "package.json");
  if (!localFs.existsSync(manifestPath)) return null;
  try {
    return JSON.parse(localFs.readFileSync(manifestPath, "utf8"));
  } catch {
    return null;
  }
}

function asDirectory(base) {
  if (!localFs.statSync(base, { throwIfNoEntry: false })?.isDirectory()) return null;
  const manifest = loadPackageJson(base);
  if (manifest && Object.hasOwn(manifest, "exports")) {
    const target = exportsTarget(manifest.exports, []);
    return target ? asFile(localPath.join(base, target)) : null;
  }
  if (typeof manifest?.main === "string") {
    const main = localPath.join(base, manifest.main);
    const resolved = asFile(main) ?? asFile(localPath.join(main, "index"));
    if (resolved) return resolved;
  }
  return asFile(localPath.join(base, "index"));
}

function resolvePackage(request, fromDir, root) {
  const parts = request.split("/");
  const packageName = request.startsWith("@") ? parts.slice(0, 2).join("/") : parts[0];
  const subpath = request.startsWith("@") ? parts.slice(2) : parts.slice(1);

  for (let dir = fromDir; dir === root || dir.startsWith(`${root}/`); dir = localPath.dirname(dir)) {
    const packageDir = localPath.join(dir, "node_modules", packageName);
    if (localFs.existsSync(packageDir)) {
      if (subpath.length === 0) return asDirectory(packageDir);
      const manifest = loadPackageJson(packageDir);
      if (manifest && Object.hasOwn(manifest, "exports")) {
        const target = exportsTarget(manifest.exports, subpath);
        return target ? asFile(localPath.join(packageDir, target)) : null;
      }
      const target = localPath.join(packageDir, ...subpath);
      return asFile(target) ?? asDirectory(target);
    }
  }
  return null;
}

function resolveFile(request, fromDir, root) {
  if (!isBare(request)) {
    const target = localPath.resolve(fromDir, request);
    return asFile(target) ?? asDirectory(target);
  }
  if (request.startsWith("node:")) return null;
  return resolvePackage(request, fromDir, root);
}

function loadFile(file, root) {
  const cached = fileModules.get(file);
  if (cached) return cached.exports;

  const module = { exports: {}, id: file, filename: file, loaded: false, children: [], paths: [] };
  // Publish first so a dependency cycle sees partial exports.
  fileModules.set(file, module);
  const dirname = localPath.dirname(file);
  try {
    if (file.endsWith(".json")) {
      module.exports = JSON.parse(localFs.readFileSync(file, "utf8"));
    } else {
      const code = localFs.readFileSync(file, "utf8");
      const factory = globalThis.__tinycastCompile(code, file);
      factory(module.exports, (request) => requireFrom(request, dirname, root), module, file, dirname);
    }
    module.loaded = true;
    return module.exports;
  } catch (error) {
    fileModules.delete(file);
    throw error;
  }
}

function requireFrom(request, fromDir, root) {
  const key = String(request);
  if (isBare(key)) {
    if (registry.has(key)) return registry.get(key);
    // Preserve deep imports into provided packages such as react-dom/client.
    const root = key.startsWith("@") ? key.split("/").slice(0, 2).join("/") : key.split("/")[0];
    if (registry.has(root)) return registry.get(root);
  }
  const file = resolveFile(key, fromDir, root);
  if (!file) notFound(key);
  return loadFile(file, root);
}

export function requireModule(name) {
  const key = String(name);
  if (registry.has(key)) return registry.get(key);
  const root = key.startsWith("@") ? key.split("/").slice(0, 2).join("/") : key.split("/")[0];
  if (registry.has(root)) return registry.get(root);
  notFound(key);
}

/// Bundles built with `createRequire` (e.g. apple-passwords lazily requires `@raycast/api`
/// through it) resolve against the same registry; the base path is irrelevant in one-file bundles.
const nodeRequire = (name) => requireModule(name);
nodeRequire.resolve = (name) => String(name);
nodeRequire.cache = {};
nodeModules["module"].createRequire = () => nodeRequire;

/// Evaluate one CJS bundle. `filename`/`dirname` matter: extensions resolve bundled assets relative
/// to `__dirname`, and `environment.assetsPath` points at the same directory.
export function evaluateCommonJS(code, filename, dirname) {
  const module = { exports: {}, id: filename, filename, loaded: false, children: [], paths: [] };
  const factory = globalThis.__tinycastCompile(code, filename);
  // The command's folder is the extension root; packages above it belong to the user, not to it.
  factory(module.exports, (request) => requireFrom(request, dirname, dirname), module, filename, dirname);
  module.loaded = true;
  return module.exports;
}
