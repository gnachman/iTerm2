//
//  TabGroupContentTests.swift
//  ModernTests
//
//  A collapsed tab group's chip shows the tabs' rich content lines, combined
//  across its members. Title and subtitle are left out, jobs and statuses
//  become collections, and anything else shows only when every member agrees.
//

import XCTest
@testable import iTerm2SharedARC

final class TabGroupContentTests: XCTestCase {
    private let layout = TabContentLayout.defaultLayout

    // A member's evaluated lines, from the built-in defaults with the given
    // variable values.
    private func member(path: String = "~/p",
                        job: String = "zsh",
                        status: String = "",
                        title: String = "t",
                        statusColor: String = "",
                        jobFormat: String? = nil) -> [EvaluatedTabContentLine] {
        var overrides = [String: Any]()
        if let jobFormat {
            overrides[TabContentSlot.jobID] = ["text": jobFormat]
        }
        let values = ["path": path,
                      "jobName": job,
                      "status": status,
                      "tab.title": title,
                      "statusColor": statusColor,
                      "iterm2.escape_html(string: jobName?)": EscapeHTMLBuiltInFunction.escape(job),
                      "iterm2.escape_html(string: status?)": EscapeHTMLBuiltInFunction.escape(status)]
        return TabContentResolver.resolve(layout: layout, overrides: overrides, profileSubtitleFormat: "sub").map {
            EvaluatedTabContentLine(line: $0) { source in
                // Stand in for evaluation: replace each \(name) with its value.
                var text = source
                for (name, value) in values {
                    text = text.replacingOccurrences(of: "\\(\(name))", with: value)
                }
                return text
            }
        }
    }

    private func combine(_ members: [[EvaluatedTabContentLine]]) -> [String] {
        return TabGroupContent.combine(layout: layout,
                                       members: members,
                                       statusPriority: { $0.lowercased().contains("wait") ? 0 : 1 }).map(\.visibleText)
    }

    private func combinedMarkup(_ members: [[EvaluatedTabContentLine]]) -> [String] {
        return TabGroupContent.combine(layout: layout,
                                       members: members,
                                       statusPriority: { $0.lowercased().contains("wait") ? 0 : 1 }).map(\.text)
    }

    // An escaped job or status is still a job or status, so a chip lists the
    // jobs and counts the statuses of HTML lines.
    func testSegmentsSeeThroughEscapeHTML() {
        let segments = TabContentSegment.split("\\(iterm2.escape_html(string: jobName?)) \\(escape_html(string: session.status)) \\(iterm2.escape_html(string: path))")
        XCTAssertEqual(segments.map(\.kind), [.job, .literal, .status, .literal, .other])
    }

