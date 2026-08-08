import Foundation

/// Confirms whether Mica's Do Not Disturb shortcut actually turns Focus on.
///
/// This is the honest core of the setup. macOS 26 emits no notification a third party can
/// observe when Focus changes — verified by capturing every Darwin and distributed
/// notification across a manual toggle and seeing none fire — so the app cannot detect
/// Focus the way earlier macOS allowed. What it *can* do, being non-sandboxed, is read the
/// Focus daemon's own log. When Do Not Disturb turns on, `donotdisturbd` logs
/// "Inserted new assertion into store"; turning off logs an invalidation instead. Watching
/// for that line is the one method proven to work on this OS.
public nonisolated enum DNDActivationCheck {

    /// Runs the on-shortcut and reports whether the daemon actually recorded an
    /// activation. Restores the prior off-state before returning.
    public static func verify(onID: String, offID: String) async -> Bool {
        // Start from a known-off state so a leftover assertion can't read as success.
        _ = ShortcutsRunner.run(uuid: offID)
        try? await Task.sleep(for: .seconds(1))

        let stream = Process()
        stream.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        stream.arguments = [
            "stream", "--style", "compact",
            "--predicate", #"subsystem == "com.apple.donotdisturb" AND eventMessage CONTAINS "Inserted new assertion""#,
        ]
        let pipe = Pipe()
        stream.standardOutput = pipe
        stream.standardError = FileHandle.nullDevice

        do {
            try stream.run()
        } catch {
            Log.effects.error("could not start log stream for DND check: \(error, privacy: .public)")
            return false
        }

        // `log stream` needs a moment before it is actually delivering.
        try? await Task.sleep(for: .seconds(1))

        _ = ShortcutsRunner.run(uuid: onID)
        // Give the daemon time to record the assertion.
        try? await Task.sleep(for: .seconds(2, milliseconds: 500))

        stream.terminate()
        // The process has ended, so the pipe is at EOF and this returns everything
        // captured rather than blocking — no concurrent reader, no races.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let activated = output.contains("Inserted new assertion")

        // Leave the machine as we found it.
        _ = ShortcutsRunner.run(uuid: offID)

        return activated
    }
}

extension Duration {
    fileprivate static func seconds(_ whole: Int, milliseconds: Int) -> Duration {
        .milliseconds(whole * 1000 + milliseconds)
    }
}
