import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: swift Scripts/render_preview_background.swift OUTPUT.png\n".utf8))
    exit(2)
}

let width = 1600
let height = 900
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let canvas = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil)!
}

func ridge(_ points: [CGPoint], fill: CGColor) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: 0))
    for point in points {
        path.addLine(to: point)
    }
    path.addLine(to: CGPoint(x: width, y: 0))
    path.closeSubpath()
    canvas.addPath(path)
    canvas.setFillColor(fill)
    canvas.fillPath()
}

canvas.drawLinearGradient(
    gradient([color(0.94, 0.73, 0.57), color(0.34, 0.59, 0.72), color(0.08, 0.17, 0.34)]),
    start: CGPoint(x: 800, y: 180), end: CGPoint(x: 800, y: height),
    options: [.drawsBeforeStartLocation]
)

let light = CGPoint(x: 1140, y: 540)
canvas.drawRadialGradient(
    gradient([color(1, 0.88, 0.63, alpha: 0.85), color(1, 0.88, 0.63, alpha: 0)]),
    startCenter: light, startRadius: 0, endCenter: light, endRadius: 250, options: []
)

ridge([
    CGPoint(x: 0, y: 440), CGPoint(x: 180, y: 525), CGPoint(x: 290, y: 490),
    CGPoint(x: 470, y: 690), CGPoint(x: 660, y: 545), CGPoint(x: 760, y: 580),
    CGPoint(x: 1010, y: 424), CGPoint(x: 1240, y: 590), CGPoint(x: 1600, y: 455)
], fill: color(0.27, 0.43, 0.54))
ridge([
    CGPoint(x: 0, y: 564), CGPoint(x: 176, y: 489), CGPoint(x: 298, y: 505),
    CGPoint(x: 450, y: 402), CGPoint(x: 730, y: 352), CGPoint(x: 945, y: 407),
    CGPoint(x: 1160, y: 489), CGPoint(x: 1420, y: 378), CGPoint(x: 1600, y: 457)
], fill: color(0.10, 0.25, 0.34))

canvas.saveGState()
canvas.clip(to: CGRect(x: 0, y: 0, width: width, height: 330))
canvas.drawLinearGradient(
    gradient([color(0.05, 0.16, 0.29), color(0.10, 0.34, 0.45), color(0.25, 0.49, 0.52)]),
    start: CGPoint(x: 800, y: 0), end: CGPoint(x: 800, y: 330), options: []
)
for index in 0..<16 {
    let y = CGFloat(27 + index * 19)
    let start = CGFloat((index * 257) % 1350)
    let length = CGFloat(110 + (index * 43) % 250)
    canvas.setStrokeColor(color(0.75, 0.84, 0.82, alpha: 0.15))
    canvas.setLineWidth(1.6)
    canvas.move(to: CGPoint(x: start, y: y))
    canvas.addLine(to: CGPoint(x: start + length, y: y))
    canvas.strokePath()
}
canvas.restoreGState()

let output = URL(fileURLWithPath: CommandLine.arguments[1])
guard let image = canvas.makeImage(),
      let writer = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Could not create the preview image at \(output.path)")
}
CGImageDestinationAddImage(writer, image, nil)
guard CGImageDestinationFinalize(writer) else {
    fatalError("Could not write the preview image at \(output.path)")
}
