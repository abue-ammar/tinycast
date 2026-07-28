#!/usr/bin/env node
// oxlint-disable no-unused-vars
// Generate Smallcast/Core/Emoji/EmojiData.generated.swift from Unicode + CLDR data.
//
// Usage: node Tools/gen-emoji.js [emoji-test.txt annotations.json annotationsDerived.json]
// Downloads the sources when paths aren't given. Run once, commit the output.
"use strict";

const fs = require("fs");
const path = require("path");

// Emoji added after this version may lack glyphs on the oldest supported macOS (26.0 ships Emoji 16.0).
const MAX_EMOJI_VERSION = 17.0;

const SOURCES = [
  ["emoji-test.txt", "https://unicode.org/Public/emoji/latest/emoji-test.txt"],
  [
    "annotations.json",
    "https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-annotations-full/annotations/en/annotations.json",
  ],
  [
    "annotationsDerived.json",
    "https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-annotations-derived-full/annotationsDerived/en/annotations.json",
  ],
];

const GROUP_TO_CATEGORY = {
  "Smileys & Emotion": "sp",
  "People & Body": "sp",
  "Animals & Nature": "an",
  "Food & Drink": "fd",
  Activities: "ac",
  "Travel & Places": "tp",
  Objects: "ob",
  Symbols: "sy",
  Flags: "fl",
};

const VS16 = 0xfe0f;
const MAX_KEYWORDS = 8;
const isToneScalar = (s) => s >= 0x1f3fb && s <= 0x1f3ff;

