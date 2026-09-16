import { Features } from "../components/features";
import { Footer } from "../components/footer";
import { Gallery } from "../components/gallery";
import { Hero } from "../components/hero";
import { Install } from "../components/install";
import { Keyboard } from "../components/keyboard";
import { LogoWall } from "../components/logo-wall";
import { Nav } from "../components/nav";
import { Privacy } from "../components/privacy";
import { Support } from "../components/support";
import { Switch } from "../components/switch";
import { ScrollTop } from "../components/ui/scroll-top";

export default function HomePage() {
  return (
    <>
      <Nav />
      {/* The hero's grid and the logo wall both reach the window edges and set
          their own inner width, so the page width lives on the group below. */}
      <main>
        <Hero />
        <LogoWall />
        <div className="mx-auto max-w-7xl">
          <Features />
          <Gallery />
          <Privacy />
          <Keyboard />
          <Switch />
          <Install />
          <Support />
        </div>
      </main>
      <Footer />
      <ScrollTop />
    </>
  );
}
