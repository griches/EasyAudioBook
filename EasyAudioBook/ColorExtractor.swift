import UIKit
import SwiftUI

enum ColorExtractor {
    /// Extract two contrasting colours from an image for use as a gradient.
    /// Returns (darker colour, lighter colour).
    static func gradientColors(from image: UIImage) -> (Color, Color) {
        guard let cgImage = image.cgImage else {
            return (Color(red: 0.05, green: 0.05, blue: 0.1), .black)
        }

        let width = 20
        let height = 20
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (Color(red: 0.05, green: 0.05, blue: 0.1), .black)
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Collect colour buckets from different regions
        var topColors: (r: CGFloat, g: CGFloat, b: CGFloat) = (0, 0, 0)
        var bottomColors: (r: CGFloat, g: CGFloat, b: CGFloat) = (0, 0, 0)
        var topCount: CGFloat = 0
        var bottomCount: CGFloat = 0

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let r = CGFloat(pixelData[offset]) / 255.0
                let g = CGFloat(pixelData[offset + 1]) / 255.0
                let b = CGFloat(pixelData[offset + 2]) / 255.0

                // Skip very dark pixels (near black)
                let brightness = (r + g + b) / 3.0
                if brightness < 0.05 { continue }

                if y < height / 2 {
                    topColors.r += r
                    topColors.g += g
                    topColors.b += b
                    topCount += 1
                } else {
                    bottomColors.r += r
                    bottomColors.g += g
                    bottomColors.b += b
                    bottomCount += 1
                }
            }
        }

        // Average and darken for background use
        let darken: CGFloat = 0.3

        let c1: Color
        if topCount > 0 {
            c1 = Color(
                red: (topColors.r / topCount) * darken,
                green: (topColors.g / topCount) * darken,
                blue: (topColors.b / topCount) * darken
            )
        } else {
            c1 = Color(red: 0.05, green: 0.05, blue: 0.1)
        }

        let c2: Color
        if bottomCount > 0 {
            c2 = Color(
                red: (bottomColors.r / bottomCount) * darken,
                green: (bottomColors.g / bottomCount) * darken,
                blue: (bottomColors.b / bottomCount) * darken
            )
        } else {
            c2 = .black
        }

        return (c1, c2)
    }
}
