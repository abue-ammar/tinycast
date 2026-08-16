// Node's `punycode` module. Extension bundles pull it in transitively through whatwg-url / tr46 (and
// so through almost every HTTP client), which makes it the single most load-bearing Node builtin
// after `path`. RFC 3492 / RFC 5891, ported from the reference implementation.

const BASE = 36;
const T_MIN = 1;
const T_MAX = 26;
const SKEW = 38;
const DAMP = 700;
const INITIAL_BIAS = 72;
const INITIAL_N = 128;
const DELIMITER = "-";
const MAX_INT = 0x7fffffff;

function error(type) {
  throw new RangeError(
    { overflow: "Overflow: input needs wider integers to process", "not-basic": "Illegal input >= 0x80 (not a basic code point)", "invalid-input": "Invalid input" }[type],
  );
}

function map(array, fn) {
  return array.map(fn);
}

function mapDomain(domain, fn) {
  const parts = domain.split("@");
  let result = "";
  if (parts.length > 1) {
    result = parts[0] + "@";
    domain = parts[1];
  }
  domain = domain.replace(/[.。．｡]/g, ".");
  return result + map(domain.split("."), fn).join(".");
}

export function ucs2decode(string) {
  const output = [];
  let counter = 0;
  while (counter < string.length) {
    const value = string.charCodeAt(counter++);
    if (value >= 0xd800 && value <= 0xdbff && counter < string.length) {
      const extra = string.charCodeAt(counter++);
      if ((extra & 0xfc00) === 0xdc00) {
        output.push(((value & 0x3ff) << 10) + (extra & 0x3ff) + 0x10000);
      } else {
        output.push(value);
        counter--;
      }
    } else {
      output.push(value);
    }
  }
  return output;
}

export function ucs2encode(codePoints) {
  return String.fromCodePoint(...codePoints);
}

function basicToDigit(codePoint) {
  if (codePoint >= 0x30 && codePoint < 0x3a) return 26 + (codePoint - 0x30);
  if (codePoint >= 0x41 && codePoint < 0x5b) return codePoint - 0x41;
  if (codePoint >= 0x61 && codePoint < 0x7b) return codePoint - 0x61;
  return BASE;
}

function digitToBasic(digit, flag) {
  return digit + 22 + (digit < 26 ? 75 : 0) - (flag !== 0 ? 1 : 0) * 32;
}

function adapt(delta, numPoints, firstTime) {
  let k = 0;
  delta = firstTime ? Math.floor(delta / DAMP) : delta >> 1;
  delta += Math.floor(delta / numPoints);
  for (; delta > ((BASE - T_MIN) * T_MAX) >> 1; k += BASE) {
    delta = Math.floor(delta / (BASE - T_MIN));
  }
  return Math.floor(k + ((BASE - T_MIN + 1) * delta) / (delta + SKEW));
}

export function decode(input) {
  const output = [];
  const inputLength = input.length;
  let i = 0;
  let n = INITIAL_N;
  let bias = INITIAL_BIAS;

  let basic = input.lastIndexOf(DELIMITER);
  if (basic < 0) basic = 0;

  for (let j = 0; j < basic; ++j) {
    if (input.charCodeAt(j) >= 0x80) error("not-basic");
    output.push(input.charCodeAt(j));
  }

  for (let index = basic > 0 ? basic + 1 : 0; index < inputLength; ) {
    const oldi = i;
    for (let w = 1, k = BASE; ; k += BASE) {
      if (index >= inputLength) error("invalid-input");
      const digit = basicToDigit(input.charCodeAt(index++));
      if (digit >= BASE) error("invalid-input");
      if (digit > Math.floor((MAX_INT - i) / w)) error("overflow");
      i += digit * w;
      const t = k <= bias ? T_MIN : k >= bias + T_MAX ? T_MAX : k - bias;
      if (digit < t) break;
      if (w > Math.floor(MAX_INT / (BASE - t))) error("overflow");
      w *= BASE - t;
    }
    const out = output.length + 1;
    bias = adapt(i - oldi, out, oldi === 0);
    if (Math.floor(i / out) > MAX_INT - n) error("overflow");
    n += Math.floor(i / out);
    i %= out;
    output.splice(i++, 0, n);
  }

  return String.fromCodePoint(...output);
}

export function encode(input) {
  const output = [];
  const decoded = ucs2decode(String(input));
  const inputLength = decoded.length;
  let n = INITIAL_N;
  let delta = 0;
  let bias = INITIAL_BIAS;

  for (const codePoint of decoded) if (codePoint < 0x80) output.push(String.fromCharCode(codePoint));

  const basicLength = output.length;
  let handledCPCount = basicLength;
  if (basicLength) output.push(DELIMITER);

  while (handledCPCount < inputLength) {
    let m = MAX_INT;
    for (const codePoint of decoded) if (codePoint >= n && codePoint < m) m = codePoint;

    const handledCPCountPlusOne = handledCPCount + 1;
    if (m - n > Math.floor((MAX_INT - delta) / handledCPCountPlusOne)) error("overflow");
    delta += (m - n) * handledCPCountPlusOne;
    n = m;

    for (const codePoint of decoded) {
      if (codePoint < n && ++delta > MAX_INT) error("overflow");
      if (codePoint !== n) continue;
      let q = delta;
      for (let k = BASE; ; k += BASE) {
        const t = k <= bias ? T_MIN : k >= bias + T_MAX ? T_MAX : k - bias;
        if (q < t) break;
        const qMinusT = q - t;
        const baseMinusT = BASE - t;
        output.push(String.fromCharCode(digitToBasic(t + (qMinusT % baseMinusT), 0)));
        q = Math.floor(qMinusT / baseMinusT);
      }
      output.push(String.fromCharCode(digitToBasic(q, 0)));
      bias = adapt(delta, handledCPCountPlusOne, handledCPCount === basicLength);
      delta = 0;
      ++handledCPCount;
    }
    ++delta;
    ++n;
  }
  return output.join("");
}

export function toUnicode(domain) {
  return mapDomain(domain, (part) =>
    /^xn--/i.test(part) ? decode(part.slice(4).toLowerCase()) : part,
  );
}

export function toASCII(domain) {
  return mapDomain(domain, (part) => (/[^\0-\x7E]/.test(part) ? "xn--" + encode(part) : part));
}

export const punycode = {
  version: "2.3.1",
  ucs2: { decode: ucs2decode, encode: ucs2encode },
  decode,
  encode,
  toASCII,
  toUnicode,
};
