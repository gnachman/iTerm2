//
//  ChatSearchResultsViewController.swift
//  iTerm2
//
//  Created by George Nachman on 2/18/25.
//

struct ChatSearchResult {
    var chatID: String
    var message: Message
}

protocol ChatSearchResultsDataSource: AnyObject {
    func chatSearchResultsIterator(query: String) -> AnySequence<ChatSearchResult>
}

protocol ChatSearchResultsViewControllerDelegate: AnyObject {
    func chatSearchResultsDidSelect(_ result: ChatSearchResult)
}

class ChatSearchResultsViewController: NSViewController {
    weak var dataSource: ChatSearchResultsDataSource?
    weak var delegate: ChatSearchResultsViewControllerDelegate?
    private struct ChatSearchSnippetResult {
        var result: ChatSearchResult
        var snippet: String
    }
    private var searchResults = [ChatSearchSnippetResult]()

    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var timer: Timer?
    private var iterator: AnySequence<ChatSearchResult>.Iterator?

    var query = "" {
        didSet {
            if query == oldValue {
                return
            }
            searchResults = []
            tableView.reloadData()
            timer?.invalidate()
            if query.isEmpty {
                iterator = nil
                timer = nil
            } else {
                iterator = dataSource?.chatSearchResultsIterator(query: query).makeIterator()
                timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true, block: { [weak self] _ in
                    self?.iterate()
                })
            }
        }
    }

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
    }

    override func loadView() {
        let root = NSView()
        self.view = root

        // Set up scroll view and table view.
        scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        tableView = NSTableView(frame: .zero)
        // One column for our custom cell.
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MainColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 40
        tableView.backgroundColor = .clear

        scrollView.documentView = tableView

        root.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func iterate() {
        guard let iterator else {
            return
        }
        let maxDuration = 0.01
        let start = NSDate.it_timeSinceBoot()
        repeat {
            guard let result = iterator.next() else {
                timer?.invalidate()
                timer = nil
                break
            }
            add(searchResult: result)
        } while NSDate.it_timeSinceBoot() - start < maxDuration
    }

    // Append the new result and update the table view.
    private func add(searchResult: ChatSearchResult) {
        guard searchResult.isValid(forQuery: query) else {
            return
        }
        guard let snippet = searchResult.snippet(query: query), !snippet.isEmpty else {
            return
        }
        searchResults.append(ChatSearchSnippetResult(result: searchResult, snippet: snippet))
        let rowIndex = searchResults.count - 1
        tableView.beginUpdates()
        tableView.insertRows(at: IndexSet(integer: rowIndex), withAnimation: .effectFade)
        tableView.endUpdates()
    }
}

// MARK: - NSTableViewDataSource
extension ChatSearchResultsViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return searchResults.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("ChatSearchResultCell")
        var cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ChatSearchResultCell
        if cell == nil {
            cell = ChatSearchResultCell(frame: .zero)
            cell?.identifier = identifier
        }
        configure(cell: cell!, row: row)
        return cell
    }

    private func configure(cell: ChatSearchResultCell, row: Int) {
        cell.configure(with: messageRendition(snippet: searchResults[row].snippet,
                                              fromUser: searchResults[row].result.message.author == .user),
                       maxBubbleWidth: tableView.tableColumns[0].width - 8)
        cell.textSelectable = false
    }
}

// MARK: - NSTableViewDelegate
extension ChatSearchResultsViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        // I simply cannot get cell reuse to work. Fuck autolayout.
        let measuringCell = ChatSearchResultCell()
        configure(cell: measuringCell, row: row)
        // Set the width to the table's width for proper auto layout measurement.
        measuringCell.frame = NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 0)
        measuringCell.layoutSubtreeIfNeeded()
        let height = measuringCell.fittingSize.height
        it_assert(height >= 0)
        return height
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0 && selectedRow < searchResults.count else { return }
        let result = searchResults[selectedRow]
        delegate?.chatSearchResultsDidSelect(result.result)
        tableView.selectRowIndexes(IndexSet(), byExtendingSelection: false)
    }

    func messageRendition(snippet: String, fromUser: Bool) -> MessageRendition {
        let attributedString = AttributedStringForGPTMarkdown(snippet,
                                                              linkColor: fromUser ? .white : .linkColor,
                                                              textColor: fromUser ? .white : .textColor) {}
        return MessageRendition(
            isUser: fromUser,
            messageUniqueID: UUID(),
            flavor: .regular(.init(attributedString: attributedString,
                                   buttons: [],
                                   enableButtons: false)),
            timestamp: "",
            isEditable: false,
            linkColor: fromUser ? .white : .linkColor)
    }
}

