//
//  TerminalRendererTest.swift
//  ModernTests
//
//  Tests for TerminalRenderer.
//

import Foundation
import XCTest
@testable import iTerm2SharedARC

class TerminalRendererTest: XCTestCase {
    func testLegacyRender() throws {
        try renderAndVerify(gpu: false, filename: "terminal_legacy_test.png")
    }

    func testGPURender() throws {
        try renderAndVerify(gpu: true, filename: "terminal_gpu_test.png")
    }

    private func renderAndVerify(gpu: Bool, filename: String) throws {
        guard let profile = ProfileModel.sharedInstance()?.defaultProfile(),
              let guid = profile[KEY_GUID] as? String else {
            XCTFail("No default profile found")
            return
        }

        let text = "Hello, World!\r\n\u{1b}[1mBold text\u{1b}[0m and \u{1b}[31mred text\u{1b}[0m"
        let data = text.data(using: .utf8)!
        let path = NSTemporaryDirectory() + filename

        try TerminalRenderer.render(
            rows: 24,
            columns: 80,
            profileGUID: guid,
            data: data,
            path: path,
            gpu: gpu
        )

        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let size = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 0, "PNG file should not be empty")
        NSLog("\(gpu ? "GPU" : "Legacy") PNG written to: \(path) (\(size) bytes)")
    }
}
