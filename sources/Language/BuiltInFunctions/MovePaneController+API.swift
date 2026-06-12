//
//  MovePaneController+API.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/11/26.
//

import Foundation

extension MovePaneController {
    enum MoveSessionError: Error, LocalizedError {
        case locked
        case noSourceTab
        case noSourceWindow
        case onlyOneSession
        case tmuxAsync
        case insertFailed

        var errorDescription: String? {
            switch self {
            case .locked: return "Session is locked"
            case .noSourceTab: return "Session has no tab"
            case .noSourceWindow: return "Session has no window"
            case .onlyOneSession: return "Tab has only one session"
            case .tmuxAsync: return "tmux sessions are moved asynchronously"
            case .insertFailed: return "Failed to insert session"
            }
        }
    }

    private struct SourceInfo {
        let tab: PTYTab
        let window: PseudoTerminal
    }

    private func sourceInfo(for session: PTYSession) throws -> SourceInfo {
        if session.locked {
            throw MoveSessionError.locked
        }
        let controller = iTermController.sharedInstance()!
        guard let tab = controller.tab(for: session) else {
            throw MoveSessionError.noSourceTab
        }
        guard let window = controller.window(for: tab) else {
            throw MoveSessionError.noSourceWindow
        }
        return SourceInfo(tab: tab, window: window)
    }

    /// Extract a session from its tab and insert it into a destination window
    /// as a new tab at the given index.
    ///
    /// Handles unmaximizing, removal, insertion, and notifications.
    /// Closes the source tab if it becomes empty.
    ///
    /// - Returns: The new tab's uniqueId.
    private func extractAndInsert(_ session: PTYSession,
                                  from source: SourceInfo,
                                  into destWindow: PseudoTerminal,
                                  at insertIndex: Int32) throws -> Int32 {
        if source.tab.hasMaximizedPane() {
            source.tab.unmaximize()
        }

        source.tab.remove(session)
        if source.tab.sessions()?.count == 0 {
            source.window.close(source.tab)
        }

        guard let newTab = destWindow.insert(session, at: insertIndex) else {
            throw MoveSessionError.insertFailed
        }
        source.tab.numberOfSessionsDidChange()
        destWindow.currentTab()?.numberOfSessionsDidChange()
        NotificationCenter.default.post(
            name: .iTermSessionDidChangeTab,
            object: session)
        session.didMove()
        return Int32(newTab.uniqueId)
    }

    // MARK: - Public API

    /// Move a session from a split pane into a new tab.
    ///
    /// - Parameters:
    ///   - session: The session to move.
    ///   - destWindow: The window to create the tab in.
    ///   - index: Tab index, or -1 to place after the source tab (same window)
    ///     or at the end (different window).
    /// - Returns: The new tab's uniqueId, or -1 on failure.
    @objc func moveSession(_ session: PTYSession,
                           toNewTabIn destWindow: PseudoTerminal,
                           atIndex index: Int32) -> Int32 {
        do {
            let source = try sourceInfo(for: session)
            let sameWindow = destWindow === source.window
            if sameWindow && (source.tab.sessions()?.count ?? 0) < 2 {
                return -1
            }

            if session.isTmuxClient {
                session.tmuxController?.breakOutWindowPane(session.tmuxPane,
                                                           toTabAside: destWindow.terminalGuid)
                return -1
            }

            let insertIndex: Int32
            if index >= 0 {
                insertIndex = index
            } else if sameWindow {
                let i = destWindow.tabs()?.firstIndex(of: source.tab)
                insertIndex = i.map { Int32($0) + 1 } ?? destWindow.numberOfTabs()
            } else {
                insertIndex = destWindow.numberOfTabs()
            }

            return try extractAndInsert(session,
                                        from: source,
                                        into: destWindow,
                                        at: insertIndex)
        } catch {
            return -1
        }
    }

    /// Move a session from a split pane into a new window.
    ///
    /// Creates a new window matching the source window's type. For
    /// drag-and-drop with a specific point, use the ObjC
    /// ``moveSessionToNewWindow:atPoint:`` instead.
    ///
    /// - Parameter session: The session to move.
    /// - Returns: The new window's terminalGuid, or nil on failure.
    @objc func moveSession(toNewWindow session: PTYSession) -> String? {
        do {
            let source = try sourceInfo(for: session)

            if session.isTmuxClient {
                session.tmuxController?.breakOutWindowPane(
                    session.tmuxPane,
                    to: source.window.window?.frame.origin ?? .zero)
                return nil
            }

            var point = source.window.window?.frame.origin ?? .zero
            point.x += 20
            point.y -= 20
            guard let newTerm = source.window.terminalDraggedFromAnotherWindow(at: point)
                    as? PseudoTerminal else {
                return nil
            }

            _ = try extractAndInsert(session,
                                     from: source,
                                     into: newTerm,
                                     at: 0)
            return newTerm.terminalGuid
        } catch {
            return nil
        }
    }
}
