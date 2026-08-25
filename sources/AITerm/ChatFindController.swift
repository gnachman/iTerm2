//
//  ChatFindController.swift
//  iTerm2
//
//  In-conversation find (Cmd-F) for the AI chat pane. Builds a list of
//  matches by scanning the rendered plain text of each message in the
//  current conversation and supports next/previous navigation.
//
//  Search is performed against the RENDERED text (markdown already
//  stripped, the same NSAttributedString the cells display), not the
//  markdown source. This keeps what's searched aligned with what the user
//  sees and makes match ranges map 1:1 onto the cells' text views so
//  highlighting is exact. See ChatViewController.findSegments(for:).
//

import AppKit

@MainActor
class ChatFindController {
    struct Match: Equatable {
        let messageID: UUID
        let itemIndex: Int
        let segment: Int
        let range: NSRange
    }

    // A location in the conversation (from a click) that Find Next/Previous
    // navigate relative to. Ordered like matches: item, then segment, then
    // character offset.
    struct Position {
        let itemIndex: Int
        let segment: Int
        let location: Int
    }

    // Set by the owner. Returns the ordered rendered-plain-text segments
    // for a message (one per findable text view in the displaying cell).
    var segmentsProvider: ((Message) -> [String])?
    weak var model: ChatViewControllerModel?

    private(set) var matches: [Match] = []
    private(set) var currentIndex: Int?
    private(set) var query: String = ""
    private var mode: iTermFindMode = .smartCaseSensitivity
    // Rendered segments keyed by message uniqueID. Invalidated wholesale
    // when the conversation changes (cheap; only matters while find is up).
    private var segmentCache: [UUID: [String]] = [:]
    // Set when the user clicks in the conversation; the next navigation
    // starts from here (then reverts to stepping through currentIndex).
    private var cursor: Position?

    var numberOfResults: Int { matches.count }
    var hasQuery: Bool { !query.isEmpty }

    var currentMatch: Match? {
        guard let currentIndex, matches.indices.contains(currentIndex) else {
            return nil
        }
        return matches[currentIndex]
    }

    func invalidateCache() {
        segmentCache.removeAll()
    }

    // Move the find cursor (e.g. the user clicked in the conversation). The
    // next Find Next/Previous navigates relative to this position.
    func setCursor(_ position: Position?) {
        cursor = position
    }

    // Re-run the current query after the conversation mutated. Only the
    // messages whose content actually changed (their uniqueIDs) are dropped
    // from the rendered-text cache, so a streamed token re-renders one message
    // rather than the whole conversation. Inserted messages aren't cached yet
    // (rebuild renders them on demand) and removed messages leave inert cache
    // entries, so structural changes pass no IDs.
    func rescan(invalidatingMessageIDs ids: [UUID]) {
        for id in ids {
            segmentCache.removeValue(forKey: id)
        }
        rebuild(preservingCurrent: true)
    }

    func search(_ query: String, mode: iTermFindMode) {
        self.query = query
        self.mode = mode
        cursor = nil
        rebuild(preservingCurrent: false)
    }

    func clear() {
        query = ""
        matches = []
        currentIndex = nil
        cursor = nil
    }

    @discardableResult
    func next() -> Match? {
        guard !matches.isEmpty else {
            currentIndex = nil
            return nil
        }
        if let cursor {
            self.cursor = nil
            // First match at or after the cursor, wrapping to the top.
            currentIndex = matches.firstIndex { !isBefore($0, cursor) } ?? 0
            return currentMatch
        }
        return move(by: 1)
    }

    @discardableResult
    func previous() -> Match? {
        guard !matches.isEmpty else {
            currentIndex = nil
            return nil
        }
        if let cursor {
            self.cursor = nil
            // Last match strictly before the cursor, wrapping to the bottom.
            currentIndex = matches.lastIndex { isBefore($0, cursor) } ?? (matches.count - 1)
            return currentMatch
        }
        return move(by: -1)
    }

