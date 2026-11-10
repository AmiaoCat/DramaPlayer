import AVFoundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

private let width = 360
private let height = 640
private let fps: Int32 = 24
private let duration = 8
private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

private struct Scene {
    let slug: String
    let title: String
    let accent: CGColor
    let shadow: CGColor
}

private let scenes = [
    Scene(slug: "01", title: "AFTERGLOW",
          accent: CGColor(red: 0.97, green: 0.60, blue: 0.33, alpha: 1),
          shadow: CGColor(red: 0.19, green: 0.07, blue: 0.15, alpha: 1)),
    Scene(slug: "02", title: "DEEP WATER",
          accent: CGColor(red: 0.34, green: 0.86, blue: 0.76, alpha: 1),
          shadow: CGColor(red: 0.02, green: 0.18, blue: 0.24, alpha: 1)),
    Scene(slug: "03", title: "BLUE HOUR",
          accent: CGColor(red: 0.70, green: 0.66, blue: 0.99, alpha: 1),
          shadow: CGColor(red: 0.11, green: 0.10, blue: 0.25, alpha: 1))
]

private func caption(_ value: String, at point: CGPoint, size: CGFloat, color: CGColor,
                     font: String = "Menlo-Regular", in context: CGContext) {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(font as CFString, size, nil),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
    ]))
    context.textPosition = point
    CTLineDraw(line, context)
}

private func draw(_ scene: Scene, frame: Int, in context: CGContext) {
    let canvas = CGRect(x: 0, y: 0, width: width, height: height)
    let progress = CGFloat(frame) / CGFloat(duration * Int(fps))
    let phase = progress * .pi * 2
    let center = CGPoint(x: 180 + sin(phase) * 55, y: 350 + cos(phase) * 34)
    let black = CGColor(red: 0.025, green: 0.035, blue: 0.055, alpha: 1)
    let gradient = CGGradient(colorsSpace: colorSpace, colors: [scene.shadow, black] as CFArray, locations: nil)!
    context.fill(canvas)
    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: 360, options: [.drawsAfterEndLocation])
    for ring in 0..<7 {
        let radius = CGFloat(40 + ring * 17) + sin(phase + CGFloat(ring) * 0.4) * 9
        context.setStrokeColor(scene.accent.copy(alpha: 0.15 + Double(6 - ring) * 0.035)!)
        context.setLineWidth(ring == 0 ? 2 : 1)
        context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                         width: 2 * radius, height: 2 * radius))
    }
    context.setFillColor(scene.accent)
    context.fillEllipse(in: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
    caption("DRAMA PLAYER / MOTION STUDIES", at: CGPoint(x: 24, y: 574),
            size: 10, color: scene.accent, in: context)
    caption(scene.slug, at: CGPoint(x: 21, y: 162), size: 62,
            color: scene.accent, font: "HelveticaNeue-Bold", in: context)
    caption(scene.title, at: CGPoint(x: 24, y: 121), size: 26,
            color: CGColor(gray: 1, alpha: 0.92), font: "HelveticaNeue-Bold", in: context)
    caption(String(format: "%05.2f / %02d SEC", Double(frame) / Double(fps), duration),
            at: CGPoint(x: 24, y: 91), size: 11, color: scene.accent, in: context)
    context.setFillColor(scene.accent.copy(alpha: 0.3)!)
    context.fill(CGRect(x: 24, y: 73, width: 312, height: 2))
    context.setFillColor(scene.accent)
    context.fill(CGRect(x: 24, y: 73, width: 312 * progress, height: 2))
}

private func makeClip(_ scene: Scene, in directory: URL) async throws {
    let movie = directory.appendingPathComponent("\(scene.slug).mp4")
    let poster = directory.appendingPathComponent("\(scene.slug).jpg")
    if FileManager.default.fileExists(atPath: movie.path) { try FileManager.default.removeItem(at: movie) }
    let writer = try AVAssetWriter(outputURL: movie, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 350_000]
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
    ])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    writer.startSession(atSourceTime: .zero)
    guard let pool = adaptor.pixelBufferPool else { throw CocoaError(.fileWriteUnknown) }

    for frame in 0..<(duration * Int(fps)) {
        while !input.isReadyForMoreMediaData {
            if let error = writer.error { throw error }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { throw CocoaError(.fileWriteUnknown) }
        try render(scene, frame: frame, into: buffer, poster: poster)
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps)) else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
    }
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
}

private func render(_ scene: Scene, frame: Int, into buffer: CVPixelBuffer, poster: URL) throws {
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
    guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: colorSpace, bitmapInfo: bitmapInfo) else {
        throw CocoaError(.fileWriteUnknown)
    }
    draw(scene, frame: frame, in: context)
    guard frame == 0 else { return }
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(poster as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for scene in scenes { try await makeClip(scene, in: output) }
