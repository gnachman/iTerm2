//
//  AppleIntelligenceLockoutTests.swift
//  iTerm2 ModernTests
//
//  An administrator can forbid all generative AI with the GenerativeAIAllowed
//  user default. Apple Intelligence runs on-device, so its requests never pass
//  through iTermAIClient.request (the backstop for remote LLMs), and nothing
//  stopped them: AI tab titles, AI chat, and the command safety check all kept
//  using the on-device model under the lockout (tangential finding T-28).
//  These tests pin that every Apple Intelligence entry point refuses before it
//  reaches the model.
//

import XCTest
import FoundationModels
import os
@testable import iTerm2SharedARC

@available(macOS 26, *)
@Generable
private struct LockoutTestTitle {
    var title: String
}

@MainActor
final class AppleIntelligenceLockoutTests: XCTestCase {
    private final class RecordingDelegate: AITermControllerDelegate {
        var choices: [String] = []
        var errors: [Error] = []
        var onError: (() -> Void)?
        func aitermControllerWillSendRequest(_ sender: AITermController) {}
        func aitermController(_ sender: AITermController, offerChoice: String) { choices.append(offerChoice) }
        func aitermController(_ sender: AITermController, didStreamUpdate update: String?) {}
        func aitermController(_ sender: AITermController, didStreamAttachment: LLM.Message.Attachment) {}
        func aitermController(_ sender: AITermController, didFailWithError error: Error) {
            errors.append(error)
            onError?()
        }
        func aitermControllerRequestRegistration(_ sender: AITermController,
                                                 completion: @escaping (AITermController.Registration) -> ()) {}
        func aitermController(_ sender: AITermController, didCreateVectorStore id: String, withName name: String) {}
        func aitermController(_ sender: AITermController, didFailToCreateVectorStoreWithError: Error) {}
        func aitermController(_ sender: AITermController, didUploadFileWithID id: String) {}
        func aitermController(_ sender: AITermController, didFailToUploadFileWithError error: Error) {}
        func aitermControllerDidAddFilesToVectorStore(_ sender: AITermController) {}
        func aitermControllerDidFailToAddFilesToVectorStore(_ sender: AITermController, error: Error) {}
        func aitermController(_ sender: AITermController, willInvokeFunction function: LLM.AnyFunction) {}
        func aitermControllerDidCancelOutstandingRequest(_ sender: AITermController) {}
    }

    private func assertRefusedByLockout(_ error: Error?, file: StaticString = #filePath, line: UInt = #line) {
        guard let runnerError = error as? AppleIntelligenceRunnerError,
              case .disallowedByAdministrator = runnerError else {
            XCTFail("expected the administrator lockout to refuse the request before it reached the model, got \(String(describing: error))",
                    file: file, line: line)
            return
        }
    }

    // MARK: - AppleIntelligenceRunner (the chokepoint)