    // The job line is HTML by default, showing the status in its color. A
    // chip counts each status in its own color, so a group shows a mix, and
    // a member with no status adds nothing.
    func testEachStatusInItsOwnColorOnAChip() {
        let lines = TabGroupContent.combine(layout: layout,
                                            members: [member(job: "claude", status: "Working", statusColor: "#00ff00"),
                                                      member(job: "claude", status: "Waiting", statusColor: "#0000ff"),
                                                      member(job: "claude", status: "Working", statusColor: "#00ff00"),
                                                      member(job: "zsh")],
                                            statusPriority: { $0.lowercased().contains("wait") ? 0 : 1 })
        XCTAssertEqual(lines[1].visibleText, "claude, zsh 1 Waiting, 2 Working")
        XCTAssertEqual(lines[1].text,
                       "claude, zsh <font color=\"\"><font color=\"#0000ff\">1 Waiting</font>, <font color=\"#00ff00\">2 Working</font></font>")

        let drawn = lines[1].attributedText(attributes: [.foregroundColor: NSColor.black])
        func color(of text: String) -> NSColor? {
            let location = (drawn.string as NSString).range(of: text).location
            return (drawn.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor)?.usingColorSpace(.sRGB)
        }
        XCTAssertEqual(color(of: "Waiting")?.blueComponent ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(color(of: "Working")?.greenComponent ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(color(of: ", 2")?.greenComponent ?? 1, 0, accuracy: 0.01, "the separator is in the line's color")
        XCTAssertEqual(color(of: ", 2")?.blueComponent ?? 1, 0, accuracy: 0.01, "the separator is in the line's color")
    }

    // A status whose program gave it no color is counted in the line's color.
    func testStatusWithoutAColorOnAChip() {
        let markup = combinedMarkup([member(job: "j", status: "Working", statusColor: "#00ff00"),
                                     member(job: "j", status: "Idle")])
        XCTAssertEqual(markup[1], "j <font color=\"\"><font color=\"#00ff00\">1 Working</font>, 1 Idle</font>")
    }

    // Values are escaped before combining, so markup in a job name stays text.
    func testEscapedJobsStayText() {
        let texts = combine([member(job: "<b>x</b>"), member(job: "y")])
        XCTAssertEqual(texts[1], "<b>x</b>, y ")
    }

    func testSegments() {
        let segments = TabContentSegment.split("a \\(jobName) b \\(session.status)\\(path)")
        XCTAssertEqual(segments.map(\.kind), [.literal, .job, .literal, .status, .other])
        XCTAssertEqual(segments.map(\.source).joined(), "a \\(jobName) b \\(session.status)\\(path)")
    }

    // Anything the parser can't split back into the original exactly stays a
    // single segment, which combines like any other value.
    func testUnsplittableFormatIsOneSegment() {
        let segments = TabContentSegment.split("\\(unterminated")
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].kind, .other)
        XCTAssertEqual(segments[0].source, "\\(unterminated")
    }

    func testTitleAndSubtitleAreLeftOut() {
        let lines = TabGroupContent.combine(layout: layout, members: [member()], statusPriority: { _ in 0 })
        XCTAssertEqual(lines.count, 2, "directory and job only")
    }

    func testIdenticalValuesShow() {
        XCTAssertEqual(combine([member(path: "~/p"), member(path: "~/p")])[0], "~/p")
    }

    func testDifferingValuesAreEmpty() {
        XCTAssertEqual(combine([member(path: "~/a"), member(path: "~/b")])[0], "")
    }

    func testJobsAreACollection() {
        let texts = combine([member(job: "zsh"), member(job: "claude"), member(job: "vimdiff"), member(job: "claude")])
        XCTAssertEqual(texts[1], "claude, vimdiff, zsh ")
    }

    // Statuses are counted, most urgent first, then most common.
    func testStatusesAreCounted() {
        let texts = combine([member(job: "claude", status: "Working"),
                             member(job: "claude", status: "Waiting"),
                             member(job: "claude", status: "Working"),
                             member(job: "claude", status: "")])
        XCTAssertEqual(texts[1], "claude 1 Waiting, 2 Working")
    }

    // When the members' formats differ, there's no telling which parts line
    // up, so the whole line follows the rule for other values.
    func testDifferentFormatsCombineWholeLines() {
        XCTAssertEqual(combine([member(job: "a"), member(job: "b", jobFormat: "\\(jobName)!")])[1], "")
        XCTAssertEqual(combine([member(job: "a", jobFormat: "\\(jobName)\\(status) "),
                                member(job: "a", jobFormat: "\\(jobName) ")])[1], "a ")
    }

    // The number of lines depends only on the layout, so the chip's size
    // doesn't change with its members.
    func testNoMembersGivesEmptyLines() {
        XCTAssertEqual(combine([]), ["", ""])
    }

    func testLayoutWithOnlyTitleAndSubtitleHasNoLines() {
        let layout = TabContentLayout(slots: [TabContentSlot(identifier: TabContentSlot.titleID, size: .regular),
                                              TabContentSlot(identifier: TabContentSlot.subtitleID, size: .small)])
        XCTAssertTrue(TabGroupContent.combine(layout: layout, members: [member()], statusPriority: { _ in 0 }).isEmpty)
    }

    func testStyleComesFromTheFirstMember() {
        var bold = member()
        bold[2].style.bold = true
        let lines = TabGroupContent.combine(layout: layout, members: [bold, member()], statusPriority: { _ in 0 })
        XCTAssertTrue(lines[0].bold)
    }
}
