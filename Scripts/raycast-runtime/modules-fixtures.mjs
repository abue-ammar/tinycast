import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { bootConfig, createHarness } from "./test.mjs";

export async function runModuleFixtures(check) {
  const root = mkdtempSync(join(tmpdir(), "tinycast-modules-"));
  const extension = join(root, "extension");
  const write = (path, content) => {
    const file = join(extension, path);
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, typeof content === "string" ? content : JSON.stringify(content));
  };
  const command = async (label, body, expected) => {
    const harness = createHarness();
    harness.boot(bootConfig());
    try {
      harness.start("modules", `module.exports.default = () => { ${body} };`,
        join(extension, "cmd.js"), extension, "no-view", {});
      await new Promise((resolve) => setTimeout(resolve, 20));
      const result = harness.call("globalThis.result");
      check(label, harness.state.failures.length === 0 && JSON.stringify(result) === JSON.stringify(expected),
        harness.state.failures.join(" | ") || JSON.stringify(result));
    } finally {
      harness.stop("modules");
    }
  };
  try {
    write("node_modules/subpkg/package.json", { exports: { ".": "./index.js", "./deep": "./lib/deep.js" } });
    write("node_modules/subpkg/index.js", 'module.exports = require("subpkg/deep");');
    write("node_modules/subpkg/lib/deep.js", 'module.exports = require("./data.json").value + 1;');
    write("node_modules/subpkg/lib/data.json", { value: 41 });
    await command("package root, exports subpath and relative JSON", 'globalThis.result = require("subpkg");', 42);

    write("local/index.js", "module.exports = 7;");
    await command("relative directory resolves index.js", 'globalThis.result = require("./local");', 7);
    write("node_modules/main-dir/package.json", { main: "./lib" });
    write("node_modules/main-dir/lib/index.js", "module.exports = 8;");
    await command("package main directory resolves index.js", 'globalThis.result = require("main-dir");', 8);
    write("node_modules/@fixture/scoped/index.cjs", "module.exports = 9;");
    write("node_modules/@fixture/scoped/package.json", { main: "index.cjs" });
    await command("scoped package resolves CommonJS main", 'globalThis.result = require("@fixture/scoped");', 9);

    write("node_modules/outer/index.js", 'module.exports = require("inner");');
    write("node_modules/outer/node_modules/inner/index.js", "module.exports = 10;");
    write("node_modules/inner/index.js", "module.exports = 99;");
    await command("nested dependency wins over parent dependency", 'globalThis.result = require("outer");', 10);

    write("node_modules/conditional/package.json", {
      exports: { node: { require: "./cjs.js", default: "./other.js" }, default: "./other.js" },
    });
    write("node_modules/conditional/cjs.js", "module.exports = 11;");
    write("node_modules/conditional/other.js", "module.exports = 99;");
    await command("nested require condition selects CommonJS", 'globalThis.result = require("conditional");', 11);

    write("node_modules/pattern/package.json", {
      exports: { "./*": "./general/*.js", "./special/*": "./specific/*.js" },
    });
    write("node_modules/pattern/general/special/value.js", "module.exports = 99;");
    write("node_modules/pattern/specific/value.js", "module.exports = 12;");
    await command("most specific exports pattern wins", 'globalThis.result = require("pattern/special/value");', 12);

    write("node_modules/private/package.json", { exports: { ".": "./index.js", "./hidden": null } });
    write("node_modules/private/index.js", "module.exports = 1;");
    write("node_modules/private/hidden.js", "module.exports = 99;");
    await command("exports map does not expose private files", `
      try { require("private/hidden"); globalThis.result = false; }
      catch { globalThis.result = true; }`, true);

    write("node_modules/up/package.json", { main: "main.js" });
    write("node_modules/up/main.js", 'module.exports = "root";');
    write("node_modules/up/lib/index.js", 'module.exports = "lib";');
    write("node_modules/up/lib/child.js", 'module.exports = require("..");');
    await command("require('..') resolves the parent directory", 'globalThis.result = require("up/lib/child");', "root");
    write("node_modules/dot/index.js", 'module.exports = "index";');
    write("node_modules/dot/other.js", 'module.exports = require(".");');
    await command("require('.') resolves the current directory", 'globalThis.result = require("dot/other");', "index");

    write("../node_modules/outside/index.js", "module.exports = 99;");
    await command("packages above the extension root are not resolved", `
      try { require("outside"); globalThis.result = false; }
      catch { globalThis.result = true; }`, true);

    write("node_modules/cycle/index.js", 'exports.first = true; exports.peer = require("./peer").first;');
    write("node_modules/cycle/peer.js", 'exports.first = require("./index").first;');
    await command("cycles see partial exports", 'globalThis.result = require("cycle");', { first: true, peer: true });
    write("node_modules/once/index.js", "globalThis.loads = (globalThis.loads || 0) + 1; module.exports = { loads: globalThis.loads };");
    await command("repeated require shares one module instance", `
      const first = require("once"); const second = require("once");
      globalThis.result = [first === second, second.loads];`, [true, 1]);
    write("node_modules/broken/index.js", 'throw new Error("fixture load failure");');
    await command("failed loads are retried rather than cached", `
      const errors = []; for (let i = 0; i < 2; i++) {
        try { require("broken"); } catch (error) { errors.push(error.message); }
      } globalThis.result = errors;`, ["fixture load failure", "fixture load failure"]);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  let failures = 0;
  await runModuleFixtures((label, condition, detail) => {
    console.log(`${condition ? "✓" : "✗"} ${label}${condition ? "" : ` — ${detail}`}`);
    if (!condition) failures++;
  });
  process.exitCode = failures ? 1 : 0;
}