    func testCompleteRefusesUnderLockout() async throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Apple Intelligence requires macOS 26")
        }
        pinAdvancedSetting("GenerativeAIAllowed", to: false)
        var thrown: Error?
        do {
            _ = try await AppleIntelligenceRunner.complete(system: "Reply with OK.", user: "Hello", maxTokens: 16)
        } catch {
            thrown = error
        }
        assertRefusedByLockout(thrown)
    }

    func testGenerateRefusesUnderLockout() async throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Apple Intelligence requires macOS 26")
        }
        pinAdvancedSetting("GenerativeAIAllowed", to: false)
        var thrown: Error?
        do {
            _ = try await AppleIntelligenceRunner.generate(system: "Name this.", user: "ls -l", as: LockoutTestTitle.self)
        } catch {
            thrown = error
        }
        assertRefusedByLockout(thrown)
    }

    func testGenerateTabTitleRefusesUnderLockout() async throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Apple Intelligence requires macOS 26")
        }
        pinAdvancedSetting("GenerativeAIAllowed", to: false)
        let progressCalls = OSAllocatedUnfairLock(initialState: 0)
        var thrown: Error?
        do {
            _ = try await AppleIntelligenceRunner.generateTabTitle(instructions: "Name this.",
                                                                   context: "",
                                                                   screen: "ls -l\ntotal 0",
                                                                   as: LockoutTestTitle.self,
                                                                   onProgress: { progressCalls.withLock { $0 += 1 } })
        } catch {
            thrown = error
        }
        assertRefusedByLockout(thrown)
        XCTAssertEqual(progressCalls.withLock { $0 }, 0, "no token-count or generation call may run under the lockout")
    }

    // The refusal is deterministic, so the tab-title generator must not treat
    // it as transient and retry the same screen every cadence tick.
    func testLockoutRefusalIsNotTransient() {
        XCTAssertFalse(AITabTitleGenerator.isTransientGenerationError(AppleIntelligenceRunnerError.disallowedByAdministrator))
    }

    // MARK: - AI tab titles

    func testTabTitlesAreOffUnderLockout() {
        pinAdvancedSetting("AiGeneratedTabTitles", to: true)
        pinAdvancedSetting("GenerativeAIAllowed", to: false)
        XCTAssertFalse(AITabTitleGenerator.isEnabled)
        let gen = AITabTitleGenerator.instance
        let guid = "t28-lockout-should-attempt"
        gen.forget(sessionID: guid)
        XCTAssertFalse(gen.shouldAttempt(forSessionID: guid))
        gen.forget(sessionID: guid)
    }

    func testTabTitlesStayOnWhenAllowed() {
        pinAdvancedSetting("AiGeneratedTabTitles", to: true)
        pinAdvancedSetting("GenerativeAIAllowed", to: true)
        XCTAssertTrue(AITabTitleGenerator.isEnabled)
    }

    // requestTitle builds the prompt context only once it has decided to run
    // the model, so an unbuilt context means no generation was started.
    func testRequestTitleStartsNoGenerationUnderLockout() {
        pinAdvancedSetting("AiGeneratedTabTitles", to: true)
        pinAdvancedSetting("GenerativeAIAllowed", to: false)
        let gen = AITabTitleGenerator.instance
        let guid = "t28-lockout-request-title"
        gen.forget(sessionID: guid)
        var contextBuilt = false
        var completed = false
        let ctx = AITabTitleContext(job: nil, commandLine: nil, atPrompt: true,
                                    lastCommand: nil, recentCommands: [], cwd: nil,
                                    user: nil, host: nil, text: "")
        gen.requestTitle(forSessionID: guid,
                         screen: "$ make\ncc -o foo foo.c\nlinking foo\n$ ./foo\nhello",
                         backgroundHistogram: [:], isAlternate: false, oscTitle: "",
                         context: { contextBuilt = true; return ctx }) { _ in
            completed = true
        }
        XCTAssertFalse(contextBuilt, "no generation may start under the lockout")
        XCTAssertFalse(completed)
        XCTAssertTrue(gen.canStartGenerationForTesting(sessionID: guid), "no generation may be left in flight")
        gen.forget(sessionID: guid)
    }

    // MARK: - AI chat and the command safety check (AITermController)

    func testAITermControllerAppleIntelligenceRefusesUnderLockout() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Apple Intelligence requires macOS 26")
        }
        pinAdvancedSetting("GenerativeAIAllowed", to: false)
        let controller = AITermController(
            registration: try XCTUnwrap(AITermController.Registration(apiKey: "test-key")))
        let delegate = RecordingDelegate()
        controller.delegate = delegate
        controller.providerOverride = LLMProvider(model: AIMetadata.recommendedAppleModel)
        let failed = expectation(description: "request fails")
        delegate.onError = { failed.fulfill() }

        controller.request(messages: [LLM.Message(role: .user, content: "Hello")], stream: false)
        wait(for: [failed], timeout: 5)

        XCTAssertEqual(delegate.choices, [], "no reply may come back under the lockout")
        XCTAssertEqual(delegate.errors.count, 1)
        // Exactly the lockout text: the controller refuses up front rather than
        // reporting the runner's refusal as an “Apple Intelligence error”.
        let message = delegate.errors.first?.localizedDescription
        XCTAssertEqual(message, AppleIntelligenceRunnerError.disallowedByAdministrator.localizedDescription)
    }
}
