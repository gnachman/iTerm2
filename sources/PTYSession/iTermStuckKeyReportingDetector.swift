//
//  iTermStuckKeyReportingDetector.swift
//  iTerm2SharedARC
//
//  Created by George Nachman.
//

import Foundation

/// Decides whether the command that just finished left the kitty keyboard
/// protocol enabled behind it, so iTerm2 can offer to put it back - the "an ssh
/// session died or an app crashed" case.
///
/// The naive test is "key reporting was off when the command started and is on
/// now", but that misfires for anyone whose shell drives the mode itself. Fish
/// 4.x arms the protocol while drawing its prompt, and a prompt renderer like
/// oh-my-posh emits FTCS D from inside the prompt function, so the flags sampled
/// at D are the shell's own - already armed for the prompt being drawn - rather
/// than an app's leftovers. See issue 13032.
///
/// The flag value is identical either way, so it cannot be the discriminator.
/// What differs is the behavior of the shell at the prompt. A shell that writes
/// the mode while it owns the terminal and drives it to zero before running a
/// command sets it with `CSI = flags ; 1 u`, which replaces the flags outright,
/// so anything an app left behind is gone by the next prompt. There is nothing
/// for the offer to restore. A shell that never touches the mode leaves an app's
/// flags standing, which is exactly when the offer is worth showing.
///
/// That verdict is recomputed at every command start rather than latched, so it
/// describes whichever shell is currently at the prompt: a local Fish and a
/// remote Bash reached over ssh get different answers, one command apart.
@objc(iTermStuckKeyReportingDetector)
class StuckKeyReportingDetector: NSObject {
    /// Did anyone assign the whole key reporting mode while the shell owned the
    /// terminal, i.e. since the FTCS D that closed the last command? The window
    /// deliberately excludes the command's own run: an app that leaks flags
    /// writes between FTCS C and FTCS D and must never be mistaken for the
    /// shell.
    ///
    /// Only a whole-value write counts, because only that kind supports the
    /// inference below. A shell that brackets its prompt with push/pop, or that
    /// sets and clears individual bits with modes 2 and 3, restores the mode it
    /// found rather than replacing it - so an app's leftovers survive its next
    /// prompt and the offer is still worth showing.
    private var replacedModeWhileShellOwnedTerminal = false

    /// Does the shell at the prompt drive the mode itself? See the class
    /// comment for why this is the only question that matters.
    private var shellManagesMode = false

    /// Set once a command start has been seen. Without it the flags below are
    /// the uninitialized default rather than a real observation, and a shell
    /// that sends FTCS D before FTCS C on startup would read as a leak.
    private var haveCommandStart = false

    /// The flags as of the FTCS C token, not the live value, so it is consistent
    /// with the snapshot taken at FTCS D. See issue 13015.
    private var flagsAtCommandStart = VT100TerminalKeyReportingFlags(rawValue: 0)

    /// Somebody changed the key reporting mode. `wholeValueReplaced` distinguishes
    /// a write that assigned the entire value - the only kind that clears whatever
    /// an app left behind - from a merge, a push, a pop, or a screen buffer swap.
    @objc
    func keyReportingFlagsDidChange(wholeValueReplaced: Bool) {
        if wholeValueReplaced {
            replacedModeWhileShellOwnedTerminal = true
        }
    }

    /// Run `body` without letting the writes it makes count as the shell's.
    /// iTerm2's own reset drives the mode to zero while the shell sits at its
    /// prompt, which is otherwise indistinguishable from a shell driving the
    /// mode and would teach us that an unmanaged shell manages it.
    ///
    /// This only works when `keyReportingFlagsDidChange` is called synchronously
    /// from inside `body`, as it is from `screenDidResetKeyReportingLocally`,
    /// where the body is the delegate call itself. It cannot exclude a write
    /// made to the terminal directly, even inside a joined block: the change
    /// notification is a side effect that is drained after the block returns,
    /// so it would land after the restore below.
    ///
    /// Capture and restore rather than skip: `keyReportingFlagsDidChange` only
    /// ever adds evidence, so restoring the prior value discards exactly what
    /// `body` added.
    @objc
    func ignoringOurOwnWrites(_ body: () -> Void) {
        let saved = replacedModeWhileShellOwnedTerminal
        body()
        replacedModeWhileShellOwnedTerminal = saved
    }

    /// FTCS C. `command` is nil when no command actually started: the synthetic
    /// FTCS C that an aborted command emits (Cmd-K at a prompt, or an FTCS D
    /// with no intervening C). That says nothing about how the shell treats the
    /// mode, and the flags there are whatever happened to be standing.
    @objc
    func commandDidStart(_ command: String?,
                         keyReportingFlags: VT100TerminalKeyReportingFlags) {
        if command != nil {
            // The shell wrote the mode while it owned the terminal and has
            // driven it to zero to run this command: it manages the mode.
            shellManagesMode = replacedModeWhileShellOwnedTerminal && keyReportingFlags.rawValue == 0
            DLog("Shell \(shellManagesMode ? "manages" : "does not manage") the key reporting mode.")
        }
        haveCommandStart = true
        flagsAtCommandStart = keyReportingFlags
    }

    /// FTCS D. Returns whether the command that just exited appears to have left
    /// the key reporting mode enabled behind it.
    ///
    /// `keyReportingFlags` must be the value snapshotted when the FTCS D token
    /// was processed, not the live value: a shell like Fish 4.x re-enables key
    /// reporting for its next prompt right after FTCS D, and the live value
    /// would misread that as an app leaving it stuck on. See issue 13015.
    @objc
    func commandDidEnd(keyReportingFlags: VT100TerminalKeyReportingFlags) -> Bool {
        // Each FTCS D closes at most one command, so a second one with no
        // intervening FTCS C closes nothing. Some setups emit a duplicate as
        // part of the next prompt's sequence. See issue 13032.
        guard haveCommandStart else {
            return false
        }
        haveCommandStart = false

        // The command is over, so the shell owns the terminal from here until
        // the next FTCS C. Cleared inside the command-start check so a stray D
        // cannot reset the window.
        replacedModeWhileShellOwnedTerminal = false

        if keyReportingFlags.rawValue == 0 {
            return false
        }
        // Flags that were already on when the command started were not turned on
        // by it. This also covers shells that legitimately use progressive
        // enhancements.
        if flagsAtCommandStart.rawValue != 0 {
            return false
        }
        // A shell that drives the mode itself will replace these flags at its
        // next prompt, so nothing was left behind.
        if shellManagesMode {
            DLog("Shell manages the key reporting mode, so \(keyReportingFlags.rawValue) is its own.")
            return false
        }
        return true
    }
}
