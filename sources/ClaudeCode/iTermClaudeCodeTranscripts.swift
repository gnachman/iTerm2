//
//  iTermClaudeCodeTranscripts.swift
//  iTerm2SharedARC
//
//  Lets Open Quickly's session contents search ("/g") also search the transcript
//  of a Claude Code conversation running in a session. Claude Code's full-screen
//  interface redraws in place, so much of a conversation never stays in the
//  scrollback, but Claude Code writes every message to a transcript file:
//
//    ~/.claude/sessions/<pid>.json           {"pid": …, "sessionId": "<id>", "cwd": "…", …}
//    ~/.claude/projects/<slug>/<id>.jsonl    one JSON record per line
//
//  GlobalJobMonitor says which sessions are running Claude Code. The claude
//  process is the one in the session’s process tree that has a sessions file.
//  Controlled by the advanced setting
//  openQuicklySearchesClaudeCodeTranscripts.
//

import Foundation

// Extracts the human-readable text of a Claude Code transcript: what the user
// typed and what Claude replied. Tool calls, tool output, and thinking are
// omitted because they mostly were not shown as conversation text.
struct iTermClaudeCodeTranscriptParser {
    static func messages(inJSONLines data: Data) -> [String] {
        var result = [String]()
        for line in data.split(separator: UInt8(ascii: "\n")) where !line.isEmpty {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = object["type"] as? String,
                  type == "user" || type == "assistant",
                  let message = object["message"] as? [String: Any] else {
                continue
            }
            if let text = message["content"] as? String {
                result.append(text)
            } else if let parts = message["content"] as? [[String: Any]] {
                for part in parts where part["type"] as? String == "text" {
                    if let text = part["text"] as? String {
                        result.append(text)
                    }
                }
            }
        }
        return result
    }
}

// Finds a query in a list of texts the way Find does by default: case
// insensitive unless the query contains an uppercase letter.
struct iTermTextOccurrences {
    var count = 0
    // The text containing the first occurrence and the occurrence's range in it.
    var first: (text: String, range: Range<String.Index>)?

    init(of query: String, in texts: [String]) {
        guard !query.isEmpty else {
            return
        }
        let caseSensitive = query.rangeOfCharacter(from: .uppercaseLetters) != nil
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        for text in texts {
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: query, options: options, range: searchRange) {
                if first == nil {
                    first = (text, range)
                }
                count += 1
                searchRange = range.upperBound..<text.endIndex
            }
        }
    }

    // A single line of context around the first occurrence.
    func snippet(maximumPrefixLength: Int = 20, maximumSuffixLength: Int = 256) -> (text: String, matchRange: NSRange)? {
        guard let first else {
            return nil
        }
        let text = first.text
        let start = text.index(first.range.lowerBound,
                               offsetBy: -maximumPrefixLength,
                               limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(first.range.upperBound,
                             offsetBy: maximumSuffixLength,
                             limitedBy: text.endIndex) ?? text.endIndex
        let flatten = { (s: Substring) in
            s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
        }
        let prefix = (start > text.startIndex ? "…" : "") + flatten(text[start..<first.range.lowerBound])
        let match = flatten(text[first.range])
        let suffix = flatten(text[first.range.upperBound..<end])
        return (prefix + match + suffix,
                NSRange(location: (prefix as NSString).length, length: (match as NSString).length))
    }
}

// A match in a Claude Code transcript. Revealing it just reveals the session,
// since the text may no longer be anywhere on screen.
@objc(iTermClaudeCodeTranscriptSearchResult)
class iTermClaudeCodeTranscriptSearchResult: NSObject, iTermGlobalSearchResultProtocol {
    weak var session: PTYSession?
    var snippet: NSAttributedString

    init(session: PTYSession, snippet: NSAttributedString) {
        self.session = session
        self.snippet = snippet
    }