// Curated text symbols: [glyph, name, keywords]. Names lowercase like the emoji dataset.
const ARROWS = [
  ["←", "leftwards arrow", "left back previous"],
  ["↑", "upwards arrow", "up top"],
  ["→", "rightwards arrow", "right next forward"],
  ["↓", "downwards arrow", "down bottom"],
  ["↖", "north west arrow", "diagonal up left"],
  ["↗", "north east arrow", "diagonal up right"],
  ["↘", "south east arrow", "diagonal down right"],
  ["↙", "south west arrow", "diagonal down left"],
  ["↔", "left right arrow", "horizontal both"],
  ["↕", "up down arrow", "vertical both"],
  ["↩", "leftwards arrow with hook", "return undo back"],
  ["↪", "rightwards arrow with hook", "redo forward"],
  ["↰", "upwards arrow with tip leftwards", "turn"],
  ["↱", "upwards arrow with tip rightwards", "turn"],
  ["↲", "downwards arrow with tip leftwards", "turn"],
  ["↳", "downwards arrow with tip rightwards", "turn branch"],
  ["⇄", "rightwards arrow over leftwards arrow", "swap exchange sync"],
  ["⇅", "upwards arrow leftwards of downwards arrow", "swap sort"],
  ["⇐", "leftwards double arrow", "implies"],
  ["⇑", "upwards double arrow", "shift"],
  ["⇒", "rightwards double arrow", "implies therefore"],
  ["⇓", "downwards double arrow", ""],
  ["⇔", "left right double arrow", "iff equivalent"],
  ["⇧", "upwards white arrow", "shift key"],
  ["⇪", "upwards white arrow from bar", "caps lock key"],
  ["➔", "heavy wide-headed rightwards arrow", "pointer"],
  ["➜", "heavy round-tipped rightwards arrow", "pointer"],
  ["➤", "black rightwards arrowhead", "pointer bullet"],
];
const CURRENCY = [
  ["$", "dollar sign", "usd money currency"],
  ["¢", "cent sign", "money currency"],
  ["£", "pound sign", "gbp sterling money currency"],
  ["€", "euro sign", "eur money currency"],
  ["¥", "yen sign", "jpy yuan money currency"],
  ["₹", "indian rupee sign", "inr money currency"],
  ["₩", "won sign", "krw money currency"],
  ["₽", "ruble sign", "rub money currency"],
  ["₺", "turkish lira sign", "try money currency"],
  ["₫", "dong sign", "vnd money currency"],
  ["₴", "hryvnia sign", "uah money currency"],
  ["₦", "naira sign", "ngn money currency"],
  ["₪", "new shekel sign", "ils money currency"],
  ["฿", "baht sign", "thb money currency"],
  ["₿", "bitcoin sign", "btc crypto money currency"],
  ["₡", "colon sign", "crc money currency"],
  ["₱", "peso sign", "php money currency"],
  ["₨", "rupee sign", "pkr money currency"],
  ["₸", "tenge sign", "kzt money currency"],
  ["¤", "generic currency sign", "money"],
];
const MATH = [
  ["+", "plus sign", "add addition"],
  ["−", "minus sign", "subtract subtraction"],
  ["×", "multiplication sign", "times multiply"],
  ["÷", "division sign", "divide"],
  ["=", "equals sign", "equal"],
  ["≠", "not equal to", "unequal"],
  ["≈", "almost equal to", "approximately"],
  ["<", "less-than sign", ""],
  [">", "greater-than sign", ""],
  ["≤", "less-than or equal to", ""],
  ["≥", "greater-than or equal to", ""],
  ["±", "plus-minus sign", "plus or minus"],
  ["¬", "not sign", "negation"],
  ["√", "square root", "radical"],
  ["∛", "cube root", "radical"],
  ["∞", "infinity", "forever"],
  ["∑", "n-ary summation", "sum sigma"],
  ["∏", "n-ary product", "pi product"],
  ["∫", "integral", "calculus"],
  ["∂", "partial differential", "calculus derivative"],
  ["∆", "increment", "delta difference"],
  ["∇", "nabla", "gradient del"],
  ["∈", "element of", "set member"],
  ["∉", "not an element of", "set"],
  ["∩", "intersection", "set"],
  ["∪", "union", "set"],
  ["⊂", "subset of", "set"],
  ["⊃", "superset of", "set"],
  ["∅", "empty set", "null"],
  ["∧", "logical and", "conjunction"],
  ["∨", "logical or", "disjunction"],
  ["⊕", "circled plus", "xor direct sum"],
  ["∝", "proportional to", ""],
  ["∴", "therefore", ""],
  ["∵", "because", "since"],
  ["°", "degree sign", "temperature angle"],
  ["‰", "per mille sign", "permille thousand"],
  ["µ", "micro sign", "mu micro"],
  ["π", "greek small letter pi", "math constant"],
  ["Ω", "greek capital letter omega", "ohm resistance"],
  ["¼", "vulgar fraction one quarter", "fourth"],
  ["½", "vulgar fraction one half", ""],
  ["¾", "vulgar fraction three quarters", ""],
  ["ƒ", "latin small letter f with hook", "function florin"],
];
const SHAPES = [
  ["■", "black square", "shape filled"],
  ["□", "white square", "shape outline"],
  ["▪", "black small square", "shape"],
  ["▫", "white small square", "shape"],
  ["▲", "black up-pointing triangle", "shape"],
  ["△", "white up-pointing triangle", "shape"],
  ["▶", "black right-pointing triangle", "play shape"],
  ["▷", "white right-pointing triangle", "play shape"],
  ["▼", "black down-pointing triangle", "shape"],
  ["▽", "white down-pointing triangle", "shape"],
  ["◀", "black left-pointing triangle", "shape"],
  ["◁", "white left-pointing triangle", "shape"],
  ["●", "black circle", "dot shape filled"],
  ["○", "white circle", "shape outline"],
  ["◆", "black diamond", "shape"],
  ["◇", "white diamond", "shape"],
  ["★", "black star", "favorite shape filled"],
  ["☆", "white star", "favorite shape outline"],
  ["✓", "check mark", "tick done yes"],
  ["✗", "ballot x", "cross no wrong"],
  ["♠", "black spade suit", "cards"],
  ["♣", "black club suit", "cards"],
  ["♥", "black heart suit", "cards love"],
  ["♦", "black diamond suit", "cards"],
  ["•", "bullet", "list point dot"],
  ["◦", "white bullet", "list point"],
  ["‣", "triangular bullet", "list point"],
  ["·", "middle dot", "interpunct"],
  ["—", "em dash", "long dash punctuation"],
  ["–", "en dash", "dash range punctuation"],
  ["…", "horizontal ellipsis", "dots punctuation"],
  ["«", "left-pointing double angle quotation mark", "guillemet quote"],
  ["»", "right-pointing double angle quotation mark", "guillemet quote"],
  ["‘", "left single quotation mark", "quote"],
  ["’", "right single quotation mark", "quote apostrophe"],
  ["“", "left double quotation mark", "quote"],
  ["”", "right double quotation mark", "quote"],
  ["„", "double low-9 quotation mark", "quote"],
  ["†", "dagger", "footnote"],
  ["‡", "double dagger", "footnote"],
  ["§", "section sign", "paragraph law"],
  ["¶", "pilcrow sign", "paragraph"],
  ["©", "copyright sign", "legal"],
  ["®", "registered sign", "trademark legal"],
  ["™", "trade mark sign", "trademark legal"],
  ["№", "numero sign", "number"],
  ["¡", "inverted exclamation mark", "spanish punctuation"],
  ["¿", "inverted question mark", "spanish punctuation"],
];
const SYMBOL_SECTIONS = [
  ["xa", ARROWS],
  ["xc", CURRENCY],
  ["xm", MATH],
  ["xs", SHAPES],
];

