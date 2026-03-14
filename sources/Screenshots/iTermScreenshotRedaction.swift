//
//  iTermScreenshotRedaction.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/9/26.
//

import AppKit

/// The type of annotation (redaction hides content, highlight draws attention to it)
@objc(iTermScreenshotAnnotationType)
enum iTermScreenshotAnnotationType: Int {
    case redaction = 0
    case highlight = 1
}

/// Represents a single annotation region (redaction or highlight) stored as sub-selections for persistence.
@objc(iTermScreenshotAnnotation)
class iTermScreenshotAnnotation: NSObject {
    let id = UUID()

    /// The type of annotation
    @objc let annotationType: iTermScreenshotAnnotationType

    /// The sub-selections that define this annotation region.
    /// Stored as absolute coordinates so they remain valid across scrollback changes.
    @objc let subSelections: [iTermSubSelection]

    /// Label for display in the list (e.g., truncated text or line numbers)
    @objc var label: String

    @objc init(annotationType: iTermScreenshotAnnotationType, subSelections: [iTermSubSelection], label: String) {
        self.annotationType = annotationType
        self.subSelections = subSelections
        self.label = label
        super.init()
    }

    /// Creates an annotation from the current selection in a text view
    @objc static func fromSelection(_ selection: iTermSelection,
                                     annotationType: iTermScreenshotAnnotationType,
                                     label: String) -> iTermScreenshotAnnotation? {
        guard selection.hasSelection else { return nil }
        guard let allSubs = selection.allSubSelections, !allSubs.isEmpty else { return nil }

        var subs: [iTermSubSelection] = []
        for sub in allSubs {
            if let copiedSub = sub.copy() as? iTermSubSelection {
                subs.append(copiedSub)
            }
        }

        guard !subs.isEmpty else { return nil }
        return iTermScreenshotAnnotation(annotationType: annotationType, subSelections: subs, label: label)
    }
}

/// Manages multiple annotations (redactions and highlights) for the screenshot feature.
@objc(iTermScreenshotRedactionManager)
class iTermScreenshotRedactionManager: NSObject {
    @objc private(set) var annotations: [iTermScreenshotAnnotation] = []

    /// Called whenever the annotations list changes
    @objc var onRedactionsChanged: (() -> Void)?

    @objc var count: Int {
        return annotations.count
    }

    /// Accessor for redactions only
    @objc var redactions: [iTermScreenshotAnnotation] {
        return annotations.filter { $0.annotationType == .redaction }
    }

    /// Accessor for highlights only
    @objc var highlights: [iTermScreenshotAnnotation] {
        return annotations.filter { $0.annotationType == .highlight }
    }

    @objc func annotation(at index: Int) -> iTermScreenshotAnnotation? {
        guard index >= 0 && index < annotations.count else { return nil }
        return annotations[index]
    }

    /// Adds a new annotation from the current selection
    @objc func addAnnotation(from selection: iTermSelection,
                              annotationType: iTermScreenshotAnnotationType,
                              label: String) -> iTermScreenshotAnnotation? {
        guard let annotation = iTermScreenshotAnnotation.fromSelection(
            selection,
            annotationType: annotationType,
            label: label
        ) else {
            return nil
        }
        annotations.append(annotation)
        onRedactionsChanged?()
        return annotation
    }

    /// Removes an annotation at the specified index
    @objc func removeAnnotation(at index: Int) {
        guard index >= 0 && index < annotations.count else { return }
        annotations.remove(at: index)
        onRedactionsChanged?()
    }

    /// Removes all annotations
    @objc func clearAll() {
        guard !annotations.isEmpty else { return }
        annotations.removeAll()
        onRedactionsChanged?()
    }

    // MARK: - Rect Computation

    /// Computes rects relative to a rendered image for the given line range.
    /// Used for applying obscuring to the preview image.
    /// Returns rects in image coordinates (origin at bottom-left, like NSImage).
    @objc func imageRects(for textView: PTYTextView,
                          lineRange: NSRange,
                          annotationType: iTermScreenshotAnnotationType) -> [NSValue] {
        guard let context = RectComputationContext(textView: textView, lineRange: lineRange) else {
            return []
        }
        let filteredAnnotations = annotations.filter { $0.annotationType == annotationType }
        var allRects: [NSValue] = []

        for annotation in filteredAnnotations {
            let groups = computeRectsForAnnotation(annotation, context: context, coordinateSystem: .image)
            for group in groups {
                allRects.append(contentsOf: group)
            }
        }

        return allRects
    }

