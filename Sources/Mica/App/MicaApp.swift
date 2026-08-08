import MenuBarExtraAccess
import MicaCore
import SwiftUI

@main
struct MicaApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var isPopoverPresented = false

    var body: some Scene {
        MenuBarExtra {
            PopoverRootView(environment: appDelegate.environment) {
                isPopoverPresented = false
            }
        } label: {
            // The glyph is drawn from vector path data rather than loaded as an asset,
            // so it stays crisp on any display and renders as a template image that
            // follows the light/dark menu bar automatically.
            Image(nsImage: MicaIcon.menuBarImage())
        }
        // Order matters: menuBarExtraStyle changes the Scene type, and the access
        // modifier is only defined on the MenuBarExtra itself.
        .menuBarExtraAccess(isPresented: $isPopoverPresented)
        .menuBarExtraStyle(.window)
    }
}
