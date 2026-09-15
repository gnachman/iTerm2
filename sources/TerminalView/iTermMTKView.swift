//
//  iTermMetalView.swift
//  iTerm2
//
//  Created by George Nachman on 12/26/24.
//

@objc
public class iTermMTKView: iTermMetalView {
    private var _timer: Timer?
    private var _lastSetNeedsDisplay: TimeInterval = 0

    // How often to keep an ordered-out or fully occluded window's Metal pipeline warm. Matches the
    // 1 Hz background update cadence (kBackgroundUpdateCadence) that hidden sessions already tick at.
    private static let occludedRedrawPeriod: TimeInterval = 1.0

    @objc(initWithFrame:device:)
    override init(frame: NSRect, device: MTLDevice?) {
        super.init(frame: frame, device: device)
        // The drawable's pixel format is controlled by the CAMetalLayer's
        // pixelFormat (set via enableHDR), not colorPixelFormat, so nothing to set
        // here.
        // Timer is scheduled in viewDidMoveToWindow; a detached view shouldn't wake up.
        // A display can gain or lose EDR headroom in place (preset switch in
        // System Settings) without changing backing scale or color space, so
        // viewDidChangeBackingProperties may not fire; observe screen-parameter
        // changes directly so the layer's EDR flag and color space stay in sync.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(screenParametersChanged),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
    }

    @MainActor required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    deinit {
        _timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func screenParametersChanged() {
        refreshHDRLayerState()
    }

    override public var alphaValue: CGFloat {
        set {
            super.alphaValue = newValue
            DLog("Set alpha value of \(self) to \(newValue) from \(Thread.callStackSymbols)")
        }
        get {
            super.alphaValue
        }
    }
    private func it_schedule() {
        _timer = Timer.it_scheduledWeakTimer(
            withTimeInterval: iTermAdvancedSettingsModel.metalRedrawPeriod(),
            target: self,
            selector: #selector(it_redrawPeriodically(_:)),
            userInfo: nil,
            repeats: true)
    }

    @objc
    private func it_redrawPeriodically(_ timer: Timer) {
        DLog("Timer with interval \(timer.timeInterval) fired for MTKView under \(superview.d) in window \(window.d)")

        if (isHidden || alphaValue < 0.01 || bounds.size.width == 0 || bounds.size.height == 0 || window == nil) {
            DLog("Not visible \(self)")
            return;
        }
        if (round(1000 * timer.timeInterval) != round(1000 * iTermAdvancedSettingsModel.metalRedrawPeriod()))  {
            DLog("Recreate timer");
            _timer?.invalidate()
            _timer = nil
            it_schedule()
        }
        // An ordered-out or fully occluded window (e.g. a hidden hotkey window) can't be seen, but a
        // cold Metal pipeline hitches on its first draw after a period of inactivity, which is very
        // visible the moment the window is revealed. Keep it warm at the slow occludedRedrawPeriod
        // instead of stopping entirely so the content is fresh and the pipeline is warm on reveal.
        let occluded = window?.occlusionState.contains(.visible) != true
        let minInterval = occluded ? max(Self.occludedRedrawPeriod, iTermAdvancedSettingsModel.metalRedrawPeriod())
                                   : timer.timeInterval
        if (NSDate.it_timeSinceBoot() - _lastSetNeedsDisplay < minInterval) {
            DLog("Redrew recently");
            return;
        }
        needsDisplay = true
    }

    override public var needsDisplay: Bool {
        set {
            DLog("setNeedsDisplay:\(needsDisplay)")
            if newValue {
                _lastSetNeedsDisplay = NSDate.it_timeSinceBoot()
            }
            super.needsDisplay = newValue
        }
        get {
            super.needsDisplay
        }
    }

    // This session's per-profile HDR-cursor setting. Set by SessionView. Gates EDR
    // engagement (and, at driver-build time, the fp16 pixel format). Changing it
    // updates the layer's EDR flag/color space live; the pixel format change is
    // handled by rebuilding the driver.
    @objc var wantsHDR: Bool = false {
        didSet {
            if wantsHDR != oldValue {
                refreshHDRLayerState()
            }
        }
    }

    // Whether to actually engage EDR: this session's HDR cursor is on AND the
    // display has real headroom. The pixel format is fp16 whenever wantsHDR is on
    // (it must match the cached pipeline states, which are built from the same
    // flag), but EDR engagement is additionally headroom-gated so a no-headroom
    // display is not needlessly pushed toward EDR and keeps its calibrated color
    // space.
    private var wantsEDR: Bool {
        guard wantsHDR, let screen = window?.screen else {
            return false
        }
        return screen.it_hasEDRHeadroom()
    }

    // The color space the metal layer should use. The HDR cursor needs an
    // extended-range color space or the compositor clamps its boosted white to
    // reference white. Only substitute the extended space when EDR is engaged, so
    // an SDR display keeps its own (calibrated) color space. The shared helper
    // matches the display's gamut (extended Display P3 vs extended sRGB) so a
    // wide-gamut display's color reproduction is not shifted.
    private var preferredColorspace: CGColorSpace? {
        let screenColorspace = window?.screen?.colorSpace?.cgColorSpace
        guard wantsEDR, let screen = window?.screen else {
            return screenColorspace
        }
        return screen.it_extendedDynamicRangeColorSpace() ?? screenColorspace
    }

    // Keep the layer's EDR flag and color space in sync with the current display.
    private func refreshHDRLayerState() {
        colorspace = preferredColorspace
        wantsExtendedDynamicRangeContent = wantsEDR
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshHDRLayerState()
        if window != nil {
            if _timer == nil {
                it_schedule()
            }
        } else {
            _timer?.invalidate()
            _timer = nil
        }
    }

    @objc(enclosingWindowDidMoveToScreen:)
    func enclosingWindowDidMove(to screen: NSScreen?) {
        refreshHDRLayerState()
    }

    override public func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // A display can change gamut or HDR mode in place (without the window
        // moving to a different screen), so recompute here too.
        refreshHDRLayerState()
    }

    @objc
    override public var colorspace: CGColorSpace? {
        set {
            RLog("Set colorspace of \(self) to \(String(describing: newValue))")
            super.colorspace = newValue
        }
        get {
            super.colorspace
        }
    }
}
