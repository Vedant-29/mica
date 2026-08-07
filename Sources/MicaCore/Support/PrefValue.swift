import Foundation

/// A preference value that remembers whether the key existed at all.
///
/// Restoring a previously-absent key by writing `false` is not equivalent to deleting it:
/// it leaves behind a setting the user never chose, which then shows up in their System
/// Settings and in any migration or backup. Every restore path in Mica has to be able to
/// put the system back to *exactly* how it found it, absences included.
public nonisolated enum PrefValue<Wrapped: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    case absent
    case present(Wrapped)

    public var value: Wrapped? {
        switch self {
        case .absent: nil
        case .present(let wrapped): wrapped
        }
    }
}
