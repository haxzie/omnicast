import XCTest

@testable import Omnicast

final class LearningModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let terminal = "app:com.apple.Terminal"
    private let textEdit = "app:com.apple.TextEdit"

    func testPickTeachesEveryPrefixOfTheQuery() {
        var model = LearningModel()
        model.record(itemID: terminal, query: "term", at: now)

        // Two keystrokes already carry the evidence from the full word.
        for query in ["t", "te", "ter", "term"] {
            let boost = model.memory(for: query, at: now).boost(for: terminal)
            XCTAssertGreaterThan(boost, 0, "prefix \(query)")
        }
        // But not a prefix that was never typed.
        XCTAssertEqual(model.memory(for: "x", at: now).share(of: terminal), 0)
    }

    func testRepeatedPicksOutrankAnOccasionalOne() {
        var model = LearningModel()
        for _ in 0..<4 { model.record(itemID: terminal, query: "te", at: now) }
        model.record(itemID: textEdit, query: "te", at: now)

        let memory = model.memory(for: "te", at: now)
        XCTAssertGreaterThan(memory.boost(for: terminal), memory.boost(for: textEdit))
    }

    func testConfidenceDampsASingleObservation() {
        var once = LearningModel()
        once.record(itemID: terminal, query: "te", at: now)

        var settled = LearningModel()
        for _ in 0..<3 { settled.record(itemID: terminal, query: "te", at: now) }

        // Same 100% share, but one pick is not yet evidence.
        XCTAssertLessThan(
            once.memory(for: "te", at: now).boost(for: terminal),
            settled.memory(for: "te", at: now).boost(for: terminal))
    }

    func testPrefixMemoryHalvesOverItsHalfLife() {
        var model = LearningModel()
        for _ in 0..<6 { model.record(itemID: terminal, query: "te", at: now) }
        let fresh = model.memory(for: "te", at: now).weight(for: terminal)

        let later = now.addingTimeInterval(LearningModel.prefixHalfLifeDays * 86_400)
        let decayed = model.memory(for: "te", at: later).weight(for: terminal)

        XCTAssertEqual(decayed, fresh / 2, accuracy: 0.001)
    }

    func testAHabitDroppedLongAgoFadesAway() {
        var model = LearningModel()
        for _ in 0..<5 { model.record(itemID: terminal, query: "te", at: now) }

        let muchLater = now.addingTimeInterval(365 * 86_400)
        XCTAssertLessThan(model.memory(for: "te", at: muchLater).boost(for: terminal), 1)
    }

    func testZeroStateRanksByWhatYouActuallyOpen() {
        var model = LearningModel()
        for _ in 0..<5 { model.record(itemID: terminal, query: "term", at: now) }
        model.record(itemID: textEdit, query: "text", at: now)

        // An empty query has no prefix to go on, so only frecency speaks.
        let memory = model.memory(for: "", at: now)
        XCTAssertGreaterThan(memory.boost(for: terminal), memory.boost(for: textEdit))
        XCTAssertEqual(memory.boost(for: "app:never.opened"), 0)
    }

    func testQueriesAreNormalised() {
        var model = LearningModel()
        model.record(itemID: terminal, query: "  TeRm  ", at: now)
        XCTAssertGreaterThan(model.memory(for: "te", at: now).boost(for: terminal), 0)
    }

    func testPrefixesAreCapped() {
        XCTAssertEqual(LearningModel.prefixes(of: "a"), ["a"])
        XCTAssertEqual(LearningModel.prefixes(of: "").count, 0)
        XCTAssertEqual(
            LearningModel.prefixes(of: "supercalifragilistic").count, LearningModel.maxPrefixLength)
    }
}

final class LearningReplayTests: XCTestCase {
    private let terminal = "app:com.apple.Terminal"
    private let textEdit = "app:com.apple.TextEdit"

