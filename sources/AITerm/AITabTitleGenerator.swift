//
//  AITabTitleGenerator.swift
//  iTerm2
//
//  Names a session's tab after the work visible on its screen, using Apple's
//  on-device model. The result is published as the session's `aiTitle`
//  variable, which the AI title component (or a custom title format that
//  interpolates \(session.aiTitle)) can display.
//
//  On-device is not an implementation detail here, it is the reason the feature
//  can exist: a tab title is regenerated as the screen changes, so a cloud
//  provider would bill the user per repaint and leak screen contents off the
//  machine on a timer nobody asked for. Nothing here ever falls back to a cloud
//  provider; when the on-device model is unavailable no title is produced and
//  the session keeps whatever name it had.
//
//  This is a single shared generator keyed by session id rather than a
//  per-session object: it is driven from the display-update cadence (see
//  PTYSession.maybeUpdateAITitle), which is many ticks a second, so every entry
//  point is cheap and coalesces by rejection - a session with a generation in
//  flight, or whose screen has not meaningfully changed, is dropped rather than
//  queued.
//
//  Beyond the visible screen it feeds the model a little structured context
//  (foreground job, command line, cwd, host) and, when idle at a shell prompt,
//  the last command run. That last signal is load-bearing: without it a
//  screenful of `ls` output gets named after a random filename on screen rather
//  than "Listing /usr/bin".
//

import Foundation
import FoundationModels

// Value snapshot of the session signals that feed a generation. Sendable (all
// value types) so it crosses into the model Task and the corpus record. `text`
// is the assembled context block; the raw fields are kept for the corpus.
struct AITabTitleContext {
    var job: String?
    var commandLine: String?
    var atPrompt: Bool
    var lastCommand: String?
    // Recent shell command history, oldest first (ending with the last finished
    // command at a prompt, or the running command in the foreground), or empty
    // in the alternate screen or without shell integration.
    var recentCommands: [String]
    var cwd: String?
    var user: String?
    var host: String?
    // The program-set OSC 2 window title, carried through only so the corpus can
    // capture it for offline A/B; not part of the assembled model prompt.
    var windowName: String? = nil
    var text: String

    // Structural markers of the assembled context block. AppleIntelligenceRunner
    // .truncatedContext sheds and protects lines by matching these exact strings, so
    // the builder here and the trimmer there MUST agree. Sharing the constants keeps a
    // header rename or an indent change from silently breaking the trimmer's line
    // classification (which would shed the high-signal Directory:/Host: lines instead
    // of history, degrading titles with no compile error or test failure). nonisolated
    // so the trimmer's nonisolated async context can read them.
    nonisolated static let historyLinePrefix = "  "               // indent before each command
    nonisolated static let historyHeaderSuffix = "oldest first:"  // tail of every history header
    nonisolated static let directoryLinePrefix = "Directory:"
    nonisolated static let hostLinePrefix = "Host:"

    // The single source of truth for the context block, shared by the live
    // session path (PTYSession.aiTitleContext) and the offline experiment
    // harness so both feed the model identical text. `home` abbreviates the
    // working directory to ~ (e.g. ~/git rather than /Users/gnachman/git):
    // the absolute prefix is noise that also eats the title's length budget.
    static func assembleText(job: String?,
                             commandLine: String?,
                             atPrompt: Bool,
                             lastCommand: String?,
                             recentCommands: [String] = [],
                             cwd: String?,
                             user: String?,
                             host: String?,
                             home: String?,
                             runningCommandInHistory: Bool = false) -> String {
        var lines: [String] = []
        // A sequence of recent commands lets the model infer the task from the
        // arc (e.g. `git status` then `git add -p` then `git commit` is a commit
        // in progress) instead of naming the tab after whatever ran last. The
        // caller only supplies these outside the alternate screen, where the
        // visible grid is the content rather than a command sequence.
        if atPrompt {
            // Idle at a prompt: every command has finished, so the whole list is
            // history and its last entry is what produced the visible screen.
            if recentCommands.count > 1 {
                lines.append("At a shell prompt.")
                lines.append(contentsOf: historyLines(recentCommands,
                                                      header: "Recent commands run in this shell, \(Self.historyHeaderSuffix)"))
            } else if let last = lastCommand ?? recentCommands.first {
                // Fall back to the single recent command when the lastCommand
                // variable is nil (a transient state right after a command
                // finishes): the one command we know about is the whole point of
                // this context, so it must not be dropped.
                lines.append("At a shell prompt. The last command run was: \(flattenedCommand(last))")
            } else {
                lines.append("At a shell prompt.")
            }
        } else {
            // A command is running in the foreground. Name it from `commandLine`
            // as before, but also show the commands that led up to it - all but
            // the running one, which `commandLine` already names - so a slow last
            // step is still read in the context of the task it belongs to.
            if let job {
                lines.append("Foreground program: \(job)")
            }
            if let commandLine, commandLine != job {
                lines.append("Command line: \(commandLine)")
            }
            // Drop the last history entry ONLY if it actually is the running command
            // (a duplicate of commandLine). Under the auto-composer path the running
            // command IS recentCommands.last, but under standard shell integration a
            // mark's fullCommand is only populated at command END, so the running
            // command is absent and recentCommands.last is a genuine finished command -
            // dropping it unconditionally would discard the most recent high-signal
            // command from the context.
            // Compare a CANONICAL form of both sides: recentCommands come from
            // mark.fullCommand (the literal typed line - embedded newlines from a
            // heredoc/quoted multi-line command, and interior whitespace runs like
            // `python  train.py`), while commandLine is the session variable, built from
            // argv joined by single spaces. canonicalCommand flattens newlines AND
            // collapses interior whitespace, so the two forms match; a compare that
            // only flattened newlines (or a raw compare) would miss the dedup whenever
            // argv spacing differs from the typed text, emitting the running command
            // twice (Command line: AND under Earlier commands) and biasing the title
            // toward it. Bites the auto-composer path, where recentCommands.last IS the
            // running command.
            //
            // Gate the drop on runningCommandInHistory (the auto-composer path is active),
            // NOT on text equality alone: under standard shell integration the running
            // command is NOT in recentCommands, so a matching .last is a genuinely-FINISHED
            // command that merely has the same text (run `make`, it finishes into history,
            // then run `make` again). Dropping it there discards a real command from the
            // arc - with one prior command it empties the whole "Earlier commands" list.
            let earlier: [String]
            if runningCommandInHistory, let commandLine, let last = recentCommands.last,
               canonicalCommand(last) == canonicalCommand(commandLine) {
                earlier = Array(recentCommands.dropLast())
            } else {
                earlier = recentCommands
            }
            lines.append(contentsOf: historyLines(earlier,
                                                  header: "Earlier commands run in this shell, \(Self.historyHeaderSuffix)"))
        }
        if let cwd {
            lines.append("\(Self.directoryLinePrefix) \(abbreviatingHome(cwd, home: home))")
        }
        if let user, let host {
            lines.append("\(Self.hostLinePrefix) \(user)@\(host)")
        } else if let host {
            lines.append("\(Self.hostLinePrefix) \(host)")
        }
        return lines.joined(separator: "\n")
    }

    // Renders a command list under `header` as an indented block. Empty for an
    // empty input; callers decide when a list is worth showing over a terser
    // single line.
    static func historyLines(_ commands: [String], header: String) -> [String] {
        guard !commands.isEmpty else {
            return []
        }
        var lines = [header]
        for command in commands {
            lines.append("\(Self.historyLinePrefix)\(flattenedCommand(command))")
        }
        return lines
    }

    // Flattens embedded newlines (a heredoc or a quoted multi-line command) to
    // spaces so each command stays a single physical line. Otherwise the assembled
    // context splits into orphaned continuation lines that the trimmer can't
    // identify as history, so it sheds cwd/host instead.
    static func flattenedCommand(_ command: String) -> String {
        return command
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    // Canonical form for comparing a running command that reaches us from two sources
    // with different spacing: mark.fullCommand (the literal typed line) vs the
    // commandLine session variable (argv joined by single spaces). Flatten newlines AND
    // collapse interior whitespace runs so the two forms compare equal for dedup.
    static func canonicalCommand(_ command: String) -> String {
        return AITabTitleGenerator.collapsedInteriorWhitespace(flattenedCommand(command))
    }

    // Delegates to the ONE shared, boundary-correct implementation rather than shipping a
    // second copy that could drift. (This used to be a separate Swift reimplementation;
    // prettyPWD had a naive-prefix boundary bug that this had fixed, so the two were
    // consolidated onto the now-correct prettyPWD.)
    static func abbreviatingHome(_ path: String, home: String?) -> String {
        return iTermSessionTitleBuiltInFunction.prettyPWD(path, homeDirectory: home)
    }
}

// The guided-generation schema. @Generable forces a single well-formed title
// field: asked for a title as free text the on-device model emits multi-line
// replies, echoes the fallback instruction, and occasionally returns a bare
// failure token. A generated field removes all three.
@available(macOS 26, *)
@Generable
private struct GeneratedTabTitle {
    @Guide(description: "A 2-to-4 word Title Case name for the task in progress. No quotes, no trailing punctuation.")
    var title: String
}

// A monotonic "last progress" timestamp shared between an in-flight generation and its
// watchdog. The generation touches it at every token-count XPC hop (and before respond);
// the watchdog reads it to time out on IDLE (no forward progress for the timeout) rather
// than on total wall-clock, so a slow-but-progressing on-device generation on a
// thermally-throttled Mac is allowed to finish instead of being force-cleaned mid-flight
// and its good title discarded. Lock-protected (@unchecked Sendable) so the nonisolated
// generation can touch it while the main-actor watchdog reads it.
final class GenerationProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var lastActivity: TimeInterval
    init(now: TimeInterval) {
        lastActivity = now
    }
    func touch(_ now: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        lastActivity = now
    }
    var lastActivityTime: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return lastActivity
    }
}

