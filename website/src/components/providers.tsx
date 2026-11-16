"use client";

import { ThemeProvider } from "next-themes";
import type { ReactNode } from "react";

// Only the theme is global. Fumadocs' RootProvider is mounted by the docs layout
// and the site nav, the two places that use its search and drawer.
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
