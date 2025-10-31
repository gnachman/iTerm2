//
//  iTermProgressBarView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/29/25.
//

import Foundation
import AppKit
import QuartzCore

extension VT100ScreenProgress {
    var successPercentage: Int32? {
        if rawValue < VT100ScreenProgress.successBase.rawValue {
            return nil
        }
        let percentage = Int32(clamping: rawValue - VT100ScreenProgress.successBase.rawValue)
        if percentage < 0 || percentage > 100 {
            return nil
        }
        return percentage
    }
    var errorPercentage: Int32? {
        if rawValue < VT100ScreenProgress.errorBase.rawValue {
            return nil
        }
        let percentage = Int32(clamping: rawValue - VT100ScreenProgress.errorBase.rawValue)
        if percentage < 0 || percentage > 100 {
            return nil
        }
        return percentage
    }
    var warningPercentage: Int32? {
        if rawValue < VT100ScreenProgress.warningBase.rawValue {
            return nil
        }
        let percentage = Int32(clamping: rawValue - VT100ScreenProgress.warningBase.rawValue)
        if percentage < 0 || percentage > 100 {
            return nil
        }
        return percentage
    }
}

@objc
class iTermProgressBarView: NSView {
    @objc var desiredHeight: CGFloat {
        iTermPreferences.float(forKey: kPreferenceKeyTopBottomMargins)
    }
    @objc var darkMode = false {
        didSet {
            if darkMode != oldValue {
                darkModeDidChange()
            }
        }
    }
    @objc var state = VT100ScreenProgress.stopped {
        didSet {
            stateDidChange(oldValue: oldValue)
        }
    }

    private enum Success {
        case success
        case warning
        case error
    }
    private enum Mode: Equatable {
        case ground
        case error
        case indeterminate
        case determinate(success: Success, percentage: Int32)
    }

    private var mode = Mode.ground {
        didSet {
            modeDidChange(oldValue: oldValue)
        }
    }

