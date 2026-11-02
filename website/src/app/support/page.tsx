import type { Metadata } from "next";
import { Footer } from "../../components/footer";
import { Nav } from "../../components/nav";
import { SupportFlow } from "../../components/support/support-flow";
import { SupporterCount } from "../../components/support/supporter-count";
import { supportHero } from "../../data/support";

const description =
  "Enjoying Tinycast? Buy the wallpaper pack and get an exclusive Discord role, or support Tinycast with crypto. Tinycast remains free and open source.";

export const metadata: Metadata = {
  title: "Enjoying Tinycast?",
  description,
  alternates: { canonical: "/support/" },
  openGraph: { title: "Enjoying Tinycast?", description, url: "/support/" },
};

function Intro() {
  return (
    <header>
      <p className="blur-in font-mono text-eyebrow uppercase text-violet-bright">
        {supportHero.eyebrow}
      </p>
      <h1
        className="blur-in mt-4 text-display text-fg"
        style={{ animationDelay: "60ms" }}
      >
        {supportHero.title}
      </h1>
      <p
        className="blur-in mt-5 max-w-xl text-pretty text-body-lg text-fg-muted"
        style={{ animationDelay: "120ms" }}
      >
        {supportHero.intro}
      </p>
      <SupporterCount />
    </header>
  );
}

export default function SupportPage() {
  return (
    <div className="flex min-h-dvh flex-col">
      <Nav />
      <main className="relative flex-1">
        <div
          aria-hidden="true"
          className="bg-grid pointer-events-none absolute inset-0"
        />
        <div className="relative mx-auto w-full max-w-7xl px-4 pb-24 pt-12 sm:px-10 sm:pt-20">
          <SupportFlow intro={<Intro />} />
        </div>
      </main>
      <Footer />
    </div>
  );
}
