//
//  iTermSessionDirectoryTrackerTests.swift
//  iTerm2
//
//  Created by George Nachman on 1/25/26.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - Mock Objects

@MainActor
class MockDirectoryTrackerDelegate: NSObject, @preconcurrency iTermSessionDirectoryTrackerDelegate {
    var didChangeDirectoryCalled = false
    var didUpdateCurrentDirectoryPath: String?
    var recordedPaths: [(path: String, host: (any VT100RemoteHostReading)?, isChange: Bool)] = []
    var createMarkDirectory: String?
    var didChangeLocalDirectoryCalled = false
    var lastChangedLocalDirectory: String?
    var processID: pid_t = 1234
    var environmentPWD: String?
    var isInSoftAlternateScreenMode = false
    var escapeSequencesDisabled = false
    var workingDirectoryProvider: MockWorkingDirectoryProvider?
    var sshIdentityProvider: (any SSHIdentityProvider)?
    /// Directories passed to resolveSymlinksInDirectory, in order.
    var resolveRequests: [String] = []
    /// Completions for those requests, so a test decides when (and whether) each finishes.
    var resolveCompletions: [(String?) -> Void] = []

    func directoryTrackerDidChangeDirectory(_ tracker: iTermSessionDirectoryTracker) {
        didChangeDirectoryCalled = true
    }

    func directoryTrackerDidUpdateCurrentDirectory(_ tracker: iTermSessionDirectoryTracker, path: String?) {
        didUpdateCurrentDirectoryPath = path
    }

    func directoryTracker(_ tracker: iTermSessionDirectoryTracker,
                          recordUsageOfPath path: String,
                          onHost host: (any VT100RemoteHostReading)?,
                          isChange: Bool) {
        recordedPaths.append((path: path, host: host, isChange: isChange))
    }

    func directoryTracker(_ tracker: iTermSessionDirectoryTracker,
                          createMarkForPolledDirectory directory: String) {
        createMarkDirectory = directory
    }

    func directoryTracker(_ tracker: iTermSessionDirectoryTracker,
                          didChangeLocalDirectory directory: String?) {
        didChangeLocalDirectoryCalled = true
        lastChangedLocalDirectory = directory
    }

    func directoryTrackerProcessID(_ tracker: iTermSessionDirectoryTracker) -> pid_t {
        return processID
    }

    func directoryTrackerForegroundProcessGroup(_ tracker: iTermSessionDirectoryTracker) -> pid_t {
        return -1
    }

    func directoryTrackerEnvironmentPWD(_ tracker: iTermSessionDirectoryTracker) -> String? {
        return environmentPWD
    }

    func directoryTrackerIsInSoftAlternateScreenMode(_ tracker: iTermSessionDirectoryTracker) -> Bool {
        return isInSoftAlternateScreenMode
    }

    func directoryTrackerEscapeSequencesDisabled(_ tracker: iTermSessionDirectoryTracker) -> Bool {
        return escapeSequencesDisabled
    }

    func directoryTrackerWorkingDirectoryProvider(_ tracker: iTermSessionDirectoryTracker) -> (any iTermWorkingDirectoryProvider)? {
        return workingDirectoryProvider
    }

    func directoryTrackerSSHIdentityProvider(_ tracker: iTermSessionDirectoryTracker) -> (any SSHIdentityProvider)? {
        return sshIdentityProvider
    }

    func directoryTracker(_ tracker: iTermSessionDirectoryTracker,
                          resolveSymlinksInDirectory directory: String,
                          completion: @escaping (String?) -> Void) {
        resolveRequests.append(directory)
        resolveCompletions.append(completion)
    }

    func reset() {
        didChangeDirectoryCalled = false
        didUpdateCurrentDirectoryPath = nil
        recordedPaths = []
        createMarkDirectory = nil
        didChangeLocalDirectoryCalled = false
        lastChangedLocalDirectory = nil
    }
}

@MainActor
@objc class MockWorkingDirectoryProvider: NSObject, @preconcurrency iTermWorkingDirectoryProvider {
    var syncResult: String?
    var asyncResult: String?
    var asyncDelay: TimeInterval = 0
    var getWorkingDirectoryCalled = false
    var getWorkingDirectoryAsyncCalled = false
    /// When set, async requests wait in deferredCompletions until the test runs them.
    var deferCompletions = false
    var deferredCompletions: [(String?) -> Void] = []

    @objc var getWorkingDirectory: String? {
        getWorkingDirectoryCalled = true
        return syncResult
    }

    @objc func getWorkingDirectory(completion: @escaping (String?) -> Void) {
        getWorkingDirectoryAsyncCalled = true
        if deferCompletions {
            deferredCompletions.append(completion)
            return
        }
        if asyncDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + asyncDelay) {
                completion(self.asyncResult)
            }
        } else {
            completion(asyncResult)
        }
    }
}

@MainActor
class MockSSHIdentityProvider: NSObject, SSHIdentityProvider {
    private let _sshIdentity: SSHIdentity

    init(sshIdentity: SSHIdentity) {
        self._sshIdentity = sshIdentity
        super.init()
    }

    var sshIdentity: SSHIdentity {
        return _sshIdentity
    }
}

// MARK: - Test Class

@MainActor
final class iTermSessionDirectoryTrackerTests: XCTestCase, @preconcurrency iTermObject {
    var tracker: iTermSessionDirectoryTracker!
    var mockDelegate: MockDirectoryTrackerDelegate!
    var mockScope: iTermVariableScope!

    // MARK: - iTermObject

    func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
    func objectScope() -> iTermVariableScope? { nil }

    override func setUp() {
        super.setUp()
        let variables = iTermVariables(context: [], owner: self)
        mockScope = iTermVariableScope()
        mockScope.add(variables, toScopeNamed: nil)
        tracker = iTermSessionDirectoryTracker(variablesScope: mockScope)
        mockDelegate = MockDirectoryTrackerDelegate()
        tracker.delegate = mockDelegate
    }

    override func tearDown() {
        tracker = nil
        mockDelegate = nil
        mockScope = nil
        super.tearDown()
    }

    // MARK: - 1. Initialization Tests

    func testInitialState() {
        // Given: A newly created tracker
        let variables = iTermVariables(context: [], owner: self)
        let scope = iTermVariableScope()
        scope.add(variables, toScopeNamed: nil)
        let newTracker = iTermSessionDirectoryTracker(variablesScope: scope)

        // Then: All properties are in their initial state
        XCTAssertNil(newTracker.lastDirectory)
        XCTAssertNil(newTracker.lastLocalDirectory)
        XCTAssertFalse(newTracker.lastLocalDirectoryWasPushed)
        XCTAssertNil(newTracker.lastRemoteHost)
        XCTAssertTrue(newTracker.directories.isEmpty)
        XCTAssertTrue(newTracker.hosts.isEmpty)
        XCTAssertFalse(newTracker.workingDirectoryPollerDisabled)
        XCTAssertFalse(newTracker.shouldExpectCurrentDirUpdates)
    }