    /// A user who always means Terminal when they type "te", even though the
    /// fuzzy matcher prefers TextEdit.
    private func picks(count: Int) -> [UsageStore.LoggedPick] {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<count).map { index in
            UsageStore.LoggedPick(
                query: "te",
                shown: [(id: textEdit, base: 200), (id: terminal, base: 150)],
                pickedID: terminal,
                createdAt: start.addingTimeInterval(Double(index) * 3_600))
        }
    }

    func testLearningBeatsFuzzyAloneOnARepeatedHabit() {
        let result = LearningReplay.evaluate(picks(count: 12))

        XCTAssertEqual(result.learned.picks, 12)
        // Fuzzy alone never gets it right: TextEdit always scores higher.
        XCTAssertEqual(result.baseline.top1, 0, accuracy: 0.001)
        XCTAssertGreaterThan(result.learned.top1, 0.8)
        XCTAssertGreaterThan(result.top1Lift, 0.8)
    }

    func testTheFirstPickIsScoredBeforeItIsLearnedFrom() {
        // With one pick there is nothing learned yet, so it must score as
        // badly as the baseline — otherwise replay is measuring memorisation.
        let result = LearningReplay.evaluate(picks(count: 1))
        XCTAssertEqual(result.learned.top1, result.baseline.top1, accuracy: 0.001)
    }

    func testEmptyLogReportsCleanly() {
        XCTAssertTrue(LearningReplay.report(for: []).contains("No picks logged yet"))
        XCTAssertEqual(LearningReplay.evaluate([]).learned.picks, 0)
    }

    func testPicksMissingFromTheirOwnCandidateListAreSkipped() {
        let orphan = UsageStore.LoggedPick(
            query: "te", shown: [(id: textEdit, base: 10)], pickedID: "app:gone",
            createdAt: Date())
        XCTAssertEqual(LearningReplay.evaluate([orphan]).learned.picks, 0)
    }
}

final class UsageStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnicast-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLearningSurvivesARestart() {
        let terminal = "app:com.apple.Terminal"
        let store = UsageStore(directory: directory)
        store.record(
            itemID: terminal, query: "term",
            shown: [(id: terminal, base: 120)], pickedIndex: 0)

        let reopened = UsageStore(directory: directory)
        XCTAssertGreaterThan(reopened.memory(for: "te").boost(for: terminal), 0)
    }

    func testPickLogRoundTrips() {
        let store = UsageStore(directory: directory)
        store.record(
            itemID: "app:a", query: "Ab",
            shown: [(id: "app:b", base: 90.5), (id: "app:a", base: 40)], pickedIndex: 1)

        let picks = store.loggedPicks()
        XCTAssertEqual(picks.count, 1)
        XCTAssertEqual(picks.first?.query, "ab")
        XCTAssertEqual(picks.first?.pickedID, "app:a")
        XCTAssertEqual(picks.first?.shown.count, 2)
        XCTAssertEqual(picks.first?.shown.first?.base ?? 0, 90.5, accuracy: 0.001)
    }

    func testResetForgetsEverything() {
        let store = UsageStore(directory: directory)
        store.record(itemID: "app:a", query: "a", shown: [(id: "app:a", base: 1)], pickedIndex: 0)
        store.reset()

        XCTAssertEqual(store.memory(for: "a").boost(for: "app:a"), 0)
        XCTAssertTrue(store.loggedPicks().isEmpty)
    }
}

final class TranscriptionErrorTests: XCTestCase {
    func testSystemDictationErrorsBecomeActionableAdvice() {
        // macOS says "Siri and Dictation are disabled", which tells the user
        // nothing about what to do next.
        let system = NSError(
            domain: "kAFAssistantErrorDomain", code: 1_700,
            userInfo: [NSLocalizedDescriptionKey: "Siri and Dictation are disabled"])

        guard case .engineMissing(let hint) = AppleSpeechTranscriber.mapped(system) else {
            return XCTFail("expected actionable advice, got \(AppleSpeechTranscriber.mapped(system))")
        }
        XCTAssertEqual(hint, AppleSpeechTranscriber.disabledHint)
        XCTAssertTrue(hint.contains("System Settings"))
    }

