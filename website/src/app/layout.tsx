import "../index.css";

import type { Metadata } from "next";
import { Geist, Geist_Mono, Instrument_Serif } from "next/font/google";
import localFont from "next/font/local";
import { Providers } from "../components/providers";
import { pageTitle, site, summary } from "../data/site";

// next/font self-hosts these at build time and generates a metric-matched
// fallback for each, so there is no third-party request and no layout shift.
const geist = Geist({ subsets: ["latin"], variable: "--font-geist" });
const geistMono = Geist_Mono({
  subsets: ["latin"],
  variable: "--font-geist-mono",
});
// The heading face. Apple's licence does not cover serving it; the owner chose to anyway.
const sfRounded = localFont({
  src: [
    { path: "../fonts/sf-pro-rounded-regular.woff2", weight: "400" },
    { path: "../fonts/sf-pro-rounded-medium.woff2", weight: "500" },
    { path: "../fonts/sf-pro-rounded-bold.woff2", weight: "700" },
  ],
  variable: "--font-sf-rounded",
  display: "swap",
});
// One display face, for the ethos pull quote and nothing else. Both styles are
// loaded because the quote sets its last sentence in italic.
const instrumentSerif = Instrument_Serif({
  subsets: ["latin"],
  weight: "400",
  style: ["normal", "italic"],
  variable: "--font-instrument-serif",
});

export const metadata: Metadata = {
  metadataBase: new URL(site.url),
  title: {
    default: pageTitle,
    template: "%s · Tinycast",
  },
  description: summary,
  applicationName: site.name,
  alternates: { canonical: "/" },
  openGraph: {
    type: "website",
    siteName: site.name,
    url: site.url,
    locale: "en_US",
    title: pageTitle,
    description: summary,
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
    title: pageTitle,
    description: summary,
    images: ["/og.png"],
  },
  robots: { index: true, follow: true },
  icons: { icon: "/favicon.svg" },
};

const structuredData = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: site.name,
  description: summary,
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
      className={`dark ${geist.variable} ${geistMono.variable} ${sfRounded.variable} ${instrumentSerif.variable}`}
      data-scroll-behavior="smooth"
      suppressHydrationWarning
    >
      <head>
        <meta name="color-scheme" content="dark" />
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
