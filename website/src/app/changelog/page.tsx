import type { Metadata } from "next";
import { Changelog } from "../../components/changelog";
import { Footer } from "../../components/footer";
import { Nav } from "../../components/nav";
import { ScrollTop } from "../../components/ui/scroll-top";
import { changelogCopy } from "../../data/changelog";
import { ogImage } from "../../data/site";
import { stableReleases } from "../../lib/changelog";

export const metadata: Metadata = {
  title: "Changelog",
  description: changelogCopy.description,
  alternates: { canonical: "/changelog/" },
  openGraph: {
    title: "Tinycast Changelog",
    description: changelogCopy.description,
    url: "/changelog/",
    images: [ogImage],
  },
};

export default async function ChangelogPage() {
  const releases = await stableReleases();

  return (
    <>
      <Nav />
      <main className="mx-auto max-w-7xl px-4 pb-24 pt-12 sm:px-10 sm:pt-20">
        <Changelog releases={releases} />
      </main>
      <Footer />
      <ScrollTop />
    </>
  );
}
