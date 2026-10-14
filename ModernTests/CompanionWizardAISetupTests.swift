//
//  CompanionWizardAISetupTests.swift
//  iTerm2 ModernTests
//
//  QA finding F-101: with a manual AI model that cannot authenticate, the
//  companion wizard's AI path asked for a vendor key the model never uses, then
//  failed verification with “plugins did not load” (although both loaded) and
//  rolled everything back. These pin the screen-mode decision and the
//  verification outcome the wizard now uses.
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionWizardAISetupTests: XCTestCase {
    private typealias Mode = CompanionWizardAIMode
    private typealias Verification = CompanionWizardVerification

    // MARK: - Screen mode

    func testRecommendedModelWithoutKeyShowsKeyEntry() {
        XCTAssertEqual(Mode.mode(usingRecommendedModel: true,
                                 defaultModelRegistrationAvailable: false),
                       .keyEntry)
    }

    func testWorkingRecommendedModelNeedsNoKey() {
        // A recommended model that can already authorize needs no key, even
        // before AI consent is granted (Install grants it). This also covers
        // vendors that use no key at all, such as Apple Intelligence, which the
        // Provider popup does not list: asking for a key there would force the
        // user to switch vendors.
        XCTAssertEqual(Mode.mode(usingRecommendedModel: true,
                                 defaultModelRegistrationAvailable: true),
                       .alreadyConfigured)
    }

    func testWorkingManualModelNeedsNoKey() {
        XCTAssertEqual(Mode.mode(usingRecommendedModel: false,
                                 defaultModelRegistrationAvailable: true),
                       .alreadyConfigured)
    }

    func testManualModelThatCannotAuthenticateHidesKeyEntry() {
        // The F-101 reproduction: manual OpenAI model, no OpenAI key. A vendor
        // key pasted in the wizard would never reach that model.
        XCTAssertEqual(Mode.mode(usingRecommendedModel: false,
                                 defaultModelRegistrationAvailable: false),
                       .manualModelNeedsConfiguration)
    }

    // MARK: - Verification

    private func verify(full: Bool = true,
                        mode: Mode,
                        companion: Bool = true,
                        aiPlugin: Bool = true,
                        aiEnabled: Bool = true,
                        registration: Bool) -> Verification {
        return Verification.verify(full: full,
                                   aiMode: mode,
                                   companionConfigured: companion,
                                   aiPluginInstalled: aiPlugin,
                                   aiEnabled: aiEnabled,
                                   defaultModelRegistrationAvailable: registration)
    }

    func testManualModelWithoutKeySucceedsWhenPluginsLoad() {
        // F-101: both plugins loaded but the manual model has no key. This must
        // not be reported as “plugins did not load” nor roll back setup.
        XCTAssertEqual(verify(mode: .manualModelNeedsConfiguration, registration: false), .ready)
    }

    func testAlreadyConfiguredSucceedsWhenPluginsLoad() {
        XCTAssertEqual(verify(mode: .alreadyConfigured, registration: true), .ready)
        // Only the plugins are checked in this mode.
        XCTAssertEqual(verify(mode: .alreadyConfigured, registration: false), .ready)
    }

    func testKeyEntryRequiresAuthentication() {
        XCTAssertEqual(verify(mode: .keyEntry, registration: true), .ready)
        XCTAssertEqual(verify(mode: .keyEntry, registration: false), .aiModelCannotAuthenticate)
    }

    func testPluginsNotLoadedInEveryMode() {
        for mode in [Mode.keyEntry, .alreadyConfigured, .manualModelNeedsConfiguration] {
            XCTAssertEqual(verify(mode: mode, companion: false, registration: true), .pluginsNotLoaded, "\(mode)")
            XCTAssertEqual(verify(mode: mode, aiPlugin: false, registration: true), .pluginsNotLoaded, "\(mode)")
            XCTAssertEqual(verify(mode: mode, aiEnabled: false, registration: true), .pluginsNotLoaded, "\(mode)")
        }
        // Plugins missing outranks a model that can't authenticate.
        XCTAssertEqual(verify(mode: .keyEntry, aiPlugin: false, registration: false), .pluginsNotLoaded)
    }

    func testCompanionOnlyIgnoresAI() {
        XCTAssertEqual(verify(full: false, mode: .keyEntry, aiPlugin: false, aiEnabled: false, registration: false),
                       .ready)
        XCTAssertEqual(verify(full: false, mode: .keyEntry, companion: false, registration: true),
                       .pluginsNotLoaded)
    }
}
