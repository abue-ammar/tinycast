#!/usr/bin/env node
// oxlint-disable no-unused-vars
// Generate Tinycast/Features/Emoji/Model/EmojiData.generated.swift from Unicode + CLDR data, plus
// one CLDR keyword pack per KEYWORD_LOCALES entry under Tinycast/Resources/EmojiKeywords/.
//
// Usage: node Scripts/gen-emoji.js [cache-dir]
// Downloads every source; a cache dir is read first and keeps what was fetched. Commit the output.
"use strict";

const fs = require("fs");
const path = require("path");

// Emoji added after this version may lack glyphs on the oldest supported macOS (26.0 ships Emoji 16.0).
const MAX_EMOJI_VERSION = 17.0;

const EMOJI_TEST_URL = "https://unicode.org/Public/emoji/latest/emoji-test.txt";
const CLDR_URL = "https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json";

// Widely used languages: CLDR locale → the pack name `Bundle.preferredLocalizations` matches.
const KEYWORD_LOCALES = {
  de: "de",
  es: "es",
  fr: "fr",
  ja: "ja",
  ko: "ko",
  pt: "pt",
  ru: "ru",
  zh: "zh-Hans",
};

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
  ["◉", "fisheye", "bullseye target circle dot"],
  ["◎", "bullseye", "target circle ring"],
  ["#", "number sign", "hash pound sharp"],
  ["*", "asterisk", "star multiply wildcard"],
  ["@", "at sign", "at arobase email"],
  ["&", "ampersand", "and"],
  ["%", "percent sign", "percent modulo"],
  ["⁉", "exclamation question mark", "interrobang surprise"],
  ["‼", "double exclamation mark", "bang emphasis"],
  ["℗", "sound recording copyright", "phonogram copyright publishing"],
  ["℠", "service mark", "servicemark trademark"],
  ["ª", "feminine ordinal indicator", "feminine ordinal spanish"],
  ["º", "masculine ordinal indicator", "masculine ordinal spanish portuguese"],
];
// Everyday CJK punctuation — not Unicode emoji, so the upstream data never carries it.
const CJK = [
  ["※", "reference mark", "kome komejirushi note footnote annotation"],
  ["〃", "ditto mark", "same repeat above"],
  ["〄", "japanese industrial standard symbol", "jis"],
  ["〆", "ideographic closing mark", "shime close seal"],
  ["〇", "ideographic number zero", "maru circle zero"],
  ["〒", "postal mark", "post yubin mail address"],
  ["〓", "geta mark", "tofu missing glyph"],
  ["〶", "circled postal mark", "post yubin mail"],
  ["〷", "ideographic telegraph line feed separator symbol", "telegraph"],
  ["〻", "vertical ideographic iteration mark", "repeat"],
  ["〼", "masu mark", "square"],
  ["〜", "wave dash", "tilde range approximately"],
  ["～", "fullwidth tilde", "wave dash range"],
  ["・", "katakana middle dot", "nakaguro separator interpunct"],
  ["―", "horizontal bar", "quotation dash long"],
  ["‥", "two dot leader", "ellipsis dots"],
  ["々", "ideographic iteration mark", "noma kurikaeshi repeat"],
  ["ゝ", "hiragana iteration mark", "repeat"],
  ["ゞ", "hiragana voiced iteration mark", "repeat dakuten"],
  ["ヽ", "katakana iteration mark", "repeat"],
  ["ヾ", "katakana voiced iteration mark", "repeat dakuten"],
  ["゠", "katakana-hiragana double hyphen", "double hyphen"],
  ["ヵ", "katakana letter small ka", "counter months"],
  ["ヶ", "katakana letter small ke", "counter months ka"],
  ["〳", "vertical kana repeat mark upper half", "repeat vertical"],
  ["〴", "voiced vertical kana repeat mark upper half", "repeat dakuten"],
  ["〵", "vertical kana repeat mark lower half", "repeat vertical"],
  ["〈", "left angle bracket", "quote open"],
  ["〉", "right angle bracket", "quote close"],
  ["《", "left double angle bracket", "quote title open"],
  ["》", "right double angle bracket", "quote title close"],
  ["「", "left corner bracket", "kagi quote open"],
  ["」", "right corner bracket", "kagi quote close"],
  ["『", "left white corner bracket", "quote title open"],
  ["』", "right white corner bracket", "quote title close"],
  ["【", "left black lenticular bracket", "heading open"],
  ["】", "right black lenticular bracket", "heading close"],
  ["︱", "vertical em dash", "tategaki presentation form"],
  ["︵", "vertical left parenthesis", "tategaki presentation form open"],
  ["︶", "vertical right parenthesis", "tategaki presentation form close"],
  ["︻", "vertical left black lenticular bracket", "tategaki heading open"],
  ["︼", "vertical right black lenticular bracket", "tategaki heading close"],
  ["﹁", "vertical left corner bracket", "tategaki kagi quote open"],
  ["﹂", "vertical right corner bracket", "tategaki kagi quote close"],
  ["﹃", "vertical left white corner bracket", "tategaki quote open"],
  ["﹄", "vertical right white corner bracket", "tategaki quote close"],
];
// Mac keyboard keys and everyday technicals, all listed by the macOS character viewer.
//  is Apple private-use (U+F8FF), so it never appears in Unicode data and is curated here.
const KEYS = [
  ["⌘", "command key", "cmd looped square place of interest"],
  ["⌥", "option key", "opt alt"],
  ["⌃", "control key", "ctrl caret up arrowhead"],
  ["⎋", "escape key", "esc"],
  ["⏎", "return key", "enter newline carriage"],
  ["⌤", "enter key", "enter numpad"],
  ["⌫", "delete key", "backspace erase backward"],
  ["⌦", "forward delete key", "delete forward fn"],
  ["⇥", "tab key", "tab right"],
  ["⇤", "backtab key", "shift tab left"],
  ["⇱", "home key", "home corner"],
  ["⇲", "end key", "end corner"],
  ["⇞", "page up key", "pgup page up"],
  ["⇟", "page down key", "pgdn page down"],
  ["⏏", "eject key", "eject media disk"],
  ["⌧", "clear key", "clear numpad"],
  ["⎙", "print screen key", "print screen sysrq"],
  ["␣", "space symbol", "space blank open box"],
  ["⌀", "diameter sign", "diameter engineering average"],
  ["⌂", "house", "home house"],
  ["⌨", "keyboard", "keyboard"],
  ["⚙", "gear", "settings cog preferences"],
  ["", "apple logo", "apple logo private"],
];
const SYMBOL_SECTIONS = [
  ["xa", ARROWS],
  ["xc", CURRENCY],
  ["xm", MATH],
  ["xs", SHAPES],
  ["xj", CJK],
  ["xk", KEYS],
];