    /// Returns rects grouped by sub-selection for highlight annotations.
    /// Each inner array contains the rects for one sub-selection, which should be outlined together.
    /// Returns rects in image coordinates (origin at bottom-left, like NSImage).
    @objc func groupedHighlightRects(for textView: PTYTextView, lineRange: NSRange) -> [[NSValue]] {
        guard let context = RectComputationContext(textView: textView, lineRange: lineRange) else {
            return []
        }
        var result: [[NSValue]] = []

        for annotation in highlights {
            let groups = computeRectsForAnnotation(annotation, context: context, coordinateSystem: .image)
            result.append(contentsOf: groups)
        }

        return result
    }

    /// Computes window rects for all redactions using the text view.
    /// Returns rects suitable for passing to the screenshot renderer.
    /// The lineRange specifies which lines will be rendered (0-based, relative line numbers).
    @objc func allWindowRects(for textView: PTYTextView, lineRange: NSRange) -> [NSValue] {
        guard let context = RectComputationContext(textView: textView, lineRange: lineRange) else {
            return []
        }
        let rangeRect = NSRect(
            x: 0,
            y: Double(context.firstLineInRange) * context.lineHeight,
            width: textView.bounds.width,
            height: Double(lineRange.length) * context.lineHeight
        )

        var allRects: [NSValue] = []

        for annotation in redactions {
            let groups = computeRectsForAnnotation(annotation, context: context, coordinateSystem: .view)
            for group in groups {
                for rectValue in group {
                    var rect = rectValue.rectValue
                    rect = rect.intersection(rangeRect)
                    if !rect.isEmpty {
                        let windowRect = textView.convert(rect, to: nil)
                        allRects.append(NSValue(rect: windowRect))
                    }
                }
            }
        }

        return allRects
    }

    /// Generates a label from the selection text
    /// Format: "N lines: 'prefix'...'suffix'" where prefix/suffix are from first/last non-empty lines
    @objc static func labelForSelection(_ selection: iTermSelection, textView: PTYTextView) -> String {
        let text = textView.selectedTextWithTrailingWhitespace()

        // Split into lines and find non-empty ones
        let lines = text.components(separatedBy: CharacterSet.newlines)
        let nonEmptyLines = lines.map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
                                 .filter { !$0.isEmpty }

        let lineCount = lines.count

        // Build the label
        let label = lineCount == 1 ? "1 line" : "\(lineCount) lines"

        if nonEmptyLines.isEmpty {
            // No non-empty lines, just show line count
            return label
        } else if nonEmptyLines.count == 1 {
            // Only one non-empty line
            let content = nonEmptyLines[0]
            let truncated = content.count > 20 ? String(content.prefix(17)) + "..." : content
            return "\(label): \u{201C}\(truncated)\u{201D}"
        } else {
            // Multiple non-empty lines - show prefix of first and suffix of last
            let first = nonEmptyLines[0]
            let last = nonEmptyLines[nonEmptyLines.count - 1]

            let prefixLen = 10
            let suffixLen = 10

            let prefix = first.count > prefixLen ? String(first.prefix(prefixLen)) : first
            let suffix = last.count > suffixLen ? String(last.suffix(suffixLen)) : last

            return "\(label): \u{201C}\(prefix)\u{201D}...\u{201C}\(suffix)\u{201D}"
        }
    }

    // MARK: - Private Helpers

    private enum CoordinateSystem {
        case image  // Y origin at bottom, relative to line range
        case view   // Y in view coordinates (line * lineHeight)
    }

    private struct RectComputationContext {
        let overflow: Int64
        let charWidth: Double
        let lineHeight: Double
        let width: Int32
        let sideMargins: Double
        let firstLineInRange: Int64
        let lastLineInRange: Int64
        let imageHeight: Double

        init?(textView: PTYTextView, lineRange: NSRange) {
            guard let dataSource = textView.dataSource else {
                return nil
            }
            overflow = dataSource.totalScrollbackOverflow()
            charWidth = textView.charWidth
            lineHeight = textView.lineHeight
            width = dataSource.width()
            sideMargins = iTermPreferences.double(forKey: kPreferenceKeySideMargins)
            firstLineInRange = Int64(lineRange.location)
            lastLineInRange = Int64(lineRange.location + lineRange.length - 1)
            imageHeight = Double(lineRange.length) * lineHeight
        }
    }

    /// Computes rects for an annotation, grouped by sub-selection.
    /// Box-originated sub-selections are accumulated and emitted as a single group.
    private func computeRectsForAnnotation(
        _ annotation: iTermScreenshotAnnotation,
        context: RectComputationContext,
        coordinateSystem: CoordinateSystem
    ) -> [[NSValue]] {
        var result: [[NSValue]] = []
        var boxSubsAccumulator: [iTermSubSelection] = []

        func flushBoxSubs() {
            guard !boxSubsAccumulator.isEmpty else { return }

            if let rect = computeRectForBoxGroup(boxSubsAccumulator, context: context, coordinateSystem: coordinateSystem) {
                result.append([NSValue(rect: rect)])
            }
            boxSubsAccumulator.removeAll()
        }

        for sub in annotation.subSelections {
            if sub.originatedFromBoxSelection {
                boxSubsAccumulator.append(sub)
                continue
            }

            flushBoxSubs()

            let rects = computeRectsForSubSelection(sub, context: context, coordinateSystem: coordinateSystem)
            if !rects.isEmpty {
                result.append(rects.map { NSValue(rect: $0) })
            }
        }

        flushBoxSubs()
        return result
    }

