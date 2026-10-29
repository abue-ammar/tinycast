// SharedArrayBuffer / Atomics fixtures. JavaScriptCore's `JSContext` does not expose
// `SharedArrayBuffer` (the embedding API gates it off even though the standalone `jsc`
// shell has it), so a package that allocates `new Int32Array(new SharedArrayBuffer(n))`
// at module load throws before a command can render. Node's `vm` context, unlike that
// `JSContext`, *does* carry both globals, so these fixtures delete them first to stand in
// for the real runtime and prove the shim in `node-shims.js` puts them back.
//
//   node sab-fixtures.mjs

import { createContext, runInContext } from "node:vm";
import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const runtimePath = [
  resolve("Tinycast/Resources/RaycastRuntime.generated.js"),
  resolve("../../Tinycast/Resources/RaycastRuntime.generated.js"),
  fileURLToPath(new URL("../../Tinycast/Resources/RaycastRuntime.generated.js", import.meta.url)),
].find(existsSync);

const runtime = readFileSync(runtimePath, "utf8");

export function runSharedArrayBufferFixtures(check) {
  // A context with neither global, the way `JSContext` hands them to an extension.
  const context = createContext({});
  runInContext("delete globalThis.SharedArrayBuffer; delete globalThis.Atomics;", context);
  check(
    "context starts without SharedArrayBuffer (mirrors JSContext)",
    runInContext("typeof SharedArrayBuffer", context) === "undefined",
  );

  context.__tinycastHost = { log() {} };
  context.__tinycastCompile = () => {};
  runInContext(runtime, context, { filename: "RaycastRuntime.generated.js" });

  check(
    "runtime defines SharedArrayBuffer",
    runInContext("typeof SharedArrayBuffer", context) === "function",
  );
  check("runtime defines Atomics", runInContext("typeof Atomics", context) === "object");

  // The exact construct that used to throw at module load.
  check(
    "new Int32Array(new SharedArrayBuffer(4)) works",
    runInContext("new Int32Array(new SharedArrayBuffer(4)).length", context) === 1,
  );

  // Atomic reads and writes are correct on one thread.
  check(
    "Atomics.store/load round-trips",
    runInContext(
      "(() => { const a = new Int32Array(new SharedArrayBuffer(4)); Atomics.store(a, 0, 7); return Atomics.load(a, 0); })()",
      context,
    ) === 7,
  );
  check(
    "Atomics.add returns the previous value",
    runInContext(
      "(() => { const a = new Int32Array(new SharedArrayBuffer(4)); Atomics.store(a, 0, 5); const prev = Atomics.add(a, 0, 3); return prev === 5 && Atomics.load(a, 0) === 8; })()",
      context,
    ) === true,
  );
  check(
    "Atomics.compareExchange swaps only on a match",
    runInContext(
      "(() => { const a = new Int32Array(new SharedArrayBuffer(4)); Atomics.store(a, 0, 1); const miss = Atomics.compareExchange(a, 0, 2, 9); const hit = Atomics.compareExchange(a, 0, 1, 9); return miss === 1 && hit === 1 && Atomics.load(a, 0) === 9; })()",
      context,
    ) === true,
  );
  // Nothing can notify on one thread, so wait never parks: it reports the state and returns.
  check(
    "Atomics.wait never blocks",
    runInContext(
      "(() => { const a = new Int32Array(new SharedArrayBuffer(4)); return Atomics.wait(a, 0, 1) === 'not-equal' && Atomics.wait(a, 0, 0) === 'timed-out'; })()",
      context,
    ) === true,
  );

  // A native global, when the embedder does expose one, must win over the shim.
  const native = createContext({});
  native.__tinycastHost = { log() {} };
  native.__tinycastCompile = () => {};
  const sentinel = runInContext("SharedArrayBuffer.__nativeSentinel = 'native'; SharedArrayBuffer", native);
  runInContext(runtime, native, { filename: "RaycastRuntime.generated.js" });
  check(
    "a native SharedArrayBuffer is left untouched",
    runInContext("SharedArrayBuffer.__nativeSentinel", native) === "native" && sentinel !== undefined,
  );
}

if (import.meta.url === `file://${process.argv[1]}`) {
  let failures = 0;
  const check = (label, condition, extra = "") => {
    if (condition) {
      console.log(`  \u2713 ${label}`);
    } else {
      failures++;
      console.log(`  \u2717 ${label}${extra ? ` \u2014 ${extra}` : ""}`);
    }
  };
  console.log("\u25b6 SharedArrayBuffer / Atomics");
  runSharedArrayBufferFixtures(check);
  console.log(failures === 0 ? "\nAll SharedArrayBuffer fixtures passed." : `\n${failures} check(s) failed.`);
  process.exit(failures === 0 ? 0 : 1);
}
