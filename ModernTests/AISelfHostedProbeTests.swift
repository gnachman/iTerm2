//
//  AISelfHostedProbeTests.swift
//  iTerm2 ModernTests
//
//  iTerm2 refuses to send a stored vendor API key to a self-hosted endpoint
//  (issue 12477), substituting a placeholder instead. The Test Connection probe
//  used to send the real key anyway, so an authenticated local server would
//  report “Connection Succeeded” while every real chat request 401’d
//  (issue 13021). These tests pin the probe’s key resolution to the request
//  path’s and cover the explanatory hint shown when the probe fails.
//

import XCTest
@testable import iTerm2SharedARC

final class AISelfHostedProbeTests: XCTestCase {

    // MARK: - usesPlaceholderAPIKey

    func testPlaceholder_localhostAndPrivateHosts() {
        for url in ["http://localhost:1337/v1",
                    "http://osaurus.local:1337/v1",
                    "http://127.0.0.1:11434/v1",
                    "http://192.168.1.10:1337/v1",
                    "http://[::1]:1337/v1"] {
            XCTAssertTrue(AITermController.usesPlaceholderAPIKey(url: url, api: .chatCompletions),
                          "\(url) should be treated as self-hosted")
        }
    }

    // NSURL keeps the case the user typed, and host names are case-insensitive,
    // so an uppercase local host must not look public and collect the vendor key.
    func testPlaceholder_hostMatchIsCaseInsensitive() {
        for url in ["http://LOCALHOST:1337/v1",
                    "http://osaurus.LOCAL:1337/v1",
                    "http://MyMac.Local:1337/v1"] {
            XCTAssertTrue(AITermController.usesPlaceholderAPIKey(url: url, api: .chatCompletions),
                          "\(url) should be treated as self-hosted")
        }
    }

    // A fully qualified name may carry the DNS root dot. It names the same
    // host, so it must not change which key is sent.
    func testPlaceholder_trailingRootDotStillCountsAsLocal() {
        for url in ["https://osaurus.local./v1", "https://localhost./v1",
                    "https://192.168.1.10./v1", "http://osaurus.local./v1"] {
            XCTAssertEqual(AITermController.apiKeyPolicy(url: url, api: .chatCompletions),
                           .placeholder(.localEndpoint),
                           "\(url) is on the local network")
        }
        XCTAssertEqual(AITermController.apiKeyPolicy(url: "https://api.openai.com./v1",
                                                     api: .chatCompletions),
                       .vendorKey)
    }

    // URL.host hands back an IPv6 literal unbracketed, so it cannot be matched
    // by the name rules; only the address rules apply to it.
    func testPlaceholder_publicIPv6LiteralUsesVendorKey() {
        for url in ["https://[2606:4700:4700::1111]/v1",
                    "https://[2001:4860:4860::8888]:8443/v1"] {
            XCTAssertEqual(AITermController.apiKeyPolicy(url: url, api: .chatCompletions),
                           .vendorKey,
                           "\(url) is a public address")
        }
        // Private and loopback literals still withhold it.
        for url in ["https://[::1]:11434/v1", "https://[fe80::1]/v1", "https://[fd00::1]/v1"] {
            XCTAssertEqual(AITermController.apiKeyPolicy(url: url, api: .chatCompletions),
                           .placeholder(.localEndpoint),
                           "\(url) is on the local network")
        }
    }

    func testPlaceholder_publicHTTPSHostUsesVendorKey() {
        for url in ["https://api.openai.com/v1/chat/completions",
                    "https://example.com/v1"] {
            XCTAssertFalse(AITermController.usesPlaceholderAPIKey(url: url, api: .chatCompletions),
                           "\(url) should authorize with the vendor key")
        }
    }

    func testPlaceholder_appleIntelligenceNeedsNoKey() {
        XCTAssertTrue(AITermController.usesPlaceholderAPIKey(url: "", api: .appleIntelligence))
    }

