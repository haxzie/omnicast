import Foundation

/// What the launcher has learned about which app you mean.
///
/// Every pick is recorded against each prefix of what you typed — `t`, `te`,
/// `ter`, `term` — so two keystrokes next time already have evidence behind
/// them. Weights decay when they are read rather than on a timer, so a habit
/// you drop fades on its own and there is no cleanup job to run.
///
/// Pure value type: no I/O, no clock of its own. `UsageStore` persists it and
/// `LearningReplay` scores it against past decisions.
struct LearningModel {
    /// Longest prefix worth remembering — past this the fuzzy match decides anyway.
    static let maxPrefixLength = 8
    /// Habits are stable, so prefix memory is long-lived.
    static let prefixHalfLifeDays = 30.0
    /// Plain "recently opened" fades faster.
    static let recencyHalfLifeDays = 7.0

    /// A decaying count and the moment it was last touched.
    struct Weight: Equatable {
        var value: Double
        var updatedAt: Date

        func decayed(halfLifeDays: Double, at now: Date) -> Double {
            let days = max(0, now.timeIntervalSince(updatedAt) / 86_400)
            return value * pow(0.5, days / halfLifeDays)
        }
    }

    struct ItemRow: Equatable {
        var itemID: String
        var launches: Weight
        var lastUsed: Date
    }

    struct PrefixRow: Equatable {
        var prefix: String
        var itemID: String
        var weight: Weight
    }

    /// Everything ranking needs for one query, computed once per keystroke
    /// rather than once per candidate.
    struct Memory {
        fileprivate var prefixWeights: [String: Double] = [:]
        fileprivate var prefixTotal: Double = 0
        fileprivate var frecency: [String: Double] = [:]

        static let empty = Memory()

        /// How much this item has learned its way up, added to the fuzzy score.
        func boost(for itemID: String) -> Double {
            var boost = frecency[itemID] ?? 0
            if prefixTotal > 0, let weight = prefixWeights[itemID] {
                // Share of everything ever picked under this prefix, damped
                // until there is enough evidence to trust it.
                let share = weight / prefixTotal
                let confidence = min(1, prefixTotal / 3)
                boost += 140 * share * confidence
            }
            return boost
        }

        /// True when nothing has been learned that touches this query.
        var isEmpty: Bool { prefixWeights.isEmpty && frecency.isEmpty }

        /// Decayed weight this item holds under the current prefix.
        func weight(for itemID: String) -> Double { prefixWeights[itemID] ?? 0 }

        /// Fraction of everything picked under this prefix that went to this
        /// item — 1.0 means it has never lost here.
        func share(of itemID: String) -> Double {
            guard prefixTotal > 0 else { return 0 }
            return weight(for: itemID) / prefixTotal
        }
    }

    private var items: [String: ItemRow] = [:]
    private var prefixes: [String: [String: Weight]] = [:]

    init() {}

    init(items: [ItemRow], prefixes: [PrefixRow]) {
        for row in items { self.items[row.itemID] = row }
        for row in prefixes { self.prefixes[row.prefix, default: [:]][row.itemID] = row.weight }
    }

    // MARK: - Learning

    /// Returns the rows that changed, so the caller can persist just those.
    @discardableResult
    mutating func record(itemID: String, query: String, at now: Date) -> (ItemRow, [PrefixRow]) {
        var item =
            items[itemID]
            ?? ItemRow(itemID: itemID, launches: Weight(value: 0, updatedAt: now), lastUsed: now)
        item.launches = Weight(
            value: item.launches.decayed(halfLifeDays: Self.recencyHalfLifeDays, at: now) + 1,
            updatedAt: now)
        item.lastUsed = now
        items[itemID] = item

        var changed: [PrefixRow] = []
        for prefix in Self.prefixes(of: query) {
            let previous = prefixes[prefix]?[itemID]
            let decayed = previous?.decayed(halfLifeDays: Self.prefixHalfLifeDays, at: now) ?? 0
            let weight = Weight(value: decayed + 1, updatedAt: now)
            prefixes[prefix, default: [:]][itemID] = weight
            changed.append(PrefixRow(prefix: prefix, itemID: itemID, weight: weight))
        }
        return (item, changed)
    }

    // MARK: - Ranking

    func memory(for query: String, at now: Date) -> Memory {
        var memory = Memory()

        for (itemID, item) in items {
            let launches = item.launches.decayed(halfLifeDays: Self.recencyHalfLifeDays, at: now)
            guard launches > 0.01 else { continue }
            // Deliberately smaller than a strong fuzzy match: typing an app's
            // name exactly must always beat "but you open this other one a lot".
            memory.frecency[itemID] = 28 * log2(launches + 1)
        }

        let key = Self.key(for: query)
        if !key.isEmpty, let bucket = prefixes[key] {
            for (itemID, weight) in bucket {
                let value = weight.decayed(halfLifeDays: Self.prefixHalfLifeDays, at: now)
                guard value > 0.01 else { continue }
                memory.prefixWeights[itemID] = value
                memory.prefixTotal += value
            }
        }
        return memory
    }

    // MARK: - Keys

    static func key(for query: String) -> String {
        String(
            query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                .prefix(maxPrefixLength))
    }

    /// `"term"` -> `["t", "te", "ter", "term"]`.
    static func prefixes(of query: String) -> [String] {
        let key = key(for: query)
        guard !key.isEmpty else { return [] }
        return (1...key.count).map { String(key.prefix($0)) }
    }
}
