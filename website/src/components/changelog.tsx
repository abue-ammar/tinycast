import { createMarkdownRenderer } from "fumadocs-core/content/md";
import type { ComponentProps } from "react";
import { ArrowUpRight, ChevronDown } from "lucide-react";
import { changelogCopy, changelogHero } from "../data/changelog";
import { site } from "../data/site";
import type { Change, Contributor, StableRelease } from "../lib/changelog";
import { cn } from "../lib/cn";
import { Button } from "./ui/button";
import { GitHubLogo } from "./ui/icon";

const releasesUrl = `${site.repo}/releases`;
// Enough to show a release's shape; the rest is one click, and needs no script.
const PREVIEW_COUNT = 8;
// The version column and the rail beside it, shared by every row so the rail is one line.
const railRow =
  "md:grid md:grid-cols-[220px_minmax(0,1fr)] lg:grid-cols-[260px_minmax(0,1fr)]";
const railLabel = "md:pr-10 md:text-right";
const railBody = "relative md:border-l md:border-border md:pl-10";

const dateFormat = new Intl.DateTimeFormat("en-US", {
  dateStyle: "medium",
  timeZone: "UTC",
});

function plural(count: number, one: string, many: string) {
  return `${count.toLocaleString("en-US")} ${count === 1 ? one : many}`;
}

function RailDot({ highlighted = false }: { highlighted?: boolean }) {
  return (
    <span
      aria-hidden="true"
      className={cn(
        "absolute -left-[5px] top-4 hidden size-[9px] rounded-full ring-4 md:block",
        highlighted
          ? "bg-violet ring-violet/20"
          : "bg-border-strong ring-canvas",
      )}
    />
  );
}

function ExternalLink({ href, children }: { href: string; children: string }) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noreferrer"
      className="inline-flex items-center gap-1 text-small text-fg-muted transition-colors hover:text-fg"
    >
      {children}
      <ArrowUpRight size={13} aria-hidden="true" />
    </a>
  );
}

// GitHub titles mark code with backticks, so every odd segment is code. An
// unpaired backtick leaves the title as plain text rather than guessing.
function ChangeTitle({ title }: { title: string }) {
  const parts = title.split("`");
  if (parts.length % 2 === 0) return title;
  return parts.map((part, index) =>
    index % 2 === 1 ? (
      <code
        key={index}
        className="rounded-sm bg-well px-1 py-0.5 font-mono text-key text-fg"
      >
        {part}
      </code>
    ) : (
      part
    ),
  );
}

// Raw HTML in a release body is dropped by the renderer, so notes cannot inject markup.
const { MarkdownServer } = createMarkdownRenderer();

function NotesHeading(props: ComponentProps<"h3">) {
  return (
    <h3
      {...props}
      className="mb-3 mt-6 text-body font-semibold text-fg first:mt-0"
    />
  );
}

const notesComponents = {
  h1: NotesHeading,
  h2: NotesHeading,
  h3: NotesHeading,
  h4: NotesHeading,
  p: (props: ComponentProps<"p">) => (
    <p {...props} className="mt-3 text-pretty first:mt-0" />
  ),
  ul: (props: ComponentProps<"ul">) => (
    <ul {...props} className="mt-3 list-disc space-y-2 pl-5" />
  ),
  ol: (props: ComponentProps<"ol">) => (
    <ol
      {...props}
      className="mt-3 list-decimal space-y-2 pl-5 marker:text-fg-subtle"
    />
  ),
  li: (props: ComponentProps<"li">) => (
    <li {...props} className="pl-1 text-pretty" />
  ),
  strong: (props: ComponentProps<"strong">) => (
    <strong {...props} className="font-semibold text-fg" />
  ),
  code: (props: ComponentProps<"code">) => (
    <code
      {...props}
      className="rounded-sm bg-well px-1 py-0.5 font-mono text-key text-fg"
    />
  ),
  a: (props: ComponentProps<"a">) => (
    <a
      {...props}
      target="_blank"
      rel="noreferrer"
      className="text-fg underline decoration-border-strong underline-offset-2 transition-colors hover:decoration-fg"
    />
  ),
};

function ReleaseNotes({ notes, isCard }: { notes: string; isCard: boolean }) {
  return (
    <div
      className={cn(
        "text-small text-fg-muted",
        isCard ? "rounded-xl px-5 py-4 shadow-key" : "mb-5",
      )}
    >
      <MarkdownServer components={notesComponents}>{notes}</MarkdownServer>
    </div>
  );
}

