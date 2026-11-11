import AppKit
import Speech
import SwiftUI

@main
struct OmnicastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var environment = AppEnvironment.shared

    var body: some Scene {
        MenuBarExtra("Omnicast", systemImage: menuBarSymbol) {
            MenuBarContent()
                .environmentObject(environment)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarSymbol: String {
        environment.dictation.isRecording ? "waveform.circle.fill" : "circle.hexagongrid"
    }
}

struct MenuBarContent: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Button("Open Launcher") { environment.showLauncher(mode: .applications) }
            .keyboardShortcut(.space, modifiers: .option)

        Button("Clipboard History") { environment.showLauncher(mode: .clipboard) }

        Button(environment.dictation.isRecording ? "Stop Dictation" : "Start Dictation") {
            environment.dictation.toggle()
        }

        Divider()

        ForEach(MainWindowTab.allCases, id: \.self) { tab in
            Button(tab.title) { environment.openMainWindow(tab: tab) }
        }

        Divider()

        Button("Quit Omnicast") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

extension AppEnvironment {
    /// Speech authorization as a word, for `--dictation-status`.
    static var speechAuthorizationName: String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not requested yet"
        @unknown default: return "unknown"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar app: no Dock icon until a window is opened.
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            AppEnvironment.shared.bootstrap()
            handleLaunchArguments()
        }
    }

    /// Debug affordances for a menu-bar app that otherwise shows no UI at
    /// launch: `Omnicast --show-window[=models]`, `--show-launcher[=query]` and
    /// `--show-droplet[=recording|transcribing|done]`, which drives the
    /// dictation droplet with synthetic levels so it can be inspected without
    /// a microphone. `--replay-learning` scores the ranker against the pick
    /// log and prints the lift over fuzzy matching alone, and
    /// `--dump-results[=query]` prints the ranked list for one query, and
    /// `--dictation-status` reports which speech engine and model would run.
    @MainActor
    private func handleLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        if let argument = arguments.first(where: { $0.hasPrefix("--dump-results") }) {
            let query = argument.split(separator: "=").dropFirst().joined(separator: "=")
            Task { @MainActor in
                let engine = AppEnvironment.shared.searchEngine
                await engine.prepare()
                engine.search(query)
                try? await Task.sleep(for: .milliseconds(500))
                print("query: \(query.isEmpty ? "(empty — predicted)" : query)")
                for (index, item) in engine.results.prefix(10).enumerated() {
                    let rank = String(index + 1).leftPadded(to: 2)
                    let title = item.title.rightPadded(to: 28)
                    let base = String(format: "%7.1f", item.base)
                    let learned = String(format: "%7.1f", item.score - item.base)
                    print("\(rank). \(title) fuzzy=\(base)  learned=\(learned)")
                }
                exit(0)
            }
            return
        }
        if arguments.contains("--dictation-status") {
            let models = AppEnvironment.shared.models
            let installed = models.installedModels
            print("whisper.cpp:  \(WhisperCLITranscriber.binaryURL?.path ?? "not installed")")
            print("models:       \(installed.isEmpty ? "none downloaded" : installed.map(\.name).joined(separator: ", "))")
            print("active model: \(models.activeModel?.name ?? "none")")
            // Apple's recognizer reports that it *supports* on-device work even
            // when Siri and Dictation are switched off and it will refuse at
            // run time, so this deliberately does not claim it is ready.
            print("apple speech: \(AppleSpeechTranscriber().isAvailable ? "supported" : "unsupported"), authorization: \(AppEnvironment.speechAuthorizationName)")
            if let model = models.activeModel, WhisperCLITranscriber.binaryURL != nil {
                print("ready:        yes — whisper.cpp with \(model.name)")
            } else if models.activeModel != nil {
                print("ready:        no — model downloaded but whisper.cpp is missing (brew install whisper-cpp)")
            } else {
                print("ready:        no model — falls back to Apple, which needs Dictation on in System Settings › Keyboard")
            }
            exit(0)
        }
        if arguments.contains("--replay-learning") {
            print(LearningReplay.report(for: UsageStore.shared.loggedPicks()))
            exit(0)
        }
        if let argument = arguments.first(where: { $0.hasPrefix("--show-window") }) {
            let name = argument.split(separator: "=").last.map(String.init) ?? ""
            AppEnvironment.shared.openMainWindow(
                tab: MainWindowTab(rawValue: name) ?? .dictation)
        }
        if let argument = arguments.first(where: { $0.hasPrefix("--show-droplet") }) {
            let value = argument.split(separator: "=").last.map(String.init) ?? "recording"
            // "recording:0.25" previews a specific voice level.
            let parts = value.split(separator: ":")
            let name = parts.first.map(String.init) ?? "recording"
            let level = parts.count > 1 ? Double(parts[1]) ?? 0.65 : 0.65
            let phase: DropletPhase =
                switch name {
                case "transcribing": .transcribing
                case "done": .done
                case "failed": .failed("whisper.cpp was not found.")
                default: .recording
                }
            AppEnvironment.shared.previewDroplet(phase, level: level)
        }
        if let argument = arguments.first(where: { $0.hasPrefix("--show-launcher") }) {
            let query = argument.split(separator: "=").dropFirst().joined(separator: "=")
            switch query {
            case "clipboard":
                AppEnvironment.shared.showLauncher(mode: .clipboard)
            case "recordings", "dictation":
                AppEnvironment.shared.showLauncher(mode: .dictation)
            default:
                AppEnvironment.shared.showLauncher(mode: .applications)
                if !query.isEmpty { AppEnvironment.shared.searchEngine.search(query) }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated {
            AppEnvironment.shared.openMainWindow(tab: .dictation)
        }
        return true
    }
}


extension String {
    fileprivate func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }

    fileprivate func rightPadded(to width: Int) -> String {
        count >= width ? String(prefix(width)) : self + String(repeating: " ", count: width - count)
    }
}
