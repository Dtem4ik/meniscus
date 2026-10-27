# Meniscus

Meniscus turns the notch of your MacBook into a live, Liquid Glass "Dynamic Island" that looks
and moves as if Apple had built it into macOS.

> A *meniscus* is the curved surface of a liquid, a nod to Liquid Glass and to the shape of the
> notch.

<!-- Screenshot: collapsed notch and expanded island, Light and Dark Mode -->
<!-- GIF: notch → island morph at 120 Hz -->

**Status:** early development. Stage 0, the window, the shape and the motion, is done. See the
[roadmap](#roadmap).

## Principles

- **Feels native.** Only system materials (Liquid Glass via `glassEffect`), system fonts,
  SF Symbols, system colors and springs. Few features, polished to system quality.
- **Quiet.** Close to 0% CPU while the notch is collapsed. Everything is event driven; nothing
  polls.
- **Private.** No telemetry and no network requests unless you configure an action that opens a
  URL. Personal settings live outside the repository, on your Mac.

## Requirements

- macOS 26 Tahoe or later. Designed and tuned for macOS 27 Golden Gate.
- A MacBook with a notch looks best. On other displays Meniscus draws a virtual notch at the top
  center of the screen.
- Apple silicon is the priority. Intel Macs running macOS 26 should work but aren't tested.

## Install a build

Every push is built by GitHub Actions. To try the latest build:

1. Open the [Actions tab](../../actions), pick the latest green **CI** run and download the
   `Meniscus-<commit>` artifact (you need to be signed in to GitHub).
2. Unzip it until you get `Meniscus.app` and move it to `/Applications`.
3. Remove the quarantine flag (see below) and open it.

### First launch of an unsigned build

Builds are ad-hoc signed, not notarized, so Gatekeeper blocks them on first launch
("Meniscus can't be opened" or "is damaged"). Either:

- run once in Terminal:

  ```sh
  xattr -dr com.apple.quarantine /Applications/Meniscus.app
  ```

- or try to open the app, then go to **System Settings → Privacy & Security** and click
  **Open Anyway** next to the message about Meniscus.

Only do this for builds you downloaded from this repository.

## Build from source

You need Xcode 27 (macOS 26 SDK or later), [XcodeGen](https://github.com/yonaskolb/XcodeGen)
and CMake (for the bundled Now Playing adapter).

```sh
brew install xcodegen cmake
git clone --recursive https://github.com/Dtem4ik/meniscus.git
cd meniscus
xcodegen generate
open Meniscus.xcodeproj
```

For day-to-day development, one command pulls the latest commits, builds and relaunches the app
(about a minute, and no Gatekeeper prompt because the build never leaves your Mac):

```sh
scripts/run.sh            # current branch; see scripts/run.sh --help
```

The Xcode project is generated from `project.yml` and is not checked in. Run `xcodegen generate`
again after pulling changes that add or remove files.

Command-line build and tests:

```sh
xcodebuild test -project Meniscus.xcodeproj -scheme Meniscus -destination 'platform=macOS'
```

## Using it

- Rest the pointer on the notch for a moment, or click it, to open the island. Move the pointer
  away to close it.
- The menu bar icon (a drop) opens Settings and the Developer menu, with a left or a right click.
  You can hide the icon in Settings; opening Meniscus again then shows Settings.

### Developer menu

Meniscus is pre-1.0, so the tuning tools are in every build (menu bar icon → Developer, or
Settings → Developer):

- **Slow Animations**: plays every transition at one fifth of the speed.
- **Outline Computed Notch**: draws a red line 1 pt outside the computed notch. On a correct
  geometry it hugs the hardware notch evenly on all three sides.
- **Use Virtual Notch**: draws the virtual notch even on a screen with a camera housing.
- **Copy Geometry Report**: copies the screen numbers behind the notch, for bug reports.
- **Simulate Charging**: plays the charging activity without plugging in a cable.

### Logs

Meniscus logs through the unified logging system. To send logs with a bug report, open Console,
start streaming, and filter by subsystem `io.github.dtem4ik.meniscus` (category `power` for
charging), or run:

```sh
log stream --predicate 'subsystem == "io.github.dtem4ik.meniscus"' --level info
```
- **Open or Close Island**: keeps the island open without hovering, to inspect it.

All motion parameters (springs, delays, the content reveal) are in
[`Meniscus/Notch/Motion.swift`](Meniscus/Notch/Motion.swift); sizes are in
[`Meniscus/Notch/Geometry/IslandLayout.swift`](Meniscus/Notch/Geometry/IslandLayout.swift).

## Modes

A mode is a button in the island that opens one thing: a link (including deep links such as
`obsidian://…` or `claude://…`), an app, a file or folder, or a Shortcut. A mode can also chain
several actions; **Add Another Action** in Settings adds one.
The first five modes show as a row of symbols under the time and the next event; hover over one
for its name.

Modes live in `~/Library/Application Support/Meniscus/config.json`, outside the repository.
Edit them in **Settings → Modes** or by hand; changes to the file are picked up immediately.
The island shows the first five, left to right in the order of the list; drag the ≡ handle or
use Move Up and Move Down in a mode's context menu to change it.
[`config.example.json`](config.example.json) has three one-action examples (Settings → Modes →
**Add Example Modes** installs them). The action types:

| `type` | Fields | Example |
| --- | --- | --- |
| `url` | `url` | `{ "type": "url", "url": "https://claude.ai/new" }` |
| `app` | `bundleId` | `{ "type": "app", "bundleId": "com.apple.Notes" }` |
| `file` | `path` (`~` allowed) | `{ "type": "file", "path": "~/Documents" }` |
| `shortcut` | `name`, optional `input` | `{ "type": "shortcut", "name": "Start Focus Session" }` |
| `capture` | none | `{ "type": "capture" }` opens the quick capture field |

Each mode has a `name`, an optional `id` (made from the name if missing) and an optional SF
Symbol name in `symbol`. In Settings you pick the app, the file or folder, the shortcut (from
your Shortcuts library) and the symbol (a searchable grid) instead of typing them; files in your
home folder are stored with `~`. By hand, run `osascript -e 'id of app "Notes"'` to find an
app's bundle id.

Links open in the app that owns them. The Claude desktop app
[handles `claude://` links](https://support.claude.com/en/articles/14729294-open-claude-desktop-with-a-link):

| Link | Opens |
| --- | --- |
| `claude://claude.ai/new` | A new chat; add `?q=` with URL-encoded text to prefill the prompt |
| `claude://claude.ai/project/ID` | A project; the ID is the end of the project's claude.ai address |
| `claude://claude.ai/chat/ID` | A chat, the same way |
| `claude://code/new?folder=/path` | A new Claude Code session in a folder (the app asks to confirm it) |

## Quick capture into Obsidian

Press **⌃⌥Space** (change it in Settings → Capture), choose **Quick Capture** in the menu bar or
use a mode with the Quick Capture action. Type a thought and press Return: a short "Saved" shows
and the island closes. Escape or a click elsewhere closes the field and keeps what you typed.

By default each capture becomes a note of its own in a folder you choose, named after the date,
the time and its first words, such as `2026-10-27 21-45 Call the bank.md`, with your text inside.
Choose the folder in **Settings → Capture**. It can be anywhere, including an Obsidian vault in
iCloud Drive; paths with spaces or non-Latin letters are fine. Alternatively, captures can be
added to the end of one note as `- 21:45 your thought`, with a `## yyyy-MM-dd` heading for each
new day if you want one.

Meniscus writes the Markdown files directly; no Obsidian plugin is needed. The chosen folder or
note is remembered with a bookmark, so it is followed when moved or renamed, and nothing about
it is stored in this repository.

## Pages

While something plays, or files are on the shelf, the open island has pages: the player, the
shelf and the home view (time, date, next event, modes). It opens on the page you looked at
last, unless something newer happened: a new track opens the player, dropped files the shelf. If
that page is gone (the shelf was cleared, the music stopped), it opens on the home view. Swipe left or
right with two fingers on the trackpad to turn pages, or click the small dots at the bottom; the
dots only show when there is more than one page.

## File shelf

As soon as you start dragging a file anywhere, the notch widens a little: a paperclip on the left
and a gently bouncing arrow up on the right. Once the pointer gets near the top of the screen, the island opens as a large drop target,
before macOS would open Mission Control at the edge. Everything goes back to normal if the drag
moves away or ends without a drop (including a cancelled drag).

Dropped files stay on the shelf, its own page of the island, with real previews (images, PDFs, videos, documents) or their
icons. Click a file for Quick Look (Space or Escape closes it, the arrow keys move between
files), double-click to open it, drag it anywhere, or right-click for AirDrop, Copy Path and
Show in Finder. A file moved or renamed on disk stays on the shelf at its new place; a deleted
file, or one put in the Trash, leaves the shelf.

While files are on the shelf, the closed notch shows a paperclip and how many there are; when
music plays, the music comes first and a small paperclip with the count sits next to the
equalizer.

Don't want it? Turn off **Settings → General → Keep dropped files on a shelf**: Meniscus then
doesn't watch file drags at all, and files already on the shelf come back when you turn it on
again. Dragging a file off the shelf never opens the drop target. The shelf only keeps references;
files are never copied or moved. A file drag is noticed with a
global monitor for mouse presses, which needs no permission: while the button is held, Meniscus
briefly checks the pointer and the drag pasteboard, and stops as soon as it is released.

## Languages

English and Russian, following the system language. Strings live in
`Meniscus/Resources/Localizable.xcstrings`; CI fails when a string has no Russian translation.

## Permissions

Meniscus asks for a permission only when you turn on a feature that needs it.

| Permission | Asked for by | Why |
| --- | --- | --- |
| Calendars | Upcoming event in the island (stage 1) | Reads your next event with EventKit. Nothing leaves your Mac. |
| Accessibility | Not needed | No current or planned feature needs it. The capture hotkey uses the system hotkey API, which works without Accessibility access. If that ever changes, it will be listed here first. |

## Roadmap

0. ✅ Skeleton: notch-perfect black island with a spring morph and Liquid Glass controls.
1. Clock, date, next calendar event; charging live activity.
2. Now Playing for any app, with artwork and controls.
3. Modes: one button that opens a named set of links, apps, files and Shortcuts.
4. Quick capture into Obsidian: a note per thought in an inbox folder, or a line in one note.
5. File shelf: drop files on the notch, drag them out, Quick Look, AirDrop.

## Project layout

```
Meniscus/
  App/          App entry point, app delegate, menu bar menu
  Notch/        Panel, geometry, shape, styles and Motion.swift
  Activities/   Live activities (stage 1+)
  Modes/        Modes and launcher (stage 3)
  Capture/      Obsidian quick capture (stage 4)
  Shelf/        File shelf (stage 5)
  Settings/     Settings window and preferences
  Shared/       Small helpers used across features
MeniscusTests/  Unit tests (Swift Testing)
project.yml     XcodeGen project definition
```

## Contributing

Issues and pull requests are welcome. Please keep commits small and use
[Conventional Commits](https://www.conventionalcommits.org/). Never commit keys, tokens, personal
paths or links; personal configuration belongs in `~/Library/Application Support/Meniscus/`.

## Now Playing

The island shows what any app is playing, with the system's artwork and play/pause, next and
previous; the playing app's icon switches to it. It uses the bundled
[mediaremote-adapter](https://github.com/ungive/mediaremote-adapter), because macOS has no
public API for this. If a macOS update breaks it, the activity just doesn't appear and
Settings → General says why. Details in [docs/now-playing.md](docs/now-playing.md).

## Third-party software

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The only dependency is
mediaremote-adapter (BSD 3-Clause), as a git submodule.

## License

[MIT](LICENSE)