const LINE_RE =
  /^([0-9A-F ]+?)\s*;\s*fully-qualified\s*#\s*(\S+)\s+E(\d+\.\d+)\s+(.*)$/;

async function source(name, url, cacheDir) {
  const cached = cacheDir && path.join(cacheDir, name);
  if (cached && fs.existsSync(cached)) return fs.readFileSync(cached, "utf-8");
  console.log(`fetching ${url}`);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`fetch ${url} failed: ${res.status}`);
  const text = await res.text();
  if (cached) fs.writeFileSync(cached, text);
  return text;
}

// One locale's `{default, tts}` by glyph; hand-written annotations win over derived ones.
async function annotationsFor(locale, cacheDir) {
  const [full, derived] = await Promise.all([
    source(
      `annotations-${locale}.json`,
      `${CLDR_URL}/cldr-annotations-full/annotations/${locale}/annotations.json`,
      cacheDir,
    ),
    source(
      `annotationsDerived-${locale}.json`,
      `${CLDR_URL}/cldr-annotations-derived-full/annotationsDerived/${locale}/annotations.json`,
      cacheDir,
    ),
  ]);
  return {
    ...JSON.parse(derived).annotationsDerived.annotations,
    ...JSON.parse(full).annotations.annotations,
  };
}

// Iterate a glyph's Unicode scalars (code points), matching Python's per-code-point view.
function scalarsOf(glyph) {
  return Array.from(glyph, (c) => c.codePointAt(0));
}

function baseKey(scalars) {
  return scalars.filter((s) => !isToneScalar(s) && s !== VS16).join(",");
}

function cleanField(s) {
  return s.replaceAll("|", " ").replaceAll(",", " ").replace(/\s+/g, " ").trim();
}

