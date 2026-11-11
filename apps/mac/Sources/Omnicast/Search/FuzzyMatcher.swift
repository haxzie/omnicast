import Foundation

/// Sublime-style fuzzy matching: a subsequence match, scored so that matches at
/// word boundaries, acronyms and consecutive runs float to the top.
///
/// The matcher is pure and allocation-light because it runs over every
/// candidate on every keystroke.
enum FuzzyMatcher {
    struct Match {
        var score: Double
        /// Indices (into the haystack's character array) that matched, for highlighting.
        var indices: [Int]
    }

    private enum Bonus {
        static let consecutive = 12.0
        static let wordStart = 30.0
        static let camelCase = 22.0
        static let afterSeparator = 26.0
        static let firstCharacter = 40.0
        static let exactPrefix = 60.0
        static let exactMatch = 120.0
        static let unmatchedPenalty = -1.2
        static let leadingPenalty = -2.0
        static let maxLeadingPenalty = -24.0
    }

    /// `nil` when the needle is not a subsequence of the haystack.
    static func match(needle: String, haystack: String) -> Match? {
        if needle.isEmpty { return Match(score: 1, indices: []) }

        let needleChars = Array(needle.lowercased())
        let haystackOriginal = Array(haystack)
        let haystackChars = Array(haystack.lowercased())
        guard needleChars.count <= haystackChars.count else { return nil }

        // Cheap rejection before the scoring pass.
        var cursor = 0
        for character in needleChars {
            guard let next = haystackChars[cursor...].firstIndex(of: character) else { return nil }
            cursor = next + 1
        }

        var best: Match?
        // Try each possible starting position for the first needle character so
        // "code" prefers "Visual Studio *Code*" over an early scattered match.
        for start in haystackChars.indices where haystackChars[start] == needleChars[0] {
            if let candidate = score(
                needleChars, haystackChars, haystackOriginal, startingAt: start),
                candidate.score > (best?.score ?? -.infinity)
            {
                best = candidate
            }
            // Four anchors is plenty; beyond that the score can only get worse.
            if (best?.indices.count ?? 0) == needleChars.count, start > 3 { break }
        }

        guard var result = best else { return nil }
        let lowerHaystack = String(haystackChars)
        let lowerNeedle = String(needleChars)
        if lowerHaystack == lowerNeedle {
            result.score += Bonus.exactMatch
        } else if lowerHaystack.hasPrefix(lowerNeedle) {
            result.score += Bonus.exactPrefix
        }
        // Shorter haystacks with the same match quality are more likely to be
        // what the user meant ("Mail" over "Mailbox Importer").
        result.score += 20.0 / Double(max(haystackChars.count, 1))
        return result
    }

    private static func score(
        _ needle: [Character], _ haystack: [Character], _ original: [Character], startingAt start: Int
    ) -> Match? {
        var indices: [Int] = []
        indices.reserveCapacity(needle.count)

        var total = max(Bonus.maxLeadingPenalty, Double(start) * Bonus.leadingPenalty)
        var needleIndex = 0
        var haystackIndex = start
        var previousMatched = false

        while needleIndex < needle.count, haystackIndex < haystack.count {
            if haystack[haystackIndex] == needle[needleIndex] {
                var points = 10.0
                if previousMatched { points += Bonus.consecutive }
                if haystackIndex == 0 {
                    points += Bonus.firstCharacter
                } else {
                    let previous = haystack[haystackIndex - 1]
                    if previous == " " || previous == "\t" {
                        points += Bonus.wordStart
                    } else if previous == "-" || previous == "_" || previous == "/" || previous == "." {
                        points += Bonus.afterSeparator
                    } else if original[haystackIndex].isUppercase, original[haystackIndex - 1].isLowercase {
                        points += Bonus.camelCase
                    }
                }
                total += points
                indices.append(haystackIndex)
                needleIndex += 1
                previousMatched = true
            } else {
                total += previousMatched ? Bonus.unmatchedPenalty : 0
                previousMatched = false
            }
            haystackIndex += 1
        }

        guard needleIndex == needle.count else { return nil }
        return Match(score: total, indices: indices)
    }
}
