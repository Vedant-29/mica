import AppKit

/// Generates the two Do Not Disturb shortcuts so the user doesn't have to build them.
///
/// A shortcut file is a plist, and `shortcuts sign` will sign an arbitrary one — which
/// matters, because macOS refuses to import an *unsigned* shortcut unless the user has
/// first enabled "Allow Untrusted Shortcuts", a setting that only appears after they've
/// already run one. Signing sidesteps that entirely: the file opens straight into the
/// Shortcuts add sheet.
public nonisolated enum ShortcutInstaller {

    public static let onName = "Mica Do Not Disturb On"
    public static let offName = "Mica Do Not Disturb Off"

    public enum InstallError: Error, CustomStringConvertible {
        case signingFailed(String)

        public var description: String {
            switch self {
            case .signingFailed(let detail): "Could not create the shortcut: \(detail)"
            }
        }
    }

    /// Writes, signs, and opens both shortcuts. The user confirms each with Add Shortcut.
    ///
    /// Signing is the slow part at roughly four seconds each, so the two run concurrently
    /// rather than back to back.
    public static func install() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Mica-Shortcuts", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        async let on = prepare(name: onName, turnOn: true, in: directory)
        async let off = prepare(name: offName, turnOn: false, in: directory)
        let urls = try await [on, off]

        // Opened On first so the two Shortcuts sheets arrive in the order the UI
        // describes them.
        await MainActor.run {
            for url in urls { NSWorkspace.shared.open(url) }
        }
    }

    private static func prepare(name: String, turnOn: Bool, in directory: URL) throws -> URL {
        // The imported shortcut takes its name from the file, so the file has to be named
        // exactly what we later look for in `shortcuts list`.
        let unsigned = directory.appending(path: "\(name).unsigned.shortcut")
        let signed = directory.appending(path: "\(name).shortcut")
        try plist(turnOn: turnOn).write(to: unsigned)
        try sign(input: unsigned, output: signed)
        return signed
    }

    /// Looks for shortcuts matching the names this installer uses.
    public static func findInstalled() -> (on: String?, off: String?) {
        let all = ShortcutsRunner.list()
        return (
            all.first { $0.name == onName }?.uuid,
            all.first { $0.name == offName }?.uuid
        )
    }

    private static func sign(input: URL, output: URL) throws {
        try? FileManager.default.removeItem(at: output)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        // `anyone` rather than the default `people-who-know-me`, which would tie the
        // signature to an iCloud identity the user may not have configured.
        process.arguments = [
            "sign", "-m", "anyone",
            "-i", input.path,
            "-o", output.path,
        ]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: output.path) else {
            let detail = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
            throw InstallError.signingFailed(detail)
        }
    }

    /// A single "Set Focus" action.
    ///
    /// `FocusModes` names Do Not Disturb explicitly rather than relying on the action's
    /// default, so it doesn't silently target whichever Focus the system considers
    /// current. If a future macOS changes the parameter shape, the action still imports
    /// and stays editable in the Shortcuts app — which is why Settings offers a test.
    private static func plist(turnOn: Bool) throws -> Data {
        let action: [String: Any] = [
            "WFWorkflowActionIdentifier": "is.workflow.actions.dnd.set",
            "WFWorkflowActionParameters": [
                "OnValue": turnOn ? 1 : 0,
                "Enabled": turnOn,
                "FocusModes": [
                    "Identifier": "com.apple.donotdisturb.mode.default",
                    "DisplayString": "Do Not Disturb",
                ],
            ],
        ]

        let workflow: [String: Any] = [
            "WFWorkflowClientVersion": "2607.1.2",
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowMinimumClientVersionString": "900",
            "WFWorkflowIcon": [
                // A real colour. -1 renders the tile white, which on the Shortcuts app's
                // white background makes the shortcut look like it was never created.
                "WFWorkflowIconStartColor": 463140863,
                "WFWorkflowIconGlyphNumber": 61440,
            ],
            "WFWorkflowImportQuestions": [],
            "WFWorkflowTypes": [],
            "WFWorkflowInputContentItemClasses": [],
            "WFWorkflowActions": [action],
        ]

        return try PropertyListSerialization.data(
            fromPropertyList: workflow, format: .xml, options: 0
        )
    }
}
