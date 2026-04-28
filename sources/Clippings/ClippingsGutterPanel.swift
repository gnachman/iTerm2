//
//  ClippingsGutterPanel.swift
//  iTerm2SharedARC
//
//  Hosts the clippings UI inside the right-gutter panel framework. The
//  panel is owned by SessionView's iTermRightGutterController; we look up
//  the live PTYSession via the SessionView's delegate so peer-swaps don't
//  leave the panel pointing at a stale session.
//

import AppKit
import Foundation

@objc(iTermClippingsGutterPanel)
class iTermClippingsGutterPanel: NSObject, iTermRightGutterPanel {
    @objc static let panelIdentifier = "com.iterm2.clippings"

    weak var panelDelegate: iTermRightGutterPanelDelegate?

    var identifier: String { iTermClippingsGutterPanel.panelIdentifier }

    private let clippingsView = iTermClippingsView(delegate: nil)
    private weak var attachedSession: PTYSession?
    private var addPanel: AddClippingPanel?

    override init() {
        super.init()
        clippingsView.delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clippingsDidChange(_:)),
            name: PTYSession.clippingsDidChangeNotification,
            object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - iTermRightGutterPanel

    var view: NSView { clippingsView }

    var width: CGFloat { iTermClippingsView.fixedWidth }

    var visible: Bool {
        return currentSession?.clippingsVisible ?? false
    }

    func attach(to session: PTYSession) {
        attachedSession = session
        clippingsView.reload()
    }

    func detach() {
        attachedSession = nil
    }

    // MARK: - Notifications

    @objc private func clippingsDidChange(_ note: Notification) {
        clippingsView.reload()
        panelDelegate?.rightGutterPanelDidChangeWidthOrVisibility(self)
    }

    // The panel is hosted inside one SessionView and the gutter controller
    // doesn't re-call attachToSession when peers swap, so resolve the live
    // session through the SessionView's current delegate.
    private var currentSession: PTYSession? {
        if let live = clippingsView.superview as? SessionView,
           let session = live.delegate as? PTYSession {
            return session
        }
        return attachedSession
    }
}

extension iTermClippingsGutterPanel: iTermClippingsViewDelegate {
    func clippingsViewClippings(_ view: iTermClippingsView) -> [PTYSessionClipping] {
        return currentSession?.clippings ?? []
    }

    func clippingsView(_ view: iTermClippingsView,
                       didChangeClippings newClippings: [PTYSessionClipping]) {
        guard let session = currentSession else { return }
        session.clippings = newClippings
        session.clippingsDidChange()
    }

    func clippingsView(_ view: iTermClippingsView,
                       pasteText text: String) {
        currentSession?.paste(text, flags: [])
    }

    func clippingsViewDidRequestClose(_ view: iTermClippingsView) {
        currentSession?.clippingsVisible = false
    }

    func clippingsView(_ view: iTermClippingsView,
                       presentAddSheetWithCompletion completion: @escaping (PTYSessionClipping?) -> Void) {
        guard let session = currentSession,
              let window = session.view.window else {
            completion(nil)
            return
        }
        let panel = AddClippingPanel()
        addPanel = panel
        panel.present(over: window) { [weak self] clipping in
            self?.addPanel = nil
            completion(clipping)
        }
    }
}

@objc(iTermClippingsGutterPanelRegistration)
class iTermClippingsGutterPanelRegistration: NSObject {
    @objc static func register() {
        iTermRightGutterPanelRegistry.sharedInstance().registerPanelType(
            iTermClippingsGutterPanel.panelIdentifier,
            factory: { iTermClippingsGutterPanel() },
            widthProvider: { _, session in
                guard let session, session.clippingsVisible else {
                    return 0
                }
                return iTermClippingsView.fixedWidth
            })
    }
}
