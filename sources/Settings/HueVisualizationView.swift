//
//  HueVisualizationView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/10/24.
//

import Foundation

@objc(iTermHueVisualizationViewDelegate)
protocol HueVisualizationViewDelegate: NSObjectProtocol {
    func hueVisualizationDidModifyColor(key: String, to: NSColor)
}

func matMul(_ mat1: [[Double]], _ mat2: [[Double]]) -> [[Double]] {
    let rows1 = mat1.count
    let cols1 = mat1[0].count
    let rows2 = mat2.count
    let cols2 = mat2[0].count

    precondition(cols1 == rows2, "Number of columns in the first matrix must equal the number of rows in the second matrix.")

    var result = Array(repeating: Array(repeating: 0.0, count: cols2), count: rows1)

    for i in 0..<rows1 {
        for j in 0..<cols2 {
            for k in 0..<cols1 {
                result[i][j] += mat1[i][k] * mat2[k][j]
            }
        }
    }

    return result
}


@objc(iTermHueVisualizationView)
class HueVisualizationView: NSView {
    // https://bottosson.github.io/posts/oklab/
    private struct OKLab: CustomDebugStringConvertible {
        var debugDescription: String {
            return "<OKLab l=\(l) a=\(a) b=\(b); hue=\(hue) chroma=\(chroma); r=\(p3.r), g=\(p3.g) b=\(p3.b)>"
        }
        var l: Float
        var a: Float
        var b: Float

        var hue: Float {
            return atan2(b, a)
        }

        var chroma: Float {
            return sqrt(a * a + b * b)
        }

        var xyz: iTermXYZColor {
            let m̅1̅ = [
                [1.227013851103521,   -0.5577999806518222,  0.2812561489664678],
                [-0.0405801784232806,  1.11225686961683,   -0.07167667866560121],
                [-0.0763812845057069, -0.4214819784180126,  1.586163220440795]
            ]

            let m̅2̅ = [
                [0.9999999984505197,  0.3963377921737678,   0.2158037580607588],
                [1.000000008881761,  -0.1055613423236563,  -0.06385417477170588],
                [1.000000054672411,  -0.08948418209496574, -1.291485537864092],
            ]
            let labVec = [ [Double(l)], [Double(a)], [Double(b)] ]
            let lmsPrimeVec = matMul(m̅2̅, labVec)
            let lmsVec = lmsPrimeVec.map { $0.map { pow($0, 3) }}
            let xyzVec = matMul(m̅1̅, lmsVec)
            return iTermXYZColor(x: xyzVec[0][0],
                                 y: xyzVec[1][0],
                                 z: xyzVec[2][0])
        }

        init(l: Float, a: Float, b: Float) {
            self.l = l
            self.a = a
            self.b = b
        }

        init?(_ color: NSColor) {
            guard let p3Color = color.usingColorSpace(.displayP3) else {
                return nil
            }
            let p3 = iTermP3Color(r: p3Color.redComponent,
                                  g: p3Color.greenComponent,
                                  b: p3Color.blueComponent)
            let xyz = iTermP3ToXYZ(p3)
            self.init(xyz)
        }

        init(_ xyz: iTermXYZColor) {
            let m1 = [
                [ 0.8189330101, 0.3618667424, -0.1288597137 ],
                [ 0.0329845436, 0.9293118715,  0.0361456387 ],
                [ 0.0482003018, 0.2643662691,  0.6338517070 ]
            ]
            let xyzVec = [[Double(xyz.x)], [Double(xyz.y)], [Double(xyz.z)]]
            let lmsVec = matMul(m1, xyzVec)
            let lmsPrimeVec = lmsVec.map { $0.map { pow($0, 1.0/3.0) }}
            let m2 = [
                [ 0.2104542553, 0.7936177850, -0.0040720468 ],
                [ 1.9779984951, -2.4285922050, +0.4505937099 ],
                [ 0.0259040371, 0.7827717662, -0.8086757660 ]
            ]
            let labVec = matMul(m2, lmsPrimeVec)

            l = Float(labVec[0][0])
            a = Float(labVec[1][0])
            b = Float(labVec[2][0])
        }

        private func clamp(_ value: CGFloat) -> CGFloat {
            if value < 0 {
                return 0
            }
            if value > 1 {
                return 1
            }
            return value
        }

        var inP3Gamut: Bool {
            let p3 = iTermXYZToLinearP3(xyz)
            return (p3.r >= 0 && p3.r <= 1 &&
                    p3.g >= 0 && p3.g <= 1 &&
                    p3.b >= 0 && p3.b <= 1)
        }

        var p3: iTermP3Color {
            return iTermXYZToP3(xyz)
        }

        var p3Color: NSColor {
            let p3 = self.p3
            return NSColor(displayP3Red: p3.r, green: p3.g, blue: p3.b, alpha: 1.0)
        }
    }
    private struct Entry {
        var key: String
        var color: NSColor
        var oklab: OKLab
    }
    private var entries: [Entry] = []
    @objc weak var delegate: HueVisualizationViewDelegate?

