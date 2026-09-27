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

    // The auto-discover preset is the guided dynamic-provider entry: native
    // dialect, dynamic models, thinking on.
    func test_ollamaAutoDiscoverPreset_isDynamic() throws {
        let p = try preset(named: "Ollama (auto-discover)")
        XCTAssertTrue(p.dynamicModels, "auto-discover preset must be dynamic")
        XCTAssertEqual(p.api, .llama)
        XCTAssertTrue(p.url.hasSuffix("/api/chat"))
        XCTAssertTrue(p.configurableThinking)
    }

    func test_ollamaNativePreset_isNotDynamic() throws {
        XCTAssertFalse(try preset(named: "Ollama (native)").dynamicModels,
                       "the single-model native preset must not be dynamic")
    }

    // Renamed from the Ollama-branded preset in 8b12ad481: for Ollama the two
    // native presets are strictly better, so this one became the generic
    // starting point for other local runners. It stays on the compat endpoint,
    // which cannot express think/num_ctx.
    func test_localOpenAICompatPreset_staysOnCompatEndpoint() throws {
        let p = try preset(named: "Local OpenAI-compatible (LM Studio, vLLM, \u{2026})")
        XCTAssertTrue(p.url.hasSuffix("/v1/chat/completions"))
        XCTAssertEqual(p.api, .chatCompletions)
    }
}