    private func isBefore(_ match: Match, _ position: Position) -> Bool {
        if match.itemIndex != position.itemIndex {
            return match.itemIndex < position.itemIndex
        }
        if match.segment != position.segment {
            return match.segment < position.segment
        }
        return match.range.location < position.location
    }

    func matches(forMessageID messageID: UUID) -> [Match] {
        matches.filter { $0.messageID == messageID }
    }

    // MARK: - Private

    private func move(by delta: Int) -> Match? {
        guard !matches.isEmpty else {
            currentIndex = nil
            return nil
        }
        let n = matches.count
        let base = currentIndex ?? (delta > 0 ? -1 : 0)
        currentIndex = ((base + delta) % n + n) % n
        return currentMatch
    }

    private func rebuild(preservingCurrent: Bool) {
        let previous = preservingCurrent ? currentMatch : nil
        var newMatches: [Match] = []
        if !query.isEmpty, let model, let provider = segmentsProvider {
            let items = model.items
            for i in 0..<items.count {
                guard case .message(let updatable) = items[i] else {
                    continue
                }
                let message = updatable.message
                let id = message.uniqueID
                let segments = cachedSegments(for: message, id: id, provider: provider)
                for (segmentIndex, segment) in segments.enumerated() {
                    for range in ranges(of: query, in: segment, mode: mode) {
                        newMatches.append(Match(messageID: id,
                                                itemIndex: i,
                                                segment: segmentIndex,
                                                range: range))
                    }
                }
            }
        }
        matches = newMatches
        if newMatches.isEmpty {
            currentIndex = nil
        } else if let previous,
                  let restored = newMatches.firstIndex(where: {
                      $0.messageID == previous.messageID &&
                      $0.segment == previous.segment &&
                      $0.range == previous.range
                  }) {
            currentIndex = restored
        } else {
            currentIndex = 0
        }
    }

    private func cachedSegments(for message: Message,
                                id: UUID,
                                provider: (Message) -> [String]) -> [String] {
        if let cached = segmentCache[id] {
            return cached
        }
        let segments = provider(message)
        segmentCache[id] = segments
        return segments
    }

    private func ranges(of query: String,
                        in text: String,
                        mode: iTermFindMode) -> [NSRange] {
        guard !query.isEmpty, !text.isEmpty else {
            return []
        }
        let string = text as NSString
        let fullRange = NSRange(location: 0, length: string.length)
        switch mode {
        case .caseSensitiveRegex, .caseInsensitiveRegex:
            var options: NSRegularExpression.Options = []
            if mode == .caseInsensitiveRegex {
                options.insert(.caseInsensitive)
            }
            guard let regex = try? NSRegularExpression(pattern: query, options: options) else {
                return []
            }
            return regex.matches(in: text, range: fullRange)
                .map { $0.range }
                .filter { $0.length > 0 }
        case .smartCaseSensitivity, .caseSensitiveSubstring, .caseInsensitiveSubstring:
            let caseSensitive: Bool
            switch mode {
            case .caseSensitiveSubstring:
                caseSensitive = true
            case .smartCaseSensitivity:
                caseSensitive = query.rangeOfCharacter(from: .uppercaseLetters) != nil
            default:
                caseSensitive = false
            }
            var options: NSString.CompareOptions = [.literal]
            if !caseSensitive {
                options.insert(.caseInsensitive)
            }
            var result: [NSRange] = []
            var searchRange = fullRange
            while searchRange.length > 0 {
                let found = string.range(of: query, options: options, range: searchRange)
                if found.location == NSNotFound {
                    break
                }
                result.append(found)
                let nextLocation = found.location + max(1, found.length)
                if nextLocation >= string.length {
                    break
                }
                searchRange = NSRange(location: nextLocation,
                                      length: string.length - nextLocation)
            }
            return result
        @unknown default:
            return []
        }
    }
}
