import AppKit
import Foundation

/// Optional, best-effort upload of dictation history to the Omnicast API.
/// Local-first: everything works with sync off, and failures just retry later.
actor SyncClient {
    static let shared = SyncClient()

    private var isPushing = false

    func pushPending() async {
        guard !isPushing else { return }
        let (enabled, base, token) = await MainActor.run {
            (Settings.shared.syncEnabled, Settings.shared.apiBaseURL, Settings.shared.apiToken)
        }
        guard enabled, let baseURL = URL(string: base) else { return }

        isPushing = true
        defer { isPushing = false }

        let store = DictationStore.shared
        let pending = store.unsynced()
        guard !pending.isEmpty else { return }

        await registerDevice(baseURL: baseURL, token: token)

        var sent: [String] = []
        for entry in pending {
            let body: [String: Any] = [
                "id": entry.id,
                "text": entry.text,
                "durationMs": entry.durationMs,
                "transcribeMs": entry.transcribeMs,
                "modelId": entry.modelID,
                "appBundleId": entry.appBundleID as Any,
                "appName": entry.appName as Any,
                "language": entry.language as Any,
                "createdAt": Int(entry.createdAt.timeIntervalSince1970 * 1000),
            ].compactMapValues { $0 is NSNull ? nil : $0 }

            guard
                await post(
                    url: baseURL.appendingPathComponent("v1/dictations"), body: body, token: token)
            else { break }  // Offline: stop and retry the whole batch next time.
            sent.append(entry.id)
        }
        store.markSynced(ids: sent)
    }

    private func registerDevice(baseURL: URL, token: String) async {
        let body: [String: Any] = [
            "id": Self.deviceID,
            "name": Host.current().localizedName ?? "Mac",
            "platform": "macos",
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
        ]
        _ = await post(
            url: baseURL.appendingPathComponent("v1/devices"), body: body, token: token,
            method: "PUT")
    }

    private func post(url: URL, body: [String: Any], token: String, method: String = "POST") async
        -> Bool
    {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.deviceID, forHTTPHeaderField: "X-Omnicast-Device")
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 10

        guard let (_, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse
        else { return false }
        return (200..<300).contains(http.statusCode)
    }

    /// Stable per-install identifier; no account, no personal data.
    private static let deviceID: String = {
        let key = "deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }()
}
