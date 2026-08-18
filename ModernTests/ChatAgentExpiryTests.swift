//
//  ChatAgentExpiryTests.swift
//  iTerm2 ModernTests
//
//  Phase 4: classifying an unusable Responses-API previous_response_id error, the
//  trigger for retrying a turn as a full stateless replay from blobs. Kept
//  deliberately narrow so a generic 4xx is never misread as an expiry and silently
//  retried against the model.
//

import XCTest
@testable import iTerm2SharedARC

final class ChatAgentExpiryTests: XCTestCase {
    private func isExpiry(_ s: String) -> Bool {
        ChatAgent.isUnusablePreviousResponseIDError(AIError(s))
    }

    func test_expiry_previousResponseNotFound() {
        XCTAssertTrue(isExpiry("Error from OpenAI: Previous response with id 'resp_abc123' not found."))
    }

    func test_expiry_previousResponseIdDoesNotExist() {
        XCTAssertTrue(isExpiry("Error from OpenAI: The previous_response_id you provided does not exist."))
    }

    func test_expiry_expiredWording() {
        XCTAssertTrue(isExpiry("Error from OpenAI: previous response resp_x has expired"))
    }

    /// A generic failure that happens to mention "response" must NOT be treated as an
    /// expiry (that would silently retry a real error).
    func test_notExpiry_genericServerError() {
        XCTAssertFalse(isExpiry("Error from OpenAI: Rate limit exceeded. Please try again later."))
        XCTAssertFalse(isExpiry("Error from OpenAI: The response was empty."))
        XCTAssertFalse(isExpiry("Error from OpenAI: Invalid API key provided."))
    }

    /// "not found" about something OTHER than the previous response is not an expiry.
    func test_notExpiry_otherNotFound() {
        XCTAssertFalse(isExpiry("Error from OpenAI: Model 'gpt-foo' not found."))
        XCTAssertFalse(isExpiry("Error from OpenAI: Vector store not found."))
    }
}
