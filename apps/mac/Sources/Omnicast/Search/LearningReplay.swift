import Foundation

/// Scores the ranker against decisions it already made.
///
/// Replays the pick log chronologically into a fresh `LearningModel`: for each
/// logged decision it re-ranks the candidates that were on screen, notes where
/// the row you actually picked landed, and only then learns from it. That
/// ordering matters — scoring a pick the model has already seen would measure
/// memorisation rather than prediction.
///
/// Compares against the fuzzy score alone, so a weight change can be judged by
/// the lift it produces instead of by how it feels.
enum LearningReplay {
    struct Metrics: Equatable {
        var picks: Int = 0
        /// Share of picks the ranker put first.
        var top1: Double = 0
        /// Mean reciprocal rank — credit for second and third place too.
        var meanReciprocalRank: Double = 0
    }

    struct Result: Equatable {
        var baseline: Metrics
        var learned: Metrics

        var top1Lift: Double { learned.top1 - baseline.top1 }
    }

    static func evaluate(_ picks: [UsageStore.LoggedPick]) -> Result {
        var model = LearningModel()
        var baseline = Metrics()
        var learned = Metrics()
        var counted = 0

        for pick in picks {
            guard !pick.shown.isEmpty,
                pick.shown.contains(where: { $0.id == pick.pickedID })
            else { continue }
            counted += 1

            let memory = model.memory(for: pick.query, at: pick.createdAt)
            accumulate(
                into: &baseline,
                rank: rank(of: pick.pickedID, in: pick.shown) { _, base in base })
            accumulate(
                into: &learned,
                rank: rank(of: pick.pickedID, in: pick.shown) { id, base in
                    base + memory.boost(for: id)
                })

            model.record(itemID: pick.pickedID, query: pick.query, at: pick.createdAt)
        }

        return Result(
            baseline: finish(baseline, over: counted), learned: finish(learned, over: counted))
    }

    static func report(for picks: [UsageStore.LoggedPick]) -> String {
        let result = evaluate(picks)
        guard result.learned.picks > 0 else {
            return "No picks logged yet — open a few apps from the launcher first."
        }

        func percent(_ value: Double) -> String { String(format: "%5.1f%%", value * 100) }
        func rank(_ value: Double) -> String { String(format: "%.3f", value) }

        return """
            Replayed \(result.learned.picks) picks

                           top-1     MRR
            fuzzy only    \(percent(result.baseline.top1))   \(rank(result.baseline.meanReciprocalRank))
            + learning    \(percent(result.learned.top1))   \(rank(result.learned.meanReciprocalRank))

            top-1 lift: \(percent(result.top1Lift))
            """
    }

    // MARK: - Internals

    /// 1-based position of `itemID` once the candidates are sorted by `score`.
    private static func rank(
        of itemID: String, in shown: [(id: String, base: Double)],
        score: (String, Double) -> Double
    ) -> Int? {
        let ordered = shown
            .map { (id: $0.id, score: score($0.id, $0.base)) }
            // Ties keep the order they were shown in, which is what the user saw.
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.score == rhs.element.score
                    ? lhs.offset < rhs.offset : lhs.element.score > rhs.element.score
            }
        guard let index = ordered.firstIndex(where: { $0.element.id == itemID }) else { return nil }
        return index + 1
    }

    private static func accumulate(into metrics: inout Metrics, rank: Int?) {
        guard let rank else { return }
        if rank == 1 { metrics.top1 += 1 }
        metrics.meanReciprocalRank += 1 / Double(rank)
    }

    private static func finish(_ metrics: Metrics, over count: Int) -> Metrics {
        guard count > 0 else { return Metrics() }
        return Metrics(
            picks: count, top1: metrics.top1 / Double(count),
            meanReciprocalRank: metrics.meanReciprocalRank / Double(count))
    }
}