    func testUnrelatedFailuresKeepTheirOwnMessage() {
        let other = NSError(
            domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "audio file is empty"])
        guard case .failed(let message) = AppleSpeechTranscriber.mapped(other) else {
            return XCTFail("expected the original failure to survive")
        }
        XCTAssertEqual(message, "audio file is empty")
    }

    func testMissingModelAdviceFitsTheIndicator() {
        // The droplet shows this on two short lines; keep it short enough to read.
        let message = TranscriptionError.noModelInstalled.errorDescription ?? ""
        XCTAssertLessThan(message.count, 60)
        XCTAssertTrue(message.localizedCaseInsensitiveContains("model"))
    }
}

final class AudioLevelTests: XCTestCase {
    /// RMS of a full-scale sine is 1/√2, so a given dBFS maps to this amplitude.
    private func rms(dBFS: Float) -> Float { pow(10, dBFS / 20) }

    func testOrdinarySpeechReadsAsAStrongSignal() {
        // A built-in mic at arm's length sits around -30 dBFS. If that only
        // moves the meter a third of the way, the waveform looks dead.
        let level = AudioLevel.normalized(rms: rms(dBFS: -30))
        XCTAssertGreaterThan(level, 0.6, "normal speech should drive most of the range")
        XCTAssertLessThan(level, 1.0, "with headroom left for a raised voice")
    }

    func testQuietSpeechStillRegisters() {
        XCTAssertGreaterThan(AudioLevel.normalized(rms: rms(dBFS: -40)), 0.35)
    }

    func testRoomToneStaysNearZero() {
        XCTAssertLessThan(AudioLevel.normalized(rms: rms(dBFS: -58)), 0.05)
        XCTAssertEqual(AudioLevel.normalized(rms: 0), 0, accuracy: 0.001)
    }

    func testLoudSpeechSaturates() {
        XCTAssertEqual(AudioLevel.normalized(rms: rms(dBFS: -10)), 1, accuracy: 0.001)
        XCTAssertEqual(AudioLevel.normalized(rms: 1), 1, accuracy: 0.001)
    }

    func testResponseIsMonotonic() {
        let levels = stride(from: Float(-60), through: 0, by: 5)
            .map { AudioLevel.normalized(rms: rms(dBFS: $0)) }
        for (lower, higher) in zip(levels, levels.dropFirst()) {
            XCTAssertLessThanOrEqual(lower, higher)
        }
    }

    func testRMSOfAKnownSignal() {
        // A ±0.5 square wave has an RMS of exactly 0.5.
        var samples = (0..<1024).map { $0.isMultiple(of: 2) ? Float(0.5) : Float(-0.5) }
        let value = samples.withUnsafeBufferPointer {
            AudioLevel.rms($0.baseAddress!, count: $0.count)
        }
        XCTAssertEqual(value, 0.5, accuracy: 0.0001)
        XCTAssertEqual(samples.count, 1024)
    }

    func testSilenceIsSilent() {
        let samples = [Float](repeating: 0, count: 512)
        let value = samples.withUnsafeBufferPointer {
            AudioLevel.rms($0.baseAddress!, count: $0.count)
        }
        XCTAssertEqual(value, 0, accuracy: 0.0001)
    }
}

final class ShaderTimeTests: XCTestCase {
    private let epoch = Date(timeIntervalSinceReferenceDate: 785_000_000)

    func testTimeAdvancesBetweenFrames() {
        let frame = epoch.addingTimeInterval(1.0 / 60)
        let a = SiriWaveView.shaderTime(epoch, since: epoch)
        let b = SiriWaveView.shaderTime(frame, since: epoch)
        XCTAssertNotEqual(a, b, "a shader fed the same time every frame draws a frozen wave")
        XCTAssertEqual(b - a, 1.0 / 60, accuracy: 0.0005)
    }