    // MARK: - 2. setLastDirectory Tests

    func testSetLastDirectory_LocalPushed() {
        // When
        tracker.setLastDirectory("/Users/test", remote: false, pushed: true)

        // Then
        XCTAssertEqual(tracker.lastDirectory, "/Users/test")
        XCTAssertEqual(tracker.lastLocalDirectory, "/Users/test")
        XCTAssertTrue(tracker.lastLocalDirectoryWasPushed)
        XCTAssertTrue(tracker.directories.contains("/Users/test"))
        XCTAssertTrue(mockDelegate.didChangeDirectoryCalled)
        XCTAssertEqual(mockScope.value(forVariableName: iTermVariableKeySessionPath) as? String, "/Users/test")
    }

    func testSetLastDirectory_LocalNotPushed() {
        // When
        tracker.setLastDirectory("/Users/test", remote: false, pushed: false)

        // Then
        XCTAssertEqual(tracker.lastDirectory, "/Users/test")
        XCTAssertEqual(tracker.lastLocalDirectory, "/Users/test")
        XCTAssertFalse(tracker.lastLocalDirectoryWasPushed)
        XCTAssertTrue(tracker.directories.isEmpty) // not pushed
        XCTAssertTrue(mockDelegate.didChangeDirectoryCalled)
    }

    func testSetLastDirectory_RemotePushed() {
        // When
        tracker.setLastDirectory("/home/user", remote: true, pushed: true)

        // Then
        XCTAssertEqual(tracker.lastDirectory, "/home/user")
        XCTAssertNil(tracker.lastLocalDirectory) // remote directory
        XCTAssertFalse(tracker.lastLocalDirectoryWasPushed)
        XCTAssertTrue(tracker.directories.contains("/home/user"))
    }

    func testSetLastDirectory_RemoteDoesNotOverwritePushedLocal() {
        // Given
        tracker.setLastDirectory("/Users/local", remote: false, pushed: true)
        mockDelegate.reset()

        // When
        tracker.setLastDirectory("/home/remote", remote: true, pushed: false)

        // Then
        XCTAssertEqual(tracker.lastDirectory, "/home/remote")
        XCTAssertEqual(tracker.lastLocalDirectory, "/Users/local") // unchanged
        XCTAssertTrue(tracker.lastLocalDirectoryWasPushed) // unchanged
    }

    func testSetLastDirectory_LocalNotPushedOverwritesNotPushedLocal() {
        // Given
        tracker.setLastDirectory("/Users/old", remote: false, pushed: false)

        // When
        tracker.setLastDirectory("/Users/new", remote: false, pushed: false)

        // Then
        XCTAssertEqual(tracker.lastLocalDirectory, "/Users/new")
        XCTAssertFalse(tracker.lastLocalDirectoryWasPushed)
    }

    func testSetLastDirectory_LocalPushedOverwritesPushedLocal() {
        // Given
        tracker.setLastDirectory("/Users/old", remote: false, pushed: true)

        // When
        tracker.setLastDirectory("/Users/new", remote: false, pushed: true)

        // Then
        XCTAssertEqual(tracker.lastLocalDirectory, "/Users/new")
        XCTAssertTrue(tracker.lastLocalDirectoryWasPushed)
    }

    func testSetLastDirectory_NilDirectory() {
        // Given
        tracker.setLastDirectory("/Users/test", remote: false, pushed: true)
        let previousPath = mockScope.value(forVariableName: iTermVariableKeySessionPath) as? String

        // When
        tracker.setLastDirectory(nil, remote: false, pushed: false)

        // Then
        XCTAssertNil(tracker.lastDirectory)
        // variablesScope.path should not be updated when nil (still has previous value)
        XCTAssertEqual(mockScope.value(forVariableName: iTermVariableKeySessionPath) as? String, previousPath)
    }

    // MARK: - 3. Directory History Trimming Tests

    func testDirectoriesTrimmedAtMax() {
        // When: Push 101 directories
        for i in 0..<101 {
            tracker.setLastDirectory("/dir\(i)", remote: false, pushed: true)
        }

        // Then
        XCTAssertEqual(tracker.directories.count, 100)
        XCTAssertFalse(tracker.directories.contains("/dir0")) // first one removed
        XCTAssertTrue(tracker.directories.contains("/dir100")) // last one present
    }

    func testHostsTrimmedAtMax() {
        // When: Add 101 hosts
        for i in 0..<101 {
            let host = VT100RemoteHost(username: "user", hostname: "host\(i).com")
            tracker.recordLastRemoteHost(host)
        }

        // Then
        XCTAssertEqual(tracker.hosts.count, 100)
    }

    // MARK: - 4. Arrangement Serialization Tests

    func testEncodeArrangement_AllFields() {
        // Given
        tracker.setLastDirectory("/Users/test", remote: false, pushed: true)
        tracker.setLastDirectory("/Users/local", remote: false, pushed: true)
        tracker.shouldExpectCurrentDirUpdates = true
        tracker.workingDirectoryPollerDisabled = true
        let host1 = VT100RemoteHost(username: "user1", hostname: "host1.com")
        let host2 = VT100RemoteHost(username: "user2", hostname: "host2.com")
        tracker.recordLastRemoteHost(host1)
        tracker.recordLastRemoteHost(host2)

        let encoder = iTermMutableDictionaryEncoderAdapter.encoder()

        // When
        tracker.encodeArrangement(with: encoder)

        // Then
        let dict = encoder.mutableDictionary
        XCTAssertEqual(dict["Last Directory"] as? String, "/Users/local")
        XCTAssertEqual(dict["Last Local Directory"] as? String, "/Users/local")
        XCTAssertEqual((dict["Last Local Directory Was Pushed"] as? NSNumber)?.boolValue, true)
        XCTAssertEqual((dict["Should Expect Current Dir Updates"] as? NSNumber)?.boolValue, true)
        XCTAssertEqual((dict["Working Directory Poller Disabled"] as? NSNumber)?.boolValue, true)
        XCTAssertNotNil(dict["Directories"])
        XCTAssertNotNil(dict["Hosts"])
    }

    func testEncodeArrangement_NilLastDirectory() {
        // Given: tracker with nil lastDirectory (initial state)
        let encoder = iTermMutableDictionaryEncoderAdapter.encoder()

        // When
        tracker.encodeArrangement(with: encoder)

        // Then
        XCTAssertNil(encoder.mutableDictionary["Last Directory"])
    }

