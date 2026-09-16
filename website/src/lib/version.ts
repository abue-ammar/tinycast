import { site } from "../data/site";

// Resolve the releases API URL from the repo link, so there's still a single
// source of truth (site.repo) rather than a second hardcoded slug.
const match = site.repo.match(/github\.com\/([^/]+)\/([^/]+)/);
const repoUrl = match
  ? `https://api.github.com/repos/${match[1]}/${match[2]}`
  : null;
const apiUrl = repoUrl ? `${repoUrl}/releases/latest` : null;

async function readRepoJson(url: string): Promise<unknown> {
  const res = await fetch(url, {
    headers: { Accept: "application/vnd.github+json" },
  });
  if (!res.ok) throw new Error(`GitHub API ${res.status}`);
  return res.json();
}

/**
 * The latest published release tag, read once at build time and baked into the
 * HTML. Doing this on the server rather than in the browser keeps the number
 * honest: an unauthenticated client fetch is rate-limited at 60/hr per IP, so
 * the old client-side version of this showed a stale fallback most of the time.
 */
export async function latestVersion(): Promise<string> {
  if (!apiUrl) return site.fallbackVersion;
  try {
    const data = await readRepoJson(apiUrl);
    const tag =
      data && typeof data === "object" && "tag_name" in data
        ? String((data as { tag_name: unknown }).tag_name)
        : "";
    return tag || site.fallbackVersion;
  } catch {
    // A build must not fail because GitHub is unreachable or rate-limiting.
    return site.fallbackVersion;
  }
}

/**
 * The repository's star count, formatted for the header badge, read at build
 * time for the same reason as the version above. Null when the number is
 * unavailable, so the caller drops the badge rather than showing a made-up one.
 */
export async function starCount(): Promise<string | null> {
  if (!repoUrl) return null;
  try {
    const data = await readRepoJson(repoUrl);
    const stars =
      data && typeof data === "object" && "stargazers_count" in data
        ? Number((data as { stargazers_count: unknown }).stargazers_count)
        : NaN;
    if (!Number.isFinite(stars)) return null;
    return stars < 1000 ? String(stars) : `${(stars / 1000).toFixed(1)}k`;
  } catch {
    // A build must not fail because GitHub is unreachable or rate-limiting.
    return null;
  }
}
