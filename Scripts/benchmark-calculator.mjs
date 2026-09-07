#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readdirSync, readFileSync, writeFileSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
function option(name, fallback) {
  const index = args.indexOf(name);
  return index < 0 ? fallback : args[index + 1];
}
const output = path.resolve(option("--output", path.join(root, "build/calculator-comparison")));
const scratch = option("--scratch", null) ?? mkdtempSync(path.join(tmpdir(), "tinycast-calculator-"));
const runs = Number(option("--runs", "9"));
const iterations = Number(option("--iterations", "2000"));
const architecture = process.arch === "x64" ? "x86_64" : process.arch;
if (!Number.isInteger(runs) || runs < 3 || !Number.isInteger(iterations) || iterations < 1) {
  throw new Error("Use at least three runs and a positive iteration count.");
}
mkdirSync(output, { recursive: true });
mkdirSync(scratch, { recursive: true });
function command(binary, arguments_, options = {}) {
  return execFileSync(binary, arguments_, { cwd: root, maxBuffer: 256 * 1024 * 1024, ...options });
}
function files(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const name = path.join(directory, entry.name);
    return entry.isDirectory() ? files(name) : [name];
  });
}
function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  return (sorted[Math.floor((sorted.length - 1) / 2)] + sorted[Math.floor(sorted.length / 2)]) / 2;
}
const versions = [
  { name: "main", ref: option("--main", "main") },
  { name: "advanced", ref: option("--advanced", "feat/calculator-advanced") },
  { name: "current", source: root }
];
for (const version of versions) {
  version.commit = command("git", ["rev-parse", version.ref ?? "HEAD"]).toString().trim();
  if (!version.source) {
    version.source = path.join(scratch, `${version.name}-${version.commit.slice(0, 12)}`);
    mkdirSync(version.source, { recursive: true });
    command("tar", ["-xf", "-", "-C", version.source], { input: command("git", ["archive", version.commit]) });
  }
  version.binary = path.join(scratch, `${version.name}-benchmark`);
  const model = files(path.join(version.source, "Tinycast/Features/Calculator/Model")).filter(f => f.endsWith(".swift"));
  const compile = ["-O", "-whole-module-optimization", "-swift-version", "6", "-module-cache-path",
    path.join(scratch, "module-cache"), "-target", `${architecture}-apple-macosx26.0`, ...model,
    path.join(root, "Tests/calc-performance.swift"), "-o", version.binary];
  console.log(`Compiling ${version.name} (${version.commit.slice(0, 7)})`);
  command("swiftc", compile);
  command("strip", ["-S", "-x", version.binary]);
  version.probeBytes = statSync(version.binary).size;
  version.modelSourceBytes = model.reduce((sum, file) => sum + statSync(file).size, 0);
  if (args.includes("--build")) {
    console.log(`Building ${version.name} Release`);
    const log = path.join(output, `${version.name}-build.log`);
    try {
      writeFileSync(log, command("xcodebuild", ["build", "-project", "Tinycast.xcodeproj", "-scheme", "Tinycast",
        "-configuration", "Release", "-derivedDataPath", path.join(scratch, `${version.name}-build`),
        "CODE_SIGNING_ALLOWED=NO", `ARCHS=${architecture}`, "ONLY_ACTIVE_ARCH=YES", "LD_GENERATE_MAP_FILE=YES"],
      { cwd: version.source, stdio: ["ignore", "pipe", "pipe"] }));
    } catch (error) {
      writeFileSync(log, Buffer.concat([error.stdout ?? Buffer.alloc(0), error.stderr ?? Buffer.alloc(0)]));
      throw new Error(`Release build failed; see ${log}`);
    }
    const build = path.join(scratch, `${version.name}-build/Build`);
    const app = path.join(build, "Products/Release/Tinycast.app");
    version.executableBytes = statSync(path.join(app, "Contents/MacOS/Tinycast")).size;
    version.bundleBytes = files(app).reduce((sum, file) => sum + statSync(file).size, 0);
    const names = new Set(files(path.join(version.source, "Tinycast/Features/Calculator"))
      .filter(f => f.endsWith(".swift")).map(f => path.basename(f, ".swift")));
    const map = readFileSync(path.join(build,
      "Intermediates.noindex/Tinycast.build/Release/Tinycast.build/Tinycast-LinkMap-normal-" + architecture + ".txt"), "utf8");
    const objects = new Map();
    version.calculatorSymbolBytes = 0;
    for (const line of map.split("# Dead Stripped Symbols:")[0].split("\n")) {
      const object = line.match(/^\[\s*(\d+)\] .*\/([^/]+)\.o$/);
      if (object) objects.set(object[1], object[2]);
      const symbol = line.match(/^0x[\dA-F]+\s+0x([\dA-F]+)\s+\[\s*(\d+)\]/);
      if (symbol && names.has(objects.get(symbol[2]))) version.calculatorSymbolBytes += parseInt(symbol[1], 16);
    }
  }
}

