import Foundation
import Testing

@testable import MicaCore

@Suite("Prior-state encoding")
struct SnapshotTests {

    /// The distinction this type exists for has to survive the round trip through the
    /// crash snapshot, or recovery would restore an absent key as `false` and leave
    /// behind a setting the user never chose.
    @Test("PrefValue keeps absent and present-false distinct through JSON")
    func prefValueRoundTrips() throws {
        let absent = PrefValue<Bool>.absent
        let presentFalse = PrefValue<Bool>.present(false)
        #expect(absent != presentFalse)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let decodedAbsent = try decoder.decode(PrefValue<Bool>.self, from: encoder.encode(absent))
        let decodedPresent = try decoder.decode(PrefValue<Bool>.self, from: encoder.encode(presentFalse))

        #expect(decodedAbsent == absent)
        #expect(decodedPresent == presentFalse)
        #expect(decodedAbsent != decodedPresent)
    }

    @Test("Desktop item prior state survives a snapshot round trip")
    func desktopPriorStateRoundTrips() throws {
        let original = DesktopItemsEffect.PriorState(
            hideIcons: .absent,
            hideWidgets: .present(false)
        )
        let payload = try JSONEncoder().encode(original)
        let snapshot = SessionSnapshot(effects: [Feature.hideDesktopItems.rawValue: payload])

        let reloaded = try JSONDecoder().decode(
            SessionSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        let restored = try #require(reloaded.effects[Feature.hideDesktopItems.rawValue])

        #expect(try JSONDecoder().decode(DesktopItemsEffect.PriorState.self, from: restored) == original)
    }

    @Test("A snapshot records the boot session so a crash can be told from a reboot")
    func snapshotCapturesBootSession() {
        let snapshot = SessionSnapshot(effects: [:])
        #expect(snapshot.bootSessionUUID == BootSession.current)
        #expect(snapshot.processIdentifier == ProcessInfo.processInfo.processIdentifier)
    }

    /// Restore walks the reverse of engage order, so windows reappear before the
    /// wallpaper cover is lifted rather than after.
    @Test("Recovery restores windows before uncovering the desktop")
    func recoveryOrderRestoresWindowsFirst() throws {
        let windows = try #require(Feature.disengageOrder.firstIndex(of: .hideWindows))
        let wallpaper = try #require(Feature.disengageOrder.firstIndex(of: .hideWallpaper))
        #expect(windows < wallpaper)
    }
}
