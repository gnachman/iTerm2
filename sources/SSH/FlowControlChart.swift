//
//  FlowControlChart.swift
//  iTerm2SharedARC
//
//  A line chart of the last minute for the flow control monitor: time runs from a minute ago at
//  the left to now at the right, values from zero up to a round number above the largest. A
//  missing value breaks its line.
//

import AppKit

struct FlowControlChart {
    struct Series {
        var label: String
        var color: NSColor
        var points: [FlowControlHistory.Point]
        var dashed = false
        /// Drawn as the range between least and most, instead of `points`.
        var band: [FlowControlHistory.Band]?
    }

    enum Unit {
        case bytes
        case bytesPerSecond
        case seconds

        func format(_ value: Double) -> String {
            // Localization unneeded: technical output in a debugging window.
            switch self {
            case .bytes:
                return Self.bytes(value)
            case .bytesPerSecond:
                return Self.bytes(value) + "/s"
            case .seconds:
                return value < 1 ? String(format: "%.1f ms", value * 1000) : String(format: "%.2f s", value)
            }
        }

        /// A round value at least `value`, in this unit's steps: KB and MB for bytes.
        func ceiling(_ value: Double) -> Double {
            switch self {
            case .bytes, .bytesPerSecond:
                var scale = 1.0
                while value / scale >= 1024 {
                    scale *= 1024
                }
                return FlowControlChart.roundUp(value / scale) * scale
            case .seconds:
                return FlowControlChart.roundUp(value)
            }
        }

        private static func bytes(_ value: Double) -> String {
            // Localization unneeded: technical output in a debugging window.
            if value >= 1024 * 1024 {
                return String(format: "%.2f MB", value / (1024 * 1024))
            }
            if value >= 1024 {
                return String(format: "%.1f KB", value / 1024)
            }
            return String(format: "%.0f B", value)
        }
    }

    static let height: CGFloat = 130

    var title: String
    var unit: Unit
    var series: [Series]
    /// The right edge's time; the left edge is `duration` before it.
    var now: TimeInterval
    var duration: TimeInterval = 60

