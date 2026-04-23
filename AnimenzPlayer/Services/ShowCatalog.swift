import Foundation

/// Canonical show names, alias expansions, and derivation rules. This is the
/// one place the rest of Wave 3 consults when it needs to answer "what show
/// does this track belong to?" or "what show does this query mean?".
///
/// The catalog is intentionally code-resident (not user-editable) for Wave 3.
/// A future wave can layer `PersistenceStore.State.userAliases` on top of
/// `canonicalAliases` without changing the callers.
enum ShowCatalog {

    // MARK: - Canonical shows
    //
    // Ordered roughly by popularity in the bundled library. Derivation uses
    // longest-match-wins (see `derivedShow(from:)`), so it's safe to include
    // overlapping names — "Attack on Titan" will always beat "Attack on" if
    // both were listed.
    static let knownShows: [String] = [
        "Attack on Titan",
        "Jujutsu Kaisen",
        "Sword Art Online",
        "Fullmetal Alchemist",
        "My Hero Academia",
        "Boku no Hero Academia",
        "Chainsaw Man",
        "Demon Slayer",
        "Neon Genesis Evangelion",
        "Fate/stay night",
        "Fate/Zero",
        "Fate/zero",
        "Kill la Kill",
        "JoJo's Bizarre Adventure",
        "No Game No Life",
        "Made in Abyss",
        "HUNTER×HUNTER",
        "Frieren",
        "SPY×FAMILY",
        "Violet Evergarden",
        "Naruto Shippuden",
        "Naruto Shippuuden",
        "Naruto",
        "Death Note",
        "Tokyo Ghoul",
        "Tokyo Revengers",
        "Your Name",
        "Kimi no Na wa",
        "Howl's Moving Castle",
        "Oshi no Ko",
        "Code Geass",
        "Guilty Crown",
        "Haikyuu",
        "Re:ZERO",
        "Re：ZERO",
        "Steins;Gate",
        "Clannad",
        "K-ON",
        "Puella Magi Madoka Magica",
        "Angel Beats",
        "Noragami",
        "Bakemonogatari",
        "NieR:Automata",
        "NieR： Automata",
        "KonoSuba",
        "Kantai Collection",
        "Love Live",
        "Soul Eater",
        "Mirai Nikki",
        "Psycho-Pass",
        "One Piece",
        "Digimon",
        "Dragon Ball",
        "Sailor Moon",
        "Inuyasha",
        "Evangelion",
        "BEASTARS",
        "Black Clover",
        "Ousama Ranking",
        "BanG Dream",
        "Gurren Lagann",
        "Ghibli",
        "Pokémon",
        "Detective Conan",
        "Suzume",
        "Weathering with You",
        "Tenki no Ko",
        "5 Centimeters per Second",
        "Fireworks",
        "Your Lie in April",
        "Spice and Wolf",
        "AnoHana",
        "Nagi no Asu kara",
        "Little Busters",
        "A Silent Voice",
        "Koe no Katachi",
        "Kekkai Sensen",
        "GochiUsa",
        "Amagi Brilliant Park",
        "Mahouka Koukou no Rettousei",
        "Kabaneri of the Iron Fortress",
        "Zombie Land Saga",
        "Kyoukai no Kanata",
        "Mahoutsukai no Yome",
        "Yuri!!! on ICE",
        "Aldnoah.Zero",
        "Aldnoah",
        "Shakugan no Shana",
        "Oregairu",
        "Domestic na Kanojo",
        "Non Non Biyori",
        "Gatchaman Crowds",
        "Selector Infected WIXOSS",
        "Expelled from Paradise",
        "Nodame Cantabile",
        "Rewrite",
        "Kyousougiga",
        "Eighty-Six",
        "86",
    ]

