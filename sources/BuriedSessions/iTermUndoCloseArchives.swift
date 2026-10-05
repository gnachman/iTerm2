//
//  iTermUndoCloseArchives.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/4/26.
//

import Foundation

// The archives of sessions in an undo-close group whose undo window ran out.
// Undo restores each one from its archive in the place of the session it
// replaces.
@objc
class iTermUndoCloseArchives: NSObject {
    // Session GUID -> archived session arrangement, marked to restore as an archive.
    private var sessionArrangements = [String: [AnyHashable: Any]]()
    // Session GUID -> the archive's tab arrangement containing only that session.
    private var tabArrangements = [String: [AnyHashable: Any]]()
    // Sessions whose archive could not be read. They are restored empty so the
    // layout around them stays intact.
    private var unreadableGUIDs = Set<String>()
    private let guids: [String]
    private let pathsBySessionGUID: [String: String]

    @objc(initWithPathsBySessionGUID:)
    init(pathsBySessionGUID: [String: String]) {
        self.pathsBySessionGUID = pathsBySessionGUID
        guids = pathsBySessionGUID.keys.sorted()
        super.init()
        for guid in guids {
            guard let path = pathsBySessionGUID[guid],
                  let tab = Self.tabArrangement(forSessionWithGUID: guid, archivePath: path) else {
                unreadableGUIDs.insert(guid)
                continue
            }
            tabArrangements[guid] = Self.markingArchivedSessions(in: tab, path: path)
            if let session = PTYTab.arrangementForSession(withGUID: guid, inArrangement: tab) {
                sessionArrangements[guid] = PTYSession.arrangement(session, markedAsArchiveAtPath: path)
            }
        }
    }

    // Returns a tab arrangement with each archived session's arrangement in
    // place of the arrangement of the session it replaces.
    @objc(tabArrangementBySubstitutingArchivesIn:)
    func tabArrangementBySubstitutingArchives(in tabArrangement: [AnyHashable: Any]) -> [AnyHashable: Any] {
        return PTYTab.modifiedArrangement(tabArrangement) { sessionArrangement in
            guard let sessionArrangement else {
                return nil
            }
            guard let guid = PTYSession.guid(inArrangement: sessionArrangement) else {
                return sessionArrangement
            }
            if let archived = self.sessionArrangements[guid] {
                return archived
            }
            if self.unreadableGUIDs.contains(guid), let path = self.pathsBySessionGUID[guid] {
                return PTYSession.arrangement(sessionArrangement, markedAsArchiveAtPath: path)
            }
            return sessionArrangement
        }
    }

    // Like tabArrangementBySubstitutingArchivesIn: for each tab in a window arrangement.
    @objc(windowArrangementBySubstitutingArchivesIn:)
    func windowArrangementBySubstitutingArchives(in windowArrangement: [AnyHashable: Any]) -> [AnyHashable: Any] {
        guard let tabs = windowArrangement[TERMINAL_ARRANGEMENT_TABS] as? [[AnyHashable: Any]] else {
            return windowArrangement
        }
        var result = windowArrangement
        result[TERMINAL_ARRANGEMENT_TABS] = tabs.map { tabArrangementBySubstitutingArchives(in: $0) }
        return result
    }

    // One single-pane tab arrangement per archive, for when archived sessions
    // can't go back into their original layout.
    @objc var standaloneTabArrangements: [[AnyHashable: Any]] {
        return guids.compactMap { tabArrangements[$0] }
    }

    private static func tabArrangement(forSessionWithGUID guid: String,
                                       archivePath path: String) -> [AnyHashable: Any]? {
        guard let windowArrangement = NSDictionary(contentsOfFile: path) as? [AnyHashable: Any] else {
            RLog("Could not read archive at \(path) for undo close")
            return nil
        }
        let tabs = windowArrangement[TERMINAL_ARRANGEMENT_TABS] as? [[AnyHashable: Any]] ?? []
        guard let tab = tabs.first(where: { PTYTab.arrangementForSession(withGUID: guid, inArrangement: $0) != nil }) else {
            RLog("Archive at \(path) does not contain session \(guid)")
            return nil
        }
        return tab
    }

    private static func markingArchivedSessions(in tabArrangement: [AnyHashable: Any],
                                                path: String) -> [AnyHashable: Any] {
        return PTYTab.modifiedArrangement(tabArrangement) { sessionArrangement in
            guard let sessionArrangement else {
                return nil
            }
            return PTYSession.arrangement(sessionArrangement, markedAsArchiveAtPath: path)
        }
    }
}
