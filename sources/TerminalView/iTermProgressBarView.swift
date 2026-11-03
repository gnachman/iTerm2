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
    @objc var heightValue: CGFloat = 2.0 {
        didSet {
            if heightValue != oldValue {
                // desiredHeight drives the sublayer sizes in layoutSublayers(of:).
                layer?.setNeedsLayout()
            }
        }
    }
    @objc var colorScheme: String = iTermProgressBarColorSchemeDefault {
        didSet {
            if colorScheme != oldValue {
                updateLayerColors()
            }
        }
    }
    @objc var desiredHeight: CGFloat {
        return heightValue > 0 ? heightValue : 0
    }
    @objc var transparent = false {
        didSet {
            updateBackgroundColor()
            if mode == .indeterminate {
                installIndeterminateLayer()
            }
        }
    }
    // The color to render behind the bar so it blends with the session's theme.
    // When nil we fall back to a fixed black/white background based on darkMode.
    // This can change for many reasons (profile edits, effective-appearance
    // changes, etc.), so setting it just refreshes the layer background.
    @objc var profileBackgroundColor: NSColor? {
        didSet {
            if profileBackgroundColor != oldValue {
                updateBackgroundColor()
            }
        }
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
        // An indeterminate band in the paused color, standing still.
        case pausedIndeterminate
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
    private lazy var pausedLayer: CALayer = {
        iTermProgressBarView.makeGradientLayer(colors: pausedColors(dark: darkMode))
    }()
    private lazy var determinateLayer: CALayer = {
        iTermProgressBarView.makeGradientLayer(colors: determinateColors(success: .success,
                                                                         dark: darkMode))
    }()
    private var indeterminateAnimationWidth: CGFloat = 0
    // indeterminateContainer or rotatingRainbowContainer while in .indeterminate.
    private var installedIndeterminateLayer: CALayer?
    private lazy var rotatingRainbowLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.type = .conic
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1.0, y: 0.5)
        layer.colors = Self.rotatingRainbowColors(step: 0)
        return layer
    }()
    private lazy var rotatingRainbowContainer: CALayer = {
        let layer = CALayer()
        layer.masksToBounds = true
        layer.addSublayer(rotatingRainbowLayer)
        return layer
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

    // The indeterminate band's shape, fading to nothing at both ends so it
    // cannot be read as a percentage, in the paused (warning) color.
    private func pausedColors(dark: Bool) -> [NSColor] {
        let color = dark ? NSColor(srgbRed: 1.0, green: 0.6, blue: 0.1, alpha: 1.0)
                         : NSColor(srgbRed: 0.85, green: 0.65, blue: 0.0, alpha: 1.0)
        let alphas: [CGFloat] = dark ? [0.0, 0.5, 1.0, 1.0, 0.5, 0.0] : [0.0, 0.3, 1.0, 0.3, 0.0]
        return alphas.map { color.withAlphaComponent($0) }
    }

    private func indeterminateColors(dark: Bool) -> [NSColor] {
        return colorSchemeColors(scheme: colorScheme, dark: dark, isIndeterminate: true)
    }

    private func determinateColors(success: Success, dark: Bool) -> [NSColor] {
        let scheme = colorScheme

        if success == .error {
            return [NSColor(srgbRed: 1.0, green: 0.0, blue: 0.0, alpha: 1.0),
                    NSColor(srgbRed: 1.0, green: 0.2, blue: 0.2, alpha: 1.0)]
        }

        if success == .warning {
            if dark {
                return [NSColor(srgbRed: 1.0, green: 0.5, blue: 0.0, alpha: 1.0),
                        NSColor(srgbRed: 1.0, green: 0.7, blue: 0.2, alpha: 1.0)]
            } else {
                return [NSColor(srgbRed: 0.8, green: 0.6, blue: 0.0, alpha: 1.0),
                        NSColor(srgbRed: 1.0, green: 0.8, blue: 0.2, alpha: 1.0)]
            }
        }

        return colorSchemeColors(scheme: scheme, dark: dark, isIndeterminate: false)
    }

    private func backgroundColor(dark: Bool) -> CGColor {
        if transparent {
            return .clear
        }
        if let profileBackgroundColor {
            return profileBackgroundColor.cgColor
        }
        if dark {
            return .black
        } else {
            return .white
        }
    }

    // The default indeterminate gradient fades to nothing at its endpoints.
    // Rather than baking in the background color (which used to be a fixed
    // black/white), we composite over the bar's background layer via alpha so
    // the fade blends into whatever is behind it (the profile background, or
    // the black/white fallback, or a transparent tab bar). Over black,
    // green(a) resolves to (0,a,0); over white, blue(a) resolves to
    // (1-a,1-a,1), matching the previous opaque colors exactly.
    private func blue(_ blueness: CGFloat) -> NSColor {
        return NSColor(srgbRed: 0, green: 0, blue: 1, alpha: blueness)
    }

    private func green(_ greenness: CGFloat) -> NSColor {
        return NSColor(srgbRed: 0, green: 1, blue: 0, alpha: greenness)
    }

    private func colorSchemeColors(scheme: String, dark: Bool, isIndeterminate: Bool) -> [NSColor] {
        switch scheme {
        case iTermProgressBarColorSchemeRainbow, iTermProgressBarColorSchemeRotatingRainbow:
            let red = NSColor(srgbRed: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
            let colors = [
                red,
                NSColor(srgbRed: 1.0, green: 0.5, blue: 0.0, alpha: 1.0),
                NSColor(srgbRed: 1.0, green: 1.0, blue: 0.0, alpha: 1.0),
                NSColor(srgbRed: 0.0, green: 1.0, blue: 0.0, alpha: 1.0),
                NSColor(srgbRed: 0.0, green: 0.5, blue: 1.0, alpha: 1.0),
                NSColor(srgbRed: 0.5, green: 0.0, blue: 1.0, alpha: 1.0),
                NSColor(srgbRed: 1.0, green: 0.0, blue: 0.5, alpha: 1.0)
            ]
            // The scrolling band tiles end to end, so close the loop at the seam.
            return isIndeterminate ? colors + [red] : colors
        case iTermProgressBarColorSchemeRed:
            return [
                NSColor(srgbRed: 0.8, green: 0.0, blue: 0.0, alpha: 1.0),
                NSColor(srgbRed: 1.0, green: 0.2, blue: 0.2, alpha: 1.0)
            ]
        case iTermProgressBarColorSchemeGreen:
            return [
                NSColor(srgbRed: 0.0, green: 0.8, blue: 0.0, alpha: 1.0),
                NSColor(srgbRed: 0.2, green: 1.0, blue: 0.2, alpha: 1.0)
            ]
        case iTermProgressBarColorSchemeBlue:
            return [
                NSColor(srgbRed: 0.0, green: 0.0, blue: 0.8, alpha: 1.0),
                NSColor(srgbRed: 0.2, green: 0.2, blue: 1.0, alpha: 1.0)
            ]
        case iTermProgressBarColorSchemeYellow:
            return [
                NSColor(srgbRed: 0.8, green: 0.8, blue: 0.0, alpha: 1.0),
                NSColor(srgbRed: 1.0, green: 1.0, blue: 0.2, alpha: 1.0)
            ]
        case iTermProgressBarColorSchemePurple:
            return [
                NSColor(srgbRed: 0.6, green: 0.0, blue: 0.8, alpha: 1.0),
                NSColor(srgbRed: 0.8, green: 0.2, blue: 1.0, alpha: 1.0)
            ]
        case iTermProgressBarColorSchemeCyan:
            return [
                NSColor(srgbRed: 0.0, green: 0.8, blue: 0.8, alpha: 1.0),
                NSColor(srgbRed: 0.2, green: 1.0, blue: 1.0, alpha: 1.0)
            ]
        case iTermProgressBarColorSchemeOrange:
            return [
                NSColor(srgbRed: 1.0, green: 0.5, blue: 0.0, alpha: 1.0),
                NSColor(srgbRed: 1.0, green: 0.7, blue: 0.2, alpha: 1.0)
            ]
        default:
            if isIndeterminate {
                if dark {
                    return [green(0.0), green(0.5), green(1.0), green(1.0), green(0.5), green(0.0)]
                } else {
                    return [blue(0.0), blue(0.3), blue(1.0), blue(0.3), blue(0.0)]
                }
            } else {
                if dark {
                    return [NSColor(srgbRed: 0.0, green: 1.0, blue: 0.0, alpha: 1.0),
                            NSColor(srgbRed: 0.2, green: 1.0, blue: 0.2, alpha: 1.0)]
                } else {
                    return [NSColor(srgbRed: 0.0, green: 0.0, blue: 1.0, alpha: 1.0),
                            NSColor(srgbRed: 0.2, green: 0.2, blue: 1.0, alpha: 1.0)]
                }
            }
        }
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

    private func updateBackgroundColor() {
        layer?.backgroundColor = backgroundColor(dark: darkMode)
    }

    private func darkModeDidChange() {
        updateBackgroundColor()
        updateLayerColors()
    }

    private func updateLayerColors() {
        if mode == .indeterminate {
            installIndeterminateLayer()
        }

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
            // Evenly spaced; the stop count changes with the scheme.
            indeterminate1.locations = nil
        }
        if let indeterminate2 = indeterminateLayer2 as? CAGradientLayer {
            let colors = indeterminateColors(dark: darkMode)
            indeterminate2.colors = colors.map { $0.cgColor }
            indeterminate2.locations = nil
        }
        // If indeterminate animations are running, restart them to keep them synchronized
        if indeterminateLayer1.animation(forKey: "indeterminateScroll") != nil {
            startIndeterminateAnimation()
        }

        if let paused = pausedLayer as? CAGradientLayer {
            let colors = pausedColors(dark: darkMode)
            paused.colors = colors.map { $0.cgColor }
            paused.locations = (0..<colors.count).map {
                NSNumber(value: Double($0) / Double(max(1, colors.count - 1)))
            }
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
        case .pausedIndeterminate:
            mode = .pausedIndeterminate
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
            removeLayer(for: oldValue)
        case .error:
            removeLayer(for: oldValue)
            layer?.addSublayer(errorLayer)
            startErrorPulseAnimation()
        case .indeterminate:
            removeLayer(for: oldValue)
            installIndeterminateLayer()
        case .pausedIndeterminate:
            removeLayer(for: oldValue)
            layer?.addSublayer(pausedLayer)
        case let .determinate(success: success, percentage: percentage):
            if case .determinate = oldValue {
                setDeterminate(success: success, percentage: percentage, animated: true)
            } else {
                removeLayer(for: oldValue)
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

        // Set up container to clip content
        indeterminateContainer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        indeterminateContainer.masksToBounds = true

        // Set up both gradient layers
        indeterminateLayer1.frame = CGRect(x: 0, y: 0, width: width, height: height)
        indeterminateLayer2.frame = CGRect(x: 0, y: 0, width: width, height: height)

        indeterminateContainer.addSublayer(indeterminateLayer1)
        indeterminateContainer.addSublayer(indeterminateLayer2)
    }

    private func startIndeterminateAnimation() {
        let animationKey = "indeterminateScroll"
        indeterminateAnimationWidth = layer?.bounds.width ?? bounds.width

        DLog("startIndeterminateAnimation called")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))

        indeterminateLayer1.removeAnimation(forKey: animationKey)
        indeterminateLayer2.removeAnimation(forKey: animationKey)

        let width = layer?.bounds.width ?? bounds.width
        let duration = darkMode ? 3.0 : 6.0
        let now = CACurrentMediaTime()

        let gradientWidth = width
        let distance = width + gradientWidth

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

        let animation2 = CABasicAnimation(keyPath: "position.x")
        animation2.fromValue = -gradientWidth / 2
        animation2.toValue = width + gradientWidth / 2
        animation2.duration = duration
        animation2.repeatCount = .infinity
        animation2.timingFunction = CAMediaTimingFunction(name: .linear)
        animation2.isRemovedOnCompletion = false
        animation2.fillMode = .forwards
        let timeOffset = (duration * Double(gradientWidth)) / Double(distance)
        animation2.beginTime = now - timeOffset

        indeterminateLayer2.position.x = -gradientWidth / 2
        indeterminateLayer2.add(animation2, forKey: animationKey)

        CATransaction.commit()
    }

    private func setDeterminate(success: Success, percentage: Int32, animated: Bool) {
        let clamped = max(0, min(100, percentage))
        let width = layer?.bounds.width ?? bounds.width
        let height = desiredHeight
        let progressWidth = width * CGFloat(clamped) / 100.0
        let newFrame = CGRect(x: 0, y: 0, width: progressWidth, height: height)
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

    private func removeLayer(for mode: Mode) {
        layer(for: mode)?.removeFromSuperlayer()
        if mode == .indeterminate {
            installedIndeterminateLayer = nil
        }
    }

    private func layer(for mode: Mode) -> CALayer? {
        switch mode {
        case .ground: return nil
        case .error: return errorLayer
        case .indeterminate: return installedIndeterminateLayer
        case .pausedIndeterminate: return pausedLayer
        case .determinate: return determinateLayer
        }
    }
}

// MARK: - Rotating rainbow

// Only the Tahoe ring (a transparent bar masked to the tab outline) rotates.
// Flat bars draw the Rotating Rainbow scheme as the scrolling rainbow.
extension iTermProgressBarView {
    private static let rotatingRainbowStopCount = 72
    private static let rotatingRainbowAnimationKey = "rotatingRainbow"
    private static let rotatingRainbowPeriod: CFTimeInterval = 3.0

    private static let rotatingRainbowHues: [CGColor] = (0..<rotatingRainbowStopCount).map {
        NSColor(hue: CGFloat($0) / CGFloat(rotatingRainbowStopCount),
                saturation: 1.0,
                brightness: 1.0,
                alpha: 1.0).cgColor
    }

    private var usesRotatingRainbow: Bool {
        transparent && colorScheme == iTermProgressBarColorSchemeRotatingRainbow
    }

    // One more color than stops: the last stop closes the loop at location 1.
    private static func rotatingRainbowColors(step: Int) -> [CGColor] {
        let hues = rotatingRainbowHues
        return (0...hues.count).map { hues[($0 + step) % hues.count] }
    }

    fileprivate func installIndeterminateLayer() {
        let rotating = usesRotatingRainbow
        let desired = rotating ? rotatingRainbowContainer : indeterminateContainer
        if installedIndeterminateLayer === desired {
            return
        }
        installedIndeterminateLayer?.removeFromSuperlayer()
        installedIndeterminateLayer = desired
        layer?.addSublayer(desired)
        if rotating {
            layoutRotatingRainbow(width: layer?.bounds.width ?? bounds.width, height: desiredHeight)
            startRotatingRainbowAnimation()
        } else {
            setupIndeterminateLayers()
            startIndeterminateAnimation()
        }
    }

    fileprivate func layoutRotatingRainbow(width: CGFloat, height: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rotatingRainbowContainer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        // Square, so the conic angles in unit space match the angles in points.
        let side = max(width, height)
        rotatingRainbowLayer.frame = CGRect(x: (width - side) / 2.0,
                                            y: (height - side) / 2.0,
                                            width: side,
                                            height: side)
        let locations = Self.stadiumConicLocations(width: width,
                                                   height: height,
                                                   count: Self.rotatingRainbowStopCount)
        rotatingRainbowLayer.locations = locations.isEmpty ? nil : (locations + [1.0]).map { NSNumber(value: Double($0)) }
        CATransaction.commit()
    }

    // Shifting each stop to its neighbor's hue moves the rainbow around the
    // ring. The colors animate; the geometry stays put, so a resize only
    // needs new locations.
    fileprivate func startRotatingRainbowAnimation() {
        let key = Self.rotatingRainbowAnimationKey
        rotatingRainbowLayer.removeAnimation(forKey: key)
        let animation = CAKeyframeAnimation(keyPath: "colors")
        animation.values = (0...Self.rotatingRainbowStopCount).map { Self.rotatingRainbowColors(step: $0) }
        animation.calculationMode = .linear
        animation.duration = Self.rotatingRainbowPeriod
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        rotatingRainbowLayer.add(animation, forKey: key)
    }

    // Conic-gradient locations in [0, 1) for `count` points evenly spaced by
    // arc length around the stadium (pill) that fills a width × height rect,
    // sorted by angle. Even spacing keeps the rainbow moving at one speed
    // along the long edges and around the caps.
    static func stadiumConicLocations(width: CGFloat, height: CGFloat, count: Int) -> [CGFloat] {
        let radius = min(width, height) / 2.0
        guard count > 0, radius > 0 else {
            return []
        }
        let halfStraight = (max(width, height) - 2.0 * radius) / 2.0
        let perimeter = 4.0 * halfStraight + 2.0 * .pi * radius
        let angles: [CGFloat] = (0..<count).map { k in
            let p = horizontalStadiumPoint(arcLength: perimeter * CGFloat(k) / CGFloat(count),
                                           radius: radius,
                                           halfStraight: halfStraight)
            // A tall stadium is a wide one rotated a quarter turn.
            let point = width >= height ? p : CGPoint(x: -p.y, y: p.x)
            let angle = atan2(point.y, point.x)
            return (angle < 0 ? angle + 2.0 * .pi : angle) / (2.0 * .pi)
        }
        guard let start = angles.indices.min(by: { angles[$0] < angles[$1] }) else {
            return []
        }
        return Array(angles[start...] + angles[..<start])
    }

    // Counterclockwise from the rightmost point of a wide stadium centered on the origin.
    private static func horizontalStadiumPoint(arcLength: CGFloat,
                                               radius r: CGFloat,
                                               halfStraight l: CGFloat) -> CGPoint {
        var s = arcLength
        let quarterArc = .pi * r / 2.0
        if s < quarterArc {
            let t = s / r
            return CGPoint(x: l + r * cos(t), y: r * sin(t))
        }
        s -= quarterArc
        if s < 2.0 * l {
            return CGPoint(x: l - s, y: r)
        }
        s -= 2.0 * l
        if s < .pi * r {
            let t = .pi / 2.0 + s / r
            return CGPoint(x: -l + r * cos(t), y: r * sin(t))
        }
        s -= .pi * r
        if s < 2.0 * l {
            return CGPoint(x: -l + s, y: -r)
        }
        s -= 2.0 * l
        let t = 3.0 * .pi / 2.0 + s / r
        return CGPoint(x: l + r * cos(t), y: r * sin(t))
    }
}

// MARK: - NSView overrides

extension iTermProgressBarView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    // Layer frame updates are handled in layoutSublayers(of:), which updates frames based on mode,
    // ensuring the error layer fills its superlayer, the indeterminate layer animates properly,
    // and the determinate layer reflects the current progress percentage.

    override func layout() {
        super.layout()
        layer?.setNeedsLayout()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // The gradient sublayers are sized in layoutSublayers(of:). When the
        // frame changes without the mode/state changing (e.g. the tab bar grows
        // after a compact->regular theme switch while progress is running),
        // nothing else marks the sublayers for layout, so they would keep their
        // old height and the ring would only be partially filled.
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
        rotatingRainbowLayer.removeAnimation(forKey: Self.rotatingRainbowAnimationKey)
        errorLayer.removeAnimation(forKey: "errorPulse")
    }

    private func resumeAnimations() {
        switch mode {
        case .indeterminate:
            if usesRotatingRainbow {
                if rotatingRainbowLayer.animation(forKey: Self.rotatingRainbowAnimationKey) == nil {
                    startRotatingRainbowAnimation()
                }
            } else if indeterminateLayer1.animation(forKey: "indeterminateScroll") == nil {
                startIndeterminateAnimation()
            }
        case .error:
            if errorLayer.animation(forKey: "errorPulse") == nil {
                startErrorPulseAnimation()
            }
        case .determinate, .ground, .pausedIndeterminate:
            break
        }
    }
}

// MARK: - CALayerDelegate

extension iTermProgressBarView: CALayerDelegate {
    // CALayerDelegate method to update sublayer frames appropriately.
    func layoutSublayers(of layer: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let width = layer.bounds.width
        let height = desiredHeight
        let size = CGSize(width: width, height: height)
        switch mode {
        case .error:
            errorLayer.frame = CGRect(x: 0, y: 0, width: width, height: height)
            if errorLayer.animation(forKey: "errorPulse") == nil {
                startErrorPulseAnimation()
            }
        case .indeterminate where usesRotatingRainbow:
            layoutRotatingRainbow(width: width, height: height)
            if rotatingRainbowLayer.animation(forKey: Self.rotatingRainbowAnimationKey) == nil {
                startRotatingRainbowAnimation()
            }
        case .indeterminate:
            indeterminateContainer.frame = CGRect(x: 0, y: 0, width: width, height: height)
            // Only update bounds and the vertical position, not position.x. The
            // horizontal position is driven by the scroll animation and setting
            // it here would create a competing implicit animation. The layers
            // are center-anchored, so position.y must track the container height
            // (otherwise a bounds change from a shorter setup, e.g. the 2pt
            // compact bar, leaves the layer centered too low and the top of a
            // taller bar/ring goes unfilled).
            indeterminateLayer1.bounds = CGRect(origin: .zero, size: size)
            indeterminateLayer2.bounds = CGRect(origin: .zero, size: size)
            indeterminateLayer1.position.y = height / 2.0
            indeterminateLayer2.position.y = height / 2.0
            if indeterminateLayer1.animation(forKey: "indeterminateScroll") == nil ||
                width != indeterminateAnimationWidth {
                startIndeterminateAnimation()
            }
        case .pausedIndeterminate:
            // Centered rather than frozen wherever the scrolling band happened
            // to be, so it looks deliberate instead of stuck.
            pausedLayer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        case let .determinate(success: success, percentage: percentage):
            let clamped = max(0, min(100, percentage))
            let progressWidth = width * CGFloat(clamped) / 100.0
            determinateLayer.frame = CGRect(x: 0, y: 0, width: progressWidth, height: height)
            updateDeterminateColors(success: success)
        case .ground:
            break
        }
        CATransaction.commit()
    }
}
