"use client";

import { ThemeProvider } from "next-themes";
import type { ReactNode } from "react";

// Only the theme is global. Fumadocs' own RootProvider — which pulls in the
// search context and its dialog — is mounted in the docs layout instead, so
// the marketing page never pays for machinery it has no use for.
export function Providers({ children }: { children: ReactNode }) {
  return (
    <ThemeProvider
      attribute="class"
      defaultTheme="dark"
      // Dark only for now; drop this to bring back Light and the toggles.
      forcedTheme="dark"
      enableSystem
      disableTransitionOnChange
    >
      {children}
    </ThemeProvider>
  );
}
