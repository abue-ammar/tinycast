import type { Company } from "../../data/site";
import { cn } from "../../lib/cn";
import { AppleLogo } from "./icon";

// Monochrome wordmarks drawn with currentColor, each around 22px tall, so the
// wall reads as one row of type rather than a strip of brand colours.
function AppleMark() {
  return (
    <span className="inline-flex items-center gap-1.5">
      <AppleLogo size={21} />
      <span className="text-[19px] font-medium tracking-tight">Apple</span>
    </span>
  );
}

function GoogleMark() {
  return (
    <span className="text-[22px] font-medium tracking-[-0.02em]">Google</span>
  );
}

function MicrosoftMark() {
  return (
    <span className="inline-flex items-center gap-2">
      <svg
        viewBox="0 0 24 24"
        className="size-[18px]"
        fill="currentColor"
        aria-hidden="true"
      >
        <rect x="1" y="1" width="10" height="10" />
        <rect x="13" y="1" width="10" height="10" opacity="0.8" />
        <rect x="1" y="13" width="10" height="10" opacity="0.8" />
        <rect x="13" y="13" width="10" height="10" opacity="0.6" />
      </svg>
      <span className="text-[19px] font-semibold tracking-[-0.01em]">
        Microsoft
      </span>
    </span>
  );
}

function OracleMark() {
  return (
    <span className="text-[18px] font-bold uppercase tracking-[0.08em]">
      Oracle
    </span>
  );
}

function ByteDanceMark() {
  return (
    <span className="inline-flex items-center gap-2">
      <svg
        viewBox="0 0 24 24"
        className="size-[18px]"
        fill="currentColor"
        aria-hidden="true"
      >
        <rect x="2" y="9" width="3.5" height="9" rx="0.5" />
        <rect x="7.5" y="4" width="3.5" height="16" rx="0.5" />
        <rect x="13" y="8" width="3.5" height="10" rx="0.5" />
        <rect x="18.5" y="2" width="3.5" height="20" rx="0.5" />
      </svg>
      <span className="text-[19px] font-semibold tracking-tight">
        ByteDance
      </span>
    </span>
  );
}

function YandexMark() {
  return (
    <span className="inline-flex items-center gap-1.5">
      <span className="grid size-[22px] place-items-center rounded-full bg-current">
        <span className="text-[13px] font-bold leading-none text-canvas">
          Y
        </span>
      </span>
      <span className="text-[19px] font-semibold tracking-tight">Yandex</span>
    </span>
  );
}

function RedHatMark() {
  return (
    <span className="inline-flex items-center gap-2">
      <svg
        viewBox="0 0 24 24"
        className="h-[18px] w-[22px]"
        fill="currentColor"
        aria-hidden="true"
      >
        <path d="M3 14.5c0-1.2 1.5-2 4.2-2 .8 0 1.5.1 2.1.3l1.1-3.9c.3-1 1.1-1.6 2.1-1.6h.8c1.3 0 2.2.9 2.6 2.1l1 3.4c.5-.2 1.1-.3 1.8-.3 2.4 0 3.3.8 3.3 1.8 0 2.3-4.5 3.7-9.1 3.7S3 16.8 3 14.5Z" />
      </svg>
      <span className="text-[19px] font-semibold tracking-tight">Red Hat</span>
    </span>
  );
}

const marks: Record<Company, () => React.JSX.Element> = {
  apple: AppleMark,
  google: GoogleMark,
  microsoft: MicrosoftMark,
  oracle: OracleMark,
  bytedance: ByteDanceMark,
  yandex: YandexMark,
  redhat: RedHatMark,
};

export function CompanyLogo({
  id,
  className,
}: {
  id: Company;
  className?: string;
}) {
  const Mark = marks[id];
  return (
    <span
      className={cn(
        "inline-flex items-center whitespace-nowrap leading-none",
        className,
      )}
    >
      <Mark />
    </span>
  );
}
