import AppKit

/// Whichever browser the system would hand an http link to.
@MainActor
enum DefaultBrowser {
    private static var cached: NSImage?

    static var applicationURL: URL? {
        guard let probe = URL(string: "https://example.com") else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: probe)
    }

    /// Cached: the launcher asks for this on every keystroke that looks like
    /// an address, and the answer changes about once a year.
    static var icon: NSImage? {
        if let cached { return cached }
        guard let url = applicationURL else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 32, height: 32)
        cached = image
        return image
    }

    static var name: String? {
        applicationURL?.deletingPathExtension().lastPathComponent
    }
}
