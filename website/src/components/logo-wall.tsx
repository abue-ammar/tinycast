import { companies } from "../data/site";
import { CompanyLogo } from "./ui/company-logos";

// The list is rendered twice and the track scrolls exactly half its width, so
// the second copy lands where the first started and the loop has no seam.
const track = [...companies, ...companies];

export function LogoWall() {
  return (
    <section
      aria-label="Companies using Tinycast"
      className="border-y border-border bg-tint/2"
    >
      <div className="mx-auto max-w-7xl px-4 py-6 sm:px-10">
        <p className="text-center font-mono text-eyebrow uppercase text-fg-subtle">
          Used every day by people at
        </p>
        <div
          className="mt-4 overflow-hidden"
          style={{
            maskImage:
              "linear-gradient(to right, transparent, #000 12%, #000 88%, transparent)",
          }}
        >
          <ul className="flex w-max animate-marquee items-center gap-16 text-fg-muted">
            {track.map((company, index) => (
              <li
                key={`${company}-${index}`}
                aria-hidden={index >= companies.length}
              >
                <CompanyLogo
                  id={company}
                  className="opacity-70 transition-opacity hover:opacity-100"
                />
              </li>
            ))}
          </ul>
        </div>
      </div>
    </section>
  );
}
