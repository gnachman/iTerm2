//
//  CompanionGateTests.swift
//  iTerm2 ModernTests
//
//  The companion pairing gate must no longer depend on AI: a mac with the
//  companion plugin installed and consented can pair and serve a phone even when
//  AI is off. These tests exercise the pure cores of gate() and aiAvailable() so
//  the contract holds deterministically, without installing either plugin.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class CompanionGateTests: XCTestCase {
    // With every companion prerequisite satisfied, the gate is open regardless of
    // AI: this is the whole point of the decoupling. The core takes no AI input,
    // so no AI state can affect the verdict.
    func testCompanionReadyGateIsAllowedWithoutAI() {
        XCTAssertEqual(
            CompanionPairingController.gate(companionPairingAllowed: true,
                                            companionPluginInstalled: true,
                                            companionConsented: true),
            .allowed)
    }

    // gate() must never return an AI verdict for ANY combination of its inputs.
    // If someone re-adds an AI prerequisite, it would have to surface as one of
    // the .ai* cases, which this exhaustive sweep forbids.
    func testGateNeverReturnsAnAICase() {
        let aiCases: Set<CompanionPairingController.Gate> = [.aiAdminDisabled, .aiPluginMissing, .aiConsentNeeded]
        for allowed in [true, false] {
            for plugin in [true, false] {
                for consent in [true, false] {
                    let verdict = CompanionPairingController.gate(companionPairingAllowed: allowed,
                                                                 companionPluginInstalled: plugin,
                                                                 companionConsented: consent)
                    XCTAssertFalse(aiCases.contains(verdict),
                                   "gate(\(allowed),\(plugin),\(consent)) must not be an AI verdict, got \(verdict)")
                }
            }
        }
    }

    // The companion prerequisites are checked in a fixed order (admin, plugin,
    // consent), so the first unmet one names the remedy.
    func testGateReportsFirstUnmetCompanionPrerequisite() {
        XCTAssertEqual(
            CompanionPairingController.gate(companionPairingAllowed: false,
                                            companionPluginInstalled: false,
                                            companionConsented: false),
            .companionAdminDisabled)
        XCTAssertEqual(
            CompanionPairingController.gate(companionPairingAllowed: true,
                                            companionPluginInstalled: false,
                                            companionConsented: false),
            .companionPluginMissing)
        XCTAssertEqual(
            CompanionPairingController.gate(companionPairingAllowed: true,
                                            companionPluginInstalled: true,
                                            companionConsented: false),
            .companionConsentNeeded)
    }

    // AI is available only when all three facts hold; any one missing means off.
    func testAIAvailableTruthTable() {
        XCTAssertTrue(CompanionPairingController.aiAvailable(generativeAIAllowed: true,
                                                            pluginInstalled: true,
                                                            consented: true))
        for (allowed, plugin, consent) in [(false, true, true), (true, false, true), (true, true, false)] {
            XCTAssertFalse(CompanionPairingController.aiAvailable(generativeAIAllowed: allowed,
                                                                 pluginInstalled: plugin,
                                                                 consented: consent),
                           "AI must be unavailable when any prerequisite is missing")
        }
    }

    // The bridge sends the typed .aiUnavailable error only to a phone that can
    // decode it (revision >= 13, spelled out here since ModernTests can't link the
    // CompanionProtocol module). An older phone gets .internalError instead so the
    // unknown code string never drops its whole frame. Revision 0 is an unpaired /
    // incompatible peer (peerRevision is reset to 0 there), which must not qualify.
    func testPeerUnderstandsAIUnavailableCodeBoundary() {
        let aiDecouplingRevision = 13
        XCTAssertTrue(CompanionHostBridge.peerUnderstandsAIUnavailableCode(peerRevision: aiDecouplingRevision))
        XCTAssertTrue(CompanionHostBridge.peerUnderstandsAIUnavailableCode(peerRevision: aiDecouplingRevision + 1))
        XCTAssertFalse(CompanionHostBridge.peerUnderstandsAIUnavailableCode(peerRevision: aiDecouplingRevision - 1))
        XCTAssertFalse(CompanionHostBridge.peerUnderstandsAIUnavailableCode(peerRevision: 0))
    }
}