// All per-session AI-title state in ONE value, so every lifecycle op adds/removes it
// atomically (forget is a single removeValue) instead of hand-maintaining a dozen
// parallel dictionaries in lockstep - the drift/leak hazard the old layout invited (a
// missed removal leaked an entry per closed session or, for the epoch sets, wedged the
// start-gate for the process lifetime).
struct SessionTitleState {
    // Monotonically increasing generation id. A completing generation applies its result
    // only if its epoch is still current, so a stale generation that finishes after a
    // terminate+revive (same guid) is dropped rather than aliasing the new one. 0 = none
    // ever started.
    var epoch = 0

    // The in-flight generation Task, so a close (forget) can cancel it and a stall can be
    // abandoned.
    var task: Task<Void, Never>? = nil

    // The watchdog Task (abandon -> force-clean -> reap phases). Stored so forget() can
    // cancel it: its reap phase reruns ~180s later and matches generations by integer
    // epoch, which the reset-to-0 forget path can reuse - so an uncancelled reaper could
    // reap a DIFFERENT live generation after a same-guid revive climbs back to that
    // epoch. Cancelling on forget closes that aliasing hole.
    var watchdog: Task<Void, Never>? = nil

    // Epochs whose finish has not yet run - including abandoned "zombie" generations whose
    // model call may still return. The epoch counter must never reset while this is
    // non-empty, or a late finish's epoch can collide with a revived session's. A Set (not
    // a count) so removal is idempotent. mayStartGeneration gates on this being empty; with
    // the state in one struct, "empty set" is the gate (no separate delete-key dance).
    var outstandingEpochs: Set<Int> = []

    // Epochs the watchdog abandoned (freed the session + bumped the epoch) whose model call
    // may still return a real title. A late finish for such an epoch applies its title
    // rather than dropping it as superseded, as long as no newer generation started and the
    // session was not forgotten.
    var abandonedEpochs: Set<Int> = []

    // Whether a generation is in flight. NOT independent state: at most one generation runs
    // at a time and abandon bumps the epoch (leaving its old epoch outstanding but no longer
    // current), so a generation is in flight exactly when the CURRENT epoch is still
    // outstanding. Derived rather than hand-set at every lifecycle site, which removes the
    // desync hazard that would silently corrupt the start-gate.
    var inFlight: Bool {
        return outstandingEpochs.contains(epoch)
    }

    // The screen fingerprint the session was last titled from, or nil if never titled.
    // Grouped into one optional so stamp is a single assignment, clear is `= nil`, and
    // "has a fingerprint" is a nil-check - instead of four fields enumerated field-by-field
    // across six sites (a stamp/clear/forget that missed one silently drifted).
    var titled: Fingerprint? = nil

    // The last title actually handed back (what the tab shows). nil = never applied,
    // "" = explicitly cleared. Suppresses re-applying an identical title.
    var lastAppliedTitle: String? = nil

    // When an attempt was last started. Keeps the per-tick cost near zero (see shouldAttempt).
    var lastAttempt: TimeInterval? = nil

    // True iff no meaningful state remains, so the whole entry can be dropped. The one
    // place that enumerates every field; hasState / the removal paths rely on it.
    var isEmpty: Bool {
        // inFlight is derived from outstandingEpochs, so it needs no separate term here.
        return epoch == 0 && task == nil && watchdog == nil
            && outstandingEpochs.isEmpty && abandonedEpochs.isEmpty
            && titled == nil && lastAppliedTitle == nil && lastAttempt == nil
    }
}

// The screen fingerprint a session was last titled from. Grouped so it can be
// stamped/cleared/compared as one value. See SessionTitleState.titled.
struct Fingerprint {
    var digest: Int
    var histogram: [NSNumber: NSNumber]
    var oscTitle: String
    var isAlternate: Bool
}

@MainActor
final class AITabTitleGenerator {
    static let instance = AITabTitleGenerator()

    // Longest title we will hand back. Tabs are narrow, and an over-long reply
    // is usually the model having ignored the length guide.
    private static let maximumTitleLength = 40

    // A screen with fewer than this many non-blank lines is not a task worth
    // naming (a fresh shell, a cleared screen, a lone prompt). Titling those
    // produced confident nonsense in testing.
    private static let minimumInterestingLines = 2

    // Minimum seconds between attempts for one session. Generation is ~0.3s and
    // free, so this is not a cost control; it stops a session producing steady
    // output from re-titling continuously while the user reads it.
    private static let minimumSecondsBetweenAttempts: TimeInterval = 5

    // The single per-session state store. See SessionTitleState.
    private var sessions = [String: SessionTitleState]()

    // How long to wait before giving up on a generation and freeing the session.
    // Generation is ~0.3s; this only fires on an XPC stall or model deadlock.
    private static let generationTimeoutNanos: UInt64 = 8 * 1_000_000_000

    // After force-cleanup keeps a hung generation's epoch outstanding (holding the
    // gate closed to avoid stacking calls), wait this much longer and then reap the
    // still-outstanding epoch, reopening the gate. Without this a single permanent
    // XPC wedge would lock the session out of AI titles for the life of the process,
    // even after the model recovers. Long so a persistently-degraded machine retries
    // at most about once every few minutes (bounded pile-up), not every interval.
    private static let reapBackoffNanos: UInt64 = 180 * 1_000_000_000

    // Sleeps until the generation has made no progress (touched `progress`) for
    // `timeoutNanos`, RESETTING the countdown whenever progress arrives. Returns true if
    // the task was cancelled (the caller should stop - e.g. the model returned and the
    // watchdog was cancelled), false when the idle threshold is genuinely reached. This
    // is what makes the watchdog an idle timeout rather than a total-time cap: the model
    // touches `progress` at each token-count XPC hop, so a slow-but-progressing
    // generation keeps resetting this and is never mistaken for a hang.
    nonisolated static func sleepUntilIdle(_ progress: GenerationProgress,
                                           timeoutNanos: UInt64) async -> Bool {
        let timeoutSeconds = Double(timeoutNanos) / 1_000_000_000
        while true {
            // Monotonic clock (systemUptime), matching AIAvailabilityProbe: it never
            // goes backward on an NTP correction or manual clock change, so idle can't be
            // spuriously stuck at 0 (which would hold mayStartGeneration closed forever) or
            // jump past the timeout (which would abandon a healthy generation).
            let idleSeconds = max(0, ProcessInfo.processInfo.systemUptime - progress.lastActivityTime)
            if idleSeconds >= timeoutSeconds {
                return false
            }
            // (timeoutSeconds - idleSeconds) is bounded by timeoutSeconds, so unlike
            // idleSeconds * 1e9 this conversion can't overflow UInt64 and trap on a corrupt
            // clock.
            let remainingNanos = UInt64((timeoutSeconds - idleSeconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: remainingNanos)
            if Task.isCancelled {
                return true
            }
        }
    }

    // How much of the background-color layout must change (fraction of cells) to
    // count as a task/program switch and re-title. histogramDistance is the
    // fraction of cells whose background bucket changed, so on an 80x24 grid one
    // full-width row is ~0.042 - below this by design: a moving cursor line, a
    // recolored one-row mode indicator, or a single status/help bar toggling does
    // NOT re-title on the frame path (those are caught, if at all, by the OSC or
    // alternate-transition or low-entropy-content signals). Only a multi-row
    // layout change (~1.4+ rows) or a full repaint clears this bar. Deliberately
    // not lower: catching every one-row recolor would churn on mode indicators.
    private static let frameChangeThreshold = 0.06

    /// Whether it is worth reading a session's screen at all right now. Cheap
    /// (dictionary lookups and a probe) so the display-cadence caller can skip
    /// the cost of extracting screen text - which walks the grid - on the vast
    /// majority of ticks. A true answer does not promise a generation: the
    /// screen may still be unchanged or not worth naming.
    func shouldAttempt(forSessionID sessionID: String) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard iTermAdvancedSettingsModel.aiGeneratedTabTitles() else {
            return false
        }
        guard mayStartGeneration(sessionID) else {
            return false
        }
        // Monotonic clock so an NTP correction / manual change can't make now - previous
        // negative (stopping attempts until the clock catches up). Must match the clock
        // abandonStalledGeneration stamps lastAttempt with.
        let now = ProcessInfo.processInfo.systemUptime
        if let previous = sessions[sessionID]?.lastAttempt,
           now - previous < Self.minimumSecondsBetweenAttempts {
            return false
        }
        // Stamp before the probe, not after a successful one. A Mac where Apple
        // Intelligence is unavailable is the common case for this feature, and
        // without the stamp that case re-probes on every tick forever. The cached
        // probe: this is a title hot path, not a security decision.
        sessions[sessionID, default: SessionTitleState()].lastAttempt = now
        return AIAvailabilityProbe.checkCached()
    }

