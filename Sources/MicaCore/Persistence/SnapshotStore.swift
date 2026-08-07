import Foundation

/// Reads and writes the session snapshot.
public final class SnapshotStore {

    public static let shared = SnapshotStore()

    private let directory: URL
    private let fileURL: URL

    public init(directory: URL = SnapshotStore.defaultDirectory) {
        self.directory = directory
        self.fileURL = directory.appending(path: "session.json")
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return base.appending(path: "Mica")
    }

    public func read() -> SessionSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(SessionSnapshot.self, from: data)
        } catch {
            Log.recovery.error("unreadable session snapshot, discarding: \(error, privacy: .public)")
            delete()
            return nil
        }
    }

    /// Writes the snapshot and does not return until it is durably on disk.
    ///
    /// Blocking on the main thread is the point. This runs immediately before the first
    /// system mutation, and if the write were deferred there would be a window in which
    /// the Dock is already hidden but nothing on disk records how to put it back — which
    /// is exactly the window a crash would fall into.
    ///
    /// `F_FULLFSYNC` rather than a plain `write(_:options:.atomic)` because atomic
    /// replacement only guarantees the rename is all-or-nothing, not that the bytes
    /// reached the platter. A kernel panic or power loss is precisely the scenario this
    /// file exists for.
    public func writeBlocking(_ snapshot: SessionSnapshot) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            let temporaryURL = directory.appending(path: "session.json.tmp")

            let descriptor = open(temporaryURL.path, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
            guard descriptor >= 0 else {
                throw CocoaError(.fileWriteUnknown)
            }
            defer { close(descriptor) }

            try data.withUnsafeBytes { buffer in
                var written = 0
                while written < buffer.count {
                    let result = write(descriptor, buffer.baseAddress!.advanced(by: written), buffer.count - written)
                    guard result > 0 else { throw CocoaError(.fileWriteUnknown) }
                    written += result
                }
            }
            _ = fcntl(descriptor, F_FULLFSYNC, 0)

            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporaryURL)
        } catch {
            // A failure here means crash recovery won't work this session, but refusing
            // to engage would be worse: the user asked for privacy and would get none.
            Log.recovery.error("could not write session snapshot: \(error, privacy: .public)")
        }
    }

    public func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }
}
