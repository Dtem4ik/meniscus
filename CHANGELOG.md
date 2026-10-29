# Changelog

All notable changes to Meniscus. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

## [0.1.0] — 2026-10-29

The first release.

### The island

- A notch-perfect black island over the hardware notch (a virtual one on other screens), with a
  spring morph, a blur-to-sharp content reveal and Reduce Motion support.
- Home view: time, date, the next calendar event (with Join for Zoom, Google Meet and Microsoft
  Teams), and up to five modes.
- Pages for the player, the shelf and home, turned by a two-finger swipe or the page dots.
- A mini banner: the island opens a little way down for a few seconds, with concentric corners.

### Now Playing

- What any app is playing, through the bundled mediaremote-adapter: artwork, progress, controls,
  the playing app's icon; an equalizer in the closed notch.
- A track change banner with the artwork, title and artist.

### Live activities

- Upcoming meeting (5 minutes before and at the start), low battery at 20% and 10%, charging,
  keyboard layout, quick capture saved.
- Third-party Bluetooth devices connecting and disconnecting, with a battery ring from IOKit,
  CoreBluetooth (GATT Battery Service), `pmset` or `system_profiler`; their low battery.
- A priority order, hidden in full screen, left out of screenshots and screen sharing if you
  want; each activity has its own switch.

### Modes, capture and shelf

- Modes: links (including `obsidian://` and `claude://`), apps, files and folders, Shortcuts and
  quick capture, edited in Settings or in `config.json`.
- Quick capture into Obsidian or any folder of Markdown notes, with a hotkey.
- File shelf: drop files on the notch, Quick Look, AirDrop, drag them back out.

### External notices

- `notify` and `activity` (start, update, end) with three states, through the `meniscus` command
  line tool (a Unix socket only you can open), `meniscus://` links (off by default) and
  Shortcuts actions. Design: [docs/external-api.md](docs/external-api.md).
- Claude Code hooks: the island shows a long task running, then "Claude finished"; quick answers
  stay silent.

### Known limitations

- Builds are signed ad hoc: Gatekeeper needs the quarantine step on first launch, and Meniscus's
  own Shortcuts actions can't run on macOS 27 (use Run Shell Script with the command line tool).
- Now Playing depends on mediaremote-adapter; a macOS update may break it until the adapter is
  updated.

[0.1.0]: https://github.com/Dtem4ik/meniscus/releases/tag/v0.1.0