    /// Requests a title for `sessionID` from `context` + `screen`. Call on the
    /// main thread after `shouldAttempt` returned true. The completion runs on
    /// the main thread and only when a generation actually ran: it receives the
    /// new title, or nil if the model failed or returned something unusable.
    /// When this decides not to generate (screen unchanged or not worth naming)
    /// the completion is never called - "keep the title you have" needs no call.
    /// `context` is a provider, not a value: assembling the context walks the
    /// session's prompt marks and reads ~9 variables, and the common outcome here
    /// is `.skip` (screen unchanged) where that work would be thrown away. It is
    /// invoked exactly once, only after this decides a generation will actually
    /// run. Caller must have gotten `true` from `shouldAttempt` first (which
    /// already stamped `lastAttempt`), so no re-stamp happens here.
    func requestTitle(forSessionID sessionID: String,
                      screen: String,
                      backgroundHistogram: [NSNumber: NSNumber],
                      isAlternate: Bool,
                      oscTitle: String,
                      context: () -> AITabTitleContext,
                      completion: @escaping (String?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard iTermAdvancedSettingsModel.aiGeneratedTabTitles() else {
            return
        }
        guard mayStartGeneration(sessionID) else {
            return
        }

        let normalized = Self.normalize(screen)
        guard Self.isWorthTitling(normalized) else {
            // The screen is no longer worth titling. Clear a stale applied title
            // (once) so the real session name shows through again, and drop
            // the regeneration fingerprints so the identical work reappearing
            // later re-generates instead of being skipped as unchanged.
            if Self.clearDecision(worthTitling: false, lastAppliedTitle: sessions[sessionID]?.lastAppliedTitle) {
                resetTitledFingerprints(sessionID: sessionID)
                completion("")
            }
            return
        }
        let digest = normalized.hashValue

        // Decide whether the task changed enough to re-title. A change in the
        // program's own OSC title always counts (it catches file/dir/context
        // switches the visuals don't). Otherwise, for a full-screen app gate on
        // the background-color layout (scrolling leaves it unchanged; switching
        // program/mode changes it), and for a line-oriented shell gate on the
        // content digest (the background there is ~constant).
        let s = sessions[sessionID]
        let decision = Self.regenerationDecision(
            lastOSC: s?.titled?.oscTitle,
            lastDigest: s?.titled?.digest,
            lastHistogram: s?.titled?.histogram,
            lastIsAlternate: s?.titled?.isAlternate,
            digest: digest,
            histogram: backgroundHistogram,
            oscTitle: oscTitle,
            isAlternate: isAlternate)
        guard case .regenerate(let reason) = decision else {
            DLog("AI title: skip \(sessionID) - task unchanged")
            return
        }
        guard AIAvailabilityProbe.checkCached() else {   // title hot path, not security
            return
        }
        guard #available(macOS 26, *) else {
            return
        }
        DLog("AI title: regenerate \(sessionID) [\(reason)] alternate=\(isAlternate) osc='\(oscTitle)'")

        // Tag this generation with a monotonically increasing epoch. finish only
        // applies a result whose epoch is still current, so a stale generation
        // that completes after a terminate+revive (which reuses the same guid)
        // cannot alias the inFlight token and apply an old title.
        var startState = sessions[sessionID] ?? SessionTitleState()
        startState.epoch += 1
        let epoch = startState.epoch
        startState.outstandingEpochs.insert(epoch)   // makes inFlight (computed) true
        sessions[sessionID] = startState
        // Now, and only now, pay for assembling the context (prompt-mark walk +
        // variable reads): a generation is actually going to run.
        generate(sessionID: sessionID,
                 context: context(),
                 screen: screen,
                 digest: digest,
                 histogram: backgroundHistogram,
                 oscTitle: oscTitle,
                 isAlternate: isAlternate,
                 epoch: epoch,
                 reason: reason,
                 completion: completion)
    }

    // Total-variation distance between two background-color histograms:
    //   Σ_k |a_k/Σa - b_k/Σb| / 2   (0 = identical layout, 1 = disjoint).
    // Comparing each bucket as a FRACTION of its own histogram's total makes the
    // metric size-invariant: a window resize (80x24 -> 120x40) with the same layout
    // leaves the fractions unchanged and yields 0, rather than a large raw-count delta
    // that spuriously crosses the threshold and re-titles on resize.
    //
    // Note the /2 is part of the metric, NOT an accidental extra factor to "restore":
    // for two SAME-size histograms (Σa = Σb = N) this equals the OLD count-based form
    // Σ|a_k - b_k| / (Σa + Σb) = Σ|a_k - b_k| / 2N exactly (both are TV), so the
    // threshold's meaning is unchanged. frameChangeThreshold and its worked example
    // were computed against this /2 form; removing the /2 would silently double the
    // gate's sensitivity.
    // The reserved bucket every image cell maps to. made it position-invariant
    // (image cells' bg bytes are x/y indices, not a color); excluding it from the
    // distance below makes the fingerprint SIZE-invariant too. The bucket counts image
    // CELLS, so without this a progressively growing / streaming / zooming inline image
    // changes its fraction and, once the change exceeds frameChangeThreshold in a ~5s
    // interval, crosses it and re-runs the model on a task that has not changed - the
    // churn the fingerprint exists to suppress. A real task switch still changes the
    // NON-image color layout, which is what remains.
    private static let imageBucketKey = NSNumber(value: iTermTabTitleFrameFingerprint.imageBucketKey())

    // Count of NON-image cells (image cells excluded, see imageBucketKey). Zero means an
    // image-dominated frame with no color layout to compare.
    private static func nonImageCellCount(_ h: [NSNumber: NSNumber]) -> Int {
        return h.reduce(0) { $0 + ($1.key == imageBucketKey ? 0 : $1.value.intValue) }
    }

    private static func histogramDistance(_ a: [NSNumber: NSNumber],
                                          _ b: [NSNumber: NSNumber]) -> Double {
        // Sum and compare NON-image buckets only (see imageBucketKey).
        let totalA = nonImageCellCount(a)
        let totalB = nonImageCellCount(b)
        guard totalA > 0, totalB > 0 else {
            return totalA == totalB ? 0 : 1
        }
        var keys = Set(a.keys)
        keys.formUnion(b.keys)
        keys.remove(imageBucketKey)
        var diff = 0.0
        for key in keys {
            let af = Double(a[key]?.intValue ?? 0) / Double(totalA)
            let bf = Double(b[key]?.intValue ?? 0) / Double(totalB)
            diff += abs(af - bf)
        }
        return diff / 2.0
    }

    // Fraction of cells one background-color bucket must reach for the histogram
    // to be "low entropy" - too uniform to distinguish frames (a monochrome pager
    // on the default background), so the content digest is used instead.
    private static let lowEntropyDominanceThreshold = 0.9

    static func isLowEntropyHistogram(_ histogram: [NSNumber: NSNumber]) -> Bool {
        // Measure dominance over NON-image buckets only, mirroring histogramDistance's
        // image-bucket exclusion. Otherwise an image-DOMINATED screen (an image
        // viewer, or a TUI rendering a large inline image beside a small status bar) has
        // >90% image cells, is judged low-entropy, and is routed to the content-digest
        // branch - where a status-bar clock/counter churns the digest and re-titles
        // every tick, even though the non-image status-bar color histogram would have
        // been perfectly discriminating. A screen with NO non-image cells is genuinely
        // low-entropy (there is no color layout to compare).
        var total = 0
        var maxCount = 0
        for (key, value) in histogram where key != imageBucketKey {
            let count = value.intValue
            total += count
            maxCount = max(maxCount, count)
        }
        guard total > 0 else {
            return true
        }
        return Double(maxCount) / Double(total) >= lowEntropyDominanceThreshold
    }

    // Whether a screen change is worth re-titling. Pure so the gate is unit-
    // testable without the model or the availability probe.
    enum RegenerationDecision: Equatable {
        case skip
        case regenerate(reason: String)
    }

    static func regenerationDecision(lastOSC: String?,
                                     lastDigest: Int?,
                                     lastHistogram: [NSNumber: NSNumber]?,
                                     lastIsAlternate: Bool?,
                                     digest: Int,
                                     histogram: [NSNumber: NSNumber],
                                     oscTitle: String,
                                     isAlternate: Bool) -> RegenerationDecision {
        // Entering or leaving a full-screen app changes what the screen means, so
        // the prior fingerprint (taken under the other regime) is not comparable:
        // always re-title once across the transition. Without this a low-color,
        // no-OSC app whose background resembles the shell's is skipped on entry
        // and, because its content churns while the background barely moves, is
        // then never titled at all.
        if let lastIsAlternate, lastIsAlternate != isAlternate {
            return .regenerate(reason: "transition")
        }
        let oscChanged = lastOSC != nil && lastOSC != oscTitle
        if !oscChanged {
            if isAlternate {
                if isLowEntropyHistogram(histogram) {
                    // A monochrome pager/TUI (less, man, a git-log pager) paints on
                    // the default background, so its histogram can't tell one page
                    // from an unrelated one. Fall back to the content digest so a
                    // task change within the app is still caught.
                    if lastDigest == digest {
                        return .skip
                    }
                } else if let last = lastHistogram, nonImageCellCount(last) == 0 {
                    // The current frame is colorful but the PRIOR frame was image-dominated
                    // (no non-image cells). The color histogram is non-comparable:
                    // histogramDistance excludes image cells, so the prior side is empty and
                    // it would report max distance (1), re-titling on a mere image->color
                    // transition (a small status bar appearing over an image viewer) even
                    // though the content is unchanged. Fall back to the content digest, like
                    // the low-entropy path, so an unchanged screen is skipped.
                    if lastDigest == digest {
                        return .skip
                    }
                } else if let last = lastHistogram, histogramDistance(histogram, last) < frameChangeThreshold {
                    // Computed lazily HERE, not up front: on the OSC-changed or shell path
                    // the full total-variation walk over every color bucket would be
                    // discarded.
                    // A colorful full-screen app (k9s, lazygit, a themed editor). Here
                    // the histogram IS meaningful, so use it ALONE - deliberately NOT
                    // also breaking the tie on the content digest. The digest is
                    // boolean (equal or not) with no magnitude, and these apps churn
                    // content every frame (live metrics, a blinking cursor, a clock),
                    // so a digest tie-break would change on essentially every idle tick
                    // and re-title constantly, flickering the tab and spamming the
                    // model - the exact noise the histogram filter exists to suppress.
                    // Accepted limitation: a task switch that keeps a similar color
                    // layout AND sets no OSC 1/2 title stays within frameChangeThreshold
                    // and is not re-titled until the layout or an OSC title changes.
                    // Most such apps either shift their color layout on a real view
                    // change or set an OSC title (handled by oscChanged above).
                    return .skip
                }
            } else {
                if lastDigest == digest {
                    return .skip
                }
            }
        }
        let reason: String
        if lastOSC == nil {
            reason = "first"
        } else if oscChanged {
            reason = "osc"
        } else if isAlternate {
            reason = "frame"
        } else {
            reason = "content"
        }
        return .regenerate(reason: reason)
    }

