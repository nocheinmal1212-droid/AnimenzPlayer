import Foundation
import AVFoundation
import ImageIO
import CoreGraphics

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Size

/// The rendering context an artwork is being loaded for. Drives the max pixel
/// dimension fed to ImageIO so a 44-pt list row doesn't end up decoding a
/// 2000×2000 JPEG into RAM.
///
/// Cache entries are keyed by (url, size), so the full-resolution player-bar
/// image and the thumbnail for the same track are cached independently.
enum ArtworkSize {
    case thumbnail   // list rows (≈44pt × 3x scale)
    case full        // player bar / future full-screen player

    var maxPixelDimension: Int {
        switch self {
        case .thumbnail: return 160
        case .full:      return 600
        }
    }
}

// MARK: - Cache

enum ArtworkCache {
    private final class Entry {
        let image: PlatformImage
        init(_ image: PlatformImage) { self.image = image }
    }

    private static let cache: NSCache<NSString, Entry> = {
        let c = NSCache<NSString, Entry>()
        // ~64 MB ceiling. A 600px JPEG decoded as RGBA is ~1.4 MB; a 160px
        // thumbnail is ~100 KB. Holds the entire typical library several
        // times over before eviction kicks in.
        c.totalCostLimit = 64 * 1024 * 1024
        return c
    }()

    static func image(for track: Track, size: ArtworkSize) async -> PlatformImage? {
        let key = cacheKey(for: track, size: size)
        if let cached = cache.object(forKey: key) {
            return cached.image
        }
        guard let image = await ArtworkLoader.load(
            for: track,
            maxPixelDimension: size.maxPixelDimension
        ) else {
            return nil
        }
        let cost = estimatedBytes(for: image)
        cache.setObject(Entry(image), forKey: key, cost: cost)
        return image
    }

    /// For tests / low-memory warnings.
    static func clear() {
        cache.removeAllObjects()
    }

    private static func cacheKey(for track: Track, size: ArtworkSize) -> NSString {
        "\(track.url.absoluteString)|\(size.maxPixelDimension)" as NSString
    }

    private static func estimatedBytes(for image: PlatformImage) -> Int {
        #if os(macOS)
        guard let rep = image.representations.first else { return 4 * 1024 }
        return max(rep.pixelsWide * rep.pixelsHigh * 4, 4 * 1024)
        #else
        let scale = image.scale
        let w = Int(image.size.width * scale)
        let h = Int(image.size.height * scale)
        return max(w * h * 4, 4 * 1024)
        #endif
    }
}

// MARK: - Loader

enum ArtworkLoader {
    /// Load artwork for a track. Tries a sidecar image file next to the audio
    /// first (what `yt-dlp --write-thumbnail` produces), then falls back to
    /// embedded artwork in the audio file's metadata. All decoding goes
    /// through ImageIO's thumbnail API so images are downsampled at decode
    /// time rather than decoded full-res and scaled down.
    static func load(for track: Track, maxPixelDimension: Int) async -> PlatformImage? {
        if let url = track.artworkURL,
           let image = downsample(url: url, maxPixelDimension: maxPixelDimension) {
            return image
        }

        let asset = AVURLAsset(url: track.url)
        guard let metadata = try? await asset.load(.commonMetadata) else {
            return nil
        }
        for item in metadata where item.commonKey == .commonKeyArtwork {
            if let data = try? await item.load(.dataValue),
               let image = downsample(data: data, maxPixelDimension: maxPixelDimension) {
                return image
            }
        }
        return nil
    }

    // MARK: - Downsampling

    private static func downsample(url: URL, maxPixelDimension: Int) -> PlatformImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return nil
        }
        return makeImage(from: source, maxPixelDimension: maxPixelDimension)
    }

    private static func downsample(data: Data, maxPixelDimension: Int) -> PlatformImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }
        return makeImage(from: source, maxPixelDimension: maxPixelDimension)
    }

    private static func makeImage(from source: CGImageSource, maxPixelDimension: Int) -> PlatformImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
            return nil
        }
        #if os(macOS)
        let size = CGSize(width: cg.width, height: cg.height)
        return NSImage(cgImage: cg, size: size)
        #else
        return UIImage(cgImage: cg)
        #endif
    }
}
