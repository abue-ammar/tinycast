export function json(body: unknown, status = 200, cacheSeconds = 0): Response {
  return Response.json(body, {
    status,
    headers: {
      "Cache-Control": cacheSeconds
        ? `public, max-age=${cacheSeconds}`
        : "no-store",
      "X-Robots-Tag": "noindex",
    },
  });
}
