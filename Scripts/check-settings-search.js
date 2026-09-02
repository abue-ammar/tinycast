#!/usr/bin/env node
// Every Settings search result must have somewhere to land.
//
// A `Form` cannot be asked what sections or rows it holds, so `SettingsSearchCatalog` is written by
// hand and its targets are matched to the panes textually. An entry with nothing to scroll to still
// compiles, reads fine, and fails only at runtime — as a result that navigates and then sits there.
//
// Usage: node Scripts/check-settings-search.js   (run by ./Scripts/lint.sh)
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const ANCHORS = "Tinycast/Features/Settings/SettingsAnchor.swift";
const CATALOG = "Tinycast/Features/Settings/SettingsSearchCatalog.swift";

function swiftSources(dir, found = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) swiftSources(full, found);
    else if (entry.name.endsWith(".swift")) found.push(full);
  }
  return found;
}

const anchorSource = fs.readFileSync(path.join(ROOT, ANCHORS), "utf8");
const catalog = fs.readFileSync(path.join(ROOT, CATALOG), "utf8");
const source = swiftSources(path.join(ROOT, "Tinycast"))
  .map((f) => fs.readFileSync(f, "utf8"))
  .join("\n");

const anchorTitles = new Map();
for (const m of anchorSource.matchAll(
  /static let (\w+) = Self\(\s*tab: \.\w+, title: "([^"]+)"\)/g
)) {
  anchorTitles.set(m[1], m[2]);
}

const problems = [];

// 1. Every anchor is claimed by a section.
for (const anchor of anchorTitles.keys()) {
  const claimed =
    source.includes(`SettingsSectionHeader(.${anchor})`) ||
    source.includes(`SettingsSectionHeader(anchor: .${anchor})`) ||
    source.includes(`settingsAnchor(.${anchor})`) ||
    source.includes(`anchor: .${anchor}`);
  if (!claimed) problems.push(`anchor .${anchor} — no Section declares it`);
}

// 2. Every row entry is marked on a row.
for (const m of catalog.matchAll(/\.init\(\s*\.(\w+),\s*"((?:[^"\\]|\\.)*)"/g)) {
  const [, anchor, title] = m;
  const quoted = title.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const marked =
    source.includes(`SettingsRowTitle(.${anchor}, "${title}")`) ||
    // A `SettingsRow` renders the pill from its own title.
    new RegExp(`SettingsRow\\(\\s*title: "${quoted}",[\\s\\S]*?anchor: \\.${anchor}`).test(source) ||
    // A feature pane's master switch, rendered by `FeatureSwitchSection`.
    new RegExp(`anchor: \\.${anchor},\\s*\\n\\s*enableTitle: "${quoted}"`).test(source) ||
    // A launcher category's switch, whose title `LauncherItemsSection` derives.
    title === `Enable ${anchorTitles.get(anchor) ?? ""}`;
  if (!marked) problems.push(`row “${title}” (.${anchor}) — no SettingsRowTitle marks it`);
}

if (problems.length > 0) {
  console.error("\n✗ Settings search targets with nothing to land on:");
  for (const p of problems) console.error(`  ${p}`);
  console.error("  Mark the row with SettingsRowTitle, or make the entry a `group:` one.");
  process.exit(1);
}
