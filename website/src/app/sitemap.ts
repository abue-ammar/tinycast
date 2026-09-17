import type { MetadataRoute } from "next";
import { site } from "../data/site";
import { source } from "../lib/source";

// Generated from the docs tree, so a new page is listed the moment it exists.
// `dynamic` must stay "force-static": an export has no request to respond to.
export const dynamic = "force-static";

export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date();

  return [
    { url: `${site.url}/`, lastModified: now, priority: 1 },
    ...source.getPages().map((page) => ({
      url: `${site.url}${page.url}/`,
      lastModified: now,
      priority: 0.7,
    })),
  ];
}
