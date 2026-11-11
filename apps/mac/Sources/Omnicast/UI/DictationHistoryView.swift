import SwiftUI

struct DictationHistoryView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var query = ""
    @State private var copiedID: String?

    private var entries: [DictationEntry] {
        let all = environment.dictation.history
        guard !query.isEmpty else { return all }
        return all.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if entries.isEmpty {
                EmptyStateView(
                    symbol: "waveform",
                    title: query.isEmpty ? "No dictations yet" : "No matches",
                    message: query.isEmpty
                        ? "Press \(environment.settings.dictationShortcut.displayString) anywhere and start talking. The text lands at your cursor."
                        : "Nothing in your history matches “\(query)”.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(entries) { entry in
                            row(entry)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .onAppear { environment.dictation.reloadHistory() }
    }

    private var header: some View {
        let stats = environment.dictation.stats()
        return VStack(alignment: .leading, spacing: 14) {
            Text("Dictation").font(.system(size: 26, weight: .semibold))

            HStack(spacing: 10) {
                StatTile(label: "Dictations", value: "\(stats.count)")
                StatTile(label: "Words", value: "\(stats.words)")
                StatTile(label: "Spoken", value: "\(Int(stats.seconds))s")
                StatTile(label: "Minutes saved", value: String(format: "%.0f", max(0, stats.minutesSaved)))
            }

            HStack {
                SearchBar(text: $query, placeholder: "Search transcripts…")
                Button("Clear history") { environment.dictation.clearHistory() }
                    .disabled(environment.dictation.history.isEmpty)
            }
        }
        .padding(20)
    }

    private func row(_ entry: DictationEntry) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(entry.text).font(.system(size: 13)).textSelection(.enabled)

                HStack(spacing: 8) {
                    Text(RelativeTime.string(from: entry.createdAt))
                    Text("·")
                    Text(entry.modelID)
                    Text("·")
                    Text("\(entry.wordCount) words")
                    if entry.wordsPerMinute > 0 {
                        Text("·")
                        Text("\(entry.wordsPerMinute) wpm")
                    }
                    if let app = entry.appName {
                        Text("·")
                        Text("into \(app)")
                    }
                    Spacer()
                    Button {
                        TextInserter.copy(entry.text)
                        copiedID = entry.id
                    } label: {
                        Label(
                            copiedID == entry.id ? "Copied" : "Copy",
                            systemImage: copiedID == entry.id ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    Button {
                        environment.dictation.delete(entry)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct StatTile: View {
    let label: String
    let value: String

    var body: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(value).font(.system(size: 20, weight: .medium)).monospacedDigit()
            }
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text).textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.07)))
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 36, weight: .thin)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 16, weight: .medium))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