class ChatSearchResultCell: RegularMessageCellView {}

extension Message {
    var indexableString: String? {
        switch content {
        case let .plainText(value), let .append(string: value, _): value
        case let .markdown(value): AttributedStringForGPTMarkdown(value,
                                                                  linkColor: linkColor,
                                                                  textColor: textColor,
                                                                  didCopy: nil).string
        case let .explanationRequest(request): request.subjectMatter + " " + request.question
        case let .explanationResponse(_, _, markdown): markdown
        case let .remoteCommandResponse(result, _, _): result.successValue
        case let .terminalCommand(cmd): cmd.command
        case  .remoteCommandRequest, .selectSessionRequest, .clientLocal, .renameChat,
                .commit, .setPermissions: nil
        }
    }
}
extension ChatSearchResult {
    func isValid(forQuery query: String) -> Bool {
        guard let text = message.indexableString else {
            return false
        }
        let tokens = query.components(separatedBy: .whitespacesAndNewlines)
        return text.validate(forTokens: tokens)
    }

    func snippet(query: String) -> String? {
        guard let text = message.indexableString else {
            return nil
        }
        let tokens = query.components(separatedBy: .whitespacesAndNewlines)
        return text.snippetize(forTokens: tokens,
                               maxLength: 200).markdownHighlight(tokens: tokens)
    }
}

extension String {
    func validate(forTokens tokens: [String]) -> Bool {
        let words = self.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return tokens.allSatisfy { token in
            words.anySatisfies({ $0.lowercased().contains(token)})
        }
    }

    func snippetize(forTokens tokens: [String], maxLength: UInt) -> String {
        // Split text into words.
        let words = self.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        // If the full text fits, make sure all tokens are present and then highlight and return.
        if self.count <= Int(maxLength) {
            return self.markdownHighlight(tokens: tokens)
        }

        // Find indices where a word matches any token (case-insensitive).
        var matchIndices = [Int]()
        for (i, word) in words.enumerated() {
            for token in tokens {
                if word.lowercased().contains(token) {
                    matchIndices.append(i)
                    break
                }
            }
        }

        // For each match, define a context range: two words before and after.
        var ranges = matchIndices.map { index -> (start: Int, end: Int) in
            let start = max(0, index - 2)
            let end = min(words.count - 1, index + 2)
            return (start, end)
        }

        // Merge overlapping or adjacent ranges.
        ranges.sort { $0.start < $1.start }
        var mergedRanges = [(start: Int, end: Int)]()
        for range in ranges {
            if let last = mergedRanges.last, range.start <= last.end + 1 {
                mergedRanges[mergedRanges.count - 1].end = max(last.end, range.end)
            } else {
                mergedRanges.append(range)
            }
        }

        // Greedily add ranges (with ellipses between) until maxLength is reached.
        var snippetPieces = [String]()
        var currentLength = 0  // counts only non-formatting characters.
        for (i, range) in mergedRanges.enumerated() {
            let piece = words[range.start...range.end].joined(separator: " ")
            // If not the first piece, we prepend an ellipsis (counting as 1 char).
            let additional = (i > 0 ? 1 : 0) + piece.count
            if currentLength + additional <= Int(maxLength) {
                if i > 0 {
                    snippetPieces.append("…")
                    currentLength += 1
                }
                snippetPieces.append(piece)
                currentLength += piece.count
            } else {
                break
            }
        }

        let snippet = snippetPieces.joined(separator: " ")
        return snippet.markdownHighlight(tokens: tokens)
    }

    func markdownHighlight(tokens: [String]) -> String {
        var result = lowercased()

        for token in tokens {
            let lowerToken = token.lowercased()
            var ranges: [Range<String.Index>] = []
            var searchRange = result.startIndex..<result.endIndex

            // Collect all matching ranges first
            while let range = result.range(of: lowerToken, options: [.literal], range: searchRange) {
                if let last = ranges.last, last.upperBound >= range.lowerBound {
                    // Merge overlapping or adjacent ranges
                    ranges[ranges.count - 1] = last.lowerBound..<range.upperBound
                } else {
                    ranges.append(range)
                }
                searchRange = range.upperBound..<result.endIndex
            }

            // Replace from the back to maintain valid indices
            for range in ranges.reversed() {
                let original = result[range]
                result.replaceSubrange(range, with: "**\(original)**")
            }
        }

        return result
    }
}
