//
//  iTermPostProcessRenderer.swift
//  iTerm2SharedARC
//
//  Applies a full-view fragment shader (for example, a CRT effect) to the
//  finished terminal frame as it is copied to the drawable.
//
//  The shader is chosen per profile (KEY_POST_PROCESSING_SHADER). It is either
//  the name of a built-in shader (a .metalsrc file in the app bundle) or the
//  path to a user-provided file. Both are compiled at runtime after
//  iTermPostProcessPrelude.metalsrc, which defines the entry points, uniforms,
//  and some GLSL compatibility shims. User files are recompiled when they
//  change.
//

import Foundation
import Metal

// Must match iTermPostProcessUniforms in iTermPostProcessPrelude.metalsrc.
private struct PostProcessUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var scale: Float
}

@objc(iTermPostProcessPipeline)
class PostProcessPipeline: NSObject {
    private let pipelineState: MTLRenderPipelineState

    init(pipelineState: MTLRenderPipelineState) {
        self.pipelineState = pipelineState
    }

    // Seconds since the epoch, wrapped to keep float precision. The period is a
    // multiple of any sensible animation cycle, and using wall clock time keeps
    // every window in phase.
    private static var time: Float {
        return Float(fmod(Date().timeIntervalSince1970, 3600))
    }

    // Draws sourceTexture into the encoder's render target through the shader.
    @objc(drawWithEncoder:sourceTexture:scale:)
    func draw(encoder: MTLRenderCommandEncoder,
              sourceTexture: MTLTexture,
              scale: CGFloat) {
        encoder.setRenderPipelineState(pipelineState)
        var uniforms = PostProcessUniforms(
            resolution: SIMD2<Float>(Float(sourceTexture.width), Float(sourceTexture.height)),
            time: Self.time,
            scale: Float(scale))
        encoder.setFragmentBytes(&uniforms,
                                 length: MemoryLayout<PostProcessUniforms>.stride,
                                 index: 0)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}

// Compiles and caches post-processing pipelines. Main thread only.
@objc(iTermPostProcessShaderCache)
class PostProcessShaderCache: NSObject {
    @objc static let instance = PostProcessShaderCache()

    private struct Key: Hashable {
        var deviceID: UInt64
        var pixelFormat: UInt
        var spec: String
        var modificationDate: Date?
    }

    private struct FileCheck {
        var path: String
        var checkedAt: TimeInterval
        var modificationDate: Date?
    }

    // A nil value records a failed compile so it isn't retried every frame.
    private var pipelines = [Key: PostProcessPipeline?]()
    private var libraries = [Key: MTLLibrary?]()
    private var fileChecks = [String: FileCheck]()
    private static let builtInExtension = "metalsrc"

    // Frames per second to redraw at while a shader is active. Zero means
    // only redraw when the terminal changes.
    @objc var frameRate: Double {
        return max(0, iTermAdvancedSettingsModel.postProcessingShaderFrameRate())
    }

    // Returns nil if shader is empty or fails to compile.
    @objc(pipelineForShader:device:pixelFormat:)
    func pipeline(shader: String?, device: MTLDevice, pixelFormat: MTLPixelFormat) -> PostProcessPipeline? {
        guard let spec = shader?.trimmingCharacters(in: .whitespacesAndNewlines), !spec.isEmpty else {
            return nil
        }
        let path = self.path(for: spec)
        let key = Key(deviceID: device.registryID,
                      pixelFormat: pixelFormat.rawValue,
                      spec: spec,
                      modificationDate: path.flatMap { modificationDate(of: $0) })
        if let cached = pipelines[key] {
            return cached
        }
        // Entries for older versions of this shader's file are garbage.
        pipelines = pipelines.filter { $0.key.spec != spec || $0.key.modificationDate == key.modificationDate }
        libraries = libraries.filter { $0.key.spec != spec || $0.key.modificationDate == key.modificationDate }
        let pipeline = makePipeline(key: key, path: path, device: device, pixelFormat: pixelFormat)
        pipelines[key] = pipeline
        return pipeline
    }

    // Returns the path of a user file, or nil for a built-in shader.
    private func path(for spec: String) -> String? {
        if spec.contains("/") || spec.hasPrefix("~") || spec.hasSuffix(".metal") {
            return (spec as NSString).expandingTildeInPath
        }
        return nil
    }

    // Checks the file system at most once a second per file.
    private func modificationDate(of path: String) -> Date? {
        let now = Date.timeIntervalSinceReferenceDate
        if let check = fileChecks[path], now - check.checkedAt < 1 {
            return check.modificationDate
        }
        let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        fileChecks[path] = FileCheck(path: path, checkedAt: now, modificationDate: date)
        return date
    }

    private func source(key: Key, path: String?) -> String? {
        let url: URL?
        if let path {
            url = URL(fileURLWithPath: path)
        } else {
            url = Bundle.main.url(forResource: key.spec, withExtension: Self.builtInExtension)
        }
        guard let url else {
            RLog("No built-in post-processing shader named \(redacted: key.spec, or: "[name]")")
            return nil
        }
        guard let body = try? String(contentsOf: url, encoding: .utf8) else {
            RLog("Could not read post-processing shader at \(redacted: url.path, or: "[path]")")
            return nil
        }
        guard let preludeURL = Bundle.main.url(forResource: "iTermPostProcessPrelude",
                                               withExtension: Self.builtInExtension),
              let prelude = try? String(contentsOf: preludeURL, encoding: .utf8) else {
            RLog("Post-processing shader prelude is missing from the bundle")
            return nil
        }
        return prelude + "\n#line 1\n" + body
    }

    private func library(key: Key, path: String?, device: MTLDevice) -> MTLLibrary? {
        var libraryKey = key
        libraryKey.pixelFormat = 0
        if let cached = libraries[libraryKey] {
            return cached
        }
        var library: MTLLibrary?
        if let source = source(key: key, path: path) {
            do {
                library = try device.makeLibrary(source: source, options: nil)
            } catch {
                RLog("Failed to compile post-processing shader \(redacted: key.spec, or: "[shader]"): \(error.localizedDescription)")
            }
        }
        libraries[libraryKey] = library
        return library
    }

    private func makePipeline(key: Key,
                              path: String?,
                              device: MTLDevice,
                              pixelFormat: MTLPixelFormat) -> PostProcessPipeline? {
        guard let library = library(key: key, path: path, device: device),
              let vertexFunction = library.makeFunction(name: "iTermPostProcessVertexShader"),
              let fragmentFunction = library.makeFunction(name: "iTermPostProcessFragmentShader") else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Post-process: \(key.spec)"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = false
        do {
            let state = try device.makeRenderPipelineState(descriptor: descriptor)
            DLog("Compiled post-processing shader \(key.spec)")
            return PostProcessPipeline(pipelineState: state)
        } catch {
            RLog("Failed to create pipeline for post-processing shader \(redacted: key.spec, or: "[shader]"): \(error.localizedDescription)")
            return nil
        }
    }
}
