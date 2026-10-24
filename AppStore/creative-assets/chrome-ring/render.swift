import Foundation
import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

// Offline video renderer; never linked into the app. Keeps the approved
// artwork fixed while animating its existing warm/cool light and reflections.
guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: render BASE.png OUTPUT.mp4")
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard !FileManager.default.fileExists(atPath: outputURL.path) else {
    fatalError("Output already exists; use a new filename")
}
let width = 3840, height = 1646, fps: Int32 = 30, seconds = 8
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CIContext(options: [.workingColorSpace: colorSpace,
                                  .outputColorSpace: colorSpace,
                                  .cacheIntermediates: false])
let source = CIImage(contentsOf: sourceURL, options: [.colorSpace: colorSpace])!
let base = source.transformed(by: CGAffineTransform(
    scaleX: CGFloat(width) / source.extent.width,
    y: CGFloat(height) / source.extent.height))
let bounds = CGRect(x: 0, y: 0, width: width, height: height)
let kernel = CIColorKernel(source: """
kernel vec4 ringLight(__sample pixel, vec2 canvas, float time) {
    vec2 uv = destCoord() / canvas;
    vec2 p = (uv - vec2(0.500, 0.549)) / vec2(0.150, 0.339);
    float radius = length(p);
    float angle = mod(1.5707963 - atan(p.y, p.x) + 6.2831853, 6.2831853);
    float quarter = floor(angle / 1.5707963);
    float cycle = time * 0.7853981634;
    float work = pow(max(0.0, cos(cycle - quarter * 1.5707963)), 6.0);
    float port = mod(floor((angle + 0.7853981634) / 1.5707963), 4.0);
    float recovery = pow(max(0.0, cos(cycle - (port - 0.5) * 1.5707963)), 8.0);
    float ring = smoothstep(0.78, 0.90, radius) * (1.0 - smoothstep(1.19, 1.32, radius));
    float warm = smoothstep(0.035, 0.24, pixel.r - pixel.g)
               * smoothstep(0.10, 0.32, pixel.r - pixel.b);
    float cool = smoothstep(0.035, 0.20, pixel.g - pixel.r)
               * smoothstep(0.025, 0.18, pixel.g - pixel.b * 0.85);
    float floorArea = 1.0 - smoothstep(0.13, 0.20, uv.y);
    float floorWarm = 0.76 + 0.12 * cos(cycle * 2.0);
    float floorCool = 0.78 + 0.15 * cos(cycle - 3.14159265);
    float gain = 1.0 + ring * warm * ((0.36 + 0.76 * work) - 1.0)
                     + ring * cool * ((0.43 + 0.69 * recovery) - 1.0)
                     + floorArea * warm * (floorWarm - 1.0)
                     + floorArea * cool * (floorCool - 1.0);
    // A faint moving highlight follows the metal, without moving the object.
    float delta = atan(sin(angle - cycle), cos(angle - cycle));
    float glint = exp(-delta * delta / 0.018)
                * exp(-pow((radius - 1.14) / 0.045, 2.0)) * 0.035;
    vec3 rgb = pixel.rgb * gain + vec3(0.83, 0.88, 1.0) * glint;
    return vec4(clamp(rgb, 0.0, 1.0), 1.0);
}
""")!

func image(at time: Double) -> CIImage {
    kernel.apply(extent: bounds, arguments: [base,
        CIVector(x: CGFloat(width), y: CGFloat(height)), time])!
}

let qa = outputURL.deletingLastPathComponent().appendingPathComponent("qa", isDirectory: true)
try FileManager.default.createDirectory(at: qa, withIntermediateDirectories: true)
for time in [0.0, 1.0 / 30, 2.0, 4.0, 6.0, 8.0 - 1.0 / 30, 8.0] {
    let cg = context.createCGImage(image(at: time), from: bounds,
                                    format: .RGBA8, colorSpace: colorSpace)!
    let name = String(format: "frame-%06.3f.png", time)
    let destination = CGImageDestinationCreateWithURL(qa.appendingPathComponent(name) as CFURL,
        UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, cg, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write QA frame") }
}

let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width, AVVideoHeightKey: height,
    AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                               AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                               AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 18_000_000,
                                     AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                     AVVideoMaxKeyFrameIntervalKey: 30]
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
    sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                 kCVPixelBufferWidthKey as String: width,
                                 kCVPixelBufferHeightKey as String: height,
                                 kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
writer.add(input)
writer.shouldOptimizeForNetworkUse = true
guard writer.startWriting() else { throw writer.error! }
writer.startSession(atSourceTime: .zero)
for frame in 0..<(seconds * Int(fps)) {
    while !input.isReadyForMoreMediaData {
        if writer.status == .failed { throw writer.error! }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    try autoreleasepool {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer) == kCVReturnSuccess,
              let buffer else { fatalError("Pixel buffer allocation failed") }
        context.render(image(at: Double(frame) / Double(fps)), to: buffer,
                       bounds: bounds, colorSpace: colorSpace)
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps)) else {
            throw writer.error ?? NSError(domain: "Render", code: 1)
        }
    }
    if frame % 30 == 0 { print("Rendered \(frame)/240 frames"); fflush(stdout) }
}
writer.endSession(atSourceTime: CMTime(value: Int64(seconds), timescale: 1))
input.markAsFinished()
await writer.finishWriting()
guard writer.status == .completed else { throw writer.error! }
print("Completed 8-second seamless header, 3840×1646, 30 fps, H.264, no audio")