function ChangeRow({ change }: { change: Change }) {
  return (
    <li className="py-3.5 sm:flex sm:items-baseline sm:justify-between sm:gap-8">
      <p className="text-pretty text-small text-fg">
        <ChangeTitle title={change.title} />
      </p>
      {change.author && change.pr && (
        <p className="mt-1 shrink-0 font-mono text-caption text-fg-subtle sm:mt-0">
          <a
            href={`https://github.com/${change.author}`}
            target="_blank"
            rel="noreferrer"
            className="transition-colors hover:text-fg"
          >
            @{change.author}
          </a>
          <span aria-hidden="true"> · </span>
          <a
            href={`${site.repo}/pull/${change.pr}`}
            target="_blank"
            rel="noreferrer"
            className="transition-colors hover:text-fg"
          >
            #{change.pr}
          </a>
        </p>
      )}
    </li>
  );
}

function ChangeList({ changes }: { changes: Change[] }) {
  const preview = changes.slice(0, PREVIEW_COUNT);
  const rest = changes.slice(PREVIEW_COUNT);

  return (
    <div>
      <ul className="divide-y divide-border border-y border-border">
        {preview.map((change, index) => (
          <ChangeRow key={change.pr ?? `line-${index}`} change={change} />
        ))}
      </ul>
      {rest.length > 0 && (
        // A closed <details> is still searchable with ⌘F, which a hidden list would not be.
        <details className="group">
          <summary className="mt-4 flex h-10 cursor-pointer list-none items-center justify-center gap-1.5 rounded-full border border-border text-small text-fg-muted transition-colors hover:border-border-strong hover:text-fg group-open:hidden [&::-webkit-details-marker]:hidden">
            {changelogCopy.showMore(rest.length)}
            <ChevronDown size={14} aria-hidden="true" />
          </summary>
          <ul className="divide-y divide-border border-b border-border">
            {rest.map((change, index) => (
              <ChangeRow key={change.pr ?? `more-${index}`} change={change} />
            ))}
          </ul>
        </details>
      )}
    </div>
  );
}

function Contributors({ contributors }: { contributors: Contributor[] }) {
  if (contributors.length === 0) return null;

  return (
    <div className="mt-8">
      <p className="font-mono text-eyebrow uppercase text-fg-muted">
        {changelogCopy.contributors(contributors.length)}
      </p>
      <ul className="mt-3 flex flex-wrap gap-2">
        {contributors.map((contributor) => (
          <li key={contributor.login}>
            <a
              href={`https://github.com/${contributor.login}`}
              target="_blank"
              rel="noreferrer"
              className="inline-flex h-7 items-center gap-1.5 rounded-full px-2.5 font-mono text-caption text-fg-muted shadow-key transition-[color,box-shadow] hover:text-fg hover:shadow-key-hover"
            >
              @{contributor.login}
              <span className="text-fg-subtle">
                {contributor.changes}
                <span className="sr-only">
                  {contributor.changes === 1 ? " change" : " changes"}
                </span>
              </span>
            </a>
          </li>
        ))}
      </ul>
    </div>
  );
}

function ReleaseEntry({
  release,
  latest,
}: {
  release: StableRelease;
  latest: boolean;
}) {
  return (
    <li
      id={release.tag}
      className={cn(
        railRow,
        "scroll-mt-20 not-first:max-md:mt-12 not-first:max-md:border-t not-first:max-md:border-border not-first:max-md:pt-12",
      )}
    >
      {/* Sticks inside its own row, so the version stays in view while its changes scroll. */}
      <header
        className={cn(railLabel, "md:sticky md:top-20 md:self-start md:pb-16")}
      >
        <div className="flex items-center gap-3 md:flex-col md:items-end md:gap-2">
          <h2 className="whitespace-nowrap text-heading tabular-nums">
            <a
              href={`#${release.tag}`}
              className="transition-colors hover:text-violet-bright"
            >
              {release.version}
            </a>
          </h2>
          {latest && (
            <span className="rounded-full bg-violet/15 px-2 py-0.5 font-mono text-micro uppercase text-violet-bright">
              {changelogCopy.latest}
            </span>
          )}
        </div>
        <time
          dateTime={release.publishedAt}
          className="mt-2 block font-mono text-eyebrow uppercase text-fg-subtle"
        >
          {dateFormat.format(new Date(release.publishedAt))}
        </time>
        {release.changes.length > 0 && (
          <p className="mt-4 text-small text-fg-muted">
            {plural(release.changes.length, "change", "changes")}
            {" · "}
            {plural(release.contributors.length, "contributor", "contributors")}
          </p>
        )}
        <ul className="mt-3 flex flex-wrap gap-x-4 gap-y-1 md:flex-col md:items-end">
          <li>
            <ExternalLink href={release.url}>
              {changelogCopy.releaseNotes}
            </ExternalLink>
          </li>
          {release.compareUrl && (
            <li>
              <ExternalLink href={release.compareUrl}>
                {changelogCopy.compare}
              </ExternalLink>
            </li>
          )}
        </ul>
      </header>

      <div className={cn(railBody, "mt-6 md:mt-0 md:pb-16")}>
        <RailDot highlighted={latest} />
        {release.summary && (
          <ReleaseNotes
            notes={release.summary}
            isCard={release.changes.length === 0}
          />
        )}
        {release.changes.length > 0 && <ChangeList changes={release.changes} />}
        <Contributors contributors={release.contributors} />
      </div>
    </li>
  );
}

