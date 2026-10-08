# 09 — SwiftUI dependency ownership and TextKit 2

Status: proposed. [Audit index](README.md). Read [UI rules](../ui.md),
[AI invariants](../features/ai.md) and [Notes invariants](../features/notes.md).

## Findings

| ID | Confirmed pattern | Priority | Difficulty | Risk |
| --- | --- | --- | --- | --- |
| V01 | Feature views frequently obtain action coordinators through `@Environment(AppCore.self)` or a passed core instead of the coordinator itself | P2 | Medium–High across surfaces | Medium |
| V02 | [ChatSelectableTextView](../../Tinycast/Features/AI/UI/ChatMarkdownText.swift#L61) explicitly creates TextKit 1 layout managers for display and measurement | P2 | High | High |

There are 28 files with an AppCore environment property. This is a dependency/ownership concern, not
evidence that Observation itself is outdated. TextKit 1 is an older architecture; its use here is not
a confirmed compiler deprecation or a reproduced text bug.

## V01 — Reach the existing coordinator directly

The user-supplied/root AGENTS.md says views reach the feature coordinator through Environment rather
than AppCore. [architecture.md](../architecture.md#single-owner-core) currently describes AppCore as
the view's locator. This is a real policy/documentation discrepancy; follow the current AGENTS.md
when implementing this plan and reconcile the architecture document in that change.

Examples are [QuicklinksSettingsView](../../Tinycast/Features/Quicklinks/Settings/QuicklinksSettingsView.swift#L6),
[SnippetsSettingsView](../../Tinycast/Features/Snippets/Settings/SnippetsSettingsView.swift#L4),
[LauncherScreen](../../Tinycast/Features/Launcher/UI/LauncherScreen.swift#L240), and
[RootPaletteView](../../Tinycast/Palette/RootPaletteView.swift#L4).

1. Begin with one feature's settings view. Inject its existing coordinator at the established
   composition site and call it directly. Read feature state through existing narrow dependencies.
2. Use type-based Environment for existing Observable coordinators; a concrete key-based environment
   is appropriate where the coordinator is intentionally not Observable. Do not add fake observable
   state solely to satisfy injection or build a second dependency container.
3. Keep policy and mutation on that coordinator. Move any remaining delete/enable/validation decisions
   out of view event handlers using the existing action methods; a view's bindings and presentation
   state remain declarative.
4. Update palette/settings/window hosting injection together, including extension menus and standalone
   windows. Missing injections are runtime failures, not compile errors. Preserve lazy feature startup;
   do not instantiate every AppCore coordinator merely to populate an environment.
5. Audit every actual view tree before changing a dependency. Existing constructor-injected screens
   need no new parallel action owner. The composition boundary may still use AppCore to supply them.

Keep AppCore as sole long-lived owner and its hotkey/composition wiring intact. Large view files alone
do not justify a new ViewModel; extract a focused subview only when it removes real responsibilities.
Keep Extensions' renderers and layout primitives inside Extensions, even if another view looks similar.

## V02 — Chat rendering on TextKit 2

The current text view creates two `NSLayoutManager` instances, asks for glyph ranges to locate search
matches/code blocks, and keeps a second text container for SwiftUI measurement. Its renderer also
uses custom code-block/table layout and
[MathAttachmentCell](../../Tinycast/Features/AI/UI/MathAttachmentCell.swift) for formula drawing.
Notes already uses NSTextLayoutManager and layout fragments as a native local precedent, but its
editor behavior is different; do not turn it into a shared chat/editor abstraction.

Apple's [TextKit 2 introduction](https://developer.apple.com/videos/play/wwdc2021/10061/) explains the
modern range/fragment model, and
[TextKit and text-view updates](https://developer.apple.com/videos/play/wwdc2022/10090/) explain
adoption and compatibility concerns.

Start with a bounded prototype in the existing AI UI feature:

1. Build the content/layout/container chain using TextKit 2 and prove that the actual text view stays
   in that mode. Calling legacy `layoutManager` APIs can trigger compatibility behavior; merely
   changing an initializer is insufficient.
2. Map the renderer's existing character ranges to NSTextRange and fragment/segment geometry.
   Replace glyph-range calculations for find anchors and code-header placement without changing the
   renderer's source/citation identities.
3. Prove code blocks, tables, links, citations and math parity before porting the complete view.
   Attachment-cell and text-block behavior may require TextKit 2 attachment providers or feature-local
   layout fragments. Check those capabilities concretely instead of assuming old customizations carry
   across unchanged.
4. Keep SwiftUI measurement separate from mutation of the live text layout. Measure a value/snapshot
   or a dedicated modern layout as necessary; do not rewrap the visible text during `sizeThatFits`.
5. Preserve selections while streaming/finalizing a response and avoid rebuilding attributed text
   when the source is unchanged. Preserve math's LaTeX copy/drag content, code-copy buttons, VoiceOver,
   find scrolling, multiple-selection behavior and the transcript's external scroll owner.
6. After parity and measurement pass, remove the old display/measuring managers and geometry helpers
   in the same migration. Do not ship both renderers or add an OS compatibility branch.

Prototype risk is high because this is a rendering engine change, not a naming cleanup. If a required
table or attachment behavior has no satisfactory implementation, record the specific blocker and
revisit the design before expanding the change. No forced replacement with SwiftUI Text: it does not
establish current selection, equation or overlay parity.

## Validation and completion

For V01, run affected coordinator harnesses, `quicklink-coordinator-test`, `settings-history-test`,
`palette-navigation-test`, `palette-tab-test`, `ext-accessory-test` and the full suite/build. Manually
open each changed surface independently, including first-use lazy features and Debug startup. Verify
that all action paths still reach the same owner and confirmation gates.

For V02, run `chat-markdown-test`, `ai-chat-test`, `text-diff-test` and the full suite/build. Existing
parser tests do not prove layout parity. Add targeted native layout coverage for the geometry that
changes. Check streamed text, long code, tables, display/inline equations, links, citations, Arabic,
Bengali, CJK, emoji, ligatures, RTL selection, resizing, font/interface size and both appearances.

Measure long-response layout/scroll time, allocations and repeated open/close memory against the
current renderer. Preserve dark tokens and leave EdgeDissolve/ThinScrollbar untouched. Arrange an
idle window for interactive tests. Done when views depend on their real action owners and the chat
view uses TextKit 2 throughout with equivalent behavior and no measured latency/memory regression.

Keep dependency injection and text rendering in separate PRs. Revert the rendering change if parity
fails; do not retain a production dual-renderer fallback.
