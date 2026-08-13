//
//  AutoResizingTextViewTests.swift
//  iTerm2SharedARC
//
//  Regression tests for the announcement-view auto-resize hot path that was
//  responsible for a beachball: a single tab-style preference change fanned out
//  to a synchronous relayout of every session's announcement view, and each
//  relayout re-ran an expensive font-fitting search that allocated a fresh
//  NSLayoutManager stack on every measurement.
//

import XCTest
@testable import iTerm2SharedARC

final class AutoResizingTextViewTests: XCTestCase {
    private func makeView(width: CGFloat = 200, height: CGFloat = 50) -> AutoResizingTextView {
        let view = AutoResizingTextView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        return view
    }

    private func sample(_ string: String, size: CGFloat = 12) -> NSAttributedString {
        return NSAttributedString(string: string,
                                  attributes: [.font: NSFont.systemFont(ofSize: size)])
    }

    // A repeated measurement with identical content and width must be served
    // from the cache rather than re-laying-out text.
    func testSizeThatFitsCachesRepeatedMeasurements() {
        let view = makeView()
        let text = sample("Hello world, this is a reasonably long announcement.")

        let missesBefore = view.sizeThatFitsMeasurementCount
        let first = view.sizeThatFits(text, width: 200)
        let second = view.sizeThatFits(text, width: 200)

        XCTAssertEqual(first, second)
        XCTAssertEqual(view.sizeThatFitsMeasurementCount - missesBefore, 1,
                       "Second measurement of identical content/width should hit the cache")
    }

    // Different width or different content must still compute.
    func testSizeThatFitsRecomputesForDifferentInputs() {
        let view = makeView()
        let text = sample("Hello world, this is a reasonably long announcement.")

        let missesBefore = view.sizeThatFitsMeasurementCount
        _ = view.sizeThatFits(text, width: 200)
        _ = view.sizeThatFits(text, width: 120)
        _ = view.sizeThatFits(sample("Different text entirely."), width: 200)

        XCTAssertEqual(view.sizeThatFitsMeasurementCount - missesBefore, 3)
    }

    // The reused layout stack must produce the same measurement a freshly
    // allocated one would have.
    func testCachedSizeMatchesFreshComputation() {
        let view = makeView()
        let text = sample("The quick brown fox jumps over the lazy dog. " +
                          "The quick brown fox jumps over the lazy dog.")

        let cached = view.sizeThatFits(text, width: 150)

        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(containerSize: CGSize(width: 150, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(textContainer)
        let textStorage = NSTextStorage(attributedString: text)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        let fresh = layoutManager.usedRect(for: textContainer).size

        XCTAssertEqual(cached.width, fresh.width, accuracy: 0.5)
        XCTAssertEqual(cached.height, fresh.height, accuracy: 0.5)
    }

    // Setting the frame to its current size must not trigger a font refit.
    func testSetFrameSizeSkipsRefitWhenSizeUnchanged() {
        let view = makeView(width: 200, height: 50)

        let countBefore = view.adjustFontSizesCount
        view.setFrameSize(NSSize(width: 200, height: 50))
        XCTAssertEqual(view.adjustFontSizesCount, countBefore,
                       "A no-op resize should not re-run the font-fitting search")
    }

    // A real size change must still trigger a refit.
    func testSetFrameSizeRefitsWhenSizeChanges() {
        let view = makeView(width: 200, height: 50)

        let countBefore = view.adjustFontSizesCount
        view.setFrameSize(NSSize(width: 240, height: 50))
        XCTAssertEqual(view.adjustFontSizesCount, countBefore + 1,
                       "Changing the frame size should re-run the font-fitting search")
    }
}
