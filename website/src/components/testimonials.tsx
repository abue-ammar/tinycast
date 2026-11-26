import Image from "next/image";
import type { CSSProperties } from "react";
import { postUrl, testimonials, type Testimonial } from "../data/testimonials";
import { TestimonialsFold } from "./testimonials-fold";
import { XLogo } from "./ui/icon";
import { Section } from "./ui/section";

type PlacedPost = { post: Testimonial; tilt: number };

// Small and alternating, so the wall reads as pinned up rather than knocked over.
const tilts = [-1.1, 0.8, -0.5, 1, -0.8, 0.6, -1.2, 0.4, -0.7, 1.1, -0.4];

const placed: PlacedPost[] = testimonials.map((post, index) => ({
  post,
  tilt: tilts[index % tilts.length],
}));

// UTC, so the static export and the visitor's clock never disagree about the day.
const postDate = new Intl.DateTimeFormat("en", {
  month: "short",
  day: "numeric",
  year: "numeric",
  timeZone: "UTC",
});

// A card's height in text lines, so columns end level without the DOM. Fitted to the rendered
// cards: about 44 characters a line, a blank line between paragraphs, 5.5 lines of chrome.
function estimatedLines({ text, link }: Testimonial) {
  return `${text} ${link ?? ""}`
    .trimEnd()
    .split("\n\n")
    .reduce(
      (lines, paragraph) => lines + Math.ceil(paragraph.length / 44) + 1,
      4.5,
    );
}

// Each card joins the shortest column so far, which also keeps the first few on the top row.
function toColumns(posts: PlacedPost[], count: number) {
  const columns: PlacedPost[][] = Array.from({ length: count }, () => []);
  const heights: number[] = Array(count).fill(0);
  for (const item of posts) {
    const shortest = heights.indexOf(Math.min(...heights));
    columns[shortest].push(item);
    heights[shortest] += estimatedLines(item.post);
  }
  return columns;
}

// CSS cannot reflow a masonry across breakpoints, so each width gets its own arrangement. The
// ones not shown are display: none, which keeps them out of the tab order and the a11y tree.
const layouts = [
  { className: "flex sm:hidden", columns: toColumns(placed, 1) },
  { className: "hidden sm:flex lg:hidden", columns: toColumns(placed, 2) },
  { className: "hidden lg:flex", columns: toColumns(placed, 3) },
];

function PostCard({ post, tilt }: PlacedPost) {
  return (
    <a
      href={postUrl(post)}
      target="_blank"
      rel="noreferrer"
      style={{ "--tilt": `${tilt}deg` } as CSSProperties}
      className="group flex flex-col gap-3 rounded-2xl bg-surface p-4 shadow-key rotate-(--tilt) transition-[rotate,box-shadow] duration-300 ease-(--ease-settle) hover:rotate-0 hover:shadow-key-hover focus-visible:rotate-0"
    >
      <span className="flex items-center gap-3">
        <Image
          src={post.avatar}
          alt=""
          width={36}
          height={36}
          className="size-9 shrink-0 rounded-full ring-1 ring-border"
        />
        <span className="flex min-w-0 flex-1 flex-col">
          <span className="truncate text-small font-semibold leading-snug text-fg">
            {post.name}
          </span>
          <span className="truncate font-mono text-caption leading-snug text-fg-subtle">
            @{post.handle}
          </span>
        </span>
        <XLogo
          size={14}
          className="shrink-0 self-start text-fg-subtle transition-colors group-hover:text-fg"
        />
      </span>

      <span className="whitespace-pre-line text-pretty text-small text-fg">
        {post.text}
        {post.link && (
          <>
            {" "}
            <span className="text-violet-bright">{post.link}</span>
          </>
        )}
      </span>

      <span className="flex flex-wrap gap-x-2 font-mono text-micro uppercase text-fg-subtle">
        <time dateTime={post.postedAt}>
          {postDate.format(new Date(post.postedAt))}
        </time>
        {post.translatedFrom && (
          <>
            <span aria-hidden="true">·</span>
            <span>Translated from {post.translatedFrom}</span>
          </>
        )}
      </span>
    </a>
  );
}

export function Testimonials() {
  return (
    <Section
      id="testimonials"
      index={6}
      label="Word of mouth"
      title="In their own words."
      intro="What people post about Tinycast on X. Each card opens the original post."
    >
      <TestimonialsFold count={testimonials.length}>
        {layouts.map((layout) => (
          <div
            key={layout.className}
            className={`items-start gap-4 ${layout.className}`}
          >
            {layout.columns.map((column) => (
              <ul
                key={column[0].post.id}
                className="flex min-w-0 flex-1 flex-col gap-4"
              >
                {column.map((item) => (
                  <li key={item.post.id}>
                    <PostCard {...item} />
                  </li>
                ))}
              </ul>
            ))}
          </div>
        ))}
      </TestimonialsFold>
    </Section>
  );
}
