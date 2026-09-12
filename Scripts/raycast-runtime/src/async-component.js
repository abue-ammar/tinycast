// Raycast extensions render async components — `withAccessToken` hands the wrapped command straight
// to `jsx` — and React only replays one on its concurrent path, where the thenable it suspended on
// survives the attempt. A sync render drops it, so every retry suspended on a fresh promise (#519).

import { use, useRef, useState } from "react";

const components = new WeakMap();

export function resolveComponent(type) {
  if (typeof type !== "function") return type;
  let component = components.get(type);
  if (component === undefined) {
    component = type.constructor?.name === "AsyncFunction" ? adapt(type) : type;
    components.set(type, component);
  }
  return component;
}

/// Committing nothing first is what keeps the hooks `type` mounts: unwinding a fiber that never
/// committed discards the state its own tree closes over.
function adapt(type) {
  const component = (props) => {
    const [mounted, setMounted] = useState(false);
    const pending = useRef(null);
    const next = Promise.resolve(type(props));
    if (!mounted) {
      const ready = () => setMounted(true);
      next.then(ready, ready);
      return null;
    }
    if (pending.current === null) pending.current = next;
    else next.catch(() => {});
    const children = use(pending.current);
    pending.current = null;
    return children;
  };
  return component;
}
