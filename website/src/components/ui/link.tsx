import NextLink from "next/link";
import type { ComponentProps } from "react";

type Props = Omit<ComponentProps<typeof NextLink>, "href"> & { href: string };

/**
 * Internal links, including in-page anchors. External URLs fall through to a
 * plain anchor with the usual rel guard.
 */
export function Link({ href, ...props }: Props) {
  if (/^(https?:|mailto:|#)/.test(href)) {
    const external = href.startsWith("http");
    return (
      <a
        href={href}
        {...(external ? { target: "_blank", rel: "noreferrer" } : {})}
        {...props}
      />
    );
  }

  return <NextLink href={href} {...props} />;
}
