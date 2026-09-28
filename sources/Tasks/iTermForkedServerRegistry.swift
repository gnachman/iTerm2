//
//  iTermForkedServerRegistry.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/23/26.
//

import Foundation

/// Socket numbers whose iTermServer *this* iTerm2 process forked.
///
/// Ownership decides whether new sessions may use a connection: a server this process forked
/// is attributed to the running app for TCC purposes, while one inherited from an earlier run
/// names a dead responsible process and loses permissions like Local Network access. See
/// issue 12106.
///
/// This has to be process-scoped rather than a flag on the client object, because a client can
/// be torn down while its server keeps running (a protocol error closes the connection but not
/// the daemon), and the next client to attach to that server must still recognize it as ours.
///
/// Socket numbers are a safe key because every socket in play belongs to this suite. Both the
/// application support directory and the dotdir fallback are per-suite, so running several
/// iTerm2 instances at once means running them under different suites, with separate socket
/// directories.
///
/// That yields the invariant this class depends on, and the reason it only ever grows: having
/// launched a server at a socket number once means the server there now is ours. Every server
/// from an earlier run already exists when we start, so if one is listening at N we attach to
/// it rather than launching, and N is never recorded. Once we have launched at N, the only
/// thing that can put a server there afterwards is this process doing it again.
@objc(iTermForkedServerRegistry)
class ForkedServerRegistry: NSObject {
    @objc(sharedInstance) static let shared = ForkedServerRegistry()

    private let mutex = Mutex()
    private var socketNumbers = Set<Int>()

    @objc(recordSocketNumber:)
    func record(socketNumber: Int) {
        mutex.sync { _ = socketNumbers.insert(socketNumber) }
    }

    /// Deliberately has no counterpart that removes a socket number, because the answer never
    /// stops being true in a useful sense: see the note on the invariant above.
    @objc(everLaunchedServerOnSocketNumber:)
    func everLaunchedServer(socketNumber: Int) -> Bool {
        return mutex.sync { socketNumbers.contains(socketNumber) }
    }
}
