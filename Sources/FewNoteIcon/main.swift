import AppKit
import FewNoteKit

/// Draws FewNote's app icon, and assembles the `.icns` the bundle needs.
///
/// The mark is the app's own wordmark, struck in the same 5×8 dot matrix the writing happens on,
/// so the icon in the Dock is made of the same stuff as the note on the screen. Small sizes get
/// the single letter instead: seven letters at thirty-two pixels is a smudge, not a name.
///
///     FewNoteIcon <output.icns>
@main
struct FewNoteIcon {

    /// The sizes macOS asks an app icon for. `iconutil` wants each of them twice, once at 1× and
    /// once at 2×, so the same pixels are rendered once and written twice under different names.
    static let sizes = [16, 32, 64, 128, 256]

    static func main() {
        let output = URL(fileURLWithPath: CommandLine.arguments.count > 1
                         ? CommandLine.arguments[1]
                         : "AppIcon.icns")

        let iconset = FileManager.default.temporaryDirectory
            .appendingPathComponent("FewNote-\(UUID().uuidString).iconset", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: iconset) }

        do {
            try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
            for size in sizes {
                guard let data = render(size: size) else {
                    throw Failure("could not render the \(size) pixel icon")
                }
                for name in names(for: size) {
                    try data.write(to: iconset.appendingPathComponent(name))
                }
            }

            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", output.path])
            print("Icon: \(output.path)")
        } catch {
            FileHandle.standardError.write("FewNoteIcon: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    /// The `.iconset` file names a rendered size is written under.
    static func names(for size: Int) -> [String] {
        switch size {
        case 16: return ["icon_16x16.png"]
        case 32: return ["icon_16x16@2x.png", "icon_32x32.png"]
        case 64: return ["icon_32x32@2x.png"]
        case 128: return ["icon_128x128.png"]
        case 256: return ["icon_128x128@2x.png", "icon_256x256.png"]
        case 512: return ["icon_256x256@2x.png", "icon_512x512.png"]
        case 1024: return ["icon_512x512@2x.png"]
        default: return []
        }
    }

    // MARK: - Drawing

    static func render(size: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: size, pixelsHigh: size,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: size, height: size)

        guard let graphics = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        draw(in: graphics.cgContext, size: CGFloat(size))
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    static func draw(in context: CGContext, size: CGFloat) {
        let plate = CGRect(x: 0, y: 0, width: size, height: size)
            .insetBy(dx: size * 0.055, dy: size * 0.055)
        let radius = plate.width * 0.2237

        context.saveGState()
        context.addPath(CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius,
                               transform: nil))
        context.clip()

        drawPlate(in: context, plate: plate)
        drawField(in: context, plate: plate)
        drawWordmark(in: context, plate: plate)

        context.restoreGState()
    }

    /// The panel itself: dark, very slightly graduated, so the dots have a surface to sit on.
    static func drawPlate(in context: CGContext, plate: CGRect) {
        let colours = [NSColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1).cgColor,
                       NSColor(srgbRed: 0.03, green: 0.03, blue: 0.04, alpha: 1).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colours, locations: [0, 1]) else { return }
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: plate.midX, y: plate.maxY),
                                   end: CGPoint(x: plate.midX, y: plate.minY),
                                   options: [])
    }

    /// The unlit dots: the same field the writing surface draws, at whatever pitch fits the icon.
    static func drawField(in context: CGContext, plate: CGRect) {
        let pitch = plate.width / 26
        let radius = pitch * 0.09
        let path = CGMutablePath()
        var y = plate.minY + pitch
        var row = 0
        while y < plate.maxY {
            var x = plate.minX + pitch * (row.isMultiple(of: 2) ? 1 : 1.5)
            while x < plate.maxX {
                path.addEllipse(in: CGRect(x: x - radius, y: y - radius,
                                           width: radius * 2, height: radius * 2))
                x += pitch
            }
            y += pitch
            row += 1
        }
        context.setFillColor(NSColor.white.withAlphaComponent(0.06).cgColor)
        context.addPath(path)
        context.fillPath()
    }

    /// The wordmark: the app's name in the app's own face, blooming the way lit dots do.
    /// Drawn on two lines ("Few" / "Note") so the name stays legible at small sizes.
    static func drawWordmark(in context: CGContext, plate: CGRect) {
        let lines = plate.width >= 110 ? ["Few", "Note"] : ["F"]
        let maxColumns = lines.map { $0.count * (GlyphFont.columns + 1) - 1 }.max() ?? 1
        let gapRows = 1
        let totalRows = lines.count * (GlyphFont.rows - 1) + (lines.count - 1) * gapRows

        let pitch = min(plate.width * 0.78 / CGFloat(maxColumns),
                        plate.height * 0.72 / CGFloat(totalRows))
        let lineSpan = CGFloat(GlyphFont.rows - 1) * pitch
        let totalHeight = CGFloat(totalRows) * pitch
        let topOriginY = plate.midY - totalHeight / 2
        let radius = pitch * 0.42

        let dots = CGMutablePath()
        for (lineIndex, word) in lines.enumerated() {
            let characters = Array(word)
            let columnsAcross = characters.count * (GlyphFont.columns + 1) - 1
            let lineTop = topOriginY + CGFloat(lines.count - 1 - lineIndex)
                          * (lineSpan + CGFloat(gapRows) * pitch)
            let penBase = plate.midX - CGFloat(columnsAcross) * pitch / 2
            for (index, character) in characters.enumerated() {
                let pen = penBase + CGFloat(index * (GlyphFont.columns + 1)) * pitch
                for dot in GlyphFont.litDots(for: character) {
                    let centre = CGPoint(x: pen + (CGFloat(dot.column) + 0.5) * pitch,
                                         y: lineTop + (CGFloat(GlyphFont.rows - 1 - dot.row) + 0.5) * pitch)
                    dots.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                               width: radius * 2, height: radius * 2))
                }
            }
        }

        let ink = NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1).cgColor
        context.setFillColor(ink)
        // A tight pass right at the strokes, then a wide faint one: the app's own bloom.
        for (blur, alpha) in [(pitch * 1.3, 0.62), (pitch * 3.6, 0.38)] {
            context.setShadow(offset: .zero, blur: blur,
                              color: NSColor.white.withAlphaComponent(CGFloat(alpha)).cgColor)
            context.addPath(dots)
            context.fillPath()
        }
    }

    // MARK: - Shell

    static func run(_ launchPath: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure("\(launchPath) failed with status \(process.terminationStatus)")
        }
    }
}
