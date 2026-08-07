import AppKit
import Foundation

/// Renders `MicaIcon`'s vector path into a `.iconset` directory at every size macOS
/// wants, ready for `iconutil --convert icns`.
///
/// Compiled at build time against `Sources/Mica/UI/MicaIcon.swift` and `SVGPath.swift`,
/// so the icon has exactly one source of truth and no committed rasters to drift.
@main
struct MakeIcon {

    /// (filename suffix, pixel edge). Retina variants are rendered at true pixel size.
    static let slices: [(name: String, pixels: Int)] = [
        ("16x16", 16), ("16x16@2x", 32),
        ("32x32", 32), ("32x32@2x", 64),
        ("128x128", 128), ("128x128@2x", 256),
        ("256x256", 256), ("256x256@2x", 512),
        ("512x512", 512), ("512x512@2x", 1024),
    ]

    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count == 2 else {
            FileHandle.standardError.write(Data("usage: mkicon <out.iconset>\n".utf8))
            exit(2)
        }
        let outputDirectory = URL(fileURLWithPath: arguments[1])

        // The parser is hand-rolled, so check the geometry is sane before baking it into
        // ten PNGs — a mangled path would otherwise surface only as a subtly wrong icon.
        if let problem = MicaIcon.validateGeometry() {
            FileHandle.standardError.write(Data("""
                mkicon: \(problem)
                The SVG path data is likely malformed — check for a line break that \
                swallowed a separator between two numbers.

                """.utf8))
            exit(1)
        }
        print("  glyph bounds \(shortDescription(MicaIcon.glyphBounds)) ✓")

        do {
            try? FileManager.default.removeItem(at: outputDirectory)
            try FileManager.default.createDirectory(
                at: outputDirectory, withIntermediateDirectories: true
            )

            for slice in slices {
                let data = try render(pixels: slice.pixels)
                try data.write(to: outputDirectory.appending(path: "icon_\(slice.name).png"))
            }
        } catch {
            FileHandle.standardError.write(Data("mkicon: \(error)\n".utf8))
            exit(1)
        }

        print("  wrote \(slices.count) slices → \(outputDirectory.path)")
    }

    /// Draws one tile at an exact pixel size, preserving alpha outside the icon plate.
    static func render(pixels: Int) throws -> Data {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else {
            throw Failure("could not allocate a \(pixels)×\(pixels) bitmap")
        }
        representation.size = NSSize(width: pixels, height: pixels)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        NSGraphicsContext.current?.imageInterpolation = .high

        let bounds = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        MicaIcon.appIconImage(fullSize: CGFloat(pixels))
            .draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)

        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw Failure("PNG encoding failed at \(pixels)px")
        }
        return data
    }

    static func shortDescription(_ rect: CGRect) -> String {
        String(format: "%.1f×%.1f", rect.width, rect.height)
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