// CLDR keys most emoji without VS16, so a fully-qualified glyph falls back to its bare form.
function annotationOf(glyph, annotations) {
  const annotation = annotations[glyph];
  if (annotation?.default?.length) return annotation;
  return annotations[glyph.replaceAll("\u{FE0F}", "")];
}

function keywordsFor(glyph, name, annotations) {
  const words = annotationOf(glyph, annotations)?.default ?? [];
  const nameWords = new Set(name.toLowerCase().split(/\s+/).filter(Boolean));
  const out = [];
  for (let w of words) {
    w = cleanField(w.toLowerCase());
    if (w && !nameWords.has(w) && !out.includes(w)) out.push(w);
  }
  return out;
}

// A Japanese IME shows hiragana until the user converts, so katakana terms gain a hiragana twin.
function hiraganaOf(term) {
  return Array.from(term, (c) => {
    const s = c.codePointAt(0);
    return s >= 0x30a1 && s <= 0x30f6 ? String.fromCodePoint(s - 0x60) : c;
  }).join("");
}

// Search-only terms, never displayed, so the typographic apostrophe folds to the one keyboards type.
function localizedTermsFor(glyph, english, annotations) {
  const annotation = annotationOf(glyph, annotations);
  const out = [];
  for (const raw of [...(annotation?.tts ?? []), ...(annotation?.default ?? [])]) {
    const term = cleanField(raw.toLowerCase().replaceAll("’", "'"));
    for (const t of new Set([term, hiraganaOf(term)])) {
      if (t && !english.has(t) && !out.includes(t)) out.push(t);
    }
  }
  return out;
}

// `glyph|terms` for every catalog glyph CLDR names in the locale, minus what English already says.
function keywordPack(records, annotations) {
  const pack = [];
  for (const [glyph, name, , , keywords] of records) {
    const english = new Set([name, ...name.split(" "), ...keywords.split(",")]);
    const terms = localizedTermsFor(glyph, english, annotations);
    if (terms.length > 0) pack.push(`${glyph}|${terms.join(",")}`);
  }
  return pack;
}

async function main() {
  const cacheDir = process.argv[2];
  if (cacheDir) fs.mkdirSync(cacheDir, { recursive: true });
  const locales = Object.keys(KEYWORD_LOCALES);
  const [emojiTest, annotations, ...localized] = await Promise.all([
    source("emoji-test.txt", EMOJI_TEST_URL, cacheDir),
    annotationsFor("en", cacheDir),
    ...locales.map((locale) => annotationsFor(locale, cacheDir)),
  ]);

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
      keywords.join(","),
    ]);
  }
  for (const [category, table] of SYMBOL_SECTIONS) {
    for (const [glyph, name, keywords] of table) {
      lines.push([
        glyph,
        cleanField(name),
        category,
        "0",
        keywords.split(/\s+/).filter(Boolean).join(","),
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
    "Tinycast/Features/Emoji/Model/EmojiData.generated.swift",
  );
  fs.mkdirSync(path.dirname(out), { recursive: true });
  const body = records.join("\n");
  fs.writeFileSync(
    out,
    "// Generated by Scripts/gen-emoji.js — do not edit by hand.\n" +
      `// Unicode emoji ≤ E${MAX_EMOJI_VERSION.toFixed(1)} + curated symbols; fields: glyph|name|category|tone|keywords.\n` +
      "enum EmojiData {\n" +
      `    static let raw = """\n${body}\n"""\n` +
      "}\n",
  );
  console.log(`wrote ${out} (${records.length} records)`);

  const packDir = path.resolve(__dirname, "..", "Tinycast/Resources/EmojiKeywords");
  fs.rmSync(packDir, { recursive: true, force: true });
  fs.mkdirSync(packDir, { recursive: true });
  locales.forEach((locale, i) => {
    const pack = keywordPack(lines, localized[i]);
    if (pack.length <= 1500)
      throw new Error(`suspiciously few ${locale} keywords: ${pack.length}`);
    const file = path.join(packDir, `${KEYWORD_LOCALES[locale]}.txt`);
    fs.writeFileSync(file, `${pack.join("\n")}\n`);
  });
  console.log(`wrote ${packDir} (${locales.length} keyword packs)`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
