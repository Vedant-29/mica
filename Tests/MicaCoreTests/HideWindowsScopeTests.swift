import Foundation
import Testing

@testable import MicaCore

@Suite("Hide Active Windows scopes")
struct HideWindowsScopeTests {

    @Test("Only the list-based scopes read the app list")
    func onlyListScopesUseTheList() {
        #expect(HideWindowsScope.all.usesAppList == false)
        #expect(HideWindowsScope.exceptFrontmost.usesAppList == false)
        #expect(HideWindowsScope.onlySelected.usesAppList)
        #expect(HideWindowsScope.allExceptSelected.usesAppList)
    }

    @Test("Every scope is offered in the picker and round-trips through storage")
    func scopesArePersistable() throws {
        for scope in HideWindowsScope.allCases {
            let restored = HideWindowsScope(rawValue: scope.rawValue)
            #expect(restored == scope)
            #expect(!scope.displayName.isEmpty)
        }
        // The two original scopes keep their raw values, so upgrading doesn't reset
        // anyone's existing preference.
        #expect(HideWindowsScope.all.rawValue == "all")
        #expect(HideWindowsScope.exceptFrontmost.rawValue == "exceptFrontmost")
    }

    @Test("Options carry the chosen apps and compare by value")
    func optionsCarrySelection() {
        let a = EffectOptions(hideWindowsScope: .onlySelected, selectedWindowApps: ["com.tinyspeck.slackmacgap"])
        let b = EffectOptions(hideWindowsScope: .onlySelected, selectedWindowApps: ["com.tinyspeck.slackmacgap"])
        let c = EffectOptions(hideWindowsScope: .onlySelected, selectedWindowApps: [])
        #expect(a == b)
        #expect(a != c)
    }

    /// The scope changes which apps are chosen, never how they're restored: the effect
    /// records exactly what it hid, so narrowing the list mid-session can't strand
    /// anything it hid earlier under a wider scope.
    @Test("Restore is driven by what was hidden, not by the current scope")
    func restoreIsIndependentOfScope() throws {
        let prior = WindowsEffect.PriorState(hiddenBundleIDs: ["com.apple.Safari", "com.apple.finder"])
        let encoded = try JSONEncoder().encode(prior)
        let decoded = try JSONDecoder().decode(WindowsEffect.PriorState.self, from: encoded)
        #expect(decoded.hiddenBundleIDs == prior.hiddenBundleIDs)
    }
}
