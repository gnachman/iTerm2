import XCTest
@testable import iTerm2SharedARC

@MainActor
final class SCPFileUploadPreparationFailureTests: XCTestCase {
    func testUploadOfMissingFileRegistersNowAndFailsAsynchronously() {
        let manager = FileTransferManager.sharedInstance()!
        let path = SCPPath()
        path.hostname = "example.com"
        path.username = "user"
        path.path = "/tmp/destination"
        let file = SCPFile()
        file.path = path
        file.setLocalPath(NSTemporaryDirectory() + "/iTerm2-missing-\(UUID().uuidString)")
        file.suppressesAutomaticMenu = true
        var completed = false
        let completion = expectation(description: "Completion called")
        file.completionBlock = { success, error in
            XCTAssertFalse(success)
            XCTAssertNotNil(error)
            XCTAssertTrue(manager.files.contains(file))
            completed = true
            completion.fulfill()
        }
        file.upload()
        // Registered right away, so the failure has an entry in the Uploads menu, but failing
        // (which can open the menu) waits for the caller to return.
        XCTAssertTrue(manager.files.contains(file))
        XCTAssertFalse(completed)
        wait(for: [completion], timeout: 10)
        XCTAssertEqual(file.status, .finishedWithError)
        manager.removeAllUploads()
    }
}
