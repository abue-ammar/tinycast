import { site, summary } from "../../data/site";
import { markdownUrl } from "../../lib/markdown-url";
import { source } from "../../lib/source";

// The llms.txt convention: one Markdown index an agent reads in a single fetch, with each page's
// raw Markdown one link away. Grouped by section, because a flat list of 37 reads as noise.
export const dynamic = "force-static";
export const revalidate = false;

const SECTIONS: Record<string, string> = {
  "": "Start here",
  launcher: "Launcher",
  features: "Features",
  ai: "AI",
  extensions: "Raycast extensions",
  reference: "Reference",
};

export function GET() {
  const grouped = new Map<string, string[]>();

  for (const page of source.getPages()) {
    const segments = page.url.replace("/docs", "").split("/").filter(Boolean);
    // Matching on any segment, so a section's own landing page files under it rather than above it.
    const section = segments.find((segment) => segment in SECTIONS) ?? "";
    const description = page.data.description
      ? `: ${page.data.description}`
      : "";
    const line = `- [${page.data.title}](${site.url}${markdownUrl(page.url)})${description}`;
    grouped.set(section, [...(grouped.get(section) ?? []), line]);
  }

  const body = Object.entries(SECTIONS)
    .filter(([key]) => grouped.has(key))
    .map(
      ([key, heading]) =>
        `## ${heading}\n\n${grouped.get(key)!.sort().join("\n")}`,
    )
    .join("\n\n");

  return new Response(`# ${site.name}\n\n> ${summary}\n\n${body}\n`, {
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
}
