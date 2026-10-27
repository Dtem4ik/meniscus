# Now Playing

Meniscus shows what any app is playing (a music app, a browser tab, a podcast player) with its
artwork and controls, using the system's own Now Playing information.

## Why an adapter

Since macOS 15.4, `mediaremoted` only answers Apple-signed processes, so third-party apps can no
longer read Now Playing through the private MediaRemote framework, and macOS 26 and 27 add no
public replacement.

Meniscus bundles [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
(BSD 3-Clause, pinned as a git submodule in `ThirdParty/mediaremote-adapter`). Its framework is
loaded into `/usr/bin/perl`, which is Apple-signed and therefore still allowed to read Now
Playing, and prints the information as JSON lines.

This relies on a private framework through a loophole Apple could close in any update. Meniscus
treats it that way:

- At start, the adapter's own self-test (`test`) checks that reading works on this macOS.
- The long-running `stream` process pushes changes; nothing polls. Unexpected exits are retried
  after 1, 2, 4… seconds, re-checked after 3 failures, and given up after 6.
- When it isn't available, the music activity simply doesn't appear, and
  Settings → General explains why: no `/usr/bin/perl`, a build without the adapter, or macOS no
  longer allowing it.

Checked on macOS 27.0.1 (26A434): `/usr/bin/perl` 5.34.1 ships, signed by Apple
(`com.apple.perl`, platform binary), without deprecation warnings; adapter v0.7.7 builds with
CMake and passes its self-test. Apple announced in 2019 that scripting runtimes would eventually
leave macOS; Python 2 was removed in macOS 12.3, Perl is still there. The CI integration test
`MediaRemoteAdapterIntegrationTests` fails as soon as that changes on the runner image.

## What it uses

- Title, artist, album, duration, position and playback rate; the position is extrapolated
  locally between updates.
- Artwork exactly as the system provides it. Nothing is downloaded.
- The playing app's bundle identifier, only to show that app's icon and open it on click.
- Commands: play/pause, next, previous (`send 2`, `send 4`, `send 5`).

## Building

The adapter is built by an Xcode build phase (`scripts/build-mediaremote-adapter.sh`) with CMake
and copied into the app: the framework into `Contents/Frameworks`, the test client into
`Contents/Helpers`, the Perl script and its license into `Contents/Resources`. Without the
submodule or CMake the app still builds; Now Playing then reports itself unavailable.
