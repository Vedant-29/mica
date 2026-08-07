import OSLog

public nonisolated enum Log {
    private static let subsystem = "com.vedant.mica"

    public static let coordinator = Logger(subsystem: subsystem, category: "coordinator")
    public static let effects = Logger(subsystem: subsystem, category: "effects")
    public static let recovery = Logger(subsystem: subsystem, category: "recovery")
    public static let monitors = Logger(subsystem: subsystem, category: "monitors")
}
