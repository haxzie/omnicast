import Combine
import CryptoKit
import Foundation

/// Downloads, verifies and deletes local speech models.
///
/// Models live in `~/Library/Application Support/Omnicast/Models` so a user can
/// delete them from Finder without breaking the app.
@MainActor
final class ModelManager: NSObject, ObservableObject {
    enum State: Equatable {
        case notInstalled
        case downloading(progress: Double, bytesWritten: Int64)
        case installed(bytes: Int64)
        case failed(String)
    }

    @Published private(set) var catalog: [SpeechModel] = ModelCatalog.bundled
    @Published private(set) var states: [String: State] = [:]

    static let shared = ModelManager()

    private lazy var session: URLSession = URLSession(
        configuration: .default, delegate: self, delegateQueue: nil)
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var taskModels: [Int: SpeechModel] = [:]

    private let directory = SQLiteDatabase.supportDirectory
        .appendingPathComponent("Models", isDirectory: true)

    private override init() {
        super.init()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        refreshStates()
    }

    // MARK: - Queries

    func location(of model: SpeechModel) -> URL {
        directory.appendingPathComponent(model.filename)
    }

    func isInstalled(_ model: SpeechModel) -> Bool {
        if case .installed = states[model.id] ?? .notInstalled { return true }
        return false
    }

    var installedModels: [SpeechModel] { catalog.filter(isInstalled) }

    /// The model dictation should use: the user's choice, else any installed
    /// model, else nothing.
    var activeModel: SpeechModel? {
        if let id = Settings.shared.selectedModelID, let model = catalog.first(where: { $0.id == id }),
            isInstalled(model)
        {
            return model
        }
        return installedModels.first
    }

    func refreshStates() {
        for model in catalog {
            if tasks[model.id] != nil { continue }
            let url = location(of: model)
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64,
                size > 0
            {
                states[model.id] = .installed(bytes: size)
            } else if states[model.id] == nil {
                states[model.id] = .notInstalled
            }
        }
    }

    /// Pulls the catalog from the API when sync is on; falls back to bundled.
    func refreshCatalog() async {
        guard Settings.shared.syncEnabled,
            let url = URL(string: Settings.shared.apiBaseURL + "/v1/models")
        else { return }
        var request = URLRequest(url: url)
        let token = Settings.shared.apiToken
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        struct Response: Decodable { let items: [SpeechModel] }
        guard let (data, _) = try? await URLSession.shared.data(for: request),
            let decoded = try? JSONDecoder().decode(Response.self, from: data),
            !decoded.items.isEmpty
        else { return }
        catalog = decoded.items
        refreshStates()
    }

    // MARK: - Mutations

    func download(_ model: SpeechModel) {
        guard tasks[model.id] == nil else { return }
        states[model.id] = .downloading(progress: 0, bytesWritten: 0)
        let task = session.downloadTask(with: model.url)
        tasks[model.id] = task
        taskModels[task.taskIdentifier] = model
        task.resume()
    }

    func cancelDownload(_ model: SpeechModel) {
        tasks[model.id]?.cancel()
        tasks[model.id] = nil
        states[model.id] = .notInstalled
    }

    func delete(_ model: SpeechModel) {
        try? FileManager.default.removeItem(at: location(of: model))
        states[model.id] = .notInstalled
        if Settings.shared.selectedModelID == model.id {
            Settings.shared.selectedModelID = installedModels.first?.id
        }
    }

    fileprivate func finish(_ model: SpeechModel, movedFrom temporary: URL) {
        let destination = location(of: model)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)

            if let expected = model.sha256 {
                let actual = try Self.sha256(of: destination)
                guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
                    try? FileManager.default.removeItem(at: destination)
                    states[model.id] = .failed("Checksum mismatch — the download was corrupted.")
                    return
                }
            }

            let size =
                (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64)
                ?? model.bytes
            states[model.id] = .installed(bytes: size ?? model.bytes)
            if Settings.shared.selectedModelID == nil { Settings.shared.selectedModelID = model.id }
        } catch {
            states[model.id] = .failed(error.localizedDescription)
        }
        tasks[model.id] = nil
    }

    fileprivate func fail(_ model: SpeechModel, message: String) {
        states[model.id] = .failed(message)
        tasks[model.id] = nil
    }

    fileprivate func progress(_ model: SpeechModel, written: Int64, total: Int64) {
        let expected = total > 0 ? total : model.bytes
        states[model.id] = .downloading(
            progress: min(1, Double(written) / Double(max(expected, 1))), bytesWritten: written)
    }

    fileprivate func model(forTask identifier: Int) -> SpeechModel? { taskModels[identifier] }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension ModelManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The temp file disappears when this method returns, so stage it first.
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.moveItem(at: location, to: staged)
        let identifier = downloadTask.taskIdentifier
        Task { @MainActor in
            guard let model = self.model(forTask: identifier) else { return }
            self.finish(model, movedFrom: staged)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        let identifier = downloadTask.taskIdentifier
        Task { @MainActor in
            guard let model = self.model(forTask: identifier) else { return }
            self.progress(model, written: totalBytesWritten, total: totalBytesExpectedToWrite)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let identifier = task.taskIdentifier
        Task { @MainActor in
            guard let model = self.model(forTask: identifier) else { return }
            if (error as NSError).code == NSURLErrorCancelled { return }
            self.fail(model, message: error.localizedDescription)
        }
    }
}
