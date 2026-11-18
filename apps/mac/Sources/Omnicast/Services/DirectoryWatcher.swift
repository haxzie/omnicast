import Foundation

/// Watches directories for changes and calls back once they settle.
///
/// Installing an app writes a great many files, so the callback is debounced:
/// one rebuild after the dust settles rather than a hundred during the copy.
final class DirectoryWatcher {
    private let paths: [String]
    private let debounce: TimeInterval
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "app.omnicast.fsevents")

    private var stream: FSEventStreamRef?
    private var pendingWork: DispatchWorkItem?

    /// Only existing directories are watched; the rest are silently dropped.
    init(paths: [String], debounce: TimeInterval = 1.5, onChange: @escaping () -> Void) {
        self.paths = paths.filter { FileManager.default.fileExists(atPath: $0) }
        self.debounce = debounce
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        guard stream == nil, !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil,
            release: nil, copyDescription: nil)

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue().schedule()
        }

        // `watchRoot` also catches the directory itself being replaced; the
        // one-second latency lets the file system coalesce a burst for us.
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagFileEvents)

        guard
            let created = FSEventStreamCreate(
                kCFAllocatorDefault, callback, &context, paths as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags)
        else { return }

        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    func stop() {
        pendingWork?.cancel()
        pendingWork = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func schedule() {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pendingWork = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
