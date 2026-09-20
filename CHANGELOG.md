# Changelog

Notable changes, newest first. Earlier entries are summarised from their
[release notes](https://github.com/kemalandic/edgecontrol/releases).

## 2.5.0

The dashboard learned to be written in. Alongside that, the contributions that
had been waiting in pull requests are merged, and the project grew the test
suite and CI it should have had already. This release carries the work that was
prepared as 2.4.0 but never published.

### Notes

The Sticky Note widget arrived as a contribution and has become the reason to
keep the app open rather than glance at it.

**Notes are files now.** They used to be base64 RTF inside the layout document,
which meant a note died with the widget showing it, nothing could read one
without loading the dashboard, and every debounced keystroke rewrote the file
holding every page, placement and setting. They live in
`Application Support/EdgeControl/Notes/` as real RTF — openable in TextEdit —
with a plain-text mirror Spotlight indexes and the last twenty versions of each
kept beside them. Backing up that folder backs up the notes, with no export step
and nothing to decode. Existing notes migrate on first launch, including ones
written before the editor was rich text.

**The editor.** Markup converts as you type: `- ` for a bullet, `- [ ] ` for a
to-do, `# ` for a heading, `---` for a rule, `` `code` `` for a chip, ```` ``` ````
for a block. A slash at the start of a line offers the same things as a menu, and
selecting text raises a formatting bar — both there because the panel is usually
reached without a keyboard in front of it, and a menu bar the kiosk window does
not show is no answer for the person standing at the screen.

**Markdown in both directions.** Paste markdown and it becomes a note; ⌘⇧C copies
a note, or a selection, back out. Recognising a paste is deliberately hard to
trigger: emphasis alone does not count, because prose is full of asterisks and
restyling somebody's pasted paragraph over `2 * 3 * 4` is worse than not
converting at all. **Export Notes** in General writes every note as Markdown with
its images alongside, so the exported folder stands on its own.

**Images** paste in and live next to the note rather than inside it. RTF carries
no images, and the alternative was to change the storage format to a package —
which would have ended "open the folder and there are your notes".

**Fill the panel.** A note in a small cell is a note you cannot write in. The
corner button gives it the whole display; Esc, the backdrop or the corner button
brings the dashboard back. Any widget can do this from the Cmd-hover controls.

**Quick capture.** ⌃⌥Space opens a box from any app and what you type lands in
the Inbox note. Not ⌘⇧N, which would have taken Finder's New Folder away in
every app on the machine. There is a switch in General because a global key
belongs to the whole machine and somebody may already have that one.

**Reminders.** ⌘⇧R sends the caret's unfinished to-do — or every one a selection
touches — to Apple Reminders, skipping what is already waiting there. One way on
purpose: keeping a note line and a reminder in step afterwards is a
synchronisation problem, and a note editor is the wrong place to grow one.

**Several notes.** A widget can be pointed at any note that exists, or keep a few
within reach as tabs. A new **Note** desktop widget shows a note's unfinished
to-dos without opening the app.

### From contributors

Eight pull requests from [@jondkinney](https://github.com/jondkinney), reviewed
and merged with follow-ups:

- **Sticky Note** and **Reminders** widgets — the first is the basis of
  everything above; the second is backed by the real EventKit database, with
  list picking, due times and ordering.
- **Edit mode** — widgets can overlap while arranging, drops displace what they
  cover, Esc cancels the session and ⌘Z steps through it. Dragging stopped
  rebuilding every widget on the page per tick.
- **Widget layout audit** — compact and size-aware layouts across sixteen
  widgets, a shared component so Network and Disk I/O render identically, and
  one-row placements for the glanceable ones.
- **Settings and window behaviour** — a Guide tab, deep links from a widget to
  its own settings, file panels as sheets, and the settings window kept off the
  kiosk display.
- **Swift 6** — the project builds clean under strict concurrency.
- **CI/CD widget** — rows collapse to the latest run per workflow, and the
  workflow name is shown.
- **Memory** is counted the way Activity Monitor counts it.

### Fixed

Most of these were found by writing the tests rather than by hitting them:

- A CPU counter wrapping after ~497 days would trap and take the app down.
- A short read from the SMC would do the same.
- A weather response whose arrays disagreed in length would crash rather than
  show a shorter forecast.
- A plugin's HTML path was checked for containment in one place out of three.
- The Top Processes list reordered itself between samples when usages tied.
- Disk and network rates were divided by an assumed interval rather than the
  measured one, which the timer's own tolerance made wrong by up to a tenth.
- Storage percentages were computed through a fudge factor.
- A layout document with a missing top-level key refused to decode.
- Esc and ⌘Z inside a note were taken by the edit session instead of the text.
- A year written in prose — "1998. That was the year" — became item 1998 of a
  list. CommonMark draws the line in the same place: an ordered list may only
  interrupt a paragraph when it starts at one.
- The weather widget chose its layout from its row count, and a row is not a
  unit of length: four rows is ~460pt on a 14.5" panel and half that on a
  monitor divided into twelve. It measures the cell it was given now.

### Project

- **The test suite went from a handful of cases to 498** — 387 Swift Testing
  tests and 111 XCTest — across the pure core of the app: readings, layout
  geometry, the note store and its migration, Markdown in both directions,
  plugin manifests, CI providers.
- **CI runs on every push and pull request**, from the same script that runs
  locally, so the two cannot drift: formatting, a clean build, a warning budget
  that gates at zero, the tests, and a coverage report.
- **swift-format** with a configuration at the repo root, and a
  `.git-blame-ignore-revs` so the formatting pass does not bury history.
- **The generated Xcode project is no longer committed.** It is generated from
  `project.yml`; keeping it produced conflicts on every branch and drifted
  silently when it did not.
- **Test runs no longer touch your dashboard.** The app bundle is its own test
  host, so `main()` ran for real against the storage directory of whoever ran
  the tests. It is redirected now.

## 2.3.1 — 2026-08-08

Archived repositories no longer fill the CI/CD widget. Archiving does not change
a repository's last-push time, so archived repositories kept sorting to the top
and pushing live work off the list.

## 2.3.0 — 2026-08-08

CI/CD on any Git host — GitHub Actions and Forgejo/Gitea, several accounts at
once. Touchscreen support, display and windowing settings, and a unit system
that follows the region rather than defaulting to metric.

## 2.2.0 — 2026-04-12

macOS desktop widgets via WidgetKit, and support for any display rather than
only the XENEON EDGE.

## 2.1.0 — 2026-04-11

The plugin system: custom widgets in HTML/JS with a permissioned SDK, a network
sandbox and theme integration. Media support extended to Safari, Chrome, Edge,
Spotify and Apple Music.

## 2.0.0 — 2026-04-10

The hardcoded seven-page layout became a dynamic grid: 20×6, drag to move and
resize, unlimited pages, 25 widgets that each adapt to the size they are given.