    // MARK: - Aliases
    //
    // Keys are lowercase. Values are one of `knownShows`.
    // Adding a new alias is a one-line change that the search engine picks
    // up without further wiring.
    static let canonicalAliases: [String: String] = [
        "aot":   "Attack on Titan",
        "snk":   "Attack on Titan",   // Shingeki no Kyojin
        "jjk":   "Jujutsu Kaisen",
        "sao":   "Sword Art Online",
        "fma":   "Fullmetal Alchemist",
        "fmab":  "Fullmetal Alchemist",
        "mha":   "My Hero Academia",
        "bnha":  "My Hero Academia",
        "csm":   "Chainsaw Man",
        "kny":   "Demon Slayer",       // Kimetsu no Yaiba
        "nge":   "Neon Genesis Evangelion",
        "eva":   "Neon Genesis Evangelion",
        "fsn":   "Fate/stay night",
        "klk":   "Kill la Kill",
        "jjba":  "JoJo's Bizarre Adventure",
        "jojo":  "JoJo's Bizarre Adventure",
        "ngnl":  "No Game No Life",
        "mia":   "Made in Abyss",
        "hxh":   "HUNTER×HUNTER",
        "hunterxhunter": "HUNTER×HUNTER",
        "ve":    "Violet Evergarden",
        "sxf":   "SPY×FAMILY",
        "spyxfamily": "SPY×FAMILY",
        "ttgl":  "Gurren Lagann",
        "madoka": "Puella Magi Madoka Magica",
        "pmmm":  "Puella Magi Madoka Magica",
        "ghibli": "Ghibli",
        "rezero": "Re:ZERO",
        "konosuba": "KonoSuba",
        "kancolle": "Kantai Collection",
        "lovelive": "Love Live",
    ]

    // MARK: - API

    /// Resolve a user query to a canonical show, via the alias table.
    /// Case-insensitive. Returns nil if the query is not a known alias.
    ///
    /// Note: this deliberately does NOT do substring matching on the
    /// knownShows list — typing "Titan" isn't an alias for Attack on Titan,
    /// it's a substring the search engine handles separately.
    static func canonicalShow(for query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        return canonicalAliases[trimmed]
    }

    /// Find the known show that appears in the title, preferring the longest
    /// match. Case-insensitive. Returns nil if the title doesn't mention any
    /// known show.
    ///
    /// Longest-match-wins so that "My Hero Academia" beats "Boku no Hero
    /// Academia" if both were somehow listed — or more usefully, so that
    /// "Fate/stay night" wins over a bare "Fate".
    static func derivedShow(from title: String) -> String? {
        // Sort once at first use, not per-call.
        let haystack = title.lowercased()
        for show in sortedByLength {
            if haystack.contains(show.lowercased()) {
                // Normalize alternate punctuations (e.g. "Re：ZERO" → "Re:ZERO")
                // to a single canonical form.
                return canonicalize(show)
            }
        }
        return nil
    }

    /// First-letter acronym of a show name. Splits on whitespace and a small
    /// set of punctuation. Uppercased.
    ///
    /// Examples:
    ///   "My Hero Academia" → "MHA"
    ///   "No Game No Life" → "NGNL"
    ///   "Attack on Titan" → "AOT"
    ///
    /// Does NOT produce repeated-letter acronyms like "JJK" for Jujutsu
    /// Kaisen — those should live in the alias table instead.
    static func acronym(of show: String) -> String {
        let separators = CharacterSet.whitespaces
            .union(CharacterSet(charactersIn: "-/:；;："))
        let tokens = show.components(separatedBy: separators).filter { !$0.isEmpty }
        return tokens.compactMap { $0.first }.map { String($0).uppercased() }.joined()
    }

    // MARK: - Private

    /// `knownShows` cached in length-descending order so derivation can skip
    /// the sort on every call.
    private static let sortedByLength: [String] = knownShows
        .sorted { $0.count > $1.count }

    /// Punctuation normalization. The bundled library mixes halfwidth and
    /// fullwidth colons in show names; callers should see one canonical form.
    private static func canonicalize(_ show: String) -> String {
        // Prefer ASCII forms of punctuation for the returned canonical name.
        var s = show
        s = s.replacingOccurrences(of: "：", with: ":")
        return s
    }
}
