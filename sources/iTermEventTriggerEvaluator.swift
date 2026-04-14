//
//  iTermEventTriggerEvaluator.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/1/26.
//

import Foundation

// MARK: - Event Info Types

/// Information about a command that finished
@objc(iTermEventCommandFinishedInfo)
class EventCommandFinishedInfo: NSObject {
    @objc let exitCode: Int32
    @objc let command: String?
    @objc let duration: TimeInterval

    @objc init(exitCode: Int32, command: String?, duration: TimeInterval) {
        self.exitCode = exitCode
        self.command = command
        self.duration = duration
    }
}

/// Information about a custom escape sequence
@objc(iTermEventCustomEscapeSequenceInfo)
class EventCustomEscapeSequenceInfo: NSObject {
    @objc let identifier: String
    @objc let payload: String

    @objc init(identifier: String, payload: String) {
        self.identifier = identifier
        self.payload = payload
    }
}

// MARK: - Event Trigger Evaluator

/// Evaluates event-based triggers (match type >= 100)
@objc(iTermEventTriggerEvaluator)
class EventTriggerEvaluator: NSObject {

    // MARK: - Properties

    @objc var triggerParametersUseInterpolatedStrings = false
    @objc var disabled = false
    @objc var foregroundJobAncestors: [String]?

    /// Description of the owning session for logging purposes
    private let sessionDescription: String

    /// Closure to fire a trigger. Set by PTYSession to forward to VT100Screen.
    @objc var fireTriggerHandler: ((Trigger, [String], Bool) -> Void)?

    /// All event triggers grouped by match type
    private var eventTriggers: [iTermTriggerMatchType: [Trigger]] = [:]

    /// Idle timers keyed by trigger (using ObjectIdentifier)
    private var idleTimers: [ObjectIdentifier: Timer] = [:]

    /// Long-running command timers keyed by trigger
    private var longRunningTimers: [ObjectIdentifier: Timer] = [:]

    /// When the current command started (for long-running detection)
    private var commandStartTime: Date?

    /// The current command being executed (for providing context)
    private var currentCommand: String?

    /// Whether we're currently idle (per trigger)
    private var isIdleForTrigger: [ObjectIdentifier: Bool] = [:]

    // MARK: - Initialization

    @objc init(sessionDescription: String) {
        self.sessionDescription = sessionDescription
        super.init()
        DLog("[\(sessionDescription)] EventTriggerEvaluator initialized")
    }

    deinit {
        DLog("[\(sessionDescription)] EventTriggerEvaluator deallocated")
        invalidateAllTimers()
    }

    // MARK: - Loading Triggers

    /// Load event triggers from profile array
    @objc func loadFromProfileArray(_ array: [[String: Any]]) {
        DLog("[\(sessionDescription)] Loading triggers from \(array.count) trigger definitions")
        invalidateAllTimers()
        eventTriggers.removeAll()
        isIdleForTrigger.removeAll()

        for dict in array {
            guard let trigger = Trigger(fromUntrustedDict: dict) else {
                DLog("[\(sessionDescription)] Failed to create trigger from dict: \(dict)")
                continue
            }

            let matchType = trigger.matchType
            guard iTermTriggerMatchTypeIsEvent(matchType) else {
                continue
            }

            DLog("[\(sessionDescription)] Loaded event trigger: \(trigger.action) matchType=\(matchType.rawValue) params=\(trigger.eventParams ?? [:])")
            if eventTriggers[matchType] == nil {
                eventTriggers[matchType] = []
            }
            eventTriggers[matchType]?.append(trigger)
        }

        DLog("[\(sessionDescription)] Loaded \(enabledEventTriggerCount) enabled event triggers across \(eventTriggers.count) event types")

        // Start idle timers for idle/activity-after-idle triggers
        startIdleTimers()
    }

    /// Check if there are any event triggers loaded
    @objc var hasEventTriggers: Bool {
        return !eventTriggers.isEmpty
    }

    /// Get the number of enabled event triggers
    @objc var enabledEventTriggerCount: Int {
        return eventTriggers.values.reduce(0) { count, triggers in
            count + triggers.filter { !$0.disabled }.count
        }
    }

    // MARK: - Trigger Type Checks