function EarlierReleases({ releases }: { releases: StableRelease[] }) {
  return (
    <section
      aria-labelledby="earlier-releases"
      className={cn(
        railRow,
        "max-md:mt-12 max-md:border-t max-md:border-border max-md:pt-12",
      )}
    >
      <div className={railLabel}>
        <h2
          id="earlier-releases"
          className="text-subheading font-semibold tracking-[-0.01em]"
        >
          {changelogCopy.earlier.title}
        </h2>
        <p className="mt-2 text-pretty text-small text-fg-subtle">
          {changelogCopy.earlier.body}
        </p>
      </div>
      <div className={cn(railBody, "mt-6 md:mt-0")}>
        <RailDot />
        <ul className="grid gap-2 sm:grid-cols-2 xl:grid-cols-3">
          {releases.map((release) => (
            <li key={release.tag}>
              <a
                href={release.url}
                target="_blank"
                rel="noreferrer"
                className="group flex items-baseline justify-between gap-3 rounded-xl px-4 py-3 shadow-key transition-shadow hover:shadow-key-hover"
              >
                <span className="font-mono text-small text-fg">
                  {release.version}
                </span>
                <time
                  dateTime={release.publishedAt}
                  className="font-mono text-caption text-fg-subtle transition-colors group-hover:text-fg-muted"
                >
                  {dateFormat.format(new Date(release.publishedAt))}
                </time>
              </a>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}

function Intro() {
  return (
    <header className="rise max-w-2xl">
      <p className="font-mono text-eyebrow uppercase text-violet-bright">
        {changelogHero.eyebrow}
      </p>
      <h1 className="mt-4 text-display text-fg">{changelogHero.title}</h1>
      <p className="mt-5 max-w-xl text-pretty text-body-lg text-fg-muted">
        {changelogHero.intro}
      </p>
      <div className="mt-8 flex flex-wrap gap-3">
        <Button href="/docs/install" size="md">
          {changelogCopy.install}
        </Button>
        <Button href={releasesUrl} variant="outline" size="md">
          <GitHubLogo size={15} />
          {changelogCopy.allReleases}
        </Button>
      </div>
    </header>
  );
}

function JumpTo({ releases }: { releases: StableRelease[] }) {
  return (
    <nav
      aria-label={changelogCopy.jumpTo}
      className="mt-14 flex flex-wrap items-center gap-2"
    >
      <span className="mr-2 font-mono text-eyebrow uppercase text-fg-subtle">
        {changelogCopy.jumpTo}
      </span>
      {releases.map((release) => (
        <a
          key={release.tag}
          href={`#${release.tag}`}
          className="inline-flex h-7 items-center rounded-full px-3 font-mono text-caption tabular-nums text-fg-muted shadow-key transition-[color,box-shadow] hover:text-fg hover:shadow-key-hover"
        >
          {release.version}
        </a>
      ))}
    </nav>
  );
}

function Unavailable() {
  return (
    <div className="mt-16 max-w-xl rounded-2xl p-8 shadow-key">
      <h2 className="text-subheading font-semibold">
        {changelogCopy.unavailable.title}
      </h2>
      <p className="mt-2 text-pretty text-small text-fg-muted">
        {changelogCopy.unavailable.body}
      </p>
      <div className="mt-6">
        <Button href={releasesUrl} variant="action" size="md">
          {changelogCopy.allReleases}
          <ArrowUpRight size={14} aria-hidden="true" />
        </Button>
      </div>
    </div>
  );
}

export function Changelog({ releases }: { releases: StableRelease[] | null }) {
  const noted = releases?.filter((r) => r.hasNotes) ?? [];
  const earlier = releases?.filter((r) => !r.hasNotes) ?? [];

  return (
    <>
      <Intro />
      {releases === null || releases.length === 0 ? (
        <Unavailable />
      ) : (
        <>
          {noted.length > 1 && <JumpTo releases={noted} />}
          <ol className="mt-16 sm:mt-20">
            {noted.map((release, index) => (
              <ReleaseEntry
                key={release.tag}
                release={release}
                latest={index === 0 && release === releases[0]}
              />
            ))}
          </ol>
          {earlier.length > 0 && <EarlierReleases releases={earlier} />}
        </>
      )}
    </>
  );
}