    func draw(in rect: NSRect) {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let label: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let axisWidth: CGFloat = 64

        // The title, then each series' latest value, across the top.
        var legendX = rect.minX
        let top = rect.minY
        let titleText = NSAttributedString(string: title,
                                           attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize),
                                                        .foregroundColor: NSColor.labelColor])
        titleText.draw(at: NSPoint(x: legendX, y: top))
        legendX += max(axisWidth + 4, titleText.size().width + 12)
        for series in series {
            let latest: String
            if let band = series.band {
                latest = band.last.flatMap { last in
                    last.least.flatMap { least in
                        last.most.map { most in least == most ? unit.format(least) : "\(unit.format(least))–\(unit.format(most))" }
                    }
                } ?? "–"
            } else {
                latest = series.points.last?.value.map(unit.format) ?? "–"
            }
            let text = NSAttributedString(string: "\(series.label) \(latest)",
                                          attributes: [.font: font, .foregroundColor: series.color])
            let size = text.size()
            if legendX + size.width > rect.maxX {
                break
            }
            text.draw(at: NSPoint(x: legendX, y: top))
            legendX += size.width + 12
        }

        let plot = NSRect(x: rect.minX + axisWidth,
                          y: top + lineHeight + 4,
                          width: max(1, rect.width - axisWidth),
                          height: max(1, rect.maxY - top - 2 * lineHeight - 8))
        NSColor.controlBackgroundColor.setFill()
        plot.fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(rect: plot.insetBy(dx: 0.5, dy: 0.5)).stroke()

        let values = series.flatMap { series in
            series.points.compactMap(\.value) + (series.band ?? []).flatMap { [$0.least, $0.most].compactMap { $0 } }
        }
        guard !values.isEmpty else {
            // Localization unneeded: technical output in a debugging window.
            let text = NSAttributedString(string: "No data yet", attributes: label)
            let size = text.size()
            text.draw(at: NSPoint(x: plot.midX - size.width / 2, y: plot.midY - size.height / 2))
            return
        }
        let ceiling = unit.ceiling(values.max() ?? 0)
        // Zero is the bottom unless something went below it, which a count that went wrong can.
        let smallest = values.min() ?? 0
        let bottom = smallest < 0 ? -unit.ceiling(-smallest) : 0
        // The view is flipped.
        func y(_ value: Double) -> CGFloat {
            plot.maxY - CGFloat((value - bottom) / (ceiling - bottom)) * plot.height
        }
        func x(_ time: TimeInterval) -> CGFloat {
            plot.minX + CGFloat((time - (now - duration)) / duration) * plot.width
        }

        let gridValues = bottom < 0 ? [bottom, 0, ceiling] : [0, ceiling / 2, ceiling]
        for value in gridValues {
            let gridY = y(value)
            if value != gridValues.first && value != gridValues.last {
                let grid = NSBezierPath()
                grid.move(to: NSPoint(x: plot.minX, y: gridY))
                grid.line(to: NSPoint(x: plot.maxX, y: gridY))
                NSColor.separatorColor.setStroke()
                grid.stroke()
            }
            let text = NSAttributedString(string: unit.format(value), attributes: label)
            let size = text.size()
            text.draw(at: NSPoint(x: plot.minX - size.width - 4,
                                  y: min(max(gridY - size.height / 2, plot.minY), plot.maxY - size.height)))
        }
        // Localization unneeded: technical output in a debugging window.
        for (offset, text) in [(-duration, "−\(Int(duration)) s"), (-duration / 2, "−\(Int(duration / 2)) s"), (0, "now")] {
            let string = NSAttributedString(string: text, attributes: label)
            let size = string.size()
            let center = x(now + offset)
            string.draw(at: NSPoint(x: min(max(center - size.width / 2, plot.minX), plot.maxX - size.width),
                                    y: plot.maxY + 2))
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: plot).addClip()
        for series in series {
            if let band = series.band {
                fillBand(band, color: series.color, x: x, y: y)
                continue
            }
            let path = NSBezierPath()
            path.lineWidth = 1.5
            if series.dashed {
                path.setLineDash([4, 3], count: 2, phase: 0)
            }
            var drawing = false
            for point in series.points {
                guard let value = point.value else {
                    drawing = false
                    continue
                }
                let p = NSPoint(x: x(point.time), y: y(value))
                if drawing {
                    path.line(to: p)
                } else {
                    path.move(to: p)
                    drawing = true
                }
            }
            series.color.setStroke()
            path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Fills between least and most wherever both are known.
    private func fillBand(_ band: [FlowControlHistory.Band],
                          color: NSColor,
                          x: (TimeInterval) -> CGFloat,
                          y: (Double) -> CGFloat) {
        var run = [FlowControlHistory.Band]()
        func flush() {
            guard !run.isEmpty else {
                return
            }
            let path = NSBezierPath()
            for (i, b) in run.enumerated() {
                let p = NSPoint(x: x(b.time), y: y(b.most!))
                if i == 0 {
                    path.move(to: p)
                } else {
                    path.line(to: p)
                }
            }
            for b in run.reversed() {
                path.line(to: NSPoint(x: x(b.time), y: y(b.least!)))
            }
            path.close()
            color.withAlphaComponent(0.35).setFill()
            path.fill()
            color.setStroke()
            path.lineWidth = 0.75
            path.stroke()
            run.removeAll()
        }
        for b in band {
            if b.least != nil && b.most != nil {
                run.append(b)
            } else {
                flush()
            }
        }
        flush()
    }

    /// 1, 2 or 5 times a power of ten, at least `value`.
    static func roundUp(_ value: Double) -> Double {
        guard value > 0, value.isFinite else {
            return 1
        }
        let power = pow(10, Foundation.floor(log10(value)))
        for step in [1.0, 2.0, 5.0, 10.0] where step * power >= value {
            return step * power
        }
        return 10 * power
    }
}
