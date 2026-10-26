//
//  FlowControlMonitorWindowController.swift
//  iTerm2SharedARC
//
//  The flow control monitor's window: for the current session, a section per SSH Integration
//  connection, outermost first, with charts of the last minute and what the controller knows now.
//  Everything here is technical output for debugging, so it is not localized.
//

import AppKit

@MainActor
final class FlowControlMonitorWindowController: NSWindowController, NSWindowDelegate {
    /// The person closed the window, as opposed to its being closed when iTerm2 quits.
    var userDidClose: (() -> Void)?
    private var closingForUser = false
    private let monitorView = FlowControlMonitorView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
    private let scrollView: NSScrollView

    init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 660, height: 820),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow],
                            backing: .buffered,
                            defer: true)
        // Localization unneeded: technical output in a debugging window.
        panel.title = "SSH Integration Flow Control"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 420, height: 300)
        panel.center()

        scrollView = NSScrollView(frame: panel.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .windowBackgroundColor
        monitorView.autoresizingMask = [.width]
        scrollView.documentView = monitorView
        panel.contentView!.addSubview(scrollView)

        super.init(window: panel)
        panel.delegate = self
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    func update(session: PTYSession?,
                connections: [FlowControlMonitor.Connection],
                received: [FlowControlHistory.Point],
                now: TimeInterval) {
        monitorView.model = FlowControlMonitorView.Model(sessionName: session?.name,
                                                         hasSession: session != nil,
                                                         connections: connections,
                                                         received: received,
                                                         now: now)
        let width = scrollView.contentSize.width
        monitorView.setFrameSize(NSSize(width: width,
                                        height: max(scrollView.contentSize.height,
                                                    monitorView.requiredHeight(width: width))))
        monitorView.needsDisplay = true
    }

    /// Shell > Close (Cmd-W) is wired to closeCurrentSession: rather than performClose:. The
    /// panel never becomes the main window, so without this the action went on to the terminal
    /// window behind it and closed a session there.
    @objc(closeCurrentSession:)
    func closeCurrentSession(_ sender: Any?) {
        window?.performClose(sender)
    }

    /// Sent only when the person closes the window (its close button or Close), not when it is
    /// closed in code, as it is when iTerm2 quits.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closingForUser = true
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard closingForUser else {
            return
        }
        closingForUser = false
        userDidClose?()
    }
}

final class FlowControlMonitorView: NSView {
    struct Model {
        var sessionName: String?
        var hasSession: Bool
        var connections: [FlowControlMonitor.Connection]
        /// The session's bytes received, sampled as a running total.
        var received: [FlowControlHistory.Point] = []
        var now: TimeInterval
    }

    var model: Model?

