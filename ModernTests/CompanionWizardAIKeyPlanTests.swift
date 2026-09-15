//
//  CompanionWizardAIKeyPlanTests.swift
//  iTerm2 ModernTests
//
//  Reproduces the companion setup wizard storing the pasted API key under
//  LLMMetadata.effectiveVendor (via `AITermControllerObjC.apiKey =`) instead of
//  the Provider popup, then on rollback parking the old effective vendor's key
//  in the newly selected slot. CompanionWizardAIKeyPlan is the persist/rollback
//  installPressed uses; these tests assert the intended slots.
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionWizardAIKeyPlanTests: XCTestCase {

    // MARK: - Same vendor (control: persist/rollback round-trip that vendor)

    func testCommit_sameVendor_storesKeyOnThatVendor() {
        let write = CompanionWizardAIKeyPlan.commit(selectedVendor: .anthropic,
                                                    pastedKey: "sk-ant-new")
        XCTAssertEqual(write.vendor, .anthropic)
        XCTAssertEqual(write.key, "sk-ant-new")
        XCTAssertEqual(write.vendorPreference, Int(iTermAIVendor.anthropic.rawValue))
    }

    func testRollback_sameVendor_restoresOriginalKey() {
        let write = CompanionWizardAIKeyPlan.rollback(
            selectedVendor: .anthropic,
            priorSelectedVendorKey: "sk-ant-old",
            priorVendorRaw: Int(iTermAIVendor.anthropic.rawValue))
        XCTAssertEqual(write.vendor, .anthropic)
        XCTAssertEqual(write.key, "sk-ant-old")
        XCTAssertEqual(write.vendorPreference, Int(iTermAIVendor.anthropic.rawValue))
    }

    // MARK: - Cross vendor (the bug)

    func testCommit_crossVendor_storesKeyOnSelectedVendor() {
        // First-run default: OpenAI is the factory vendor (effectiveVendor),
        // the user picks Anthropic in the wizard and pastes an Anthropic key.
        // installPressed used to do:
        //   AITermControllerObjC.apiKey = pastedKey   // effectiveVendor = OpenAI
        //   iTermPreferences.setInt(anthropic, forKey: kPreferenceKeyAIVendor)
        // The Anthropic key must land in the Anthropic keychain account, or a
        // phone-originated chat (which reads the new default vendor) finds no key.
        let write = CompanionWizardAIKeyPlan.commit(selectedVendor: .anthropic,
                                                    pastedKey: "sk-ant-new")
        XCTAssertEqual(write.vendor, .anthropic,
                       "wizard stored the pasted key under \(write.vendor.rawValue), not the Provider popup")
        XCTAssertEqual(write.key, "sk-ant-new")
        XCTAssertEqual(write.vendorPreference, Int(iTermAIVendor.anthropic.rawValue))
    }

    func testRollback_crossVendor_restoresSelectedVendorPreviousKey() {
        // After the preference has flipped to Anthropic, installPressed used to:
        //   AITermControllerObjC.apiKey = priorAPIKey  // the OpenAI key snapshotted at start
        //   iTermPreferences.setInt(openAI, forKey: kPreferenceKeyAIVendor)
        // Anthropic had no key; rollback must restore that (nil), not park the
        // OpenAI secret in the Anthropic account.
        let write = CompanionWizardAIKeyPlan.rollback(
            selectedVendor: .anthropic,
            priorSelectedVendorKey: nil,
            priorVendorRaw: Int(iTermAIVendor.openAI.rawValue))
        XCTAssertEqual(write.vendor, .anthropic)
        XCTAssertNil(write.key,
                     "rollback wrote \(write.key ?? "nil") into the selected vendor; expected the selected vendor's previous key (nil)")
        XCTAssertEqual(write.vendorPreference, Int(iTermAIVendor.openAI.rawValue))
    }
}
