//
//  ComposerFileCompletionEscapingTests.swift
//  iTerm2
//
//  With AI command suggestions on, the composer's early result (built from
//  already shell-escaped filenames) is handed back at the top of the completion
//  list next to the raw file completions. It must not be escaped a second time,
//  or the popup row for “my file.txt” reads “my\\\ file.txt”.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class ComposerFileCompletionEscapingTests: XCTestCase {
    private var controller: NSViewController!
    private var textView: ComposerTextView!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // The ObjC class isn't visible to Swift, so look it up by name.
        let theClass = try XCTUnwrap(NSClassFromString("iTermStatusBarLargeComposerViewController") as? NSViewController.Type)
        controller = theClass.init(nibName: "iTermStatusBarLargeComposerViewController",
                                   bundle: Bundle(for: ComposerTextView.self))
        _ = controller.view
        textView = try XCTUnwrap(controller.value(forKey: "textView") as? ComposerTextView,
                                 "Precondition: nib loaded the composer text view")
    }

    override func tearDown() {
        controller = nil
        textView = nil
        super.tearDown()
    }

    // Calls the private -setEarlyResult:history:prefix:, which PTYSession reaches
    // through iTermSuggestionRequest.earlyResult.
    private func earlyResult(files: [CompletionItem],
                             history: [CompletionItem],
                             prefix: String) -> CompletionItem? {
        typealias Fn = @convention(c) (AnyObject, Selector, NSArray, NSArray, NSString) -> CompletionItem?
        let sel = NSSelectorFromString("setEarlyResult:history:prefix:")
        XCTAssertTrue(controller.responds(to: sel))
        let fn = unsafeBitCast(controller.method(for: sel), to: Fn.self)
        return fn(controller, sel, files as NSArray, history as NSArray, prefix as NSString)
    }

    // Calls the private -didFindCompletions:historySuggestions:forGeneration:escape:suggestionOnly:prefix:,
    // which is where the completion list from PTYSession.suggestWithAI ends up.
    private func didFindCompletions(_ completions: [CompletionItem], prefix: String) {
        typealias Fn = @convention(c) (AnyObject, Selector, NSArray, NSArray, Int, ObjCBool, ObjCBool, NSString) -> Void
        let sel = NSSelectorFromString("didFindCompletions:historySuggestions:forGeneration:escape:suggestionOnly:prefix:")
        XCTAssertTrue(controller.responds(to: sel))
        let fn = unsafeBitCast(controller.method(for: sel), to: Fn.self)
        // A fresh controller's completion generation is 0.
        fn(controller, sel, completions as NSArray, [] as NSArray, 0, true, false, prefix as NSString)
    }

    private func popupValues() -> [String] {
        let child = Mirror(reflecting: textView!).children.first { $0.label == "_completions" }
        let items = child?.value as? [CompletionItem] ?? []
        return items.map(\.value)
    }

    // Mirrors PTYSession.suggestWithAI: the early result goes first, followed by
    // the raw file completions (the AI rows are irrelevant here).
    private func runAIFlow(files: [CompletionItem], prefix: String) -> [String] {
        let first = earlyResult(files: files, history: [], prefix: prefix)
        let list = (first.map { [$0] } ?? []) + files.filter { $0.value != first?.value }
        didFindCompletions(list, prefix: prefix)
        return popupValues()
    }

    func testEarlyResultForNameWithSpaceIsEscapedOnce() {
        let file = CompletionItem(value: " file.txt", detail: "my file.txt", kind: .file)
        let values = runAIFlow(files: [file], prefix: "show my")
        XCTAssertEqual(values, ["\\ file.txt"])
    }

    func testEarlyResultForNameWithApostropheIsEscapedOnce() {
        let file = CompletionItem(value: "'s.txt", detail: "it's.txt", kind: .file)
        let values = runAIFlow(files: [file], prefix: "show it")
        XCTAssertEqual(values, ["\\'s.txt"])
    }

    func testEarlyResultFromHistoryIsNotEscaped() {
        let history = CompletionItem(value: " a b", detail: "echo a b", kind: .history)
        let first = earlyResult(files: [], history: [history], prefix: "echo")
        XCTAssertEqual(first?.value, " a b")
        didFindCompletions([first].compactMap { $0 }, prefix: "echo")
        XCTAssertEqual(popupValues(), [" a b"])
    }

    // T-85: with AI off, explicitly requested completions are raw file names. The ghost text
    // must be the escaped name, like the popup's row.
    func testGhostTextForRawFileCompletionIsEscaped() {
        let file = CompletionItem(value: " file.txt", detail: "my file.txt", kind: .file)
        didFindCompletions([file], prefix: "show my")
        XCTAssertEqual(popupValues(), ["\\ file.txt"])
        XCTAssertEqual(textView.suggestion, "\\ file.txt")
    }

    func testRawFileCompletionsAreStillEscaped() {
        let items = CompletionItem.shellEscapingFilenameCompletions([
            CompletionItem(value: "my file.txt", detail: nil, kind: .file),
            CompletionItem(value: "ls my\\ file.txt", detail: nil, kind: .aiSuggestion),
        ])
        XCTAssertEqual(items.map(\.value), ["my\\ file.txt", "ls my\\ file.txt"])
    }
}
