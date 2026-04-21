# Animenz Player — Setup Guide

A SwiftUI app for iOS and macOS that bundles your Animenz playlist and plays it.
Supports: tap-to-play any track, shuffle, continuous auto-advance, scrub, and search.

## What you need
- A Mac
- Xcode 15 or later (free on the Mac App Store)
- Your downloaded `.m4a` files from yt-dlp

## Step 1 — Create the Xcode project

1. Open Xcode. Choose **File > New > Project**.
2. Select **Multiplatform > App**, click Next.
3. Fill in:
   - Product Name: `AnimenzPlayer`
   - Organization Identifier: something like `com.yourname`
   - Interface: **SwiftUI**
   - Language: **Swift**
4. Save it anywhere (Desktop is fine).

## Step 2 — Replace the generated Swift files

Xcode will have created two files: `AnimenzPlayerApp.swift` and `ContentView.swift`.

1. In the Xcode project navigator (left sidebar), delete both files (move to trash).
2. Drag these four files from this folder into the Xcode project navigator:
   - `AnimenzPlayerApp.swift`
   - `Track.swift`
   - `PlayerViewModel.swift`
   - `ContentView.swift`
3. In the dialog that appears, make sure **"Copy items if needed"** is checked and both targets (iOS and macOS) are selected. Click Finish.

## Step 3 — Add your music

1. In Finder, rename your `Animenz` folder to `Music`.
2. Drag the `Music` folder into the Xcode project navigator (drop it alongside the Swift files).
3. In the dialog:
   - Check **"Copy items if needed"**
   - Choose **"Create folder references"** (NOT "Create groups") — the folder icon should turn **blue**, not yellow. This matters; groups flatten the files and strip the subfolder.
   - Select both targets.
4. Click Finish.

## Step 4 — (macOS only) Allow file access

macOS apps are sandboxed and need entitlement to read files. Bundled resources usually work without changes, but if the track list is empty on macOS:

1. Click the project in the navigator, select the macOS target.
2. Go to **Signing & Capabilities**.
3. Under App Sandbox, you shouldn't need to change anything since we're reading from the bundle — but if empty, try disabling sandbox temporarily to confirm it's not that.

## Step 5 — Run

- For **macOS**: pick the "My Mac" scheme at the top of Xcode, hit the ▶ button.
- For **iOS**: pick a simulator (e.g. iPhone 15) and hit ▶.
- For **iOS on your device**: plug your iPhone in, select it as the destination, hit ▶. You may need to trust the developer certificate in Settings > General > VPN & Device Management.

## Tips

- **Background playback on iOS:** Add the "Audio, AirPlay, and Picture in Picture" background mode. Project > iOS target > Signing & Capabilities > + Capability > Background Modes > check "Audio, AirPlay, and Picture in Picture".
- **App icon:** Drag an image into `Assets.xcassets > AppIcon` if you want a custom icon.
- **Adding more tracks later:** just drag more `.m4a` files into the Music folder inside the project, rebuild.

## How it works

- `Track.swift` parses yt-dlp's `NNN - Title [videoid].m4a` filenames into numbered, readable titles.
- `PlayerViewModel.swift` loads all audio files from the bundled `Music` folder at launch, uses `AVAudioPlayer` for playback, and auto-advances on finish (that's the "continuous" part).
- `ContentView.swift` shows the list, search bar, and transport controls. Tap any track to jump to it; shuffle rebuilds the queue while keeping the current track playing.

## Troubleshooting

**"No tracks found"** — The Music folder wasn't added as a folder reference. Remove it from Xcode, re-add with "Create folder references" selected (blue folder).

**App builds but doesn't play anything on macOS** — Check the console for permission errors. The bundle resources should be readable without sandbox tweaks.

**Playlist is huge and Xcode is slow** — That's normal; 165 files × ~5 MB = a heavy app bundle. Once built, it runs fine.