    // Apple Intelligence has no endpoint at all, so "add a custom header" is
    // meaningless for it. The advice and the Settings hints must agree about
    // leaving it out; only the generic "No API key is used." applies.
    func testOnDevice_getsNoHeaderAdvice() {
        XCTAssertEqual(AITermController.apiKeyPolicy(url: "", api: .appleIntelligence),
                       .placeholder(.onDevice))
        XCTAssertNil(AIWithheldKeyAdvice.hint(url: "", api: .appleIntelligence, customHeaders: []))
        XCTAssertFalse(AITermControllerObjC.modelWithholdsAPIKeyForLocalEndpoint(
                        url: "", api: .appleIntelligence))
        // Even with a local URL attached, which a migrated config could carry.
        XCTAssertFalse(AITermControllerObjC.modelWithholdsAPIKeyForLocalEndpoint(
                        url: "http://localhost:1337/v1", api: .appleIntelligence))
    }

    // MARK: - probe key resolution

    func testProbeKey_selfHostedSendsPlaceholderWithoutPrompting() {
        XCTAssertEqual(AIConnectionTester.unpromptedAPIKey(url: "http://osaurus.local:1337/v1",
                                                           api: .chatCompletions),
                       AITermController.selfHostedPlaceholderAPIKey)
    }

    func testProbeKey_publicHostFallsBackToStoredKey() {
        XCTAssertNil(AIConnectionTester.unpromptedAPIKey(url: "https://api.openai.com/v1",
                                                         api: .chatCompletions))
    }

    // MARK: - credential header names

    // Derived from LLMAuthorizationProvider so the advice can't name a header
    // the lane doesn't actually authenticate with.
    func testCredentialHeaders_perAPI() {
        XCTAssertEqual(LLMAuthorizationProvider.credentialHeaderNames(url: "http://localhost:1337/v1",
                                                                      api: .chatCompletions),
                       ["Authorization"])
        XCTAssertEqual(LLMAuthorizationProvider.credentialHeaderNames(url: "http://localhost:1337/v1",
                                                                      api: .anthropic),
                       ["x-api-key"])
        XCTAssertTrue(LLMAuthorizationProvider.credentialHeaderNames(url: "http://localhost:11434",
                                                                     api: .llama).isEmpty)
        XCTAssertTrue(LLMAuthorizationProvider.credentialHeaderNames(url: "http://localhost:1337",
                                                                     api: .gemini).isEmpty)
    }

    // anthropic-version rides along in the same dictionary but carries no
    // credential, so it must not be offered as the header to authenticate with.
    func testCredentialHeaders_excludeNonCredentialHeaders() {
        let names = LLMAuthorizationProvider.credentialHeaderNames(url: "http://localhost:1337/v1",
                                                                   api: .anthropic)
        XCTAssertFalse(names.contains("anthropic-version"))
    }

    func testCredentialHeaders_azureUsesApiKey() {
        XCTAssertEqual(LLMAuthorizationProvider.credentialHeaderNames(
            url: "https://example.openai.azure.com/openai/deployments/x/chat/completions",
            api: .chatCompletions),
                       ["api-key"])
    }

    // MARK: - failure hint

    func testHint_explainsPlaceholderWhenSelfHostedAndUnauthenticated() {
        let hint = AIWithheldKeyAdvice.hint(url: "http://osaurus.local:1337/v1",
                                                         api: .chatCompletions,
                                                         customHeaders: [])
        XCTAssertNotNil(hint)
        // It must name the header this lane authenticates with.
        XCTAssertTrue(hint?.contains("Authorization") ?? false, "\(hint ?? "nil")")
    }

    // A local Anthropic-compatible server authenticates with x-api-key, so
    // advising an Authorization header would send the user down a dead end.
    func testHint_namesTheLaneSOwnCredentialHeader() {
        let hint = AIWithheldKeyAdvice.hint(url: "http://osaurus.local:1337/v1",
                                                         api: .anthropic,
                                                         customHeaders: [])
        XCTAssertTrue(hint?.contains("x-api-key") ?? false, "\(hint ?? "nil")")
        XCTAssertFalse(hint?.contains("Authorization") ?? true, "\(hint ?? "nil")")
    }

    // A 401 from an Ollama endpoint means a reverse proxy in front of it wants
    // an Authorization header, which is exactly what the advice is for. These
    // lanes send no credential header of their own, so the advice cannot name
    // one, but it must still appear.
    func testHint_presentForLanesWithNoCredentialHeaderOfTheirOwn() {
        for api in [iTermAIAPI.llama, .gemini] {
            XCTAssertNotNil(AIWithheldKeyAdvice.hint(url: "http://localhost:11434/v1",
                                                                  api: api,
                                                                  customHeaders: []),
                            "\(api) should still get advice")
        }
    }

