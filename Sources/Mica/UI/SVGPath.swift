import CoreGraphics
import Foundation

/// A minimal parser for the `d` attribute of an SVG `<path>`.
///
/// This exists so the app icon can be stored as its original vector path rather than
/// a pile of rasterised PNGs: the same source drives the `.icns`, the menu bar template
/// image, and any in-app rendering, all crisp at any size. No SVG rasteriser is
/// installed on this machine (`rsvg-convert`, `magick`, `inkscape` are all absent) and
/// `sips` cannot read SVG, so parsing the path ourselves avoids a build dependency.
///
/// Supports the command subset Mica's icon uses, plus enough neighbours to be useful:
/// `M m L l H h V v C c S s Z z`. Arcs and quadratics are not implemented — they would
/// be dead code here, and silently mis-rendering them is worse than not accepting them.
enum SVGPath {

    /// Parses path data into a `CGPath` in the SVG's own coordinate space (y-down).
    /// Callers are responsible for flipping and fitting — see `MicaIcon.glyphPath(fitting:)`.
    nonisolated static func parse(_ d: String) -> CGPath {
        let path = CGMutablePath()
        var lexer = Lexer(d)

        var current = CGPoint.zero      // current point
        var subpathStart = CGPoint.zero // where the active subpath began, for Z
        var lastCubicControl: CGPoint?  // trailing control point, for S/s reflection
        var command: Character = " "

        // A leading lowercase `m` is defined to be absolute. Because `current` starts at
        // the origin, treating it as relative produces exactly that — no special case.
        while let cmd = lexer.nextCommand(continuing: command) {
            command = cmd
            let isRelative = cmd.isLowercase

            /// Resolves a coordinate pair against the current point when the command is relative.
            func resolve(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                isRelative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }

            switch cmd {
            case "M", "m":
                guard let x = lexer.number(), let y = lexer.number() else { return path }
                current = resolve(x, y)
                subpathStart = current
                lastCubicControl = nil
                path.move(to: current)

            case "L", "l":
                guard let x = lexer.number(), let y = lexer.number() else { return path }
                current = resolve(x, y)
                lastCubicControl = nil
                path.addLine(to: current)

            case "H", "h":
                guard let x = lexer.number() else { return path }
                current = CGPoint(x: isRelative ? current.x + x : x, y: current.y)
                lastCubicControl = nil
                path.addLine(to: current)

            case "V", "v":
                guard let y = lexer.number() else { return path }
                current = CGPoint(x: current.x, y: isRelative ? current.y + y : y)
                lastCubicControl = nil
                path.addLine(to: current)

            case "C", "c":
                guard let x1 = lexer.number(), let y1 = lexer.number(),
                      let x2 = lexer.number(), let y2 = lexer.number(),
                      let x = lexer.number(), let y = lexer.number() else { return path }
                let c1 = resolve(x1, y1), c2 = resolve(x2, y2)
                current = resolve(x, y)
                lastCubicControl = c2
                path.addCurve(to: current, control1: c1, control2: c2)

            case "S", "s":
                guard let x2 = lexer.number(), let y2 = lexer.number(),
                      let x = lexer.number(), let y = lexer.number() else { return path }
                // The first control point mirrors the previous curve's trailing control
                // point about the current point; with no previous curve it coincides with it.
                let c1 = lastCubicControl.map {
                    CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y)
                } ?? current
                let c2 = resolve(x2, y2)
                current = resolve(x, y)
                lastCubicControl = c2
                path.addCurve(to: current, control1: c1, control2: c2)

            case "Z", "z":
                path.closeSubpath()
                current = subpathStart
                lastCubicControl = nil

            default:
                // An unsupported command means every following coordinate is being read
                // against the wrong grammar, so the rest of the path is meaningless.
                assertionFailure("SVGPath: unsupported command '\(cmd)'")
                return path
            }
        }

        return path
    }

    // MARK: - Lexer

    // The package sets `defaultIsolation(MainActor.self)`, which would otherwise pull
    // this into the main actor and make it unreachable from the nonisolated parser —
    // and from `Tools/mkicon.swift`, which compiles these files outside the package.
    private nonisolated struct Lexer {
        private let chars: [Character]
        private var index = 0

        init(_ source: String) { chars = Array(source) }

        private mutating func skipSeparators() {
            while index < chars.count, chars[index] == " " || chars[index] == ","
                    || chars[index] == "\n" || chars[index] == "\t" || chars[index] == "\r" {
                index += 1
            }
        }

        /// Returns the next explicit command letter, or the implicit repeat of `previous`
        /// when the next token is another coordinate. SVG defines the implicit repeat of
        /// a moveto as a lineto, which is why `M`/`m` decay rather than repeating.
        mutating func nextCommand(continuing previous: Character) -> Character? {
            skipSeparators()
            guard index < chars.count else { return nil }

            if chars[index].isLetter {
                defer { index += 1 }
                return chars[index]
            }

            switch previous {
            case "M": return "L"
            case "m": return "l"
            case " ": return nil   // coordinates before any command: malformed
            default: return previous
            }
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            guard index < chars.count else { return nil }

            var literal = ""
            if chars[index] == "-" || chars[index] == "+" {
                literal.append(chars[index])
                index += 1
            }

            var sawDecimalPoint = false
            while index < chars.count {
                let c = chars[index]
                if c.isNumber {
                    literal.append(c)
                    index += 1
                } else if c == "." && !sawDecimalPoint {
                    // A second '.' starts a new number — SVG allows "0.5.5" to mean 0.5 then 0.5.
                    sawDecimalPoint = true
                    literal.append(c)
                    index += 1
                } else if c == "e" || c == "E" {
                    literal.append(c)
                    index += 1
                    if index < chars.count, chars[index] == "-" || chars[index] == "+" {
                        literal.append(chars[index])
                        index += 1
                    }
                } else {
                    break
                }
            }

            return Double(literal).map { CGFloat($0) }
        }
    }
}
