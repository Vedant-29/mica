import MicaCore
import SwiftUI

@main
struct MicaApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PopoverRootView(environment: appDelegate.environment)
        } label: {
            // The glyph is drawn from vector path data rather than loaded as an asset,
            // so it stays crisp on any display and renders as a template image that
            // follows the light/dark menu bar automatically.
            Image(nsImage: MicaIcon.menuBarImage())
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView(environment: appDelegate.environment)
        }
    }
}
