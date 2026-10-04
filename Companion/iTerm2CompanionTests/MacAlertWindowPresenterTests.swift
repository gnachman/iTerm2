//
//  MacAlertWindowPresenterTests.swift
//  iTerm2CompanionTests
//
//  The Mac alert card is shown in its own window, above the app's, so it
//  appears over any sheet. These tests pin that the window really is put on
//  screen when the model says to show the card, at a level above the app's
//  windows, and taken down when the alert goes away or is set aside.
//

import XCTest
import SwiftUI
import UIKit
import CompanionProtocol
@testable import iTerm2Companion

@MainActor
final class MacAlertWindowPresenterTests: XCTestCase {
    private func alert(_ id: String, isAppModal: Bool = true) -> CompanionModalAlert {
        return CompanionModalAlert(
            id: id,
            heading: "Heading",
            body: "Body",
            buttons: [.init(title: "OK", isCancel: false, isDestructive: false, rememberable: true)],
            suppressionLabel: nil,
            hasAccessory: false,
            isAppModal: isAppModal)
    }

    private func model(showing alerts: [CompanionModalAlert]) -> AppModel {
        let model = AppModel()
        model.testApplyHandshake(CompanionClient.HandshakeResult(
            compatibility: .compatible,
            wantsNotificationPermission: false,
            peerRevision: CompanionProtocolVersion.modalAlertRevision,
            aiAvailable: true,
            macStatus: CompanionMacStatus(modalAlerts: alerts, mainBlocked: false)))
        return model
    }

    /// The windows above the app's normal ones, in any scene.
    private func alertLevelWindows() -> [UIWindow] {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .filter { $0.windowLevel == .alert && !$0.isHidden }
    }

    func test_cardWindowIsShownForAnAlertAndRemovedWhenItGoesAway() throws {
        let presenter = MacAlertWindowPresenter()
        let model = model(showing: [alert("A")])
        presenter.update(model: model)
        XCTAssertTrue(presenter.isShowing)
        let window = try XCTUnwrap(alertLevelWindows().first, "the card's window is not on screen")
        XCTAssertNotNil(window.rootViewController)
        XCTAssertEqual(window.frame, window.windowScene?.screen.bounds, "it covers the screen")

        model.testHandleHostEvent(.macStatusChanged(status: CompanionMacStatus(modalAlerts: [], mainBlocked: false)))
        presenter.update(model: model)
        XCTAssertFalse(presenter.isShowing)
        XCTAssertEqual(alertLevelWindows().count, 0)
    }

    func test_cardWindowIsNotShownForAPillOrABanner() {
        let presenter = MacAlertWindowPresenter()
        // A sheet that does not block the Mac is only a pill.
        presenter.update(model: model(showing: [alert("A", isAppModal: false)]))
        XCTAssertFalse(presenter.isShowing)

        // Set aside with “Not now”.
        let setAside = model(showing: [alert("A")])
        presenter.update(model: setAside)
        XCTAssertTrue(presenter.isShowing)
        setAside.dismissMacAlert()
        presenter.update(model: setAside)
        XCTAssertFalse(presenter.isShowing)
        XCTAssertEqual(alertLevelWindows().count, 0)
    }

    /// The whole path, as the app runs it: the root view is on screen, the Mac
    /// reports an alert, and the card's window appears without anything else
    /// asking for it. Then the alert goes away and so does the window.
    func test_rootViewShowsAndHidesTheCardAsTheMacStatusChanges() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let model = AppModel()
        let host = UIWindow(windowScene: scene)
        host.rootViewController = UIHostingController(rootView: RootView().environment(model))
        host.isHidden = false
        defer { host.isHidden = true }

        func waitUntil(_ what: String, _ condition: () -> Bool) async {
            // SwiftUI applies the change on a later turn of the run loop. The
            // limit only matters if it never does.
            for _ in 0..<200 where !condition() {
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            XCTAssertTrue(condition(), what)
        }

        model.testApplyHandshake(CompanionClient.HandshakeResult(
            compatibility: .compatible,
            wantsNotificationPermission: false,
            peerRevision: CompanionProtocolVersion.modalAlertRevision,
            aiAvailable: true,
            macStatus: CompanionMacStatus(modalAlerts: [alert("A")], mainBlocked: true)))
        await waitUntil("the card's window never appeared") { MacAlertWindowPresenter.shared.isShowing }

        model.testHandleHostEvent(.macStatusChanged(status: CompanionMacStatus(modalAlerts: [], mainBlocked: false)))
        await waitUntil("the card's window never went away") { !MacAlertWindowPresenter.shared.isShowing }
    }
}