    func testRestoreFromArrangement_AllFields() {
        // Given
        let arrangement: [String: Any] = [
            "Last Directory": "/Users/test",
            "Last Local Directory": "/Users/local",
            "Last Local Directory Was Pushed": true,
            "Should Expect Current Dir Updates": true,
            "Working Directory Poller Disabled": true,
            "Directories": ["/a", "/b"],
            "Hosts": [["hostname": "host.com", "username": "user"]]
        ]

        // When
        tracker.restoreFromArrangement(arrangement)

        // Then
        XCTAssertEqual(tracker.lastDirectory, "/Users/test")
        XCTAssertEqual(tracker.lastLocalDirectory, "/Users/local")
        XCTAssertTrue(tracker.lastLocalDirectoryWasPushed)
        XCTAssertTrue(tracker.shouldExpectCurrentDirUpdates)
        XCTAssertTrue(tracker.workingDirectoryPollerDisabled)
        XCTAssertEqual(tracker.directories, ["/a", "/b"])
        XCTAssertEqual(tracker.hosts.count, 1)
    }

    func testRestoreFromArrangement_BackwardCompatibility_IsRemote() {
        // Given: old arrangement with deprecated key
        let arrangement: [String: Any] = [
            "Last Directory": "/home/user",
            "Last Directory Is Remote": true
        ]

        // When
        tracker.restoreFromArrangement(arrangement)

        // Then
        XCTAssertEqual(tracker.lastDirectory, "/home/user")
        XCTAssertNil(tracker.lastLocalDirectory) // because isRemote was true
    }

    func testRestoreFromArrangement_BackwardCompatibility_NotRemote() {
        // Given
        let arrangement: [String: Any] = [
            "Last Directory": "/Users/local",
            "Last Directory Is Remote": false
        ]

        // When
        tracker.restoreFromArrangement(arrangement)

        // Then
        XCTAssertEqual(tracker.lastDirectory, "/Users/local")
        XCTAssertEqual(tracker.lastLocalDirectory, "/Users/local")
    }

    func testRestoreFromArrangement_SetsPollerDisabledFromExpectUpdates() {
        // Given
        let arrangement: [String: Any] = [
            "Should Expect Current Dir Updates": true,
            "Working Directory Poller Disabled": false
        ]

        // When
        tracker.restoreFromArrangement(arrangement)

        // Then: workingDirectoryPollerDisabled is OR of both
        XCTAssertTrue(tracker.workingDirectoryPollerDisabled)
    }

    // MARK: - 5. Working Directory Poller Delegate Tests

    func testPollerResult_ValidDirectory_CreatesMarkWhenAllowed() {
        // Given
        tracker.workingDirectoryPollerDisabled = false
        tracker.shouldExpectCurrentDirUpdates = false
        mockDelegate.isInSoftAlternateScreenMode = false
        mockDelegate.escapeSequencesDisabled = false

        // When
        pollerFound("/Users/test", invalidated: false)

        // Then
        XCTAssertEqual(mockDelegate.createMarkDirectory, "/Users/test")
    }

    func testPollerResult_Invalidated_DoesNotCreateMark() {
        // Given
        tracker.workingDirectoryPollerDisabled = false
        tracker.shouldExpectCurrentDirUpdates = false

        // When
        pollerFound("/Users/test", invalidated: true)

        // Then
        XCTAssertNil(mockDelegate.createMarkDirectory)
        XCTAssertEqual(tracker.lastLocalDirectory, "/Users/test")
        XCTAssertFalse(tracker.lastLocalDirectoryWasPushed)
    }

    func testPollerResult_Invalidated_DoesNotOverwritePushedLocal() {
        // Given
        tracker.setLastDirectory("/Users/pushed", remote: false, pushed: true)
        mockDelegate.reset()

        // When
        pollerFound("/Users/polled", invalidated: true)

        // Then
        XCTAssertEqual(tracker.lastLocalDirectory, "/Users/pushed") // unchanged
        // When we have a pushed local directory and get an invalidated result, we return early
        // without calling any delegate methods
        XCTAssertFalse(mockDelegate.didChangeDirectoryCalled)
    }

    func testPollerResult_PollerDisabled_DoesNotCreateMark() {
        // Given
        tracker.workingDirectoryPollerDisabled = true

        // When
        pollerFound("/Users/test", invalidated: false)

        // Then
        XCTAssertNil(mockDelegate.createMarkDirectory)
    }

    func testPollerResult_ShellIntegrationUsed_DoesNotCreateMark() {
        // Given
        tracker.shouldExpectCurrentDirUpdates = true
        mockDelegate.escapeSequencesDisabled = false

        // When
        pollerFound("/Users/test", invalidated: false)

        // Then
        XCTAssertNil(mockDelegate.createMarkDirectory)
    }

    func testPollerResult_ShellIntegrationUsed_ButEscapeSequencesDisabled_CreatesMarkWhenAllowed() {
        // Given
        tracker.shouldExpectCurrentDirUpdates = true
        mockDelegate.escapeSequencesDisabled = true
        tracker.workingDirectoryPollerDisabled = false

        // When
        pollerFound("/Users/test", invalidated: false)

        // Then
        XCTAssertEqual(mockDelegate.createMarkDirectory, "/Users/test")
    }

    func testPollerResult_NilDirectory_DoesNotCreateMark() {
        // Given: valid conditions
        tracker.workingDirectoryPollerDisabled = false
        tracker.shouldExpectCurrentDirUpdates = false

        // When
        pollerFound(nil, invalidated: false)

        // Then
        XCTAssertNil(mockDelegate.createMarkDirectory)
    }

    // MARK: - 5b. Plain ssh: local poll must not clobber the remote path (QA F-103)

    // Mirrors what PTYSession does when OSC 7 from a remote shell (plain `ssh`,
    // no ssh integration) reports a directory on a remote host.
    private func pushRemoteDirectory(_ dir: String) {
        let remoteHost = VT100RemoteHost(username: "qauser", hostname: "qaremote")
        tracker.screenWillChangeCurrentDirectory(to: dir, remoteHost: remoteHost)
        tracker.screenLogWorkingDirectory(onAbsoluteLine: 10,
                                          remoteHost: remoteHost,
                                          withDirectory: dir,
                                          pushType: .strongPush,
                                          accepted: true)
        mockScope.setValue(dir, forVariableNamed: iTermVariableKeySessionPath)
        tracker.screenDidChangeCurrentDirectory()
    }

    private var sessionPath: String? {
        mockScope.value(forVariableName: iTermVariableKeySessionPath) as? String
    }

    func testPollerResult_AfterRemotePush_DoesNotChangeSessionPath() {
        pushRemoteDirectory("/tmp/qa125")

        // The poller reports the local ssh process's cwd (e.g. after a key press
        // and a line feed), arriving after the remote push.
        pollerFound("/Users/local", invalidated: false)

        XCTAssertEqual(sessionPath, "/tmp/qa125")
        XCTAssertEqual(tracker.lastDirectory, "/tmp/qa125")
        // The local directory is still tracked for session restoration.
        XCTAssertEqual(tracker.lastLocalDirectory, "/Users/local")
    }

