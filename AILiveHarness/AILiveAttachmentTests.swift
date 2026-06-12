//
//  AILiveAttachmentTests.swift
//  iTerm2 AI live harness
//
//  The 96 live test methods that exercise the attachment matrix.
//  Each test method is a one-liner that resolves a (lane, kind) pair
//  from AttachmentMatrix and forwards to runAttachmentCase. The shared
//  runner bypasses LLMProvider.accepts(_:), feeds the fixture through
//  the per-vendor request builder, and asserts the actual outcome
//  matches the matrix expectation.
//
//  Naming: test_attachmentMatrix_<lane>_<kind>. The lane prefix lets
//  `tools/run_ai_live.sh attachmentMatrix_anthropic` filter to a single
//  vendor's column; `tools/run_ai_live.sh attachmentMatrix_imagePNG`
//  filters to a single MIME's row across lanes.
//

import XCTest
@testable import iTerm2SharedARC

extension AILiveHarness {

    // MARK: - Runner

    /// Drive one cell of the attachment matrix and assert the outcome.
    /// Loud failure on drift in either direction (expected accept but got
    /// 4xx; expected reject but got 200; etc.) so a vendor capability
    /// change immediately surfaces with an obvious fix instruction.
    func runAttachmentCase(lane: AttachmentLane,
                           kind: AILiveAttachmentKind,
                           file: StaticString = #file,
                           line: UInt = #line) throws {
        let expected = AttachmentMatrix.expectedOutcome(lane: lane, kind: kind)
        if case .skipped(let reason) = expected {
            throw XCTSkip("[\(lane.displayName)/\(kind.rawValue)] \(reason)")
        }

        let apiKey = try keyOrSkipForLane(lane)
        let model = try lane.resolveModel()
        let fixture = try AILiveAttachmentFixtures.make(kind)

        let attachment = LLM.Message.Attachment(
            inline: true,
            id: "matrix-\(kind.rawValue)",
            type: .file(.init(name: fixture.filename,
                              content: fixture.bytes,
                              mimeType: fixture.mime,
                              localPath: nil)))
        let messages = [
            LLM.Message(responseID: nil,
                        role: .user,
                        body: .multipart([
                            .text(fixture.prompt),
                            .attachment(attachment),
                        ]))
        ]

        throttle(forVendor: lane.keyVendor)

        let actual: ActualOutcome
        do {
            let result = try AILiveDriver.run(model: model,
                                              apiKey: apiKey,
                                              messages: messages,
                                              streaming: false,
                                              scenarioTag: "attachmentMatrix.\(kind.rawValue)",
                                              test: self)
            let probeMatched = fixture.acceptanceProbes.contains { needle in
                result.finalText.range(of: needle, options: .caseInsensitive) != nil
            }
            actual = .accepted(finalText: result.finalText,
                               probeMatched: probeMatched)
        } catch let error {
            let text = "\(error)"
            if let status = parseHTTPStatus(text), (400..<500).contains(status) {
                actual = .rejectedHTTP(status: status, message: text)
            } else {
                XCTFail("[\(lane.displayName)/\(kind.rawValue)] unexpected non-HTTP error: \(text)",
                        file: file, line: line)
                return
            }
        }

        switch (expected, actual) {
        case (.acceptsAndExtractsProbe, .accepted(_, true)):
            // Happy path. Quiet success.
            break
        case (.acceptsAndExtractsProbe, .accepted(let text, false)):
            XCTFail("""
                [\(lane.displayName)/\(kind.rawValue)] MATRIX DRIFT: vendor accepted the request \
                but response did not contain any acceptance probe \
                (\(fixture.acceptanceProbes)). Either the serializer regressed \
                (binary getting mangled?) or the probe phrasing needs to be widened. Response: \
                \(text.prefix(400))
                """, file: file, line: line)
        case (.acceptsAndExtractsProbe, .rejectedHTTP(let status, let msg)):
            XCTFail("""
                [\(lane.displayName)/\(kind.rawValue)] MATRIX DRIFT: vendor REJECTED what we \
                expected it to accept (HTTP \(status)). The vendor may have narrowed support, \
                or our serializer regressed to a shape they no longer accept. Update either \
                LLMProvider.supported* to drop this MIME, or fix the request builder. \
                Vendor said: \(msg.prefix(400))
                """, file: file, line: line)

        case (.rejectsAtHTTPLayer, .rejectedHTTP(_, _)):
            // Happy path. Quiet success.
            break
        case (.rejectsAtHTTPLayer, .accepted(let text, let probed)):
            XCTFail("""
                [\(lane.displayName)/\(kind.rawValue)] MATRIX DRIFT: vendor ACCEPTED what we \
                expected it to reject (probe matched: \(probed)). Likely the vendor added \
                support; consider widening LLMProvider.supported* for this MIME and updating \
                this matrix cell to .acceptsAndExtractsProbe. Response: \(text.prefix(400))
                """, file: file, line: line)

        case (.acceptsButGarbled, .accepted(_, false)):
            // Happy path. Vendor accepted the wire, but couldn't extract the
            // probe. This is what we expected from a lossyString-mangled
            // binary.
            break
        case (.acceptsButGarbled, .accepted(let text, true)):
            XCTFail("""
                [\(lane.displayName)/\(kind.rawValue)] MATRIX DRIFT: vendor extracted the probe \
                from a representation we expected to be garbled. Either the vendor is now \
                accepting a content type we treat as lossyString-fallback, or our serializer \
                started taking a non-fallback path. Consider updating this cell to \
                .acceptsAndExtractsProbe. Response: \(text.prefix(400))
                """, file: file, line: line)
        case (.acceptsButGarbled, .rejectedHTTP(let status, let msg)):
            XCTFail("""
                [\(lane.displayName)/\(kind.rawValue)] MATRIX DRIFT: vendor REJECTED what we \
                expected to be silently accepted as garbled text (HTTP \(status)). The vendor \
                may have started validating wrapped binary payloads. Consider updating this \
                cell to .rejectsAtHTTPLayer. Vendor said: \(msg.prefix(400))
                """, file: file, line: line)

        case (.skipped, _):
            // Already handled at the top of the function; unreachable.
            break
        }

        Self.report(lane: lane, kind: kind, expected: expected, actual: actual)
    }

