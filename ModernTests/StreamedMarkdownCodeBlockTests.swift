//
//  StreamedMarkdownCodeBlockTests.swift
//  iTerm2 ModernTests
//
//  A streamed AI chat reply is accumulated chunk by chunk with
//  Message.append and re-rendered from the accumulated text. Servers that
//  stream word by word can leave whitespace after the closing code fence
//  (for example, “```\n ” or “``` ”). CommonMark still treats those as
//  closing fences, so the rendering must match the non-streamed reply.
//

import XCTest
import AppKit
@testable import iTerm2SharedARC

final class StreamedMarkdownCodeBlockTests: XCTestCase {
    private let lineStyleKey = NSAttributedString.Key("swiftyMarkdownLineStyle")

    // Splits the text the way the fake server does: word by word, with a
    // space after every word, including the last one.
    private func wordByWordChunks(_ text: String) -> [String] {
        return text.components(separatedBy: " ").map { $0 + " " }
    }

    private func streamedMessage(_ chunks: [String]) -> Message {
        var message = Message(chatID: "chat",
                              author: .agent,
                              content: .markdown(chunks[0]),
                              sentDate: Date(),
                              uniqueID: UUID())
        for chunk in chunks.dropFirst() {
            message.append(chunk, useMarkdownIfAmbiguous: true)
        }
        return message
    }

    private func render(_ content: Message.Content) -> NSAttributedString {
        return content.attributedStringValue(linkColor: .blue, textColor: .black)
    }

    private func render(_ text: String) -> NSAttributedString {
        return render(Message.Content.markdown(text))
    }

    private struct Run: Equatable, CustomStringConvertible {
        var text: String
        var lineStyle: String?
        var fixedPitch: Bool
        var attachment: Bool
        var description: String {
            "<\(lineStyle ?? "nil") fixed=\(fixedPitch) attachment=\(attachment) \(text.debugDescription)>"
        }
    }

    // A comparable summary of the parts of the rendering that the finding
    // is about: line styles, fonts, and the copy button attachments.
    private func runs(_ attributed: NSAttributedString) -> [Run] {
        var result = [Run]()
        let string = attributed.string as NSString
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            let font = attributes[.font] as? NSFont
            result.append(Run(text: string.substring(with: range),
                              lineStyle: attributes[lineStyleKey] as? String,
                              fixedPitch: font?.isFixedPitch ?? false,
                              attachment: attributes[.attachment] != nil))
        }
        return result
    }

    private func codeBlockText(_ attributed: NSAttributedString) -> String {
        return runs(attributed)
            .filter { $0.lineStyle == "codeblock" && !$0.attachment }
            .map(\.text)
            .joined()
    }

    private func copyButtonCount(_ attributed: NSAttributedString) -> Int {
        return runs(attributed).filter(\.attachment).count
    }

    private func assertStreamedMatchesNonStreamed(_ text: String,
                                                  expectedCode: String,
                                                  expectedCopyButtons: Int = 1,
                                                  file: StaticString = #filePath,
                                                  line: UInt = #line) {
        let nonStreamed = render(text)
        XCTAssertTrue(codeBlockText(nonStreamed).contains(expectedCode),
                      "Non-streamed rendering lacks the code block: \(runs(nonStreamed))",
                      file: file, line: line)
        XCTAssertEqual(copyButtonCount(nonStreamed), expectedCopyButtons, file: file, line: line)

        let streamed = streamedMessage(wordByWordChunks(text))
        guard case .markdown(let accumulated) = streamed.content else {
            XCTFail("Streamed message is not markdown: \(streamed.content)", file: file, line: line)
            return
        }
        XCTAssertEqual(accumulated, text + " ", file: file, line: line)

        let rendered = render(streamed.content)
        XCTAssertTrue(codeBlockText(rendered).contains(expectedCode),
                      "Streamed rendering lacks the code block: \(runs(rendered))",
                      file: file, line: line)
        XCTAssertFalse(rendered.string.contains("```"),
                       "Closing fence rendered as text: \(rendered.string.debugDescription)",
                       file: file, line: line)
        XCTAssertEqual(copyButtonCount(rendered), expectedCopyButtons, file: file, line: line)
        for run in runs(rendered) where run.lineStyle == "codeblock" && !run.attachment {
            XCTAssertTrue(run.fixedPitch, "Code is not monospaced: \(run)", file: file, line: line)
        }
        XCTAssertEqual(runs(rendered), runs(nonStreamed), file: file, line: line)
    }

    func test_finalFencedBlockWithLanguage_trailingNewline() {
        assertStreamedMatchesNonStreamed("Here you go:\n\n```bash\necho QA437CODE\n```\n",
                                         expectedCode: "echo QA437CODE")
    }

    func test_finalPlainFencedBlock_trailingNewline() {
        assertStreamedMatchesNonStreamed("Here you go:\n\n```\necho QA437CODE\n```\n",
                                         expectedCode: "echo QA437CODE")
    }

    func test_finalFencedBlock_noTrailingNewline() {
        assertStreamedMatchesNonStreamed("Here you go:\n\n```bash\necho QA437CODE\n```",
                                         expectedCode: "echo QA437CODE")
    }

    func test_earlierAndFinalFencedBlocks() {
        assertStreamedMatchesNonStreamed(
            "First:\n\n```bash\necho one\n```\n\nSecond:\n\n```bash\necho two\n```\n",
            expectedCode: "echo two",
            expectedCopyButtons: 2)
    }

    func test_closingFenceWithTrailingSpacesMidMessage() {
        let withSpaces = render("Run:\n\n```bash   \necho QA437CODE\n```  \n\nDone.")
        let clean = render("Run:\n\n```bash\necho QA437CODE\n```\n\nDone.")
        XCTAssertFalse(withSpaces.string.contains("```"), withSpaces.string.debugDescription)
        XCTAssertEqual(runs(withSpaces), runs(clean))
    }

    func test_sanitizeMarkdownLines() {
        XCTAssertEqual(sanitizeMarkdownLines("  ```bash  \nx\n``` "), "```bash\nx\n```")
        XCTAssertEqual(sanitizeMarkdownLines("```\t\nx\n```\t"), "```\nx\n```")
        // Not fences.
        XCTAssertEqual(sanitizeMarkdownLines("echo ```  "), "echo ```  ")
        XCTAssertEqual(sanitizeMarkdownLines("```foo bar"), "```foo bar")
        // Whitespace-only lines are blank outside code blocks only.
        XCTAssertEqual(sanitizeMarkdownLines("a\n  \nb"), "a\n\nb")
        XCTAssertEqual(sanitizeMarkdownLines("```\n  \n```\n\t"), "```\n  \n```\n")
        // An opening fence inside a block is code and is left alone.
        XCTAssertEqual(sanitizeMarkdownLines("```\n  ```bash \n```"), "```\n  ```bash \n```")
    }

    func test_whitespaceOnlyLineDoesNotMakeHeading() {
        for blank in [" ", "\t", "\u{00A0}"] {
            let rendered = render("Hello\n\(blank)\nWorld")
            XCTAssertFalse(runs(rendered).contains { $0.lineStyle == "h1" },
                           "\(blank.debugDescription): \(runs(rendered))")
        }
    }

    func test_midStreamOpenBlockWithTrailingSpace() {
        let rendered = render("Here:\n\n```bash\necho hi\n ")
        XCTAssertFalse(runs(rendered).contains { $0.lineStyle == "h1" }, "\(runs(rendered))")
        XCTAssertTrue(codeBlockText(rendered).contains("echo hi"), "\(runs(rendered))")
    }
}
