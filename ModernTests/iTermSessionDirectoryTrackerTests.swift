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

    @objc var getWorkingDirectory: String? {
        getWorkingDirectoryCalled = true
        return syncResult
    }

    @objc func getWorkingDirectory(completion: @escaping (String?) -> Void) {
        getWorkingDirectoryAsyncCalled = true
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
        tracker.workingDirectoryPollerDidFindWorkingDirectory("/Users/test", invalidated: false)

        // Then
        XCTAssertEqual(mockDelegate.createMarkDirectory, "/Users/test")
    }

    func testPollerResult_Invalidated_DoesNotCreateMark() {
        // Given
        tracker.workingDirectoryPollerDisabled = false
        tracker.shouldExpectCurrentDirUpdates = false

        // When
        tracker.workingDirectoryPollerDidFindWorkingDirectory("/Users/test", invalidated: true)

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
        tracker.workingDirectoryPollerDidFindWorkingDirectory("/Users/polled", invalidated: true)

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
        tracker.workingDirectoryPollerDidFindWorkingDirectory("/Users/test", invalidated: false)

        // Then
        XCTAssertNil(mockDelegate.createMarkDirectory)
    }

    func testPollerResult_ShellIntegrationUsed_DoesNotCreateMark() {
        // Given
        tracker.shouldExpectCurrentDirUpdates = true
        mockDelegate.escapeSequencesDisabled = false

        // When
        tracker.workingDirectoryPollerDidFindWorkingDirectory("/Users/test", invalidated: false)

        // Then
        XCTAssertNil(mockDelegate.createMarkDirectory)
    }

    func testPollerResult_ShellIntegrationUsed_ButEscapeSequencesDisabled_CreatesMarkWhenAllowed() {
        // Given
        tracker.shouldExpectCurrentDirUpdates = true
        mockDelegate.escapeSequencesDisabled = true
        tracker.workingDirectoryPollerDisabled = false

        // When
        tracker.workingDirectoryPollerDidFindWorkingDirectory("/Users/test", invalidated: false)

        // Then
        XCTAssertEqual(mockDelegate.createMarkDirectory, "/Users/test")
    }

    func testPollerResult_NilDirectory_DoesNotCreateMark() {
        // Given: valid conditions
        tracker.workingDirectoryPollerDisabled = false
        tracker.shouldExpectCurrentDirUpdates = false

        // When
        tracker.workingDirectoryPollerDidFindWorkingDirectory(nil, invalidated: false)

        // Then
        XCTAssertNil(mockDelegate.createMarkDirectory)
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

    // MARK: - 7. Async Directory Fetching Tests

    func testAsyncCurrentLocalWorkingDirectory_CachedValue() {
        // Given
        tracker.setLastDirectory("/Users/cached", remote: false, pushed: true)
        let provider = MockWorkingDirectoryProvider()
        mockDelegate.workingDirectoryProvider = provider

        let expectation = self.expectation(description: "completion called")

        // When
        tracker.asyncCurrentLocalWorkingDirectory { pwd in
            // Then
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
        // Given
        mockDelegate.sshIdentityProvider = nil
        tracker.setLastDirectory("/Users/local", remote: false, pushed: true)

        let expectation = self.expectation(description: "completion called")

        // When
        tracker.asyncInitialDirectoryForNewSessionBasedOnCurrentDirectory(sshIdentity: nil) { pwd in
            // Then
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
        // Given: Current session is local with a local directory
        mockDelegate.sshIdentityProvider = nil
        tracker.setLastDirectory("/Users/local", remote: false, pushed: true)

        let expectation = self.expectation(description: "completion called")

        // When: Creating a local session (nil SSH identity)
        tracker.asyncInitialDirectoryForNewSessionBasedOnCurrentDirectory(sshIdentity: nil) { pwd in
            // Then: Should return the local directory
            XCTAssertEqual(pwd, "/Users/local")
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
