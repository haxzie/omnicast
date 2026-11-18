import AppKit
import Combine
import SwiftUI

/// The window is for the things you set up once. Browsing clipboard history
/// and past recordings belongs in the launcher, where you already are.
enum MainWindowTab: String, Hashable, CaseIterable {
    case models, settings

    var title: String {
        switch self {
        case .models: return "Models"
        case .settings: return "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .models: return "brain"
        case .settings: return "gearshape"
        }
    }
}

/// Owns the long-lived singletons and the two windows (launcher panel + main
/// window) so SwiftUI views can reach them through one object.
@MainActor
final class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()

    let searchEngine = SearchEngine()
    let clipboardMonitor = ClipboardMonitor()
    let dictation = DictationController()
    let models = ModelManager.shared
    let settings = Settings.shared

    @Published var mainWindowTab: MainWindowTab = .settings
    /// Bumped on every open. The launcher's SwiftUI view appears once and is
    /// reused for every presentation after that, so `onAppear` is not enough
    /// to put the caret back in the field.
    @Published private(set) var launcherPresentations = 0
    /// Drives the launcher's own enter and exit animation.
    @Published private(set) var isLauncherPresented = false

    private var launcher: LauncherPanel?
    private var transcript: TranscriptPanel?
    private var aurora: AuroraPanel?
    private let hudModel = DictationHUDModel()
    private var fnKeyMonitor: FnKeyMonitor?
    private var hudHideTask: Task<Void, Never>?
    private var hotKeyIDs: [UInt32] = []
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // SwiftUI does not observe nested ObservableObjects, so a view holding
        // only @EnvironmentObject AppEnvironment would never redraw when the
        // search engine or dictation state changed. Forward their change
        // notifications into this object's own publisher.
        for child in [
            searchEngine.objectWillChange, clipboardMonitor.objectWillChange,
            dictation.objectWillChange, models.objectWillChange, settings.objectWillChange,
        ] {
            child
                .sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    func bootstrap() {
        clipboardMonitor.start()
        registerHotKeys()
        configureFnKey()
        observeDictationPhase()

        Task {
            await searchEngine.prepare()
            await models.refreshCatalog()
            await SyncClient.shared.pushPending()
        }

        settings.$fnKeyDictation
            .dropFirst()
            .sink { [weak self] enabled in self?.setFnKeyDictation(enabled) }
            .store(in: &cancellables)

        // Re-register whenever the user edits a shortcut in Settings.
        settings.$launcherShortcut
            .combineLatest(settings.$clipboardShortcut, settings.$dictationShortcut)
            .dropFirst()
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _, _, _ in self?.registerHotKeys() }
            .store(in: &cancellables)
    }

    // MARK: - Launcher

    func showLauncher(mode: SearchEngine.Mode = .applications) {
        let panel = launcher ?? makeLauncher()
        if mode == .applications {
            // `goBack` only searches when it actually leaves a browser. Coming
            // back to a launcher that is already at the root — every ordinary
            // open — it does nothing, so the results it was reset to empty
            // would stay empty and the quick-launch row never appear.
            if !searchEngine.goBack() {
                searchEngine.search(searchEngine.query)
            }
        } else {
            searchEngine.enter(mode)
        }
        launcherPresentations += 1
        // Order the window in while the content is still in its hidden state,
        // then flip the flag — so the first frame drawn is the start of the
        // animation rather than its end.
        panel.present()
        isLauncherPresented = true
    }

    /// Opening from the menu-bar menu, which needs to finish closing first.
    ///
    /// A panel presented while the menu is still tearing down wins key status
    /// and then has it taken straight back off it, which the click-away check
    /// reads as the user dismissing the launcher — so it opened and vanished
    /// again. One beat later the menu is gone and this is an ordinary
    /// presentation. `LauncherPanel.focusGrace` covers what slips through.
    func showLauncherFromMenu(mode: SearchEngine.Mode = .applications) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.menuTeardown) { [weak self] in
            self?.showLauncher(mode: mode)
        }
    }

    /// Long enough for a menu-bar menu to close before the panel appears.
    private static let menuTeardown: TimeInterval = 0.18

    func hideLauncher() {
        guard isLauncherPresented else { return }
        // Flipping this first lets the content animate out; the panel orders
        // itself away once that finishes.
        isLauncherPresented = false
        launcher?.dismiss()
    }

    func resizeLauncher(toContentHeight height: CGFloat) {
        launcher?.setContentHeight(height)
    }

    func toggleLauncher(mode: SearchEngine.Mode = .applications) {
        if let launcher, launcher.isVisible, searchEngine.mode == mode {
            hideLauncher()
        } else {
            if launcher?.isVisible != true { searchEngine.reset() }
            showLauncher(mode: mode)
        }
    }

    private func makeLauncher() -> LauncherPanel {
        let panel = LauncherPanel()
        panel.onDismissRequest = { [weak self] in self?.hideLauncher() }
        panel.contentView = NSHostingView(
            rootView: LauncherView().environmentObject(self))
        launcher = panel
        return panel
    }

    // MARK: - Main window

    func openMainWindow(tab: MainWindowTab) {
        mainWindowTab = tab
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == MainWindow.identifier }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            MainWindow.open(environment: self)
        }
    }

    // MARK: - fn key

    private func configureFnKey() {
        fnKeyMonitor = FnKeyMonitor { [weak self] action in
            self?.handle(fnAction: action)
        }
        setFnKeyDictation(settings.fnKeyDictation)
    }

    private func setFnKeyDictation(_ enabled: Bool) {
        enabled ? fnKeyMonitor?.start() : fnKeyMonitor?.stop()
    }

    private func handle(fnAction action: FnGestureMachine.Action) {
        switch action {
        case .start:
            // Ignore a new press while the previous take is still being transcribed.
            guard dictation.phase != .transcribing else { return }
            Task { await dictation.start() }
        case .finish:
            Task { await dictation.stopAndTranscribe() }
        case .cancel:
            dictation.cancel()
        case .none:
            break
        }
    }

    // MARK: - Droplet

    private func observeDictationPhase() {
        dictation.$phase
            .removeDuplicates()
            .sink { [weak self] phase in self?.updateHUD(for: phase) }
            .store(in: &cancellables)

        dictation.$level
            .sink { [weak self] level in self?.hudModel.level = level }
            .store(in: &cancellables)

        dictation.$liveText
            .sink { [weak self] text in self?.hudModel.text = text }
            .store(in: &cancellables)
    }

    private func updateHUD(for phase: DictationController.Phase) {
        hudHideTask?.cancel()

        switch phase {
        case .idle:
            // Nothing to retract if the droplet was never shown — this fires
            // once on subscription with the controller's initial state.
            guard hudModel.phase != .hidden else { return }
            // Let the drop retract into the top of the screen before the panel goes.
            hudModel.phase = .hidden
            fnKeyMonitor?.resetGesture()
            hudHideTask = Task { [weak self] in
                // Just long enough for the fade; the text should be gone the
                // moment it lands in the app, not linger afterwards.
                try? await Task.sleep(
                    for: .milliseconds(Int(LiveTranscriptView.appearanceDuration * 1000) + 40))
                guard !Task.isCancelled else { return }
                self?.transcript?.orderOut(nil)
                self?.aurora?.orderOut(nil)
            }
        case .recording:
            showHUD(.recording)
        case .transcribing:
            showHUD(.transcribing)
        case .failed(let message):
            showHUD(.failed(message))
        }
    }

    private func showHUD(_ phase: DictationHUDPhase) {
        hudHideTask?.cancel()
        // Presented back to front: both float at the same window level, so
        // the last one in sits on top — glow first, then the words.
        let glow = aurora ?? AuroraPanel(model: hudModel)
        aurora = glow
        if !glow.isVisible { glow.present() }

        let panel = transcript ?? TranscriptPanel(model: hudModel)
        transcript = panel
        panel.present()

        hudModel.phase = phase
    }

    /// Drives the display with synthetic values. Used by `--show-hud`.
    func previewHUD(_ phase: DictationHUDPhase, level: Double, text: String = "") {
        showHUD(phase)
        hudModel.level = level
        hudModel.text = text
    }

    // MARK: - Hot keys

    private func registerHotKeys() {
        hotKeyIDs.forEach(HotKeyManager.shared.unregister)
        hotKeyIDs = [
            HotKeyManager.shared.register(shortcut: settings.launcherShortcut) { [weak self] in
                self?.toggleLauncher(mode: .applications)
            },
            HotKeyManager.shared.register(shortcut: settings.clipboardShortcut) { [weak self] in
                self?.toggleLauncher(mode: .clipboard)
            },
            HotKeyManager.shared.register(shortcut: settings.dictationShortcut) { [weak self] in
                self?.dictation.toggle()
            },
        ]
    }
}
