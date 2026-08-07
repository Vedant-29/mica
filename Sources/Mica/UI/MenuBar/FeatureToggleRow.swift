import MicaCore
import SwiftUI

/// One privacy feature in the popover: an icon chip that fills amber when enabled,
/// the feature name, and an optional ⓘ for features whose behaviour needs a caveat.
///
/// The whole row is the hit target — a 28pt chip is a fussy thing to aim at, and every
/// row here is a plain toggle, so there's nothing else a click could mean.
struct FeatureToggleRow: View {
    let feature: Feature
    let isEnabled: Bool
    let onToggle: () -> Void

    @State private var isHovered = false
    @State private var isShowingNote = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                chip
                Text(feature.displayName)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if feature.note != nil {
                    noteButton
                }
            }
            .padding(.horizontal, Theme.horizontalPadding)
            .frame(height: Theme.rowHeight)
            .contentShape(.rect)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary.opacity(0.6))
                        .padding(.horizontal, Theme.horizontalPadding - 6)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(feature.displayName)
        .accessibilityValue(isEnabled ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }

    private var chip: some View {
        RoundedRectangle(cornerRadius: Theme.chipCornerRadius, style: .continuous)
            .fill(isEnabled ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.quaternary))
            .frame(width: Theme.chipSize, height: Theme.chipSize)
            .overlay {
                Image(systemName: feature.symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            }
    }

    private var noteButton: some View {
        Button {
            isShowingNote = true
        } label: {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingNote, arrowEdge: .trailing) {
            Text(feature.note ?? "")
                .font(.system(size: 12))
                .frame(width: 220, alignment: .leading)
                .padding(12)
        }
        .accessibilityLabel("About \(feature.displayName)")
    }
}

/// A plain action row, used for Settings and Quit beneath the feature list.
struct MenuActionRow: View {
    let title: String
    let symbolName: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: Theme.chipSize, height: Theme.chipSize)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.horizontalPadding)
            .frame(height: 32)
            .contentShape(.rect)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary.opacity(0.6))
                        .padding(.horizontal, Theme.horizontalPadding - 6)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