    @objc var hasPromptDetectedTrigger: Bool {
        return hasEnabledTrigger(for: .eventPromptDetected)
    }

    @objc var hasCommandFinishedTrigger: Bool {
        return hasEnabledTrigger(for: .eventCommandFinished)
    }

    @objc var hasDirectoryChangedTrigger: Bool {
        return hasEnabledTrigger(for: .eventDirectoryChanged)
    }

    @objc var hasHostChangedTrigger: Bool {
        return hasEnabledTrigger(for: .eventHostChanged)
    }

    @objc var hasUserChangedTrigger: Bool {
        return hasEnabledTrigger(for: .eventUserChanged)
    }

    @objc var hasIdleTrigger: Bool {
        return hasEnabledTrigger(for: .eventIdle)
    }

    @objc var hasActivityAfterIdleTrigger: Bool {
        return hasEnabledTrigger(for: .eventActivityAfterIdle)
    }

    @objc var hasSessionEndedTrigger: Bool {
        return hasEnabledTrigger(for: .eventSessionEnded)
    }

    @objc var hasBellReceivedTrigger: Bool {
        return hasEnabledTrigger(for: .eventBellReceived)
    }

    @objc var hasLongRunningCommandTrigger: Bool {
        return hasEnabledTrigger(for: .eventLongRunningCommand)
    }

    @objc var hasCustomEscapeSequenceTrigger: Bool {
        return hasEnabledTrigger(for: .eventCustomEscapeSequence)
    }

    private func hasEnabledTrigger(for matchType: iTermTriggerMatchType) -> Bool {
        guard let triggers = eventTriggers[matchType] else { return false }
        return triggers.contains { !$0.disabled }
    }

    // MARK: - Event Methods

    /// Called when a prompt is detected
    @objc func promptDetected() {
        DLog("[\(sessionDescription)] Prompt detected")
        fireTriggersForMatchType(.eventPromptDetected)
    }

    /// Called when a command finishes
    @objc func commandFinished(info: EventCommandFinishedInfo) {
        DLog("[\(sessionDescription)] Command finished: exitCode=\(info.exitCode) command=\(info.command ?? "(nil)") duration=\(info.duration)")
        // Stop all long-running timers since command finished
        for (_, timer) in longRunningTimers {
            timer.invalidate()
        }
        longRunningTimers.removeAll()
        commandStartTime = nil
        currentCommand = nil

        guard !disabled else {
            DLog("[\(sessionDescription)] Disabled, skipping command finished triggers")
            return
        }
        guard let triggers = eventTriggers[.eventCommandFinished] else {
            DLog("[\(sessionDescription)] No command finished triggers configured")
            return
        }

        for trigger in triggers where !trigger.disabled {
            if matchesExitCodeFilter(trigger: trigger, exitCode: info.exitCode) {
                fireTrigger(trigger, capturedStrings: ["\(info.exitCode)"])
            } else {
                DLog("[\(sessionDescription)] Exit code \(info.exitCode) did not match filter for trigger \(trigger.action)")
            }
        }
    }

    /// Called when the working directory changes
    @objc func directoryChanged(to path: String) {
        DLog("[\(sessionDescription)] Directory changed to: \(path)")
        guard !disabled else {
            DLog("[\(sessionDescription)] Disabled, skipping directory changed triggers")
            return
        }
        guard let triggers = eventTriggers[.eventDirectoryChanged] else {
            DLog("[\(sessionDescription)] No directory changed triggers configured")
            return
        }

        for trigger in triggers where !trigger.disabled {
            if matchesDirectoryFilter(trigger: trigger, path: path) {
                fireTrigger(trigger, capturedStrings: [path])
            } else {
                DLog("[\(sessionDescription)] Path '\(path)' did not match filter for trigger \(trigger.action)")
            }
        }
    }

    /// Called when the remote host changes
    @objc func hostChanged(to host: String) {
        DLog("[\(sessionDescription)] Host changed to: \(host)")
        guard !disabled else {
            DLog("[\(sessionDescription)] Disabled, skipping host changed triggers")
            return
        }
        guard let triggers = eventTriggers[.eventHostChanged] else {
            DLog("[\(sessionDescription)] No host changed triggers configured")
            return
        }

        for trigger in triggers where !trigger.disabled {
            if matchesHostFilter(trigger: trigger, host: host) {
                fireTrigger(trigger, capturedStrings: [host])
            } else {
                DLog("[\(sessionDescription)] Host '\(host)' did not match filter for trigger \(trigger.action)")
            }
        }
    }