    func reveal(withState state: NSMutableDictionary, completion: @escaping (NSRect) -> Void) {
        completion(.zero)
    }
}

@objc(iTermClaudeCodeTranscripts)
class iTermClaudeCodeTranscripts: NSObject {
    @objc static let instance = iTermClaudeCodeTranscripts()

    // On the first read of a very long conversation only its most recent part is
    // parsed, to bound memory use and the time until results appear.
    static let maximumInitialReadLength: UInt64 = 64 * 1024 * 1024

    // Allowed difference between a process's start time and the start time its
    // sessions file records.
    private static let startTimeTolerance: TimeInterval = 10

    private let configDirectory: URL

    // Transcripts are append-only. Cache what has been parsed and only parse what
    // was appended since.
    private struct CacheEntry {
        var fileIdentifier: NSObject?
        var parsedLength: UInt64 = 0
        var messages = [String]()
    }
    // Only accessed on `queue`.
    private var cache = [URL: CacheEntry]()
    private let queue = DispatchQueue(label: "com.iterm2.claude-code-transcripts")

    // Identifies the newest search so older ones can stop early.
    private var latestRequest = 0
    private let requestLock = NSLock()

    init(configDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")) {
        self.configDirectory = configDirectory
    }

    // A process that might be Claude Code.
    struct Candidate {
        var pid: pid_t
        var startTime: Date?
    }

    // The processes that might be Claude Code in a session GlobalJobMonitor says is
    // running it. No file I/O, so it is cheap enough for the main thread.
    @MainActor
    func candidates(for session: PTYSession) -> [Candidate] {
        // Process IDs only identify local processes. The processes of a tmux or
        // SSH-integrated session may be on another machine.
        guard GlobalJobMonitor.instance.sessionGUIDs(runningJob: "claude").contains(session.guid),
              !session.isTmuxClient,
              session.conductor == nil,
              session.shell.pid > 0,
              let root = session.processInfoProvider?.processInfo(for: session.shell.pid) else {
            return []
        }
        var candidates = [Candidate]()
        _ = root.enumerateTree { info, _ in
            candidates.append(Candidate(pid: info.processID, startTime: info.startTime))
        }
        return candidates
    }

