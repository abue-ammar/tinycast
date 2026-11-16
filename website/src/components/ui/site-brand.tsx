import { site } from "../../data/site";
import { Logo } from "./icon";
import { Link } from "./link";

export function SiteBrand() {
  return (
    <Link href="/" className="flex items-center gap-2">
      <Logo size={24} />
      <span className="font-rounded text-title font-semibold text-fg">
        {site.name}
      </span>
    </Link>
  );
}