    // The result of a completed (or failed) generation.
    enum TitleOutcome: Equatable {
        case produced(String?)   // the sanitized title, or nil/"" if unusable
        case transientFailure    // the model call threw (busy, cancelled, etc.)
    }

    // What to do with a completed generation. Pure so the apply logic is unit-
    // testable without the model.
    struct ApplyResult: Equatable {
        var stampFingerprint: Bool   // cache this screen as "handled"
        var titleToApply: String?    // nil = leave the tab's current title alone
    }

    // Whether a thrown generation error is transient (worth retrying on the same
    // screen) rather than deterministic. Only a cancelled task qualifies: every
    // deterministic FoundationModels failure - guardrail violation, unsupported
    // language, context overflow, decoding failure - reproduces for the same
    // input, so treating an unrecognized error as transient would re-run the
    // model on the same offending screen every cadence tick forever.
    static func isTransientGenerationError(_ error: Error) -> Bool {
        // A cancelled task is the one unambiguously transient case. Everything
        // else - including unrecognized errors - is treated as deterministic so a
        // reproducible failure stamps the fingerprint and stops re-running. Being
        // conservative here (a rare truly-transient error waits for the next
        // screen change rather than retrying immediately) is far cheaper than the
        // infinite-retry it prevents.
        return error is CancellationError
    }

    // Whether a session actually consumes the AI title, and therefore should be
    // run through the model. Gating only on the global advanced setting means
    // every idle session in every window is fed through the on-device model even
    // though only profiles that selected the AI component (or a custom title
    // function that might interpolate session.aiTitle) will ever display it.
    static func sessionConsumesAITitle(titleComponents: UInt,
                                       hasCustomTitleFunction: Bool,
                                       isMaskedByTemporaryName: Bool = false) -> Bool {
        // An active TemporarySessionName (manual tab rename / Set-Title trigger) out-ranks
        // the AI title in titleForSessionName, so a generated title would never be shown.
        // Treat a masked session as NOT consuming: skip the per-interval grid walk and the
        // on-device model run (and feeding the screen to it) for a title that is discarded.
        // The mask clears when the manual name is removed, and consumption resumes.
        if isMaskedByTemporaryName {
            return false
        }
        // Use the enum value, not a hardcoded 1<<12, so a renumbering can't
        // silently diverge this gate from iTermTitleComponentsAI.
        //
        // The custom-title-function branch requires the Custom component to be the
        // ACTIVE title mode, not merely that a function is stored. A registered
        // KEY_TITLE_FUNC is only ever invoked when components == iTermTitleComponentsCustom
        // (see -sessionNameControllerUniqueIdentifier), and switching the Title popup
        // from a function to a plain component (e.g. Job) sets KEY_TITLE_COMPONENTS
        // but leaves the stale func tuple in KEY_TITLE_FUNC. Without the Custom gate
        // such a profile would run the model every tick to produce an aiTitle the
        // custom function can never interpolate because it never runs - wasted CPU/
        // battery and screen contents fed to the model for a session the user did not
        // opt into. Custom is mutually exclusive with other components, so the bitwise
        // test matches the strict equality at the usage site.
        let usesAIComponent = (titleComponents & iTermTitleComponents.AI.rawValue) != 0
        let usesActiveCustomFunction =
            (titleComponents & iTermTitleComponents.custom.rawValue) != 0 && hasCustomTitleFunction
        return usesAIComponent || usesActiveCustomFunction
    }

    // Whether to clear a previously applied AI title. When the screen stops being
    // worth titling (the user ran `clear`, or sits idle at an empty prompt) a
    // stale title must be wiped so it stops masking the real session name -
    // otherwise "Reviewing Auth Diff" lingers on every later unrelated task.
    static func clearDecision(worthTitling: Bool, lastAppliedTitle: String?) -> Bool {
        return !worthTitling && (lastAppliedTitle?.isEmpty == false)
    }

    static func applyDecision(outcome: TitleOutcome, lastAppliedTitle: String?) -> ApplyResult {
        switch outcome {
        case .transientFailure:
            // A throw is not a deterministic result: a retry on the same screen
            // may succeed, so do NOT cache the fingerprint (that would suppress
            // the retry until the screen content changes).
            return ApplyResult(stampFingerprint: false, titleToApply: nil)
        case .produced(let title):
            guard let title, !title.isEmpty else {
                // Deterministic empty: the greedy model returned nothing usable
                // for this (worth-titling) screen and will again. Stamp so we stop
                // re-hitting it, and clear a prior title so a stale name stops
                // masking the new work; nothing to clear if none was applied.
                let cleared = (lastAppliedTitle?.isEmpty == false) ? "" : nil
                return ApplyResult(stampFingerprint: true, titleToApply: cleared)
            }
            if title == lastAppliedTitle {
                // Regeneration ran (an animated OSC token, one more line of steady
                // output) but produced the same title. Re-applying it renames the
                // tab to what it already says, which reads as churn while the user
                // is looking at it - so stamp but do not re-apply.
                return ApplyResult(stampFingerprint: true, titleToApply: nil)
            }
            return ApplyResult(stampFingerprint: true, titleToApply: title)
        }
    }