console.log("Benchmarking sequentially; no builds run during measurement.");
const samples = [];
for (let run = 0; run < runs; run++) {
  for (let index = 0; index < versions.length; index++) {
    const version = versions[(run + index) % versions.length];
    samples.push({ run, version: version.name,
      rows: JSON.parse(command(version.binary, [String(iterations)]).toString()) });
  }
}
const groups = samples[0].rows.map(row => row.group);
const timings = groups.map(group => {
  const row = { group };
  for (const version of versions) {
    const matches = samples.filter(sample => sample.version === version.name)
      .map(sample => sample.rows.find(item => item.group === group));
    row[version.name] = { medianUS: median(matches.map(item => item.us)), minUS: Math.min(...matches.map(item => item.us)),
      maxUS: Math.max(...matches.map(item => item.us)), outputs: matches[0].outputs };
  }
  row.matchesAdvanced = JSON.stringify(row.current.outputs) === JSON.stringify(row.advanced.outputs);
  row.matchesMain = JSON.stringify(row.current.outputs) === JSON.stringify(row.main.outputs);
  row.matchesMainValues = JSON.stringify(row.current.outputs.map(fields => fields.slice(3)))
    === JSON.stringify(row.main.outputs.map(fields => fields.slice(3)));
  if (!row.matchesAdvanced) throw new Error(`Advanced output regression in ${group}`);
  return row;
});
const cold = [];
for (const query of ["safari", "2+2", "10kg + 500g to lb", "time in Tokyo"]) {
  const row = { query };
  for (const version of versions) {
    row[version.name] = median(Array.from({ length: runs }, () =>
      JSON.parse(command(version.binary, ["--cold", query]).toString()).us));
  }
  cold.push(row);
}
const results = { machine: command("sysctl", ["-n", "machdep.cpu.brand_string"]).toString().trim(),
  os: command("sw_vers", ["-productVersion"]).toString().trim(),
  compiler: command("swiftc", ["--version"]).toString().trim(), flags: "-O -whole-module-optimization -swift-version 6",
  runs, iterations, versions, timings, cold, samples };
writeFileSync(path.join(output, "results.json"), JSON.stringify(results, null, 2) + "\n");
const lines = ["# Calculator size and performance", "", `${results.machine}; macOS ${results.os}.`, "",
  `Swift 6, ${architecture}, -O, whole-module optimization; ${runs} rotating sequential runs, ${iterations} iterations per query.`,
  "Fixed clock, calendar, locale, region and exchange rates. Full engine evaluation includes formatting; CalcMemo is bypassed.", "",
  "| Metric (bytes) | Main | Old advanced | Current |", "| --- | ---: | ---: | ---: |"];
for (const [label, key] of [["Release bundle", "bundleBytes"], ["Release executable", "executableBytes"],
  ["Calculator linked symbols", "calculatorSymbolBytes"], ["Stripped engine probe", "probeBytes"],
  ["Model source", "modelSourceBytes"]]) {
  if (versions.every(v => v[key] !== undefined)) lines.push(`| ${label} | ${versions.map(v => v[key].toLocaleString("en-US")).join(" | ")} |`);
}
lines.push("", "Calculator symbols include Model, Service and UI objects; shared compiler helpers and alignment are not fully attributable.",
  "The standalone probe includes its benchmark driver and is not the calculator's exact contribution to the app.", "",
  "| Query group (µs/query) | Main | Old advanced | Current | Change vs advanced |", "| --- | ---: | ---: | ---: | ---: |");
for (const row of timings) {
  const values = versions.map(v => row[v.name].medianUS.toFixed(3));
  if (!row.matchesMainValues) values[0] += "*";
  else if (!row.matchesMain) values[0] += "†";
  lines.push(`| ${row.group} | ${values.join(" | ")} | ${((row.current.medianUS / row.advanced.medianUS - 1) * 100).toFixed(1)}% |`);
}
lines.push("", "*Main produces different or unsupported answers in this group; its timing is not a like-for-like speed comparison.",
  "†Main calculates the same values; expression echo formatting differs.",
  "Current and advanced benchmark outputs match, including display, copy text, errors and badges.", "",
  "| First evaluation in fresh process (µs) | Main | Old advanced | Current |", "| --- | ---: | ---: | ---: |");
for (const row of cold) lines.push(`| ${row.query} | ${versions.map(v => row[v.name].toFixed(1)).join(" | ")} |`);
lines.push("", "Cold timings exclude process launch and fixture setup; each sample starts a fresh process.", "",
  ...versions.map(v => `- ${v.name}: ${v.commit}${v.name === "current" ? " plus working-tree changes" : ""}`), "");
writeFileSync(path.join(output, "report.md"), lines.join("\n"));
console.log(lines.join("\n"));