    private let margin: CGFloat = 16
    private let gap: CGFloat = 10
    private static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    /// The tables line up their columns with spaces.
    private static let smallFont = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        _ = layOut(width: bounds.width, drawing: true)
    }

    func requiredHeight(width: CGFloat) -> CGFloat {
        layOut(width: width, drawing: false)
    }

    /// Lays out the content for `width`, drawing it if `drawing`, and returns its height.
    private func layOut(width: CGFloat, drawing: Bool) -> CGFloat {
        // Localization unneeded: technical output in a debugging window.
        guard let model else {
            return 0
        }
        let contentWidth = max(1, width - 2 * margin)
        var y = margin
        func text(_ string: String, font: NSFont, color: NSColor = .labelColor) {
            let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
            let rect = attributed.boundingRect(with: NSSize(width: contentWidth, height: .greatestFiniteMagnitude),
                                               options: [.usesLineFragmentOrigin])
            if drawing {
                attributed.draw(with: NSRect(x: margin, y: y, width: contentWidth, height: ceil(rect.height)),
                                options: [.usesLineFragmentOrigin])
            }
            y += ceil(rect.height)
        }

        if !model.hasSession {
            text("No current session.", font: Self.font, color: .secondaryLabelColor)
            return y + margin
        }
        text("Session: \(model.sessionName ?? "")", font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize))
        if model.connections.isEmpty {
            y += 4
            text("This session has no SSH Integration connection.", font: Self.font, color: .secondaryLabelColor)
            return y + margin
        }
        // Everything the session reads, from every connection, with flow control on or off.
        y += gap
        if drawing {
            FlowControlChart(title: "Received", unit: .bytesPerSecond, series: [
                FlowControlChart.Series(label: "By the session", color: .systemBlue,
                                        points: FlowControlHistory.rate(ofTotals: model.received, over: 1)),
            ], now: model.now).draw(in: NSRect(x: margin, y: y, width: contentWidth, height: FlowControlChart.height))
        }
        y += FlowControlChart.height
        for connection in model.connections {
            y += gap * 2
            if drawing {
                NSColor.separatorColor.setFill()
                NSRect(x: margin, y: y - gap, width: contentWidth, height: 1).fill()
            }
            text("Depth \(connection.depth): \(connection.name)", font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize))
            let latest = connection.history.samples.last?.snapshot
            if let reason = connection.reasonOff {
                text(reason, font: Self.font, color: .secondaryLabelColor)
            } else if let latest {
                text(Self.summary(connection, latest), font: Self.font, color: .secondaryLabelColor)
            }
            guard connection.history.samples.contains(where: { $0.snapshot != nil }) else {
                // Without flow control, how long commands take to be answered still shows how
                // slow the path is.
                if !connection.roundTrips.isEmpty {
                    y += gap
                    if drawing {
                        FlowControlChart(title: "Round trips", unit: .seconds,
                                         series: [Self.roundTripSeries(connection)], now: model.now)
                            .draw(in: NSRect(x: margin, y: y, width: contentWidth, height: FlowControlChart.height))
                    }
                    y += FlowControlChart.height
                }
                continue
            }
            for chart in Self.charts(connection, now: model.now) {
                y += gap
                if drawing {
                    chart.draw(in: NSRect(x: margin, y: y, width: contentWidth, height: FlowControlChart.height))
                }
                y += FlowControlChart.height
            }
            if let latest {
                y += gap
                text(Self.statistics(latest), font: Self.smallFont)
                y += gap
                text(Self.eventList(latest, now: model.now), font: Self.smallFont)
                y += gap
                text(Self.bucketTable(latest), font: Self.smallFont)
                y += gap
                text(Self.flowTable(latest), font: Self.smallFont)
            }
        }
        return y + margin
    }

    private static func summary(_ connection: FlowControlMonitor.Connection,
                                _ snapshot: FramerFlowController.Snapshot) -> String {
        // Localization unneeded: technical output in a debugging window.
        let state: String
        if snapshot.quarantined {
            state = "Quarantined until a reset drain completes"
        } else {
            switch snapshot.drain {
            case .draining:
                state = "Draining"
            case .pinging:
                state = "Timing the empty path"
            case .idle:
                state = snapshot.slowStart ? "Slow start" : "Congestion avoidance"
            }
        }
        let clock = connection.clockName.map { ", \($0) clock" } ?? ""
        let measured: String
        switch snapshot.measuresToCarrier {
        case .some(true):
            measured = "; delay measured to the carrying frame"
        case .some(false):
            measured = "; delay measured on arrival"
        case .none:
            measured = ""
        }
        return "Flow control version \(connection.flowVersion)\(clock). \(state)\(measured)."
    }

    private static func roundTripSeries(_ connection: FlowControlMonitor.Connection) -> FlowControlChart.Series {
        // Localization unneeded: technical output in a debugging window.
        FlowControlChart.Series(label: "Round trips", color: .systemTeal,
                                points: connection.roundTrips.map {
                                    FlowControlHistory.Point(time: $0.time, value: $0.seconds)
                                })
    }

    private static func charts(_ connection: FlowControlMonitor.Connection, now: TimeInterval) -> [FlowControlChart] {
        // Localization unneeded: technical output in a debugging window.
        let history = connection.history
        var credit = [
            FlowControlChart.Series(label: "W", color: .systemBlue, points: history.values { $0.window }),
            FlowControlChart.Series(label: "Outstanding", color: .systemOrange,
                                    points: history.values { Double($0.outstanding) }),
            FlowControlChart.Series(label: "Not arrived", color: .systemBrown,
                                    points: history.values { Double($0.granted - $0.arrived) }),
            FlowControlChart.Series(label: "Floor", color: .systemGray,
                                    points: history.values { $0.floor }, dashed: true),
        ]
        if history.samples.contains(where: { $0.snapshot?.carrierWindow != nil }) {
            credit.append(FlowControlChart.Series(label: "Carrier W", color: .systemPurple,
                                                  points: history.values { $0.carrierWindow }))
        }
        var delay = [
            // Over each half second, since it jumps from sample to sample.
            FlowControlChart.Series(label: "Queueing", color: .systemRed, points: [],
                                    band: FlowControlHistory.extremes(of: history.values { $0.queueingDelay },
                                                                      over: 0.5)),
            FlowControlChart.Series(label: "RTT min", color: .systemGreen,
                                    points: history.values { $0.rttMin }),
            FlowControlChart.Series(label: "Target", color: .systemGray,
                                    points: history.values { $0.target }, dashed: true),
        ]
        // Averaged over a second, for the eye; the controller uses it as is.
        delay.append(FlowControlChart.Series(label: "Link's cost per KB", color: .systemBrown,
                                             points: FlowControlHistory.mean(of: history.values {
                                                 $0.delayBaseline.costPerKilobyte
                                             }, over: 1)))
        delay.append(roundTripSeries(connection))
        if history.samples.contains(where: { ($0.snapshot?.carrierDelay ?? 0) > 0 }) {
            delay.append(FlowControlChart.Series(label: "Beyond", color: .systemPurple,
                                                 points: history.values { $0.carrierDelay }))
        }
        let rate = [
            FlowControlChart.Series(label: "Consumed", color: .systemBlue,
                                    points: history.rate(over: 1) { $0.consumed }),
            FlowControlChart.Series(label: "Arrived", color: .systemTeal,
                                    points: history.rate(over: 1) { $0.arrived }),
            FlowControlChart.Series(label: "Delivery estimate", color: .systemGray,
                                    points: history.values { $0.deliveryRate }, dashed: true),
        ]
        return [
            FlowControlChart(title: "Credit", unit: .bytes, series: credit, now: now),
            FlowControlChart(title: "Delay", unit: .seconds, series: delay, now: now),
            FlowControlChart(title: "Throughput", unit: .bytesPerSecond, series: rate, now: now),
        ]
    }

    private static func statistics(_ s: FramerFlowController.Snapshot) -> String {
        // Localization unneeded: technical output in a debugging window.
        let bytes = FlowControlChart.Unit.bytes.format
        let seconds = FlowControlChart.Unit.seconds.format
        let rate = FlowControlChart.Unit.bytesPerSecond.format
        let rows: [(String, String)] = [
            ("Window (W)", bytes(s.window)),
            ("Outstanding (granted, not consumed)", bytes(Double(s.outstanding))),
            ("Not arrived (unspent, or on the way)", bytes(Double(s.granted - s.arrived))),
            ("Backlog (arrived, not consumed)", bytes(Double(s.arrived - s.consumed))),
            ("Floor", bytes(s.floor)),
            ("Carrier window", s.carrierWindow.map(bytes) ?? "–"),
            ("Granted in all", bytes(Double(s.granted))),
            ("Arrived in all", bytes(Double(s.arrived))),
            ("Consumed in all", bytes(Double(s.consumed))),
            ("RTT min", seconds(s.rttMin)),
            ("Target", seconds(s.target)),
            ("Queueing delay", s.queueingDelay.map(seconds) ?? "–"),
            // One-way delays carry the clocks' offset; only differences between them mean anything.
            ("Last frame", s.lastReading.map {
                "\(bytes(Double($0.bytes)))\($0.exempt ? " (echo allowance)" : "")"
            } ?? "–"),
            ("  correction for its size", s.lastReading.map {
                seconds(s.delayBaseline.correction(forBytes: $0.bytes))
            } ?? "–"),
            ("  delay over the baseline", s.lastReading.flatMap { reading in
                s.delayBaseline.base.map {
                    seconds(reading.oneWayDelay - s.delayBaseline.correction(forBytes: reading.bytes) - $0)
                }
            } ?? "–"),
            ("Link's cost per KB", !s.correctsForSize ? "not corrected (measured to the carrying frame)"
                : s.delayBaseline.edge.isEmpty ? "not corrected (sizes vary too little)"
                : seconds(s.delayBaseline.costPerKilobyte)),
            ("Feedback delay", seconds(s.feedbackDelay)),
            ("Delay beyond this hop", seconds(s.carrierDelay)),
            ("Delivery rate", s.deliveryRate.map(rate) ?? "–"),
            ("Baseline window (L)", seconds(s.baselineWindow)),
            ("Grants", "\(s.statistics.grants)"),
            ("Heartbeats", "\(s.statistics.heartbeats)"),
            ("Drains", "\(s.statistics.drains) (\(s.statistics.resetDrains) reset, \(s.statistics.creditRecalls) to take back credit, \(s.statistics.abandonedDrains) abandoned)"),
            ("Window decreases", "\(s.statistics.decreases)"),
            ("Share caps", "\(s.statistics.capDecreases)"),
            ("Silences", "\(s.statistics.silences)"),
            ("Safety valves", "\(s.statistics.valves)"),
            ("Round trip samples", "\(s.statistics.roundTripSamples)"),
        ]
        let labelWidth = rows.map(\.0.count).max() ?? 0
        return rows.map { $0.0.padding(toLength: labelWidth + 2, withPad: " ", startingAt: 0) + $0.1 }
            .joined(separator: "\n")
    }

    /// What the controller did lately that changes what it does next, newest first.
    private static func eventList(_ s: FramerFlowController.Snapshot, now: TimeInterval) -> String {
        // Localization unneeded: technical output in a debugging window.
        let shown = s.events.suffix(15).reversed()
        guard !shown.isEmpty else {
            return "Recent events: none"
        }
        return (["Recent events, newest first:"] + shown.map {
            String(format: "%8.2f s  ", $0.time - now) + $0.description
        }).joined(separator: "\n")
    }

    /// The least delay of each size of frame over L, which the baseline is drawn from.
    private static func bucketTable(_ s: FramerFlowController.Snapshot) -> String {
        // Localization unneeded: technical output in a debugging window.
        let bytes = { (n: Int) in FlowControlChart.Unit.bytes.format(Double(n)) }
        let seconds = FlowControlChart.Unit.seconds.format
        let baseline = s.delayBaseline
        let header = ["Frames", "Seen", "Least at", "Over base", "Correction", "Corrected", "Edge"]
        let rows = baseline.buckets.map { bucket -> [String] in
            let range = bucket.upperBound.map { "\(bytes(bucket.lowerBound))–\(bytes($0))" } ?? "\(bytes(bucket.lowerBound))+"
            guard let delay = bucket.leastDelay, let size = bucket.leastBytes, let base = baseline.base else {
                return [range, "\(bucket.readings)", "–", "–", "–", "–", ""]
            }
            let correction = baseline.correction(forBytes: size)
            return [range,
                    "\(bucket.readings)",
                    bytes(size),
                    seconds(delay - base),
                    seconds(correction),
                    seconds(delay - correction - base),
                    bucket.onEdge ? "yes" : ""]
        }
        return table(header: header, rows: rows)
    }

    private static func table(header: [String], rows: [[String]]) -> String {
        let all = [header] + rows
        let widths = header.indices.map { column in all.map { $0[column].count }.max() ?? 0 }
        return all.map { row in
            row.indices.map { row[$0].padding(toLength: widths[$0] + 2, withPad: " ", startingAt: 0) }
                .joined()
        }.joined(separator: "\n")
    }

    private static func flowTable(_ s: FramerFlowController.Snapshot) -> String {
        // Localization unneeded: technical output in a debugging window.
        let bytes = FlowControlChart.Unit.bytes.format
        let seconds = FlowControlChart.Unit.seconds.format
        let header = ["Flow", "Window", "Outstanding", "Backlog", "Waits", "Cap", "Busy"]
        let rows = s.flows.map { flow in
            [flow.flow.description,
             bytes(flow.window),
             bytes(Double(flow.outstanding)),
             bytes(Double(flow.backlog)),
             flow.consumptionDelay.map(seconds) ?? "–",
             flow.cap.map(bytes) ?? "–",
             flow.busy ? "yes" : "no"]
        }
        return table(header: header, rows: rows)
    }
}
