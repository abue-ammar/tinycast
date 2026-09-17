import { MARKDOWN_LEAF } from "./source";

/** Where a page's raw Markdown lives — see the route in `app/llms.md/docs`. */
export function markdownUrl(pageUrl: string): string {
  const slug = pageUrl.replace(/^\/docs\/?/, "");
  return `/llms.md/docs/${slug ? `${slug}/` : ""}${MARKDOWN_LEAF}`;
}
