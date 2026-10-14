//
//  iTermTitleBatch.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/14/26.
//

import Foundation

/// A working directory fetch that a window title asked for, to be logged at
/// the line the cursor was on when the title arrived.
@objc(iTermTitleDirectoryFetch)
final class TitleDirectoryFetch: NSObject {
    @objc let absLine: Int64
    @objc let token: any iTermOrderedToken

    @objc(initWithAbsLine:token:)
    init(absLine: Int64, token: any iTermOrderedToken) {
        self.absLine = absLine
        self.token = token
    }
}

/// What a run of OSC 0, 1 and 2 sequences adds up to. Each title replaces the
/// one before it, so only the latest of each kind matters. A window title may
/// also ask for the working directory; see TitleBatch.
@objc(iTermTitleUpdate)
final class TitleUpdate: NSObject {
    @objc private(set) var setsWindowTitle = false
    @objc private(set) var windowTitle: String?
    @objc private(set) var setsIconTitle = false
    @objc private(set) var iconTitle: String?
    @objc private(set) var setsSubtitle = false
    @objc private(set) var subtitle: String?
    @objc private(set) var pollsLocalDirectoryOnly = false
    private var firstFetch: TitleDirectoryFetch?
    private var lastFetch: TitleDirectoryFetch?

    /// Where to log the working directory, in order: the first line asked
    /// for and, if it was another line, the last. Lines in between are
    /// dropped. The directory is fetched once for all of them, as the
    /// per-title fetches would all have found the same directory, and logging
    /// it at the first and last lines leaves the same working directory mark
    /// when the cursor only moves down: the mark for the first line is
    /// extended to the last. If it moved back up in between, the mark may end
    /// sooner, which does not change the directory found on any line.
    @objc var directoryFetches: [TitleDirectoryFetch] {
        return [firstFetch, lastFetch].compactMap { $0 }
    }

    @objc(changeWindowTitle:)
    func changeWindowTitle(_ title: String?) {
        setsWindowTitle = true
        windowTitle = title
    }

    @objc(changeIconTitle:)
    func changeIconTitle(_ title: String?) {
        setsIconTitle = true
        iconTitle = title
    }

    @objc(changeSubtitle:)
    func changeSubtitle(_ subtitle: String?) {
        setsSubtitle = true
        self.subtitle = subtitle
    }

    @objc
    func pollLocalDirectoryOnly() {
        pollsLocalDirectoryOnly = true
    }

    @objc(fetchWorkingDirectoryOnAbsLine:token:)
    func fetchWorkingDirectory(onAbsLine absLine: Int64, token: any iTermOrderedToken) {
        let fetch = TitleDirectoryFetch(absLine: absLine, token: token)
        guard let firstFetch else {
            firstFetch = fetch
            return
        }
        if firstFetch.absLine == absLine && lastFetch == nil {
            // Same line as the only fetch so far: the newer token supersedes
            // it.
            self.firstFetch = fetch
            return
        }
        lastFetch = fetch
    }
}

/// Title changes the mutation thread has parsed but the main thread has not
/// yet applied. A program can set the title as fast as it can write, and one
/// side effect per title would leave the main thread minutes behind, setting
/// titles nobody sees and fetching the working directory once per title, so
/// titles with no other side effect between them share one batch and one side
/// effect. The batch holds at most one title of each kind and two lines to log
/// the working directory at however long the run is.
///
/// The mutation thread adds; the main thread (or the mutation thread, while
/// joined) takes, once, after which the batch accepts nothing more.
@objc(iTermTitleBatch)
final class TitleBatch: NSObject {
    private let mutex = Mutex()
    private let update = TitleUpdate()
    private var taken = false

    /// Runs `block` on the pending update, unless the batch was already
    /// taken. Returns whether it ran.
    @objc(addUpdate:)
    func add(_ block: (TitleUpdate) -> Void) -> Bool {
        return mutex.sync {
            guard !taken else {
                return false
            }
            block(update)
            return true
        }
    }

    /// Returns the update and closes the batch.
    @objc
    func take() -> TitleUpdate {
        return mutex.sync {
            taken = true
            return update
        }
    }
}
