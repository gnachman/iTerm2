//
//  iTermOpenQuicklyContentSearch.swift
//  iTerm2SharedARC
//
//  Searches the contents of every session for Open Quickly's "/g" command. The
//  heavy lifting is done by iTermGlobalSearchEngine (the engine behind Find
//  Globally), which searches incrementally from the main run loop and can be
//  stopped at any time. Sessions running Claude Code also have their
//  conversation transcript searched (see iTermClaudeCodeTranscripts). This class
//  reduces the results to one match per session so Open Quickly can show one row
//  per session.
//

import AppKit

// Where a match was found. The same text is often in more than one source, so
// matches are counted per source rather than added up.
enum iTermContentMatchSource: Int, Comparable {
    // The session's scrollback and screen. Preferred because the match can be
    // scrolled to.
    case buffer
    // The transcript of a Claude Code conversation running in the session.
    case claudeCodeTranscript

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// Accumulates search results per session: how many matches each one has and its
// first match, which supplies the snippet and the place to scroll to. Free of
// session types so it can be unit tested.
struct iTermContentMatchTally<Key: Hashable, Result> {
    struct Entry {
        fileprivate var firsts = [iTermContentMatchSource: Result]()
        fileprivate var counts = [iTermContentMatchSource: Int]()
        // Order in which the session first matched. Used as a stable tiebreaker.
        var ordinal: Int

        // The first match from the most useful source.
        var first: Result {
            return firsts[firsts.keys.min()!]!
        }

        // The number of matches in the source with the most of them.
        var count: Int {
            return counts.values.max() ?? 0
        }
    }

    private(set) var entries = [Key: Entry]()

    mutating func add(_ results: [Result], count: Int? = nil, for key: Key, source: iTermContentMatchSource) {
        guard let first = results.first else {
            return
        }
        var entry = entries[key] ?? Entry(ordinal: entries.count)
        if entry.firsts[source] == nil {
            entry.firsts[source] = first
        }
        entry.counts[source, default: 0] += count ?? results.count
        entries[key] = entry
    }

    mutating func removeAll() {
        entries.removeAll()
    }
}

@objc(iTermOpenQuicklyContentMatch)
class iTermOpenQuicklyContentMatch: NSObject {
    @objc let session: PTYSession
    @objc let result: iTermGlobalSearchResultProtocol
    @objc let count: Int
    @objc let ordinal: Int

    init(session: PTYSession, result: iTermGlobalSearchResultProtocol, count: Int, ordinal: Int) {
        self.session = session
        self.result = result
        self.count = count
        self.ordinal = ordinal
    }
}

@objc(iTermOpenQuicklyContentSearch)
class iTermOpenQuicklyContentSearch: NSObject {
    // Shorter queries match nearly every session and the engine would spend a long
    // time producing results nobody will look at.
    @objc static let minimumQueryLength = 2

    // Coalesces the engine's frequent callbacks into one UI refresh per interval.
    private static let updateInterval: TimeInterval = 0.1

    @objc private(set) var query: String?
    @objc var finished: Bool {
        return engine == nil && !searchingTranscripts
    }
    private var engine: iTermGlobalSearchEngine?
    private var searchingTranscripts = false
    // Keyed by session GUID. Sessions are looked up when needed rather than
    // retained, so a session that closes during a search drops out.
    private var tally = iTermContentMatchTally<String, iTermGlobalSearchResultProtocol>()
    private var updateScheduled = false
    private var onUpdate: (() -> Void)?
    // Incremented whenever a search starts or stops so stale callbacks are dropped.
    private var generation = 0

    // Starts a search unless one for the same query already ran, so it is safe to
    // call on every model refresh. onUpdate is called (coalesced) as results
    // arrive and once more when the search finishes.
    @objc(searchFor:sessions:onUpdate:)
    @MainActor
    func search(for query: String, sessions: [PTYSession], onUpdate: @escaping () -> Void) {
        if query == self.query {
            self.onUpdate = onUpdate
            return
        }
        stop()
        self.query = query
        self.onUpdate = onUpdate
        guard query.count >= Self.minimumQueryLength, !sessions.isEmpty else {
            return
        }
        DLog("Open Quickly content search for \(query) in \(sessions.count) sessions")
        let generation = self.generation
        searchTranscripts(for: query, sessions: sessions, generation: generation)
        engine = iTermGlobalSearchEngine(query: query,
                                         sessions: sessions,
                                         mode: .smartCaseSensitivity) { [weak self] session, results, _ in
            guard let self, self.generation == generation else {
                return
            }
            guard let session else {
                // The engine calls the handler with a nil session when it is done.
                DLog("Open Quickly content search for \(query) finished searching buffers")
                self.engine = nil
                self.scheduleUpdate()
                return
            }
            guard let results, !results.isEmpty else {
                return
            }
            self.tally.add(results, for: session.guid, source: .buffer)
            self.scheduleUpdate()
        }
    }

    @MainActor
    private func searchTranscripts(for query: String, sessions: [PTYSession], generation: Int) {
        guard iTermAdvancedSettingsModel.openQuicklySearchesClaudeCodeTranscripts() else {
            return
        }
        let transcripts = iTermClaudeCodeTranscripts.instance
        var candidates = [String: [iTermClaudeCodeTranscripts.Candidate]]()
        for session in sessions {
            let processes = transcripts.candidates(for: session)
            if !processes.isEmpty {
                candidates[session.guid] = processes
            }
        }
        guard !candidates.isEmpty else {
            return
        }
        searchingTranscripts = true
        transcripts.search(for: query, candidates: candidates) { [weak self] occurrencesByGUID in
            guard let self, self.generation == generation else {
                return
            }
            self.searchingTranscripts = false
            for (guid, occurrences) in occurrencesByGUID {
                guard let session = iTermController.sharedInstance().session(withGUID: guid),
                      let snippet = occurrences.snippet() else {
                    continue
                }
                let attributedSnippet = NSMutableAttributedString(string: snippet.text)
                // Same emphasis as Find Globally's snippets.
                attributedSnippet.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue,
                                                 .backgroundColor: NSColor(red: 1, green: 1, blue: 0, alpha: 0.35)],
                                                range: snippet.matchRange)
                let result = iTermClaudeCodeTranscriptSearchResult(session: session, snippet: attributedSnippet)
                self.tally.add([result],
                               count: occurrences.count,
                               for: guid,
                               source: .claudeCodeTranscript)
            }
            self.scheduleUpdate()
        }
    }

    // Cancels any search in progress and forgets its results.
    @objc func stop() {
        generation += 1
        let engine = self.engine
        self.engine = nil
        engine?.stop()
        query = nil
        searchingTranscripts = false
        tally.removeAll()
        updateScheduled = false
        onUpdate = nil
    }

    // One match per session that still exists, in the order sessions first matched.
    @objc var matches: [iTermOpenQuicklyContentMatch] {
        return tally.entries.compactMap { guid, entry -> iTermOpenQuicklyContentMatch? in
            guard let session = iTermController.sharedInstance().session(withGUID: guid) else {
                return nil
            }
            return iTermOpenQuicklyContentMatch(session: session,
                                                result: entry.first,
                                                count: entry.count,
                                                ordinal: entry.ordinal)
        }.sorted { $0.ordinal < $1.ordinal }
    }

    private func scheduleUpdate() {
        if updateScheduled {
            return
        }
        updateScheduled = true
        let generation = self.generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.updateInterval) { [weak self] in
            guard let self, self.generation == generation else {
                return
            }
            self.updateScheduled = false
            self.onUpdate?()
        }
    }
}
