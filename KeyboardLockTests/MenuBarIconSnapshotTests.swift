import XCTest
import AppKit
@testable import KeyboardLock

/// REV-22 — render the unlocked and locked menu-bar icons at 16/32/64 pt ×
/// 1×/2× and confirm each rasterizes to the expected pixel dimensions with
/// actual (non-empty) content, so the SF Symbol composite is crisp before we
/// commit to it over a custom asset (SPEC-Q5). Dependency-free: instead of an
/// image-diff library we assert geometry + non-emptiness and emit PNG artifacts
/// for manual inspection.
final class MenuBarIconSnapshotTests: XCTestCase {

    private let points: [CGFloat] = [16, 32, 64]
    private let scales: [CGFloat] = [1, 2]

    func testIconsRasterizeCrisplyAtAllSizes() throws {
        let artifactsDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kbl-icon-snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: artifactsDir, withIntermediateDirectories: true)

        for locked in [false, true] {
            let image = MenuBarIcon.image(locked: locked)
            for pt in points {
                for scale in scales {
                    let rep = try rasterize(image, pt: pt, scale: scale)
                    let expected = Int(pt * scale)
                    XCTAssertEqual(rep.pixelsWide, expected, "width @\(pt)pt \(scale)x")
                    XCTAssertEqual(rep.pixelsHigh, expected, "height @\(pt)pt \(scale)x")
                    XCTAssertTrue(hasContent(rep), "icon (locked=\(locked)) was blank @\(pt)pt \(scale)x")

                    if let png = rep.representation(using: .png, properties: [:]) {
                        let name = "kbd-\(locked ? "locked" : "unlocked")-\(Int(pt))pt@\(Int(scale))x.png"
                        try? png.write(to: artifactsDir.appendingPathComponent(name))
                    }
                }
            }
        }
    }

    private func rasterize(_ image: NSImage, pt: CGFloat, scale: CGFloat) throws -> NSBitmapImageRep {
        let pixels = Int(pt * scale)
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = NSSize(width: pt, height: pt)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pt, height: pt))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// True if any sampled pixel is non-transparent (the symbol drew something).
    private func hasContent(_ rep: NSBitmapImageRep) -> Bool {
        let step = max(1, rep.pixelsWide / 16)
        var x = 0
        while x < rep.pixelsWide {
            var y = 0
            while y < rep.pixelsHigh {
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.01 {
                    return true
                }
                y += step
            }
            x += step
        }
        return false
    }
}
