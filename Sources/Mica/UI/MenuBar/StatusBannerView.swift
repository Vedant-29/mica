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

    private var message: String {
        // Naming the capturing app is strictly nicer than "something is capturing", but
        // attribution is best-effort, so fall back rather than promising it.
        if case .screenCaptured = decision.reason, let capturerName {
            return "\(capturerName) is capturing your screen"
        }
        return decision.reason.summary
    }
}
