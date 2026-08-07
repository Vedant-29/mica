import AppKit
import CoreGraphics

/// Mica's mark: a rounded hexagon with a notch carved out of it.
///
/// Held as vector path data so one source serves every output — the `.icns` at all
/// iconset sizes, the menu bar template image, and any in-app use. This file is
/// deliberately free of SwiftUI and of actor isolation so `Tools/mkicon.swift` can
/// compile it directly at build time without pulling in the app target.
enum MicaIcon {

    /// The `viewBox` of the source artwork. Path coordinates are in this space, y-down.
    nonisolated static let viewBox = CGRect(x: 0, y: 0, width: 155.9, height: 142)

    /// Every line break here falls immediately *before* a command letter. That is load
    /// bearing: `\` in a multiline literal eats the newline and any indentation, so
    /// breaking mid-coordinate would silently weld two numbers together ("-5.2 1.9"
    /// becoming "-5.21.9") and quietly deform the mark.
    nonisolated static let pathData = """
    m141.8 65-26.2-45.6c-2.1-3.4-6-6.4-11.5-6.4h-51.8c-4.7 0-9.2 2.6-11.7 6.6\
    l-26.4 44.9c-2.2 3.7-2.3 9.6 0 13.4l25.6 43.7c2.1 4.1 6.2 7.7 12.3 7.9\
    l52.2-0.1c3.8 0 8.4-1.8 10.8-5.2 1.9-2.5 8.8-14.5 26.5-46.1 2.2-3.9 2.3-9.3 0.2-13.1\
    zm-17.4 12.1-17.1 29.6c-2.2 3.7-7 4-9.1 0.2l-17.2-30c-1.9-3.1-5-5.7-9.6-5.8\
    h-34.3c-1.4 0-2.1 0-3.5-1.3-1.7-1.7-2.5-4.1-0.9-6.7l16.7-28.4c1.9-3.9 6.1-7.2 10.9-7.5\
    h35.7c5.2 0.6 9.3 4.1 10.7 7.4l17.6 30.8c2.1 3.2 2.1 8.1 0.1 11.7z
    """

    /// The parsed glyph in SVG coordinate space. Parsing is not free and this is asked
    /// for at ten icon sizes plus every menu bar redraw, so it is done once.
    nonisolated(unsafe) private static let parsedPath = SVGPath.parse(pathData)

    /// The glyph's own tight bounds, which sit *inside* `viewBox` — the source artwork
    /// carries roughly 12 units of padding on every side. Fitting against these rather
    /// than the viewBox means callers get a glyph that actually fills the box they
    /// asked for, instead of one silently shrunk by the artwork's internal margins.
    nonisolated static var glyphBounds: CGRect { parsedPath.boundingBoxOfPath }

    /// The glyph scaled to fit `rect` and flipped from SVG's y-down space into Core
    /// Graphics' y-up space. Aspect ratio is preserved and the result is centred.
    nonisolated static func glyphPath(fitting rect: CGRect) -> CGPath {
        let bounds = glyphBounds
        guard bounds.width > 0, bounds.height > 0 else { return parsedPath }

        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        let scaled = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        // Compose right-to-left: shift the artwork's own origin to zero, flip Y (SVG
        // grows downward, Core Graphics upward), then place it centred in `rect`.
        var transform = CGAffineTransform.identity
            .translatedBy(x: rect.midX - scaled.width / 2, y: rect.midY + scaled.height / 2)
            .scaledBy(x: scale, y: -scale)
            .translatedBy(x: -bounds.minX, y: -bounds.minY)

        return parsedPath.copy(using: &transform) ?? parsedPath
    }

    /// Cheap integrity check on the hand-rolled parse. A line break that swallowed a
    /// separator between two coordinates welds them into one huge number, which throws
    /// the geometry far outside the viewBox — so containment plus a sane fill fraction
    /// catches exactly that failure without hard-coding the artwork's dimensions.
    nonisolated static func validateGeometry() -> String? {
        let bounds = glyphBounds
        guard bounds.width > 0, bounds.height > 0 else {
            return "parsed path is empty"
        }
        let slack: CGFloat = 1
        guard bounds.minX >= -slack, bounds.minY >= -slack,
              bounds.maxX <= viewBox.width + slack, bounds.maxY <= viewBox.height + slack
        else {
            return "parsed bounds \(bounds) fall outside viewBox \(viewBox)"
        }
        guard bounds.width >= viewBox.width / 2, bounds.height >= viewBox.height / 2 else {
            return "parsed bounds \(bounds) cover too little of viewBox \(viewBox)"
        }
        return nil
    }

    // MARK: - Menu bar

    /// A template image for the status item. Template images carry shape in their alpha
    /// channel only, so macOS tints them for light/dark menu bars automatically — which
    /// also means the fill colour here is irrelevant beyond being fully opaque.
    nonisolated static func menuBarImage(pointSize: CGFloat = 18) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(glyphPath(fitting: rect))
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath(using: .evenOdd)
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - App icon

    /// One app-icon tile: the macOS rounded-rect plate with the glyph knocked out in white.
    ///
    /// `fullSize` is the canvas edge (1024, 512, …). Apple's icon grid insets the plate
    /// from the canvas, so the plate is drawn at `plateRatio` of the canvas with a
    /// continuous-corner radius, matching how system icons sit next to each other.
    nonisolated static func appIconImage(fullSize: CGFloat) -> NSImage {
        let plateRatio: CGFloat = 824.0 / 1024.0
        let cornerRatio: CGFloat = 0.2237   // Apple's squircle radius, as a fraction of the plate
        let glyphRatio: CGFloat = 0.52      // glyph width relative to the plate

        let canvas = CGRect(x: 0, y: 0, width: fullSize, height: fullSize)
        let plateEdge = fullSize * plateRatio
        let plate = CGRect(
            x: (fullSize - plateEdge) / 2,
            y: (fullSize - plateEdge) / 2,
            width: plateEdge,
            height: plateEdge
        )

        return NSImage(size: NSSize(width: fullSize, height: fullSize), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            context.clear(canvas)

            // Near-black plate with a barely-there vertical lift, so the icon reads as a
            // solid object rather than a hole at large sizes.
            let plateShape = CGPath(
                roundedRect: plate,
                cornerWidth: plateEdge * cornerRatio,
                cornerHeight: plateEdge * cornerRatio,
                transform: nil
            )
            context.saveGState()
            context.addPath(plateShape)
            context.clip()
            let colors = [
                NSColor(calibratedWhite: 0.14, alpha: 1).cgColor,
                NSColor(calibratedWhite: 0.04, alpha: 1).cgColor,
            ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]
            ) {
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: plate.midX, y: plate.maxY),
                    end: CGPoint(x: plate.midX, y: plate.minY),
                    options: []
                )
            }
            context.restoreGState()

            let glyphEdge = plateEdge * glyphRatio
            let glyphBox = CGRect(
                x: plate.midX - glyphEdge / 2,
                y: plate.midY - glyphEdge / 2,
                width: glyphEdge,
                height: glyphEdge
            )
            context.addPath(glyphPath(fitting: glyphBox))
            context.setFillColor(NSColor(calibratedWhite: 0.91, alpha: 1).cgColor)
            context.fillPath(using: .evenOdd)

            return true
        }
    }
}