const LINE_RE =
  /^([0-9A-F ]+?)\s*;\s*fully-qualified\s*#\s*(\S+)\s+E(\d+\.\d+)\s+(.*)$/;

async function load(paths) {
  const texts = [];
  for (let i = 0; i < SOURCES.length; i++) {
    const [, url] = SOURCES[i];
    const given = paths[i];
    if (given) {
      texts.push(fs.readFileSync(given, "utf-8"));
    } else {
      console.log(`fetching ${url}`);
      const res = await fetch(url);
      if (!res.ok) throw new Error(`fetch ${url} failed: ${res.status}`);
      texts.push(await res.text());
    }
  }
  return texts;
}

// Iterate a glyph's Unicode scalars (code points), matching Python's per-code-point view.
function scalarsOf(glyph) {
  return Array.from(glyph, (c) => c.codePointAt(0));
}

function baseKey(scalars) {
  return scalars.filter((s) => !isToneScalar(s) && s !== VS16).join(",");
}

function cleanField(s) {
  return s.replaceAll("|", " ").replaceAll(",", " ").trim();
}

function keywordsFor(glyph, name, annotations) {
  let words = annotations[glyph];
  if (!words || words.length === 0)
    words = annotations[glyph.replaceAll("️", "")];
  if (!words) words = [];
  const nameWords = new Set(name.toLowerCase().split(/\s+/).filter(Boolean));
  const out = [];
  for (let w of words) {
    w = cleanField(w.toLowerCase());
    if (w && !nameWords.has(w) && !out.includes(w)) out.push(w);
  }
  return out.slice(0, MAX_KEYWORDS);
}

async function main() {
  const [emojiTest, annJson, derivedJson] = await load(
    process.argv.slice(2, 5),
  );
  const ann = JSON.parse(annJson).annotations.annotations;
  const derived = JSON.parse(derivedJson).annotationsDerived.annotations;
  const merged = { ...derived, ...ann };
  const annotations = {};
  for (const g of Object.keys(merged)) annotations[g] = merged[g].default || [];

  let group = null;
  const entries = []; // [glyph, name, category, scalars]
  const tonedBases = new Set();
  for (const line of emojiTest.split("\n")) {
    if (line.startsWith("# group:")) {
      group = line.split(":").slice(1).join(":").trim();
      continue;
    }
    const m = LINE_RE.exec(line);
    if (!m || !(group in GROUP_TO_CATEGORY)) continue;
    const [, codes, glyph, version, name] = m;
    if (parseFloat(version) > MAX_EMOJI_VERSION) continue;
    const scalars = codes.split(/\s+/).map((c) => parseInt(c, 16));
    if (scalars.some(isToneScalar)) {
      tonedBases.add(baseKey(scalars));
      continue;
    }
    entries.push([glyph, name.trim(), GROUP_TO_CATEGORY[group], scalars]);
  }

  const lines = [];
  for (const [glyph, name, category, scalars] of entries) {
    const bk = baseKey(scalars);
    const toneCapable = tonedBases.has(bk) && bk !== "" && !bk.includes(",");
    const keywords = keywordsFor(glyph, name, annotations);
    lines.push([
      glyph,
      cleanField(name.toLowerCase()),
      category,
      toneCapable ? "1" : "0",
      keywords.join(" "),
    ]);
  }
  for (const [category, table] of SYMBOL_SECTIONS) {
    for (const [glyph, name, keywords] of table) {
      lines.push([
        glyph,
        cleanField(name),
        category,
        "0",
        cleanField(keywords),
      ]);
    }
  }

  const seen = new Set();
  const records = [];
  for (const fields of lines) {
    if (seen.has(fields[0]))
      throw new Error(`duplicate glyph ${JSON.stringify(fields[0])}`);
    seen.add(fields[0]);
    const record = fields.join("|");
    if (record.includes('"""') || record.includes("\\"))
      throw new Error(`unsafe record ${JSON.stringify(record)}`);
    records.push(record);
  }
  if (records.length <= 1500)
    throw new Error(`suspiciously few records: ${records.length}`);

  const out = path.resolve(
    __dirname,
    "..",
    "Smallcast/Core/Emoji/EmojiData.generated.swift",
  );
  fs.mkdirSync(path.dirname(out), { recursive: true });
  const body = records.join("\n");
  fs.writeFileSync(
    out,
    "// Generated by Tools/gen-emoji.js — do not edit by hand.\n" +
      `// Unicode emoji ≤ E${MAX_EMOJI_VERSION.toFixed(1)} + curated symbols; fields: glyph|name|category|tone|keywords.\n` +
      "enum EmojiData {\n" +
      `    static let raw = """\n${body}\n"""\n` +
      "}\n",
  );
  console.log(`wrote ${out} (${records.length} records)`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
