import AppKit
import ImageIO
import UniformTypeIdentifiers

func failure(_ message: String) -> NSError {
    NSError(domain: "HUDson.Icon", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message])
}

func render(_ image: NSImage, pixels: Int, to destination: URL) throws {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: pixels, height: pixels,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw failure("Cannot create a \(pixels)px drawing context")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
               from: .zero, operation: .copy, fraction: 1,
               respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
    NSGraphicsContext.restoreGraphicsState()
    guard let rendered = context.makeImage(),
          let output = CGImageDestinationCreateWithURL(destination as CFURL,
                                                       UTType.png.identifier as CFString, 1, nil) else {
        throw failure("Cannot encode \(destination.path)")
    }
    CGImageDestinationAddImage(output, rendered, nil)
    guard CGImageDestinationFinalize(output) else {
        throw failure("Cannot write \(destination.path)")
    }
}

if CommandLine.arguments.dropFirst().first == "--png" {
    guard CommandLine.arguments.count == 5,
          let pixels = Int(CommandLine.arguments[4]), (1...4096).contains(pixels),
          let image = NSImage(contentsOfFile: CommandLine.arguments[2]) else {
        fputs("Usage: swift scripts/render-icon.swift --png <SVG> <PNG> <pixels: 1...4096>\n", stderr)
        exit(1)
    }
    let destination = URL(fileURLWithPath: CommandLine.arguments[3])
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
    try render(image, pixels: pixels, to: destination)
    print("Rendered \(destination.path)")
    exit(0)
}

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift scripts/render-icon.swift <output-directory>\n", stderr)
    exit(1)
}

let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = project.appendingPathComponent("Resources", isDirectory: true)
// Each icon has its own hand-edited source; neither is generated from the other.
let statusURL = resources.appendingPathComponent("StatusIcon.svg")
let appURL = resources.appendingPathComponent("AppIcon.svg")
guard let appImage = NSImage(contentsOf: appURL),
      let statusImage = NSImage(contentsOf: statusURL) else {
    throw failure("AppKit could not decode the SVG assets")
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = outputDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for density in [1, 2] {
        let suffix = density == 2 ? "@2x" : ""
        let filename = "icon_\(points)x\(points)\(suffix).png"
        try render(appImage, pixels: points * density, to: iconset.appendingPathComponent(filename))
    }
}
let master = outputDirectory.appendingPathComponent("AppIcon-1024.png")
try Data(contentsOf: iconset.appendingPathComponent("icon_512x512@2x.png")).write(to: master)
for density in [1, 2] {
    let suffix = density == 2 ? "@2x" : ""
    try render(statusImage, pixels: 18 * density,
               to: outputDirectory.appendingPathComponent("StatusIcon\(suffix).png"))
}
print("Rendered \(master.path), all 10 iconset sizes, and menu-bar previews")
