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
    private struct LineDash {
        var dashPattern: [CGFloat]
        var phase: CGFloat
    }
    private var segments = [Segment]()
    private var lineDash: LineDash?
    @objc var lineWidth = 1.0
    @objc var endcap = CGLineCap.square
    @objc var enableEndcap = true

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

    @objc(setLineDash:count:phase:)
    func setLineDash(_ dashPattern: UnsafePointer<CGFloat>, count: Int, phase: CGFloat) {
        let buffer = UnsafeBufferPointer(start: dashPattern, count: count)
        lineDash = LineDash(dashPattern: Array(buffer), phase: phase)
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

    @objc(strokeInContext:color:)
    func stroke(in ctx: CGContext, color: CGColor) {
        // For axis-aligned lines without dashes, fill pixel-aligned rects instead of
        // stroking to avoid anti-aliased smearing across pixel boundaries.
        if lineDash == nil, let rects = axisAlignedRects() {
            ctx.setFillColor(color)
            for rect in rects {
                ctx.fill(pixelAlignedRect(rect, in: ctx))
            }
            return
        }

        addPath(to: ctx)
        if let lineDash {
            ctx.setLineDash(phase: lineDash.phase, lengths: lineDash.dashPattern)
        }
        ctx.setStrokeColor(color)
        ctx.setLineWidth(lineWidth)
        if enableEndcap {
            ctx.setLineCap(endcap)
        }
        ctx.strokePath()
    }

    // Returns filled rects equivalent to stroking the path, or nil if any segment
    // is diagonal or curved.
    private func axisAlignedRects() -> [CGRect]? {
        var rects = [CGRect]()
        var currentPoint: NSPoint?
        let halfWidth = lineWidth / 2
        let capExtension = (enableEndcap && endcap == .square) ? halfWidth : 0

        for segment in segments {
            switch segment {
            case .moveTo(let p):
                currentPoint = p
            case .lineTo(let p):
                guard let start = currentPoint else { return nil }
                if start.x == p.x {
                    // Vertical line
                    let minY = min(start.y, p.y)
                    let maxY = max(start.y, p.y)
                    rects.append(CGRect(x: start.x - halfWidth,
                                        y: minY - capExtension,
                                        width: lineWidth,
                                        height: maxY - minY + 2 * capExtension))
                } else if start.y == p.y {
                    // Horizontal line
                    let minX = min(start.x, p.x)
                    let maxX = max(start.x, p.x)
                    rects.append(CGRect(x: minX - capExtension,
                                        y: start.y - halfWidth,
                                        width: maxX - minX + 2 * capExtension,
                                        height: lineWidth))
                } else {
                    // Diagonal — can't convert to a rect
                    return nil
                }
                currentPoint = p
            case .curveTo:
                return nil
            }
        }

        return rects.isEmpty ? nil : rects
    }

    // Snaps a rect to device-pixel boundaries, ensuring at least 1 device pixel
    // in each dimension.
    private func pixelAlignedRect(_ rect: CGRect, in ctx: CGContext) -> CGRect {
        let deviceRect = ctx.convertToDeviceSpace(rect)
        let x = round(deviceRect.origin.x)
        let y = round(deviceRect.origin.y)
        let maxX = round(deviceRect.maxX)
        let maxY = round(deviceRect.maxY)
        let aligned = CGRect(x: x, y: y,
                             width: max(1, maxX - x),
                             height: max(1, maxY - y))
        return ctx.convertToUserSpace(aligned)
    }
}