    func testAbsoluteTimeWouldNotSurviveFloat32() {
        // Documents the bug this epoch exists to avoid: near 7.85e8 a float32
        // steps in jumps of 1024 seconds, so every frame carries an identical
        // value and the wave never moves.
        let now = Date(timeIntervalSinceReferenceDate: 785_000_000)
        let nextFrame = now.addingTimeInterval(1.0 / 60)
        XCTAssertEqual(
            Float(now.timeIntervalSinceReferenceDate),
            Float(nextFrame.timeIntervalSinceReferenceDate),
            "if these ever differ, float32 got more precise and this guard can go")
    }

    func testTimeStaysSmallOverALongSession() {
        // A week in, the value must still carry sub-frame precision.
        let later = epoch.addingTimeInterval(7 * 86_400 + 12.5)
        let time = SiriWaveView.shaderTime(later, since: epoch)
        XCTAssertLessThan(time, 3600)
        let nextFrame = SiriWaveView.shaderTime(
            later.addingTimeInterval(1.0 / 60), since: epoch)
        XCTAssertNotEqual(time, nextFrame)
    }
}

final class SearchModeTests: XCTestCase {
    func testEmptyApplicationSearchPredicts() {
        XCTAssertTrue(SearchEngine.predicts(query: "", mode: .applications))
    }

    func testTypingStopsPredicting() {
        XCTAssertFalse(SearchEngine.predicts(query: "saf", mode: .applications))
    }

    func testBrowsersListEverythingWhenTheFilterIsEmpty() {
        // Predicting here would hide every clip and recording you have not
        // already opened from the launcher, which is all of them.
        XCTAssertFalse(SearchEngine.predicts(query: "", mode: .clipboard))
        XCTAssertFalse(SearchEngine.predicts(query: "", mode: .dictation))
    }

    func testBrowsersAreTheOnesWithADetailPane() {
        XCTAssertTrue(SearchEngine.Mode.clipboard.isBrowser)
        XCTAssertTrue(SearchEngine.Mode.dictation.isBrowser)
        XCTAssertFalse(SearchEngine.Mode.applications.isBrowser)
    }
}

final class BrowserEntryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnicast-browse-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testClipboardEntriesCopyOnReturnAndCarryTheirDetail() async {
        let store = ClipboardStore(directory: directory)
        store.insert(
            ClipboardEntry(
                id: "a", content: .text, text: "ship the glass panel",
                preview: "ship the glass panel", sourceAppName: "Notes",
                sourceBundleID: "com.apple.Notes", copiedAt: Date(), pinned: false,
                imagePath: nil))

        let items = await ClipboardProvider(store: store, browsing: true).items(for: "")
        let item = try? XCTUnwrap(items.first)

        XCTAssertEqual(item?.action, .copyText("ship the glass panel"))
        XCTAssertEqual(item?.section, "Most recent")
        guard case .clipboard(let entry)? = item?.detail else {
            return XCTFail("the detail pane needs the whole entry")
        }
        XCTAssertEqual(entry.sourceAppName, "Notes")
    }

    func testPinnedClipsAreTheirOwnSection() async {
        let store = ClipboardStore(directory: directory)
        store.insert(
            ClipboardEntry(
                id: "p", content: .text, text: "pinned", preview: "pinned",
                sourceAppName: nil, sourceBundleID: nil, copiedAt: Date(), pinned: true,
                imagePath: nil))

        let items = await ClipboardProvider(store: store, browsing: true).items(for: "")
        XCTAssertEqual(items.first?.section, "Pinned")
    }

    func testRecordingsCopyOnReturnAndGroupByDay() async {
        let store = DictationStore(directory: directory)
        store.insert(
            DictationEntry(
                id: "d", text: "hello there", durationMs: 2_000, transcribeMs: 100,
                modelID: "base.en-q5_1", appName: "Slack", appBundleID: nil, language: "en",
                createdAt: Date()))

        let items = await DictationProvider(store: store, browsing: true).items(for: "")
        XCTAssertEqual(items.first?.action, .copyText("hello there"))
        XCTAssertEqual(items.first?.section, "Today")
        guard case .dictation(let entry)? = items.first?.detail else {
            return XCTFail("the detail pane needs the whole entry")
        }
        XCTAssertEqual(entry.modelID, "base.en-q5_1")
    }

    func testBothBrowsersAreReachableFromTheLauncher() async {
        let items = await PaneProvider().items(for: "clip")
        XCTAssertEqual(items.first?.title, "Clipboard History")
        XCTAssertEqual(items.first?.action, .openPane(.clipboard))

        let recordings = await PaneProvider().items(for: "recordings")
        XCTAssertEqual(recordings.first?.action, .openPane(.dictation))

        // Keywords reach them too, not just the exact titles.
        let byKeyword = await PaneProvider().items(for: "transcript")
        XCTAssertTrue(byKeyword.contains { $0.action == .openPane(.dictation) })
    }
}

