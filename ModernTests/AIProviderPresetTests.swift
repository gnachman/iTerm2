//
//  AIProviderPresetTests.swift
//  iTerm2 ModernTests
//
//  The provider presets are the guided setup path for third-party / local
//  gateways. These pin the native Ollama preset so the one-click setup keeps
//  filling in the native /api/chat endpoint, the .llama (Ollama) API type, and
//  the Think toggle.
//

import XCTest
@testable import iTerm2SharedARC

final class AIProviderPresetTests: XCTestCase {
    private func preset(named name: String) throws -> AIProviderPreset {
        let presets = AIMetadata.instance.providerPresets
        return try XCTUnwrap(presets.first { $0.name == name },
                             "no provider preset named \(name); have \(presets.map { $0.name })")
    }

    func test_ollamaNativePreset_usesNativeEndpointAndDialect() throws {
        let p = try preset(named: "Ollama (native)")
        XCTAssertTrue(p.url.hasSuffix("/api/chat"),
                      "native Ollama preset must target /api/chat, was \(p.url)")
        XCTAssertEqual(p.api, .llama, "native Ollama preset must use the .llama (Ollama) dialect")
    }

    // The Think toggle only appears when the model advertises configurable
    // thinking, so the native preset must preselect it.
    func test_ollamaNativePreset_enablesConfigurableThinking() throws {
        XCTAssertTrue(try preset(named: "Ollama (native)").configurableThinking,
                      "native Ollama preset should enable the Think toggle")
    }

    // Vision defaults off even on the native preset: a local runner mixes text
    // and vision models, so the user opts in per model. (The reset itself is what
    // matters: a preset must drive every capability so none goes stale.)
    func test_ollamaNativePreset_visionDefaultsOff() throws {
        XCTAssertFalse(try preset(named: "Ollama (native)").vision)
    }

    // The OpenAI-compatible preset stays available but on the compat endpoint,
    // which cannot express think/num_ctx.
    func test_ollamaCompatPreset_staysOnCompatEndpoint() throws {
        let p = try preset(named: "Ollama (OpenAI-compatible)")
        XCTAssertTrue(p.url.hasSuffix("/v1/chat/completions"))
        XCTAssertEqual(p.api, .chatCompletions)
    }
}