    @objc(setColor:forKey:) func set(color: NSColor, forKey key: String) {
        if let i = entries.firstIndex(where: { $0.key == key}) {
            if entries[i].color.isEqual(color) {
                return
            }
            entries[i].color = color
            entries[i].oklab = OKLab(color) ?? OKLab(l: 0, a: 0, b: 0)
        } else {
            entries.append(Entry(key: key, color: color, oklab: OKLab(color) ?? OKLab(l: 0, a: 0, b: 0)))
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        drawCircles()
        drawRadiuses()
        drawPoints()
    }

    private var center: NSPoint {
        return NSPoint(x: bounds.width / 2, y: bounds.height / 2)
    }

    private var radius: CGFloat {
        min(bounds.width, bounds.height) / 2
    }

    private func drawCircles() {
        let numCircles = 8
        if radius <= 0 {
            return
        }
        for i in 0..<numCircles {
            let r = self.radius * CGFloat(i + 1) / CGFloat(numCircles)
            if i == numCircles - 1 {
                NSColor.black.setStroke()
            } else {
                NSColor.gray.setStroke()
            }
            drawCircle(radius: r)
        }
    }

    private func drawCircle(radius: CGFloat) {
        let path = NSBezierPath(ovalIn: NSRect(x: center.x - radius,
                                               y: center.y - radius,
                                               width: radius * 2,
                                               height: radius * 2))
        path.lineWidth = 1
        path.stroke()
    }

    private func drawRadiuses() {
        let numRadiuses = 8
        NSColor.gray.setStroke()
        for i in 0..<numRadiuses {
            let Θ = Double.pi * 2.0 * Double(i) / Double(numRadiuses)
            drawRadius(angle: Θ)
        }
    }

    private func drawRadius(angle: Double) {
        let path = NSBezierPath()
        path.move(to: center)
        path.line(to: NSPoint(x: center.x + radius * cos(angle),
                              y: center.y + radius * sin(angle)))
        path.lineWidth = 1
        path.stroke()
    }

    private let pointRadius = CGFloat(4)
    // I checked all the colors in P3 and 0.4 is more than enough.
    private let maxChroma = Float(0.4)

    private func drawPoints() {
        for entry in entries {
            let r: CGFloat
            if dragInfo?.key == entry.key {
                r = pointRadius + 2
                NSColor.white.setStroke()
            } else {
                r = pointRadius
                NSColor.black.setStroke()
            }
            let path = NSBezierPath(ovalIn: rect(entry: entry, pointRadius: r))
            entry.color.setFill()
            path.fill()
            path.stroke()
        }
    }

    private func rect(entry: Entry, pointRadius: CGFloat) -> NSRect {
        let r = CGFloat(entry.oklab.chroma / maxChroma) * radius + pointRadius
        return NSRect(x: center.x + CGFloat(cos(entry.oklab.hue)) * CGFloat(r) - pointRadius,
                      y: center.y + CGFloat(sin(entry.oklab.hue)) * CGFloat(r) - pointRadius,
                      width: pointRadius * 2,
                      height: pointRadius * 2)
    }

    private struct Drag {
        var key: String
        var originalCenter: NSPoint
        var start: NSPoint
    }
    private var dragInfo: Drag?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (i, entry) in entries.enumerated().reversed() {
            let r = rect(entry: entry, pointRadius: pointRadius)
            if r.center.distance(to: point) <= pointRadius {
                dragInfo = Drag(key: entry.key,
                                originalCenter: NSPoint(x: r.midX, y: r.midY),
                                start: point)
                entries.remove(at: IndexSet(integer: i))
                entries.append(entry)
                needsDisplay = true
                return
            }
        }
    }

    private func index(key: String) -> Int? {
        return entries.firstIndex { entry in
            entry.key == key
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragInfo, let i = index(key: dragInfo.key) else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let delta = NSPoint(x: point.x - dragInfo.start.x,
                            y: point.y - dragInfo.start.y)
        let newCenter = NSPoint(x: dragInfo.originalCenter.x + delta.x,
                                y: dragInfo.originalCenter.y + delta.y)
        let (chroma, hue) = chromaAndHue(for: newCenter)

        let orig = entries[i]
        var temp = orig
        temp.oklab.a = chroma * cos(hue)
        temp.oklab.b = chroma * sin(hue)
        if let newValue = OKLab(temp.oklab.p3Color) {
            temp.oklab = newValue
            temp.color = newValue.p3Color

            delegate?.hueVisualizationDidModifyColor(key: dragInfo.key, to: temp.oklab.p3Color)
            entries[i] = temp
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragInfo = nil
        needsDisplay = true
    }

    func chromaAndHue(for point: NSPoint) -> (Float, Float) {
        // Calculate the vector from the center to the point
        let dx = point.x - center.x
        let dy = point.y - center.y

        // Calculate the distance from the center to the point
        let distance = sqrt(dx * dx + dy * dy)

        // Calculate the raw chroma based on the distance and reverse the radius scaling
        let chroma = Float((distance - pointRadius) / radius) * Float(maxChroma)

        // Calculate the hue based on the angle of the vector (atan2 returns the angle in radians)
        let hue = atan2(Float(dy), Float(dx))

        return (chroma, hue)
    }
}

