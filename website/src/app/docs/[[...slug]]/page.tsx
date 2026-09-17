import {
  DocsBody,
  DocsDescription,
  DocsPage,
  DocsTitle,
  MarkdownCopyButton,
  ViewOptionsPopover,
} from "fumadocs-ui/layouts/docs/page";
import { notFound } from "next/navigation";
import { site } from "../../../data/site";
import { markdownUrl } from "../../../lib/markdown-url";
import { source } from "../../../lib/source";
import { getMDXComponents } from "../../../mdx-components";

export default async function Page(props: PageProps<"/docs/[[...slug]]">) {
  const params = await props.params;
  const page = source.getPage(params.slug);
  if (!page) notFound();

  const MDX = page.data.body;
  const markdown = markdownUrl(page.url);

  return (
    <DocsPage toc={page.data.toc} full={page.data.full}>
      <DocsTitle>{page.data.title}</DocsTitle>
      {/* The default `mb-8` leaves the actions floating a long way under the
          description; they belong with the heading block, not adrift from it. */}
      <DocsDescription className="mb-4">
        {page.data.description}
      </DocsDescription>
      <div className="flex flex-row items-center gap-2 border-b pb-4">
        <MarkdownCopyButton markdownUrl={markdown} />
        <ViewOptionsPopover
          markdownUrl={markdown}
          githubUrl={`${site.repo}/blob/main/website/content/docs/${page.path}`}
        />
      </div>
      <DocsBody>
        <MDX components={getMDXComponents()} />
      </DocsBody>
    </DocsPage>
  );
}

export function generateStaticParams() {
  return source.generateParams();
}

export async function generateMetadata(props: PageProps<"/docs/[[...slug]]">) {
  const params = await props.params;
  const page = source.getPage(params.slug);
  if (!page) notFound();

  // `trailingSlash` is what the host actually serves, so the canonical has to carry it too.
  const canonical = `${page.url}/`;

  return {
    title: page.data.title,
    description: page.data.description,
    alternates: { canonical },
    openGraph: {
      url: canonical,
      title: page.data.title,
      description: page.data.description,
    },
  };
}
