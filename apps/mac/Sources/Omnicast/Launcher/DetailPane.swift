import AppKit
import SwiftUI

/// The right-hand half of a browser: a preview of the highlighted row above a
/// table of what is known about it.
struct DetailPane: View {
    let item: SearchItem?

    var body: some View {
        Group {
            switch item?.detail {
            case .clipboard(let entry):
                content(preview: { ClipboardPreview(entry: entry) }, rows: Self.rows(for: entry))
            case .dictation(let entry):
                content(preview: { TranscriptPreview(entry: entry) }, rows: Self.rows(for: entry))
            case nil:
                Text("Nothing selected")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func content<Preview: View>(
        @ViewBuilder preview: () -> Preview, rows: [(String, String)]
    ) -> some View {
        VStack(spacing: 0) {
            preview()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 7) {
                Text("Information")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                ForEach(rows, id: \.0) { label, value in
                    HStack {
                        Text(label).foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Text(value)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.system(size: 11))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Rows

    private static func rows(for entry: ClipboardEntry) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Application", entry.sourceAppName ?? "Unknown"),
            ("Content type", entry.content.label),
        ]
        if entry.content != .image {
            rows.append(("Characters", "\(entry.text.count)"))
            let words = entry.text.split(whereSeparator: \.isWhitespace).count
            if words > 1 { rows.append(("Words", "\(words)")) }
        }
        rows.append(("Copied", Self.timestamp.string(from: entry.copiedAt)))
        if entry.pinned { rows.append(("Pinned", "Yes")) }
        return rows
    }

    private static func rows(for entry: DictationEntry) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Model", entry.modelID),
            ("Duration", String(format: "%.1fs", Double(entry.durationMs) / 1000)),
            ("Words", "\(entry.wordCount)"),
        ]
        if entry.wordsPerMinute > 0 { rows.append(("Pace", "\(entry.wordsPerMinute) wpm")) }
        if let app = entry.appName { rows.append(("Pasted into", app)) }
        rows.append(("Recorded", Self.timestamp.string(from: entry.createdAt)))
        return rows
    }

    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}

/// Clipboard entries preview as their own content: an image, a colour swatch,
/// or the text itself.
private struct ClipboardPreview: View {
    let entry: ClipboardEntry

    var body: some View {
        if entry.content == .image, let path = entry.imagePath,
            let image = NSImage(contentsOfFile: path)
        {
            VStack(spacing: 10) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                Text(entry.preview)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        } else if let color = Self.color(from: entry.text) {
            VStack(spacing: 12) {
                Circle()
                    .fill(Color(nsColor: color))
                    .frame(width: 84, height: 84)
                    .overlay(Circle().strokeBorder(.white.opacity(0.15)))
                Text(entry.text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
                    .font(.system(size: 13, design: .monospaced))
            }
        } else {
            ScrollView {
                Text(entry.text)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// `#FF6363` and friends, so a copied colour previews as one.
    static func color(from text: String) -> NSColor? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("#") else { return nil }
        value.removeFirst()
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

private struct TranscriptPreview: View {
    let entry: DictationEntry

    var body: some View {
        ScrollView {
            Text(entry.text)
                .font(.system(size: 13))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension ClipboardEntry.Content {
    var label: String {
        switch self {
        case .text: return "Text"
        case .url: return "Link"
        case .color: return "Color"
        case .image: return "Image"
        case .file: return "File"
        }
    }
}
