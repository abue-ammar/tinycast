import { createFromSource } from "fumadocs-core/search/server";
import { source } from "../../../lib/source";

// The index is emitted as a static file at build time — the site is a static export with no
// server to run a search route, so `staticGET` is the only shape that works.
export const revalidate = false;
export const { staticGET: GET } = createFromSource(source);
