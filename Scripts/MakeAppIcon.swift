import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Resize the approved master mechanically; do not add borders, masks, or decorative effects.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let arguments = Array(CommandLine.arguments.dropFirst())
let output =
  arguments.first.map { URL(fileURLWithPath: $0) }
  ?? root.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
let master =
  arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
  ?? root.appendingPathComponent("Design/AppIcon/aether-atlas-master.png")

enum IconError: Error {
  case unreadableMaster, nonSquareMaster, renderingFailed, encodingFailed
}

guard let source = CGImageSourceCreateWithURL(master as CFURL, nil),
  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else { throw IconError.unreadableMaster }
guard image.width == image.height else { throw IconError.nonSquareMaster }
guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
  throw IconError.renderingFailed
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for size in [16, 32, 64, 128, 256, 512, 1024] {
  guard
    let context = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { throw IconError.renderingFailed }
  context.interpolationQuality = .high
  context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
  let file = output.appendingPathComponent("icon-\(size).png")
  guard let scaled = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
      file as CFURL, UTType.png.identifier as CFString, 1, nil)
  else { throw IconError.encodingFailed }
  CGImageDestinationAddImage(destination, scaled, nil)
  guard CGImageDestinationFinalize(destination) else { throw IconError.encodingFailed }
}

let entries: [[String: Any]] = [16, 32, 128, 256, 512].flatMap { point -> [[String: Any]] in
  [1, 2].map { scale in
    [
      "idiom": "mac", "size": "\(point)x\(point)", "scale": "\(scale)x",
      "filename": "icon-\(point * scale).png",
    ]
  }
}
let json: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(
  to: output.appendingPathComponent("Contents.json"))
print("Generated all macOS icon sizes from \(master.path)")