    func testInvalidatedPollerResult_AfterRemotePush_DoesNotChangeSessionPath() {
        pushRemoteDirectory("/tmp/qa125")

        pollerFound("/Users/local", invalidated: true)

        XCTAssertEqual(sessionPath, "/tmp/qa125")
        XCTAssertEqual(tracker.lastLocalDirectory, "/Users/local")
    }

    func testPollLocalDirectoryOnly_AfterRemotePush_DoesNotChangeSessionPath() {
        let provider = MockWorkingDirectoryProvider()
        provider.asyncResult = "/Users/local"
        mockDelegate.workingDirectoryProvider = provider
        pushRemoteDirectory("/tmp/qa125")

        tracker.pollLocalDirectoryOnly()

        XCTAssertTrue(provider.getWorkingDirectoryAsyncCalled)
        XCTAssertEqual(tracker.lastLocalDirectory, "/Users/local")
        XCTAssertEqual(sessionPath, "/tmp/qa125")
    }

    // MARK: - 6. Screen Delegate Method Tests

    func testScreenLogWorkingDirectory_Pushed_RecordsHistory() {
        // Given
        let host = VT100RemoteHost.localhost()

        // When
        tracker.screenLogWorkingDirectory(onAbsoluteLine: 100,
                                          remoteHost: host,
                                          withDirectory: "/Users/test",
                                          pushType: .weakPush,
                                          accepted: true)

        // Then
        XCTAssertEqual(mockDelegate.recordedPaths.count, 1)
        XCTAssertEqual(mockDelegate.recordedPaths[0].path, "/Users/test")
        XCTAssertTrue(mockDelegate.recordedPaths[0].isChange)
        XCTAssertEqual(tracker.lastDirectory, "/Users/test")
        XCTAssertTrue(tracker.lastRemoteHost?.isEqual(toRemoteHost: host) ?? false)
    }

    func testScreenLogWorkingDirectory_Pushed_SameDirectorySameHost_NotAChange() {
        // Given
        let host = VT100RemoteHost.localhost()
        tracker.setLastDirectory("/Users/test", remote: false, pushed: true)
        tracker.recordLastRemoteHost(host)
        mockDelegate.reset()

        // When
        tracker.screenLogWorkingDirectory(onAbsoluteLine: 100,
                                          remoteHost: host,
                                          withDirectory: "/Users/test",
                                          pushType: .weakPush,
                                          accepted: true)

        // Then
        XCTAssertEqual(mockDelegate.recordedPaths.count, 1)
        XCTAssertFalse(mockDelegate.recordedPaths[0].isChange)
    }

    func testScreenLogWorkingDirectory_Pull_DoesNotRecordHistory() {
        // When
        tracker.screenLogWorkingDirectory(onAbsoluteLine: 100,
                                          remoteHost: nil,
                                          withDirectory: "/Users/test",
                                          pushType: .pull,
                                          accepted: true)

        // Then
        XCTAssertTrue(mockDelegate.recordedPaths.isEmpty)
    }

    func testScreenLogWorkingDirectory_NotAccepted_DoesNotUpdateState() {
        // Given
        tracker.setLastDirectory("/Users/old", remote: false, pushed: true)

        // When
        tracker.screenLogWorkingDirectory(onAbsoluteLine: 100,
                                          remoteHost: nil,
                                          withDirectory: "/Users/new",
                                          pushType: .weakPush,
                                          accepted: false)

        // Then
        XCTAssertEqual(tracker.lastDirectory, "/Users/old") // unchanged
    }

    func testScreenLogWorkingDirectory_StrongPush_RemoteHost_MarksRemote() {
        // Given
        let remoteHost = VT100RemoteHost(username: "user", hostname: "remote.com")

        // When
        tracker.screenLogWorkingDirectory(onAbsoluteLine: 100,
                                          remoteHost: remoteHost,
                                          withDirectory: "/home/user",
                                          pushType: .strongPush,
                                          accepted: true)

        // Then
        XCTAssertNil(tracker.lastLocalDirectory) // directory is remote
    }

    func testScreenLogWorkingDirectory_StrongPush_LocalHost_MarksLocal() {
        // Given
        let localHost = VT100RemoteHost.localhost()

        // When
        tracker.screenLogWorkingDirectory(onAbsoluteLine: 100,
                                          remoteHost: localHost,
                                          withDirectory: "/Users/test",
                                          pushType: .strongPush,
                                          accepted: true)

        // Then
        XCTAssertEqual(tracker.lastLocalDirectory, "/Users/test")
    }

    func testScreenDidChangeCurrentDirectory_DisablesPoller() {
        // Given
        tracker.workingDirectoryPollerDisabled = false

        // When
        tracker.screenDidChangeCurrentDirectory()

        // Then
        XCTAssertTrue(tracker.workingDirectoryPollerDisabled)
    }

    func testScreenWillChangeCurrentDirectory_SetsExpectUpdates() {
        // Given
        tracker.shouldExpectCurrentDirUpdates = false

        // When
        tracker.screenWillChangeCurrentDirectory(to: "/Users/test", remoteHost: nil)

        // Then
        XCTAssertTrue(tracker.shouldExpectCurrentDirUpdates)
        XCTAssertEqual(mockDelegate.didUpdateCurrentDirectoryPath, "/Users/test")
    }

    // MARK: - 6b. Pushes refresh the directory new local sessions start in

    // `cd foo; claude` pasted: the poller last ran before the cd, so its cached result is
    // stale. The push from the prompt after the cd must refresh it.
    func testUnverifiedStrongPush_PollsLocalDirectory() {
        pollerFound("/Users/before", invalidated: false)
        let provider = MockWorkingDirectoryProvider()
        provider.asyncResult = "/Users/after"
        mockDelegate.workingDirectoryProvider = provider

        tracker.screenLogWorkingDirectory(onAbsoluteLine: 100,
                                          remoteHost: VT100RemoteHost.localhost(),
                                          withDirectory: "/Users/after",
                                          pushType: .strongPush,
                                          locality: .unverified,
                                          accepted: true)

        XCTAssertTrue(provider.getWorkingDirectoryAsyncCalled)
        XCTAssertEqual(tracker.verifiedLocalDirectory, "/Users/after")
    }

