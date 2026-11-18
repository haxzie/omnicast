import AppKit
import SwiftUI

struct ResultRow: View {
    let item: SearchItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                highlightedTitle
                    .font(.system(size: 13.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Text(item.kind.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(.white.opacity(isSelected ? 0.16 : 0.08)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.14))
            }
        }
        .contentShape(Rectangle())
    }

    private var icon: some View {
        ItemIcon(icon: item.icon, symbolSize: 15)
    }

    /// Bolds the characters the query actually matched.
    private var highlightedTitle: Text {
        guard !item.titleMatch.isEmpty else { return Text(item.title) }
        let matched = Set(item.titleMatch)
        var result = Text("")
        for (index, character) in item.title.enumerated() {
            let piece = Text(String(character))
            result =
                result
                + (matched.contains(index)
                    ? piece.fontWeight(.bold).foregroundColor(.accentColor) : piece)
        }
        return result
    }
}

/// `NSWorkspace.icon(forFile:)` hits the disk; the launcher redraws its whole
/// list on every keystroke, so icons are cached by path.
@MainActor
final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for url: URL) -> NSImage {
        if let cached = cache[url.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 32, height: 32)
        cache[url.path] = image
        return image
    }
}

/// A compact row for the browsers, where the detail pane carries the context
/// that a search result has to pack into its subtitle.
struct BrowseRow: View {
    let item: SearchItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            if case .symbol(let name) = item.icon {
                Image(systemName: name)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            Text(item.title)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.14))
            }
        }
        .contentShape(Rectangle())
    }
}

struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Text(keys)
                .font(.system(size: 10, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.12)))
        }
    }
}

extension Array {
    /// Index that tolerates being out of bounds, for "is this a new section?".
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Draws whichever kind of icon a result carries, so every surface that shows
/// results renders them identically.
struct ItemIcon: View {
    let icon: SearchItem.Icon
    var symbolSize: CGFloat = 15

    var body: some View {
        switch icon {
        case .file(let url):
            Image(nsImage: IconCache.shared.icon(for: url))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: symbolSize, weight: .regular))
                .foregroundStyle(.primary.opacity(0.85))
        case .named(let name):
            Image(nsImage: NSImage(named: name) ?? NSImage())
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        case .builtIn(let kind):
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let shape = RoundedRectangle(
                    cornerRadius: side * BuiltInIcon.cornerRatio, style: .continuous)
                shape
                    .fill(
                        LinearGradient(
                            colors: kind.colors, startPoint: .top, endPoint: .bottom)
                    )
                    .overlay {
                        Image(systemName: kind.symbol)
                            .font(.system(size: side * 0.46, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .overlay {
                        // The hairline every macOS icon has where its face
                        // catches the light.
                        shape.strokeBorder(.white.opacity(0.14), lineWidth: max(0.5, side * 0.02))
                    }
                    .frame(width: side, height: side)
            }
            .aspectRatio(1, contentMode: .fit)
        case .image(let url):
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "globe")
                    .font(.system(size: symbolSize))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One square on the quick-launch row: icon above, name beneath.
struct QuickLaunchTile: View {
    let item: SearchItem
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            ItemIcon(icon: item.icon, symbolSize: 26)
                .frame(width: 38, height: 38)
            Text(item.compactTitle ?? item.title)
                .font(.system(size: 11))
                // One line, so every tile is the same height and the
                // highlight sits evenly above and below its contents.
                // Reserving a second line left a dead gap under short names.
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .frame(width: 84)
        .padding(.vertical, 12)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.14))
            }
        }
        .contentShape(Rectangle())
    }
}