    private lazy var errorLayer: CALayer = {
        iTermProgressBarView.makeGradientLayer(colors: errorColors(dark: darkMode).base)
    }()
    private lazy var indeterminateContainer: CALayer = {
        CALayer()
    }()
    private lazy var indeterminateLayer1: CALayer = {
        iTermProgressBarView.makeGradientLayer(colors: indeterminateColors(dark: darkMode))
    }()
    private lazy var indeterminateLayer2: CALayer = {
        iTermProgressBarView.makeGradientLayer(colors: indeterminateColors(dark: darkMode))
    }()
    private lazy var determinateLayer: CALayer = {
        iTermProgressBarView.makeGradientLayer(colors: determinateColors(success: .success,
                                                                         dark: darkMode))
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.delegate = self
        layer?.backgroundColor = backgroundColor(dark: darkMode)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Private implementation

private extension iTermProgressBarView {
    // MARK: - Color Schemes

    private func errorColors(dark: Bool) -> (base: [NSColor], light: [NSColor]) {
        if dark {
            let baseDark1 = NSColor(srgbRed: 1.0, green: 0.5, blue: 0.5, alpha: 1.0)
            let baseDark2 = NSColor(srgbRed: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
            let baseDark3 = NSColor(srgbRed: 1.0, green: 0.5, blue: 0.5, alpha: 1.0)

            let lightDark1 = NSColor(srgbRed: 1.0, green: 0.9, blue: 0.9, alpha: 1.0)
            let lightDark2 = NSColor(srgbRed: 1.0, green: 0.8, blue: 0.8, alpha: 1.0)
            let lightDark3 = NSColor(srgbRed: 1.0, green: 0.9, blue: 0.9, alpha: 1.0)

            return (base: [baseDark1, baseDark2, baseDark3],
                    light: [lightDark1, lightDark2, lightDark3])
        } else {
            let baseLight1 = NSColor(srgbRed: 0.8, green: 0.2, blue: 0.2, alpha: 1.0)
            let baseLight2 = NSColor(srgbRed: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
            let baseLight3 = NSColor(srgbRed: 1.0, green: 0.2, blue: 0.2, alpha: 1.0)

            let lightLight1 = NSColor(srgbRed: 0.9, green: 0.6, blue: 0.6, alpha: 1.0)
            let lightLight2 = NSColor(srgbRed: 1.0, green: 0.5, blue: 0.5, alpha: 1.0)
            let lightLight3 = NSColor(srgbRed: 1.0, green: 0.6, blue: 0.6, alpha: 1.0)

            return (base: [baseLight1, baseLight2, baseLight3],
                    light: [lightLight1, lightLight2, lightLight3])
        }
    }

    private func indeterminateColors(dark: Bool) -> [NSColor] {
        if dark {
            return [green(0.0), green(0.5), green(1.0), green(1.0), green(0.5), green(0.0)]
        } else {
            return [blue(0.0), blue(0.3), blue(1.0), blue(0.3), blue(0.0)]
        }
    }

    private func determinateColors(success: Success, dark: Bool) -> [NSColor] {
        switch success {
        case .success:
            if dark {
                return [NSColor(srgbRed: 0.0, green: 1.0, blue: 0.0, alpha: 1.0),
                        NSColor(srgbRed: 0.2, green: 1.0, blue: 0.2, alpha: 1.0)]
            } else {
                return [NSColor(srgbRed: 0.0, green: 0.0, blue: 1.0, alpha: 1.0),
                        NSColor(srgbRed: 0.2, green: 0.2, blue: 1.0, alpha: 1.0)]
            }
        case .warning:
            if dark {
                return [NSColor(srgbRed: 1.0, green: 0.5, blue: 0.0, alpha: 1.0),
                        NSColor(srgbRed: 1.0, green: 0.7, blue: 0.2, alpha: 1.0)]
            } else {
                return [NSColor(srgbRed: 0.8, green: 0.6, blue: 0.0, alpha: 1.0),
                        NSColor(srgbRed: 1.0, green: 0.8, blue: 0.2, alpha: 1.0)]
            }
        case .error:
            if dark {
                return [NSColor(srgbRed: 1.0, green: 0.0, blue: 0.0, alpha: 1.0),
                        NSColor(srgbRed: 1.0, green: 0.2, blue: 0.2, alpha: 1.0)]
            } else {
                return [NSColor(srgbRed: 1.0, green: 0.0, blue: 0.0, alpha: 1.0),
                        NSColor(srgbRed: 1.0, green: 0.2, blue: 0.2, alpha: 1.0)]
            }
        }
    }

    private func backgroundColor(dark: Bool) -> CGColor {
        if dark {
            return .black
        } else {
            return .white
        }
    }

    private func blue(_ blueness: CGFloat) -> NSColor {
        return NSColor(srgbRed: 1.0 - blueness, green: 1.0 - blueness, blue: 1, alpha: 1)
    }

    private func green(_ greenness: CGFloat) -> NSColor {
        return NSColor(srgbRed: 0.0, green: greenness, blue: 0.0, alpha: 1)
    }

    // MARK: - Layer Creation

    private static func makeGradientLayer(colors: [NSColor]) -> CALayer {
        let layer = CAGradientLayer()
        layer.frame = CGRect(x: 0, y: 0, width: 100, height: 2)
        layer.colors = colors.map { $0.cgColor }
        layer.locations = (0..<colors.count).map {
            Double($0) / Double(max(1, colors.count - 1))
        }.map {
            NSNumber(value: $0)
        }
        layer.startPoint = CGPoint(x: 0, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 0.5)
        return layer
    }

    private func darkModeDidChange() {
        // Update background color
        layer?.backgroundColor = backgroundColor(dark: darkMode)

        // Update error layer colors
        if let errorGradient = errorLayer as? CAGradientLayer {
            let colors = errorColors(dark: darkMode)
            errorGradient.colors = colors.base.map { $0.cgColor }

            // If error animation is running, restart it with new colors
            if errorGradient.animation(forKey: "errorPulse") != nil {
                startErrorPulseAnimation()
            }
        }

        // Update indeterminate layer colors
        if let indeterminate1 = indeterminateLayer1 as? CAGradientLayer {
            let colors = indeterminateColors(dark: darkMode)
            indeterminate1.colors = colors.map { $0.cgColor }
        }
        if let indeterminate2 = indeterminateLayer2 as? CAGradientLayer {
            let colors = indeterminateColors(dark: darkMode)
            indeterminate2.colors = colors.map { $0.cgColor }
        }
        // If indeterminate animations are running, restart them to keep them synchronized
        if indeterminateLayer1.animation(forKey: "indeterminateScroll") != nil {
            startIndeterminateAnimation()
        }

        // Update determinate layer colors
        if case let .determinate(success: success, percentage: _) = mode {
            updateDeterminateColors(success: success)
        } else {
            updateDeterminateColors(success: .success)
        }
    }

    private func updateDeterminateColors(success: Success) {
        if let determinateGradient = determinateLayer as? CAGradientLayer {
            let colors = determinateColors(success: success, dark: darkMode)
            determinateGradient.colors = colors.map { $0.cgColor }
        }
    }
    
    private func stateDidChange(oldValue: VT100ScreenProgress) {
        if state == oldValue {
            return
        }
        switch state {
        case .stopped:
            mode = .ground
            return
        case .error:
            mode = .error
            return
        case .indeterminate:
            mode = .indeterminate
            return
        case .successBase, .errorBase, .warningBase:
            break
        @unknown default:
            break
        }
        if let newPercentage = state.successPercentage {
            mode = .determinate(success: .success, percentage: newPercentage)
        } else if let newPercentage = state.errorPercentage {
            mode = .determinate(success: .error, percentage: newPercentage)
        } else if let newPercentage = state.warningPercentage {
            mode = .determinate(success: .warning, percentage: newPercentage)
        } else {
            mode = .ground
        }
    }

    private func modeDidChange(oldValue: Mode) {
        if mode == oldValue {
            return
        }
        switch mode {
        case .ground:
            layer(for: oldValue)?.removeFromSuperlayer()
        case .error:
            layer(for: oldValue)?.removeFromSuperlayer()
            layer?.addSublayer(errorLayer)
            startErrorPulseAnimation()
        case .indeterminate:
            layer(for: oldValue)?.removeFromSuperlayer()
            layer?.addSublayer(indeterminateContainer)
            setupIndeterminateLayers()
            startIndeterminateAnimation()
        case let .determinate(success: success, percentage: percentage):
            if case .determinate = oldValue {
                setDeterminate(success: success, percentage: percentage, animated: true)
            } else {
                layer(for: oldValue)?.removeFromSuperlayer()
                layer?.addSublayer(determinateLayer)
                setDeterminate(success: success, percentage: percentage, animated: false)
            }
        }
        layer?.setNeedsLayout()
    }

    private func startErrorPulseAnimation() {
        guard let gradientLayer = errorLayer as? CAGradientLayer else { return }

        let animationKey = "errorPulse"
        gradientLayer.removeAnimation(forKey: animationKey)

        // Get color scheme based on dark mode
        let colors = errorColors(dark: darkMode)
        let baseColors = colors.base.map { $0.cgColor }
        let lightColors = colors.light.map { $0.cgColor }

        // Update the base colors
        gradientLayer.colors = baseColors

        // Animate between base and light colors
        let animation = CABasicAnimation(keyPath: "colors")
        animation.fromValue = baseColors
        animation.toValue = lightColors
        animation.duration = 0.8
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        gradientLayer.add(animation, forKey: animationKey)
    }

    private func setupIndeterminateLayers() {
        let width = layer?.bounds.width ?? bounds.width
        let height = desiredHeight

        let gradientWidth = width

        // Set up container to clip content
        indeterminateContainer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        indeterminateContainer.masksToBounds = true

        // Set up both gradient layers
        indeterminateLayer1.frame = CGRect(x: 0, y: 0, width: gradientWidth, height: height)
        indeterminateLayer2.frame = CGRect(x: 0, y: 0, width: gradientWidth, height: height)

        indeterminateContainer.addSublayer(indeterminateLayer1)
        indeterminateContainer.addSublayer(indeterminateLayer2)
    }

    private func startIndeterminateAnimation() {
        let animationKey = "indeterminateScroll"

        DLog("startIndeterminateAnimation called")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))

        indeterminateLayer1.removeAnimation(forKey: animationKey)
        indeterminateLayer2.removeAnimation(forKey: animationKey)

        let width = layer?.bounds.width ?? bounds.width
        let gradientWidth = width

        // Calculate the distance to travel (one full cycle)
        let distance = width + gradientWidth
        let duration = darkMode ? 3.0 : 6.0

        // Get current time to synchronize both animations precisely
        let now = CACurrentMediaTime()

        // Layer 1 starts from off-screen left
        let animation1 = CABasicAnimation(keyPath: "position.x")
        animation1.fromValue = -gradientWidth / 2
        animation1.toValue = width + gradientWidth / 2
        animation1.duration = duration
        animation1.repeatCount = .infinity
        animation1.timingFunction = CAMediaTimingFunction(name: .linear)
        animation1.beginTime = now
        animation1.isRemovedOnCompletion = false
        animation1.fillMode = .forwards

        indeterminateLayer1.position.x = -gradientWidth / 2
        indeterminateLayer1.add(animation1, forKey: animationKey)

        // Layer 2 follows layer 1, offset by half the duration to create wrap-around effect
        let animation2 = CABasicAnimation(keyPath: "position.x")
        animation2.fromValue = -gradientWidth / 2
        animation2.toValue = width + gradientWidth / 2
        animation2.duration = duration
        animation2.repeatCount = .infinity
        animation2.timingFunction = CAMediaTimingFunction(name: .linear)
        animation2.isRemovedOnCompletion = false
        animation2.fillMode = .forwards
        // Start layer 2's animation offset by the time it takes to travel one gradient width
        let timeOffset = (duration * Double(gradientWidth)) / Double(distance)
        animation2.beginTime = now - timeOffset

        indeterminateLayer2.position.x = -gradientWidth / 2
        indeterminateLayer2.add(animation2, forKey: animationKey)

        CATransaction.commit()
    }

    private func setDeterminate(success: Success, percentage: Int32, animated: Bool) {
        let clamped = max(0, min(100, percentage))
        let width = layer?.bounds.width ?? bounds.width
        let progressWidth = width * CGFloat(clamped) / 100.0
        let newFrame = CGRect(x: 0, y: 0, width: progressWidth, height: desiredHeight)
        if animated {
            let animation = CABasicAnimation(keyPath: "frame")
            animation.fromValue = determinateLayer.presentation()?.frame ?? determinateLayer.frame
            animation.toValue = newFrame
            animation.duration = 0.25
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            determinateLayer.add(animation, forKey: "progressWidth")
            determinateLayer.frame = newFrame
            updateDeterminateColors(success: success)
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            updateDeterminateColors(success: success)
            determinateLayer.frame = newFrame
            CATransaction.commit()
        }
    }

    private func layer(for mode: Mode) -> CALayer? {
        switch mode {
        case .ground: return nil
        case .error: return errorLayer
        case .indeterminate: return indeterminateContainer
        case .determinate: return determinateLayer
        }
    }
}

// MARK: - NSView overrides

extension iTermProgressBarView {
    // Layer frame updates are handled in layoutSublayers(of:), which updates frames based on mode,
    // ensuring the error layer fills its superlayer, the indeterminate layer animates properly,
    // and the determinate layer reflects the current progress percentage.

    override func layout() {
        super.layout()
        layer?.setNeedsLayout()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            // View removed from window - pause animations
            pauseAnimations()
        } else {
            // View added to window - resume animations
            resumeAnimations()
        }
    }

    private func pauseAnimations() {
        indeterminateLayer1.removeAnimation(forKey: "indeterminateScroll")
        indeterminateLayer2.removeAnimation(forKey: "indeterminateScroll")
        errorLayer.removeAnimation(forKey: "errorPulse")
    }

    private func resumeAnimations() {
        switch mode {
        case .indeterminate:
            if indeterminateLayer1.animation(forKey: "indeterminateScroll") == nil {
                startIndeterminateAnimation()
            }
        case .error:
            if errorLayer.animation(forKey: "errorPulse") == nil {
                startErrorPulseAnimation()
            }
        case .determinate, .ground:
            break
        }
    }
}

// MARK: - CALayerDelegate

extension iTermProgressBarView: CALayerDelegate {
    // CALayerDelegate method to update sublayer frames appropriately.
    func layoutSublayers(of layer: CALayer) {
        let width = layer.bounds.width
        let height = desiredHeight
        switch mode {
        case .error:
            // Make the error layer fill the entire width and desired height.
            errorLayer.frame = CGRect(x: 0, y: 0, width: width, height: height)
            // Only restart animation if it's not already running
            if errorLayer.animation(forKey: "errorPulse") == nil {
                startErrorPulseAnimation()
            }
        case .indeterminate:
            // Update container frame and restart animation if needed.
            indeterminateContainer.frame = CGRect(x: 0, y: 0, width: width, height: height)
            let gradientWidth = width
            indeterminateLayer1.frame = CGRect(x: 0, y: 0, width: gradientWidth, height: height)
            indeterminateLayer2.frame = CGRect(x: 0, y: 0, width: gradientWidth, height: height)
            // Only restart animation if it's not already running
            if indeterminateLayer1.animation(forKey: "indeterminateScroll") == nil {
                startIndeterminateAnimation()
            }
        case let .determinate(success: success, percentage: percentage):
            // Set determinate layer width according to current percentage.
            let clamped = max(0, min(100, percentage))
            let progressWidth = width * CGFloat(clamped) / 100.0
            determinateLayer.frame = CGRect(x: 0, y: 0, width: progressWidth, height: height)
            updateDeterminateColors(success: success)
        case .ground:
            // No visible layer to layout.
            break
        }
    }
}
