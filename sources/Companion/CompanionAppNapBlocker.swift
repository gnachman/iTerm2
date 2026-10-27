//
//  CompanionAppNapBlocker.swift
//  iTerm2
//
//  Keeps App Nap off while a phone is paired. When the displays sleep, every
//  window is hidden and macOS naps the app: the main thread runs at low
//  priority, and requests from the phone wait seconds for it. The phone then
//  shows that the Mac is busy and is slow to connect. A paired Mac must be
//  ready to answer the phone at any moment, so it opts out for as long as the
//  pairing lasts. Idle system sleep is still allowed.
//

import Foundation

final class CompanionAppNapBlocker {
    private let begin: () -> NSObjectProtocol
    private let end: (NSObjectProtocol) -> Void
    private var activity: NSObjectProtocol?

    /// - begin: starts an activity that prevents App Nap. Injected for tests.
    /// - end: ends an activity returned by `begin`.
    init(begin: @escaping () -> NSObjectProtocol = {
             // Localization unneeded: the reason is only shown in debugging tools.
             ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                   reason: "An iTerm2 Buddy phone is paired")
         },
         end: @escaping (NSObjectProtocol) -> Void = {
             ProcessInfo.processInfo.endActivity($0)
         }) {
        self.begin = begin
        self.end = end
    }

    func setPaired(_ paired: Bool) {
        if paired {
            guard activity == nil else {
                return
            }
            RLog("Companion: paired; preventing App Nap")
            activity = begin()
        } else {
            guard let activity else {
                return
            }
            RLog("Companion: unpaired; allowing App Nap")
            end(activity)
            self.activity = nil
        }
    }
}
