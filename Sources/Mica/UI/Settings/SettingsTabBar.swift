import SwiftUI

/// The settings window's top navigation.
///
/// Hand-built rather than SwiftUI's `TabView`, which on macOS 26 wraps itself in toolbar
/// chrome that carries a heavy drop shadow — and there's no API to turn that off. Drawing
/// the strip directly keeps the icon-above-label look of a classic preferences window
/// while leaving the background completely flat.
struct SettingsTabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                TabButton(tab: tab, isSelected: selection == tab) {
                    selection = tab
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
}

private struct TabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 16, weight: .regular))
                    .frame(height: 20)
                Text(tab.title)
                    .font(.system(size: 11))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(width: 82, height: 48)
            .background {
                // A flat fill, no shadow and no border — the selected state reads from
                // the tint and the wash alone.
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(fill)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var fill: some ShapeStyle {
        if isSelected {
            AnyShapeStyle(Color.accentColor.opacity(0.14))
        } else if isHovered {
            AnyShapeStyle(.quaternary.opacity(0.5))
        } else {
            AnyShapeStyle(.clear)
        }
    }
}
