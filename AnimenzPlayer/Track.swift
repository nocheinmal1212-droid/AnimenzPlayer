import Foundation

struct Track: Identifiable, Hashable {
    let id: URL
    let url: URL
    let title: String
    let index: Int
    let artworkURL: URL?

    init(url: URL) {
        self.id = url
        self.url = url

        var filename = url.deletingPathExtension().lastPathComponent

        // yt-dlp appends a " [videoid]" suffix — strip it for display
        if let bracket = filename.range(of: " [", options: .backwards),
           filename.hasSuffix("]") {
            filename = String(filename[..<bracket.lowerBound])
        }

        // Expect "NNN - Title" format from yt-dlp's playlist_index template
        var parsedIndex = Int.max
        var parsedTitle = filename
        if let dashRange = filename.range(of: " - "),
           let idx = Int(
                filename[..<dashRange.lowerBound]
                    .trimmingCharacters(in: .whitespaces)
           ) {
            parsedIndex = idx
            parsedTitle = String(filename[dashRange.upperBound...])
        }
        self.index = parsedIndex
        self.title = parsedTitle

        // Look for a sidecar thumbnail with the same base filename.
        // yt-dlp's --write-thumbnail writes e.g. "001 - Title [id].jpg"
        self.artworkURL = Self.findArtwork(for: url)
    }

    private static func findArtwork(for audioURL: URL) -> URL? {
        let fm = FileManager.default
        let base = audioURL.deletingPathExtension()
        let extensions = ["jpg", "jpeg", "png", "webp"]
        for ext in extensions {
            let candidate = base.appendingPathExtension(ext)
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    // Identity is the file URL. Manual conformance keeps two Tracks equal
    // even if, say, artwork gets discovered on a later scan.
    static func == (lhs: Track, rhs: Track) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
