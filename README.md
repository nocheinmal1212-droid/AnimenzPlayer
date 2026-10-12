# Animenz Player

A SwiftUI music player for iOS and macOS that plays a local library bundled with the app. It discovers audio files, derives track numbers and titles from filenames, and loads sidecar or embedded artwork. The app uses Apple frameworks only; there are no third-party runtime dependencies.

## Requirements

| Setting | Current project configuration |
| --- | --- |
| Xcode | Use Xcode 26.2 or later with SDKs for the configured deployment targets |
| iOS deployment target | 26.2 |
| macOS deployment target | 26.2 |
| Swift language mode | Swift 5 (`SWIFT_VERSION = 5.0`), using Xcode's bundled compiler |

The project was created with Xcode 26.2 and uses filesystem-synchronized source folders. The Swift language mode is separate from the installed compiler version. The project also configures visionOS 26.2; the usage instructions here cover iOS and macOS.

## Build and run

1. Open `AnimenzPlayer.xcodeproj` in Xcode.
2. Select the `AnimenzPlayer` scheme and choose **My Mac** or an iOS Simulator running 26.2 or later.
3. Press **⌘R**. For a physical device, select your development team under **Signing & Capabilities**.

A fresh clone has no music or asset catalog: `AnimenzPlayer/Music/` and `AnimenzPlayer/Assets.xcassets/` are intentionally ignored. Without music, the app shows an empty library. See [Adding music](#adding-music) and [Troubleshooting](docs/troubleshooting.md) for setup.

Background audio is already configured through `UIBackgroundModes = [audio]` in `AnimenzPlayer/Info.plist`. The engine sets the iOS audio session category to `.playback`; no initial capability change is required.

## Features

- Play, pause, seek, shuffle, and repeat off / all / one.
- Favorites and the 50 most recently played tracks, available through the list filter.
- Last-played track and position, shuffle, repeat mode, favorites, history, and search scope saved across launches.
- Sleep timer for 5, 15, 30, or 60 minutes, or until the current track ends. End-of-track expiration takes precedence over repeat mode.
- System Now Playing information and remote playback commands; iOS interruption handling and haptics.
- Search by title, show name, curated alias, acronym, or out-of-order words.
- Scoped queues and an ambient artwork background for recognized show searches.
- Bounded playback recovery and local diagnostics export on macOS.

## Adding music

1. Create `AnimenzPlayer/Music/` inside the app source folder. This location is excluded from Git.
2. Add audio files. Supported extensions are `m4a`, `mp3`, `aac`, `wav`, `flac`, `aiff`, and `caf`.
3. Ensure Xcode includes the folder's files in the `AnimenzPlayer` target. If adding an explicit folder reference, preserve the folder name **Music** and its directory structure in the built bundle. Avoid adding the same files twice through both synchronized membership and a separate reference.
4. Build and run. If the library is empty, inspect the built app's resources as described in [Troubleshooting](docs/troubleshooting.md#no-tracks-at-launch).

Discovery scans the bundled `Music` directory first, or the bundle resource root if that directory is absent. Each scan is flat: nested subdirectories are not searched. Audio is bundled at build time; adding files requires rebuilding the app.

Filenames such as `001 - Title [videoid].m4a` supply the track number and displayed title. The `yt-dlp` output template `%(playlist_index)03d - %(title)s [%(id)s].%(ext)s` provides the expected numbering. Sidecar JPEG, PNG, or WebP images with the same base filename supply artwork; embedded metadata is the fallback. See [yt-dlp](https://github.com/yt-dlp/yt-dlp) for its tooling documentation.

[`music_list.txt`](AnimenzPlayer/music_list.txt) is a reference catalog, including the source titles used for search-test fixtures. It is retained in the repo; the app discovers playable files from the bundle rather than reading this list.

## Search and scoped playback

Aliases are case-insensitive: `AOT` finds Attack on Titan, `JJK` finds Jujutsu Kaisen, and `SAO` finds Sword Art Online. Literal title/show substrings, short letter acronyms, and multi-word token matching are also supported. Multi-word queries do not expand aliases: use `sword alicization` rather than `sao alicization`.

The search box and filter control the visible list. Selecting a track captures the corresponding playback scope:

| Action | Playback scope |
| --- | --- |
| Type a query or change the list filter | Unchanged |
| Select a track from search results | That result set |
| Select a track from Favorites or Recent without a query | That filter's tracks |
| Clear the search text | Unchanged |
| Select a track from All without a query | Full library |
| Press X on the scope chip | Full library, preserving the current track |

Next, previous, shuffle, and repeat all operate within the active scope. Search scope is restored by re-ranking its saved query against the current library; Favorites and Recent scopes are session-only.

The background follows the **active playback scope**, independently of the current search text. It uses artwork from a representative track when a search scope resolves to a known show. The preference `themedBackgroundsEnabled` is read through `@AppStorage` and defaults to on; there is currently no settings control for it.

## Keyboard shortcuts on macOS

These commands appear in the **Playback** menu.

| Action | Shortcut |
| --- | --- |
| Play / Pause | Space |
| Next track | ⌥⌘ → |
| Previous track | ⌥⌘ ← |
| Toggle shuffle | ⇧⌘ S |
| Cycle repeat mode | ⇧⌘ R |
| Toggle favorite | ⇧⌘ L |

The modifier combinations avoid normal text-navigation shortcuts. Space enters text when the search field is focused. Sleep Timer is available from the repeat button's context menu. **Playback → Export Debug Log…** saves local diagnostics on macOS.

## Developer documentation

- [Architecture](docs/architecture.md): component responsibilities, playback scope, persistence, recovery, and layout constraints.
- [Contributing](CONTRIBUTING.md): development workflow, tests, and manual checks.
- [Troubleshooting](docs/troubleshooting.md): library setup, build issues, playback recovery, and diagnostics.

## License

Licensed under the [MIT License](LICENSE).
