import AppKit
import Observation

/// What a trigger app should do when it starts.
public nonisolated enum TriggerAction: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Engage Mica automatically.
    case activate
    /// Just post a notification with an Activate button, and let the user decide.
    case remind

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .activate: "Activate"
        case .remind: "Remind me"
        }
    }
}

public nonisolated struct AppEntry: Codable, Equatable, Sendable, Identifiable {
    public var bundleID: String
    public var displayName: String
    public var action: TriggerAction

    public var id: String { bundleID }

    public init(bundleID: String, displayName: String, action: TriggerAction = .activate) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.action = action
    }
}

/// An observable, file-backed list of apps.
///
/// These live in JSON rather than `UserDefaults` because they're unbounded and
/// structured — arrays of dictionaries in a plist are miserable to diff, inspect, or
/// hand-edit, and this is exactly the kind of setting you want to be able to look at.
@Observable
public final class AppListStore {

    public private(set) var entries: [AppEntry] = []

    @ObservationIgnored private let fileURL: URL

    public init(filename: String, directory: URL = SnapshotStore.defaultDirectory) {
        self.fileURL = directory.appending(path: filename)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        entries = (try? JSONDecoder().decode([AppEntry].self, from: data)) ?? []
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            Log.coordinator.error("could not save \(self.fileURL.lastPathComponent, privacy: .public): \(error, privacy: .public)")
        }
    }

    public func add(_ entry: AppEntry) {
        guard !entries.contains(where: { $0.bundleID == entry.bundleID }) else { return }
        entries.append(entry)
        entries.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        save()
    }

    public func remove(bundleID: String) {
        entries.removeAll { $0.bundleID == bundleID }
        save()
    }

    public func setAction(_ action: TriggerAction, for bundleID: String) {
        guard let index = entries.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        entries[index].action = action
        save()
    }

    public func bundleIDs(action: TriggerAction? = nil) -> Set<String> {
        Set(entries.filter { action == nil || $0.action == action }.map(\.bundleID))
    }

    public func displayName(for bundleID: String) -> String {
        entries.first { $0.bundleID == bundleID }?.displayName ?? bundleID
    }
}
