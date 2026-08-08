import AppKit
import MicaCore
import SwiftUI

/// A grid of app tiles with icons big enough to recognise at a glance.
///
/// The list this replaced packed 18pt icons into table rows, which made the app you
/// picked the least legible thing on screen — backwards, since the whole point of the
/// section is confirming *which* apps are selected.
struct AppGridView: View {
    @Bindable var store: AppListStore
    /// Shows the Activate / Remind me control on each tile.
    var showsAction: Bool = false
    var emptyMessage: String = "No apps selected yet."
    let onChange: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 132), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.entries.isEmpty {
                HStack {
                    Spacer()
                    Text(emptyMessage)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.vertical, 18)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(store.entries) { entry in
                        AppTile(entry: entry, showsAction: showsAction) { action in
                            switch action {
                            case .remove:
                                store.remove(bundleID: entry.bundleID)
                            case .setAction(let value):
                                store.setAction(value, for: entry.bundleID)
                            }
                            onChange()
                        }
                    }
                }
            }

            Button {
                let added = AppPicker.chooseMany()
                guard !added.isEmpty else { return }
                for entry in added { store.add(entry) }
                onChange()
            } label: {
                Label("Add Apps…", systemImage: "plus")
            }
        }
    }
}

private struct AppTile: View {
    enum Action {
        case remove
        case setAction(TriggerAction)
    }

    let entry: AppEntry
    let showsAction: Bool
    let perform: (Action) -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: AppIconCache.icon(forBundleID: entry.bundleID))
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)

            Text(entry.displayName)
                .font(.system(size: 11))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if showsAction {
                Picker("", selection: Binding(
                    get: { entry.action },
                    set: { perform(.setAction($0)) }
                )) {
                    ForEach(TriggerAction.allCases) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .controlSize(.mini)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(isHovered ? 0.55 : 0.3))
        }
        .overlay(alignment: .topTrailing) {
            // Revealed on hover so a grid of ten apps isn't a grid of ten delete buttons.
            if isHovered {
                Button {
                    perform(.remove)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .secondary)
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel("Remove \(entry.displayName)")
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

/// Picks application bundles.
///
/// An open panel rather than a list of running apps: it reaches anything installed, not
/// only what happens to be running, which is the common case when setting this up ahead
/// of a meeting rather than during one.
enum AppPicker {
    static func chooseMany() -> [AppEntry] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        panel.message = "Choose applications"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return [] }

        return panel.urls.compactMap { url in
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return nil }
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            return AppEntry(bundleID: bundleID, displayName: name)
        }
    }
}

enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(forBundleID bundleID: String) -> NSImage {
        if let cached = cache[bundleID] { return cached }

        let image: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSWorkspace.shared.icon(for: .application)
        }
        cache[bundleID] = image
        return image
    }
}
