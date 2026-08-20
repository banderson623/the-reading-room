# The Reading Room

*Where your documents get your undivided attention.*

> **The Reading Room** is a calm, native macOS space for reading your markdown.
> Open the door, settle in, and everything you need is within reach — a full
> folder of docs, rendered beautifully, no distractions. Sessions are private
> and restored exactly where you left off, so you can always pick up right where
> you… finished. However long it takes.

- **Restores your session** — comes right back to where you left off. We won't ask how long you were in there.
- **Change notifications** — someone left you a note while you were away.
- **Full-text search** — find anything, without getting up.
- **Follows system dark mode** — reads great with the lights off.
- **No cloud, no accounts** — what happens in the Reading Room stays in the Reading Room.

---

A small, native macOS reader for a folder of markdown files. Swift and SwiftUI,
no Electron, no bundled browser engine beyond the system WebKit.

Open a folder, get a sidebar of every markdown file in it (nested included), and
read them rendered in GitHub's style.

## Build

```bash
./build.sh --run
```

That produces `build/The Reading Room.app` (universal, ad-hoc signed) and opens
it. Other options:

```bash
./build.sh --install
```

- `--install` copies it to `/Applications`
- `--debug` builds for the native architecture only (faster, for iterating)
- `--run` launches the app when the build finishes

