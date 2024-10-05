//
//  iTermShape.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/6/25.
//

import Foundation

enum Segment {
    var description: String {
        switch self {
            case .moveTo(let p):
            return "moveTo(\(p.x),\(p.y))"
        case .lineTo(let p):
            return "lineTo(\(p.x),\(p.y))"
        case .curveTo(destination: let d, control1: let c1, control2: let c2):
            return "curveTo(\(d.x),\(d.y); \(c1.x),\(c1.y); \(c2.x),\(c2.y))"
        }
    }

    case moveTo(NSPoint)
    case lineTo(NSPoint)
    case curveTo(destination: NSPoint, control1: NSPoint, control2: NSPoint)
}

// This is like NSBezierPath, but you can use it without crying. The CG APIs make it much easier to
// draw shapes with vertices where you'd expect them.
@objc(iTermShapeBuilder)
class ShapeBuilder: NSObject {
    private var segments = [Segment]()
    @objc var lineWidth = 1.0
    override var description: String {
        "lineWidth=\(lineWidth)\n" +
        segments.map { "  " + $0.description }.joined(separator: "\n")
    }

    @objc
    func moveTo(_ point: NSPoint) {
        segments.append(.moveTo(point))
    }

    @objc
    func lineTo(_ point: NSPoint) {
        segments.append(.lineTo(point))
    }

    @objc
    func curve(to destination: NSPoint, control1: NSPoint, control2: NSPoint) {
        segments.append(.curveTo(destination: destination, control1: control1, control2: control2))
    }

    @objc(addRect:)
    func add(rect: NSRect) {
        moveTo(rect.minXmaxY)
        lineTo(rect.maxXmaxY)
        lineTo(rect.maxXminY)
        lineTo(rect.minXminY)
        lineTo(rect.minXmaxY)
    }

    @objc
    func addPath(to ctx: CGContext) {
        guard !segments.isEmpty else {
            return
        }
        ctx.beginPath()
        for segment in segments {
            switch segment {
            case .moveTo(let p):
                ctx.move(to: p)
            case .lineTo(let p):
                ctx.addLine(to: p)
            case .curveTo(destination: let d, control1: let c1, control2: let c2):
                ctx.addCurve(to: d, control1: c1, control2: c2)
            }
        }
    }
}

