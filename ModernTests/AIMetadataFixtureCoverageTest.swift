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
            guard let vendor = model.vendor else { continue }
            // Exemption is now a data field on the catalog entry (fixtureExempt
            // in ai-models.json). It covers models that don't make sense to
            // fixture-capture: local Llama (no refusal semantics), on-device
            // Apple (no HTTP request), models unreachable for new keys, and
            // models that block the refusal prompt at HTTP 400.
            //
            // Drift guard, both directions, so a data field in ai-models.json
            // can't silently opt a cloud model out of coverage:
            //
            //   - Structural exemption: vendor .llama (local, no refusal
            //     semantics) and .apple (on-device, no HTTP request) are
            //     inherently unfixturable.
            //   - Sanctioned exemption: a cloud model may only be exempt if the
            //     live harness genuinely can't exercise it for a refusal, i.e.
            //     it's in unreachableForNewKeys or refusalBlockedAtHTTP.
            //
            // Forward: anything the harness skips must be marked fixtureExempt.
            // Reverse: any fixtureExempt cloud model must have a sanctioned
            // reason (be in one of those harness sets). Together this keeps the
            // flag from drifting away from the harness in either direction.
            let harnessSkips = AILiveHarness.unreachableForNewKeys.contains(model.name) ||
                AILiveHarness.refusalBlockedAtHTTP.contains(model.name)
            let structurallyExempt = vendor == .llama || vendor == .apple
            if harnessSkips {
                XCTAssertTrue(model.fixtureExempt,
                              "\(model.name) is skipped by the live harness but is not marked fixtureExempt in ai-models.json")
            }
            if model.fixtureExempt && !structurallyExempt {
                XCTAssertTrue(harnessSkips,
                              "\(model.name) is marked fixtureExempt in ai-models.json but has no sanctioned reason: a cloud model may only be exempt if it is in AILiveHarness.unreachableForNewKeys or refusalBlockedAtHTTP")
            }
            if model.fixtureExempt { continue }
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

    // The "fresh API key can't reach this model" list lives on AILiveHarness
    // (see AILiveHarness.unreachableForNewKeys). The harness skips them on
    // default sweeps; coverage skips them here for the same reason.

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
