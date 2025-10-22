import XCTest
import Foundation

final class IntegrationTests: XCTestCase {
    func testAllShellScripts() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let testScript = packageRoot.appendingPathComponent("run_all_tests.sh")

        let process = Process()
        process.executableURL = testScript
        process.currentDirectoryURL = packageRoot

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        print(output)

        XCTAssertEqual(process.terminationStatus, 0, "Shell tests failed:\n\(output)")
    }
}
