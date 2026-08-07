import AppKit

/// A small floating panel used in place of a system notification.
///
/// macOS refuses `UNUserNotificationCenter` authorization to any app that fails Gatekeeper
/// assessment, and an app signed with an Apple Development certificate rather than a
/// notarized Developer ID always does — so on a personal build, system notifications are
/// simply unavailable. Rather than let the Remind-me trigger silently do nothing, this
/// draws the same prompt itself. It needs no permission and cannot be refused.
///
/// Deliberately plain AppKit: this lives in the core module, which has no other reason to
/// depend on SwiftUI.
final class ReminderBanner {

    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?
    private var onActivate: (() -> Void)?

    func show(title: String, message: String, activateTitle: String, onActivate: @escaping () -> Void) {
        dismiss()
        self.onActivate = onActivate

        let width: CGFloat = 340
        let height: CGFloat = 92

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        // Follows the user between Spaces, like a real notification would.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.frame = NSRect(x: 14, y: height - 32, width: width - 28, height: 18)

        let messageLabel = NSTextField(labelWithString: message)
        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.frame = NSRect(x: 14, y: height - 54, width: width - 28, height: 18)

        let activate = NSButton(title: activateTitle, target: self, action: #selector(activateTapped))
        activate.bezelStyle = .rounded
        activate.keyEquivalent = "\r"
        activate.frame = NSRect(x: width - 110, y: 12, width: 96, height: 24)

        let dismissButton = NSButton(title: "Dismiss", target: self, action: #selector(dismissTapped))
        dismissButton.bezelStyle = .rounded
        dismissButton.frame = NSRect(x: width - 200, y: 12, width: 84, height: 24)

        for view in [titleLabel, messageLabel, activate, dismissButton] as [NSView] {
            background.addSubview(view)
        }
        panel.contentView = background

        position(panel, width: width, height: height)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }

        self.panel = panel

        // Self-dismissing, so a missed reminder never leaves a panel sitting on screen.
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
    }

    /// Top-right, below the menu bar — where a notification would appear.
    private func position(_ panel: NSPanel, width: CGFloat, height: CGFloat) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - width - 16,
            y: visible.maxY - height - 12
        ))
    }

    @objc private func activateTapped() {
        let handler = onActivate
        dismiss()
        handler?()
    }

    @objc private func dismissTapped() {
        dismiss()
    }

    func dismiss() {
        dismissWork?.cancel()
        dismissWork = nil
        panel?.orderOut(nil)
        panel = nil
        onActivate = nil
    }
}
