import { PolarCore } from "@polar-sh/sdk/core.js";
import { checkoutsCreate } from "@polar-sh/sdk/funcs/checkoutsCreate.js";
import { cryptoRates, fiatRates } from "./currencies";
import { json } from "./http";
import { countSupporters } from "./supporters";

// Absent in a contributor's local run, which must still serve the site.
type WorkerEnv = Env & { POLAR_ACCESS_TOKEN?: string };

type Plan = "monthly" | "one-time";

// A count that lags a few minutes is fine, and it keeps Polar out of most page loads.
const SUPPORTERS_CACHE_SECONDS = 600;
const MAX_AMOUNT = 10_000;

function polar(env: WorkerEnv, accessToken: string): PolarCore {
  // .dev.vars may say "sandbox"; the generated type only knows the deployed value.
  const server = env.POLAR_SERVER as "production" | "sandbox";
  return new PolarCore({ accessToken, server });
}

async function supporters(
  request: Request,
  env: WorkerEnv,
  ctx: ExecutionContext,
): Promise<Response> {
  const token = env.POLAR_ACCESS_TOKEN;
  if (!token) return json({ total: 0 });

  // One key whatever the query string, so ?anything cannot skip the cache and hammer Polar.
  const key = new Request(new URL("/api/supporters", request.url));
  const cache = caches.default;
  const cached = await cache.match(key);
  if (cached) return cached;
  try {
    const total = await countSupporters(polar(env, token), [
      env.POLAR_PRODUCT_MONTHLY,
      env.POLAR_PRODUCT_ONE_TIME,
    ]);
    const response = json({ total }, 200, SUPPORTERS_CACHE_SECONDS);
    ctx.waitUntil(cache.put(key, response.clone()));
    return response;
  } catch (error) {
    console.error("supporter count failed", error);
    return json({ error: "The supporter count is unavailable." }, 502);
  }
}

function parseCheckout(body: unknown): { plan: Plan; amount: number } | null {
  if (!body || typeof body !== "object") return null;
  const { plan, amount } = body as Record<string, unknown>;
  if (plan !== "monthly" && plan !== "one-time") return null;
  if (!Number.isInteger(amount)) return null;
  const dollars = amount as number;
  if (dollars < 1 || dollars > MAX_AMOUNT) return null;
  return { plan, amount: dollars };
}

async function checkout(request: Request, env: WorkerEnv): Promise<Response> {
  const token = env.POLAR_ACCESS_TOKEN;
  if (!token) return json({ error: "Checkout is not configured." }, 503);

  const visitor = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const { success } = await env.CHECKOUT_LIMIT.limit({ key: visitor });
  if (!success) {
    return json({ error: "Too many attempts. Try again in a minute." }, 429);
  }

  const input = parseCheckout(await request.json().catch(() => null));
  if (!input) return json({ error: "Choose a whole amount in dollars." }, 400);

  // The Worker serves the page too, so its own origin is where Polar sends the visitor back.
  const origin = new URL(request.url).origin;
  const result = await checkoutsCreate(polar(env, token), {
    products: [
      input.plan === "monthly"
        ? env.POLAR_PRODUCT_MONTHLY
        : env.POLAR_PRODUCT_ONE_TIME,
    ],
    amount: input.amount * 100,
    successUrl: `${origin}/support/?thanks=${input.plan}`,
    returnUrl: `${origin}/support/`,
    metadata: { source: "support-page", plan: input.plan },
  });
  if (!result.ok) {
    console.error("checkout create failed", result.error);
    return json({ error: "Polar could not start the checkout." }, 502);
  }
  return json({ url: result.value.url });
}

export default {
  async fetch(request, env, ctx) {
    const { pathname } = new URL(request.url);
    const method = request.method;

    if (pathname === "/api/supporters" && method === "GET") {
      return supporters(request, env, ctx);
    }
    if (pathname === "/api/checkout" && method === "POST") {
      return checkout(request, env);
    }
    if (pathname === "/api/v1/currencies" && method === "GET") {
      return fiatRates(request, ctx);
    }
    if (pathname === "/api/v1/currencies/crypto" && method === "GET") {
      return cryptoRates(request, ctx);
    }
    return env.ASSETS.fetch(request);
  },
} satisfies ExportedHandler<WorkerEnv>;
