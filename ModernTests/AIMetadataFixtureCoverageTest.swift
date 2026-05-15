//
//  AIMetadataFixtureCoverageTest.swift
//  iTerm2 ModernTests
//
//  Fails if any model declared in AIMetadata.swift lacks a corresponding
//  refusal-shape fixture under ModernTests/Resources/SafetyRefusalFixtures/.
//
//  When this test fails after you add a model, capture the missing fixture:
//
//      ITERM2_AI_LIVE_<VENDOR>_MODELS=<modelname> \
//          tools/run_ai_live.sh test_<vendor>_refusal
//
//  Then `git add ModernTests/Resources/SafetyRefusalFixtures/*` and commit.
//  The full instructions live in the header of AIMetadata.swift.
//
//  This is a regular unit test (no network); it runs as part of `make test`.
//

import XCTest
@testable import iTerm2SharedARC

final class AIMetadataFixtureCoverageTest: XCTestCase {
    func testEveryModelHasRefusalFixture() {
        let fixturesDir = AIMetadataFixtureCoverageTest.fixturesDirectory()
        let existing: Set<String>
        if let names = try? FileManager.default.contentsOfDirectory(atPath: fixturesDir.path) {
            existing = Set(names)
        } else {
            existing = []
        }

        var missing: [String] = []
        for model in AIMetadata.instance.models {
            // Skip vendors that don't make sense to fixture-capture:
            //   - llama:  local Ollama, no real "refusal" semantics
            //   - none:   shouldn't happen, but skip rather than crash
            guard let vendor = model.vendor, vendor != .llama else { continue }
            // Skip models that are deprecated to new keys. They still work
            // for grandfathered accounts so we keep the AIMetadata entry,
            // but a fixture can't be captured from a fresh API key. The list
            // is short and easy to revisit when Google fully removes a model.
            if Self.deprecatedToNewKeys.contains(model.name) { continue }
            let vendorString = AIMetadataFixtureCoverageTest.vendorSlug(for: vendor)
            let safeModel = AIMetadataFixtureCoverageTest.sanitize(model.name)
            // Filenames are <vendor>_<safeModel>_refusal_<mode>_<seq>.json.
            // Either streaming or non-streaming counts as covered.
            let prefix = "\(vendorString)_\(safeModel)_refusal_"
            let covered = existing.contains(where: { $0.hasPrefix(prefix) })
            if !covered {
                missing.append("\(vendorString) / \(model.name)")
            }
        }

        if !missing.isEmpty {
            // xcodebuild collapses XCTFail messages to one line, so print the
            // detail to stdout before failing.
            print("\n[AIMetadataFixtureCoverageTest] Missing refusal fixtures:")
            for entry in missing {
                print("  - \(entry)")
            }
            print("""

                Capture them by running:
                  tools/run_ai_live.sh refusal

                Or for a specific vendor / model:
                  ITERM2_AI_LIVE_<VENDOR>_MODELS=<modelname> tools/run_ai_live.sh test_<vendor>_refusal

                Then commit the new files in
                  ModernTests/Resources/SafetyRefusalFixtures/

                See the header of sources/AITerm/AIMetadata.swift for full instructions.

                """)
            XCTFail("Missing refusal fixtures for \(missing.count) model(s); see stdout for details and the command to capture them.")
        }
    }

    // Models that AIMetadata still lists (so grandfathered keys keep working)
    // but that a freshly-minted vendor API key cannot reach — either the
    // capture returns 404 / "no longer available to new users", or the
    // model's per-key quota for fresh accounts is too tight to actually
    // record a refusal (Google's 2.0-generation Gemini models return 429
    // RESOURCE_EXHAUSTED on the first request from a new key as of
    // 2026-05). The coverage test skips these rather than failing on
    // capture problems we can't fix from inside the test suite.
    private static let deprecatedToNewKeys: Set<String> = [
        "gemini-2.0-flash",
        "gemini-2.0-flash-lite",
    ]

    // MARK: - Helpers

    private static func fixturesDirectory() -> URL {
        // Resolve via #filePath so the test works no matter where the bundle
        // ends up being placed by Xcode (DerivedData, archive, etc.).
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()                       // ModernTests/
            .appendingPathComponent("Resources")
            .appendingPathComponent("SafetyRefusalFixtures")
    }

    private static func vendorSlug(for vendor: iTermAIVendor) -> String {
        switch vendor {
        case .openAI:    return "openai"
        case .anthropic: return "anthropic"
        case .gemini:    return "gemini"
        case .deepSeek:  return "deepseek"
        case .llama:     return "llama"
        @unknown default: return "unknown"
        }
    }

    private static func sanitize(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return String(s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }
}