final class BackspaceNavigationTests: XCTestCase {
    func testBackspaceLeavesABrowserWhenTheFilterIsEmpty() {
        XCTAssertTrue(SearchEngine.backspaceExits(query: "", mode: .clipboard))
        XCTAssertTrue(SearchEngine.backspaceExits(query: "", mode: .dictation))
    }

    func testBackspaceStillDeletesWhileThereIsSomethingToDelete() {
        XCTAssertFalse(SearchEngine.backspaceExits(query: "a", mode: .clipboard))
        XCTAssertFalse(SearchEngine.backspaceExits(query: "glass", mode: .dictation))
    }

    func testBackspaceAtTheRootIsJustBackspace() {
        // Nothing to go back to, and swallowing it would break typing.
        XCTAssertFalse(SearchEngine.backspaceExits(query: "", mode: .applications))
        XCTAssertFalse(SearchEngine.backspaceExits(query: "saf", mode: .applications))
    }
}

final class QuickLinkTests: XCTestCase {
    func testTrashAndApplicationsAreReachable() async {
        let items = await QuickLinkProvider().items(for: "trash")
        XCTAssertEqual(items.first?.title, "Trash")
        XCTAssertEqual(items.first?.kind, .folder)

        let apps = await QuickLinkProvider().items(for: "applications")
        XCTAssertEqual(apps.first?.title, "Applications")
        XCTAssertEqual(apps.first?.action, .openURL(URL(fileURLWithPath: "/Applications")))
    }

    func testKeywordsReachThemToo() async {
        let bin = await QuickLinkProvider().items(for: "bin")
        XCTAssertTrue(bin.contains { $0.title == "Trash" })

        let photos = await QuickLinkProvider().items(for: "photos")
        XCTAssertTrue(photos.contains { $0.title == "Pictures" })
    }

    func testEveryOfferedLinkActuallyExists() async {
        // A link to somewhere this Mac does not have is worse than no link.
        for item in await QuickLinkProvider().items(for: "") {
            guard case .openURL(let url) = item.action else { continue }
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path),
                "\(item.title) points at \(url.path), which is not there")
        }
    }

    func testFoldersNeverOutweighApplications() async {
        // "music" must land on Music.app, not the Music folder.
        let provider = ApplicationProvider()
        await provider.prepare()

        let links = await QuickLinkProvider().items(for: "")
        let apps = await provider.items(for: "")
        XCTAssertFalse(links.isEmpty)
        XCTAssertFalse(apps.isEmpty)
        XCTAssertLessThan(links[0].weight, apps[0].weight)
    }
}

final class ApplicationIndexTests: XCTestCase {
    /// Finder lives in /System/Library/CoreServices, which is otherwise full
    /// of internal agents — it was missing from the index entirely.
    func testFinderIsIndexed() async {
        let provider = ApplicationProvider()
        await provider.prepare()
        let items = await provider.items(for: "finder")
        XCTAssertEqual(items.first?.title, "Finder")
    }

    func testTheUsualApplicationsAreIndexed() async {
        let provider = ApplicationProvider()
        await provider.prepare()
        for name in ["Safari", "Mail", "Terminal"] {
            let items = await provider.items(for: name)
            XCTAssertEqual(items.first?.title, name, "\(name) should be the top hit for its name")
        }
    }
}

