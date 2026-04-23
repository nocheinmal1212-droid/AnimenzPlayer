import Foundation

/// Pure, stateless search + ranking over a list of tracks. No Combine, no
/// SwiftUI, no I/O — everything is derivable from the inputs.
///
/// Ranking rules (highest score wins; ties break by library index ascending):
///
///  100  Query is an alias whose canonical show equals the track's show
///   80  Query is a substring of the track title
///   70  Query is a substring of the track's derived show name
///   60  Query is an acronym of the track's derived show name
///   40  Every whitespace-separated token of the query is in the title
///   25  Every whitespace-separated token of the query is in title+show
///    0  none of the above (track is filtered out)
///
/// The rules stack as a *max*, not a sum: a track that's both an alias match
/// and a substring match scores 100, not 180. Scores are intentionally
/// integer and well-spaced so future tuning doesn't need float arithmetic.
enum SearchEngine {

    /// Rank `tracks` against `query`. Returns tracks whose score is positive,
    /// sorted by descending score and then by library index.
    ///
    /// An empty / whitespace-only query is treated as "no filter": all tracks
    /// are returned in their natural (library-index) order.
    static func rank(_ query: String, in tracks: [Track]) -> [Track] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return tracks }

        let canonicalFromAlias = ShowCatalog.canonicalShow(for: q)
        let lowerQuery = q.lowercased()
        let queryLooksLikeAcronym = isLikelyAcronym(q)
        let tokens = q.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }

        let scored: [(track: Track, score: Int)] = tracks.compactMap { track in
            let s = score(
                for: track,
                lowerQuery: lowerQuery,
                canonicalFromAlias: canonicalFromAlias,
                queryLooksLikeAcronym: queryLooksLikeAcronym,
                tokens: tokens
            )
            return s > 0 ? (track, s) : nil
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.track.index < rhs.track.index
            }
            .map(\.track)
    }

    // MARK: - Scoring

    private static func score(
        for track: Track,
        lowerQuery: String,
        canonicalFromAlias: String?,
        queryLooksLikeAcronym: Bool,
        tokens: [String]
    ) -> Int {
        let lowerTitle = track.title.lowercased()
        let derivedShow = track.show
        let lowerShow = derivedShow?.lowercased() ?? ""

        // 100 — alias match against the track's canonical show.
        if let alias = canonicalFromAlias,
           let derivedShow,
           alias.caseInsensitiveCompare(derivedShow) == .orderedSame {
            return 100
        }

        // 80 — query is a substring of the title.
        if lowerTitle.contains(lowerQuery) {
            return 80
        }

        // 70 — query is a substring of the derived show name.
        if !lowerShow.isEmpty && lowerShow.contains(lowerQuery) {
            return 70
        }

        // 60 — query matches the acronym of the derived show.
        if queryLooksLikeAcronym, let derivedShow {
            let generated = ShowCatalog.acronym(of: derivedShow)
            if generated.caseInsensitiveCompare(lowerQuery) == .orderedSame {
                return 60
            }
        }

        // 40 / 25 — token match.
        if !tokens.isEmpty {
            if tokens.allSatisfy({ lowerTitle.contains($0) }) {
                return 40
            }
            if !lowerShow.isEmpty {
                let haystack = lowerTitle + " " + lowerShow
                if tokens.allSatisfy({ haystack.contains($0) }) {
                    return 25
                }
            }
        }

        return 0
    }

    /// A query "looks like an acronym" when it's 2–5 characters with no
    /// spaces and contains only letters. This keeps us from e.g. attempting
    /// acronym matches on the query "ost" against every track's show (which
    /// would produce noisy results).
    private static func isLikelyAcronym(_ query: String) -> Bool {
        guard (2...5).contains(query.count) else { return false }
        return query.allSatisfy { $0.isLetter }
    }
}
