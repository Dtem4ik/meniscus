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

You need Xcode 27 (macOS 26 SDK or later) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
git clone https://github.com/Dtem4ik/meniscus.git
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
- The menu bar icon (a drop) opens Settings and the Developer menu. You can hide the icon in
  Settings; the gear button inside the island still opens Settings.

### Developer menu

Meniscus is pre-1.0, so the tuning tools are in every build (menu bar icon → Developer, or
Settings → Developer):

- **Island Style**: three experiments for the transition from the black notch to glass.
  - *A · Obsidian*: the whole island is black, like Dynamic Island; controls inside are glass.
  - *B · Meniscus*: a glass panel rises to the top of the screen; only the notch stays black,
    sitting in the glass like a drop.
  - *C · Droplet*: the notch stays put; a glass drop flows out from under it.
- **Slow Animations**: plays every transition at one fifth of the speed.
- **Outline Computed Notch**: draws a red line 1 pt outside the computed notch. On a correct
  geometry it hugs the hardware notch evenly on all three sides.
- **Use Virtual Notch**: draws the virtual notch even on a screen with a camera housing.
- **Copy Geometry Report**: copies the screen numbers behind the notch, for bug reports.
- **Open or Close Island**: keeps the island open without hovering, to inspect it.

All motion parameters (springs, delays, the content reveal) are in
[`Meniscus/Notch/Motion.swift`](Meniscus/Notch/Motion.swift); sizes are in
[`Meniscus/Notch/Geometry/IslandLayout.swift`](Meniscus/Notch/Geometry/IslandLayout.swift).

## Permissions

Meniscus asks for a permission only when you turn on a feature that needs it.

| Permission | Asked for by | Why |
| --- | --- | --- |
| Calendars | Upcoming event in the island (stage 1) | Reads your next event with EventKit. Nothing leaves your Mac. |
| Automation (Apple Events) | Now Playing (stage 2) | Reads the current track from and sends play/pause/next/previous to Music and Spotify. |
| Accessibility | Not needed | No current or planned feature needs it. The capture hotkey uses the system hotkey API, which works without Accessibility access. If that ever changes, it will be listed here first. |

## Roadmap

0. ✅ Skeleton: notch-perfect black shape, spring morph into a glass panel.
1. Clock, date, next calendar event; charging live activity.
2. Now Playing for Music and Spotify.
3. Modes: one button that opens a named set of links, apps, files and Shortcuts.
4. Quick capture into an Obsidian inbox note.
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

## License

[MIT](LICENSE)
