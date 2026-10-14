//
//  CompanionWizardChooseModeLayoutTests.swift
//  iTerm2 ModernTests
//
//  QA findings F-267 and F-035: the companion wizard's choose-mode screen gave
//  each detail label a fixed two-line height, so the manual-model detail
//  (English) and the German terminal-only detail were cut off. These pin that
//  the labels are measured to fit their text and that the controls below a
//  taller label move down instead of overlapping it.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class CompanionWizardChooseModeLayoutTests: XCTestCase {
    private typealias Layout = CompanionWizardChooseModeLayout
    private let contentHeight: CGFloat = 560

    // MARK: - Measuring

    func testManualModelDetailNeedsMoreThanTwoLines() {
        let text = "Chat with the orchestrator and per-session agents. Requires the AI model selected in Settings > General > AI to be configured."
        let height = CompanionWizardWindowController.bodyLabelHeight(text)
        XCTAssertGreaterThan(height, Layout.minimumDetailHeight)
        XCTAssertGreaterThanOrEqual(height, threeLineHeight())
    }

    func testGermanTerminalOnlyDetailNeedsMoreThanTwoLines() {
        let text = "Durchsuchen Sie Sitzungen, verfolgen Sie die Live-Ausgabe und tippen Sie von Ihrem iPhone aus. Keine KI oder API-Schlüssel erforderlich."
        let height = CompanionWizardWindowController.bodyLabelHeight(text)
        XCTAssertGreaterThanOrEqual(height, threeLineHeight())
    }

    func testShortDetailKeepsTheDesignedTwoLineHeight() {
        XCTAssertEqual(CompanionWizardWindowController.bodyLabelHeight("No AI needed."),
                       Layout.minimumDetailHeight)
    }

    // MARK: - Screen layout

    func testScreenLayoutFitsBothLongDetails() {
        let manual = "Chat with the orchestrator and per-session agents. Requires the AI model selected in Settings > General > AI to be configured."
        let german = "Durchsuchen Sie Sitzungen, verfolgen Sie die Live-Ausgabe und tippen Sie von Ihrem iPhone aus. Keine KI oder API-Schlüssel erforderlich."
        let layout = CompanionWizardWindowController.chooseModeLayout(withAIDetail: manual,
                                                                      terminalOnlyDetail: german)
        let width = CompanionWizardWindowController.bodyLabelWidth
        let manualNeeds = Layout.fittingHeight(of: CompanionWizardWindowController.makeBodyLabel(manual),
                                               width: width)
        let germanNeeds = Layout.fittingHeight(of: CompanionWizardWindowController.makeBodyLabel(german),
                                               width: width)
        XCTAssertGreaterThanOrEqual(layout.withAIDetailHeight, manualNeeds)
        XCTAssertGreaterThanOrEqual(layout.terminalOnlyDetailHeight, germanNeeds)
        XCTAssertLessThanOrEqual(layout.terminalOnlyButtonY + Layout.buttonHeight, layout.withAIDetailY)
    }

    // MARK: - Stacking

    func testTwoLineDetailsKeepTheOriginalPositions() {
        let layout = Layout(contentHeight: contentHeight,
                            withAIDetailHeight: 34,
                            terminalOnlyDetailHeight: 34)
        XCTAssertEqual(layout.withAIButtonY, contentHeight - 230)
        XCTAssertEqual(layout.withAIDetailY, contentHeight - 268)
        XCTAssertEqual(layout.terminalOnlyButtonY, contentHeight - 320)
        XCTAssertEqual(layout.terminalOnlyDetailY, contentHeight - 358)
    }

    func testTallWithAIDetailPushesTerminalOnlyControlsDown() {
        let short = Layout(contentHeight: contentHeight,
                           withAIDetailHeight: 34,
                           terminalOnlyDetailHeight: 34)
        let tall = Layout(contentHeight: contentHeight,
                          withAIDetailHeight: 51,
                          terminalOnlyDetailHeight: 51)
        XCTAssertEqual(tall.withAIButtonY, short.withAIButtonY)
        XCTAssertEqual(tall.terminalOnlyButtonY, short.terminalOnlyButtonY - 17)
        XCTAssertEqual(tall.terminalOnlyDetailY, short.terminalOnlyDetailY - 34)

        // Nothing overlaps: each control's top is below the bottom of the one above.
        XCTAssertLessThanOrEqual(tall.withAIDetailY + tall.withAIDetailHeight, tall.withAIButtonY)
        XCTAssertLessThanOrEqual(tall.terminalOnlyButtonY + Layout.buttonHeight, tall.withAIDetailY)
        XCTAssertLessThanOrEqual(tall.terminalOnlyDetailY + tall.terminalOnlyDetailHeight,
                                 tall.terminalOnlyButtonY)
        XCTAssertGreaterThanOrEqual(tall.terminalOnlyDetailY, 0)
    }

    // MARK: - Helpers

    /// The height of three lines in the body label's font, measured the same
    /// way the screen measures its labels.
    private func threeLineHeight() -> CGFloat {
        let label = CompanionWizardWindowController.makeBodyLabel("A\nB\nC")
        return Layout.fittingHeight(of: label, width: CompanionWizardWindowController.bodyLabelWidth)
    }
}