    /// Whether any per-session state is retained for `sessionID`. For tests: a
    /// closed session must leave nothing behind (see forget).
    func hasState(forSessionID sessionID: String) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return !(sessions[sessionID]?.isEmpty ?? true)
    }

    // Whether a generation is in flight for the session. For tests.
    func isInFlightForTesting(sessionID: String) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return sessions[sessionID]?.inFlight ?? false
    }

    // Whether a new generation may start for this session. A generation the
    // watchdog abandoned frees inFlight while its model call is still outstanding;
    // starting another on top of it would, against a wedged model, spawn a fresh
    // hung call every interval instead of backing off. Gate on BOTH the inFlight
    // token and any outstanding (including abandoned-but-running) epoch, so a wedge
    // waits for the abandoned call to return (S1 applies it) or for the grace timer
    // to reclaim it.
    private func mayStartGeneration(_ sessionID: String) -> Bool {
        let s = sessions[sessionID]
        return !(s?.inFlight ?? false) && (s?.outstandingEpochs.isEmpty ?? true)
    }

    // Test seam mirroring the mayStartGeneration gate.
    func canStartGenerationForTesting(sessionID: String) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return mayStartGeneration(sessionID)
    }

    // The title currently recorded as applied for the session (what the tab shows):
    // nil = never applied, "" = explicitly cleared. For tests.
    func appliedTitleForTesting(sessionID: String) -> String? {
        dispatchPrecondition(condition: .onQueue(.main))
        return sessions[sessionID]?.lastAppliedTitle
    }

    // Test seams for the terminate+revive race.
    func beginGenerationForTesting(sessionID: String) -> Int {
        dispatchPrecondition(condition: .onQueue(.main))
        var s = sessions[sessionID] ?? SessionTitleState()
        s.epoch += 1
        s.outstandingEpochs.insert(s.epoch)   // makes inFlight (computed) true
        sessions[sessionID] = s
        return s.epoch
    }

    func generationIsCurrentForTesting(sessionID: String, epoch: Int) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return sessions[sessionID]?.epoch == epoch
    }

    // Drives finish with the given epoch and an empty result, so the late-finish
    // bookkeeping (including the superseded-generation cleanup) is testable.
    @discardableResult
    func finishForTesting(sessionID: String, epoch: Int, title: String? = nil, digest: Int = 0) -> String? {
        var applied: String? = nil
        finish(sessionID: sessionID, outcome: .produced(title), digest: digest,
               histogram: [:], oscTitle: "", isAlternate: false, epoch: epoch) { applied = $0 }
        return applied
    }

    // Drive finish with a transient (cancelled) failure, to exercise the retry
    // contract on the abandoned-but-current path.
    func finishTransientForTesting(sessionID: String, epoch: Int, digest: Int = 0) {
        finish(sessionID: sessionID, outcome: .transientFailure, digest: digest,
               histogram: [:], oscTitle: "", isAlternate: false, epoch: epoch) { _ in }
    }

    // Whether a non-empty AI title is currently applied for this session, from the
    // generator's own record - a single dictionary lookup, cheaper than a variable-
    // scope traversal on the caller's side. Used by the feature-off display tick to
    // decide whether there is a stale title to clear.
    func hasNonEmptyAppliedTitle(forSessionID sessionID: String) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return sessions[sessionID]?.lastAppliedTitle?.isEmpty == false
    }

    /// Forgets a session's cached state. Call when a session closes so a long
    /// iTerm2 run does not accumulate an entry per session ever opened.
    func forget(sessionID: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard var s = sessions[sessionID] else {
            return   // nothing to forget
        }
        // inFlight is derived from outstandingEpochs, which is emptied below.
        if !s.outstandingEpochs.isEmpty {
            // A generation is still outstanding (in flight, or an abandoned one whose
            // model call may still return and fire a late finish). Bump the counter
            // so a same-guid revive uses a fresh epoch and the late finish is dropped,
            // NOT reset, or the revive reuses epoch 1 and the zombie aliases it. Then
            // REMOVE the outstanding entry: a closed session has no gate to protect,
            // and keeping it would leak permanently for a wedged call whose watchdog
            // has already run both phases (no reclaimer would remain). The bumped
            // counter is reclaimed by the late finish's superseded-drop if the call
            // returns, else persists as a single bounded entry (aliasing-safety). This
            // makes the "closed-while-wedged" path self-contained rather than deferring
            // to a grace timer that may no longer exist.
            s.epoch += 1
            s.outstandingEpochs = []
        } else {
            s.epoch = 0
        }
        // Cancel BOTH the work Task and the watchdog (best effort - cancelling work may
        // free a cancellable model await). Cancelling the watchdog is load-bearing: its
        // reap phase reruns ~180s later and matches by integer epoch, and the reset-to-0
        // branch below lets a same-guid revive reuse that epoch, so an uncancelled reaper
        // could reap a DIFFERENT live generation. Cancelling here closes that hole (it
        // replaces the old "self-expiring epoch-guarded no-op" reasoning, which had that
        // reset-to-0 gap).
        s.task?.cancel()
        s.task = nil
        s.watchdog?.cancel()
        s.watchdog = nil
        // A forgotten session (closed, or revived under the same guid) must not let a
        // still-outstanding abandoned generation apply its title to the new shell:
        // dropping the abandoned mark makes the late finish take the superseded
        // (dropped) path.
        s.abandonedEpochs = []
        // Drop the regeneration fingerprint and the applied title (but keep the bumped
        // epoch above, if any, for aliasing safety).
        s.titled = nil
        s.lastAppliedTitle = nil
        s.lastAttempt = nil
        // Only a bumped epoch (aliasing-safety) may remain; if even that is gone, drop
        // the entry entirely - the single removeValue that the consolidation buys.
        if s.isEmpty {
            sessions.removeValue(forKey: sessionID)
        } else {
            sessions[sessionID] = s
        }
    }

    // Fully reclaims the monotonic epoch bookkeeping for a session: the counter,
    // any abandoned mark, and the task handle. Called when a superseded finish or the
    // force-cleanup determines no generation remains and none can be reused.
    private func clearGenerationEpoch(_ sessionID: String) {
        guard var s = sessions[sessionID] else {
            return
        }
        s.epoch = 0
        s.task = nil
        s.abandonedEpochs = []
        sessions[sessionID] = s
        pruneIfEmpty(sessionID)
    }

    // Drops the regeneration fingerprints (and the applied title) but not
    // lastAttempt, so an identical screen reappearing re-generates instead of
    // being skipped as "unchanged". Shared by forget and the clear branch.
    // Remove `epoch` from a per-session epoch set, deleting the session's entry once
    // its set is empty. Centralized deliberately: mayStartGeneration gates on
    // `outstandingEpochs[sessionID] == nil`, so any caller that removed the epoch but
    // left an empty Set behind would keep the gate closed and lock the session out of
    // AI titles for the process lifetime. One helper means that half can't be dropped
    // in one of the five call sites.
    private func removeEpoch(_ epoch: Int,
                             from keyPath: WritableKeyPath<SessionTitleState, Set<Int>>,
                             for sessionID: String) {
        // With the state in one struct the "delete the key when the set empties" dance is
        // gone: mayStartGeneration reads outstandingEpochs.isEmpty directly, so removing
        // the element is all that is needed.
        sessions[sessionID]?[keyPath: keyPath].remove(epoch)
    }

    // Removes the session's whole state entry when nothing meaningful is left, so a
    // cleared-out session doesn't linger. Called after the removal paths.
    private func pruneIfEmpty(_ sessionID: String) {
        if sessions[sessionID]?.isEmpty == true {
            sessions.removeValue(forKey: sessionID)
        }
    }

    // Stamp the 4-field "last titled" fingerprint together so the two stamp sites
    // (finish, abandonStalledGeneration) can't drift from each other or from the
    // clear/read sites. Adding a dimension means editing this one place.
    private func stampTitledFingerprint(sessionID: String,
                                        digest: Int,
                                        histogram: [NSNumber: NSNumber],
                                        oscTitle: String,
                                        isAlternate: Bool) {
        var s = sessions[sessionID] ?? SessionTitleState()
        s.titled = Fingerprint(digest: digest, histogram: histogram, oscTitle: oscTitle, isAlternate: isAlternate)
        sessions[sessionID] = s
    }

    // Clear only the fingerprint, NOT lastAppliedTitle - forceCleanup manages the
    // displayed title separately. resetTitledFingerprints layers lastAppliedTitle on
    // top.
    private func clearTitledFingerprint(sessionID: String) {
        guard sessions[sessionID]?.titled != nil else { return }
        sessions[sessionID]?.titled = nil
        pruneIfEmpty(sessionID)
    }

    private func resetTitledFingerprints(sessionID: String) {
        sessions[sessionID]?.lastAppliedTitle = nil
        clearTitledFingerprint(sessionID: sessionID)   // also prunes if now empty
    }

    // Whether any regeneration fingerprint is retained (ignores lastAttempt). For
    // tests.
    func hasTitledFingerprint(forSessionID sessionID: String) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return sessions[sessionID]?.titled != nil
    }

    // Seeds per-session state as if a generation had completed, so the clear /
    // recurring-screen behavior is testable without the on-device model.
    func seedTitledStateForTesting(sessionID: String, digest: Int, oscTitle: String, appliedTitle: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        var s = sessions[sessionID] ?? SessionTitleState()
        s.titled = Fingerprint(digest: digest, histogram: [:], oscTitle: oscTitle, isAlternate: false)
        s.lastAppliedTitle = appliedTitle
        sessions[sessionID] = s
    }

    // Split out so the macOS 26 requirement rides a declaration rather than a
    // `guard #available` narrowing across a closure boundary.
    @available(macOS 26, *)
    private func generate(sessionID: String,
                          context: AITabTitleContext,
                          screen: String,
                          digest: Int,
                          histogram: [NSNumber: NSNumber],
                          oscTitle: String,
                          isAlternate: Bool,
                          epoch: Int,
                          reason: String,
                          completion: @escaping (String?) -> Void) {
        let timestamp = Date.timeIntervalSinceReferenceDate
        let instructions = Self.instructions
        // Inherits this type's main-actor isolation, so the await suspends off
        // the main thread and resumes back on it - no manual hop needed.
        let work = Task { [weak self] in
            // If forget already cancelled this work Task before it ran, return before
            // creating a watchdog - otherwise a watchdog (with its ~180s reaper) would be
            // spawned for an already-forgotten generation.
            guard !Task.isCancelled else {
                return
            }
            // Shared idle-progress clock: generateTabTitle touches it at every token-count
            // XPC hop and before respond, so the watchdog below abandons/force-cleans on
            // IDLE (no progress for the timeout), not on total wall-clock. That lets a
            // slow-but-progressing generation on a throttled Mac finish instead of having
            // its good title discarded by a fixed cap.
            let progress = GenerationProgress(now: ProcessInfo.processInfo.systemUptime)   // monotonic
            let onProgress: @Sendable () -> Void = {
                progress.touch(ProcessInfo.processInfo.systemUptime)
            }
            // Watchdog: if the model call stalls (XPC hang, deadlock) with no forward
            // progress past the timeout, free the session so it can retry rather than
            // being locked out for the life of the process. Cancelled on normal
            // completion.
            let watchdog = Task { [weak self] in
                if await Self.sleepUntilIdle(progress, timeoutNanos: Self.generationTimeoutNanos) {
                    return   // cancelled
                }
                self?.abandonStalledGeneration(sessionID: sessionID, epoch: epoch,
                                               digest: digest, histogram: histogram,
                                               oscTitle: oscTitle, isAlternate: isAlternate)
                // Give the abandoned call a FIXED grace period to still return (and run
                // its finish) before force-cleaning. Deliberately NOT idle-based here:
                // phase 1 fired because idle already reached the timeout, and the actual
                // inference (session.respond) is one opaque await that reports no progress,
                // so re-running the idle check would find idle STILL past the timeout and
                // return immediately - collapsing the 8s->16s recovery window to ~0 and
                // discarding a slow-but-successful title (the contract). A real sleep
                // restores that window; a call that returns during it cancels this
                // watchdog, so the sleep ends early.
                try? await Task.sleep(nanoseconds: Self.generationTimeoutNanos)
                guard !Task.isCancelled else {
                    return
                }
                // Yield once before giving up. A model call that returns right at the
                // grace boundary enqueues its finish on this same main actor at ~the
                // same instant this continuation does; whichever was enqueued first
                // runs first. Yielding lets a finish that is ALREADY enqueued run (it
                // cancels this watchdog before calling finish), so the good slow title
                // is applied via the abandoned-but-current path instead of being
                // dropped by a force-cleanup that removed the abandoned mark first. A
                // genuinely hung call has no such finish pending, so we resume and
                // force-clean as before.
                //
                // This is best-effort, NOT a guarantee: a finish enqueued just after
                // we resume from the yield still loses the race and its title is
                // dropped. That residual is transient and self-corrects on the next
                // tick - force-cleanup clears the fingerprint, so the unchanged
                // screen regenerates. A fully deterministic fix would require racing
                // the model call against the timer inside the work Task rather than a
                // separate watchdog; not worth the restructure for a one-scheduler-hop
                // window that already self-heals.
                await Task.yield()
                guard !Task.isCancelled else {
                    return
                }
                if self?.forceCleanupHungGeneration(sessionID: sessionID, epoch: epoch) == true {
                    // The model has really given up: a title was showing for an
                    // earlier screen and is now stale for the one we stalled on, so
                    // clear it and fall back to the real session name. Doing this
                    // here (not at abandon) means a stall that recovers before the
                    // grace timer never flickers the tab.
                    completion("")
                }
                // Phase 3: force-cleanup kept the epoch outstanding to hold the gate
                // closed (so we don't stack calls on a degraded machine). But if the
                // call STILL never returns, that would lock the session out of AI
                // titles forever. After a long backoff, reap the still-outstanding
                // epoch so the gate reopens and the session can be titled again once
                // the model recovers - accepting the one orphaned call. A call that
                // returns during the backoff cancels this watchdog first, so a normal
                // (even slow) generation never reaches here.
                try? await Task.sleep(nanoseconds: Self.reapBackoffNanos)
                guard !Task.isCancelled else {
                    return
                }
                self?.reapOrphanedGeneration(sessionID: sessionID, epoch: epoch)
            }
            // Store the watchdog handle so forget() can cancel it (see the field's
            // note). requestTitle created the session's state before generate, so
            // the entry exists; if it does not (forgotten in the meantime), this is a
            // no-op and the watchdog self-expires via its epoch guards.
            self?.sessions[sessionID]?.watchdog = watchdog
            // Monotonic, like every other duration here: a wall-clock delta would log a
            // negative or wildly inflated latency into the corpus if an NTP correction /
            // manual clock change lands during the ~0.3s generation. (The absolute
            // `timestamp` corpus field stays Date - it wants wall time.)
            let start = ProcessInfo.processInfo.systemUptime
            // generateTabTitle condenses whitespace and trims the screen to fit
            // the on-device context window, so a large screen produces a title
            // instead of throwing exceededContextWindowSize (and no title). A
            // throw here is transient (model busy/cancelled): distinguished from a
            // deterministic empty result so a static screen that momentarily
            // failed is retried rather than cached as handled.
            let outcome: TitleOutcome
            do {
                let raw = try await AppleIntelligenceRunner.generateTabTitle(
                    instructions: instructions,
                    context: context.text,
                    screen: screen,
                    as: GeneratedTabTitle.self,
                    onProgress: onProgress).title
                outcome = .produced(Self.sanitize(raw))
            } catch {
                // Only a genuinely transient error skips stamping so a retry can
                // succeed; a deterministic failure (guardrail, unsupported
                // language, context overflow) behaves like an empty result and
                // stamps, so the same screen is not re-run forever.
                outcome = Self.isTransientGenerationError(error) ? .transientFailure : .produced(nil)
            }
            let latencyMs = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
            let title: String?
            if case .produced(let t) = outcome {
                title = t
            } else {
                title = nil
            }

            // Record every generation that reached the model, including failures
            // (title == nil), so the corpus captures the inputs that produced a
            // bad or empty result too. Guard on isEnabled so we don't copy the whole
            // screen/context/instructions/recentCommands on every generation in the
            // normal case, where corpus logging is off.
            if AITabTitleCorpus.shared.isEnabled {
                AITabTitleCorpus.shared.log(AITabTitleRecord(timestamp: timestamp,
                                                             trigger: reason,
                                                             job: context.job,
                                                             commandLine: context.commandLine,
                                                             atPrompt: context.atPrompt,
                                                             lastCommand: context.lastCommand,
                                                             recentCommands: context.recentCommands.isEmpty ? nil : context.recentCommands,
                                                             cwd: context.cwd,
                                                             user: context.user,
                                                             host: context.host,
                                                             windowName: context.windowName,
                                                             screen: screen,
                                                             context: context.text,
                                                             instructions: instructions,
                                                             model: "apple-on-device",
                                                             title: title,
                                                             latencyMs: latencyMs))
            }

            // Cancel the watchdog before finishing: the model has returned, so its
            // second (force-cleanup) phase must not fire after this finish. If the
            // first (abandon) phase already ran at the timeout boundary, finish
            // recognizes this as an abandoned generation and still applies a usable
            // title rather than dropping it.
            watchdog.cancel()
            self?.finish(sessionID: sessionID,
                         outcome: outcome,
                         digest: digest,
                         histogram: histogram,
                         oscTitle: oscTitle,
                         isAlternate: isAlternate,
                         epoch: epoch,
                         completion: completion)
        }
        // requestTitle inserted the session's state before calling generate, so the
        // entry exists; store the work Task handle on it.
        sessions[sessionID]?.task = work
    }

    // Frees a session whose generation stalled past the timeout so it can retry,
    // and bumps the epoch so the eventual late finish is dropped. Does NOT clear the
    // displayed title: a stall that recovers before the grace timer fires (finish
    // cancels the watchdog) must not flicker a good title to the fallback and back.
    // The display is cleared only once the model has really given up, in
    // forceCleanupHungGeneration.
    func abandonStalledGeneration(sessionID: String, epoch: Int,
                                  digest: Int = 0,
                                  histogram: [NSNumber: NSNumber] = [:],
                                  oscTitle: String = "",
                                  isAlternate: Bool = false) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard sessions[sessionID]?.epoch == epoch, sessions[sessionID]?.inFlight == true else {
            return   // already finished, forgotten, or superseded
        }
        DLog("AI title: abandoning stalled generation for \(sessionID)")
        // Stamp the fingerprint of the screen we gave up on, so an unchanged screen
        // is not immediately retried into the same stall. A genuine transient stall
        // still recovers on the next screen change (its digest/OSC then differ); a
        // permanently wedged model stops being re-invoked every ~8s forever.
        stampTitledFingerprint(sessionID: sessionID, digest: digest, histogram: histogram,
                               oscTitle: oscTitle, isAlternate: isAlternate)
        // Bump past this epoch: the OLD epoch stays outstanding (its call may still
        // return) but is no longer current, so inFlight (computed) becomes false while
        // the gate stays closed on the outstanding set.
        sessions[sessionID]?.epoch = epoch + 1
        // Record that this epoch was abandoned, not finished: if its model call is
        // merely slow and still returns a good title, finish applies it instead of
        // dropping it as superseded.
        sessions[sessionID]?.abandonedEpochs.insert(epoch)
        // Push the throttle forward as well: on a wedged model the mayStartGeneration
        // gate already blocks a new start while this epoch stays outstanding, but if
        // it does resolve, honor the normal inter-attempt spacing from here rather
        // than firing immediately off the pre-stall stamp.
        sessions[sessionID]?.lastAttempt = ProcessInfo.processInfo.systemUptime   // monotonic; matches shouldAttempt
        // Deliberately do NOT cancel the work Task. If LanguageModelSession.respond
        // honors cooperative cancellation, cancelling turns a merely-slow call into a
        // CancellationError, which generate() maps to .transientFailure - defeating
        // the slow-success recovery (there is then no produced title for the
        // abandoned-but-current path to apply). Letting the call run to completion
        // lets a slow-but-good title still land; a truly hung call ignores
        // cancellation anyway, so cancelling would buy nothing. The handle is kept so
        // its late finish is still accounted for.
    }

    // Last resort after abandon: if the model call still hasn't produced a finish a
    // grace period later, assume it is hung and give up on its result. Returns true
    // if a stale title was cleared and the watchdog should clear the displayed
    // variable. Idempotent with a late finish that targets the same epoch.
    @discardableResult
    func forceCleanupHungGeneration(sessionID: String, epoch: Int) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard sessions[sessionID]?.outstandingEpochs.contains(epoch) == true else {
            return false   // it completed within the grace period; nothing to do
        }
        DLog("AI title: force-cleaning hung generation \(epoch) for \(sessionID)")

        // Note: there is no forgotten-session branch here. forget() removes the
        // outstanding entry itself (bumping the counter), so if the session was
        // closed before this fires, the guard above already returned - a closed
        // session is reclaimed by forget, not deferred to this timer.

        // Live session. Give up on this generation's late result: drop the abandoned
        // mark so a call that returns after this grace window is dropped as
        // superseded, not applied - which would otherwise double-fire completion
        // after the clear below (the tab flicks fallback -> stale title).
        removeEpoch(epoch, from: \.abandonedEpochs, for: sessionID)
        // But KEEP the epoch in outstandingEpochs so mayStartGeneration stays closed.
        // Reopening the gate here would, on a degraded machine where every generation
        // exceeds the grace window, start a fresh generation each period while the
        // prior hung calls are still alive - an unbounded pile-up of on-device calls.
        // Instead the gate reopens only when this call finally returns (finish
        // removes the epoch and reclaims) or the session closes (forget). At most one
        // generation is ever outstanding, so state stays bounded. The cost is that a
        // truly-hung call keeps the session from re-titling until it resolves; a
        // merely-slow call that returns before this force-cleanup still applies via
        // the abandoned-but-current path in finish.
        sessions[sessionID]?.task = nil
        // Clear the screen fingerprint abandon stamped. Otherwise this screen stays
        // cached-as-handled, so once the hung call finally resolves (reopening the
        // gate) an unchanged screen would be skipped and stuck on the fallback name
        // forever, even though a fresh generation would now succeed. Clearing it lets
        // that unchanged screen be retitled on the next tick after the call resolves.
        // This does NOT cause a retry loop: while the call stays outstanding the gate
        // is closed, and a permanently-wedged call never reopens it.
        clearTitledFingerprint(sessionID: sessionID)
        // The model has given up for now: if a title was showing it was minted for an
        // earlier screen and is now stale, so clear the applied-title record and
        // report it (the watchdog clears the displayed variable). Deferring this to
        // force-cleanup, rather than abandon, avoids flickering a good title to the
        // fallback and back when a stall recovers within the grace window.
        let hadDisplayedTitle = (sessions[sessionID]?.lastAppliedTitle?.isEmpty == false)
        if hadDisplayedTitle {
            sessions[sessionID]?.lastAppliedTitle = ""
        }
        return hadDisplayedTitle
    }

    // Last-ditch reaper (watchdog phase 3): a generation force-cleaned but whose call
    // still never returned a long backoff later is orphaned. Free its outstanding
    // entry so mayStartGeneration reopens and the session can be titled again (once
    // the model recovers), accepting the one orphaned call. The monotonic epoch
    // counter stays bumped (not reset), so if the orphan ever does return its late
    // finish is dropped as superseded, never aliasing a retry.
    func reapOrphanedGeneration(sessionID: String, epoch: Int) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard sessions[sessionID]?.outstandingEpochs.contains(epoch) == true else {
            return   // it resolved (or was reclaimed) in the meantime; nothing to do
        }
        DLog("AI title: reaping orphaned generation \(epoch) for \(sessionID)")
        removeEpoch(epoch, from: \.outstandingEpochs, for: sessionID)
        removeEpoch(epoch, from: \.abandonedEpochs, for: sessionID)
        sessions[sessionID]?.task = nil
        sessions[sessionID]?.watchdog = nil   // this reaper is the watchdog's last act
        pruneIfEmpty(sessionID)
    }

    private func finish(sessionID: String,
                        outcome: TitleOutcome,
                        digest: Int,
                        histogram: [NSNumber: NSNumber],
                        oscTitle: String,
                        isAlternate: Bool,
                        epoch: Int,
                        completion: (String?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        // This generation's finish has run: it is no longer outstanding.
        removeEpoch(epoch, from: \.outstandingEpochs, for: sessionID)
        let noneOutstanding = sessions[sessionID]?.outstandingEpochs.isEmpty ?? true
        // A generation the watchdog abandoned can still finish with a real title.
        // Consume the abandoned mark and, if the abandon was the ONLY thing that
        // bumped the epoch (no newer generation started) and the session was not
        // forgotten (forget clears the mark), let a usable result apply below
        // rather than be dropped - so a slow-but-successful generation is not lost
        // and its retry not suppressed.
        let wasAbandoned = sessions[sessionID]?.abandonedEpochs.contains(epoch) == true
        if wasAbandoned {
            removeEpoch(epoch, from: \.abandonedEpochs, for: sessionID)
        }
        // An abandoned generation that is still the immediate predecessor (its
        // epoch was bumped exactly once, by the abandon, so no newer generation has
        // started) and whose session was not forgotten (forget clears the mark)
        // should apply its result - EMPTY or not. A usable title lands; an
        // empty result still routes through applyDecision so it clears any stale
        // unrelated title (and stamps the fingerprint) exactly as the non-abandoned
        // empty path does. Dropping the empty case would leave a previous screen's
        // title showing forever, since abandon already stamped this screen.
        //
        // This is the 8s-16s recovery window only: a generation abandoned at 8s that
        // returns before force-cleanup (which at 16s drops the abandoned mark) still
        // applies. While the epoch is outstanding, mayStartGeneration is closed, so
        // no new generation and no not-worth-titling clear can run - nothing can
        // change the fingerprint or the epoch - so a digest re-check here would be a
        // tautology and is deliberately omitted. (A work switch during this window
        // still applies the prior screen's title; that transient wrong-title
        // self-corrects on the next change, an accepted cost of the T4 gate.)
        let abandonedButCurrent = wasAbandoned && sessions[sessionID]?.epoch == epoch + 1
        // Apply only if this is still the session's current generation, or it is an
        // abandoned generation still current per the above. A stale generation (its
        // session was forgotten, or terminated and revived under the same guid,
        // then a newer generation started) has a superseded epoch and is dropped -
        // so it cannot steal the new generation's inFlight token and apply an old
        // title.
        guard sessions[sessionID]?.epoch == epoch || abandonedButCurrent else {
            // Superseded (forgotten, revived, or abandoned). Drop the leftover
            // epoch ONLY when no generation is still outstanding for the session -
            // otherwise another zombie's late finish could see a reset counter and
            // alias a revived session's epoch. A single !inFlight check is not
            // enough because abandon also clears inFlight.
            if noneOutstanding && !(sessions[sessionID]?.inFlight ?? false) {
                clearGenerationEpoch(sessionID)
            }
            return
        }
        // removeEpoch above dropped this epoch from outstandingEpochs, so inFlight
        // (computed) is already false here. The watchdog was cancelled by `work` before
        // it called finish; clear the stored handle so the entry can be pruned.
        sessions[sessionID]?.task = nil
        sessions[sessionID]?.watchdog = nil
        let result = Self.applyDecision(outcome: outcome,
                                        lastAppliedTitle: sessions[sessionID]?.lastAppliedTitle)
        // Cache this screen as handled unless the failure was transient. A
        // greedy, deterministic model reproduces the same (possibly empty) result
        // for an unchanged screen, so stamping stops us re-hitting a static screen
        // every interval; a transient throw is not cached so a retry can succeed.
        if result.stampFingerprint {
            stampTitledFingerprint(sessionID: sessionID, digest: digest, histogram: histogram,
                                   oscTitle: oscTitle, isAlternate: isAlternate)
        } else if wasAbandoned {
            // A transient failure on the abandoned-but-current path. abandon pre-stamped
            // this screen at 8s (so an unchanged screen would not be retried into the
            // same stall), but the transient-failure contract is "do NOT stamp, so the
            // unchanged screen CAN be retried". abandon's stamp defeats that: once the
            // epoch clears, regenerationDecision sees lastDigest == digest and skips
            // forever, leaving the screen permanently untitled. Clear abandon's stamp so
            // the promised retry can actually happen, mirroring forceCleanupHungGeneration.
            // (Non-abandoned transient failures never stamped, so there is nothing to
            // clear for them.)
            clearTitledFingerprint(sessionID: sessionID)
        }
        // Remember any usable title (even one we suppress as a duplicate) so the
        // next generation can tell whether the title actually changed; when we
        // cleared a stale title (titleToApply == ""), record that we now show
        // nothing.
        if case .produced(let title?) = outcome, !title.isEmpty {
            sessions[sessionID]?.lastAppliedTitle = title
        } else if result.titleToApply == "" {
            sessions[sessionID]?.lastAppliedTitle = ""
        }
        if let applied = result.titleToApply {
            DLog("AI tab title -> '\(applied)'")
        }
        completion(result.titleToApply)
    }

    // MARK: - Screen text

    // How the shared condenser treats blank lines, the ONLY axis on which the digest
    // path and the prompt path differ.
    enum BlankLinePolicy {
        case dropAll         // the change digest: every blank line removed (normalize)
        case collapseRuns    // the model prompt: runs of blanks -> one, ends trimmed
    }

    // The single screen condenser shared by the change-digest path (normalize) and the
    // model-prompt path (AppleIntelligenceRunner.condenseWhitespace). Both MUST split on
    // the same newline set and collapse interior whitespace identically, or the digest
    // silently disagrees with what the model sees, causing spurious full regenerations
    // (or missed ones) with no compile error or test failure. Sharing the line walk here
    // - with blank-line handling as an explicit parameter, the only real difference -
    // makes that drift impossible. nonisolated so the prompt path's nonisolated context
    // can call it.
    nonisolated static func condense(_ screen: String, blankLines: BlankLinePolicy) -> String {
        var result: [String] = []
        var lastWasBlank = false
        for rawLine in screen.components(separatedBy: .newlines) {
            let line = collapsedInteriorWhitespace(rawLine)
            if line.isEmpty {
                switch blankLines {
                case .dropAll:
                    continue
                case .collapseRuns:
                    if !lastWasBlank {
                        result.append("")
                    }
                    lastWasBlank = true
                }
            } else {
                result.append(line)
                lastWasBlank = false
            }
        }
        if case .collapseRuns = blankLines {
            while result.first == "" {
                result.removeFirst()
            }
            while result.last == "" {
                result.removeLast()
            }
        }
        return result.joined(separator: "\n")
    }

    // Collapses incidental differences between two repaints of the same screen so
    // they hash equal: interior whitespace runs, leading/trailing whitespace, and
    // blank lines. Collapsing INTERIOR runs (not just trailing) is what keeps the
    // change digest in agreement with what the model actually sees.
    private static func normalize(_ screen: String) -> String {
        return condense(screen, blankLines: .dropAll)
    }

    // Collapses interior space/tab runs to a single space and trims each end of a
    // SINGLE line. The one shared definition used by the condenser above (and hence by
    // both the digest and prompt paths): they must treat interior whitespace identically
    // or the digest disagrees with what the model sees, causing spurious regenerations.
    nonisolated static func collapsedInteriorWhitespace(_ line: String) -> String {
        return line.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
    }

    private static func isWorthTitling(_ normalized: String) -> Bool {
        return normalized.components(separatedBy: "\n").count >= minimumInterestingLines
    }

    // MARK: - Model output

    // Keeps whole space-separated words up to `maxLength` graphemes; if the first
    // word alone exceeds it, hard-truncates that word. Never returns empty for a
    // non-empty input.
    private static func truncatedToWordBoundary(_ s: String, maxLength: Int) -> String {
        var result = ""
        for word in s.split(separator: " ") {
            let candidate = result.isEmpty ? String(word) : result + " " + word
            if candidate.count > maxLength {
                break
            }
            result = candidate
        }
        if result.isEmpty {
            result = String(s.prefix(maxLength))
        }
        return result
    }

    // Whether `first` and `last` form a genuine wrapping quote pair: the same quote
    // glyph at both ends (straight, or the SAME curly glyph the model sometimes emits
    // on both sides), or a curly opener with its matching curly closer. A mismatched
    // pair (opener of one kind, unrelated closer) is not a wrapper, so unwrapping it
    // would delete legitimate content. Requiring the IDENTICAL glyph at both ends for
    // the same-glyph cases keeps a leading/trailing apostrophe ('90s Playlist, at the
    // front only) untouched.
    private static func isMatchedQuotePair(_ first: Character, _ last: Character) -> Bool {
        switch (first, last) {
        case ("\"", "\""), ("'", "'"),
             ("\u{201C}", "\u{201D}"),   // “ … ”
             ("\u{2018}", "\u{2019}"),   // ‘ … ’
             ("\u{201D}", "\u{201D}"),   // ” … ” (same closer both ends)
             ("\u{201C}", "\u{201C}"),   // “ … “ (same opener both ends)
             ("\u{2019}", "\u{2019}"),   // ’ … ’
             ("\u{2018}", "\u{2018}"):   // ‘ … ‘
            return true
        default:
            return false
        }
    }

    // The model's reply is untrusted text on its way into persistent UI. Guided
    // generation makes a well-formed single field very likely but not a
    // *sensible* one, so everything the tab bar cannot render safely is stripped
    // here, at the single point where titles are minted.
    static func sanitize(_ raw: String) -> String? {
        // JOIN the non-empty lines with a space rather than taking only the first.
        // Skipping leading blank lines is still needed (the on-device model sometimes
        // prefixes its reply with a blank line; the first physical line would be "" ->
        // nil -> the fingerprint is stamped and a good title lost), but greedy
        // generation can also put a newline INSIDE the single `title` field ("Fix\n
        // Auth Bug"), and taking only the first line would truncate that to "Fix". The
        // interior-whitespace collapse below turns the joined result's runs into single
        // spaces, so "Fix Auth Bug" is recovered whole.
        let contentLines = raw.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var trimmed = contentLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        // Models like to wrap a title in quotes despite being told not to.
        // Curly quotes included: the reply is prose, not source.
        // Unwrap a MATCHED surrounding quote pair, not every leading/trailing quote:
        // trimmingCharacters would mangle a title that legitimately begins or ends
        // with an apostrophe ('90s Playlist, 'Tis the Season).
        // Loop so a double-wrapped reply (""Build System"") is fully unwrapped, not
        // left with an inner pair. Bounded: each pass removes two characters. Strip
        // only a genuine MATCHED wrapping pair - same straight quote at both ends,
        // or a curly opener with its matching curly closer - so a leading/trailing
        // apostrophe ('90s Playlist) and an asymmetric/mismatched pair ("Developers')
        // are preserved rather than mangled.
        while trimmed.count >= 2, let first = trimmed.first, let last = trimmed.last,
              Self.isMatchedQuotePair(first, last) {
            let interior = trimmed.dropFirst().dropLast()
            // isMatchedQuotePair only compares the two endpoints, so a title that merely
            // begins and ends with a quote glyph but is NOT a single wrapped span - two
            // separate quoted words ("git" vs "hg", 'ls' and 'cd') - would be mangled by
            // stripping. Only strip when the pair genuinely wraps the whole title: the
            // wrapping glyph is absent from the interior, OR the interior is itself a
            // matched pair (a nested double-wrap like ""Build System"", which the next
            // pass then unwraps). If the interior contains the glyph but its own ends are
            // not a pair, the quotes belong to different spans, so stop.
            if interior.contains(first) || interior.contains(last) {
                guard let innerFirst = interior.first, let innerLast = interior.last,
                      Self.isMatchedQuotePair(innerFirst, innerLast) else {
                    break
                }
            }
            trimmed = String(interior)
        }
        trimmed = trimmed.trimmingCharacters(in: .whitespaces)

        // Interior whitespace runs - a doubled regular space, a tab, or any Unicode
        // space separator (NBSP, EN/EM/THIN, IDEOGRAPHIC U+3000, ...) the model may
        // emit - are just whitespace, not a malformed reply, so collapse any run to a
        // single ASCII space rather than rejecting the title or letting the exotic
        // spaces through verbatim into the permanent tab title. Use the whole
        // whitespace category (not a hand-picked list), plus the zero-width space
        // U+200B (Cf, not Zs) which is invisible padding.
        var interiorWhitespace = CharacterSet.whitespaces
        interiorWhitespace.insert("\u{200B}")
        trimmed = trimmed.components(separatedBy: interiorWhitespace)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // A remaining genuine control character (Cc: NUL, ESC, a newline) means the
        // title is malformed, so reject. NOT most Unicode FORMAT chars (Cf) -
        // CharacterSet.controlCharacters is Cc AND Cf, and Cf includes the ZERO
        // WIDTH JOINER in emoji sequences (👨‍💻) and the bidi marks LRM/RLM in RTL
        // titles, which are well-formed, not malformed. BUT reject the bidi
        // OVERRIDE / ISOLATE controls (also Cf): U+202A-202E (LRE/RLE/PDF/LRO/RLO)
        // and U+2066-2069 (LRI/RLI/FSI/PDI) can visually reorder the title and the
        // adjacent tab-bar text (Trojan-Source-style) - exactly what an untrusted
        // model reply into persistent UI must not be able to do.
        guard !trimmed.unicodeScalars.contains(where: { scalar in
            scalar.properties.generalCategory == .control
                || (0x202A...0x202E).contains(scalar.value)
                || (0x2066...0x2069).contains(scalar.value)
        }) else {
            return nil
        }
        guard !trimmed.isEmpty else {
            return nil
        }
        // Truncate an over-long but otherwise valid title on a word boundary rather
        // than discarding it. The model is asked for 2-to-4 words, but four words
        // can legitimately exceed the cap ("Continuous Integration Pipeline
        // Configuration"); returning nil makes generate stamp the screen as handled,
        // leaving a screen for which the model produced a fine name untitled forever
        // with no shorter retry.
        if trimmed.count > maximumTitleLength {
            trimmed = Self.truncatedToWordBoundary(trimmed, maxLength: maximumTitleLength)
        }
        // Bound the scalar count too: `count` is grapheme clusters, so one base char
        // plus hundreds of combining scalars ("Zalgo") is only a few graphemes and
        // would pass the cap above, then go into a persistent tab title. This is an
        // anti-abuse guard (unlike the length cap, malformed rather than merely
        // long), so it stays reject-not-truncate. A generous factor still admits
        // legitimate multi-scalar emoji/ZWJ titles.
        guard trimmed.unicodeScalars.count <= maximumTitleLength * 4 else {
            return nil
        }
        // Require actual content, checked on the FINAL string AFTER truncation:
        // truncation can drop the only alphanumeric word (a leading "- " plus one
        // over-length word truncates to just "-"), so checking before it would let a
        // punctuation-only title through - the very thing this guard prevents. Reject
        // an all-punctuation reply (a lone quote, "--", "...", "??"): the @Generable
        // schema exists because the model occasionally returns a bare failure token,
        // so treat a content-free reply like the other unusable results (no title
        // applied, fingerprint stamped). CJK/Arabic letters count (they are
        // .alphanumerics); only symbol/punctuation-only replies are rejected.
        guard trimmed.rangeOfCharacter(from: .alphanumerics) != nil else {
            return nil
        }
        return trimmed
    }

    // Deliberately gives no concrete example title. A worked example ("a diff is
    // Code Review") anchors the small on-device model hard: in the live grader
    // it then answered "Code Review" for a vim edit and a dev server too. Asking
    // for specificity without an example produces diverse, on-target titles. See
    // AILiveAppleIntelligenceTabTitle for the comparison.
    private static let instructions = """
        You name terminal tabs. You are given context about a terminal session \
        and the visible contents of its screen. Work out what the user is trying \
        to accomplish in this session and reply with a Title Case label of at \
        most four words for that goal. Read the whole screen, not just the latest \
        output: the sequence of commands and the files, services, or projects \
        they touch reveal the goal better than any single line does. Name the \
        goal or activity, not the tool hosting it and not merely the most recent \
        command or its output, and prefer a name that stays stable while the user \
        keeps working toward the same thing. Keep it short; avoid generic labels.
        """
}

