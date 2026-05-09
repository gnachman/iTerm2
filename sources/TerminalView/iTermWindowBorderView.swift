//
//  iTermWindowBorderView.swift
//  iTerm2SharedARC
//

import Foundation
import AppKit

@objc(iTermWindowBorderView)
class iTermWindowBorderView: NSView {
    private let shapeLayer = CAShapeLayer()

    @objc var borderColor: NSColor = NSColor(white: 0.5, alpha: 0.75) {
        didSet { shapeLayer.strokeColor = borderColor.cgColor }
    }

    @objc var borderWidth: CGFloat = 1 {
        didSet {
            shapeLayer.lineWidth = borderWidth
            updatePath()
        }
    }

    @objc var cornerRadius: CGFloat = 12 {
        didSet { updatePath() }
    }

    @objc var outset: CGFloat = 0 {
        didSet { updatePath() }
    }

    @objc var haveLeftEdge: Bool = false { didSet { updatePath() } }
    @objc var haveTopEdge: Bool = false { didSet { updatePath() } }
    @objc var haveRightEdge: Bool = false { didSet { updatePath() } }
    @objc var haveBottomEdge: Bool = false { didSet { updatePath() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.addSublayer(shapeLayer)
        shapeLayer.fillColor = nil
        shapeLayer.strokeColor = borderColor.cgColor
        shapeLayer.lineWidth = borderWidth
    }

    override func layout() {
        super.layout()
        shapeLayer.frame = bounds
        updatePath()
    }

    // Stroke is the only visible content; pass clicks through to the layer underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    private func updatePath() {
        let effectiveInset = borderWidth / 2 - outset
        let inset = bounds.insetBy(dx: effectiveInset, dy: effectiveInset)
        guard inset.width > 0 && inset.height > 0 else {
            shapeLayer.path = nil
            return
        }
        let r = max(0, min(cornerRadius, min(inset.width, inset.height) / 2))

        let topLeftPresent     = haveTopEdge    && haveLeftEdge
        let topRightPresent    = haveTopEdge    && haveRightEdge
        let bottomLeftPresent  = haveBottomEdge && haveLeftEdge
        let bottomRightPresent = haveBottomEdge && haveRightEdge

        let leftX   = inset.minX
        let rightX  = inset.maxX
        let topY    = inset.maxY
        let bottomY = inset.minY

        let path = CGMutablePath()
        var penDown = false

        if haveTopEdge {
            let startX = leftX  + (topLeftPresent  ? r : 0)
            let endX   = rightX - (topRightPresent ? r : 0)
            path.move(to: CGPoint(x: startX, y: topY))
            path.addLine(to: CGPoint(x: endX, y: topY))
            if topRightPresent {
                path.addArc(tangent1End: CGPoint(x: rightX, y: topY),
                            tangent2End: CGPoint(x: rightX, y: topY - r),
                            radius: r)
                penDown = true
            } else {
                penDown = false
            }
        }

        if haveRightEdge {
            let startY = topY    - (topRightPresent    ? r : 0)
            let endY   = bottomY + (bottomRightPresent ? r : 0)
            if !penDown {
                path.move(to: CGPoint(x: rightX, y: startY))
            }
            path.addLine(to: CGPoint(x: rightX, y: endY))
            if bottomRightPresent {
                path.addArc(tangent1End: CGPoint(x: rightX, y: bottomY),
                            tangent2End: CGPoint(x: rightX - r, y: bottomY),
                            radius: r)
                penDown = true
            } else {
                penDown = false
            }
        }

        if haveBottomEdge {
            let startX = rightX - (bottomRightPresent ? r : 0)
            let endX   = leftX  + (bottomLeftPresent  ? r : 0)
            if !penDown {
                path.move(to: CGPoint(x: startX, y: bottomY))
            }
            path.addLine(to: CGPoint(x: endX, y: bottomY))
            if bottomLeftPresent {
                path.addArc(tangent1End: CGPoint(x: leftX, y: bottomY),
                            tangent2End: CGPoint(x: leftX, y: bottomY + r),
                            radius: r)
                penDown = true
            } else {
                penDown = false
            }
        }

        if haveLeftEdge {
            let startY = bottomY + (bottomLeftPresent ? r : 0)
            let endY   = topY    - (topLeftPresent    ? r : 0)
            if !penDown {
                path.move(to: CGPoint(x: leftX, y: startY))
            }
            path.addLine(to: CGPoint(x: leftX, y: endY))
            if topLeftPresent {
                path.addArc(tangent1End: CGPoint(x: leftX, y: topY),
                            tangent2End: CGPoint(x: leftX + r, y: topY),
                            radius: r)
            }
        }

        shapeLayer.path = path
    }
}
