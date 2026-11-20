//
//  PTYSession+Twin.swift
//  iTerm2SharedARC
//
//  A twin session shows what a live session shows. It starts from a copy of the live
//  session's screen and then parses a copy of every byte the live session reads.
//

import Foundation

extension PTYSession {
    private static let twinStartRetryInterval = DispatchTimeInterval.milliseconds(5)
    private static let twinStartMaximumAttempts = 100

    /// Main queue. Makes `twin`, a session with no program, show what this session shows.
    /// Reports failure when this session's queued tokens do not finish executing, such as when
    /// it is in copy mode, or when either session closes first.
    @objc(startTwin:completion:)
    func startTwin(_ twin: PTYSession, completion: @escaping (Bool) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        twin.isTwin = true
        continueStartingTwin(twin,
                             attemptsLeft: Self.twinStartMaximumAttempts,
                             holdingLock: false,
                             completion: completion)
    }

    private func continueStartingTwin(_ twin: PTYSession,
                                      attemptsLeft: Int,
                                      holdingLock: Bool,
                                      completion: @escaping (Bool) -> Void) {
        let retry = { [weak self] (holdingLock: Bool) in
            guard let self, attemptsLeft > 0 else {
                if holdingLock {
                    self?.twinFeedLock.unlock()
                }
                completion(false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.twinStartRetryInterval) {
                self.continueStartingTwin(twin,
                                          attemptsLeft: attemptsLeft - 1,
                                          holdingLock: holdingLock,
                                          completion: completion)
            }
        }
        if twinStartCancelled || twin.twinStartCancelled {
            // One of the two sessions closed while the twin was starting.
            if holdingLock {
                twinFeedLock.unlock()
            }
            completion(false)
            return
        }
        // The reader thread holds the lock while it parses, and it can wait there for room in
        // the token queue. Never block the main queue on it.
        guard holdingLock || twinFeedLock.try() else {
            retry(false)
            return
        }
        // No byte can arrive now. The screen matches the bytes read so far once the tokens that
        // are already queued have executed.
        var hasPendingWork = false
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let executor = mutableState.tokenExecutor
            hasPendingWork = executor.hasPendingWork
            if hasPendingWork {
                executor.schedule()
            }
        })
        if hasPendingWork {
            retry(true)
            return
        }
        copyTerminalState(toTwin: twin)
        if let previous = self.twin, previous !== twin, previous.twinSource === self {
            previous.twinSource = nil
        }
        twin.twinSource = self
        self.twin = twin
        twinFeedLock.unlock()
        updateTwinTab()
        completion(true)
    }
}
