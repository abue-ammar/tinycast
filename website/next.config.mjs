import { createMDX } from "fumadocs-mdx/next";

const withMDX = createMDX();

/** @type {import('next').NextConfig} */
const config = {
  // Cloudflare serves the exported files directly — there is no Node process behind this site.
  output: "export",
  // The Image Optimization API needs a server, which an export does not have.
  images: { unoptimized: true },
  // Emits /docs/palette/index.html, the only shape a static host can serve.
  trailingSlash: true,
  reactCompiler: true,
};

export default withMDX(config);
