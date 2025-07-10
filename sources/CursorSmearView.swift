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
        DLog("Make animation from \(start) to \(end)")
        let pathAnimation = CAKeyframeAnimation(keyPath: "path")
        pathAnimation.duration = animationDuration
        pathAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        // Keyframes for path animation
        pathAnimation.values = animationPaths(rect1: start, rect2: end)
        pathAnimation.keyTimes = [0.0, 0.5, 1.0] as [NSNumber]

        return pathAnimation
    }

    private func distanceSquared(_ p1: NSPoint, _ p2: NSPoint) -> CGFloat {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return dx * dx + dy * dy
    }

    internal func animationPaths(rect1: NSRect, rect2: NSRect) -> [CGPath] {
        let startTopLeft = NSPoint(x: rect1.minX, y: rect1.minY)
        let startTopRight = NSPoint(x: rect1.maxX, y: rect1.minY)
        let startBottomRight = NSPoint(x: rect1.maxX, y: rect1.maxY)
        let startBottomLeft = NSPoint(x: rect1.minX, y: rect1.maxY)
        
        let endTopLeft = NSPoint(x: rect2.minX, y: rect2.minY)
        let endTopRight = NSPoint(x: rect2.maxX, y: rect2.minY)
        let endBottomRight = NSPoint(x: rect2.maxX, y: rect2.maxY)
        let endBottomLeft = NSPoint(x: rect2.minX, y: rect2.maxY)
        
        // Determine which quadrant rect2 is in relative to rect1
        let dx = rect2.midX - rect1.midX
        let dy = rect2.midY - rect1.midY
        DLog("rect1=\(rect1), rect2=\(rect2) dx=\(dx) dy=\(dy)")

        if dx >= 0 && dy >= 0 {
            // rect2 is bottom-right of rect1 (down and right in flipped coords)
            return [pathFromVertices([startTopLeft, startTopRight, startTopRight, startBottomRight, startBottomLeft, startBottomLeft]),
                    pathFromVertices([startTopLeft, startTopRight,   endTopRight,   endBottomRight,   endBottomLeft, startBottomLeft]),
                    pathFromVertices([  endTopLeft,   endTopRight,   endTopRight,   endBottomRight,   endBottomLeft,   endBottomLeft])]
        } else if dx < 0 && dy >= 0 {
            // rect2 is bottom-left of rect1 (down and left in flipped coords)
            return [pathFromVertices([startTopRight, startBottomRight, startBottomRight, startBottomLeft, startTopLeft, startTopLeft]),
                    pathFromVertices([startTopRight, startBottomRight,   endBottomRight,   endBottomLeft,   endTopLeft, startTopLeft]),
                    pathFromVertices([  endTopRight,   endBottomRight,   endBottomRight,   endBottomLeft,   endTopLeft,   endTopLeft])]
        } else if dx < 0 && dy < 0 {
            // rect2 is top-left of rect1 (up and left in flipped coords)
            return [pathFromVertices([startTopLeft, startTopRight, startTopRight, startBottomRight, startBottomLeft, startBottomLeft]),
                    pathFromVertices([  endTopLeft,   endTopRight, startTopRight, startBottomRight, startBottomLeft,   endBottomLeft]),
                    pathFromVertices([  endTopLeft,   endTopRight,   endTopRight,   endBottomRight,   endBottomLeft,   endBottomLeft])]
        } else {  // dx >= 0 && dy < 0
            // rect2 is top-right of rect1 (up and right in flipped coords)
            return [pathFromVertices([startBottomLeft, startTopLeft,  startTopLeft, startTopRight, startBottomRight, startBottomRight]),
                    pathFromVertices([startBottomLeft, startTopLeft,    endTopLeft,   endTopRight,   endBottomRight, startBottomRight]),
                    pathFromVertices([  endBottomLeft,   endTopLeft,    endTopLeft,   endTopRight,   endBottomRight,   endBottomRight])]
        }
    }
    
    private func pathFromVertices(_ vertices: [NSPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: vertices)
        path.closeSubpath()
        return path
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
