//
//  AppModelBrowserStreamTests.swift
//  iTerm2CompanionTests
//
//  A streamed web browser session is interactive only with a Mac at
//  browserInputRevision: the stream config marks it as a browser, and the Mac's
//  browserEditingChanged events drive the keyboard, and its
//  browserNavigationChanged events drive the browser controls.
//

import XCTest
import CompanionProtocol
@testable import iTerm2Companion

@MainActor
final class AppModelBrowserStreamTests: XCTestCase {
    private func config(streamID: UInt32, isBrowser: Bool) -> CompanionStreamConfig {
        CompanionStreamConfig(streamID: streamID, generationId: 1, codecExtradata: Data(),
                              pixelWidth: 800, pixelHeight: 600, scale: 2, columns: 0, rows: 0,
                              canResize: false, isBrowser: isBrowser)
    }

    private func model(macRevision: Int, streamID: UInt32 = 3) -> AppModel {
        let model = AppModel()
        model.testSetMacRevision(macRevision)
        model.testSetActiveStreamID(streamID)
        return model
    }

    func test_browserStreamIsInteractiveWithCurrentMac() {
        let model = model(macRevision: CompanionProtocolVersion.browserInputRevision)
        model.testHandleHostEvent(.streamConfig(config(streamID: 3, isBrowser: true)))
        XCTAssertTrue(model.activeStreamIsBrowser)
        XCTAssertTrue(model.browserInputActive)
    }

    func test_browserStreamIsViewOnlyWithOlderMac() {
        let model = model(macRevision: CompanionProtocolVersion.browserInputRevision - 1)
        model.testHandleHostEvent(.streamConfig(config(streamID: 3, isBrowser: true)))
        XCTAssertTrue(model.activeStreamIsBrowser)
        XCTAssertFalse(model.browserInputActive)
    }

    func test_terminalStreamIsNotBrowserInput() {
        let model = model(macRevision: CompanionProtocolVersion.browserInputRevision)
        model.testHandleHostEvent(.streamConfig(config(streamID: 3, isBrowser: false)))
        XCTAssertFalse(model.browserInputActive)
    }

    func test_editingFollowsEventsForTheActiveStreamOnly() {
        let model = model(macRevision: CompanionProtocolVersion.browserInputRevision)
        model.testHandleHostEvent(.streamConfig(config(streamID: 3, isBrowser: true)))
        model.testHandleHostEvent(.browserEditingChanged(streamID: 3, editing: true))
        XCTAssertTrue(model.activeStreamBrowserEditing)
        // An event for a stream that is no longer being watched is ignored.
        model.testHandleHostEvent(.browserEditingChanged(streamID: 99, editing: false))
        XCTAssertTrue(model.activeStreamBrowserEditing)
        model.testHandleHostEvent(.browserEditingChanged(streamID: 3, editing: false))
        XCTAssertFalse(model.activeStreamBrowserEditing)
    }

    /// The mac reports editing before its first stream config arrives; the config
    /// must not discard it, so a field that already has focus raises the keyboard.
    func test_editingReportedBeforeConfigSurvivesIt() {
        let model = model(macRevision: CompanionProtocolVersion.browserInputRevision)
        model.testHandleHostEvent(.browserEditingChanged(streamID: 3, editing: true))
        model.testHandleHostEvent(.streamConfig(config(streamID: 3, isBrowser: true)))
        XCTAssertTrue(model.activeStreamBrowserEditing)
        XCTAssertTrue(model.browserInputActive)
    }

    func test_streamEndClearsEditing() {
        let model = model(macRevision: CompanionProtocolVersion.browserInputRevision)
        model.testHandleHostEvent(.streamConfig(config(streamID: 3, isBrowser: true)))
        model.testHandleHostEvent(.browserEditingChanged(streamID: 3, editing: true))
        model.testHandleHostEvent(.streamEnded(streamID: 3, reason: .sessionClosed))
        XCTAssertFalse(model.activeStreamBrowserEditing)
    }

    func test_navigationFollowsEventsForTheActiveStreamOnly() {
        let model = model(macRevision: CompanionProtocolVersion.browserInputRevision)
        model.testHandleHostEvent(.streamConfig(config(streamID: 3, isBrowser: true)))
        XCTAssertNil(model.activeStreamBrowserNavigation)
        let state = CompanionBrowserNavigationState(url: "https://iterm2.com/", title: "iTerm2",
                                                    canGoBack: true, canGoForward: false, isLoading: false)
        model.testHandleHostEvent(.browserNavigationChanged(streamID: 3, state: state))
        XCTAssertEqual(model.activeStreamBrowserNavigation, state)
        let other = CompanionBrowserNavigationState(url: "https://example.com/", title: "",
                                                    canGoBack: false, canGoForward: false, isLoading: true)
        model.testHandleHostEvent(.browserNavigationChanged(streamID: 99, state: other))
        XCTAssertEqual(model.activeStreamBrowserNavigation, state)
    }

    func test_streamEndClearsNavigation() {
        let model = model(macRevision: CompanionProtocolVersion.browserInputRevision)
        model.testHandleHostEvent(.streamConfig(config(streamID: 3, isBrowser: true)))
        let state = CompanionBrowserNavigationState(url: "https://iterm2.com/", title: "iTerm2",
                                                    canGoBack: true, canGoForward: false, isLoading: false)
        model.testHandleHostEvent(.browserNavigationChanged(streamID: 3, state: state))
        model.testHandleHostEvent(.streamEnded(streamID: 3, reason: .sessionClosed))
        XCTAssertNil(model.activeStreamBrowserNavigation)
    }
}
