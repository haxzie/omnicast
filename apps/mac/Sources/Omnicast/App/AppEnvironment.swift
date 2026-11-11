import AppKit
import Combine
import SwiftUI

enum MainWindowTab: String, Hashable, CaseIterable {
    case dictation, clipboard, models, settings

    var title: String {
        switch self {
        case .dictation: return "Dictation"
        case .clipboard: return "Clipboard"
        case .models: return "Models"
        case .settings: return "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .dictation: return "waveform"
        case .clipboard: return "doc.on.clipboard"
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

    @Published var mainWindowTab: MainWindowTab = .dictation

    private var launcher: LauncherPanel?
    private var droplet: DropletPanel?
    private let dropletModel = DropletModel()
    private var fnKeyMonitor: FnKeyMonitor?
    private var dropletHideTask: Task<Void, Never>?
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
            searchEngine.goBack()
        } else {
            searchEngine.enter(mode)
        }
        panel.present()
    }

    func hideLauncher() {
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
            .sink { [weak self] phase in self?.updateDroplet(for: phase) }
            .store(in: &cancellables)

        dictation.$level
            .sink { [weak self] level in self?.dropletModel.level = level }
            .store(in: &cancellables)
    }

    private func updateDroplet(for phase: DictationController.Phase) {
        dropletHideTask?.cancel()

        switch phase {
        case .idle:
            // Nothing to retract if the droplet was never shown — this fires
            // once on subscription with the controller's initial state.
            guard dropletModel.phase != .hidden else { return }
            // Let the drop retract into the top of the screen before the panel goes.
            dropletModel.phase = .hidden
            fnKeyMonitor?.resetGesture()
            dropletHideTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                self?.droplet?.orderOut(nil)
            }
        case .recording:
            showDroplet(.recording)
        case .transcribing:
            showDroplet(.transcribing)
        case .inserted:
            showDroplet(.done)
        case .failed(let message):
            showDroplet(.failed(message))
        }
    }

    private func showDroplet(_ phase: DropletPhase) {
        dropletHideTask?.cancel()
        let panel = droplet ?? DropletPanel(model: dropletModel)
        droplet = panel
        if !panel.isVisible { panel.present() }
        dropletModel.phase = phase
    }

    /// Drives the droplet with synthetic values. Used by `--show-droplet`.
    func previewDroplet(_ phase: DropletPhase, level: Double) {
        showDroplet(phase)
        dropletModel.level = level
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
