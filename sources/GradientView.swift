//
//  GradientView.swift
//  iTerm2
//
//  Created by George Nachman on 2/20/25.
//

import Cocoa

class GradientView: NSView {
    struct Stop {
        var color: NSColor
        var location: CGFloat
    }
    struct Gradient {
        var stops: [Stop]
    }

    private var gradientLayer: CAGradientLayer {
        return layer as! CAGradientLayer
    }

    var gradient: Gradient {
        didSet {
            updateGradient()
        }
    }

    init(gradient: Gradient) {
        self.gradient = gradient
        super.init(frame: .zero)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        it_fatalError()
    }

    override func makeBackingLayer() -> CALayer {
        return CAGradientLayer()
    }

    private func setupLayer() {
        wantsLayer = true
        updateGradient()
    }

    private func updateGradient() {
        effectiveAppearance.it_perform {
            let sorted = gradient.stops.sorted { lhs, rhs in
                lhs.location < rhs.location
            }
            let colors = sorted.map { $0.color.cgColor }
            let locations = sorted.map { NSNumber(value: $0.location) }
            print("colors=\(colors)")
            print("locations=\(locations)")
            gradientLayer.colors = colors
            gradientLayer.locations = locations
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateGradient()
    }
}