    /// Computes a single rect from a group of box-originated sub-selections.
    private func computeRectForBoxGroup(
        _ subs: [iTermSubSelection],
        context: RectComputationContext,
        coordinateSystem: CoordinateSystem
    ) -> NSRect? {
        guard !subs.isEmpty else { return nil }

        let boxBounds = subs[0].boxColumnBounds
        let leftColumn = Int(boxBounds.location)
        let rightColumn = Int(boxBounds.location + boxBounds.length)

        var minY: Int64 = Int64.max
        var maxY: Int64 = Int64.min

        for sub in subs {
            let absRange = sub.absRange.coordRange
            let subStartY = Int64(absRange.start.y) - context.overflow
            let subEndY = Int64(absRange.end.y) - context.overflow

            if subEndY < context.firstLineInRange || subStartY > context.lastLineInRange {
                continue
            }

            minY = min(minY, max(subStartY, context.firstLineInRange))
            maxY = max(maxY, min(subEndY, context.lastLineInRange))
        }

        guard minY <= maxY else { return nil }

        let heightInLines = maxY - minY + 1

        let yCoord: Double
        switch coordinateSystem {
        case .image:
            let lineInImage = minY - context.firstLineInRange
            yCoord = context.imageHeight - Double(lineInImage + heightInLines) * context.lineHeight
        case .view:
            yCoord = Double(minY) * context.lineHeight
        }

        return NSRect(
            x: context.sideMargins + Double(leftColumn) * context.charWidth,
            y: yCoord,
            width: Double(rightColumn - leftColumn) * context.charWidth,
            height: Double(heightInLines) * context.lineHeight
        )
    }

    /// Computes rects for a single non-box sub-selection.
    private func computeRectsForSubSelection(
        _ sub: iTermSubSelection,
        context: RectComputationContext,
        coordinateSystem: CoordinateSystem
    ) -> [NSRect] {
        let absRange = sub.absRange.coordRange
        let startY = Int64(absRange.start.y) - context.overflow
        let endY = Int64(absRange.end.y) - context.overflow

        // Skip subselections completely outside the line range
        if endY < context.firstLineInRange || startY > context.lastLineInRange {
            return []
        }

        let clampedStartY = max(startY, context.firstLineInRange)
        let clampedEndY = min(endY, context.lastLineInRange)

        if sub.selectionMode == .kiTermSelectionModeBox {
            let leftColumn = Int(sub.absRange.columnWindow.location)
            let rightColumn = Int(VT100GridRangeMax(sub.absRange.columnWindow))
            let heightInLines = clampedEndY - clampedStartY + 1

            let yCoord: Double
            switch coordinateSystem {
            case .image:
                let lineInImage = clampedStartY - context.firstLineInRange
                yCoord = context.imageHeight - Double(lineInImage + heightInLines) * context.lineHeight
            case .view:
                yCoord = Double(clampedStartY) * context.lineHeight
            }

            let rect = NSRect(
                x: context.sideMargins + Double(leftColumn) * context.charWidth,
                y: yCoord,
                width: Double(rightColumn - leftColumn) * context.charWidth,
                height: Double(heightInLines) * context.lineHeight
            )
            return [rect]
        } else {
            // Character/line selection
            var rects: [NSRect] = []
            guard clampedStartY <= clampedEndY else { return rects }

            for line in clampedStartY...clampedEndY {
                let startX: Int32
                let endX: Int32

                if line == startY {
                    startX = absRange.start.x
                } else {
                    startX = 0
                }

                if line == endY {
                    endX = absRange.end.x
                } else {
                    endX = context.width
                }

                if startX >= endX && line == endY {
                    continue
                }

                let yCoord: Double
                switch coordinateSystem {
                case .image:
                    let lineInImage = line - context.firstLineInRange
                    yCoord = context.imageHeight - Double(lineInImage + 1) * context.lineHeight
                case .view:
                    yCoord = Double(line) * context.lineHeight
                }

                let rect = NSRect(
                    x: context.sideMargins + Double(startX) * context.charWidth,
                    y: yCoord,
                    width: Double(endX - startX) * context.charWidth,
                    height: context.lineHeight
                )
                rects.append(rect)
            }

            return rects
        }
    }
}
