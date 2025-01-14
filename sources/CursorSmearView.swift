//
//  CursorSmearView.swift
//  iTerm2
//
//  Created by George Nachman on 12/16/24.
//

import AppKit

@objc(iTermCursorSmearView)
class CursorSmearView: NSView {
    private var shapeLayer: CAShapeLayer?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        isHidden = true
    }
    
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    @objc
    func beginAnimation(start: NSRect,
                        end: NSRect,
                        color: NSColor) {
        DLog("Run smear from \(start) to \(end) with color \(color)")
        if distanceSquared(start.origin, end.origin) < 150.0 * 150.0 {
            DLog("Too close")
            return
        }
        let layer = makeLayer(color: color, frame: start)
        setShapeLayer(layer)
        run(animation: makeAnimation(start: start, end: end),
            inLayer: layer,
            endFrame: end)
        isHidden = false
    }

    private func setShapeLayer(_ layer: CAShapeLayer) {
        shapeLayer?.removeFromSuperlayer()
        shapeLayer = nil
        self.layer?.addSublayer(layer)
        shapeLayer = layer
    }

    private func makeLayer(color: NSColor, frame: NSRect) -> CAShapeLayer {
        let shapeLayer = CAShapeLayer()
        shapeLayer.fillColor = color.cgColor
        shapeLayer.frame = bounds
        shapeLayer.path = CGPath(rect: frame, transform: nil)
        return shapeLayer
    }

    private let animationDuration = CFTimeInterval(0.1)

    private func makeAnimation(start: NSRect, end: NSRect) -> CAAnimation {
        let pathAnimation = CAKeyframeAnimation(keyPath: "path")
        pathAnimation.duration = animationDuration
        pathAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        // Keyframes for path animation
        pathAnimation.values = animationPaths(rect1: start, rect2: end)
        pathAnimation.keyTimes = [0.0, 0.5, 1.0] as [NSNumber]

        return pathAnimation
    }

    private func alignRectToConvexHull(rect: NSRect, hull: [NSPoint]) -> [NSPoint] {
        // Get the vertices of the rectangle
        let rectPoints = rect.vertices

        // Find the closest rectangle vertex for each hull vertex
        var alignedPoints: [NSPoint] = []
        for hullPoint in hull {
            // Find the rectangle vertex closest to the current hull point
            if let closest = rectPoints.min(by: { distanceSquared($0, hullPoint) < distanceSquared($1, hullPoint) }) {
                alignedPoints.append(closest)
            }
        }

        // Ensure six points by duplicating necessary vertices
        while alignedPoints.count < 6 {
            alignedPoints.append(alignedPoints.last!)
        }

        return alignedPoints
    }

    private func distanceSquared(_ p1: NSPoint, _ p2: NSPoint) -> CGFloat {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return dx * dx + dy * dy
    }

    private func animationPaths(rect1: NSRect, rect2: NSRect) -> [CGPath] {
        // Compute the convex hull
        let hull = convexHull(of: rect1, and: rect2)

        // Align the start and end rectangles to match the hull
        let startPath = alignRectToConvexHull(rect: rect1, hull: hull)
        let endPath = alignRectToConvexHull(rect: rect2, hull: hull)

        return [pathFromVertices(startPath),
                pathFromVertices(hull),
                pathFromVertices(endPath)]
    }

    private func makeConvexHullPath(start: NSRect, end: NSRect) -> CGPath {
        // Determine the hull points explicitly
        let vertices = convexHull(of: start, and: end)
        return pathFromVertices(vertices)
    }

    private func pathFromVertices(_ vertices: [NSPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: vertices)
        path.closeSubpath()
        return path
    }

    // This implements the Monotone Chain algorithm. There is an animation here that makes it
    // easy to understand:
    // https://en.wikibooks.org/wiki/Algorithm_Implementation/Geometry/Convex_hull/Monotone_chain
    func convexHull(of rect1: NSRect, and rect2: NSRect) -> [NSPoint] {
        // Get all vertices of the two rectangles
        let points = rect1.vertices + rect2.vertices

        // Sort points by x-coordinate, breaking ties by y-coordinate
        let sortedPoints = points.sorted { (p1, p2) -> Bool in
            if p1.x == p2.x {
                return p1.y < p2.y
            }
            return p1.x < p2.x
        }

        // Build the lower hull
        var lower: [NSPoint] = []
        for point in sortedPoints {
            while lower.count >= 2 && NSPoint.cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }

        // Build the upper hull
        var upper: [NSPoint] = []
        for point in sortedPoints.reversed() {
            while upper.count >= 2 && NSPoint.cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }

        // Remove the last point of each half because it's repeated at the beginning of the other
        lower.removeLast()
        upper.removeLast()

        // Concatenate lower and upper hulls to get the full convex hull
        return lower + upper
    }

    private func run(animation: CAAnimation, inLayer layer: CALayer, endFrame: NSRect) {
        // Handle animation completion
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.animationDidComplete(layer)
        }

        layer.add(animation, forKey: "frameAnimation")
        layer.frame = bounds
        CATransaction.commit()
    }

    private func animationDidComplete(_ layer: CALayer) {
        DLog("Animation completed")
        guard layer == shapeLayer else {
            return
        }
        layer.removeFromSuperlayer()
        shapeLayer = nil
        isHidden = true
    }
}

extension NSRect {
    var vertices: [NSPoint] {
        [NSPoint(x: minX, y: minY),
         NSPoint(x: maxX, y: minY),
         NSPoint(x: minX, y: maxY),
         NSPoint(x: maxX, y: maxY)]
    }
}

extension NSPoint {
    // The cross-product of three points gives the oriented area of the
    // triangle formed by them. This is the signed area scaled by two.
    // If it's positive, then a, b, and o are arranged in counterclockwise order.
    // If it's negative, then a, b, and o are arranged in clockwise order.
    // If it's zero, the points are collinear.
    static func cross(_ o: NSPoint,
                      _ a: NSPoint,
                      _ b: NSPoint) -> CGFloat {
        return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }
}
