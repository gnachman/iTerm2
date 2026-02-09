//
//  iTermActivePaneBorderView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/8/26.
//

import Foundation
import AppKit

@objc(iTermActivePaneBorderView)
class iTermActivePaneBorderView: NSView {
    private let shapeLayer = CAShapeLayer()

    @objc var borderColor: NSColor = .systemBlue {
        didSet {
            updateBorder()
        }
    }

    @objc var borderWidth: CGFloat = 2.0 {
        didSet {
            updateBorder()
        }
    }

    private var topLeftRadius: CGFloat = 0
    private var topRightRadius: CGFloat = 0
    private var bottomLeftRadius: CGFloat = 0
    private var bottomRightRadius: CGFloat = 0

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
        shapeLayer.lineWidth = borderWidth
        updateBorder()
    }

    override func layout() {
        super.layout()
        shapeLayer.frame = bounds
        updatePath()
    }

    @objc func setCornerRadius(_ radius: CGFloat,
                               topLeft: Bool,
                               topRight: Bool,
                               bottomLeft: Bool,
                               bottomRight: Bool) {
        topLeftRadius = topLeft ? radius : 0
        topRightRadius = topRight ? radius : 0
        bottomLeftRadius = bottomLeft ? radius : 0
        bottomRightRadius = bottomRight ? radius : 0
        updatePath()
    }

    private func updateBorder() {
        shapeLayer.strokeColor = borderColor.cgColor
        shapeLayer.lineWidth = borderWidth
    }

    private func updatePath() {
        let rect = bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
        guard rect.width > 0 && rect.height > 0 else {
            shapeLayer.path = nil
            return
        }

        let path = CGMutablePath()

        // Start at top-left, after the corner radius
        let topLeftCorner = CGPoint(x: rect.minX, y: rect.maxY)
        let topRightCorner = CGPoint(x: rect.maxX, y: rect.maxY)
        let bottomRightCorner = CGPoint(x: rect.maxX, y: rect.minY)
        let bottomLeftCorner = CGPoint(x: rect.minX, y: rect.minY)

        // Clamp radii to not exceed half the smaller dimension
        let maxRadius = min(rect.width, rect.height) / 2
        let tlRadius = min(topLeftRadius, maxRadius)
        let trRadius = min(topRightRadius, maxRadius)
        let brRadius = min(bottomRightRadius, maxRadius)
        let blRadius = min(bottomLeftRadius, maxRadius)

        // Move to start position (after top-left corner)
        path.move(to: CGPoint(x: rect.minX + tlRadius, y: rect.maxY))

        // Top edge to top-right corner
        path.addLine(to: CGPoint(x: rect.maxX - trRadius, y: rect.maxY))

        // Top-right corner
        if trRadius > 0 {
            path.addArc(tangent1End: topRightCorner,
                       tangent2End: CGPoint(x: rect.maxX, y: rect.maxY - trRadius),
                       radius: trRadius)
        } else {
            path.addLine(to: topRightCorner)
        }

        // Right edge to bottom-right corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + brRadius))

        // Bottom-right corner
        if brRadius > 0 {
            path.addArc(tangent1End: bottomRightCorner,
                       tangent2End: CGPoint(x: rect.maxX - brRadius, y: rect.minY),
                       radius: brRadius)
        } else {
            path.addLine(to: bottomRightCorner)
        }

        // Bottom edge to bottom-left corner
        path.addLine(to: CGPoint(x: rect.minX + blRadius, y: rect.minY))

        // Bottom-left corner
        if blRadius > 0 {
            path.addArc(tangent1End: bottomLeftCorner,
                       tangent2End: CGPoint(x: rect.minX, y: rect.minY + blRadius),
                       radius: blRadius)
        } else {
            path.addLine(to: bottomLeftCorner)
        }

        // Left edge to top-left corner
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - tlRadius))

        // Top-left corner
        if tlRadius > 0 {
            path.addArc(tangent1End: topLeftCorner,
                       tangent2End: CGPoint(x: rect.minX + tlRadius, y: rect.maxY),
                       radius: tlRadius)
        } else {
            path.addLine(to: topLeftCorner)
        }

        path.closeSubpath()
        shapeLayer.path = path
    }
}
