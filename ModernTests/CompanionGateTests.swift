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

    // gate() only ever yields companion verdicts (or .allowed) for ANY combination
    // of its inputs. The Gate enum no longer even has AI cases, so this is enforced
    // by the type system too; the sweep documents that no input path is missed.
    func testGateOnlyYieldsCompanionVerdicts() {
        let companionCases: Set<CompanionPairingController.Gate> =
            [.allowed, .companionAdminDisabled, .companionPluginMissing, .companionConsentNeeded]
        for allowed in [true, false] {
            for plugin in [true, false] {
                for consent in [true, false] {
                    let verdict = CompanionPairingController.gate(companionPairingAllowed: allowed,
                                                                 companionPluginInstalled: plugin,
                                                                 companionConsented: consent)
                    XCTAssertTrue(companionCases.contains(verdict),
                                  "gate(\(allowed),\(plugin),\(consent)) must be a companion verdict, got \(verdict)")
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

    // The single AI gate keys off aiRequirement(of:). These pin the classification
    // that the dispatch relies on, especially the cases that were bugs: persistence
    // and cleanup (setChatMuted, unsubscribe) must be OPEN so they run with AI off,
    // and the push-fetch messages must be MIXED so their handlers classify the
    // connection before deciding whether to serve.
    func testAIRequirementClassification() {
        func req(_ m: CompanionClientMessage) -> CompanionHostBridge.AIRequirement {
            CompanionHostBridge.aiRequirement(of: m)
        }
        // Open: persistence/cleanup and non-AI interaction.
        XCTAssertEqual(req(.setChatMuted(chatID: "c", muted: true)), .open)
        XCTAssertEqual(req(.unsubscribe(chatID: "c")), .open)
        XCTAssertEqual(req(.fetchSessionTree), .open)
        XCTAssertEqual(req(.sendKey(sessionGuid: "g", event: CompanionKeyEvent(key: .text("x")))), .open)
        XCTAssertEqual(req(.ping), .open)
        // Mixed: partially served with AI off; must classify before gating.
        XCTAssertEqual(req(.listChatsAndSessions), .mixed)
        XCTAssertEqual(req(.messagesSince(collapseToken: "t", seq: 0, limit: 1, nonce: nil)), .mixed)
        XCTAssertEqual(req(.syncSince(messageSeq: 0, alertSeq: 0, limit: 1, nonce: nil)), .mixed)
        // AI-only: refused with AI off.
        XCTAssertEqual(req(.createChat(title: "t", mode: .orchestrator)), .aiOnly)
        XCTAssertEqual(req(.publish(message: Message(chatID: "c", author: .user, content: .markdown("x"),
                                                     sentDate: Date(timeIntervalSince1970: 0), uniqueID: UUID()),
                                    toChatID: "c", partial: false)), .aiOnly)
        XCTAssertEqual(req(.subscribe(chatID: "c")), .aiOnly)
    }
}
