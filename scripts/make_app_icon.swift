import Foundation
import AppKit
import CoreGraphics

func makeAppIcons(sourcePath: String, outputDir: String) throws {
    let sourceURL = URL(fileURLWithPath: sourcePath)
    guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        fatalError("Failed to load source image at \(sourcePath)")
    }

    let fileManager = FileManager.default
    try fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

    let specs: [(size: String, scale: String, px: Int, filename: String)] = [
        ("16x16", "1x", 16, "icon_16x16.png"),
        ("16x16", "2x", 32, "icon_16x16@2x.png"),
        ("32x32", "1x", 32, "icon_32x32.png"),
        ("32x32", "2x", 64, "icon_32x32@2x.png"),
        ("128x128", "1x", 128, "icon_128x128.png"),
        ("128x128", "2x", 256, "icon_128x128@2x.png"),
        ("256x256", "1x", 256, "icon_256x256.png"),
        ("256x256", "2x", 512, "icon_256x256@2x.png"),
        ("512x512", "1x", 512, "icon_512x512.png"),
        ("512x512", "2x", 1024, "icon_512x512@2x.png")
    ]

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    for spec in specs {
        let px = spec.px
        let bodySize = Double(px) * (824.0 / 1024.0)
        let offset = (Double(px) - bodySize) / 2.0
        let cornerRadius = bodySize * (185.4 / 824.0)

        guard let context = CGContext(
            data: nil,
            width: px,
            height: px,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("Failed to create CGContext for size \(px)")
        }

        context.interpolationQuality = .high
        context.clear(CGRect(x: 0, y: 0, width: px, height: px))

        // macOS standard rounded rectangle
        let bodyRect = CGRect(x: offset, y: offset, width: bodySize, height: bodySize)
        let clipPath = CGPath(
            roundedRect: bodyRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )

        context.saveGState()
        context.addPath(clipPath)
        context.clip()

        // Draw original logo into squircle
        context.draw(cgImage, in: bodyRect)
        context.restoreGState()

        guard let outputCGImage = context.makeImage() else {
            fatalError("Failed to make CGImage for \(spec.filename)")
        }

        let outURL = URL(fileURLWithPath: outputDir).appendingPathComponent(spec.filename)
        guard let destination = CGImageDestinationCreateWithURL(outURL as CFURL, "public.png" as CFString, 1, nil) else {
            fatalError("Failed to create destination for \(outURL)")
        }
        CGImageDestinationAddImage(destination, outputCGImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            fatalError("Failed to finalize image destination for \(outURL)")
        }
        print("Generated: \(spec.filename) (\(px)x\(px))")
    }

    // Write Contents.json
    var imagesArray: [[String: String]] = []
    for spec in specs {
        imagesArray.append([
            "size": spec.size,
            "idiom": "mac",
            "scale": spec.scale,
            "filename": spec.filename
        ])
    }

    let contents: [String: Any] = [
        "images": imagesArray,
        "info": [
            "version": 1,
            "author": "xcode"
        ]
    ]

    let jsonData = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    let contentsURL = URL(fileURLWithPath: outputDir).appendingPathComponent("Contents.json")
    try jsonData.write(to: contentsURL)
    print("Generated Contents.json in \(outputDir)")
}

let args = CommandLine.arguments
let source = args.count > 1 ? args[1] : "magnific__design-a-minimalist-japaneseinspired-logo-for-a-ma__78247.png"
let dest = args.count > 2 ? args[2] : "App/Resources/Assets.xcassets/AppIcon.appiconset"

try makeAppIcons(sourcePath: source, outputDir: dest)
