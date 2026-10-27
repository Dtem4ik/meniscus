import AppKit
import CoreImage
import SwiftUI

/// The artwork's average color, brightened enough to read on the black island. Computed once per
/// artwork, on the GPU.
nonisolated enum ArtworkTint {
    // CIContext is thread-safe and expensive to create, so one is shared.
    nonisolated(unsafe) private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func color(of image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input,
            kCIInputExtentKey: CIVector(cgRect: input.extent),
        ]), let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: output.extent, format: .RGBA8, colorSpace: nil)
        let average = NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
        return legible(average)
    }

    /// Keeps the hue, lifts dark colors so they stand out on black.
    static func legible(_ color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return color }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: min(saturation, 0.85), brightness: max(brightness, 0.8), alpha: 1)
    }
}
