import MicaCore
import SwiftUI

/// One line under the header explaining what Mica is doing and why.
///
/// Worth the space: without it, "Auto" is opaque — the user can't tell whether nothing is
/// happening because no trigger fired, because an excluded app is running, or because a
/// feature failed.
struct StatusBannerView: View {
    let decision: EngagementDecision
    let capturerName: String?

    var body: some View {
        if let message {
            HStack(spacing: 6) {
                Circle()
                    .fill(decision.shouldEngage ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.quaternary))
                    .frame(width: 6, height: 6)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.horizontalPadding)
            .padding(.bottom, 8)
        }
    }

    /// Nil when there's nothing to add.
    ///
    /// In On and Off the segmented control right above already says exactly this, and a
    /// line that only ever echoes the control next to it is noise. The banner earns its
    /// space in Auto, where the mode alone doesn't tell you whether anything is happening.
    private var message: String? {
        switch decision.reason {
        case .modeOn, .modeOff:
            nil
        case .screenCaptured:
            // Naming the capturing app is strictly nicer than "something is capturing",
            // but attribution is best-effort, so fall back rather than promising it.
            capturerName.map { "\($0) is capturing your screen" } ?? decision.reason.summary
        default:
            decision.reason.summary
        }
    }
}
