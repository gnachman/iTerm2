import XCTest
import ProtobufRuntime
@testable import it2core

/// A fake Objective-C-facing channel (the shape the app implements against
/// iTermAPIServer).
private final class FakeObjCChannel: NSObject, IT2ObjCChannel {
    var responses: [ITMServerOriginatedMessage] = []
    func send(_ request: ITMClientOriginatedMessage) throws {}
    func receiveMessage() throws -> ITMServerOriginatedMessage {
        guard !responses.isEmpty else { throw IT2Error.apiError("empty") }
        return responses.removeFirst()
    }
    func disconnect() {}
}

/// Tests the @objc facade IT2Runner that the app calls from Objective-C.
final class IT2RunnerTests: XCTestCase {
    func testRunnerVersionReturnsZero() {
        var out: [String] = []
        let code = IT2Runner.run(["--version"],
                                 stdout: { out.append($0) },
                                 stderr: { _ in },
                                 channel: FakeObjCChannel())
        XCTAssertEqual(code, 0)
        XCTAssertTrue(out.contains("1.0.0"), "got \(out)")
    }

    func testRunnerUnknownCommandReturns64() {
        var err: [String] = []
        let code = IT2Runner.run(["bogus-xyz"],
                                 stdout: { _ in },
                                 stderr: { err.append($0) },
                                 channel: FakeObjCChannel())
        XCTAssertEqual(code, 64)
        XCTAssertFalse(err.isEmpty)
    }
}
