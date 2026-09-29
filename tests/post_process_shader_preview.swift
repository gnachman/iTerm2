// Renders a fake terminal frame through a post-processing shader, offscreen, and
// writes PNGs. Handy for developing a shader without running iTerm2.
//
// Usage (from the repo root):
//   swift tests/post_process_shader_preview.swift <shader.metalsrc|shader.metal> <output-dir> [time ...]
//
// The shader is compiled the same way iTerm2 does it: after
// OtherResources/iTermPostProcessPrelude.metalsrc.
//
// Set PREVIEW_BG_ALPHA (e.g. 0.4) to give the fake terminal a transparent
// background; results are then composited over a fake blurred desktop.

import AppKit
import Metal
import MetalKit

struct Uniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var scale: Float
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    fail("Usage: \(args[0]) <shader> <output-dir> [time ...]")
}
let shaderPath = args[1]
let outputDir = URL(fileURLWithPath: args[2])
let times = args.count > 3 ? args[3...].compactMap { Float($0) } : [0.5, 2.0, 3.5, 20.1]

let width = 1600
let height = 900
let scale: Float = 2
let backgroundAlpha = CGFloat(Double(ProcessInfo.processInfo.environment["PREVIEW_BG_ALPHA"] ?? "") ?? 1)

// Draw something terminal-like.
func makeTerminalImage() -> CGImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil,
                            width: width,
                            height: height,
                            bitsPerComponent: 8,
                            bytesPerRow: 0,
                            space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    context.setFillColor(NSColor(srgbRed: 0.11, green: 0.08, blue: 0.03, alpha: backgroundAlpha).cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let lines: [(String, NSColor)] = [
        ("moimart@minipro ~/code/iTerm2 % ls -la", .init(srgbRed: 1.0, green: 0.69, blue: 0.10, alpha: 1)),
        ("drwxr-xr-x  42 moimart  staff   1344 Sep 23 11:00 .", .init(srgbRed: 0.9, green: 0.9, blue: 0.9, alpha: 1)),
        ("drwxr-xr-x  17 moimart  staff    544 Sep 23 10:58 ..", .init(srgbRed: 0.9, green: 0.9, blue: 0.9, alpha: 1)),
        ("-rw-r--r--   1 moimart  staff  35147 Sep 23 11:00 COPYING", .init(srgbRed: 0.9, green: 0.9, blue: 0.9, alpha: 1)),
        ("-rw-r--r--   1 moimart  staff  25630 Sep 23 11:00 Makefile", .init(srgbRed: 0.9, green: 0.9, blue: 0.9, alpha: 1)),
        ("drwxr-xr-x 212 moimart  staff   6784 Sep 23 11:00 sources", .init(srgbRed: 0.40, green: 0.65, blue: 1.0, alpha: 1)),
        ("drwxr-xr-x  31 moimart  staff    992 Sep 23 11:00 tools", .init(srgbRed: 0.40, green: 0.65, blue: 1.0, alpha: 1)),
        ("moimart@minipro ~/code/iTerm2 % make Development", .init(srgbRed: 1.0, green: 0.69, blue: 0.10, alpha: 1)),
        ("** BUILD SUCCEEDED **", .init(srgbRed: 0.45, green: 0.95, blue: 0.45, alpha: 1)),
        ("moimart@minipro ~/code/iTerm2 % █", .init(srgbRed: 1.0, green: 0.69, blue: 0.10, alpha: 1)),
    ]
    let font = NSFont.monospacedSystemFont(ofSize: 30, weight: .regular)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    for (i, (text, color)) in lines.enumerated() {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        string.draw(at: NSPoint(x: 40, y: CGFloat(height) - 80 - CGFloat(i) * 44))
    }
    NSGraphicsContext.current = nil
    return context.makeImage()!
}

