import Foundation

/// Runs Shortcuts through the `shortcuts` command line tool.
///
/// This is how Do Not Disturb gets toggled, because on macOS 26 there is no reachable API
/// that sets Focus. `DNDModeAssertionService` is gated behind an Apple-only entitlement;
/// `INFocusStatusCenter` is read-only with no setter; and writing the Do Not Disturb
/// database directly needs Full Disk Access and fights the daemon that owns those files.
///
/// Spawning a process is deliberately better than `tell application "Shortcuts Events"`:
/// `posix_spawn` is not an Apple Event, so the Automation permission never engages and
/// the user is never prompted.
public nonisolated enum ShortcutsRunner {

    private static let executable = URL(fileURLWithPath: "/usr/bin/shortcuts")

    public struct Shortcut: Equatable, Sendable, Identifiable {
        public var name: String
        public var uuid: String
        public var id: String { uuid }
    }

    public static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: executable.path)
    }

    /// Every shortcut the user has, with identifiers.
    ///
    /// Shortcuts are always addressed by UUID rather than name: names collide, can be
    /// renamed out from under us, and are localised.
    public static func list() -> [Shortcut] {
        guard let output = capture(arguments: ["list", "--show-identifiers"]) else { return [] }

        return output.split(separator: "\n").compactMap { line in
            // Format is `Name (UUID)`, and a name may itself contain parentheses, so
            // match the *last* pair.
            let text = String(line)
            guard text.hasSuffix(")"), let open = text.lastIndex(of: "(") else { return nil }
            let uuid = String(text[text.index(after: open)..<text.index(before: text.endIndex)])
            let name = String(text[text.startIndex..<open]).trimmingCharacters(in: .whitespaces)
            guard !uuid.isEmpty, !name.isEmpty else { return nil }
            return Shortcut(name: name, uuid: uuid)
        }
    }

    public static func exists(uuid: String) -> Bool {
        list().contains { $0.uuid == uuid }
    }

    /// Runs a shortcut, waiting up to `timeout` seconds.
    @discardableResult
    public static func run(uuid: String, timeout: TimeInterval = 10) -> Bool {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["run", uuid]
        // A shortcut that asks for input would otherwise block forever waiting on a
        // terminal that isn't there.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            Log.effects.error("could not run shortcut: \(error, privacy: .public)")
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            Log.effects.error("shortcut \(uuid, privacy: .public) timed out")
            return false
        }
        return process.terminationStatus == 0
    }

    private static func capture(arguments: [String]) -> String? {
        guard isAvailable else { return nil }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
