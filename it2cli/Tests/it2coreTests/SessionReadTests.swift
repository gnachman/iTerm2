import XCTest
@testable import it2core

final class SessionReadTests: XCTestCase {
    // `--lines=-1` must fail validation up front with a clean error (nonzero exit) rather
    // than reach Collection.suffix(_:), which traps on a negative length and, run embedded
    // over SSH integration, would crash the entire iTerm2 process from a remote command.
    func testNegativeLinesRejectedWithoutTrapping() throws {
        let capture = OutputCapture()
        var command = try Session.Read.parse(["--lines=-1"])
        XCTAssertThrowsError(try command.run(capture.context(channel: FakeChannel()))) { error in
            guard case IT2Error.invalidArgument = error else {
                return XCTFail("expected IT2Error.invalidArgument, got \(error)")
            }
        }
    }
}