    // The transcript of the Claude Code process with this pid, if it is one. A
    // sessions file can outlive its process, so if the process started after the
    // file's conversation did, the pid has been reused and the file is ignored.
    func transcriptURL(forProcessID pid: pid_t, startTime: Date? = nil) -> URL? {
        let sessionFile = configDirectory.appendingPathComponent("sessions/\(pid).json")
        guard let data = try? Data(contentsOf: sessionFile),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let startTime,
           let startedAt = object["startedAt"] as? Double,
           startTime.timeIntervalSince1970 > startedAt / 1000 + Self.startTimeTolerance {
            return nil
        }
        guard let sessionID = object["sessionId"] as? String,
              !sessionID.isEmpty,
              !sessionID.contains("/") else {
            return nil
        }
        let projects = configDirectory.appendingPathComponent("projects")
        if let cwd = object["cwd"] as? String {
            let url = projects
                .appendingPathComponent(Self.projectDirectoryName(forWorkingDirectory: cwd))
                .appendingPathComponent("\(sessionID).jsonl")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        // Long paths are shortened differently, and the scheme may change. Look in
        // every project.
        let candidates = (try? FileManager.default.contentsOfDirectory(at: projects,
                                                                       includingPropertiesForKeys: nil)) ?? []
        return candidates.lazy
            .map { $0.appendingPathComponent("\(sessionID).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // Claude Code names a project's directory after its working directory, with
    // every UTF-16 code unit that is not an ASCII letter or digit replaced by a
    // hyphen.
    static func projectDirectoryName(forWorkingDirectory cwd: String) -> String {
        let units = cwd.utf16.map { unit -> UInt16 in
            switch unit {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A:
                return unit
            default:
                return 0x2D
            }
        }
        return String(utf16CodeUnits: units, count: units.count)
    }

    // Finds the transcript of each session's Claude Code process and searches it,
    // off the main thread. `candidates` maps a key (a session GUID) to the
    // session's processes. Calls completion on the main thread with the
    // occurrences for each key that has any. A newer call supersedes this one, in
    // which case completion is not called.
    func search(for query: String,
                candidates: [String: [Candidate]],
                completion: @escaping ([String: iTermTextOccurrences]) -> Void) {
        requestLock.lock()
        latestRequest += 1
        let request = latestRequest
        requestLock.unlock()

        queue.async { [weak self] in
            guard let self else {
                return
            }
            var urls = [String: URL]()
            for (key, processes) in candidates {
                guard self.isLatest(request) else {
                    return
                }
                urls[key] = processes.lazy.compactMap {
                    self.transcriptURL(forProcessID: $0.pid, startTime: $0.startTime)
                }.first
            }
            // Forget transcripts of conversations that are no longer running.
            let current = Set(urls.values)
            self.cache = self.cache.filter { current.contains($0.key) }

            var results = [String: iTermTextOccurrences]()
            for (key, url) in urls {
                guard self.isLatest(request) else {
                    return
                }
                let occurrences = iTermTextOccurrences(of: query, in: self.messages(in: url))
                if occurrences.count > 0 {
                    results[key] = occurrences
                }
            }
            DispatchQueue.main.async { [weak self] in
                if self?.isLatest(request) == true {
                    completion(results)
                }
            }
        }
    }

    private func isLatest(_ request: Int) -> Bool {
        requestLock.lock()
        defer {
            requestLock.unlock()
        }
        return latestRequest == request
    }

    // Must be called on `queue`.
    private func messages(in url: URL) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            cache.removeValue(forKey: url)
            return []
        }
        defer {
            try? handle.close()
        }
        let fileIdentifier = (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier as? NSObject
        var entry = cache[url] ?? CacheEntry()
        guard let end = try? handle.seekToEnd() else {
            return entry.messages
        }
        if !Self.isAppended(entry, handle: handle, end: end, fileIdentifier: fileIdentifier) {
            // Replaced or rewritten rather than appended to. Start over.
            entry = CacheEntry()
        }
        entry.fileIdentifier = fileIdentifier

        var offset = entry.parsedLength
        let startsMidLine = offset == 0 && end > Self.maximumInitialReadLength
        if startsMidLine {
            offset = end - Self.maximumInitialReadLength
        }
        guard end > offset,
              (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd() else {
            cache[url] = entry
            return entry.messages
        }
        var firstLine = data.startIndex
        if startsMidLine {
            guard let newline = data.firstIndex(of: UInt8(ascii: "\n")) else {
                return entry.messages
            }
            firstLine = data.index(after: newline)
        }
        // Only parse complete lines. A partial last line is still being written.
        if let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")), lastNewline >= firstLine {
            entry.messages += iTermClaudeCodeTranscriptParser.messages(inJSONLines: Data(data[firstLine...lastNewline]))
            entry.parsedLength = offset + UInt64(data.distance(from: data.startIndex, to: lastNewline) + 1)
        }
        cache[url] = entry
        return entry.messages
    }

    // Whether the file is the one that was cached, with only lines added since.
    private static func isAppended(_ entry: CacheEntry,
                                   handle: FileHandle,
                                   end: UInt64,
                                   fileIdentifier: NSObject?) -> Bool {
        if entry.parsedLength == 0 {
            return true
        }
        if let fileIdentifier, let cached = entry.fileIdentifier, !fileIdentifier.isEqual(cached) {
            return false
        }
        guard end >= entry.parsedLength,
              (try? handle.seek(toOffset: entry.parsedLength - 1)) != nil,
              let byte = try? handle.read(upToCount: 1) else {
            return false
        }
        return byte == Data([UInt8(ascii: "\n")])
    }
}
