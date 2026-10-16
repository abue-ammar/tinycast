#!/usr/bin/env node
// Every string Tinycast ships is translated into every language it ships.
//
// A missing translation still builds and runs: the string just appears in English, in the middle
// of an otherwise translated window. A translation whose format specifiers differ from the source
// is worse — `String(format:)` reads the wrong argument, or crashes.
//
// Usage: node Scripts/check-localizations.js   (run by ./Scripts/lint.sh)
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const CATALOGS = ["Tinycast/Resources/Localizable.xcstrings", "Tinycast/Resources/InfoPlist.xcstrings"];

// CLDR cardinal categories each language must spell out.
const LANGUAGES = {
  de: ["one", "other"],
  es: ["one", "many", "other"],
  fr: ["one", "many", "other"],
  ja: ["other"],
  ko: ["other"],
  pt: ["one", "many", "other"],
  ru: ["one", "few", "many", "other"],
  "zh-Hans": ["other"],
};

const SPECIFIER = /%(?:(\d+)\$)?[-+ 0#]*\d*(?:\.\d+)?(hh|h|ll|l|q|L|z|t|j)?([@dDiuUxXoOfFeEgGcCsSpaA])/g;

/** Argument types by position, so a translation may reorder `%1$@ %2$lld`. */
function specifiers(text, substitutions = {}) {
  const types = [];
  let next = 0;
  text = text.replace(/%(?:\d+\$)?#@([^@]+)@/g, (token, name) => {
    const sub = substitutions[name];
    return sub ? `%${sub.argNum}$${sub.formatSpecifier}` : token;
  });
  for (const m of text.replaceAll("%%", "").matchAll(SPECIFIER)) {
    const index = m[1] ? Number(m[1]) - 1 : next++;
    const type = (m[2] ?? "") + m[3];
    types[index] = types[index] && types[index] !== type ? `${types[index]}/${type}` : type;
  }
  return types;
}

/** Every leaf string of one localization, labelled by the variation path that holds it. */
function leaves(localization, label = "", argumentTypes = null) {
  const found = [];
  if (localization.stringUnit) {
    found.push({ label, unit: localization.stringUnit, argumentTypes,
      substitutions: localization.substitutions });
  }
  for (const [kind, cases] of Object.entries(localization.variations ?? {})) {
    for (const [name, child] of Object.entries(cases)) {
      found.push(...leaves(child, `${label}${kind}.${name} `, argumentTypes));
    }
  }
  for (const [name, child] of Object.entries(localization.substitutions ?? {})) {
    found.push(...leaves(child, `${label}%#@${name}@ `, [child.formatSpecifier]));
  }
  return found;
}

function pluralCases(localization) {
  return Object.keys(localization.variations?.plural ?? {});
}

function checkPlurals(localization, required, context, problems) {
  const cases = pluralCases(localization);
  if (cases.length > 0) {
    const missing = required.filter((c) => !cases.includes(c));
    if (missing.length > 0) problems.push(`${context} lacks plural ${missing.join(", ")}`);
  }
  for (const [name, child] of Object.entries(localization.substitutions ?? {})) {
    checkPlurals(child, required, `${context} substitution ${name}`, problems);
  }
}

const problems = [];

for (const file of CATALOGS) {
  const catalog = JSON.parse(fs.readFileSync(path.join(ROOT, file), "utf8"));
  const name = path.basename(file);
  for (const [key, entry] of Object.entries(catalog.strings)) {
    if (entry.extractionState === "stale") {
      problems.push(`${name}: “${key}” is stale — no source uses it any more`);
      continue;
    }
    if (entry.shouldTranslate === false || !/\p{L}/u.test(key)) continue;

    const source = entry.localizations?.en;
    const keyTypes = specifiers(key);
    const sourceTypes = keyTypes.length > 0 ? keyTypes
      : specifiers(source?.stringUnit?.value ?? key, source?.substitutions);
    const isPlural = source && pluralCases(source).length > 0;

    for (const [language, required] of Object.entries({ en: ["one", "other"], ...LANGUAGES })) {
      const localization = entry.localizations?.[language];
      if (language === "en" && !localization) continue;
      if (!localization) {
        problems.push(`${name}: “${key}” has no ${language} translation`);
        continue;
      }
      const context = `${name}: “${key}” ${language}`;
      if (isPlural && pluralCases(localization).length === 0) {
        problems.push(`${context} lacks plural variations`);
      }
      checkPlurals(localization, required, context, problems);
      for (const sub of Object.values(source?.substitutions ?? {})) {
        if (pluralCases(sub).length > 0 && !Object.values(localization.substitutions ?? {}).some(
          (translated) => translated.argNum === sub.argNum && pluralCases(translated).length > 0
        )) {
          problems.push(`${context} lacks plural substitution for argument ${sub.argNum}`);
        }
      }
      for (const [subName, sub] of Object.entries(localization.substitutions ?? {})) {
        if (sourceTypes[sub.argNum - 1] !== sub.formatSpecifier) {
          problems.push(`${context} substitution ${subName} has an invalid argument type or position`);
        }
      }
      const strings = leaves(localization);
      if (strings.length === 0) problems.push(`${context} has no translated text`);
      for (const { label, unit, argumentTypes, substitutions } of strings) {
        if (unit.state !== "translated") {
          problems.push(`${name}: “${key}” ${language} ${label}is ${unit.state}`);
          continue;
        }
        for (const match of unit.value.matchAll(/%(?:\d+\$)?#@([^@]+)@/g)) {
          if (!substitutions?.[match[1]]) problems.push(`${context} references missing substitution ${match[1]}`);
        }
        const expected = argumentTypes ?? sourceTypes;
        if (expected.length === 0) continue;
        const types = specifiers(unit.value, substitutions);
        // A plural form may drop the count ("one" reading "an item"); it may never add or retype one.
        const count = label.includes("plural.") ? expected.findIndex((type) => /^(?:ll|l)?[diu]$/.test(type)) : -1;
        const mismatched = types.some((type, i) => type !== undefined && type !== expected[i])
          || types.length > expected.length
          || expected.some((type, i) => type !== types[i] && i !== count);
        if (mismatched) {
          problems.push(`${context} ${label}has specifiers [${types}] for [${expected}]`);
        }
      }
    }
  }
}

if (problems.length > 0) {
  console.error(`\n✗ ${problems.length} localization problem(s):`);
  for (const p of problems.slice(0, 200)) console.error(`  ${p}`);
  if (problems.length > 200) console.error(`  … and ${problems.length - 200} more`);
  console.error("  Run ./Scripts/sync-strings.sh after changing UI text, then translate what it adds.");
  process.exit(1);
}
