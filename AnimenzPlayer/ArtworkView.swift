import SwiftUI
import AVFoundation

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

// MARK: - Loader

enum ArtworkLoader {
    /// Load artwork for a track. Tries a sidecar image file next to the audio
    /// first (what `yt-dlp --write-thumbnail` produces), then falls back to
    /// embedded artwork in the audio file's metadata.
    static func load(for track: Track) async -> PlatformImage? {
        // 1. Sidecar file
        if let url = track.artworkURL,
           let data = try? Data(contentsOf: url),
           let image = PlatformImage(data: data) {
            return image
        }

        // 2. Embedded metadata (requires iOS 16 / macOS 13)
        let asset = AVURLAsset(url: track.url)
        guard let metadata = try? await asset.load(.commonMetadata) else {
            return nil
        }
        for item in metadata where item.commonKey == .commonKeyArtwork {
            if let data = try? await item.load(.dataValue),
               let image = PlatformImage(data: data) {
                return image
            }
        }
        return nil
    }
}

// MARK: - Cache

/// Small in-memory cache so scrolling through the track list and changing
/// tracks doesn't re-decode the same artwork over and over.
enum ArtworkCache {
    private static let cache: NSCache<NSURL, PlatformImage> = {
        let c = NSCache<NSURL, PlatformImage>()
        c.countLimit = 200
        return c
    }()

    static func image(for track: Track) async -> PlatformImage? {
        let key = track.id as NSURL
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = await ArtworkLoader.load(for: track) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

// MARK: - View

struct ArtworkView: View {
    let image: PlatformImage?
    let size: CGFloat

    private var cornerRadius: CGFloat { max(4, size * 0.08) }

    var body: some View {
        Group {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.quaternary)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.35))
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
