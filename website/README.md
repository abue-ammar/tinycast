# Tinycast website

The marketing page and documentation for Tinycast, at <https://tinycast.dev>.

Next.js (App Router) with a **static export** — there is no server behind the deployed site. Tailwind
v4 for styling, [Fumadocs](https://fumadocs.dev) for the documentation section.

## Develop

```sh
npm install
npm run dev      # http://localhost:3000
```

`npm install` runs `fumadocs-mdx`, which generates `.source/` from `content/docs/`. That directory is
generated and not committed.

## Scripts

| Script           | Does                            |
| ---------------- | ------------------------------- |
| `npm run dev`    | Dev server                      |
| `npm run build`  | Type-check and export to `out/` |
| `npm run lint`   | oxlint                          |
| `npm run format` | Prettier                        |

## Structure

| Path               | Holds                                                                  |
| ------------------ | ---------------------------------------------------------------------- |
| `src/app/`         | Routes. `page.tsx` is the marketing page; `docs/` is the documentation |
| `src/components/`  | Page sections, with shared primitives in `ui/`                         |
| `src/data/`        | All copy and content, so components stay free of prose                 |
| `src/index.css`    | **The only design-token source.** Colors, type scale, shadows          |
| `content/docs/`    | The documentation, as plain Markdown                                   |
| `source.config.ts` | Fumadocs and Shiki configuration                                       |

## Design tokens

`src/index.css` is the single source of truth, and Tailwind's default text and shadow scales are
**disabled** there so an off-scale value cannot slip in. Use the named roles (`text-body`,
`shadow-key`) rather than raw sizes.

Token names are semantic: `canvas` is near-black in Dark and near-white in Light. Dark is the frozen
baseline and Light restates it with the ink inverted — the same rule the app itself follows.

**Any new token must also be registered in `src/lib/cn.ts`.** Its `extendTailwindMerge` call teaches
tailwind-merge about the custom groups; an unregistered `shadow-*` is misclassified as a color and
silently dropped when merged.

## Documentation

One Markdown file per page under `content/docs/`, with a `meta.json` per folder controlling sidebar
order. Adding a page means adding a file and a line.

Shiki highlighting is limited to `bash`, `json` and `markdown` in `source.config.ts`. Keep it that
way — highlighting a keyboard shortcut or a placeholder buys nothing and costs bytes. Keyboard keys
use `<kbd>`, which renders through the same keycap component as the marketing page.

## Deploy

Pushes to `main` touching `website/**` run `.github/workflows/website.yml`, which does two
independent things.

**Cloudflare — the live site.** `npm run build` exports to `out/`, and `wrangler deploy` publishes it
as an assets-only Worker (`wrangler.jsonc`): no `main`, so nothing runs in the request path. The
apex `tinycast.dev` is the Worker's only custom domain; `www` is a redirect rule in the Cloudflare
dashboard rather than a second origin. The workflow needs `CLOUDFLARE_API_TOKEN` and
`CLOUDFLARE_ACCOUNT_ID` repo secrets.

**GitHub Pages — the forwarder.** The site used to live at `abue-ammar.github.io/tinycast/`, and
`redirect/` is what is published there now: a `CNAME` file and nothing else. A custom domain on a
project site makes GitHub 301 `abue-ammar.github.io/tinycast/<path>` to `tinycast.dev/<path>` from
its own edge — the repo prefix stripped, the rest of the path, query and fragment carried across,
and no HTML parsed or JavaScript run. GitHub's `Location` names `http://`, which costs nothing: the
whole `.dev` TLD is HSTS-preloaded, so browsers upgrade it before the request leaves. **Settings →
Pages → Custom domain must read `tinycast.dev`**; the file alone is not enough, and GitHub will
warn that the DNS does not point at Pages, which is correct and can be ignored — the redirect is
served from `github.io`, not from the custom domain. That job is deliberately separate from the
Cloudflare one: a failed deploy must not take the forwarder down with it.

**R2 — big media.** Workers refuses any single asset over 25 MiB, which the 26.5 MiB tour video
breaks. Media that size lives in `media/` rather than `public/`, so `next build` never copies it
into `out/`, and is served from the `tinycast-cdn` R2 bucket behind `cdn.tinycast.dev` — a public
bucket on a custom domain, so nothing runs in the request path there either. `site.cdn` is the only
place that host is written.

`.github/workflows/website-media.yml` mirrors the folder on every push that touches it, running the
same `Scripts/upload-website-media.sh` you can run locally with `npm run upload-media`. It is a
separate workflow so GitHub's path filter can stop a docs typo from re-uploading tens of megabytes.

**To add a video:** drop it in `media/`, point a `galleryItems` entry at
`` `${site.cdn}/<name>` ``, push. If its extension is new, add the content type to the script — it
stops rather than guess, because R2 would otherwise serve it as `octet-stream` and `<video>` would
refuse to play it.

The site is served from the domain root, so there is no `basePath` and a file in `public/` is
referenced as `/name.png` directly. To test the exported shape rather than the dev server:

```sh
npm run build
cd out && python3 -m http.server 4321   # http://localhost:4321/
```
