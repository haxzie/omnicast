import AppKit
import SwiftUI

struct ClipboardHistoryView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var query = ""
    @State private var entries: [ClipboardEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Clipboard").font(.system(size: 26, weight: .semibold))
                HStack {
                    SearchBar(text: $query, placeholder: "Search clipboard history…")
                    Button("Clear unpinned") {
                        ClipboardStore.shared.deleteAll()
                        reload()
                    }
                }
            }
            .padding(20)

            if entries.isEmpty {
                EmptyStateView(
                    symbol: "doc.on.clipboard",
                    title: query.isEmpty ? "Nothing copied yet" : "No matches",
                    message: "Everything you copy shows up here. Open it anywhere with \(environment.settings.clipboardShortcut.displayString).")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(entries) { entry in
                            row(entry)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: query) { _, _ in reload() }
        // Pick up new copies while the window is open.
        .onReceive(environment.clipboardMonitor.$latest) { _ in reload() }
    }

    private func row(_ entry: ClipboardEntry) -> some View {
        GlassCard(padding: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: entry.symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.preview).font(.system(size: 12)).lineLimit(3)
                    HStack(spacing: 6) {
                        Text(entry.sourceAppName ?? "Unknown app")
                        Text("·")
                        Text(RelativeTime.string(from: entry.copiedAt))
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    Button {
                        ClipboardStore.shared.setPinned(!entry.pinned, id: entry.id)
                        reload()
                    } label: {
                        Image(systemName: entry.pinned ? "pin.fill" : "pin")
                    }
                    .help(entry.pinned ? "Unpin" : "Pin")

                    Button {
                        TextInserter.copy(entry.text)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Copy")

                    Button {
                        ClipboardStore.shared.delete(id: entry.id)
                        reload()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func reload() {
        let text = query
        Task.detached(priority: .userInitiated) {
            let items = ClipboardStore.shared.search(text)
            await MainActor.run { entries = items }
        }
    }
}
