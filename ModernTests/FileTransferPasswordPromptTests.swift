//
//  FileTransferPasswordPromptTests.swift
//  ModernTests
//
//  An scp transfer asks for its password (or other keyboard-interactive answer)
//  from a background thread some time after it starts, possibly with nobody at
//  the Mac. These tests pin that the prompt is published for the companion app
//  with the password as a secret input, and that what the phone answers is what
//  the transfer gets.
//
//  Nothing is shown: the prompt runs as a headless modal (see
//  iTermWarning.setRunsHeadlessModals).
//

import XCTest
@testable import iTerm2SharedARC

final class FileTransferPasswordPromptTests: XCTestCase {
    private final class FakeFile: TransferrableFile {
        override func protocolName() -> String? { "secure copy" }
        override func authRequestor() -> String? { "example.com" }
    }

    override func setUp() {
        super.setUp()
        iTermWarning.setRunsHeadlessModals(true)
    }

    override func tearDown() {
        iTermWarning.cancelHeadlessModals()
        iTermWarning.setRunsHeadlessModals(false)
        super.tearDown()
    }

    private static func cancelHeadlessModals() {
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            iTermWarning.cancelHeadlessModals()
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    /// Asks for a password the way SCPFile does (from a main-queue block), lets
    /// `answer` see what was published and answer it, and returns what the
    /// transfer was given.
    private func promptAndAnswer(
        _ answer: (ModalAlertSnapshot, ModalAlertRegistry) async -> Bool
    ) async throws -> String {
        let registry = ModalAlertRegistry.shared
        let (changes, changesContinuation) = AsyncStream<Void>.makeStream()
        let token = registry.addObserver { changesContinuation.yield() }
        defer { _ = token }
        let (finished, finishedContinuation) = AsyncStream<String>.makeStream()

        DispatchQueue.main.async {
            FileTransferManager.sharedInstance().transferrableFile(FakeFile(), interactivePrompt: "password") {
                finishedContinuation.yield($0 ?? "(cancelled)")
            }
        }
        do {
            let snapshot = try await FrozenMainQueue.withFailsafe("the prompt to register") { () -> ModalAlertSnapshot in
                for await _ in changes {
                    if let top = registry.currentAlerts().last {
                        return top
                    }
                }
                throw CancellationError()
            }
            let accepted = await answer(snapshot, registry)
            XCTAssertTrue(accepted)
            if !accepted {
                Self.cancelHeadlessModals()
            }
            return try await FrozenMainQueue.withFailsafe("the prompt to return") {
                for await outcome in finished {
                    return outcome
                }
                throw CancellationError()
            }
        } catch {
            Self.cancelHeadlessModals()
            throw error
        }
    }

    func testPasswordEnteredOnThePhoneIsGivenToTheTransfer() async throws {
        let outcome = try await promptAndAnswer { snapshot, registry in
            XCTAssertTrue(snapshot.heading.contains("example.com"))
            XCTAssertTrue(snapshot.body.contains("password"))
            XCTAssertTrue(snapshot.body.contains("secure copy"))
            XCTAssertEqual(snapshot.inputs, [.init(id: "password", label: nil, kind: .secret, value: "")])
            XCTAssertFalse(snapshot.hasAccessory)
            XCTAssertTrue(snapshot.isAppModal)
            return await registry.answer(id: snapshot.id, buttonIndex: 0, suppress: false,
                                         inputs: ["password": "correct horse"])
        }
        XCTAssertEqual(outcome, "correct horse")
    }

    func testCancelFromThePhoneGivesTheTransferNothing() async throws {
        let outcome = try await promptAndAnswer { snapshot, registry in
            return await registry.answer(id: snapshot.id, buttonIndex: 1, suppress: false,
                                         inputs: ["password": "ignored"])
        }
        XCTAssertEqual(outcome, "(cancelled)")
    }

    /// The Password Manager button opens a window on the Mac, so the phone is
    /// not offered it and cannot press it.
    func testPasswordManagerButtonIsNotOfferedToThePhone() async throws {
        let outcome = try await promptAndAnswer { snapshot, registry in
            XCTAssertEqual(snapshot.buttons.map { $0.offered }, [true, true, false])
            XCTAssertEqual(snapshot.buttons.map { $0.isCancel }, [false, true, false])
            let refused = await registry.answer(id: snapshot.id, buttonIndex: 2, suppress: false)
            XCTAssertFalse(refused)
            return await registry.answer(id: snapshot.id, buttonIndex: 1, suppress: false)
        }
        XCTAssertEqual(outcome, "(cancelled)")
    }
}
