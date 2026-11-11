import AppKit
import SwiftUI

/// The app's regular window: dictation history, clipboard history, models and
/// settings. The launcher is deliberately a separate panel.
@MainActor
enum MainWindow {
    static let identifier = "app.omnicast.main"

    static func open(environment: AppEnvironment) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier(identifier)
        window.title = "Omnicast"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        window.setFrameAutosaveName("OmnicastMain")
        window.contentView = NSHostingView(rootView: MainView().environmentObject(environment))
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
    }
}

struct MainView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        NavigationSplitView {
            List(MainWindowTab.allCases, id: \.self, selection: selection) { tab in
                Label(tab.title, systemImage: tab.symbolName).tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .scrollContentBackground(.hidden)
        } detail: {
            Group {
                switch environment.mainWindowTab {
                case .dictation: DictationHistoryView()
                case .clipboard: ClipboardHistoryView()
                case .models: ModelsView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(VisualEffectBackground(material: .underWindowBackground))
        .frame(minWidth: 820, minHeight: 540)
    }

    private var selection: Binding<MainWindowTab?> {
        Binding(
            get: { environment.mainWindowTab },
            set: { if let value = $0 { environment.mainWindowTab = value } })
    }
}
