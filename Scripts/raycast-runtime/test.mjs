// Drives the built runtime against a real extension bundle inside a bare `vm` context — the closest
// thing to JavaScriptCore that Node offers (no console, no timers, no URL, no Node globals).
//
//   node test.mjs                                  # the built-in fixtures
//   node test.mjs <extension-dir> <command-name>    # any prebuilt Raycast extension
//
// Prints the render tree the Swift side would receive.

import { createContext, runInContext } from "node:vm";
import { readFileSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import { createHash, randomUUID, randomBytes, createHmac } from "node:crypto";
import { homedir, tmpdir } from "node:os";
import * as fs from "node:fs";
import * as zlib from "node:zlib";

const runtimePath = [
  resolve("Tinycast/Resources/RaycastRuntime.generated.js"),
  resolve("../../Tinycast/Resources/RaycastRuntime.generated.js"),
  fileURLToPath(new URL("../../Tinycast/Resources/RaycastRuntime.generated.js", import.meta.url)),
].find(existsSync);

const runtime = readFileSync(runtimePath, "utf8");

export function createHarness({ onRender, onFail, verbose = false, stubs = {} } = {}) {
  const context = createContext({});
  const timers = new Map();
  const state = { trees: [], failures: [], logs: [], finished: false, hostCalls: [] };

  const host = {
    log(level, message) {
      state.logs.push(`[${level}] ${message}`);
      if (verbose) console.log(`  [${level}] ${message}`);
    },
    render(sessionId, json) {
      const tree = JSON.parse(json);
      state.trees.push(tree);
      onRender?.(tree);
    },
    failed(sessionId, message) {
      state.failures.push(message);
      onFail?.(message);
    },
    navigationDepthChanged(sessionId, depth) {
      state.navigationDepth = Number(depth);
    },
    finished() {
      state.finished = true;
    },
    fieldCommand() {},
    startTimer(id, ms, repeats) {
      const fire = () => runInContext(`__tinycast.fireTimer(${JSON.stringify(id)})`, context);
      timers.set(id, repeats ? setInterval(fire, Math.max(ms, 1)) : setTimeout(fire, ms));
    },
    clearTimer(id) {
      const handle = timers.get(id);
      if (handle) {
        clearTimeout(handle);
        clearInterval(handle);
        timers.delete(id);
      }
    },
    invoke(callId, api, method, argsJson) {
      const name = `${api}.${method}`;
      state.hostCalls.push(name);
      const args = JSON.parse(argsJson);
      Promise.resolve()
        .then(() => (stubs[name] ? stubs[name](args) : stubHostCall(api, method, args)))
        .then(
          (value) => settle(callId, true, value),
          (error) => settle(callId, false, String(error?.message ?? error)),
        );
    },
    invokeSync(api, method, argsJson) {
      try {
        return JSON.stringify({ ok: true, value: syncHostCall(api, method, JSON.parse(argsJson)) });
      } catch (error) {
        return JSON.stringify({ ok: false, error: String(error?.message ?? error), code: error?.code });
      }
    },
  };

  function settle(callId, ok, value) {
    runInContext(
      `__tinycast.settle(${JSON.stringify(String(callId))}, ${ok}, ${JSON.stringify(value === undefined ? "" : JSON.stringify(value))})`,
      context,
    );
  }

  context.__tinycastHost = host;
  // Mirrors what Swift installs: compile the extension's CJS body in global scope.
  context.__tinycastCompile = (code, filename) =>
    runInContext(
      `(function (exports, require, module, __filename, __dirname) {\n${code}\n})`,
      context,
      { filename },
    );

  runInContext(runtime, context, { filename: "RaycastRuntime.generated.js" });

  return {
    context,
    state,
    call(expression) {
      return runInContext(expression, context);
    },
    boot(config) {
      return runInContext(`__tinycast.boot(${JSON.stringify(JSON.stringify(config))})`, context);
    },
    start(sessionId, code, filename, dirname, mode, ctx) {
      return runInContext(
        `__tinycast.start(${JSON.stringify(sessionId)}, ${JSON.stringify(code)}, ${JSON.stringify(filename)}, ${JSON.stringify(dirname)}, ${JSON.stringify(mode)}, ${JSON.stringify(JSON.stringify(ctx))})`,
        context,
      );
    },
    dispatch(sessionId, handlerId, args = []) {
      return runInContext(
        `__tinycast.dispatch(${JSON.stringify(sessionId)}, ${JSON.stringify(handlerId)}, ${JSON.stringify(JSON.stringify(args))})`,
        context,
      );
    },
    stop(sessionId) {
      runInContext(`__tinycast.stop(${JSON.stringify(sessionId)})`, context);
      for (const id of [...timers.keys()]) host.clearTimer(id);
    },
  };
}

function syncHostCall(api, method, args) {
  switch (`${api}.${method}`) {
    case "fs.readFile":
      return fs.readFileSync(args[0]).toString("base64");
    case "fs.writeFile":
      fs[args[2] ? "appendFileSync" : "writeFileSync"](args[0], Buffer.from(args[1], "base64"));
      return null;
    case "fs.exists":
      return fs.existsSync(args[0]);
    case "fs.stat": {
      const stat = args[1] ? fs.lstatSync(args[0]) : fs.statSync(args[0]);
      return {
        size: stat.size,
        mode: stat.mode,
        mtimeMs: stat.mtimeMs,
        atimeMs: stat.atimeMs,
        ctimeMs: stat.ctimeMs,
        birthtimeMs: stat.birthtimeMs,
        _isFile: stat.isFile(),
        _isDirectory: stat.isDirectory(),
        _isSymbolicLink: stat.isSymbolicLink(),
      };
    }
    case "fs.readdir":
      return fs.readdirSync(args[0], { withFileTypes: true }).map((entry) => ({
        name: entry.name,
        parentPath: args[0],
        _isFile: entry.isFile(),
        _isDirectory: entry.isDirectory(),
        _isSymbolicLink: entry.isSymbolicLink(),
      }));
    case "fs.mkdir":
      return fs.mkdirSync(args[0], { recursive: args[1] }) ?? null;
    case "fs.realpath":
      return fs.realpathSync(args[0]);
    case "fs.mkdtemp":
      return fs.mkdtempSync(args[0]);
    case "fs.remove":
      fs.rmSync(args[0], { recursive: args[1], force: args[2] });
      return null;
    case "fs.rename":
      fs.renameSync(args[0], args[1]);
      return null;
    case "fs.copyFile":
      fs.copyFileSync(args[0], args[1]);
      return null;
    case "crypto.uuid":
      return randomUUID();
    case "crypto.random":
      return randomBytes(args[0]).toString("base64");
    case "crypto.hash":
      return createHash(args[0]).update(Buffer.from(args[1], "base64")).digest("base64");
    case "crypto.hmac":
      return createHmac(args[0], Buffer.from(args[2], "base64"))
        .update(Buffer.from(args[1], "base64"))
        .digest("base64");
    case "proc.run": {
      const spec = args[0];
      try {
        const stdout = spec.shell
          ? execFileSync("/bin/sh", ["-c", spec.command], { cwd: spec.cwd })
          : execFileSync(spec.command, spec.args, { cwd: spec.cwd });
        return { stdout: stdout.toString("base64"), stderr: "", status: 0 };
      } catch (error) {
        return {
          stdout: Buffer.from(error.stdout ?? "").toString("base64"),
          stderr: Buffer.from(error.stderr ?? "").toString("base64"),
          status: error.status ?? 1,
        };
      }
    }
    case "zlib.gzip":
      return zlib.gzipSync(Buffer.from(args[0], "base64")).toString("base64");
    case "zlib.gunzip":
      return zlib.gunzipSync(Buffer.from(args[0], "base64")).toString("base64");
    case "zlib.deflate":
      return zlib.deflateSync(Buffer.from(args[0], "base64")).toString("base64");
    case "zlib.inflate":
      return zlib.inflateSync(Buffer.from(args[0], "base64")).toString("base64");
    case "zlib.deflateRaw":
      return zlib.deflateRawSync(Buffer.from(args[0], "base64")).toString("base64");
    case "zlib.inflateRaw":
      return zlib.inflateRawSync(Buffer.from(args[0], "base64")).toString("base64");
    default:
      throw new Error(`harness: no sync stub for ${api}.${method}`);
  }
}

const oauthTokens = new Map();

async function stubHostCall(api, method, args) {
  switch (`${api}.${method}`) {
    case "storage.get":
      return null;
    case "storage.all":
      return {};
    case "clipboard.readText":
      return "";
    case "feedback.showToast":
      return "toast-1";
    case "system.frontmostApplication":
      return { name: "Finder", path: "/System/Library/CoreServices/Finder.app", bundleId: "com.apple.finder" };
    case "system.applications":
      return [];
    case "fetch.request": {
      const spec = args[0];
      const response = await fetch(spec.url, {
        method: spec.method,
        headers: spec.headers,
        body: spec.bodyBase64 ? Buffer.from(spec.bodyBase64, "base64") : undefined,
      });
      const body = Buffer.from(await response.arrayBuffer());
      return {
        status: response.status,
        statusText: response.statusText,
        headers: Object.fromEntries(response.headers),
        url: response.url,
        bodyBase64: body.toString("base64"),
      };
    }
    case "proc.run":
      return syncHostCall(api, method, args);
    // Positional arguments throughout, matching `src/api/oauth.js`.
    case "oauth.authorize":
      return { authorizationCode: "auth-code-12345", state: args[1] ?? "" };
    case "oauth.getTokens":
      return oauthTokens.get(args[0]) ?? null;
    case "oauth.setTokens":
      oauthTokens.set(args[0], args[1]);
      return null;
    case "oauth.removeTokens":
      oauthTokens.delete(args[0]);
      return null;
    default:
      if (["window", "feedback", "cache", "storage", "clipboard", "system"].includes(api)) return null;
      throw new Error(`harness: no async stub for ${api}.${method}`);
  }
}

export function bootConfig(overrides = {}) {
  return {
    node: {
      arch: "arm64",
      env: { HOME: homedir(), PATH: process.env.PATH },
      cwd: homedir(),
      homedir: homedir(),
      tmpdir: tmpdir(),
      username: "tester",
      cpus: 8,
    },
    environment: {
      extensionName: "fixture",
      commandName: "fixture",
      commandMode: "view",
      assetsPath: "/tmp",
      supportPath: "/tmp",
      isDevelopment: false,
      raycastVersion: "2.0.3",
      textSize: "medium",
      appearance: "dark",
      launchType: "userInitiated",
    },
    preferences: {},
    caches: {},
    ...overrides,
  };
}

/// Compact one-line-per-node dump so a tree diff is readable in a terminal.
export function describeTree(tree, indent = "") {
  const lines = [];
  const walk = (node, depth) => {
    if (node.type === "#text") {
      lines.push(`${"  ".repeat(depth)}"${node.text}"`);
      return;
    }
    const props = Object.entries(node.props ?? {})
      .filter(([, value]) => value !== undefined)
      .map(([key, value]) => `${key}=${summarize(value)}`)
      .join(" ");
    lines.push(`${"  ".repeat(depth)}<${node.type}${props ? " " + props : ""}>`);
    for (const child of node.children ?? []) walk(child, depth + 1);
  };
  for (const child of tree.children ?? []) walk(child, 0);
  return lines.map((line) => indent + line).join("\n");
}

function summarize(value) {
  if (value && typeof value === "object" && value.$fn) return `fn(${value.$fn})`;
  if (Array.isArray(value)) return `[${value.length}]`;
  if (value && typeof value === "object") {
    if (value.$date) return value.$date;
    if (value.type) return `<${value.type}>`;
    return "{…}";
  }
  return JSON.stringify(value);
}

// ─── CLI ────────────────────────────────────────────────────────────

if (import.meta.url === `file://${process.argv[1]}`) {
  const [dir, command] = process.argv.slice(2);
  if (dir) {
    await runExtension(dir, command);
  } else {
    await runFixtures();
  }
}

/// Mirrors the Swift-side resolution: a manifest default can be platform-keyed
/// (`{"macOS": "…", "Windows": "…"}`), and a checkbox with no default is false, not "".
export function preferenceDefault(pref) {
  const raw = pref.default;
  if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw.macOS ?? "";
  if (raw !== undefined) return raw;
  return pref.type === "checkbox" ? false : "";
}

async function runExtension(dir, commandName) {
  const manifest = JSON.parse(readFileSync(join(dir, "package.json"), "utf8"));
  const commands = manifest.commands ?? [];
  const target = commandName ? commands.find((c) => c.name === commandName) : commands[0];
  if (!target) throw new Error(`no command ${commandName ?? ""} in ${manifest.name}`);
  const file = join(dir, `${target.name}.js`);
  if (!existsSync(file)) throw new Error(`missing built bundle ${file}`);

  console.log(`▶ ${manifest.title} — ${target.title} (${target.mode})`);
  const harness = createHarness({ verbose: true });
  harness.boot(
    bootConfig({
      environment: {
        ...bootConfig().environment,
        extensionName: manifest.name,
        commandName: target.name,
        commandMode: target.mode,
        assetsPath: join(dir, "assets"),
      },
      preferences: {
        ...Object.fromEntries(
          [...(manifest.preferences ?? []), ...(target.preferences ?? [])].map((pref) => [
            pref.name,
            preferenceDefault(pref),
          ]),
        ),
        // `EXT_TEST_PREFS={"version":"v8"}` stands in for what the user set in Settings — plenty of
        // extensions branch on a preference that has no manifest default. Same knob as ext-test.
        ...JSON.parse(process.env.EXT_TEST_PREFS ?? "{}"),
      },
    }),
  );
  harness.start("s1", readFileSync(file, "utf8"), file, dir, target.mode === "view" ? "view" : "no-view", {});

  await new Promise((resolve) => setTimeout(resolve, 1500));
  if (harness.state.failures.length) {
    console.log("\n✗ failures:");
    for (const failure of harness.state.failures) console.log(failure);
  }
  const last = harness.state.trees.at(-1);
  console.log(`\n${harness.state.trees.length} render(s), host calls: ${[...new Set(harness.state.hostCalls)].join(", ") || "none"}`);
  if (last) console.log("\n" + describeTree(last));
  harness.stop("s1");
  process.exit(harness.state.failures.length ? 1 : 0);
}

async function runFixtures() {
  const { runFixtures: run } = await import("./fixtures.mjs");
  await run();
}