    private enum ActualOutcome {
        case accepted(finalText: String, probeMatched: Bool)
        case rejectedHTTP(status: Int, message: String)
    }

    /// Parse the status code from an error string like:
    ///   "HTTP request failed with status 400."
    /// or the AILiveError.providerFailure(...) wrapping thereof. Returns
    /// nil if no status code pattern is present. Delegates to the shared
    /// implementation on AILiveHarness so the refusal scenario and the
    /// attachment matrix parse status codes identically.
    private func parseHTTPStatus(_ text: String) -> Int? {
        return AILiveHarness.httpStatusCode(inErrorText: text)
    }

    /// Lane-aware key resolver. Re-implements keyOrSkip without exposing
    /// the private Keys struct on AILiveHarness.
    private func keyOrSkipForLane(_ lane: AttachmentLane) throws -> String {
        // See AILiveHarness.configPath() for why /tmp.
        let configPath = "/tmp/iterm2-ai-live.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else {
            throw XCTSkip("Live AI harness config missing.")
        }
        let envKey: String
        switch lane.keyVendor {
        case "openai":    envKey = "OPENAI_API_KEY"
        case "anthropic": envKey = "ANTHROPIC_API_KEY"
        case "gemini":    envKey = "GEMINI_API_KEY"
        case "deepseek":  envKey = "DEEPSEEK_API_KEY"
        case "llama":
            throw XCTSkip("Llama lane has no live API wiring.")
        default:
            throw XCTSkip("Unknown vendor \(lane.keyVendor)")
        }
        let value = json[envKey] ?? ""
        if value.isEmpty {
            throw XCTSkip("No API key set for \(lane.keyVendor).")
        }
        return value
    }

    private static func report(lane: AttachmentLane,
                               kind: AILiveAttachmentKind,
                               expected: AttachmentExpectedOutcome,
                               actual: ActualOutcome) {
        let actualTag: String
        switch actual {
        case .accepted(_, true):  actualTag = "accept+probe"
        case .accepted(_, false): actualTag = "accept+noprobe"
        case .rejectedHTTP(let s, _): actualTag = "reject(\(s))"
        }
        let expectedTag: String
        switch expected {
        case .acceptsAndExtractsProbe: expectedTag = "accept+probe"
        case .rejectsAtHTTPLayer:      expectedTag = "reject"
        case .acceptsButGarbled:       expectedTag = "accept+noprobe"
        case .skipped:                 expectedTag = "skip"
        }
        print("[live] \(lane.displayName) \(kind.rawValue): expected=\(expectedTag) actual=\(actualTag)")
    }

    // MARK: - Static probe-fixture regeneration (opt-in)

    /// True when the live config opts into fixture regeneration.
    private func regenerateFixturesRequested() -> Bool {
        let configPath = "/tmp/iterm2-ai-live.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return false }
        return json["REGENERATE_ATTACHMENT_FIXTURES"] == "1"
    }

    /// Rewrites every regenerable probe fixture: the images (magic.png/heic/
    /// tiff, number.png) and the timestamp-bearing magic.pdf / magic.zip.
    /// Regenerating the pdf/zip changes their embedded timestamp, so this
    /// invalidates the pdf/zip cassettes; re-record them after. Normally
    /// skipped. Refresh after changing visualProbe / textProbe or a generator:
    ///   ITERM2_AI_LIVE_REGENERATE_ATTACHMENT_FIXTURES=1 \
    ///     tools/run_ai_live.sh test_regenerateProbeAttachmentFixtures
    func test_regenerateProbeAttachmentFixtures() throws {
        try XCTSkipUnless(regenerateFixturesRequested(),
                          "Opt-in. Set ITERM2_AI_LIVE_REGENERATE_ATTACHMENT_FIXTURES=1 to rewrite all probe fixtures.")
        let dir = try AILiveAttachmentFixtures.regenerateStaticProbeFixtures()
        print("[fixtures] regenerated all probe fixtures (images + pdf + zip) in \(dir)")
    }

    /// Re-freezes only the image probe fixtures (magic.png/heic/tiff,
    /// number.png), leaving the timestamped pdf/zip and their cassettes
    /// untouched. Use this when image encoders drift on a new OS. Run on the
    /// same host that records the cassettes so the bytes match:
    ///   ITERM2_AI_LIVE_REGENERATE_ATTACHMENT_FIXTURES=1 \
    ///     tools/run_ai_live.sh test_regenerateImageFixtures
    func test_regenerateImageFixtures() throws {
        try XCTSkipUnless(regenerateFixturesRequested(),
                          "Opt-in. Set ITERM2_AI_LIVE_REGENERATE_ATTACHMENT_FIXTURES=1 to rewrite the image fixtures.")
        let dir = try AILiveAttachmentFixtures.regenerateImageFixtures()
        print("[fixtures] regenerated image fixtures (magic.png/heic/tiff, number.png) in \(dir)")
    }

    // MARK: - 96 test methods
    //
    // Generated explicitly so xctest discovers each as a distinct
    // method, which means individual filters (e.g. test_attachmentMatrix_anthropic_imagePNG)
    // work directly with `tools/run_ai_live.sh`.

    // openaiChat (16)
    func test_attachmentMatrix_openaiChat_textPlain()        throws { try runAttachmentCase(lane: .openaiChat,      kind: .textPlain) }
    func test_attachmentMatrix_openaiChat_textMarkdown()     throws { try runAttachmentCase(lane: .openaiChat,      kind: .textMarkdown) }
    func test_attachmentMatrix_openaiChat_applicationJSON()  throws { try runAttachmentCase(lane: .openaiChat,      kind: .applicationJSON) }
    func test_attachmentMatrix_openaiChat_applicationXML()   throws { try runAttachmentCase(lane: .openaiChat,      kind: .applicationXML) }
    func test_attachmentMatrix_openaiChat_imageSVG()         throws { try runAttachmentCase(lane: .openaiChat,      kind: .imageSVG) }
    func test_attachmentMatrix_openaiChat_yamlAsUnknown()    throws { try runAttachmentCase(lane: .openaiChat,      kind: .yamlAsUnknown) }
    func test_attachmentMatrix_openaiChat_imagePNG()         throws { try runAttachmentCase(lane: .openaiChat,      kind: .imagePNG) }
    func test_attachmentMatrix_openaiChat_imageWEBP()        throws { try runAttachmentCase(lane: .openaiChat,      kind: .imageWEBP) }
    func test_attachmentMatrix_openaiChat_imageHEIC()        throws { try runAttachmentCase(lane: .openaiChat,      kind: .imageHEIC) }
    func test_attachmentMatrix_openaiChat_imageTIFF()        throws { try runAttachmentCase(lane: .openaiChat,      kind: .imageTIFF) }
    func test_attachmentMatrix_openaiChat_applicationPDF()   throws { try runAttachmentCase(lane: .openaiChat,      kind: .applicationPDF) }
    func test_attachmentMatrix_openaiChat_audioMPEG()        throws { try runAttachmentCase(lane: .openaiChat,      kind: .audioMPEG) }
    func test_attachmentMatrix_openaiChat_videoMP4()         throws { try runAttachmentCase(lane: .openaiChat,      kind: .videoMP4) }
    func test_attachmentMatrix_openaiChat_applicationDOCX()  throws { try runAttachmentCase(lane: .openaiChat,      kind: .applicationDOCX) }
    func test_attachmentMatrix_openaiChat_applicationZIP()   throws { try runAttachmentCase(lane: .openaiChat,      kind: .applicationZIP) }
    func test_attachmentMatrix_openaiChat_applicationOctet() throws { try runAttachmentCase(lane: .openaiChat,      kind: .applicationOctet) }

    // openaiResponses (16)
    func test_attachmentMatrix_openaiResponses_textPlain()        throws { try runAttachmentCase(lane: .openaiResponses, kind: .textPlain) }
    func test_attachmentMatrix_openaiResponses_textMarkdown()     throws { try runAttachmentCase(lane: .openaiResponses, kind: .textMarkdown) }
    func test_attachmentMatrix_openaiResponses_applicationJSON()  throws { try runAttachmentCase(lane: .openaiResponses, kind: .applicationJSON) }
    func test_attachmentMatrix_openaiResponses_applicationXML()   throws { try runAttachmentCase(lane: .openaiResponses, kind: .applicationXML) }
    func test_attachmentMatrix_openaiResponses_imageSVG()         throws { try runAttachmentCase(lane: .openaiResponses, kind: .imageSVG) }
    func test_attachmentMatrix_openaiResponses_yamlAsUnknown()    throws { try runAttachmentCase(lane: .openaiResponses, kind: .yamlAsUnknown) }
    func test_attachmentMatrix_openaiResponses_imagePNG()         throws { try runAttachmentCase(lane: .openaiResponses, kind: .imagePNG) }
    func test_attachmentMatrix_openaiResponses_imageWEBP()        throws { try runAttachmentCase(lane: .openaiResponses, kind: .imageWEBP) }
    func test_attachmentMatrix_openaiResponses_imageHEIC()        throws { try runAttachmentCase(lane: .openaiResponses, kind: .imageHEIC) }
    func test_attachmentMatrix_openaiResponses_imageTIFF()        throws { try runAttachmentCase(lane: .openaiResponses, kind: .imageTIFF) }
    func test_attachmentMatrix_openaiResponses_applicationPDF()   throws { try runAttachmentCase(lane: .openaiResponses, kind: .applicationPDF) }
    func test_attachmentMatrix_openaiResponses_audioMPEG()        throws { try runAttachmentCase(lane: .openaiResponses, kind: .audioMPEG) }
    func test_attachmentMatrix_openaiResponses_videoMP4()         throws { try runAttachmentCase(lane: .openaiResponses, kind: .videoMP4) }
    func test_attachmentMatrix_openaiResponses_applicationDOCX()  throws { try runAttachmentCase(lane: .openaiResponses, kind: .applicationDOCX) }
    func test_attachmentMatrix_openaiResponses_applicationZIP()   throws { try runAttachmentCase(lane: .openaiResponses, kind: .applicationZIP) }
    func test_attachmentMatrix_openaiResponses_applicationOctet() throws { try runAttachmentCase(lane: .openaiResponses, kind: .applicationOctet) }

    // anthropic (16)
    func test_attachmentMatrix_anthropic_textPlain()        throws { try runAttachmentCase(lane: .anthropic,       kind: .textPlain) }
    func test_attachmentMatrix_anthropic_textMarkdown()     throws { try runAttachmentCase(lane: .anthropic,       kind: .textMarkdown) }
    func test_attachmentMatrix_anthropic_applicationJSON()  throws { try runAttachmentCase(lane: .anthropic,       kind: .applicationJSON) }
    func test_attachmentMatrix_anthropic_applicationXML()   throws { try runAttachmentCase(lane: .anthropic,       kind: .applicationXML) }
    func test_attachmentMatrix_anthropic_imageSVG()         throws { try runAttachmentCase(lane: .anthropic,       kind: .imageSVG) }
    func test_attachmentMatrix_anthropic_yamlAsUnknown()    throws { try runAttachmentCase(lane: .anthropic,       kind: .yamlAsUnknown) }
    func test_attachmentMatrix_anthropic_imagePNG()         throws { try runAttachmentCase(lane: .anthropic,       kind: .imagePNG) }
    func test_attachmentMatrix_anthropic_imageWEBP()        throws { try runAttachmentCase(lane: .anthropic,       kind: .imageWEBP) }
    func test_attachmentMatrix_anthropic_imageHEIC()        throws { try runAttachmentCase(lane: .anthropic,       kind: .imageHEIC) }
    func test_attachmentMatrix_anthropic_imageTIFF()        throws { try runAttachmentCase(lane: .anthropic,       kind: .imageTIFF) }
    func test_attachmentMatrix_anthropic_applicationPDF()   throws { try runAttachmentCase(lane: .anthropic,       kind: .applicationPDF) }
    func test_attachmentMatrix_anthropic_audioMPEG()        throws { try runAttachmentCase(lane: .anthropic,       kind: .audioMPEG) }
    func test_attachmentMatrix_anthropic_videoMP4()         throws { try runAttachmentCase(lane: .anthropic,       kind: .videoMP4) }
    func test_attachmentMatrix_anthropic_applicationDOCX()  throws { try runAttachmentCase(lane: .anthropic,       kind: .applicationDOCX) }
    func test_attachmentMatrix_anthropic_applicationZIP()   throws { try runAttachmentCase(lane: .anthropic,       kind: .applicationZIP) }
    func test_attachmentMatrix_anthropic_applicationOctet() throws { try runAttachmentCase(lane: .anthropic,       kind: .applicationOctet) }

    // gemini (16)
    func test_attachmentMatrix_gemini_textPlain()        throws { try runAttachmentCase(lane: .gemini,          kind: .textPlain) }
    func test_attachmentMatrix_gemini_textMarkdown()     throws { try runAttachmentCase(lane: .gemini,          kind: .textMarkdown) }
    func test_attachmentMatrix_gemini_applicationJSON()  throws { try runAttachmentCase(lane: .gemini,          kind: .applicationJSON) }
    func test_attachmentMatrix_gemini_applicationXML()   throws { try runAttachmentCase(lane: .gemini,          kind: .applicationXML) }
    func test_attachmentMatrix_gemini_imageSVG()         throws { try runAttachmentCase(lane: .gemini,          kind: .imageSVG) }
    func test_attachmentMatrix_gemini_yamlAsUnknown()    throws { try runAttachmentCase(lane: .gemini,          kind: .yamlAsUnknown) }
    func test_attachmentMatrix_gemini_imagePNG()         throws { try runAttachmentCase(lane: .gemini,          kind: .imagePNG) }
    func test_attachmentMatrix_gemini_imageWEBP()        throws { try runAttachmentCase(lane: .gemini,          kind: .imageWEBP) }
    func test_attachmentMatrix_gemini_imageHEIC()        throws { try runAttachmentCase(lane: .gemini,          kind: .imageHEIC) }
    func test_attachmentMatrix_gemini_imageTIFF()        throws { try runAttachmentCase(lane: .gemini,          kind: .imageTIFF) }
    func test_attachmentMatrix_gemini_applicationPDF()   throws { try runAttachmentCase(lane: .gemini,          kind: .applicationPDF) }
    func test_attachmentMatrix_gemini_audioMPEG()        throws { try runAttachmentCase(lane: .gemini,          kind: .audioMPEG) }
    func test_attachmentMatrix_gemini_videoMP4()         throws { try runAttachmentCase(lane: .gemini,          kind: .videoMP4) }
    func test_attachmentMatrix_gemini_applicationDOCX()  throws { try runAttachmentCase(lane: .gemini,          kind: .applicationDOCX) }
    func test_attachmentMatrix_gemini_applicationZIP()   throws { try runAttachmentCase(lane: .gemini,          kind: .applicationZIP) }
    func test_attachmentMatrix_gemini_applicationOctet() throws { try runAttachmentCase(lane: .gemini,          kind: .applicationOctet) }

    // deepseek (16)
    func test_attachmentMatrix_deepseek_textPlain()        throws { try runAttachmentCase(lane: .deepseek,        kind: .textPlain) }
    func test_attachmentMatrix_deepseek_textMarkdown()     throws { try runAttachmentCase(lane: .deepseek,        kind: .textMarkdown) }
    func test_attachmentMatrix_deepseek_applicationJSON()  throws { try runAttachmentCase(lane: .deepseek,        kind: .applicationJSON) }
    func test_attachmentMatrix_deepseek_applicationXML()   throws { try runAttachmentCase(lane: .deepseek,        kind: .applicationXML) }
    func test_attachmentMatrix_deepseek_imageSVG()         throws { try runAttachmentCase(lane: .deepseek,        kind: .imageSVG) }
    func test_attachmentMatrix_deepseek_yamlAsUnknown()    throws { try runAttachmentCase(lane: .deepseek,        kind: .yamlAsUnknown) }
    func test_attachmentMatrix_deepseek_imagePNG()         throws { try runAttachmentCase(lane: .deepseek,        kind: .imagePNG) }
    func test_attachmentMatrix_deepseek_imageWEBP()        throws { try runAttachmentCase(lane: .deepseek,        kind: .imageWEBP) }
    func test_attachmentMatrix_deepseek_imageHEIC()        throws { try runAttachmentCase(lane: .deepseek,        kind: .imageHEIC) }
    func test_attachmentMatrix_deepseek_imageTIFF()        throws { try runAttachmentCase(lane: .deepseek,        kind: .imageTIFF) }
    func test_attachmentMatrix_deepseek_applicationPDF()   throws { try runAttachmentCase(lane: .deepseek,        kind: .applicationPDF) }
    func test_attachmentMatrix_deepseek_audioMPEG()        throws { try runAttachmentCase(lane: .deepseek,        kind: .audioMPEG) }
    func test_attachmentMatrix_deepseek_videoMP4()         throws { try runAttachmentCase(lane: .deepseek,        kind: .videoMP4) }
    func test_attachmentMatrix_deepseek_applicationDOCX()  throws { try runAttachmentCase(lane: .deepseek,        kind: .applicationDOCX) }
    func test_attachmentMatrix_deepseek_applicationZIP()   throws { try runAttachmentCase(lane: .deepseek,        kind: .applicationZIP) }
    func test_attachmentMatrix_deepseek_applicationOctet() throws { try runAttachmentCase(lane: .deepseek,        kind: .applicationOctet) }

    // llama (16) — all skip
    func test_attachmentMatrix_llama_textPlain()        throws { try runAttachmentCase(lane: .llama,           kind: .textPlain) }
    func test_attachmentMatrix_llama_textMarkdown()     throws { try runAttachmentCase(lane: .llama,           kind: .textMarkdown) }
    func test_attachmentMatrix_llama_applicationJSON()  throws { try runAttachmentCase(lane: .llama,           kind: .applicationJSON) }
    func test_attachmentMatrix_llama_applicationXML()   throws { try runAttachmentCase(lane: .llama,           kind: .applicationXML) }
    func test_attachmentMatrix_llama_imageSVG()         throws { try runAttachmentCase(lane: .llama,           kind: .imageSVG) }
    func test_attachmentMatrix_llama_yamlAsUnknown()    throws { try runAttachmentCase(lane: .llama,           kind: .yamlAsUnknown) }
    func test_attachmentMatrix_llama_imagePNG()         throws { try runAttachmentCase(lane: .llama,           kind: .imagePNG) }
    func test_attachmentMatrix_llama_imageWEBP()        throws { try runAttachmentCase(lane: .llama,           kind: .imageWEBP) }
    func test_attachmentMatrix_llama_imageHEIC()        throws { try runAttachmentCase(lane: .llama,           kind: .imageHEIC) }
    func test_attachmentMatrix_llama_imageTIFF()        throws { try runAttachmentCase(lane: .llama,           kind: .imageTIFF) }
    func test_attachmentMatrix_llama_applicationPDF()   throws { try runAttachmentCase(lane: .llama,           kind: .applicationPDF) }
    func test_attachmentMatrix_llama_audioMPEG()        throws { try runAttachmentCase(lane: .llama,           kind: .audioMPEG) }
    func test_attachmentMatrix_llama_videoMP4()         throws { try runAttachmentCase(lane: .llama,           kind: .videoMP4) }
    func test_attachmentMatrix_llama_applicationDOCX()  throws { try runAttachmentCase(lane: .llama,           kind: .applicationDOCX) }
    func test_attachmentMatrix_llama_applicationZIP()   throws { try runAttachmentCase(lane: .llama,           kind: .applicationZIP) }
    func test_attachmentMatrix_llama_applicationOctet() throws { try runAttachmentCase(lane: .llama,           kind: .applicationOctet) }
}
