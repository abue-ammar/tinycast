# Action Chains

Action Chains are named, ordered sequences of existing Tinycast actions. They appear in launcher
search and can receive the same global shortcut recorder as other addressable actions.

## Invariants

- A chain stores references, never copied actions: application bundle IDs, fixed action IDs, and the
  stable UUIDs of custom commands and quicklinks.
- The runner starts each step only after the preceding step returns. It stops at the first missing or
  ineligible reference and reports that step to the user.
- Chains only offer targets that do not require typed input. A custom command with arguments, a
  templated quicklink, and a system action requiring confirmation remain available on their own rows,
  but cannot silently acquire input or bypass a confirmation inside a chain.
- State is one `UserDefaults` JSON value. The feature owns no monitor, timer, task, cache, or launch
  work, so an unused chain adds no idle CPU or RAM activity.
- A run is single-flight: a repeated shortcut while a chain is running is ignored. The launcher closes
  once, and window and system steps keep the app that was active when the chain started as their target.
  Launching an application does not wait for it to activate, so it cannot be used as a prerequisite for
  tiling that newly launched app in the same chain.

## Wiring

`ActionChainStore` owns persisted records. `ActionChainCoordinator` projects them into `AppIndex`,
registers UUID-keyed hotkeys through `HotKeyManager`, and owns the serial execution funnel. Deleting a
chain clears its shortcut, favorite, visibility and ranking references with the record.
Settings backup carries chains and their shortcuts with custom commands and quicklinks.

Settings ▸ Action Chains provides the whole editing surface: add a named chain, append eligible actions,
reorder or remove its steps, assign a shortcut, edit, and delete. The editor lists applications, safe
system actions, window commands, argument-free custom commands, and non-templated quicklinks.
