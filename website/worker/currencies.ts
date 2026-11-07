import { json } from "./http";

// Pages first: jsDelivr's `@latest` lags each daily publish by up to its 12-hour s-maxage.
const UPSTREAMS = [
  "https://latest.currency-api.pages.dev/v1/currencies/usd.min.json",
  "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json",
];
const BASE = "USD";
// The feed publishes once a day, so an hour bounds the lag without leaning on the upstream.
const REFRESH_SECONDS = 3600;
// Long enough to keep answering with the last snapshot through a multi-day upstream outage.
const KEEP_SECONDS = 7 * 86400;
const RESPONSE_CACHE_SECONDS = 600;
const UPSTREAM_TIMEOUT_MS = 5000;
// A healthy feed quotes ~340 codes; far fewer means a broken publish, not a smaller world.
const MIN_CODES = 150;
const MAX_SYMBOLS = 50;
const FETCHED_AT = "X-Fetched-At";

// Listed, not derived: the feed mixes in coin tickers, and the edge's ICU lags new ISO codes.
const FIAT = new Set(
  `
  AED AFN ALL AMD ANG AOA ARS AUD AWG AZN BAM BBD BDT BGN BHD BIF BMD BND BOB BRL
  BSD BTN BWP BYN BYR BZD CAD CDF CHF CLF CLP CNH CNY COP CRC CUC CUP CVE CZK DJF
  DKK DOP DZD EGP ERN ETB EUR FJD FKP GBP GEL GGP GHS GIP GMD GNF GTQ GYD HKD HNL
  HRK HTG HUF IDR ILS IMP INR IQD IRR ISK JEP JMD JOD JPY KES KGS KHR KMF KPW KRW
  KWD KYD KZT LAK LBP LKR LRD LSL LTL LVL LYD MAD MDL MGA MKD MMK MNT MOP MRU MUR
  MVR MWK MXN MXV MYR MZN NAD NGN NIO NOK NPR NZD OMR PAB PEN PGK PHP PKR PLN PYG
  QAR RON RSD RUB RWF SAR SBD SCR SDG SEK SGD SHP SLE SLL SOS SRD SSP STD STN SVC
  SYP SZL THB TJS TMT TND TOP TRY TTD TWD TZS UAH UGX UYU UZS VES VND VUV WST XAF
  XAG XAU XCD XCG XDR XOF XPF YER ZAR ZMK ZMW ZWL
  `
    .trim()
    .split(/\s+/),
);

/** Units of each uppercase code per one USD, as of `timestamp` in Unix seconds. */
type Snapshot = { timestamp: number; rates: Record<string, number> };

const usable = (rate: unknown): rate is number =>
  typeof rate === "number" && Number.isFinite(rate) && rate > 0;

function parse(body: unknown): Snapshot | null {
  if (!body || typeof body !== "object") return null;
  const { date, usd } = body as Record<string, unknown>;
  if (typeof date !== "string" || !usd || typeof usd !== "object") return null;
  const timestamp = Date.parse(`${date}T00:00:00Z`) / 1000;
  if (!Number.isFinite(timestamp)) return null;

  const rates: Record<string, number> = {};
  for (const [code, rate] of Object.entries(usd)) {
    if (usable(rate)) rates[code.toUpperCase()] = rate;
  }
  if (Object.keys(rates).length < MIN_CODES) return null;
  return { timestamp, rates };
}

async function download(): Promise<Snapshot | null> {
  for (const url of UPSTREAMS) {
    try {
      const response = await fetch(url, {
        signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
      });
      if (!response.ok) continue;
      const snapshot = parse(await response.json());
      if (snapshot) return snapshot;
    } catch (error) {
      console.error("currency upstream failed", url, error);
    }
  }
  return null;
}

async function store(key: Request, snapshot: Snapshot): Promise<void> {
  const response = Response.json(snapshot, {
    headers: {
      "Cache-Control": `public, max-age=${KEEP_SECONDS}`,
      [FETCHED_AT]: String(Date.now()),
    },
  });
  await caches.default.put(key, response);
}

async function refresh(
  key: Request,
  current: Snapshot | null,
): Promise<Snapshot | null> {
  const next = await download();
  // A lagging fallback must not roll back a newer table; re-storing still restarts the clock.
  const kept =
    next && (!current || next.timestamp >= current.timestamp) ? next : current;
  if (kept) await store(key, kept);
  return kept;
}

/** Edge-cached per colo; a stale copy answers at once while a fresh one loads behind it. */
async function snapshot(
  request: Request,
  ctx: ExecutionContext,
): Promise<Snapshot | null> {
  const key = new Request(new URL("/api/v1/currencies/snapshot", request.url));
  const cached = await caches.default.match(key);
  if (!cached) return refresh(key, null);

  const current = (await cached.json()) as Snapshot;
  const age = Date.now() - Number(cached.headers.get(FETCHED_AT));
  if (!(age < REFRESH_SECONDS * 1000)) ctx.waitUntil(refresh(key, current));
  return current;
}

function failure(status: number, info: string): Response {
  return json({ success: false, error: { code: status, info } }, status);
}

/** `{ success, timestamp, source, quotes: { USDEUR, … } }`, omitting the base's own row. */
export async function fiatRates(
  request: Request,
  ctx: ExecutionContext,
): Promise<Response> {
  const table = await snapshot(request, ctx);
  if (!table) return failure(502, "Exchange rates are unavailable.");

  const quotes: Record<string, number> = {};
  for (const [code, rate] of Object.entries(table.rates)) {
    if (code !== BASE && FIAT.has(code)) quotes[BASE + code] = rate;
  }
  return json(
    { success: true, timestamp: table.timestamp, source: BASE, quotes },
    200,
    RESPONSE_CACHE_SECONDS,
  );
}

/** `{ success, timestamp, target, rates: { BTC, … } }`: one coin's price in the base. */
export async function cryptoRates(
  request: Request,
  ctx: ExecutionContext,
): Promise<Response> {
  const symbols = new Set(
    (new URL(request.url).searchParams.get("symbols") ?? "")
      .split(",")
      .map((symbol) => symbol.trim().toUpperCase())
      .filter((symbol) => /^[A-Z0-9]{1,10}$/.test(symbol)),
  );
  if (symbols.size === 0) return failure(400, "Pass one or more symbols.");
  if (symbols.size > MAX_SYMBOLS) {
    return failure(400, `Pass at most ${MAX_SYMBOLS} symbols.`);
  }

  const table = await snapshot(request, ctx);
  if (!table) return failure(502, "Crypto rates are unavailable.");

  const rates: Record<string, number> = {};
  for (const symbol of symbols) {
    const perBase = table.rates[symbol];
    if (perBase !== undefined) rates[symbol] = 1 / perBase;
  }
  return json(
    { success: true, timestamp: table.timestamp, target: BASE, rates },
    200,
    RESPONSE_CACHE_SECONDS,
  );
}