    /// Called when the user changes
    @objc func userChanged(to user: String) {
        DLog("[\(sessionDescription)] User changed to: \(user)")
        guard !disabled else {
            DLog("[\(sessionDescription)] Disabled, skipping user changed triggers")
            return
        }
        guard let triggers = eventTriggers[.eventUserChanged] else {
            DLog("[\(sessionDescription)] No user changed triggers configured")
            return
        }

        for trigger in triggers where !trigger.disabled {
            if matchesUserFilter(trigger: trigger, user: user) {
                fireTrigger(trigger, capturedStrings: [user])
            } else {
                DLog("[\(sessionDescription)] User '\(user)' did not match filter for trigger \(trigger.action)")
            }
        }
    }

    /// Called when output is received (resets idle timers, checks activity-after-idle)
    @objc func outputReceived() {
        guard !disabled else { return }

        // Check for activity-after-idle triggers
        if let triggers = eventTriggers[.eventActivityAfterIdle] {
            for trigger in triggers where !trigger.disabled {
                let triggerId = ObjectIdentifier(trigger)
                if isIdleForTrigger[triggerId] == true {
                    DLog("[\(sessionDescription)] Activity after idle detected, firing trigger \(trigger.action)")
                    isIdleForTrigger[triggerId] = false
                    fireTrigger(trigger, capturedStrings: [])
                }
            }
        }

        // Also reset idle state for idle triggers
        if let triggers = eventTriggers[.eventIdle] {
            for trigger in triggers {
                let triggerId = ObjectIdentifier(trigger)
                isIdleForTrigger[triggerId] = false
            }
        }

        // Reset all idle timers
        resetIdleTimers()
    }

    /// Called when session ends
    @objc func sessionEnded() {
        DLog("[\(sessionDescription)] Session ended")
        invalidateAllTimers()
        fireTriggersForMatchType(.eventSessionEnded)
    }

    /// Called when bell is received
    @objc func bellReceived() {
        DLog("[\(sessionDescription)] Bell received")
        fireTriggersForMatchType(.eventBellReceived)
    }

    /// Called when a command starts
    @objc func commandStarted(command: String?) {
        DLog("[\(sessionDescription)] Command started: \(command ?? "(nil)")")
        commandStartTime = Date()
        currentCommand = command

        guard !disabled else {
            DLog("[\(sessionDescription)] Disabled, skipping long-running command timers")
            return
        }

        // Start long-running timers for each long-running command trigger
        guard let triggers = eventTriggers[.eventLongRunningCommand] else {
            return
        }

        for trigger in triggers where !trigger.disabled {
            // Only start timer if command matches the filter (or no filter specified)
            if !matchesCommandFilter(trigger: trigger, command: command ?? "") {
                DLog("[\(sessionDescription)] Command '\(command ?? "")' did not match filter for long-running trigger \(trigger.action)")
                continue
            }

            let threshold = (trigger.eventParams?["threshold"] as? NSNumber)?.doubleValue ?? 60.0
            let triggerId = ObjectIdentifier(trigger)

            DLog("[\(sessionDescription)] Starting long-running timer for \(threshold)s for trigger \(trigger.action)")
            longRunningTimers[triggerId]?.invalidate()
            longRunningTimers[triggerId] = Timer.scheduledTimer(
                withTimeInterval: threshold,
                repeats: false
            ) { [weak self, weak trigger] _ in
                guard let self = self, let trigger = trigger else { return }
                self.longRunningTimerFired(for: trigger)
            }
        }
    }

    /// Called when a custom escape sequence is received
    @objc func customEscapeSequence(info: EventCustomEscapeSequenceInfo) {
        DLog("[\(sessionDescription)] Custom escape sequence received: id=\(info.identifier) payload=\(info.payload)")
        guard !disabled else {
            DLog("[\(sessionDescription)] Disabled, skipping custom escape sequence triggers")
            return
        }
        guard let triggers = eventTriggers[.eventCustomEscapeSequence] else {
            DLog("[\(sessionDescription)] No custom escape sequence triggers configured")
            return
        }

        for trigger in triggers where !trigger.disabled {
            if matchesSequenceIdFilter(trigger: trigger, identifier: info.identifier) {
                fireTrigger(trigger, capturedStrings: [info.identifier, info.payload])
            } else {
                DLog("[\(sessionDescription)] Sequence ID '\(info.identifier)' did not match filter for trigger \(trigger.action)")
            }
        }
    }

