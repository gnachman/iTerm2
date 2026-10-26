//
//  FlowControlMonitorViewTests.swift
//  iTerm2 ModernTests
//
//  The flow control monitor's window content, drawn from a minute of a real controller's
//  history. Each test also writes what it drew to a PNG in the temporary directory, named in
//  the test's output, for a person to look at.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class FlowControlMonitorViewTests: XCTestCase {
    typealias Controller = FramerFlowController

    /// A minute of a flood over a 50 ms round trip, sampled ten times a second as the monitor
    /// does. Half way through the session falls behind for a few seconds.
    private func floodHistory(carried: Bool) -> FlowControlHistory {
        let c = Controller(now: 0, recovering: false) { _ in }
        c.roundTripDidComplete(sentAt: 0, now: 0.05)
        var history = FlowControlHistory()
        var t = 0.0
        while t < 60 {
            t += 0.01
            let queued = (t > 30 && t < 34) ? 0.08 : 0.005
            c.frameDidArrive(now: t,
                             sendMilliseconds: Int64((t - 0.025 - queued) * 1000),
                             bytes: 400,
                             limited: true,
                             exempt: false,
                             carrierMilliseconds: carried ? Int64((t - 0.01) * 1000) : nil)
            c.flowDidConsume(.leader, bytes: 400, now: t)
            if carried {
                c.carrierWindow = 48 * 1024
            }
            c.tick(now: t)
            if Int((t * 100).rounded()) % 10 == 0 {
                history.record(c.snapshot(now: t), at: t)
            }
        }
        return history
    }

    private func model() -> FlowControlMonitorView.Model {
        FlowControlMonitorView.Model(
            sessionName: "Default (zsh)",
            hasSession: true,
            connections: [
                .init(guid: "outer", depth: 0, name: "george@host1", reasonOff: nil, flowVersion: 2,
                      clockName: "boottime", history: floodHistory(carried: false), roundTrips: []),
                .init(guid: "inner", depth: 1, name: "george@host2", reasonOff: nil, flowVersion: 2,
                      clockName: "monotonic", history: floodHistory(carried: true), roundTrips: []),
                .init(guid: "third", depth: 2, name: "george@host3",
                      reasonOff: "Off until the connection it is nested in runs flow control version 2.",
                      flowVersion: 1, clockName: nil, history: FlowControlHistory(),
                      roundTrips: (1...20).map { Conductor.RoundTrip(time: 40 + Double($0), seconds: 0.03 * Double($0 % 5 + 1)) }),
            ],
            now: 60)
    }

    private func render(_ view: NSView, appearance: NSAppearance.Name, name: String) throws -> NSBitmapImageRep {
        view.appearance = NSAppearance(named: appearance)
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("FlowControlMonitor-\(name).png")
        try png.write(to: URL(fileURLWithPath: path))
        print("Wrote \(path)")
        return rep
    }

    func testEveryConnectionGetsASection() throws {
        let view = FlowControlMonitorView(frame: NSRect(x: 0, y: 0, width: 640, height: 100))
        view.model = model()
        let height = view.requiredHeight(width: 640)
        // Two connections with charts (three each) and one that is off.
        XCTAssertGreaterThan(height, 6 * FlowControlChart.height)
        view.setFrameSize(NSSize(width: 640, height: height))
        for (appearance, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            let rep = try render(view, appearance: appearance, name: name)
            XCTAssertEqual(rep.size.height, height)
        }
    }

    func testWithoutAConnectionItSaysSo() throws {
        let view = FlowControlMonitorView(frame: NSRect(x: 0, y: 0, width: 640, height: 100))
        view.model = FlowControlMonitorView.Model(sessionName: "Default", hasSession: true, connections: [], now: 0)
        XCTAssertLessThan(view.requiredHeight(width: 640), FlowControlChart.height)
        _ = try render(view, appearance: .aqua, name: "none")
    }

    func testAxisCeilingsAreRound() {
        XCTAssertEqual(FlowControlChart.Unit.bytes.ceiling(50_000), 50 * 1024)
        XCTAssertEqual(FlowControlChart.Unit.bytes.ceiling(1500), 2 * 1024)
        XCTAssertEqual(FlowControlChart.Unit.bytes.ceiling(3 * 1024 * 1024), 5 * 1024 * 1024)
        XCTAssertEqual(FlowControlChart.Unit.seconds.ceiling(0.037), 0.05, accuracy: 1e-12)
        XCTAssertEqual(FlowControlChart.Unit.seconds.ceiling(0), 1)
    }
}
