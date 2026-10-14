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
    var foregroundProcessGroup: pid_t = -1

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

    func directoryTrackerForegroundProcessGroup(_ tracker: iTermSessionDirectoryTracker) -> pid_t {
        return foregroundProcessGroup
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

    // MARK: - 5b. Plain ssh: local poll must not clobber the remote path (QA F-103)

    // Foreground process groups of the session's local terminal.
    private let shellGroup: pid_t = 100     // The session's shell (or login's child).
    private let subshellGroup: pid_t = 150  // e.g. `bash` run from the login shell.
    private let sshGroup: pid_t = 200       // ssh, talking to a remote shell.

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

    private func poll(_ dir: String, invalidated: Bool = false) {
        tracker.workingDirectoryPollerDidFindWorkingDirectory(dir, invalidated: invalidated)
    }

    func testPollerResult_AfterRemotePush_DoesNotChangeSessionPath() {
        mockDelegate.foregroundProcessGroup = sshGroup
        pushRemoteDirectory("/tmp/qa125")

        // The poller reports the local ssh process's cwd (e.g. after a key press
        // and a line feed), arriving after the remote push.
        poll("/Users/local")

        XCTAssertEqual(sessionPath, "/tmp/qa125")
        XCTAssertEqual(tracker.lastDirectory, "/tmp/qa125")
        // The local directory is still tracked for session restoration.
        XCTAssertEqual(tracker.lastLocalDirectory, "/Users/local")
    }

    // The poller reads the login shell's cwd, which can't change under ssh, but
    // even a different value must not replace the remote directory while ssh runs.
    func testPollerResult_WhileSSHRuns_DoesNotChangeSessionPath() {
        mockDelegate.foregroundProcessGroup = sshGroup
        pushRemoteDirectory("/tmp/qa125")
        poll("/Users/local")
        poll("/Users/local")
        poll("/a")

        XCTAssertEqual(sessionPath, "/tmp/qa125")
        XCTAssertEqual(tracker.lastDirectory, "/tmp/qa125")
    }

    func testInvalidatedPollerResult_AfterRemotePush_DoesNotChangeSessionPath() {
        mockDelegate.foregroundProcessGroup = sshGroup
        pushRemoteDirectory("/tmp/qa125")
        mockDelegate.foregroundProcessGroup = shellGroup

        poll("/Users/local", invalidated: true)
        poll("/usr", invalidated: true)

        XCTAssertEqual(sessionPath, "/tmp/qa125")
        XCTAssertEqual(tracker.lastDirectory, "/tmp/qa125")
        XCTAssertEqual(tracker.lastLocalDirectory, "/usr")
    }

    func testPollLocalDirectoryOnly_AfterRemotePush_DoesNotChangeSessionPath() {
        let provider = MockWorkingDirectoryProvider()
        provider.asyncResult = "/Users/local"
        mockDelegate.workingDirectoryProvider = provider
        mockDelegate.foregroundProcessGroup = shellGroup
        pushRemoteDirectory("/tmp/qa125")
        mockDelegate.foregroundProcessGroup = shellGroup + 1

        tracker.pollLocalDirectoryOnly()

        XCTAssertTrue(provider.getWorkingDirectoryAsyncCalled)
        XCTAssertEqual(tracker.lastLocalDirectory, "/Users/local")
        XCTAssertEqual(sessionPath, "/tmp/qa125")
    }

    // When the profile's command is ssh itself, ssh is the session's root process
    // and always in the foreground.
    func testPollerResult_SSHIsSessionCommand_DoesNotChangeSessionPath() {
        mockDelegate.foregroundProcessGroup = shellGroup
        pushRemoteDirectory("/tmp/qa125")
        poll("/Users/local")
        poll("/Users/local")

        XCTAssertEqual(sessionPath, "/tmp/qa125")
    }

    // ssh to a host, then ssh again from there: the local foreground job is the
    // outer ssh throughout.
    func testPollerResult_NestedSSH_KeepsRemotePathUntilOuterSSHExits() {
        mockDelegate.foregroundProcessGroup = sshGroup
        pushRemoteDirectory("/tmp/qa125")
        pushRemoteDirectory("/tmp/qb")
        poll("/Users/local")
        XCTAssertEqual(sessionPath, "/tmp/qb")

        // The inner ssh exits.
        pushRemoteDirectory("/tmp/qa125")
        poll("/Users/local")
        XCTAssertEqual(sessionPath, "/tmp/qa125")

        // The outer ssh exits.
        mockDelegate.foregroundProcessGroup = shellGroup
        poll("/Users/local")
        XCTAssertEqual(sessionPath, "/Users/local")
    }

    // `ssh A; ssh B` with no poll in between: B's first OSC 7 continues A's
    // remote stretch, so a poll while B runs goes local until B's next prompt
    // records B's group.
    func testPollerResult_SecondSSHBeforeAnyPoll_HealsAtNextRemotePush() {
        mockDelegate.foregroundProcessGroup = sshGroup
        pushRemoteDirectory("/tmp/qa125")
        mockDelegate.foregroundProcessGroup = sshGroup + 1
        pushRemoteDirectory("/tmp/qb")
        poll("/Users/local")
        XCTAssertEqual(sessionPath, "/Users/local")

        pushRemoteDirectory("/tmp/qb")
        poll("/Users/local")
        XCTAssertEqual(sessionPath, "/tmp/qb")
    }

    // ssh suspended with ~^Z gives the terminal back to the shell. After `fg` the
    // remote directory returns with the remote shell's next prompt.
    func testPollerResult_SuspendedSSH_GoesLocalUntilNextRemotePush() {
        mockDelegate.foregroundProcessGroup = sshGroup
        pushRemoteDirectory("/tmp/qa125")
        mockDelegate.foregroundProcessGroup = shellGroup
        poll("/Users/local")
        XCTAssertEqual(sessionPath, "/Users/local")

        mockDelegate.foregroundProcessGroup = sshGroup
        poll("/Users/local")
        XCTAssertEqual(sessionPath, "/Users/local")

        pushRemoteDirectory("/tmp/qa125")
        poll("/Users/local")
        XCTAssertEqual(sessionPath, "/tmp/qa125")
    }

    // If the foreground group could not be read at the first push, a later push in
    // the same remote stretch records it.
    func testPollerResult_ForegroundGroupReadableOnLaterPush_KeepsRemotePath() {
        mockDelegate.foregroundProcessGroup = -1
        pushRemoteDirectory("/tmp/qa125")
        mockDelegate.foregroundProcessGroup = sshGroup
        pushRemoteDirectory("/tmp/qb")

        poll("/Users/local")

        XCTAssertEqual(sessionPath, "/tmp/qb")
    }

    // MARK: - 5c. Exit from plain ssh to a local shell without shell integration (QA F-134, F-138)

    func testPollerResult_ChangesAfterExit_UpdatesSessionPath() {
        mockDelegate.foregroundProcessGroup = sshGroup
        pushRemoteDirectory("/tmp/qa125")
        poll("/Users/local")
        XCTAssertEqual(sessionPath, "/tmp/qa125")

        // `exit` from ssh, then `cd /usr` in the local shell.
        mockDelegate.foregroundProcessGroup = shellGroup
        poll("/usr")

        XCTAssertEqual(sessionPath, "/usr")
        XCTAssertEqual(tracker.lastDirectory, "/usr")
        XCTAssertEqual(tracker.lastLocalDirectory, "/usr")

        // Later local cds keep updating the path.
        poll("/etc")
        XCTAssertEqual(sessionPath, "/etc")
        XCTAssertEqual(tracker.lastDirectory, "/etc")
    }

    // `ssh qaremote`, `cd /tmp/qa125`, `exit`, Return: the local shell is back in
    // the foreground in the directory it ssh'ed from, so the poll result equals
    // the one seen while ssh ran. It must still become the current directory.
    func testPollerResult_ExitWithoutCd_UpdatesSessionPath() {
        mockDelegate.foregroundProcessGroup = sshGroup
        pushRemoteDirectory("/tmp/qa125")
        poll("/Users/local")
        XCTAssertEqual(sessionPath, "/tmp/qa125")

        mockDelegate.foregroundProcessGroup = shellGroup
        poll("/Users/local")

        XCTAssertEqual(sessionPath, "/Users/local")
        XCTAssertEqual(tracker.lastDirectory, "/Users/local")
    }

    // ssh exits before the first poll after the last remote push.
    func testPollerResult_ExitBeforeFirstPollAfterRemotePush_UpdatesSessionPath() {
        mockDelegate.foregroundProcessGroup = sshGroup
        pushRemoteDirectory("/tmp/qa125")

        mockDelegate.foregroundProcessGroup = shellGroup
        poll("/Users/local")

        XCTAssertEqual(sessionPath, "/Users/local")
    }

    // Right after ssh exits, its process group may be gone before the shell takes
    // the terminal back, which reads as no foreground group.
    func testPollerResult_ForegroundGroupGone_UpdatesSessionPath() {
        mockDelegate.foregroundProcessGroup = sshGroup
        pushRemoteDirectory("/tmp/qa125")

        mockDelegate.foregroundProcessGroup = -1
        poll("/Users/local")

        XCTAssertEqual(sessionPath, "/Users/local")
    }

    // An OSC 7 processed after ssh already gave the terminal back belongs to the
    // same remote stretch, which ssh started.
    func testPollerResult_LateRemotePushAfterExit_UpdatesSessionPath() {
        mockDelegate.foregroundProcessGroup = sshGroup
        pushRemoteDirectory("/tmp/qa125")
        mockDelegate.foregroundProcessGroup = shellGroup
        pushRemoteDirectory("/tmp/qa125")

        poll("/Users/local")

        XCTAssertEqual(sessionPath, "/Users/local")
    }

    // The ssh that ended an earlier remote stretch has nothing to do with the next.
    func testPollerResult_NextSSH_KeepsItsRemotePath() {
        mockDelegate.foregroundProcessGroup = sshGroup
        pushRemoteDirectory("/tmp/qa125")
        mockDelegate.foregroundProcessGroup = shellGroup
        poll("/Users/local")
        XCTAssertEqual(sessionPath, "/Users/local")

        mockDelegate.foregroundProcessGroup = sshGroup + 1
        pushRemoteDirectory("/tmp/qb")
        poll("/Users/local")
        XCTAssertEqual(sessionPath, "/tmp/qb")

        mockDelegate.foregroundProcessGroup = shellGroup
        poll("/Users/local")
        XCTAssertEqual(sessionPath, "/Users/local")
    }

    // MARK: - 5d. ssh from a local subshell (QA F-141)

    // `bash` in the login shell, then `ssh qaremote`, `cd /tmp/qa125`, `exit`.
    // bash, not the polled login shell, is back in the foreground. The poller
    // still reads the login shell's cwd, which didn't change.
    func testPollerResult_ExitToSubshell_UpdatesSessionPath() {
        mockDelegate.foregroundProcessGroup = sshGroup
        pushRemoteDirectory("/tmp/qa125")
        poll("/Users/local")
        XCTAssertEqual(sessionPath, "/tmp/qa125")

        mockDelegate.foregroundProcessGroup = subshellGroup
        poll("/Users/local")
        XCTAssertEqual(sessionPath, "/Users/local")
        XCTAssertEqual(tracker.lastDirectory, "/Users/local")

        // Exiting the subshell leaves it local.
        mockDelegate.foregroundProcessGroup = shellGroup
        poll("/Users/local")
        XCTAssertEqual(sessionPath, "/Users/local")
    }

    // MARK: - 5e. tmux integration panes (QA F-142)

    // A tmux integration pane has no local terminal whose foreground can be read,
    // so nothing holds the remote directory: the poll result (tmux's
    // pane_current_path) becomes current, as in 3.7.4.
    func testPollerResult_NoForegroundGroup_FirstLocalCdUpdatesSessionPath() {
        mockDelegate.foregroundProcessGroup = -1
        pushRemoteDirectory("/tmp/qa125")

        // `exit`, then `cd /usr`: the first poll after the push reports /usr.
        poll("/usr")
        XCTAssertEqual(sessionPath, "/usr")
        XCTAssertEqual(tracker.lastDirectory, "/usr")

        poll("/tmp/qb")
        XCTAssertEqual(sessionPath, "/tmp/qb")
    }

    func testPollerResult_NoForegroundGroup_ExitWithoutCdUpdatesSessionPath() {
        mockDelegate.foregroundProcessGroup = -1
        pushRemoteDirectory("/tmp/qa125")

        poll("/Users/local")

        XCTAssertEqual(sessionPath, "/Users/local")
    }

    // MARK: - 5f. Restored sessions

    private func restoredTracker() -> iTermSessionDirectoryTracker {
        let encoder = iTermMutableDictionaryEncoderAdapter.encoder()
        tracker.encodeArrangement(with: encoder)
        let restored = iTermSessionDirectoryTracker(variablesScope: mockScope)
        restored.delegate = mockDelegate
        restored.restoreFromArrangement(encoder.mutableDictionary as! [String: Any])
        mockScope.setValue(restored.lastDirectory, forVariableNamed: iTermVariableKeySessionPath)
        tracker = restored
        return restored
    }

    // A session whose ssh job survives a relaunch (restored from a running server)
    // keeps its remote path while ssh runs and goes local when it exits.
    func testRestoredRemoteDirectory_SSHStillRunning_KeepsRemotePathUntilExit() {
        poll("/Users/local")
        mockDelegate.foregroundProcessGroup = sshGroup
        pushRemoteDirectory("/tmp/qa125")
        let restored = restoredTracker()

        poll("/Users/local")
        XCTAssertEqual(sessionPath, "/tmp/qa125")
        XCTAssertEqual(restored.lastDirectory, "/tmp/qa125")
        XCTAssertEqual(restored.lastLocalDirectory, "/Users/local")

        mockDelegate.foregroundProcessGroup = shellGroup
        poll("/Users/local")
        XCTAssertEqual(sessionPath, "/Users/local")
    }

    // Restored without its job (a new shell): the saved group is not in the
    // foreground, so the first poll replaces the remote path.
    func testRestoredRemoteDirectory_NewShell_UpdatesSessionPath() {
        mockDelegate.foregroundProcessGroup = sshGroup
        pushRemoteDirectory("/tmp/qa125")
        _ = restoredTracker()

        mockDelegate.foregroundProcessGroup = shellGroup + 1000
        poll("/Users/local")

        XCTAssertEqual(sessionPath, "/Users/local")
    }

    // Arrangements from builds that did not save the remote foreground group
    // behave as 3.7.4 did: a poll replaces the path.
    func testRestoredLegacyRemoteDirectory_PollerResult_UpdatesSessionPath() {
        let arrangement: [String: Any] = [
            "Last Directory": "/tmp/qa125",
            "Last Local Directory": "/Users/local",
            "Last Local Directory Was Pushed": false,
            "Should Expect Current Dir Updates": true,
            "Working Directory Poller Disabled": true,
        ]
        tracker.restoreFromArrangement(arrangement)
        mockScope.setValue("/tmp/qa125", forVariableNamed: iTermVariableKeySessionPath)
        mockDelegate.foregroundProcessGroup = sshGroup

        poll("/Users/local")

        XCTAssertEqual(sessionPath, "/Users/local")
    }

    // Arrangements that say the directory is remote but have no foreground group.
    func testRestoredRemoteDirectory_NoSavedGroup_UpdatesSessionPath() {
        let arrangement: [String: Any] = [
            "Last Directory": "/tmp/qa125",
            "Last Directory Is Remote": true,
            "Last Local Directory": "/Users/local",
            "Last Local Directory Was Pushed": false,
            "Should Expect Current Dir Updates": true,
            "Working Directory Poller Disabled": true,
        ]
        tracker.restoreFromArrangement(arrangement)
        mockScope.setValue("/tmp/qa125", forVariableNamed: iTermVariableKeySessionPath)
        mockDelegate.foregroundProcessGroup = sshGroup

        poll("/Users/local")

        XCTAssertEqual(sessionPath, "/Users/local")
    }

    func testPollerResult_AfterLocalPush_DoesNotChangeSessionPath() {
        tracker.screenLogWorkingDirectory(onAbsoluteLine: 1,
                                          remoteHost: nil,
                                          withDirectory: "/pushed",
                                          pushType: .strongPush,
                                          accepted: true)
        tracker.screenDidChangeCurrentDirectory()

        poll("/Users/local")
        poll("/usr")

        XCTAssertEqual(sessionPath, "/pushed")
        XCTAssertEqual(tracker.lastDirectory, "/pushed")
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
        // Given: Simulate a poller result to set polledLocalDirectory
        tracker.workingDirectoryPollerDidFindWorkingDirectory("/Users/cached", invalidated: false)
        let provider = MockWorkingDirectoryProvider()
        mockDelegate.workingDirectoryProvider = provider

        let expectation = self.expectation(description: "completion called")

        // When
        tracker.asyncCurrentLocalWorkingDirectory { pwd in
            // Then: Should use polledLocalDirectory, not fetch again
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
        // Given: Simulate a poller result to set polledLocalDirectory
        mockDelegate.sshIdentityProvider = nil
        tracker.workingDirectoryPollerDidFindWorkingDirectory("/Users/local", invalidated: false)

        let expectation = self.expectation(description: "completion called")

        // When
        tracker.asyncInitialDirectoryForNewSessionBasedOnCurrentDirectory(sshIdentity: nil) { pwd in
            // Then: Should use polledLocalDirectory for new local sessions
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
        // Given: Simulate a poller result to set polledLocalDirectory
        mockDelegate.sshIdentityProvider = nil
        tracker.workingDirectoryPollerDidFindWorkingDirectory("/Users/local", invalidated: false)

        let expectation = self.expectation(description: "completion called")

        // When: Creating a local session (nil SSH identity)
        tracker.asyncInitialDirectoryForNewSessionBasedOnCurrentDirectory(sshIdentity: nil) { pwd in
            // Then: Should return the polled local directory
            XCTAssertEqual(pwd, "/Users/local")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func testAsyncInitialDirectory_OSC7WithoutHostname_UsesPolledNotPushed() {
        // This tests the bug fix for issue 12616: When SSHed to a remote server
        // and the remote shell sends OSC 7 without a hostname (e.g., fish),
        // new local sessions should use the polled local directory, not the
        // pushed (remote) directory that was incorrectly treated as local.

        // Given: Remote shell pushed a directory via OSC 7 (treated as local because no hostname)
        tracker.setLastDirectory("/home/remote/path", remote: false, pushed: true)
        // But the poller knows the real local directory
        tracker.workingDirectoryPollerDidFindWorkingDirectory("/Users/local/path", invalidated: false)

        let expectation = self.expectation(description: "completion called")

        // When: Creating a new local session
        tracker.asyncInitialDirectoryForNewSessionBasedOnCurrentDirectory(sshIdentity: nil) { pwd in
            // Then: Should use the polled local directory, not the pushed remote one
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
