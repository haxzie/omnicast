import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject private var settings = Settings.shared
    @State private var recording: ShortcutField.Target?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings").font(.system(size: 26, weight: .semibold))

                section("Shortcuts") {
                    ShortcutField(
                        label: "Open launcher", shortcut: $settings.launcherShortcut,
                        target: .launcher, recording: $recording)
                    ShortcutField(
                        label: "Clipboard history", shortcut: $settings.clipboardShortcut,
                        target: .clipboard, recording: $recording)
                    ShortcutField(
                        label: "Start / stop dictation", shortcut: $settings.dictationShortcut,
                        target: .dictation, recording: $recording)
                }

                section("Search") {
                    HStack {
                        Text("Application index")
                        Spacer()
                        Button("Rebuild now") { environment.searchEngine.reindexApplications() }
                    }
                    Text("The launcher searches installed applications only.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Divider().opacity(0.4)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Learned ranking")
                            Text("Results improve as you pick them. Everything stays on this Mac.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reset") { environment.searchEngine.resetLearning() }
                    }
                }

                section("Clipboard") {
                    Toggle("Record clipboard history", isOn: $settings.clipboardHistoryEnabled)
                    Picker("Keep history for", selection: $settings.clipboardRetentionDays) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("Forever").tag(36_500)
                    }
                    Text("Items copied from password managers are never recorded.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                section("Dictation") {
                    Toggle("Hold the fn key to dictate", isOn: $settings.fnKeyDictation)
                    Text(
                        "Hold 🌐 fn and talk, release to paste. Tap it once to keep recording hands-free, tap again to finish. Set System Settings › Keyboard › “Press 🌐 to” to “Do Nothing” so macOS doesn’t act on the key too."
                    )
                    .font(.system(size: 11)).foregroundStyle(.secondary)

                    Picker("Language", selection: $settings.dictationLanguage) {
                        Text("Auto-detect").tag("auto")
                        Text("English").tag("en")
                        Text("Spanish").tag("es")
                        Text("French").tag("fr")
                        Text("German").tag("de")
                        Text("Hindi").tag("hi")
                        Text("Japanese").tag("ja")
                    }
                    Toggle("Paste transcript at the cursor", isOn: $settings.autoPasteDictation)
                    Toggle("Play start and stop sounds", isOn: $settings.playDictationSounds)
                    permissionRow
                }

                section("Sync (optional)") {
                    Toggle("Sync dictation history to the Omnicast API", isOn: $settings.syncEnabled)
                    TextField("API base URL", text: $settings.apiBaseURL)
                        .disabled(!settings.syncEnabled)
                    SecureField("API token", text: $settings.apiToken)
                        .disabled(!settings.syncEnabled)
                    Text("Everything works offline. Sync only uploads transcript text and timings.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                section("General") {
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                        .onChange(of: settings.launchAtLogin) { _, enabled in
                            setLaunchAtLogin(enabled)
                        }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(
                            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                                ?? "0.1.0"
                        )
                        .foregroundStyle(.secondary)
                    }
                    Button("Quit Omnicast") { NSApp.terminate(nil) }
                }
            }
            .padding(20)
        }
    }

    private var permissionRow: some View {
        HStack {
            Image(systemName: TextInserter.hasAccessibilityPermission ? "checkmark.circle" : "exclamationmark.circle")
                .foregroundStyle(TextInserter.hasAccessibilityPermission ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility access")
                Text("Required for the fn key and for pasting transcripts into other apps.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if !TextInserter.hasAccessibilityPermission {
                Button("Grant…") { TextInserter.requestAccessibilityPermission() }
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content)
        -> some View
    {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            GlassCard {
                VStack(alignment: .leading, spacing: 10, content: content)
                    .toggleStyle(.switch)
                    .pickerStyle(.menu)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Omnicast: login item update failed — \(error.localizedDescription)")
        }
    }
}

/// Click, then press a chord to rebind it.
struct ShortcutField: View {
    enum Target { case launcher, clipboard, dictation }

    let label: String
    @Binding var shortcut: Shortcut
    let target: Target
    @Binding var recording: Target?

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Button(isRecording ? "Press keys…" : shortcut.displayString) {
                recording = isRecording ? nil : target
            }
            .font(.system(size: 12, design: .rounded))
            .frame(minWidth: 110)
            .background(KeyCaptureView(isActive: isRecording) { captured in
                shortcut = captured
                recording = nil
            })
        }
    }

    private var isRecording: Bool { recording == target }
}

/// A zero-size NSView that swallows the next key-down while recording a chord.
private struct KeyCaptureView: NSViewRepresentable {
    let isActive: Bool
    let onCapture: (Shortcut) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onCapture = onCapture
        context.coordinator.setActive(isActive)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator {
        var onCapture: (Shortcut) -> Void
        private var monitor: Any?

        init(onCapture: @escaping (Shortcut) -> Void) {
            self.onCapture = onCapture
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        func setActive(_ active: Bool) {
            if active, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    // A bare key makes a terrible global shortcut.
                    guard !flags.isEmpty else { return event }
                    self?.onCapture(
                        Shortcut(keyCode: UInt32(event.keyCode), modifiers: flags.rawValue))
                    return nil
                }
            } else if !active, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
