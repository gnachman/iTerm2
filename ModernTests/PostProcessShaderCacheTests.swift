//
//  PostProcessShaderCacheTests.swift
//  ModernTests
//

import XCTest
import Metal
@testable import iTerm2SharedARC

final class PostProcessShaderCacheTests: XCTestCase {
    private var device: MTLDevice!
    private var directory: URL!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func pipeline(_ shader: String?) -> PostProcessPipeline? {
        return PostProcessShaderCache.instance.pipeline(shader: shader, device: device, pixelFormat: .bgra8Unorm)
    }

    private func writeShader(_ body: String, name: String = "shader.metal") throws -> String {
        let url = directory.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    private let passThrough = """
        float4 mainImage(float2 fragCoord, float2 iResolution, float iTime, float iScale, texture2d<float> iChannel0) {
            return texture(iChannel0, fragCoord / iResolution);
        }
        """

    func testNoShader() {
        XCTAssertNil(pipeline(nil))
        XCTAssertNil(pipeline(""))
        XCTAssertNil(pipeline("   "))
    }

    func testBuiltInShaderCompiles() {
        XCTAssertNotNil(pipeline("amber-crt"))
    }

    func testUnknownBuiltInShader() {
        XCTAssertNil(pipeline("no-such-shader"))
    }

    func testCustomShaderFile() throws {
        let path = try writeShader(passThrough)
        XCTAssertNotNil(pipeline(path))
    }

    func testMissingShaderFile() {
        XCTAssertNil(pipeline(directory.appendingPathComponent("missing.metal").path))
    }

    func testShaderWithCompileError() throws {
        let path = try writeShader("float4 mainImage(this is not valid Metal")
        XCTAssertNil(pipeline(path))
    }

    func testSamePipelineIsReused() throws {
        let path = try writeShader(passThrough)
        let first = try XCTUnwrap(pipeline(path))
        XCTAssertTrue(first === pipeline(path))
    }

    func testEditedFileIsRecompiled() throws {
        let path = try writeShader("float4 mainImage(this is not valid Metal", name: "edited.metal")
        XCTAssertNil(pipeline(path))

        try passThrough.write(toFile: path, atomically: true, encoding: .utf8)
        // Give the file a modification date that is clearly different from the first version.
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)],
                                              ofItemAtPath: path)
        // The file system is checked at most once a second, so wait out that window.
        let fixed = expectation(description: "recompiled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            if self.pipeline(path) != nil {
                fixed.fulfill()
            }
        }
        wait(for: [fixed], timeout: 5)
    }
}
