# Dictionary

`Define Word` is a launcher command and a fallback. The command opens the dictionary screen (`.dictionary`)
empty; the fallback opens it on whatever was typed. The search field stays the term, so a different
word is one edit away. Everything is read from the dictionaries enabled in Dictionary.app — no network,
no bundled word list.

## Invariants

- **The command gates the fallback, never the reverse.** Define Word has no feature pane, so
  Settings › Commands is its switch: while the command is hidden there — itself or the whole Commands
  category — `FallbackCoordinator` offers no Define Word fallback and Settings › Fallbacks does not
  list it. While it is visible, the fallback's own checkbox hides just the fallback, leaving the
  command searchable.
- **The page comes from an undocumented call, resolved at run time.** The public
  `DCSCopyTextDefinition` returns one unbroken line, so `DictionaryService` asks for the record's XHTML
  through `DCSGetActiveDictionaries`, `DCSCopyRecordsForSearchString` and `DCSRecordCopyData` — what
  Dictionary.app itself reads. They are found with `dlsym`, never linked: a macOS that drops one loses
  the layout and falls back to the public plain text, rather than failing to launch.
- **The span classes are the only structure, and `DictionaryMarkup` is the only reader of them.**
  `hg` is the headword, `posg` the part of speech, `se2` a numbered sense, `msDict` (`msThes` in a
  thesaurus) its definition or a `t_subsense` bullet, `note` an aside, `x_xoLblBlk` a section label
  (`ORIGIN`, `PHRASES`). Every Oxford bilingual pair (Chinese, Japanese, Korean, Vietnamese, French,
  Spanish, German, …) shares a second schema mapped onto the same blocks: `hwg` the headword,
  `gramb` the part of speech, `semb` a sense numbered by its `ty_label tg_semb` or `sn`, `exg` an
  example, `idm`/`pvg`/`cwg`/`drvg` a phrase under an `IDIOMS`-style label. An `sn` inside an example
  is its bullet, never a sense number. Line breaks follow each dictionary's own `DefaultStyle.css`:
  `x_xo1` is a block everywhere, and examples after a definition with no colon (Duden) start their
  own line. The bilingual stylesheets separate spans by margin alone, so `DictionaryMarkup` restores
  the word break before a translation or indicator. An example sits tight under its sense, the way
  the stylesheets space `exg`. Unknown markup reads as plain text in the nearest block, so a format
  change degrades rather than drops words. A record built from the plain Dictionary Development Kit
  template has no classes at all, so its `h1` is the headword and each `p` a paragraph.
  `dictionary-test` holds real records from each schema as its fixtures.
- **Dictionary is the default scope, and it is the lookup that always was.** The header's selector
  (⌘P) switches to Thesaurus, which asks only the enabled dictionaries whose `CFBundleName` names a
  thesaurus — no Info.plist key marks one — and skips the public plain-text fallback, which reads
  every dictionary. The selector shows only while a thesaurus is enabled in Dictionary.app, re-read
  each time the screen opens. The scope lives on `DictionarySession` until quit, never on disk.
- **Lookups run off the main actor.** A long entry (`run`, `take`) is a few hundred blocks, so
  `DictionarySession` debounces the query and looks it up detached, the way `FileSearchSession` does.
  The previous page stays up until the next resolves, and ↵ and ⌘K act on that page — what is shown
  is what is copied — so neither the page nor the footer flickers while typing.

## Actions

| Key | Does |
| --- | --- |
| ↵ | Copy Definition — the whole entry, one line per block, then the palette closes |
| ⌘↵ | Open in Dictionary — `dict://<term>`, for every other enabled dictionary |

The first enabled dictionary that knows the term answers, in Dictionary.app's own order, unless the
header's selector (⌘P) is set to Thesaurus. A term none of them knows reads "No definition found".