    // Suppression has to run on these lanes too. An Ollama model behind a proxy
    // that already carries an Authorization header and 401s for some other
    // reason (expired token, wrong realm) must not be told to add the header it
    // already has: with no credential header of its own to compare against, any
    // usable header counts.
    func testHint_absentWhenALaneWithNoCredentialHeaderAlreadyCarriesOne() {
        let headers = [["name": "Authorization", "value": "Bearer abc"]]
        for api in [iTermAIAPI.llama, .gemini] {
            XCTAssertNil(AIWithheldKeyAdvice.hint(url: "http://localhost:11434/v1",
                                                               api: api,
                                                               customHeaders: headers),
                         "\(api) already authenticates itself")
        }
    }

    // An unrelated header is not a credential, on these lanes either. Ollama
    // behind a proxy that wants Authorization, carrying only an X-Request-Id,
    // is precisely the case the generic advice exists for.
    func testHint_presentWhenALaneWithNoCredentialHeaderCarriesOnlyAnUnrelatedOne() {
        let headers = [["name": "X-Request-Id", "value": "abc123"]]
        for api in [iTermAIAPI.llama, .gemini] {
            XCTAssertNotNil(AIWithheldKeyAdvice.hint(url: "http://localhost:11434/v1",
                                                     api: api,
                                                     customHeaders: headers),
                            "\(api): an unrelated header is not authentication")
        }
    }

    // A non-canonical credential header counts on a lane that has its own
    // name too: an OpenAI-compatible server fronted by a proxy wanting
    // X-Api-Key is authenticated, even though this lane's own name is
    // Authorization.
    func testHint_absentWhenANonCanonicalCredentialHeaderIsConfigured() {
        let headers = [["name": "X-Api-Key", "value": "secret"]]
        XCTAssertNil(AIWithheldKeyAdvice.hint(url: "http://osaurus.local:1337/v1",
                                              api: .chatCompletions,
                                              customHeaders: headers))
    }

    // Any of the names a proxy in front of such a server plausibly wants does
    // count, since there is no authoritative name to compare against.
    func testHint_absentWhenALaneWithNoCredentialHeaderCarriesAKnownAuthHeader() {
        for name in ["Authorization", "x-api-key", "Proxy-Authorization", "X-Auth-Token"] {
            let headers = [["name": name, "value": "secret"]]
            XCTAssertNil(AIWithheldKeyAdvice.hint(url: "http://localhost:11434/v1",
                                                  api: .llama,
                                                  customHeaders: headers),
                         "\(name) should count as authentication")
        }
    }

    func testHint_presentWhenALaneWithNoCredentialHeaderCarriesARejectedOne() {
        let headers = [["name": "Bad Name", "value": "x"]]
        XCTAssertNotNil(AIWithheldKeyAdvice.hint(url: "http://localhost:11434/v1",
                                                              api: .llama,
                                                              customHeaders: headers))
    }

    // The frame must not carry an article that has to agree with the injected
    // header name: "add a Authorization header" is wrong English.
    func testHint_readsGrammaticallyForEveryCredentialHeaderName() {
        for (api, name) in [(iTermAIAPI.chatCompletions, "Authorization"),
                            (iTermAIAPI.anthropic, "x-api-key")] {
            let hint = AIWithheldKeyAdvice.hint(url: "http://osaurus.local:1337/v1",
                                                             api: api,
                                                             customHeaders: [])
            XCTAssertNotNil(hint)
            XCTAssertFalse(hint?.contains("a \(name)") ?? true,
                           "article disagrees with the header name: \(hint ?? "nil")")
            XCTAssertFalse(hint?.contains("an \(name)") ?? true,
                           "article disagrees with the header name: \(hint ?? "nil")")
        }
    }

    // The advice points at a section of the model editor, so it has to use that
    // section's actual label.
    func testHint_namesTheEditorSectionAsItIsLabeled() {
        for api in [iTermAIAPI.chatCompletions, .llama] {
            let hint = AIWithheldKeyAdvice.hint(url: "http://osaurus.local:1337/v1",
                                                             api: api,
                                                             customHeaders: [])
            XCTAssertTrue(hint?.contains("\u{201c}Custom headers\u{201d}") ?? false, "\(hint ?? "nil")")
        }
    }