Requires Xcode's Swift toolchain. The only dependency is
[apple/swift-markdown](https://github.com/apple/swift-markdown), fetched by SwiftPM.

The app is signed with the first "Apple Development" identity in your keychain,
which is what Notification Center wants — an ad-hoc signature is unreliable
there. Set `SIGN_IDENTITY` to pick a different one; with no identity at all the
build falls back to ad-hoc and everything except notifications still works.

## Using it

| | |
| --- | --- |
| Open a folder | drag it onto the window or the Dock icon, or ⌘O — it opens in a new window, leaving what you were reading alone. A folder already open just comes to the front; you never get two windows on one directory |
| New window | ⌘N — starts empty, with its own folder, selection, and history |
| Pick up where you left off | quitting remembers every open window; relaunching reopens them on the same files, scrolled to the same place |
| Search file *contents* | type in the sidebar field (⇧⌘F), matches shown with a preview line. Files whose *name* or title match appear too |
| Jump to a heading | the outline button in the toolbar lists the document's headings |
| Sort the sidebar | the control beside the search field, or View ▸ Sort Files By |
| Follow a markdown link | click it — it opens in place, with ⌘[ / ⌘] for back and forward |
| Open a web link | click it — it goes to your default browser |
| Find in the page | ⌘F, then ⌘G / ⇧⌘G |
| Copy the file's path | ⇧⌘C (relative), ⌥⇧⌘C (absolute), or right-click a row |
| Copy a link back to a document | ⇧⌘L, right-click a row, or the ⋯ menu — see [Deep links](#deep-links) |
| Reveal in Finder | ⇧⌘R |
| Zoom | ⌘+ (or ⌘=) / ⌘- / ⌘0, or pinch on a trackpad. Steps through browser-style levels from 50% to 300%, remembered between launches |
| Reload | ⌘R |
| Tick a task off | click a `- [ ]` checkbox — see below |

Editing a file in another app re-renders it immediately, keeping your scroll
position. Files appearing, disappearing, or moving update the sidebar.

When a file *other* than the one you're reading changes, a notification appears
naming it; clicking the notification brings that file up. More than three
changes at once collapse into a single "5 files changed" banner. Turn this off
with `"notifyOnChange": false` in the settings file.

### Rendering

CommonMark plus GitHub's extensions: tables with alignment, task lists,
strikethrough, autolinks, footnote-style link references, raw HTML, and
`> [!NOTE]`-style alerts. Strikethrough needs `~~two tildes~~` — cmark-gfm also
pairs single ones, which turns prose like "~$230/mo … (~$200)" into one long
struck-out run. Code blocks are syntax highlighted. Headings get
anchors, so `#section` links work. Links that leave the app for your browser
are marked with a small ↗. YAML front matter is treated as metadata and
not rendered. Light and dark follow the system appearance.

Each document shows its last-modified date above the content.

### Ticking a box

Task-list checkboxes are live: clicking one rewrites the `[ ]` / `[x]` marker in
the file. That is the only edit the app makes — two characters on one line, with
the rest of the file, including whitespace, left exactly as it was. If the line
has changed since the page was rendered — no longer a task item, or already in
the state you clicked it to — the write is refused and the document re-renders
so you can see what the file actually says.

### Sidebar titles

A file named `index.md` tells you nothing, so files with generic names are
labelled with their own title instead — front matter `title:`, else the first
heading. The filename is still in the row's tooltip.

The default list is `index`, `_index`, `readme`, `home`, `overview`,
`introduction`, `intro`, `about`, `start`, `main`. Change it in
**Help ▸ Edit Settings…**, which opens `~/.config/the-reading-room/config.json`:

```json
{
  "titleFromHeadingFor": ["index", "readme", "spec"],
  "alsoTitleFromHeadingFor": ["notes"]
}
```

`titleFromHeadingFor` replaces the defaults; `alsoTitleFromHeadingFor` adds to
them. `notifyOnChange` controls change notifications. Reopen the folder to apply.

### Custom CSS

**Help ▸ Edit Custom Stylesheet…** opens
`~/.config/the-reading-room/custom.css`, appended after the built-in stylesheet.
⌘R reloads.

### Deep links

Every document has a URL that opens it here. **Copy Deep Link** — ⇧⌘L, the
right-click menu on a sidebar row, or the ⋯ menu in the toolbar — puts one on
the clipboard:

```
reading-room://open?path=/Users/me/notes/api/auth.md&root=/Users/me/notes
```

Paste it into a note, a ticket, a commit message, another markdown file — click
it and the file comes up in The Reading Room, in the folder it was read in
rather than its immediate parent. A window already on that folder comes to the
front; otherwise it opens a new one. Links survive a relaunch: clicking one
launches the app.

`root` is optional, `path` may be relative to it, and the whole thing can be
written as a plain path, so links are easy to build by hand or from a script:

```bash
open "reading-room:///Users/me/notes/api/auth.md"
open "reading-room://open?root=/Users/me/notes&path=api/auth.md"
open "reading-room://open?root=/Users/me/notes"          # just the folder
```

If the file has moved, the folder still opens. Registering the scheme is
LaunchServices' job, so a link works once macOS has seen the app — build with
`./build.sh --install`, or open it from `build/` once.

### Command line

```bash
"/Applications/The Reading Room.app/Contents/MacOS/TheReadingRoom" --render notes.md > notes.html
```

Writes a self-contained HTML file — styles and highlighting inlined.

```bash
"/Applications/The Reading Room.app/Contents/MacOS/TheReadingRoom" --notifications
```

Reports whether macOS has granted notification permission and what has been
delivered — the thing to check when change notifications aren't showing up.

## How it works

- **`TheReadingRoomCore`** — rendering and file logic, no UI, covered by tests:
  markdown → HTML, the file tree, content search, document titles, settings.
- **`TheReadingRoom`** — the SwiftUI app: sidebar, `WKWebView`, menus, FSEvents.

Two decisions worth knowing about:

**Pages are served over a custom `mdv://` URL scheme** rather than `file://`.
Relative links and images then resolve by ordinary URL rules, so following a
markdown link is a normal web navigation — which is why back/forward history and
in-page anchors work without any special handling, and why WebKit's `file://`
read restrictions never come up.

**Markdown is parsed once in Swift, not in JavaScript.** `swift-markdown`
(cmark-gfm) produces the AST and a visitor writes the HTML, so the page ships as
finished HTML with only a syntax highlighter running on it.

Search reads each file once and caches it by modification date, so typing
re-scans from memory. Searches run off the main thread and are cancelled when the
query changes.

The session — one entry per window, with its folder, open file, and scroll
offset — is written on quit and whenever the app loses focus, so an unexpected
exit still leaves a recent record. Restoring queues those entries; each window
takes one as it appears and then asks for the next, which is what unfolds a
multi-window session one window at a time.

```bash
swift test
```

## License

The bundled `highlight.min.js` is [highlight.js](https://highlightjs.org),
BSD-3-Clause. Everything else here is yours to do as you like with.
