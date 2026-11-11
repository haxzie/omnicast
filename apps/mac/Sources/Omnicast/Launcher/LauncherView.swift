import AppKit
import Carbon.HIToolbox
import SwiftUI

struct LauncherView: View {
    static let width: CGFloat = 720
    /// Transparent margin around the glass so its drop shadow has somewhere to
    /// land — the window clips anything drawn outside its bounds.
    static let shadowInset: CGFloat = 52
    /// Width of the window hosting this view.
    static var panelWidth: CGFloat { width + shadowInset * 2 }
    private static let rowHeight: CGFloat = 46
    private static let maxVisibleRows = 8

    @EnvironmentObject private var environment: AppEnvironment
    @FocusState private var fieldFocused: Bool
    @State private var backspaceMonitor: Any?

    private var engine: SearchEngine { environment.searchEngine }

    /// Typing goes straight into the engine; there is no second copy of the
    /// query to drift out of sync with it.
    private var query: Binding<String> {
        Binding(get: { engine.query }, set: { engine.search($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if engine.mode.isBrowser {
                Divider().opacity(0.35)
                browser
                Divider().opacity(0.35)
                actionBar
            } else if !engine.results.isEmpty {
                Divider().opacity(0.35)
                resultList
            }
            if environment.dictation.phase != .idle {
                Divider().opacity(0.35)
                dictationStrip
            }
        }
        .frame(width: Self.width)
        .glassPanel(cornerRadius: 22)
        .padding(Self.shadowInset)
        .onAppear {
            fieldFocused = true
            installBackspaceMonitor()
        }
        .onChange(of: engine.mode) { _, _ in fieldFocused = true }
        // The panel resizes to its content so there's never empty glass.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(PanelHeightKey.self) { height in
            Task { @MainActor in environment.resizeLauncher(toContentHeight: height) }
        }
    }

    // MARK: - Pieces

    private var searchField: some View {
        HStack(spacing: 12) {
            if engine.mode.isBrowser {
                Button {
                    engine.goBack()
                    fieldFocused = true
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("Back (esc)")

                Text(engine.mode.title)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(.white.opacity(0.1)))
            } else if let browser = detectedURLBrowserIcon {
                // The field turns into an address bar the moment what you have
                // typed is one.
                Image(nsImage: browser)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .frame(width: 26)
                    .transition(.opacity)
            } else {
                Image(systemName: modeSymbol)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
            }

            TextField(engine.mode.placeholder, text: query)
                .textFieldStyle(.plain)
                .font(.system(size: engine.mode.isBrowser ? 15 : 22, weight: .light))
                .focused($fieldFocused)
                .onSubmit(activateSelection)
                .onKeyPress(.downArrow) { engine.move(by: 1); return .handled }
                .onKeyPress(.upArrow) { engine.move(by: -1); return .handled }
                .onKeyPress(.escape) {
                    if environment.dictation.isRecording {
                        environment.dictation.cancel()
                    } else if !engine.goBack() {
                        // Already at the root, so esc dismisses.
                        environment.hideLauncher()
                    }
                    return .handled
                }
                .onKeyPress(.tab) { completeWithSelection(); return .handled }
                .onKeyPress(keys: [.return], phases: .down) { press in
                    // ⌘↩ pastes a browsed entry instead of copying it.
                    guard press.modifiers.contains(.command), let item = engine.selectedItem,
                        case .copyText(let text) = item.action
                    else { return .ignored }
                    engine.recordUse(of: item)
                    environment.hideLauncher()
                    TextInserter.paste(text)
                    return .handled
                }

            if engine.isSearching {
                ProgressView().controlSize(.small)
            }
            if environment.dictation.phase == .idle {
                Button {
                    environment.dictation.toggle()
                } label: {
                    Image(systemName: "mic")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dictate (\(environment.settings.dictationShortcut.displayString))")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 60)
    }

    /// A list of entries beside a detail pane, Raycast style.
    private var browser: some View {
        HStack(spacing: 0) {
            browseList
                .frame(width: 262)
            Divider().opacity(0.35)
            DetailPane(item: engine.selectedItem)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 332)
    }

    private var browseList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                    ForEach(Array(engine.results.enumerated()), id: \.element.id) { index, item in
                        if item.section != engine.results[safe: index - 1]?.section {
                            Text(item.section ?? "")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 14)
                                .padding(.top, index == 0 ? 6 : 12)
                                .padding(.bottom, 2)
                        }
                        BrowseRow(item: item, isSelected: index == engine.selectedIndex)
                            .id(item.id)
                            .onTapGesture {
                                engine.select(index: index)
                                activateSelection()
                            }
                    }
                }
                .padding(6)
            }
            .onChange(of: engine.selectedIndex) { _, index in
                guard engine.results.indices.contains(index) else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(engine.results[index].id, anchor: .center)
                }
            }
            .onChange(of: engine.mode) { _, _ in
                // Entering a browser leaves the selection at zero, so there is
                // no index change to scroll on — but the list may still be
                // holding an old offset.
                guard let first = engine.results.first else { return }
                proxy.scrollTo(first.id, anchor: .top)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 14) {
            Spacer()
            KeyHint(keys: "↩", label: "Copy")
            KeyHint(keys: "⌘↩", label: "Paste")
            KeyHint(keys: "⌫ esc", label: "Back")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(engine.results.enumerated()), id: \.element.id) { index, item in
                        ResultRow(item: item, isSelected: index == engine.selectedIndex)
                            .id(item.id)
                            .onTapGesture {
                                engine.select(index: index)
                                activateSelection()
                            }
                    }
                }
                .padding(6)
            }
            .frame(
                height: min(
                    CGFloat(engine.results.count) * Self.rowHeight + 12,
                    CGFloat(Self.maxVisibleRows) * Self.rowHeight))
            .onChange(of: engine.selectedIndex) { _, index in
                guard engine.results.indices.contains(index) else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(engine.results[index].id, anchor: .center)
                }
            }
        }
    }

    private var dictationStrip: some View {
        HStack(spacing: 12) {
            switch environment.dictation.phase {
            case .recording:
                SiriWaveView(level: environment.dictation.level).frame(width: 64, height: 20)
                Text("Listening… press esc to cancel")
            case .transcribing:
                ProgressView().controlSize(.small)
                Text("Transcribing with \(environment.models.activeModel?.name ?? environment.dictation.engineName)")
            case .inserted(let value):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(value).lineLimit(1)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).lineLimit(2)
            case .idle:
                EmptyView()
            }
            Spacer()
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    /// The default browser's icon, when the query is a web address.
    private var detectedURLBrowserIcon: NSImage? {
        guard !engine.mode.isBrowser, URLDetector.url(from: engine.query) != nil else { return nil }
        return DefaultBrowser.icon
    }

    private var modeSymbol: String {
        switch engine.mode {
        case .applications: return "magnifyingglass"
        case .clipboard: return "doc.on.clipboard"
        case .dictation: return "waveform"
        }
    }

    // MARK: - Actions

    /// Backspace is text input, so the focused field consumes it long before
    /// `onKeyPress` runs. Catching it ahead of dispatch is the only way to get
    /// "delete past the start of an empty filter steps back out".
    private func installBackspaceMonitor() {
        guard backspaceMonitor == nil else { return }
        backspaceMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == UInt16(kVK_Delete),
                // Local monitors only see this app's events, and this is the
                // only window the launcher ever keys — so a backspace typed
                // anywhere else is never swallowed.
                NSApp.keyWindow is LauncherPanel,
                SearchEngine.backspaceExits(query: engine.query, mode: engine.mode)
            else { return event }
            engine.goBack()
            return nil
        }
    }

    private func activateSelection() {
        guard let item = engine.selectedItem else { return }
        ActionRunner.run(item, from: environment)
    }

    /// Tab fills the field with the highlighted app's name, like a shell completion.
    private func completeWithSelection() {
        guard let item = engine.selectedItem, item.kind == .application else { return }
        engine.search(item.title)
    }
}

/// Reports the laid-out height of the launcher content up to the panel.
private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