    // A push proven local by a machineID token is as good as a poll, and keeps the
    // user's unresolved symlinks.
    func testVerifiedStrongPush_UsesPushedDirectoryWithoutPolling() {
        pollerFound("/Users/before", invalidated: false)
        let provider = MockWorkingDirectoryProvider()
        provider.asyncResult = "/private/resolved/after"
        mockDelegate.workingDirectoryProvider = provider

        tracker.screenLogWorkingDirectory(onAbsoluteLine: 100,
                                          remoteHost: VT100RemoteHost.localhost(),
                                          withDirectory: "/Users/after",
                                          pushType: .strongPush,
                                          locality: .verifiedReport,
                                          accepted: true)

        XCTAssertFalse(provider.getWorkingDirectoryAsyncCalled)
        XCTAssertEqual(tracker.verifiedLocalDirectory, "/Users/after")
    }

    // Issue 12616: fish over plain ssh pushes a remote path with no hostname. It is not
    // verified, so the local directory comes from polling the local shell, not the push.
    func testUnverifiedRemotePathPush_DoesNotBecomeLocalDirectory() {
        let provider = MockWorkingDirectoryProvider()
        provider.asyncResult = "/Users/local"
        mockDelegate.workingDirectoryProvider = provider

        tracker.screenLogWorkingDirectory(onAbsoluteLine: 100,
                                          remoteHost: VT100RemoteHost.localhost(),
                                          withDirectory: "/home/remote",
                                          pushType: .strongPush,
                                          locality: .unverified,
                                          accepted: true)

        XCTAssertEqual(tracker.verifiedLocalDirectory, "/Users/local")
        let expectation = self.expectation(description: "completion called")
        tracker.asyncInitialDirectoryForNewSessionBasedOnCurrentDirectory(sshIdentity: nil) { pwd in
            XCTAssertEqual(pwd, "/Users/local")
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    // A poll resolves symlinks. It must not replace the readable path a verified push gave,
    // whether it comes from the line-feed poller or a local-only poll.
    func testPollAfterVerifiedPush_KeepsPushedSymlinkPath() {
        let provider = MockWorkingDirectoryProvider()
        provider.asyncResult = "/Volumes/Data/src"
        mockDelegate.workingDirectoryProvider = provider
        tracker.screenLogWorkingDirectory(onAbsoluteLine: 100,
                                          remoteHost: VT100RemoteHost.localhost(),
                                          withDirectory: "/Users/me/src",
                                          pushType: .strongPush,
                                          locality: .verifiedReport,
                                          accepted: true)

        pollerFound("/Volumes/Data/src", invalidated: false)
        tracker.pollLocalDirectoryOnly()

        XCTAssertEqual(tracker.verifiedLocalDirectory, "/Users/me/src")
    }

    /// A poller result for a request that began just now, after any push so far.
    private func pollerFound(_ pwd: String?, invalidated: Bool) {
        tracker.workingDirectoryPollerDidFindWorkingDirectory(pwd,
                                                              invalidated: invalidated,
                                                              requestStamp: tracker.workingDirectoryPollerRequestStamp())
    }

    private func pushVerified(_ directory: String) {
        tracker.screenLogWorkingDirectory(onAbsoluteLine: 100,
                                          remoteHost: VT100RemoteHost.localhost(),
                                          withDirectory: directory,
                                          pushType: .strongPush,
                                          locality: .verifiedReport,
                                          accepted: true)
    }

    // Once the pushed symlink's target is known, polls of the target keep the symlink.
    func testPollOfResolvedPushedDirectory_KeepsSymlinkPath() {
        pushVerified("/Users/me/src")
        XCTAssertEqual(mockDelegate.resolveRequests, ["/Users/me/src"])
        mockDelegate.resolveCompletions[0]("/Volumes/Data/src")

        pollerFound("/Volumes/Data/src", invalidated: false)

        XCTAssertEqual(tracker.verifiedLocalDirectory, "/Users/me/src")
    }

    // A poll naming neither the pushed directory nor its target means the shell moved without
    // reporting it (e.g., it exec'ed a shell without shell integration and cd'ed).
    func testPollOfOtherDirectoryAfterResolution_Wins() {
        pushVerified("/Users/me/src")
        mockDelegate.resolveCompletions[0]("/Volumes/Data/src")

        pollerFound("/tmp/elsewhere", invalidated: false)

        XCTAssertEqual(tracker.verifiedLocalDirectory, "/tmp/elsewhere")
    }

    // Re-pushing the same directory, as every prompt does, keeps the cached resolution.
    func testRepushOfSameDirectory_DoesNotResolveAgain() {
        pushVerified("/Users/me/src")
        mockDelegate.resolveCompletions[0]("/Volumes/Data/src")
        pushVerified("/Users/me/src")

        XCTAssertEqual(mockDelegate.resolveRequests.count, 1)
        pollerFound("/Volumes/Data/src", invalidated: false)
        XCTAssertEqual(tracker.verifiedLocalDirectory, "/Users/me/src")
    }

    // Symlinks can change, so a new pushed directory discards the old resolution, and a
    // resolution of the old directory that finishes late is ignored.
    func testNewPush_DiscardsResolutionOfPreviousDirectory() {
        pushVerified("/Users/me/a")
        pushVerified("/Users/me/b")
        XCTAssertEqual(mockDelegate.resolveRequests, ["/Users/me/a", "/Users/me/b"])
        mockDelegate.resolveCompletions[0]("/Volumes/Data/a")

        // b is still resolving, so it's kept even though a's target was polled.
        pollerFound("/Volumes/Data/a", invalidated: false)
        XCTAssertEqual(tracker.verifiedLocalDirectory, "/Users/me/b")

        mockDelegate.resolveCompletions[1]("/Volumes/Data/b")
        pollerFound("/Volumes/Data/a", invalidated: false)
        XCTAssertEqual(tracker.verifiedLocalDirectory, "/Volumes/Data/a")
    }

    // A line-feed poll that began before the push may describe where the shell was before it.
    func testPollerResultFromBeforeVerifiedPush_IsIgnored() {
        let stamp = tracker.workingDirectoryPollerRequestStamp()
        pushVerified("/Users/me/src")
        mockDelegate.resolveCompletions[0]("/Volumes/Data/src")

        tracker.workingDirectoryPollerDidFindWorkingDirectory("/Users/me/before",
                                                              invalidated: true,
                                                              requestStamp: stamp)

        XCTAssertEqual(tracker.verifiedLocalDirectory, "/Users/me/src")
    }

    // Pressing Enter on `cd foo` starts a line-feed poll while the shell is still in the old
    // directory. The prompt's unverified push starts a refresh poll. If the refresh returns
    // first, the old poll must not put the old directory back.
    func testPollerResultFromBeforeUnverifiedPush_DoesNotOverrideRefresh() {
        let provider = MockWorkingDirectoryProvider()
        provider.deferCompletions = true
        mockDelegate.workingDirectoryProvider = provider
        let stamp = tracker.workingDirectoryPollerRequestStamp()

        tracker.screenLogWorkingDirectory(onAbsoluteLine: 100,
                                          remoteHost: nil,
                                          withDirectory: "/new",
                                          pushType: .strongPush,
                                          locality: .unverified,
                                          accepted: true)
        provider.deferredCompletions[0]("/new")
        tracker.workingDirectoryPollerDidFindWorkingDirectory("/old",
                                                              invalidated: true,
                                                              requestStamp: stamp)

        XCTAssertEqual(tracker.verifiedLocalDirectory, "/new")
    }

    // An empty CurrentDir report is filled in with whichever poll finishes first, which may
    // have begun before a newer push. The tracker already recorded that poll, stale-checked,
    // so the push carrying its result must not override a newer verified push.
    func testPushOfPolledDirectory_DoesNotReplaceNewerVerifiedPush() {
        let provider = MockWorkingDirectoryProvider()
        provider.deferCompletions = true
        mockDelegate.workingDirectoryProvider = provider
        pushVerified("/Users/me/new")

        tracker.screenLogWorkingDirectory(onAbsoluteLine: 100,
                                          remoteHost: VT100RemoteHost.localhost(),
                                          withDirectory: "/Users/me/old",
                                          pushType: .strongPush,
                                          locality: .localPoll,
                                          accepted: true)

        XCTAssertEqual(tracker.verifiedLocalDirectory, "/Users/me/new")
        XCTAssertEqual(mockDelegate.resolveRequests, ["/Users/me/new"])
        XCTAssertTrue(provider.deferredCompletions.isEmpty)
        // It isn't a new push either, so a poll begun after the verified push still counts.
        mockDelegate.resolveCompletions[0]("/Volumes/Data/new")
        pollerFound("/tmp/elsewhere", invalidated: false)
        XCTAssertEqual(tracker.verifiedLocalDirectory, "/tmp/elsewhere")
    }

    // An empty CurrentDir report says the shell moved, so a poll that began before it is
    // stale even if it lands after the poll that fills in the report.
    func testPollerResultFromBeforeEmptyReport_DoesNotOverrideFillInPoll() {
        pollerFound("/old", invalidated: false)
        let stamp = tracker.workingDirectoryPollerRequestStamp()

        tracker.directoryChangeReportedWithoutDirectory()
        pollerFound("/new", invalidated: false)
        tracker.workingDirectoryPollerDidFindWorkingDirectory("/old",
                                                              invalidated: false,
                                                              requestStamp: stamp)

        XCTAssertEqual(tracker.verifiedLocalDirectory, "/new")
    }

    // The report says the shell moved, so the poll filling it in replaces a verified push even
    // before the push's resolution is known.
    func testEmptyReport_LetsFillInPollReplaceUnresolvedVerifiedPush() {
        pushVerified("/Users/me/src")

        tracker.directoryChangeReportedWithoutDirectory()
        pollerFound("/tmp/elsewhere", invalidated: false)

        XCTAssertEqual(tracker.verifiedLocalDirectory, "/tmp/elsewhere")
    }

    // With nothing recorded, a new session polls. If a push makes that poll stale before it
    // finishes, its result is still better than nothing while the push's own poll runs.
    func testAsyncLocalDirectory_UsesStalePollWhenNothingRecorded() {
        let provider = MockWorkingDirectoryProvider()
        provider.deferCompletions = true
        mockDelegate.workingDirectoryProvider = provider
        var result: String?
        tracker.asyncCurrentLocalWorkingDirectory { result = $0 }

        tracker.screenLogWorkingDirectory(onAbsoluteLine: 100,
                                          remoteHost: nil,
                                          withDirectory: "/Users/me/pushed",
                                          pushType: .strongPush,
                                          locality: .unverified,
                                          accepted: true)
        provider.deferredCompletions[0]("/Users/me/polled")

        XCTAssertEqual(result, "/Users/me/polled")
        XCTAssertNil(tracker.verifiedLocalDirectory)
    }

    // A weak push invalidates the poller's requests but establishes nothing, so a poll that
    // began before it still applies.
    func testPollerResultFromBeforeWeakPush_Applies() {
        let stamp = tracker.workingDirectoryPollerRequestStamp()
        tracker.screenLogWorkingDirectory(onAbsoluteLine: 100,
                                          remoteHost: nil,
                                          withDirectory: "/Users/titled",
                                          pushType: .weakPush,
                                          accepted: true)

        tracker.workingDirectoryPollerDidFindWorkingDirectory("/Users/polled",
                                                              invalidated: true,
                                                              requestStamp: stamp)

        XCTAssertEqual(tracker.verifiedLocalDirectory, "/Users/polled")
    }

    // A resolution that comes back empty (the service wasn't ready, or it failed) is retried
    // on the next push of the same directory; otherwise the shell moving without a push
    // would never be detected.
    func testFailedResolution_IsRetriedOnRepush() {
        pushVerified("/Users/me/src")
        mockDelegate.resolveCompletions[0](nil)

        pushVerified("/Users/me/src")
        XCTAssertEqual(mockDelegate.resolveRequests, ["/Users/me/src", "/Users/me/src"])

        mockDelegate.resolveCompletions[1]("/Volumes/Data/src")
        pollerFound("/tmp/elsewhere", invalidated: false)
        XCTAssertEqual(tracker.verifiedLocalDirectory, "/tmp/elsewhere")
    }

    // While a resolution is outstanding, a re-push doesn't start another.
    func testOutstandingResolution_IsNotDuplicatedOnRepush() {
        pushVerified("/Users/me/src")
        pushVerified("/Users/me/src")

        XCTAssertEqual(mockDelegate.resolveRequests.count, 1)
    }

    // A resolution of a replaced directory doesn't count as outstanding for the new one.
    func testResolutionOfReplacedDirectory_DoesNotBlockRetry() {
        pushVerified("/Users/me/a")
        pushVerified("/Users/me/b")
        mockDelegate.resolveCompletions[1](nil)
        mockDelegate.resolveCompletions[0]("/Volumes/Data/a")

        pushVerified("/Users/me/b")

        XCTAssertEqual(mockDelegate.resolveRequests, ["/Users/me/a", "/Users/me/b", "/Users/me/b"])
    }

    // Likewise for a local-only poll that began before the push.
    func testLocalPollStartedBeforeVerifiedPush_IsIgnored() {
        let provider = MockWorkingDirectoryProvider()
        provider.deferCompletions = true
        mockDelegate.workingDirectoryProvider = provider
        tracker.pollLocalDirectoryOnly()

        pushVerified("/Users/me/src")
        mockDelegate.resolveCompletions[0]("/Volumes/Data/src")
        provider.deferredCompletions[0]("/Users/me/before")

        XCTAssertEqual(tracker.verifiedLocalDirectory, "/Users/me/src")
    }

    // ssh from a local shell (nested or not) to a host whose reports are unverified, whether
    // third-party, older scripts without a machineID, or ours proving it's remote. The poll
    // reads the local shell that ran ssh, which is still in the pushed directory, so the
    // pushed spelling stays.
    func testUnverifiedPushAfterVerifiedPush_KeepsPushedPathWhenPollNamesIt() {
        let provider = MockWorkingDirectoryProvider()
        provider.asyncResult = "/Volumes/Data/src"
        mockDelegate.workingDirectoryProvider = provider
        pushVerified("/Users/me/src")
        mockDelegate.resolveCompletions[0]("/Volumes/Data/src")

        tracker.screenLogWorkingDirectory(onAbsoluteLine: 101,
                                          remoteHost: nil,
                                          withDirectory: "/home/remote",
                                          pushType: .strongPush,
                                          locality: .unverified,
                                          accepted: true)

        XCTAssertTrue(provider.getWorkingDirectoryAsyncCalled)
        XCTAssertEqual(tracker.verifiedLocalDirectory, "/Users/me/src")
    }

    // A local shell without a machineID (e.g., `exec fish`) that cd's: the poll after its push
    // names another directory, so it wins.
    func testUnverifiedPushAfterVerifiedPush_PollOfOtherDirectoryWins() {
        let provider = MockWorkingDirectoryProvider()
        provider.asyncResult = "/tmp/y"
        mockDelegate.workingDirectoryProvider = provider
        pushVerified("/Users/me/src")
        mockDelegate.resolveCompletions[0]("/Volumes/Data/src")

        tracker.screenLogWorkingDirectory(onAbsoluteLine: 101,
                                          remoteHost: nil,
                                          withDirectory: "/tmp/y",
                                          pushType: .strongPush,
                                          locality: .unverified,
                                          accepted: true)

        XCTAssertEqual(tracker.verifiedLocalDirectory, "/tmp/y")
    }

    // An unverified push says the shell may have moved, so before the verified push's
    // resolution is known its poll, and later polls, apply.
    func testUnverifiedPushAfterVerifiedPush_LetsPollsApplyAgain() {
        let provider = MockWorkingDirectoryProvider()
        provider.asyncResult = "/Users/local"
        mockDelegate.workingDirectoryProvider = provider
        tracker.screenLogWorkingDirectory(onAbsoluteLine: 100,
                                          remoteHost: VT100RemoteHost.localhost(),
                                          withDirectory: "/Users/me/src",
                                          pushType: .strongPush,
                                          locality: .verifiedReport,
                                          accepted: true)

        tracker.screenLogWorkingDirectory(onAbsoluteLine: 101,
                                          remoteHost: VT100RemoteHost.localhost(),
                                          withDirectory: "/home/remote",
                                          pushType: .strongPush,
                                          locality: .unverified,
                                          accepted: true)
        XCTAssertEqual(tracker.verifiedLocalDirectory, "/Users/local")

        pollerFound("/Users/elsewhere", invalidated: false)
        XCTAssertEqual(tracker.verifiedLocalDirectory, "/Users/elsewhere")
    }

    func testRejectedPush_DoesNotTouchLocalDirectory() {
        pollerFound("/Users/before", invalidated: false)
        let provider = MockWorkingDirectoryProvider()
        provider.asyncResult = "/Users/after"
        mockDelegate.workingDirectoryProvider = provider

        tracker.screenLogWorkingDirectory(onAbsoluteLine: 100,
                                          remoteHost: VT100RemoteHost.localhost(),
                                          withDirectory: "/Users/after",
                                          pushType: .strongPush,
                                          locality: .verifiedReport,
                                          accepted: false)

        XCTAssertFalse(provider.getWorkingDirectoryAsyncCalled)
        XCTAssertEqual(tracker.verifiedLocalDirectory, "/Users/before")
    }

    // MARK: - 7. Async Directory Fetching Tests

    func testAsyncCurrentLocalWorkingDirectory_CachedValue() {
        // Given: Simulate a poller result to set verifiedLocalDirectory
        pollerFound("/Users/cached", invalidated: false)
        let provider = MockWorkingDirectoryProvider()
        mockDelegate.workingDirectoryProvider = provider

        let expectation = self.expectation(description: "completion called")

        // When
        tracker.asyncCurrentLocalWorkingDirectory { pwd in
            // Then: Should use verifiedLocalDirectory, not fetch again
            XCTAssertEqual(pwd, "/Users/cached")
            XCTAssertFalse(provider.getWorkingDirectoryAsyncCalled)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func testAsyncCurrentLocalWorkingDirectory_FetchesWhenNoCachedValue() {
        // Given
        let provider = MockWorkingDirectoryProvider()
        provider.asyncResult = "/Users/fetched"
        mockDelegate.workingDirectoryProvider = provider

        let expectation = self.expectation(description: "completion called")

        // When
        tracker.asyncCurrentLocalWorkingDirectory { pwd in
            // Then
            XCTAssertEqual(pwd, "/Users/fetched")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(provider.getWorkingDirectoryAsyncCalled)
        XCTAssertEqual(tracker.lastLocalDirectory, "/Users/fetched")
        XCTAssertFalse(tracker.lastLocalDirectoryWasPushed)
    }

    func testCurrentLocalWorkingDirectory_Sync_ReturnsCachedValue() {
        // Given
        tracker.setLastDirectory("/Users/cached", remote: false, pushed: true)
        let provider = MockWorkingDirectoryProvider()
        mockDelegate.workingDirectoryProvider = provider

        // When
        let result = tracker.currentLocalWorkingDirectory

        // Then
        XCTAssertEqual(result, "/Users/cached")
        XCTAssertFalse(provider.getWorkingDirectoryCalled)
    }

    func testCurrentLocalWorkingDirectory_Sync_FetchesWhenNil() {
        // Given
        let provider = MockWorkingDirectoryProvider()
        provider.syncResult = "/Users/fetched"
        mockDelegate.workingDirectoryProvider = provider

        // When
        let result = tracker.currentLocalWorkingDirectory

        // Then
        XCTAssertEqual(result, "/Users/fetched")
        XCTAssertTrue(provider.getWorkingDirectoryCalled)
        XCTAssertEqual(tracker.lastLocalDirectory, "/Users/fetched")
        XCTAssertFalse(tracker.lastLocalDirectoryWasPushed)
    }

    func testAsyncInitialDirectory_NoConductor_UsesLocalDirectory() {
        // Given: Simulate a poller result to set verifiedLocalDirectory
        mockDelegate.sshIdentityProvider = nil
        pollerFound("/Users/local", invalidated: false)

        let expectation = self.expectation(description: "completion called")

        // When
        tracker.asyncInitialDirectoryForNewSessionBasedOnCurrentDirectory(sshIdentity: nil) { pwd in
            // Then: Should use verifiedLocalDirectory for new local sessions
            XCTAssertEqual(pwd, "/Users/local")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func testAsyncInitialDirectory_NoConductor_NoLocalDirectory_UsesEnvPWD() {
        // Given
        mockDelegate.sshIdentityProvider = nil
        mockDelegate.environmentPWD = "/env/pwd"
        let provider = MockWorkingDirectoryProvider()
        provider.asyncResult = nil
        mockDelegate.workingDirectoryProvider = provider

        let expectation = self.expectation(description: "completion called")

        // When
        tracker.asyncInitialDirectoryForNewSessionBasedOnCurrentDirectory(sshIdentity: nil) { pwd in
            // Then
            XCTAssertEqual(pwd, "/env/pwd")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - 8. SSH Identity Tests (Phase 2 Bug Fix)

    func testAsyncInitialDirectory_LocalSessionToSSHSession_ReturnsNil() {
        // Given: Current session is local with a local directory
        mockDelegate.sshIdentityProvider = nil
        tracker.setLastDirectory("/Users/local", remote: false, pushed: true)
        // lastDirectorySSHIdentity should be nil since it's a local directory

        let sshIdentity = SSHIdentity(host: "Remote", hostname: "remote.example.com", username: "user", port: 22)
        let expectation = self.expectation(description: "completion called")

        // When: Creating an SSH session
        tracker.asyncInitialDirectoryForNewSessionBasedOnCurrentDirectory(sshIdentity: sshIdentity) { pwd in
            // Then: Should NOT pass the local directory to SSH session
            XCTAssertNil(pwd)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func testAsyncInitialDirectory_SSHSessionToSameSSHSession_ReturnsDirectory() {
        // Given: Current session is SSH with a remote directory
        let sshIdentity = SSHIdentity(host: "Remote", hostname: "remote.example.com", username: "user", port: 22)

        // Set up the mock SSH identity provider BEFORE calling setLastDirectory
        // so that lastDirectorySSHIdentity gets set correctly
        mockDelegate.sshIdentityProvider = MockSSHIdentityProvider(sshIdentity: sshIdentity)

        tracker.setLastDirectory("/home/user", remote: true, pushed: true)

        let expectation = self.expectation(description: "completion called")

        // When: Creating another SSH session to the SAME host
        tracker.asyncInitialDirectoryForNewSessionBasedOnCurrentDirectory(sshIdentity: sshIdentity) { pwd in
            // Then: Should return the directory since SSH identities match
            XCTAssertEqual(pwd, "/home/user")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func testAsyncInitialDirectory_SSHSessionToDifferentSSHSession_ReturnsNil() {
        // Given: Current session has a directory from one SSH host
        let currentSSHIdentity = SSHIdentity(host: "Remote", hostname: "remote.example.com", username: "user", port: 22)
        mockDelegate.sshIdentityProvider = MockSSHIdentityProvider(sshIdentity: currentSSHIdentity)
        tracker.setLastDirectory("/home/user", remote: true, pushed: true)

        // New session is to a DIFFERENT SSH host
        let differentSSHIdentity = SSHIdentity(host: "Other", hostname: "other.example.com", username: "user", port: 22)
        let expectation = self.expectation(description: "completion called")

        // When
        tracker.asyncInitialDirectoryForNewSessionBasedOnCurrentDirectory(sshIdentity: differentSSHIdentity) { pwd in
            // Then: Should NOT pass directory from different SSH host
            XCTAssertNil(pwd)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func testAsyncInitialDirectory_LocalSessionToLocalSession_ReturnsDirectory() {
        // Given: Simulate a poller result to set verifiedLocalDirectory
        mockDelegate.sshIdentityProvider = nil
        pollerFound("/Users/local", invalidated: false)

        let expectation = self.expectation(description: "completion called")

        // When: Creating a local session (nil SSH identity)
        tracker.asyncInitialDirectoryForNewSessionBasedOnCurrentDirectory(sshIdentity: nil) { pwd in
            // Then: Should return the verified local directory
            XCTAssertEqual(pwd, "/Users/local")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func testAsyncInitialDirectory_OSC7WithoutHostname_UsesPolledNotPushed() {
        // This tests the bug fix for issue 12616: When SSHed to a remote server
        // and the remote shell sends OSC 7 without a hostname (e.g., fish),
        // new local sessions should use the verified local directory, not the
        // pushed (remote) directory that was incorrectly treated as local.

        // Given: Remote shell pushed a directory via OSC 7 (treated as local because no hostname)
        tracker.setLastDirectory("/home/remote/path", remote: false, pushed: true)
        // But the poller knows the real local directory
        pollerFound("/Users/local/path", invalidated: false)

        let expectation = self.expectation(description: "completion called")

        // When: Creating a new local session
        tracker.asyncInitialDirectoryForNewSessionBasedOnCurrentDirectory(sshIdentity: nil) { pwd in
            // Then: Should use the verified local directory, not the pushed remote one
            XCTAssertEqual(pwd, "/Users/local/path")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - 9. Host Recording Tests

    func testRecordLastRemoteHost_AddsToHistory() {
        // Given
        let host = VT100RemoteHost(username: "user", hostname: "test.com")

        // When
        tracker.recordLastRemoteHost(host)

        // Then
        XCTAssertEqual(tracker.hosts.count, 1)
        XCTAssertTrue(tracker.lastRemoteHost?.isEqual(toRemoteHost: host) ?? false)
    }

    func testRecordLastRemoteHost_Nil_DoesNotAddToHistory() {
        // When
        tracker.recordLastRemoteHost(nil)

        // Then
        XCTAssertTrue(tracker.hosts.isEmpty)
        XCTAssertNil(tracker.lastRemoteHost)
    }

    // MARK: - 10. Delegate Callback Tests

    func testLocalFileCheckerUpdate() {
        // When
        tracker.setLastDirectory("/Users/test", remote: false, pushed: true)

        // Then
        XCTAssertTrue(mockDelegate.didChangeLocalDirectoryCalled)
        XCTAssertEqual(mockDelegate.lastChangedLocalDirectory, "/Users/test")
    }

    // MARK: - 11. Edge Case Tests

    func testWeakDelegate_NoRetainCycle() {
        // Given
        var delegate: MockDirectoryTrackerDelegate? = MockDirectoryTrackerDelegate()
        tracker.delegate = delegate

        // When
        delegate = nil

        // Then
        XCTAssertNil(tracker.delegate)
    }

    func testEmptyDirectoryString() {
        // When
        tracker.setLastDirectory("", remote: false, pushed: true)

        // Then: empty string is treated as valid directory
        XCTAssertEqual(tracker.lastDirectory, "")
        XCTAssertEqual(tracker.lastLocalDirectory, "")
        XCTAssertTrue(tracker.directories.contains(""))
    }
}
