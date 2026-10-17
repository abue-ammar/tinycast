#!/usr/bin/env node
// Usage: make-spec.mjs <dumped-spec.json> <out-dir> <project-name> [feature ...]

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const [specPath, outDir, projectName, ...features] = process.argv.slice(2);
if (!specPath || !outDir || !projectName) {
  console.error("usage: make-spec.mjs <dumped-spec.json> <out-dir> <project-name> [feature ...]");
  process.exit(2);
}

const catalog = JSON.parse(readFileSync(join(root, "Variants/features.json"), "utf8"));
for (const name of features) {
  if (!catalog[name]) fail(`unknown feature "${name}" (known: ${Object.keys(catalog).join(", ")})`);
}

const spec = JSON.parse(readFileSync(specPath, "utf8"));
spec.name = projectName;
const app = spec.targets?.Tinycast ?? fail("spec has no Tinycast target");
const appSourceIndex = app.sources.findIndex((s) => (typeof s === "string" ? s : s.path) === "Tinycast");
if (appSourceIndex < 0) fail('Tinycast target has no "Tinycast" source folder');
if (typeof app.sources[appSourceIndex] === "string") {
  app.sources[appSourceIndex] = { path: app.sources[appSourceIndex] };
}
const appSource = app.sources[appSourceIndex];
appSource.excludes ??= [];

if (features.length) app.sources.push({ path: "Variants/Stubs/Common" });

const conditions = [];
const plistEdits = { deleteKeys: [], removeURLSchemes: [] };
const entitlementDeletes = [];

for (const name of features) {
  const feature = catalog[name];
  const keep = feature.keep.map((p) => resolve(root, p));
  for (const path of feature.exclude) {
    const absolute = resolve(root, path);
    if (!existsSync(absolute)) fail(`${name}: excluded path ${path} does not exist`);
    // An exclude inside a kept folder still applies.
    const insideKeep = keep.some((k) => absolute.startsWith(k + "/"));
    for (const entry of insideKeep ? [absolute] : exclusions(absolute, keep)) {
      appSource.excludes.push(relative(join(root, "Tinycast"), entry));
    }
  }

  const stubs = resolve(root, feature.stubs);
  if (!existsSync(stubs)) fail(`${name}: stand-in folder ${feature.stubs} does not exist`);
  app.sources.push({ path: feature.stubs });

  for (const target of feature.dropTargets) delete spec.targets[target];
  app.dependencies = (app.dependencies ?? []).filter(
    (dep) => !feature.dropDependencies.includes(dep.target ?? dep.framework),
  );

  conditions.push(feature.condition);
  plistEdits.deleteKeys.push(...feature.infoPlist.deleteKeys);
  plistEdits.removeURLSchemes.push(...feature.infoPlist.removeURLSchemes);
  entitlementDeletes.push(...feature.entitlements.deleteKeys);
}

for (const [name, target] of Object.entries(spec.targets)) {
  for (const dep of target.dependencies ?? []) {
    if (dep.target && !spec.targets[dep.target]) fail(`${name} still depends on dropped ${dep.target}`);
  }
}

mkdirSync(outDir, { recursive: true });
app.settings ??= {};
app.settings.base ??= {};
const base = app.settings.base;

if (conditions.length) {
  base.SWIFT_ACTIVE_COMPILATION_CONDITIONS = ["$(inherited)", ...conditions].join(" ");
}

if (plistEdits.deleteKeys.length || plistEdits.removeURLSchemes.length) {
  const source = resolve(root, base.INFOPLIST_FILE ?? fail("Tinycast target has no INFOPLIST_FILE"));
  const plist = readPlist(source);
  for (const key of plistEdits.deleteKeys) delete plist[key];
  plist.CFBundleURLTypes = (plist.CFBundleURLTypes ?? [])
    .map((type) => ({
      ...type,
      CFBundleURLSchemes: (type.CFBundleURLSchemes ?? []).filter(
        (scheme) => !plistEdits.removeURLSchemes.includes(scheme),
      ),
    }))
    .filter((type) => type.CFBundleURLSchemes.length);
  if (!plist.CFBundleURLTypes.length) delete plist.CFBundleURLTypes;
  const derived = resolve(outDir, "Info.plist");
  writePlist(derived, plist);
  // A plist that is no longer INFOPLIST_FILE would otherwise be copied in as a resource.
  appSource.excludes.push(relative(join(root, "Tinycast"), source));
  base.INFOPLIST_FILE = derived;
}

if (entitlementDeletes.length) {
  const source = resolve(root, base.CODE_SIGN_ENTITLEMENTS ?? fail("no CODE_SIGN_ENTITLEMENTS"));
  const entitlements = readPlist(source);
  for (const key of entitlementDeletes) delete entitlements[key];
  const derived = resolve(outDir, "Tinycast.entitlements");
  writePlist(derived, entitlements);
  base.CODE_SIGN_ENTITLEMENTS = derived;
}

writeFileSync(join(outDir, "project.json"), JSON.stringify(spec, null, 2));

function exclusions(path, keep) {
  if (keep.some((k) => k === path || path.startsWith(k + "/"))) return [];
  if (!statSync(path).isDirectory() || !keep.some((k) => k.startsWith(path + "/"))) return [path];
  return readdirSync(path)
    .filter((child) => child !== ".DS_Store")
    .flatMap((child) => exclusions(join(path, child), keep));
}

function readPlist(path) {
  return JSON.parse(execFileSync("plutil", ["-convert", "json", "-o", "-", path], { encoding: "utf8" }));
}

function writePlist(path, value) {
  execFileSync("plutil", ["-convert", "xml1", "-o", path, "-"], { input: JSON.stringify(value) });
}

function fail(message) {
  console.error(`make-spec: ${message}`);
  process.exit(1);
}
