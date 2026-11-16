import { readRepoJson, repoApiUrl } from "./github";

// Scripts/release-notes.sh puts the install text below this line; only the half above is notes.
const INSTALL_MARKER = "<!-- tinycast:install -->";
// The updater's own rule: anything else (a beta, a one-off build) is not a stable release.
const STABLE_TAG = /^v(\d+)\.(\d+)\.(\d+)$/;
const PAGE_SIZE = 100;
const MAX_PAGES = 10;

// GitHub's generated notes, before and after the release script shortens PR links.
const CHANGE_LINE =
  /^\* (.+) by @([\w-]+(?:\[bot\])?) in (?:#|https:\/\/github\.com\/[^/]+\/[^/]+\/pull\/)(\d+)$/;
const COMPARE_LINK = /\[Full changelog\]\((\S+)\)/;
// A handful of PRs were titled Conventional-Commit style; the prefix is noise in a changelog.
const COMMIT_PREFIX =
  /^(?:feat|fix|chore|docs|refactor|perf|style|test|build|ci)(?:\([^)]*\))?!?:\s*/i;

export type Change = {
  title: string;
  author: string | null;
  pr: number | null;
};

export type Contributor = {
  login: string;
  changes: number;
};

export type StableRelease = {
  version: string;
  tag: string;
  publishedAt: string;
  url: string;
  compareUrl: string | null;
  /** False for releases published before notes were generated from merged PRs. */
  hasNotes: boolean;
  /** The notes' prose as markdown, such as the line a release with no merged PRs carries. */
  summary: string | null;
  changes: Change[];
  contributors: Contributor[];
};

type ApiRelease = {
  tag_name: string;
  draft: boolean;
  prerelease: boolean;
  published_at: string | null;
  html_url: string;
  body: string | null;
};

function isApiRelease(value: unknown): value is ApiRelease {
  if (!value || typeof value !== "object") return false;
  const release = value as Record<string, unknown>;
  return (
    typeof release.tag_name === "string" &&
    typeof release.html_url === "string" &&
    typeof release.draft === "boolean" &&
    typeof release.prerelease === "boolean"
  );
}

function cleanTitle(title: string): string {
  const bare = title.replace(COMMIT_PREFIX, "").trim();
  return bare.charAt(0).toUpperCase() + bare.slice(1);
}

function toChange(line: string): Change {
  const match = line.match(CHANGE_LINE);
  if (!match)
    return { title: cleanTitle(line.slice(2)), author: null, pr: null };
  return {
    title: cleanTitle(match[1]),
    author: match[2],
    pr: Number(match[3]),
  };
}

function parseNotes(notes: string) {
  const changes: Change[] = [];
  const prose: string[] = [];
  let section = "";

  for (const raw of notes.split(/\r?\n/)) {
    const line = raw.trim();
    // Only GitHub's level-2 headings start a generated list; a deeper one opens hand-written prose.
    if (line.startsWith("## ")) {
      section = line.slice(3).toLowerCase();
      continue;
    }
    if (/^#{3,6} /.test(line)) section = "notes";

    const isGenerated = section !== "notes";
    if (isGenerated && line.startsWith("* ")) {
      // Everyone listed there is already credited on the changes they made.
      if (!section.startsWith("new contributors")) changes.push(toChange(line));
      continue;
    }
    // The raw line keeps its indentation and blank lines, which the markdown needs.
    prose.push(raw.trimEnd());
  }

  const summary = prose
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  return { changes, summary: summary || null };
}

// Most changes first, ties in the order they first appear in the notes.
function rankContributors(changes: Change[]): Contributor[] {
  const counts = new Map<string, number>();
  for (const { author } of changes) {
    if (author) counts.set(author, (counts.get(author) ?? 0) + 1);
  }
  return [...counts]
    .map(([login, count]) => ({ login, changes: count }))
    .sort((a, b) => b.changes - a.changes);
}

function toStableRelease(release: ApiRelease): StableRelease | null {
  if (release.draft || release.prerelease) return null;
  if (!STABLE_TAG.test(release.tag_name) || !release.published_at) return null;

  const body = release.body ?? "";
  const [notes, install] = body.split(INSTALL_MARKER);
  const hasNotes = install !== undefined;
  const { changes, summary } = parseNotes(hasNotes ? notes : "");
  return {
    version: release.tag_name.slice(1),
    tag: release.tag_name,
    publishedAt: release.published_at,
    url: release.html_url,
    compareUrl: body.match(COMPARE_LINK)?.[1] ?? null,
    hasNotes,
    summary,
    changes,
    contributors: rankContributors(changes),
  };
}

function versionParts(tag: string): number[] {
  return (tag.match(STABLE_TAG) ?? []).slice(1).map(Number);
}

function byVersionDescending(a: StableRelease, b: StableRelease): number {
  const left = versionParts(a.tag);
  const right = versionParts(b.tag);
  for (let i = 0; i < 3; i++) {
    if (left[i] !== right[i]) return right[i] - left[i];
  }
  return 0;
}

/**
 * Every stable release, newest first, read once at build time. Null when GitHub
 * cannot be reached, so the page says so instead of claiming there is nothing.
 */
export async function stableReleases(): Promise<StableRelease[] | null> {
  if (!repoApiUrl) return null;
  try {
    const releases: StableRelease[] = [];
    for (let page = 1; page <= MAX_PAGES; page++) {
      const batch = await readRepoJson(
        `${repoApiUrl}/releases?per_page=${PAGE_SIZE}&page=${page}`,
      );
      if (!Array.isArray(batch)) throw new Error("Unexpected releases payload");
      for (const item of batch) {
        const release = isApiRelease(item) ? toStableRelease(item) : null;
        if (release) releases.push(release);
      }
      if (batch.length < PAGE_SIZE) break;
    }
    return releases.sort(byVersionDescending);
  } catch {
    // A build must not fail because GitHub is unreachable or rate-limiting.
    return null;
  }
}