// Soft colored blobs, standing in for a blurred desktop behind a transparent window.
func makeDesktopImage() -> CGImage {
    let context = CGContext(data: nil,
                            width: width,
                            height: height,
                            bitsPerComponent: 8,
                            bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    let colors = [NSColor(srgbRed: 0.10, green: 0.20, blue: 0.45, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.45, green: 0.15, blue: 0.40, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: nil)!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
    let blobs: [(CGFloat, CGFloat, CGFloat, NSColor)] = [
        (0.2, 0.3, 380, NSColor(srgbRed: 0.95, green: 0.55, blue: 0.20, alpha: 0.8)),
        (0.75, 0.7, 420, NSColor(srgbRed: 0.20, green: 0.80, blue: 0.75, alpha: 0.7)),
        (0.6, 0.2, 300, NSColor(srgbRed: 0.90, green: 0.30, blue: 0.50, alpha: 0.7)),
    ]
    for (x, y, r, color) in blobs {
        let blob = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
                              locations: nil)!
        let center = CGPoint(x: x * CGFloat(width), y: y * CGFloat(height))
        context.drawRadialGradient(blob, startCenter: center, startRadius: 0, endCenter: center, endRadius: r, options: [])
    }
    return context.makeImage()!
}

func writePNG(texture: MTLTexture, to url: URL) {
    let bytesPerRow = width * 4
    var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
    texture.getBytes(&bytes, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let image = CGImage(width: width,
                        height: height,
                        bitsPerComponent: 8,
                        bitsPerPixel: 32,
                        bytesPerRow: bytesPerRow,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                        provider: provider,
                        decode: nil,
                        shouldInterpolate: false,
                        intent: .defaultIntent)!
    var output = image
    if backgroundAlpha < 1 {
        let context = CGContext(data: nil,
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(makeDesktopImage(), in: rect)
        context.draw(image, in: rect)
        output = context.makeImage()!
    }
    let rep = NSBitmapImageRep(cgImage: output)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

guard let device = MTLCreateSystemDefaultDevice() else {
    fail("No Metal device")
}
let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let preludeURL = repoRoot.appendingPathComponent("OtherResources/iTermPostProcessPrelude.metalsrc")
guard let prelude = try? String(contentsOf: preludeURL, encoding: .utf8),
      let body = try? String(contentsOfFile: shaderPath, encoding: .utf8) else {
    fail("Could not read \(preludeURL.path) or \(shaderPath)")
}

let library: MTLLibrary
do {
    library = try device.makeLibrary(source: prelude + "\n#line 1\n" + body, options: nil)
} catch {
    fail("Compile failed:\n\(error)")
}
let descriptor = MTLRenderPipelineDescriptor()
descriptor.vertexFunction = library.makeFunction(name: "iTermPostProcessVertexShader")
descriptor.fragmentFunction = library.makeFunction(name: "iTermPostProcessFragmentShader")
descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
let pipeline = try! device.makeRenderPipelineState(descriptor: descriptor)

let source = try! MTKTextureLoader(device: device).newTexture(cgImage: makeTerminalImage(),
                                                               options: [.SRGB: false])
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
let queue = device.makeCommandQueue()!

writePNG(texture: source, to: outputDir.appendingPathComponent("source.png"))
for time in times {
    let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                    width: width,
                                                                    height: height,
                                                                    mipmapped: false)
    targetDescriptor.usage = [.renderTarget, .shaderRead]
    targetDescriptor.storageMode = .shared
    let target = device.makeTexture(descriptor: targetDescriptor)!
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = target
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    let commandBuffer = queue.makeCommandBuffer()!
    let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)!
    encoder.setRenderPipelineState(pipeline)
    var uniforms = Uniforms(resolution: SIMD2(Float(width), Float(height)), time: time, scale: scale)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    encoder.setFragmentTexture(source, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    let url = outputDir.appendingPathComponent(String(format: "t%06.2f.png", time))
    writePNG(texture: target, to: url)
    print("Wrote \(url.path)")
}
