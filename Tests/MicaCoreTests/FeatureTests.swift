import Testing

@testable import MicaCore

@Suite("Feature ordering")
struct FeatureTests {

    @Test("Engage order covers every feature exactly once")
    func engageOrderIsComplete() {
        #expect(Set(Feature.engageOrder) == Set(Feature.allCases))
        #expect(Feature.engageOrder.count == Feature.allCases.count)
    }

    @Test("Disengage order is the exact reverse of engage order")
    func disengageOrderIsReversed() {
        #expect(Feature.disengageOrder == Feature.engageOrder.reversed())
    }

    /// Hiding a window before the desktop is covered would flash the wallpaper through
    /// the gap — the whole thing this app exists to prevent.
    @Test("The desktop is covered before windows are hidden")
    func desktopIsCoveredBeforeWindowsAreHidden() throws {
        let wallpaper = try #require(Feature.engageOrder.firstIndex(of: .hideWallpaper))
        let desktopItems = try #require(Feature.engageOrder.firstIndex(of: .hideDesktopItems))
        let windows = try #require(Feature.engageOrder.firstIndex(of: .hideWindows))

        #expect(wallpaper < windows)
        #expect(desktopItems < windows)
    }

    /// Only effects that outlive the process belong in the crash snapshot; the cover
    /// window and the menu bar spacer die with it, so recording them would be noise.
    @Test("Process-local effects are excluded from crash recovery")
    func processLocalEffectsAreNotPersistent() {
        #expect(Feature.hideWallpaper.mutatesPersistentSystemState == false)
        #expect(Feature.hideMenuBarIcons.mutatesPersistentSystemState == false)
        #expect(Feature.hideDock.mutatesPersistentSystemState)
        #expect(Feature.doNotDisturb.mutatesPersistentSystemState)
    }
}
