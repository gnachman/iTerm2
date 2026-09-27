//
//  iTermHDREngager.swift
//  iTerm2SharedARC
//
//  A tiny, invisible utility view whose job is to keep the display's extended
//  dynamic range engaged while this session's HDR cursor is enabled.
//
//  There is no ambient "reference EDR" on a standard display preset: content can
//  only exceed reference white (1.0) while some layer on screen has
//  wantsExtendedDynamicRangeContent set. That is how the legacy (drawRect:) HDR
//  cursor glows. Relying on the main Metal view for that engagement is fragile: it
//  is created and destroyed as the GPU renderer is toggled, and tearing down an
//  EDR-engaged Metal layer latches the window out of EDR entirely until relaunch.
//
//  This view holds a small CAMetalLayer with the flag set and presents 1x1
//  frames as needed to keep EDR engaged. Metal resources are created lazily only
//  while the HDR cursor is enabled and the display has headroom, and released
//  otherwise, so a session pays nothing until the feature is actually used.
import Cocoa
import Metal
import QuartzCore

@objc(iTermHDREngager)
class iTermHDREngager: NSView {
    private var metalLayer: CAMetalLayer?
    private var commandQueue: MTLCommandQueue?
    private var engaged = false
    // True while a presentFrames retry chain is in flight. Guards against the
    // several independent triggers (activation, window move, backing change,
    // occlusion, Metal-view teardown) starting overlapping chains.
    private var presenting = false

    // This session's per-profile HDR-cursor setting, set by SessionView. Flipping
    // it re-evaluates engagement. EDR is engaged while this is on, the display has
    // headroom, and the window is visible; see shouldEngage.
    @objc var enabled: Bool = false {
        didSet {
            if enabled != oldValue {
                reengage()
            }
        }
    }

    // EDR must be engaged for this session's HDR cursor. The terminal's fp16
    // framebuffer is gated separately (per-session); this just decides whether the
    // tiny keep-alive layer holds the panel in EDR.
    private var shouldEngage: Bool {
        return enabled
    }

