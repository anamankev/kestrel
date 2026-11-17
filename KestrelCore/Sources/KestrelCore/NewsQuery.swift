import Foundation

/// Headline search. Terms are ANDed and match at word starts, case- and accent-insensitively, so
/// `rate` finds "rates" but `ai` doesn't find "said". `"quoted phrases"` match whole, and `-term`
/// excludes. Headlines are also tagged with the securities they mention.
public struct NewsQuery: Sendable, Equatable {
    public private(set) var include: [String] = []
    public private(set) var exclude: [String] = []

    public static let maxLength = 120

    public init(_ text: String) {
        var s = Substring(text.prefix(Self.maxLength))
        while let q = s.firstIndex(of: "\"") {
            let rest = s[s.index(after: q)...]
            guard let end = rest.firstIndex(of: "\"") else { break }
            let phrase = Self.fold(String(rest[..<end]))
            let negated = q > s.startIndex && s[s.index(before: q)] == "-"
            if !phrase.isEmpty { if negated { exclude.append(phrase) } else { include.append(phrase) } }
            s = s[..<(negated ? s.index(before: q) : q)] + " " + rest[rest.index(after: end)...]
        }
        for word in s.split(whereSeparator: \.isWhitespace) {
            if word.hasPrefix("-"), word.count > 1 { exclude.append(Self.fold(String(word.dropFirst()))) }
            else if word != "-" { include.append(Self.fold(String(word))) }
        }
        include.removeAll { $0.isEmpty }; exclude.removeAll { $0.isEmpty }
    }

    public var isEmpty: Bool { include.isEmpty && exclude.isEmpty }

    public func matches(_ title: String) -> Bool {
        let t = Self.fold(title)
        return include.allSatisfy { Self.contains(t, $0) } && !exclude.contains { Self.contains(t, $0) }
    }

    /// Ranges in `title` to highlight for the included terms.
    public func highlights(in title: String) -> [Range<String.Index>] {
        include.flatMap { term in
            var out: [Range<String.Index>] = [], from = title.startIndex
            while let r = title.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: from..<title.endIndex) {
                if r.lowerBound == title.startIndex || !title[title.index(before: r.lowerBound)].isLetterOrNumber { out.append(r) }
                from = r.upperBound
            }
            return out
        }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: .whitespaces)
    }

    /// Word-start containment on already-folded text.
    static func contains(_ text: String, _ term: String) -> Bool {
        var from = text.startIndex
        while let r = text.range(of: term, range: from..<text.endIndex) {
            if r.lowerBound == text.startIndex || !text[text.index(before: r.lowerBound)].isLetterOrNumber { return true }
            from = text.index(after: r.lowerBound)
        }
        return false
    }

    /// Whole-word containment (a trailing possessive or punctuation still counts).
    static func containsWord(_ text: String, _ word: String) -> Bool {
        var from = text.startIndex
        while let r = text.range(of: word, range: from..<text.endIndex) {
            let startOK = r.lowerBound == text.startIndex || !text[text.index(before: r.lowerBound)].isLetterOrNumber
            let endOK = r.upperBound == text.endIndex || !text[r.upperBound].isLetterOrNumber
            if startOK && endOK { return true }
            from = text.index(after: r.lowerBound)
        }
        return false
    }

    /// Securities a headline mentions: an exact ticker in capitals (`NVDA`, `$TSLA`) or the
    /// company's distinctive first name word ("Nvidia", "Microsoft"). Common words are skipped.
    public static func mentions(_ title: String, in universe: [Instrument] = Universe.equities + Universe.crypto) -> [Instrument] {
        let words = Set(title.split { !$0.isLetter && !$0.isNumber && $0 != "$" }.map { String($0).trimmingCharacters(in: ["$"]) })
        let folded = fold(title)
        return universe.filter { i in
            if i.ticker.count >= 2, words.contains(i.ticker) { return true }
            guard let first = i.name.split(separator: " ").first.map(String.init), first.count >= 4,
                  !genericNames.contains(first.lowercased()) else { return false }
            return containsWord(folded, fold(first.trimmingCharacters(in: .punctuationCharacters)))
        }
    }

    private static let genericNames: Set<String> = ["the", "first", "general", "american", "united", "international", "bank", "global", "spdr", "invesco", "ishares"]
}

extension Character {
    var isLetterOrNumber: Bool { isLetter || isNumber }
}
