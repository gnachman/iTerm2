//
//  ExplanationResponseParserTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

final class ExplanationResponseParserTests: XCTestCase {
    private func makeRequest() throws -> AIExplanationRequest {
        let located = iTermCodableLocatedString(iTermLocatedString(string: "", gridCoords: GridCoordArray()))
        let locatedJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(located))
        let json: [String: Any] = [
            "truncated": false,
            "originalString": locatedJSON,
            "question": "",
            "subjectMatter": "",
            "context": ["sessionID": "test", "baseOffset": 0]
        ]
        return try JSONDecoder().decode(AIExplanationRequest.self,
                                        from: JSONSerialization.data(withJSONObject: json))
    }

    func testWellFormedResponseIsExtracted() throws {
        var response = ExplanationResponse(request: try makeRequest())
        let update = response.append("<response>hello &amp; bye</response>", final: true)
        XCTAssertEqual(update.mainResponse, "hello & bye")
    }

    // The body used to be read with indices from before the block was cut
    // out of the buffer, which returned the wrong text when anything
    // surrounded it.
    func testResponseSurroundedByTextIsExtracted() throws {
        var response = ExplanationResponse(request: try makeRequest())
        let update = response.append("preamble <response>body</response> trailing", final: true)
        XCTAssertEqual(update.mainResponse, "body")
        XCTAssertEqual(response.unparsed, "preamble  trailing")
    }

    // A closing tag before the opening tag used to produce a backwards range
    // and trap.
    func testClosingTagBeforeOpeningTagDoesNotCrash() throws {
        var response = ExplanationResponse(request: try makeRequest())
        let first = response.append("junk</response> more <response>body", final: false)
        XCTAssertNil(first.mainResponse)
        let second = response.append("</response>", final: true)
        XCTAssertEqual(second.mainResponse, "body")
    }
}
