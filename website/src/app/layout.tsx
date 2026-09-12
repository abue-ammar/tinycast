import "../index.css";

import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { Providers } from "../components/providers";
import { site } from "../data/site";
import { asset } from "../lib/asset";

// next/font self-hosts these at build time and generates a metric-matched
// fallback for each, so there is no third-party request and no layout shift.
const geist = Geist({ subsets: ["latin"], variable: "--font-geist" });
const geistMono = Geist_Mono({
  subsets: ["latin"],
  variable: "--font-geist-mono",
});

const description =
  "Tinycast is a tiny, fully native macOS launcher: fuzzy app search, an inline calculator, clipboard history, snippets, notes, window management and global hotkeys, with no Electron, no account and no telemetry.";

export const metadata: Metadata = {
  metadataBase: new URL(site.url),
  title: {
    default: "Tinycast — a tiny, native macOS launcher",
    template: "%s — Tinycast",
  },
  description,
  applicationName: site.name,
  alternates: { canonical: "/" },
  openGraph: {
    type: "website",
    siteName: site.name,
    url: site.url,
    locale: "en_US",
    title: "Tinycast — a tiny, native macOS launcher",
    description,
    images: [
      {
        url: "/og.png",
        width: 1200,
        height: 630,
        alt: "The Tinycast command palette open over a macOS desktop, showing fuzzy app search.",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Tinycast — a tiny, native macOS launcher",
    description,
    images: ["/og.png"],
  },
  robots: { index: true, follow: true },
  icons: { icon: asset("favicon.svg") },
};

const structuredData = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: site.name,
  description,
  url: site.url,
  image: `${site.url}/og.png`,
  applicationCategory: "UtilitiesApplication",
  operatingSystem: site.platform,
  license: "https://www.gnu.org/licenses/agpl-3.0.html",
  offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    // suppressHydrationWarning: next-themes writes the theme class onto <html>
    // before React hydrates, which is the whole point — it prevents the flash.
    // data-scroll-behavior: Next reads this to switch smooth scrolling off for
    // the duration of a route change. Without it the scroll reset animates
    // against the incoming page and you land part-way down the new one.
    <html
      lang="en"
      className={`${geist.variable} ${geistMono.variable}`}
      data-scroll-behavior="smooth"
      suppressHydrationWarning
    >
      <head>
        <meta name="color-scheme" content="light dark" />
        <script
          type="application/ld+json"
          // eslint-disable-next-line react/no-danger
          dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData) }}
        />
      </head>
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
