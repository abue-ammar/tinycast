import { Features } from "../components/features";
import { Footer } from "../components/footer";
import { Gallery } from "../components/gallery";
import { Ethos } from "../components/ethos";
import { Hero } from "../components/hero";
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
        </div>
        <Ethos />
        <div className="mx-auto max-w-7xl">
          <Support />
        </div>
      </main>
      <Footer />
      <ScrollTop />
    </>
  );
}