    // MARK: - Timer Management

    private func invalidateAllTimers() {
        if !idleTimers.isEmpty || !longRunningTimers.isEmpty {
            DLog("[\(sessionDescription)] Invalidating all timers: \(idleTimers.count) idle, \(longRunningTimers.count) long-running")
        }
        for (_, timer) in idleTimers {
            timer.invalidate()
        }
        idleTimers.removeAll()

        for (_, timer) in longRunningTimers {
            timer.invalidate()
        }
        longRunningTimers.removeAll()
    }

    private func startIdleTimers() {
        // Start timers for idle triggers
        if let triggers = eventTriggers[.eventIdle] {
            for trigger in triggers where !trigger.disabled {
                startIdleTimer(for: trigger)
            }
        }

        // Also start timers for activity-after-idle triggers (they need to track idle state)
        if let triggers = eventTriggers[.eventActivityAfterIdle] {
            for trigger in triggers where !trigger.disabled {
                startIdleTimer(for: trigger)
            }
        }
    }

    private func startIdleTimer(for trigger: Trigger) {
        let timeout = (trigger.eventParams?["timeout"] as? NSNumber)?.doubleValue ?? 30.0
        let triggerId = ObjectIdentifier(trigger)

        DLog("[\(sessionDescription)] Starting idle timer for \(timeout)s for trigger \(trigger.action)")
        idleTimers[triggerId]?.invalidate()
        idleTimers[triggerId] = Timer.scheduledTimer(
            withTimeInterval: timeout,
            repeats: false
        ) { [weak self, weak trigger] _ in
            guard let self = self, let trigger = trigger else { return }
            self.idleTimerFired(for: trigger)
        }
    }

    private func resetIdleTimers() {
        // Reset timers for idle triggers
        if let triggers = eventTriggers[.eventIdle] {
            for trigger in triggers where !trigger.disabled {
                startIdleTimer(for: trigger)
            }
        }

        // Reset timers for activity-after-idle triggers
        if let triggers = eventTriggers[.eventActivityAfterIdle] {
            for trigger in triggers where !trigger.disabled {
                startIdleTimer(for: trigger)
            }
        }
    }

    private func idleTimerFired(for trigger: Trigger) {
        DLog("[\(sessionDescription)] Idle timer fired for trigger \(trigger.action)")
        let triggerId = ObjectIdentifier(trigger)
        isIdleForTrigger[triggerId] = true

        // Only fire if this is an idle trigger (not activity-after-idle)
        if trigger.matchType == .eventIdle && !trigger.disabled {
            let timeout = (trigger.eventParams?["timeout"] as? NSNumber)?.doubleValue ?? 30.0
            fireTrigger(trigger, capturedStrings: ["\(Int(timeout))"])
        } else {
            DLog("[\(sessionDescription)] Not firing idle trigger (matchType=\(trigger.matchType.rawValue) disabled=\(trigger.disabled))")
        }
    }

    private func longRunningTimerFired(for trigger: Trigger) {
        DLog("[\(sessionDescription)] Long-running timer fired for trigger \(trigger.action)")
        guard !trigger.disabled else {
            DLog("[\(sessionDescription)] Trigger is disabled, not firing")
            return
        }

        let triggerId = ObjectIdentifier(trigger)
        longRunningTimers.removeValue(forKey: triggerId)

        let elapsed = commandStartTime.map { -$0.timeIntervalSinceNow } ?? 0
        let command = currentCommand ?? ""
        DLog("[\(sessionDescription)] Command '\(command)' has been running for \(Int(elapsed))s")
        fireTrigger(trigger, capturedStrings: [command, "\(Int(elapsed))"])
    }

    // MARK: - Trigger Evaluation

