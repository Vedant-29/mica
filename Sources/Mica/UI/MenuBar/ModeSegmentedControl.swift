import MicaCore
import SwiftUI

/// The On / Auto / Off control in the popover header.
///
/// Hand-built rather than a SwiftUI `Picker(.segmented)` because the selected segment
/// needs to carry the amber "engaged" colour, which the system style won't tint.
struct ModeSegmentedControl: View {
    @Binding var mode: AppMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppMode.allCases, id: \.self) { candidate in
                Button {
                    mode = candidate
                } label: {
                    Text(candidate.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(candidate == mode ? Color.white : Color.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background {
                            if candidate == mode {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Theme.accent)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate.displayName)
                .accessibilityAddTraits(candidate == mode ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        }
    }
}
