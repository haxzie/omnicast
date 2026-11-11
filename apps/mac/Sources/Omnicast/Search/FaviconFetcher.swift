import AppKit
import Foundation

/// Fetches a site's icon so suggestions look like the sites they point at.
///
/// This is the one thing in Omnicast that talks to a third party: the icon
/// comes from Google's favicon service, which means Google learns the domain.
/// It only ever runs for a site you just chose to open, and Settings can turn
/// it off — in which case suggestions fall back to a globe.
actor FaviconFetcher {
    static let shared = FaviconFetcher()

    private let store = URLHistoryStore.shared
    private var inFlight: Set<String> = []

    func fetchIfNeeded(for url: URL) async {
        guard await MainActor.run(body: { Settings.shared.downloadFavicons }) else { return }

        let host = URLDetector.host(of: url)
        guard !host.isEmpty, !inFlight.contains(host) else { return }

        let destination = store.faviconDirectory.appendingPathComponent("\(host).png")
        if FileManager.default.fileExists(atPath: destination.path) {
            store.setFavicon(path: destination.path, host: host)
            return
        }

        inFlight.insert(host)
        defer { inFlight.remove(host) }

        guard
            let source = URL(
                string:
                    "https://www.google.com/s2/favicons?sz=64&domain=\(host.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? host)"
            )
        else { return }

        var request = URLRequest(url: source)
        request.timeoutInterval = 8
        // Google 301s to the real asset and answers 404 with a placeholder
        // globe for hosts it has never seen, so the status is the whole test.
        // Size is not: a real icon can be a couple of hundred bytes, smaller
        // than the placeholder.
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200,
            !data.isEmpty, NSImage(data: data) != nil
        else { return }

        guard (try? data.write(to: destination)) != nil else { return }
        store.setFavicon(path: destination.path, host: host)
    }
}