final class URLDetectorTests: XCTestCase {
    func testPlainDomainsAreAddresses() {
        XCTAssertEqual(URLDetector.url(from: "github.com")?.absoluteString, "https://github.com")
        XCTAssertEqual(
            URLDetector.url(from: "news.ycombinator.com/news")?.absoluteString,
            "https://news.ycombinator.com/news")
    }

    func testSchemesAreHonoured() {
        XCTAssertEqual(
            URLDetector.url(from: "http://example.org")?.absoluteString, "http://example.org")
        // Somebody else's scheme is not ours to open as a web page.
        XCTAssertNil(URLDetector.url(from: "slack://channel?team=T1"))
        XCTAssertNil(URLDetector.url(from: "file:///etc/hosts"))
    }

    func testLocalhostCountsEvenWithoutADot() {
        XCTAssertEqual(
            URLDetector.url(from: "localhost:3000")?.absoluteString, "http://localhost:3000")
    }

    func testFilenamesAreNotAddresses() {
        // .md, .sh and .app are all real top-level domains, which is exactly
        // why a naive "has a dot" check turns every filename into a URL —
        // and inside a launcher these are overwhelmingly files and bundles.
        XCTAssertNil(URLDetector.url(from: "readme.md"))
        XCTAssertNil(URLDetector.url(from: "build.sh"))
        XCTAssertNil(URLDetector.url(from: "Omnicast.app"))
    }

    func testCollidingDomainsStillWorkWithAPathOrScheme() {
        // The escape hatches, for when you really do mean the website.
        XCTAssertEqual(
            URLDetector.url(from: "linear.app/pricing")?.absoluteString,
            "https://linear.app/pricing")
        XCTAssertEqual(
            URLDetector.url(from: "https://omnicast.app")?.absoluteString, "https://omnicast.app")
    }

    func testOrdinaryQueriesAreNotAddresses() {
        for query in ["safari", "clipboard history", "git", "", "1.5", "v2.0"] {
            XCTAssertNil(URLDetector.url(from: query), "\(query) should not be a URL")
        }
    }

    func testHostIgnoresWWWAndCase() {
        let url = URL(string: "https://WWW.GitHub.com/haxzie")!
        XCTAssertEqual(URLDetector.host(of: url), "github.com")
    }
}

final class URLHistoryTests: XCTestCase {
    private var directory: URL!
    private var store: URLHistoryStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnicast-urls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = URLHistoryStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testVisitsAccumulateOnOneRowPerHost() {
        store.record(URL(string: "https://github.com/haxzie")!)
        store.record(URL(string: "https://github.com/anthropics")!)

        let all = store.all()
        XCTAssertEqual(all.count, 1, "paths should not each become their own suggestion")
        XCTAssertEqual(all.first?.visits, 2)
        XCTAssertEqual(all.first?.host, "github.com")
    }

    func testTypingAPrefixSuggestsAVisitedSite() async {
        store.record(URL(string: "https://github.com")!)

        let items = await URLProvider(store: store).items(for: "git")
        XCTAssertEqual(items.first?.title, "github.com")
        XCTAssertEqual(items.first?.kind, .website)
    }

    func testATypedAddressOutranksEverything() async {
        let items = await URLProvider(store: store).items(for: "example.com")
        XCTAssertEqual(items.first?.title, "example.com")
        XCTAssertGreaterThan(items.first?.score ?? 0, 1_000)
    }

    func testTheSuggestionSharesTheLearnedIdentity() async {
        // Same id whether typed in full or suggested, so opening it once
        // teaches the prefix memory that "git" means this site.
        store.record(URL(string: "https://github.com")!)
        let typed = await URLProvider(store: store).items(for: "github.com")
        let suggested = await URLProvider(store: store).items(for: "git")
        XCTAssertEqual(typed.first?.id, suggested.first?.id)
        XCTAssertEqual(typed.first?.id, URLProvider.itemID(forHost: "github.com"))
    }

    func testForgettingClearsEverything() {
        store.record(URL(string: "https://example.com")!)
        store.forgetAll()
        XCTAssertTrue(store.all().isEmpty)
    }
}