    private func fireTriggersForMatchType(_ matchType: iTermTriggerMatchType, capturedStrings: [String] = []) {
        guard !disabled else {
            DLog("[\(sessionDescription)] Disabled, skipping triggers for matchType \(matchType.rawValue)")
            return
        }
        guard let triggers = eventTriggers[matchType] else {
            DLog("[\(sessionDescription)] No triggers configured for matchType \(matchType.rawValue)")
            return
        }

        DLog("[\(sessionDescription)] Firing \(triggers.filter { !$0.disabled }.count) triggers for matchType \(matchType.rawValue)")
        let currentJobAncestors = foregroundJobAncestors
        for trigger in triggers where !trigger.disabled {
            if let triggerJob = trigger.job, !triggerJob.isEmpty,
               !(currentJobAncestors?.contains(triggerJob.lowercased()) ?? false) {
                DLog("[\(sessionDescription)] Skip trigger \(trigger.action) because job \(triggerJob) doesn't match foreground job ancestors \(String(describing: currentJobAncestors))")
                continue
            }
            fireTrigger(trigger, capturedStrings: capturedStrings)
        }
    }

    private func fireTrigger(_ trigger: Trigger, capturedStrings: [String]) {
        guard let handler = fireTriggerHandler else {
            DLog("[\(sessionDescription)] No fireTriggerHandler set, cannot fire trigger \(trigger.action)")
            return
        }
        DLog("[\(sessionDescription)] Firing trigger \(trigger.action) with captures: \(capturedStrings)")
        handler(trigger, capturedStrings, triggerParametersUseInterpolatedStrings)
    }

    // MARK: - Filter Matching

    /// Checks if a string matches a regex pattern from trigger event params.
    /// Returns true if no pattern is specified (matches all).
    /// Falls back to substring matching if the regex is invalid.
    private func matchesRegexParam(trigger: Trigger,
                                   paramKey: String,
                                   value: String,
                                   fallbackToExactMatch: Bool = false) -> Bool {
        guard let pattern = trigger.eventParams?[paramKey] as? String, !pattern.isEmpty else {
            DLog("[\(sessionDescription)] No pattern for \(paramKey), matches by default")
            return true
        }

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(value.startIndex..., in: value)
            let matches = regex.firstMatch(in: value, options: [], range: range) != nil
            DLog("[\(sessionDescription)] Regex /\(pattern)/ \(matches ? "matches" : "does not match") '\(value)'")
            return matches
        } catch {
            let matches = fallbackToExactMatch ? (value == pattern) : value.contains(pattern)
            DLog("[\(sessionDescription)] Invalid regex /\(pattern)/, falling back to \(fallbackToExactMatch ? "exact" : "substring") match: \(matches)")
            return matches
        }
    }

    private func matchesExitCodeFilter(trigger: Trigger, exitCode: Int32) -> Bool {
        guard let filter = trigger.eventParams?["exitCodeFilter"] as? String else {
            DLog("[\(sessionDescription)] No exit code filter, matches by default")
            return true
        }

        let matches: Bool
        switch filter {
        case "*", "":
            matches = true
        case "0":
            matches = exitCode == 0
        case "!0":
            matches = exitCode != 0
        default:
            if let specificCode = Int32(filter) {
                matches = exitCode == specificCode
            } else {
                matches = true
            }
        }
        DLog("[\(sessionDescription)] Exit code filter '\(filter)' \(matches ? "matches" : "does not match") exit code \(exitCode)")
        return matches
    }

    private func matchesSequenceIdFilter(trigger: Trigger, identifier: String) -> Bool {
        return matchesRegexParam(trigger: trigger,
                                 paramKey: "sequenceId",
                                 value: identifier,
                                 fallbackToExactMatch: true)
    }

    private func matchesDirectoryFilter(trigger: Trigger, path: String) -> Bool {
        return matchesRegexParam(trigger: trigger, paramKey: "directoryRegex", value: path)
    }

    private func matchesHostFilter(trigger: Trigger, host: String) -> Bool {
        return matchesRegexParam(trigger: trigger, paramKey: "hostRegex", value: host)
    }

    private func matchesUserFilter(trigger: Trigger, user: String) -> Bool {
        return matchesRegexParam(trigger: trigger, paramKey: "userRegex", value: user)
    }

    private func matchesCommandFilter(trigger: Trigger, command: String) -> Bool {
        return matchesRegexParam(trigger: trigger, paramKey: "commandRegex", value: command)
    }
}

