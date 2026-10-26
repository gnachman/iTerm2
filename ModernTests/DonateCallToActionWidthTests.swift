//
//  DonateCallToActionWidthTests.swift
//  ModernTests
//
//  QA findings F-230 and F-300: the donation link in the Settings and Edit
//  Session title bars picked a call to action at random regardless of its
//  width, so the long ones (in English, and most of the Russian ones)
//  truncated the window title. These pin that the link only offers calls to
//  action that leave the title room.
//

import XCTest
@testable import iTerm2SharedARC

final class DonateCallToActionWidthTests: XCTestCase {
    // The Edit Session window QA saw, which is the narrowest window with the
    // link.
    private let editSessionWidth: CGFloat = 589

    private func fitting(_ candidates: [String], maxWidth: CGFloat) -> [String] {
        var offered = [String]()
        _ = DonateViewController.callToAction(from: candidates, maxWidth: maxWidth) { fitting in
            offered = fitting
            return fitting.first
        }
        return offered
    }

    private func callsToAction(localization: String) -> [String] {
        guard let path = Bundle.main.path(forResource: "Localizable",
                                          ofType: "strings",
                                          inDirectory: nil,
                                          forLocalization: localization),
              let table = NSDictionary(contentsOfFile: path) as? [String: String] else {
            XCTFail("No Localizable.strings for \(localization)")
            return []
        }
        let result = table.filter { $0.key.hasPrefix("Donate.CallToAction") }.map { $0.value }
        XCTAssertEqual(result.count, 9, localization)
        return result
    }

    func testEditSessionDropsTheCallsToActionThatTruncatedItsTitle() {
        let maxWidth = DonateViewController.maxTextWidth(windowWidth: editSessionWidth, title: "Edit Session")
        let offered = fitting(DonateViewController.callsToAction, maxWidth: maxWidth)
        // Seen truncating the title in 3.7.4 and in QA.
        XCTAssertFalse(offered.contains("Support the creator of iTerm2 – Donate now!"))
        XCTAssertFalse(offered.contains("iTerm2 is one person’s project. Donate now!"))
        // Seen fitting beside the full title in 3.7.4.
        XCTAssertTrue(offered.contains("Keep the iTerm2 dream alive – Donate!"))
        XCTAssertTrue(offered.contains("Donate"))
    }

    func testWideWindowOffersEveryCallToAction() {
        let maxWidth = DonateViewController.maxTextWidth(windowWidth: 1200, title: "Settings")
        let all = DonateViewController.callsToAction
        XCTAssertEqual(Set(fitting(all, maxWidth: maxWidth)), Set(all))
    }

    func testRussianGeneralSettingsDropsTheLinkThatTruncatedItsTitle() {
        // F-230: the General pane in Russian is 800 points wide.
        let candidates = callsToAction(localization: "ru")
        let maxWidth = DonateViewController.maxTextWidth(windowWidth: 800, title: "Настройки")
        let offered = fitting(candidates, maxWidth: maxWidth)
        XCTAssertFalse(offered.contains("Сохраните мечту об iTerm2 живой: сделайте пожертвование!"))
        XCTAssertFalse(offered.isEmpty)
        XCTAssertLessThan(offered.count, candidates.count)
    }

    func testEveryOfferedCallToActionIsWithinTheLimit() {
        for localization in ["de", "ja", "pt-BR", "ru", "zh-Hans"] {
            let maxWidth = DonateViewController.maxTextWidth(windowWidth: editSessionWidth, title: "Edit Session")
            for text in fitting(callsToAction(localization: localization), maxWidth: maxWidth) {
                XCTAssertLessThanOrEqual(DismissableLinkViewController.width(of: text), maxWidth,
                                         "\(localization): \(text)")
            }
        }
    }

    func testFallsBackToTheNarrowestWhenNoneFits() {
        let chosen = DonateViewController.callToAction(from: DonateViewController.callsToAction, maxWidth: 0)
        XCTAssertEqual(chosen, "Donate")
    }
}