    // Suppression must agree with AICustomHeaders.merged, which overrides
    // case-insensitively, or the user who typed a lowercase name loses both the
    // header and the explanation (issue 13021).
    func testHint_absentWhenTheModelCarriesItsOwnAuthorizationHeader() {
        for name in ["authorization", "Authorization", "AUTHORIZATION"] {
            let headers = [["name": name, "value": "Bearer abc"]]
            XCTAssertNil(AIWithheldKeyAdvice.hint(url: "http://osaurus.local:1337/v1",
                                                               api: .chatCompletions,
                                                               customHeaders: headers),
                         "\(name) should count as authenticated")
        }
    }

    func testHint_absentWhenAnthropicLaneCarriesXAPIKey() {
        let headers = [["name": "X-Api-Key", "value": "secret"]]
        XCTAssertNil(AIWithheldKeyAdvice.hint(url: "http://osaurus.local:1337/v1",
                                                           api: .anthropic,
                                                           customHeaders: headers))
    }

    // An unrelated header is not a credential, so the advice stands.
    func testHint_presentWhenTheOnlyCustomHeaderIsUnrelated() {
        let headers = [["name": "X-Route", "value": "alpha"]]
        XCTAssertNotNil(AIWithheldKeyAdvice.hint(url: "http://osaurus.local:1337/v1",
                                                              api: .chatCompletions,
                                                              customHeaders: headers))
    }

    // merged sends an empty value (isValidValue("") is true), replacing the
    // built-in header, so the user's header did reach the server and telling
    // them to add it would be wrong. Suppression tracks what merged sends, not
    // whether the value looks useful.
    func testHint_absentWhenTheAuthorizationHeaderIsEmpty() {
        let headers = [["name": "Authorization", "value": ""]]
        XCTAssertNil(AIWithheldKeyAdvice.hint(url: "http://osaurus.local:1337/v1",
                                                           api: .chatCompletions,
                                                           customHeaders: headers))
    }

    // A value merged rejects never reaches the server, so the advice stands.
    func testHint_presentWhenTheAuthorizationHeaderWouldBeRejected() {
        let headers = [["name": "Authorization", "value": "Bearer bad\r\nX-Smuggled: yes"]]
        XCTAssertNotNil(AIWithheldKeyAdvice.hint(url: "http://osaurus.local:1337/v1",
                                                              api: .chatCompletions,
                                                              customHeaders: headers))
    }

    // A gateway that answers 401 with a structured body loses the status text
    // before the message is built, and its prose need not contain any auth
    // vocabulary. The transport's own error string still carries the status,
    // so classification has to see both.
    func testAuthFailureDetection_statusSurvivesAParsedBody() {
        let parsedMessage = "Invalid proxy server token passed."
        XCTAssertFalse(AIWithheldKeyAdvice.looksLikeAuthFailure(parsedMessage))
        XCTAssertTrue(AIWithheldKeyAdvice.looksLikeAuthFailure("HTTP request failed with status 401."))
    }

    // MARK: - which failures earn the hint

    // The hint explains a withheld credential, so it belongs only on a refusal
    // that came back from the server and reads like one about credentials.
    func testAuthFailureDetection() {
        for message in ["HTTP request failed with status 401.",
                        "HTTP request failed with status 403. Forbidden",
                        "Invalid access key: Unrecognized token format",
                        "Unauthorized",
                        "authentication_error: invalid x-api-key"] {
            XCTAssertTrue(AIWithheldKeyAdvice.looksLikeAuthFailure(message), message)
        }
        for message in ["Could not connect to the server.",
                        "The URL is not valid.",
                        "Could not build a request: malformed body",
                        "model \"llama4\" not found, try pulling it first",
                        "HTTP request failed with status 500.",
                        ""] {
            XCTAssertFalse(AIWithheldKeyAdvice.looksLikeAuthFailure(message), message)
        }
    }

    func testHint_absentForPublicHost() {
        XCTAssertNil(AIWithheldKeyAdvice.hint(url: "https://api.openai.com/v1",
                                                           api: .chatCompletions,
                                                           customHeaders: []))
    }
}