    @objc(initWithFrame:)
    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        wantsLayer = true
        // App activation, GPU-renderer toggling, and a window becoming visible
        // again after being occluded/minimized can drop the display out of
        // extended range or make presenting possible again; re-assert on those.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reengage),
                                               name: NSApplication.didBecomeActiveNotification,
                                               object: nil)
        // A display can gain or lose EDR headroom in place when the user switches
        // its preset in System Settings. That need not change backing scale or
        // color space, so viewDidChangeBackingProperties may not fire; observe the
        // screen-parameters change directly so engagement tracks live capability.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reengage),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // Re-present so EDR is re-engaged if it was dropped, or release it if the HDR
    // cursor was turned off. Callable from ObjC (e.g. after the Metal view is torn
    // down).
    @objc func reengage() {
        engaged = false
        updateEngagement()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    // Never intercept events; this is a 1pt invisible utility view.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerWindowScopedObservers()
        reengage()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        reengage()
    }

    // Occlusion notifications are per-window and frequent (Space switches, another
    // app covering a window, minimize). Scoped to our own window they only wake
    // this session's engager instead of every session's on any window's change.
    // The screen-change notification catches a window dragged between two already
    // connected displays of the same size/scale/gamut, where the window's screen
    // gains or loses headroom but no backing-property change fires.
    private func registerWindowScopedObservers() {
        let center = NotificationCenter.default
        center.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        center.removeObserver(self, name: NSWindow.didChangeScreenNotification, object: nil)
        guard let window else {
            return
        }
        center.addObserver(self,
                           selector: #selector(reengage),
                           name: NSWindow.didChangeOcclusionStateNotification,
                           object: window)
        center.addObserver(self,
                           selector: #selector(reengage),
                           name: NSWindow.didChangeScreenNotification,
                           object: window)
    }

    // Presenting into a layer that is not being composited (window minimized,
    // fully occluded, or off-screen) is pointless and, worse, nextDrawable() can
    // block the main thread for up to ~1s once the drawable pool is exhausted
    // because presented drawables are never released. So only present while the
    // window is actually visible.
    private var windowIsVisible: Bool {
        guard let window, window.isVisible else {
            return false
        }
        return window.occlusionState.contains(.visible)
    }

    private func updateEngagement() {
        // Losing both HDR consumers (this session's cursor and the tab outline) is
        // the only condition that should actively return the panel to SDR; do that
        // by tearing the layer down.
        guard shouldEngage else {
            releaseEngagement()
            return
        }
        // Otherwise engage when we can. A windowless/occluded view or a display
        // without headroom is a no-op, NOT a release: dropping the layer here
        // would pull the whole screen out of EDR while another EDR-engaged view
        // (e.g. the Metal view) is momentarily detached during teardown.
        guard let window,
              window.screen?.it_hasEDRHeadroom() ?? false,
              windowIsVisible,
              !engaged else {
            return
        }
        ensureLayer()
        // Re-enable the flag: a prior releaseEngagement leaves the reused layer
        // with EDR off. Track the current display's gamut too, since the layer may
        // have been created on a different-gamut screen and ensureLayer is a no-op
        // once it exists.
        metalLayer?.wantsExtendedDynamicRangeContent = true
        metalLayer?.contentsScale = window.backingScaleFactor
        metalLayer?.colorspace = window.screen?.it_extendedDynamicRangeColorSpace()
        startPresenting()
    }

    private func releaseEngagement() {
        engaged = false
        presenting = false
        // Invalidate any in-flight retry chain: its pending closure will see a
        // newer generation and bail without touching shared state, so a fast
        // off/on toggle cannot leave two chains running against one layer.
        presentGeneration &+= 1
        guard let metalLayer else {
            return
        }
        // Disengage EDR by clearing the flag and committing one frame that reflects
        // it, rather than removing the layer. Tearing down an EDR-engaged
        // CAMetalLayer can latch the window out of EDR until relaunch (the exact
        // bug this class exists to prevent), so keep the tiny 1x1 layer alive for
        // reuse; updateEngagement re-enables the flag when a consumer returns.
        metalLayer.wantsExtendedDynamicRangeContent = false
        _ = present()
    }

    private func ensureLayer() {
        guard metalLayer == nil, let device = MTLCreateSystemDefaultDevice() else {
            return
        }
        commandQueue = device.makeCommandQueue()
        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .rgba16Float
        layer.framebufferOnly = false
        layer.isOpaque = false
        layer.wantsExtendedDynamicRangeContent = true
        // Match the display's gamut, like the real Metal view, rather than
        // hardcoding extended sRGB, so the two EDR-engaging layers agree.
        layer.colorspace = window?.screen?.it_extendedDynamicRangeColorSpace()
        layer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        layer.drawableSize = CGSize(width: 1, height: 1)
        self.layer?.addSublayer(layer)
        metalLayer = layer
    }

    private static let framesBeforeLatching = 3
    private static let maxPresentAttempts = 30
    // Bumped each time a chain starts or the layer is released, so a stale
    // scheduled closure can tell it has been superseded.
    private var presentGeneration = 0

    private func startPresenting() {
        guard !presenting else {
            return
        }
        presenting = true
        presentGeneration &+= 1
        presentFrames(generation: presentGeneration,
                      successesRemaining: Self.framesBeforeLatching,
                      attemptsRemaining: Self.maxPresentAttempts)
    }

    // We cannot poll current headroom to confirm engagement: on a reference-mode
    // XDR display maximumExtendedDynamicRangeColorComponentValue stays 1.0 even
    // while EDR content displays, so there is no verification signal. A single
    // commit from a just-added layer also does not prove the layer is composited
    // or that EDR latched. So present a few frames across separate runloop turns
    // (giving the compositor time to bring the layer live) before latching, and
    // retry across turns while present() fails because no drawable is ready yet.
    private func presentFrames(generation: Int, successesRemaining: Int, attemptsRemaining: Int) {
        // A newer chain (or a release) superseded us; leave shared state to it.
        guard generation == presentGeneration else {
            return
        }
        guard !engaged,
              shouldEngage,
              windowIsVisible,
              window?.screen?.it_hasEDRHeadroom() ?? false,
              metalLayer != nil else {
            presenting = false
            return
        }
        let successesLeft = present() ? successesRemaining - 1 : successesRemaining
        if successesLeft <= 0 {
            engaged = true
            presenting = false
            return
        }
        // Fast burst first (attemptsRemaining > 0). If the layer still is not
        // presentable afterward (e.g. a slow compositor right after launch or
        // session restore), fall back to a slow perpetual retry rather than giving
        // up: the natural re-triggers (activation, occlusion, screen changes) may
        // never come while the user just sits in the window, and the guards above
        // stop the chain the moment it engages or the window/headroom/settings
        // change. Log the transition once so field debug logs show a stuck engage.
        let fastPhase = attemptsRemaining > 0
        if attemptsRemaining == 1 {
            DLog("HDR engager still not engaged after fast present burst; falling back to slow retry")
        }
        let delay: TimeInterval = fastPhase ? 0.1 : 1.0
        let nextAttempts = fastPhase ? attemptsRemaining - 1 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.presentFrames(generation: generation,
                                successesRemaining: successesLeft,
                                attemptsRemaining: nextAttempts)
        }
    }

    private func present() -> Bool {
        guard windowIsVisible,
              let commandQueue, let metalLayer, let drawable = metalLayer.nextDrawable() else {
            return false
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return false
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        return true
    }
}
