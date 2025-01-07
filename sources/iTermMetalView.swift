//
//  iTermMetalView.swift
//  iTerm2
//
//  Created by George Nachman on 12/20/24.
//

import AppKit
import QuartzCore
import Metal

/// Delegate protocol for handling view rendering and resizing
@objc public protocol iTermMetalViewDelegate: AnyObject {
    func metalView(_ view: iTermMetalView, drawableSizeWillChange size: CGSize)

    @objc(drawInMetalView:)
    func draw(in view: iTermMetalView)
}

/// Custom MetalKit-like view for rendering Metal content. This is a stripped-down version of `iTermMetalView_full` containing
/// only useful code paths for iTerm2. It is more or less tested and works.
@objc(iTermMetalView)
public class iTermMetalView: NSView, CALayerDelegate {
    private var metalLayer: CAMetalLayer? = nil
    private var frameInterval: Int = 0
    private var sizeDirty: Bool = false
    private var drawableScaleFactor: CGSize = .zero
    private var displayLink: CVDisplayLink?
    private var currentInterval: Int = 0
    private var displaySource: DispatchSourceUserDataAdd?
    private static var drawRectSuperIMP: IMP?
    private var drawRectSubIMP: IMP?
    private var subClassOverridesDrawRect: Bool = false
    private var doesNotifyOnRecommendedSizeUpdate: Bool = false
    private var _drawableAttachmentIndex = 0
    private var drawableAttachmentIndex: Int {
        set {
            if newValue <= 7 {
                _drawableAttachmentIndex = newValue
            }
        }
        get {
            _drawableAttachmentIndex
        }
    }

    // Evenly divides hardware refresh rate, based on preferredFramesPerSecond.
    private var nominalFramesPerSecond: Int = 0
    private var maxValidAttachmentIndex: Int = 0
    private var colorPixelFormats = [MTLPixelFormat](repeating: .invalid, count: 8)
    private var _colorTextures = [MTLTexture?](repeating: nil, count: 8)
    private var colorTextures: [MTLTexture?]? {
        colorTexturesForceUpdate(false)
    }
    private var drawableIdx: UInt = 0
    private struct DirtyState: OptionSet {
        static let colorTexturesDirty = DirtyState(rawValue: 0x1)

        let rawValue: Int
    }
    private var renderAttachmentDirtyState: DirtyState = []
    private var frameNum: UInt32 = 0

    // MARK: - Properties

    @objc
    public weak var delegate: iTermMetalViewDelegate?

    private var _device: MTLDevice?

    @objc
    var device: MTLDevice? {
        set {
            if newValue === metalLayer?.device {
                return
            }
            metalLayer?.device = newValue
            renderAttachmentDirtyState.insert(.colorTexturesDirty)
        }
        get {
            _device
        }
    }
    private var _currentDrawable: CAMetalDrawable?
    private class PendingDrawable {
        let drawable: CAMetalDrawable?
        let context: LayerContext
        init(_ context: LayerContext, drawable: CAMetalDrawable?) {
            self.drawable = drawable
            self.context = context
        }
    }
    private var pendingDrawablePromise: iTermPromise<PendingDrawable>?
    private static let getDrawableQueue = DispatchQueue(label: "com.iterm2.get-drawable")

    private struct LayerContext: Equatable {
        static func == (lhs: iTermMetalView.LayerContext, rhs: iTermMetalView.LayerContext) -> Bool {
            return (lhs.device === rhs.device &&
                    lhs.framebufferOnly == rhs.framebufferOnly &&
                    lhs.presentsWithTransaction == rhs.presentsWithTransaction &&
                    lhs.pixelFormat == rhs.pixelFormat &&
                    lhs.colorspace === rhs.colorspace &&
                    lhs.size == rhs.size)
        }
        
        weak var device: MTLDevice?
        var framebufferOnly: Bool
        var presentsWithTransaction: Bool
        var pixelFormat: MTLPixelFormat
        var colorspace: CGColorSpace?
        var size: CGSize
    }

    private func layerContext(metalLayer: CAMetalLayer) -> LayerContext {
        LayerContext(device: metalLayer.device,
                     framebufferOnly: metalLayer.framebufferOnly,
                     presentsWithTransaction: metalLayer.presentsWithTransaction,
                     pixelFormat: metalLayer.pixelFormat,
                     colorspace: metalLayer.colorspace,
                     size: metalLayer.drawableSize)
    }

    private func fetchDrawable(timeout: TimeInterval) -> CAMetalDrawable? {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let metalLayer else {
            return nil
        }
        metalLayer.allowsNextDrawableTimeout = false

        let context = layerContext(metalLayer: metalLayer)
        var timedOut = false
        while !timedOut {
            let promise = pendingDrawablePromise ?? iTermPromise<PendingDrawable> { seal in
                Self.getDrawableQueue.async {
                    seal.fulfill(PendingDrawable(context, drawable: metalLayer.nextDrawable()))
                }
            }
            var result: CAMetalDrawable?
            DLog("Will wait for promise")
            promise.wait(withTimeout: timeout).whenFirst { pending in
                DLog("Promise fulfilled")
                if pending.context == context {
                    result = pending.drawable
                }
                pendingDrawablePromise = nil
            } second: { err in
                DLog("Promise rejected")
                precondition(err.code == iTermPromiseErrorCode.timeout.rawValue)
                pendingDrawablePromise = promise
                timedOut = true
            }
            // If result is not nil, then it is valid and should be returned.
            // If result is nil then either there was a timeout or the drawable was not usable (e.g., wrong size).
            if let result {
                DLog("Returning valid drawable")
                return result
            }
        }
        DLog("Return nil because of timeout")
        return nil
    }

    @objc
    func currentDrawable(timeout: TimeInterval) -> CAMetalDrawable? {
        if let _currentDrawable {
            return _currentDrawable
        }
        _currentDrawable = fetchDrawable(timeout: timeout)
        return _currentDrawable
    }

    @objc
    var currentDrawable: CAMetalDrawable? {
        get {
            currentDrawable(timeout: .infinity)
        }
    }

    private var _framebufferOnly = true

    @objc
    public var framebufferOnly: Bool {
        get {
            _framebufferOnly = false
            return metalLayer?.framebufferOnly ?? false
        }
        set {
            _framebufferOnly = newValue
            metalLayer?.framebufferOnly = newValue
        }
    }

    @objc
    public var presentsWithTransaction: Bool {
        get {
            metalLayer?.presentsWithTransaction ?? false
        }
        set {
            metalLayer?.presentsWithTransaction = newValue
        }
    }

    @objc
    public var colorPixelFormat: MTLPixelFormat {
        set {
            setColorPixelFormat(newValue, atIndex: _drawableAttachmentIndex)
        }
        get {
            colorPixelFormats[_drawableAttachmentIndex]
        }
    }

    private func setColorPixelFormat(_ format: MTLPixelFormat, atIndex index: Int) {
        guard index < 8 else {
            return
        }

        colorPixelFormats[index] = format
        renderAttachmentDirtyState.insert(.colorTexturesDirty)
        if _drawableAttachmentIndex == index {
            metalLayer?.pixelFormat = format
        }
        if format != .invalid {
            if maxValidAttachmentIndex < index {
                maxValidAttachmentIndex = index
            }
            return
        }
        if maxValidAttachmentIndex != index {
            return
        }
        if let i = colorPixelFormats.lastIndex(where: { $0 != .invalid }) {
            maxValidAttachmentIndex = i
        }
    }

    @objc
    public var clearColor: MTLClearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)

    @objc
    public func display(_ layer: CALayer) {
        if !_enableSetNeedsDisplay {
            return
        }
        displaySource?.add(data: 1)
    }

    @objc(drawLayer:inContext:)
    public func draw(_ layer: CALayer, in context: CGContext) {
        if _enableSetNeedsDisplay {
            display(layer)
        }
    }

    func drawNumber() -> UInt32 {
        frameNum
    }

    @objc
    public func currentRenderPassDescriptor(timeout: TimeInterval) -> MTLRenderPassDescriptor? {
        guard currentDrawable(timeout: timeout) != nil else {
            return nil
        }
        let descriptor = MTLRenderPassDescriptor()
        _ = colorTextures
        for i in 0...maxValidAttachmentIndex {
            descriptor.colorAttachments[i].texture = _colorTextures[i]!
            descriptor.colorAttachments[i].loadAction = .clear
            descriptor.colorAttachments[i].clearColor = clearColor
        }
        return descriptor
    }

    @objc
    public var currentRenderPassDescriptor: MTLRenderPassDescriptor? {
        return currentRenderPassDescriptor(timeout: .infinity)
    }

    private var _preferredFramesPerSecond = 60

    @objc
    public var preferredFramesPerSecond: Int {
        get {
            _preferredFramesPerSecond
        }
        set {
            _preferredFramesPerSecond = newValue
            if _preferredFramesPerSecond <= 0 {
                _preferredFramesPerSecond = 1
                paused = true
            }
            let refreshesPerSecond = calculateRefreshesPerSecond()
            let ratio = Int(ceil(Double(refreshesPerSecond) / Double(_preferredFramesPerSecond)))
            frameInterval = ratio
            nominalFramesPerSecond = refreshesPerSecond / ratio
        }
    }

    private var _enableSetNeedsDisplay: Bool = false

    @objc
    public var enableSetNeedsDisplay: Bool {
        get {
            _enableSetNeedsDisplay
        }
        set {
            _enableSetNeedsDisplay = newValue
            if newValue {
                paused = true
            }
        }
    }

    @objc
    public var autoResizeDrawable: Bool = true

    private var _drawableSize = CGSize.zero

    @objc
    public var drawableSize: CGSize {
        get {
            _drawableSize
        }
        set {
            if newValue == _drawableSize {
                return
            }

            let myBounds = bounds
            let screen = window?.screen
            let backingScaleFactor = if let screen {
                screen.backingScaleFactor
            } else {
                NSScreen.main?.backingScaleFactor ?? 0
            }
            drawableScaleFactor = CGSize(width: newValue.width / (myBounds.width * backingScaleFactor),
                                         height: newValue.height / (myBounds.height * backingScaleFactor))
            delegate?.metalView(self, drawableSizeWillChange: newValue)
            _drawableSize = newValue
            sizeDirty = true
        }
    }

    @objc
    public var paused: Bool = false {
        didSet {
            if paused {
                if let displayLink {
                    CVDisplayLinkStop(displayLink)
                }
            } else {
                if let displayLink {
                    CVDisplayLinkStart(displayLink)
                }
            }
        }
    }

    @objc
    public var colorspace: CGColorSpace? {
        get {
            metalLayer?.colorspace
        }
        set {
            metalLayer?.colorspace = newValue
        }
    }

    @objc
    public var preferredDrawableSize: CGSize {
        doesNotifyOnRecommendedSizeUpdate = true
        return super._recommendedDrawableSize()
    }

    @objc
    public var preferredDevice: MTLDevice? {
        metalLayer?.preferredDevice
    }

    // MARK: - Initializers

    public override convenience init(frame frameRect: CGRect) {
        self.init(frame: frameRect, device: nil)
    }

    override public func encode(with coder: NSCoder) {
        super.encode(with: coder)

        // Encode maxValidAttachmentIndex + 1
        let (indexPlusOne, overflow) = maxValidAttachmentIndex.addingReportingOverflow(1)
        coder.encode(indexPlusOne, forKey: "MTKViewNumberColorPixelFormatsCoderKey")

        // Allocate memory for attachments if valid
        var buffer = [MTLPixelFormat](repeating: .invalid, count: indexPlusOne)

        if !overflow {  // if overflow goto loc_1933e5e1c
            buffer = colorPixelFormats
        }
        buffer.withUnsafeBufferPointer { buffer in
            coder.encodeBytes(buffer.baseAddress, length: buffer.count * MemoryLayout<MTLPixelFormat>.stride, forKey: "MTKViewColorPixelFormatArrayCoderKey")
        }
        coder.encode(drawableAttachmentIndex, forKey: "MTKViewDrawableAttachmentIndexCoderKey")
        coder.encode(colorPixelFormat, forKey: "MTKViewColorPixelFormatCoderKey")
        let clearColorData = withUnsafeBytes(of: clearColor) { bytes in
            Data(bytes: bytes.baseAddress!, count: MemoryLayout<MTLClearColor>.size)
        }
        coder.encode(clearColorData, forKey: "MTKViewClearColorCoderKey")
        coder.encode(_preferredFramesPerSecond, forKey: "MTKViewPreferredFramesPerSecondCoderKey")
        coder.encode(_enableSetNeedsDisplay, forKey: "MTKViewEnableSetNeedsDisplayCoderKey")
        coder.encode(paused, forKey: "MTKViewPausedCoderKey")
        coder.encode(metalLayer?.framebufferOnly ?? false, forKey: "MTKViewFramebufferOnlyCoderKey")
        coder.encode(metalLayer?.presentsWithTransaction ?? false, forKey: "MTKViewPresentsWithTransactionCoderKey")
        coder.encode(autoResizeDrawable, forKey: "MTKViewAutoResizeDrawableCoderKey")
    }

    @objc
    public init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect)
        _device = device
        initCommon()
    }

    @objc
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        device = nil
        initCommon()
        if coder.containsValue(forKey: "MTKViewNumberColorPixelFormatsCoderKey") {
            maxValidAttachmentIndex = coder.decodeInteger(forKey: "MTKViewNumberColorPixelFormatsCoderKey") - 1
        }
        if coder.containsValue(forKey: "MTKViewColorPixelFormatArrayCoderKey") {
            var length = 0
            let bytes = coder.decodeBytes(forKey: "MTKViewColorPixelFormatArrayCoderKey", returnedLength: &length)
            precondition(length == maxValidAttachmentIndex * 8)
            let formats = stride(from: 0, to: length, by: MemoryLayout<MTLPixelFormat>.stride).map { offset -> MTLPixelFormat in
                guard let valuePointer = UnsafeRawPointer(bytes)?.advanced(by: offset).assumingMemoryBound(to: MTLPixelFormat.RawValue.self) else {
                    return .invalid
                }
                return MTLPixelFormat(rawValue: valuePointer.pointee) ?? .invalid
            }
            if length > 0 {
                for x23 in 0...maxValidAttachmentIndex {
                    setColorPixelFormat(formats[x23], atIndex: x23)
                }
            }
        }
        if coder.containsValue(forKey: "MTKViewDrawableAttachmentIndexCoderKey") {
            drawableAttachmentIndex = coder.decodeInteger(forKey: "MTKViewDrawableAttachmentIndexCoderKey")
        }
        if coder.containsValue(forKey: "MTKViewColorPixelFormatCoderKey") {
            colorPixelFormat = MTLPixelFormat(rawValue: UInt(coder.decodeInteger(forKey: "MTKViewColorPixelFormatCoderKey"))) ?? .invalid
        }
        if coder.containsValue(forKey: "MTKViewClearColorCoderKey") {
            let data = coder.decodeObject(forKey: "MTKViewClearColorCoderKey") as! Data

            clearColor = data.withUnsafeBytes({ buffer in
                buffer.load(as: MTLClearColor.self)
            })
        }
        if coder.containsValue(forKey: "MTKViewFramebufferOnlyCoderKey") {
            framebufferOnly = coder.decodeBool(forKey: "MTKViewFramebufferOnlyCoderKey")
        }

        if coder.containsValue(forKey: "MTKViewPresentsWithTransactionCoderKey") {
            presentsWithTransaction = coder.decodeBool(forKey: "MTKViewPresentsWithTransactionCoderKey")
        }
        if coder.containsValue(forKey: "MTKViewPreferredFramesPerSecondCoderKey") {
            preferredFramesPerSecond = coder.decodeInteger(forKey: "MTKViewPreferredFramesPerSecondCoderKey")
        }
        if coder.containsValue(forKey: "MTKViewEnableSetNeedsDisplayCoderKey") {
            enableSetNeedsDisplay = coder.decodeBool(forKey: "MTKViewEnableSetNeedsDisplayCoderKey")
        }
        if coder.containsValue(forKey: "MTKViewPausedCoderKey") {
            paused = coder.decodeBool(forKey: "MTKViewPausedCoderKey")
        }
        if coder.containsValue(forKey: "MTKViewAutoResizeDrawableCoderKey") {
            autoResizeDrawable = coder.decodeBool(forKey: "MTKViewAutoResizeDrawableCoderKey")
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let displayLink {
            CVDisplayLinkStop(displayLink)
            displaySource?.cancel()
        }
    }

    // MARK: - Methods

    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if autoResizeDrawable {
            resizeDrawable()
        }
    }

    override static public func keyPathsForValuesAffectingValue(forKey key: String) -> Set<String> {
        var paths = super.keyPathsForValuesAffectingValue(forKey: key)
        if key == "preferredDrawableSize" {
            paths.insert("_recommendedDrawableSize")
        }
        return paths
    }

    @objc static func layerClass() -> AnyClass {
        return CAMetalLayer.self
    }

    @objc
    public func releaseDrawables() {
    }

    private func callDrawRectIMP(on target: AnyObject, with rect: CGRect, imp: IMP) {
        // Define the function type for the -drawRect: method
        typealias DrawRectFunction = @convention(c) (AnyObject, Selector, CGRect) -> Void

        // Cast the IMP to the correct function type
        let drawRect = unsafeBitCast(imp, to: DrawRectFunction.self)

        // Call the function
        drawRect(target, #selector(NSView.draw(_:)), rect)
    }

    @objc
    public func draw() {
        frameNum += 1
        if !paused {
            guard it_canDraw else { return }
            currentInterval += 1
            guard currentInterval >= frameInterval else { return }
            currentInterval = 0
        }
        resizeMetalLayerDrawable()
        if subClassOverridesDrawRect {
            callDrawRectIMP(on: self, with: bounds, imp: drawRectSubIMP!)
        } else {
            delegate?.draw(in: self)
        }

        _currentDrawable = nil
        _colorTextures[Int(_drawableAttachmentIndex)] = nil
    }

    // MARK: - Private Methods

    open override func addObserver(_ observer: NSObject, forKeyPath keyPath: String, options: NSKeyValueObservingOptions, context: UnsafeMutableRawPointer?) {
        if keyPath == "preferredDrawableSize" {
            if !doesNotifyOnRecommendedSizeUpdate {
                _recommendedDrawableSize()  // private method in NSView. I think we just call this to set the associated object. Kinda weird.
                doesNotifyOnRecommendedSizeUpdate = true
            }
        }
        super.addObserver(observer, forKeyPath: keyPath, options: options, context: context)
    }

    open override func convertFromBacking(_ point: CGPoint) -> CGPoint {
        let converted = super.convertFromBacking(point)
        let scale = drawableScaleFactor
        return CGPoint(x: converted.x / scale.width, y: converted.y / scale.height)
    }

    open override func convertToBacking(_ point: CGPoint) -> CGPoint {
        let converted = super.convertToBacking(point)
        let scale = drawableScaleFactor
        return CGPoint(x: converted.x * scale.width, y: converted.y * scale.height)
    }

    open override func convertFromBacking(_ size: CGSize) -> CGSize {
        let converted = super.convertFromBacking(size)
        let scale = drawableScaleFactor
        return CGSize(width: converted.width / scale.width, height: converted.height / scale.height)
    }

    open override func convertToBacking(_ size: CGSize) -> CGSize {
        let converted = super.convertToBacking(size)
        let scale = drawableScaleFactor
        return CGSize(width: converted.width * scale.width, height: converted.height * scale.height)
    }

    open override func setBoundsSize(_ size: CGSize) {
        super.setBoundsSize(size)
        if autoResizeDrawable {
            resizeDrawable()
        }
    }

    open override func setNilValueForKey(_ key: String) {
        if key == "clearColor" {
            clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        } else {
            super.setNilValueForKey(key)
        }
    }

    open override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()

        if autoResizeDrawable {
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                self.resizeDrawable()
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
    }

    open override func viewDidMoveToWindow() {
        updateToNativeScale()
    }

    // MARK:- Private methods

    private func initCommon() {
        drawableScaleFactor = CGSize(width: 1.0, height: 1.0)
        wantsLayer = true
        metalLayer = CAMetalLayer()
        layer = metalLayer
        layerContentsRedrawPolicy = .duringViewResize
        paused = false
        renderAttachmentDirtyState = [DirtyState.colorTexturesDirty]

        colorPixelFormats = [.invalid, .invalid, .invalid, .invalid, .invalid, .invalid, .invalid, .invalid]
        _colorTextures = [nil, nil, nil, nil, nil, nil, nil, nil]
        _drawableAttachmentIndex = 0
        maxValidAttachmentIndex = 0
        colorPixelFormat = .bgra8Unorm
        metalLayer?.device = _device
        metalLayer?.delegate = self
        metalLayer?.framebufferOnly = true
        _framebufferOnly = true
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        _enableSetNeedsDisplay = false
        displaySource = DispatchSource.makeUserDataAddSource(queue: DispatchQueue.main)
        displaySource?.setEventHandler(handler: DispatchWorkItem(block: { [weak self] in
            self?.draw()
        }))
        displaySource?.resume()
        createCVDisplayLink()
        if Self.drawRectSuperIMP == nil {
            Self.drawRectSuperIMP =  NSView.instanceMethod(for: #selector(draw(_:)))
        }
        if responds(to: #selector(draw(_:))) {
            // This is unreachable unless something crazy is done since NSView implements it.
            drawRectSubIMP = method(for: #selector(draw(_:)))
        }
        subClassOverridesDrawRect = (drawRectSubIMP != nil && drawRectSubIMP != Self.drawRectSuperIMP)
        autoResizeDrawable = true
        resizeDrawable()
    }

    private func createCVDisplayLink() {
        if displayLink == nil {
            if CVDisplayLinkCreateWithActiveCGDisplays(&displayLink) == 0 {
                if let displayLink,
                   let displaySource,
                   CVDisplayLinkSetOutputCallback(displayLink, DisplayLinkCallback, Unmanaged.passUnretained(displaySource).toOpaque()) == 0 {
                    if CVDisplayLinkSetCurrentCGDisplay(displayLink, CGMainDisplayID()) ==  kCVReturnSuccess {
                        CVDisplayLinkStart(displayLink)
                        NotificationCenter.default.addObserver(self, selector: #selector(_windowWillClose(_:)), name: NSWindow.willCloseNotification, object: window)
                        preferredFramesPerSecond = 60
                        return
                    }
                }
            }
        }
        displayLink = nil
        return
    }

    private func pixelSize(fromPointSize pointSize: CGSize) -> CGSize {
        let converted = convertToBacking(pointSize)
        return CGSize(width: converted.width.rounded(.toNearestOrAwayFromZero),
                      height: converted.height.rounded(.toNearestOrAwayFromZero))
    }

    private func resizeDrawable() {
        let newPixelSize = pixelSize(fromPointSize: bounds.size)
        if newPixelSize != drawableSize {
            if let delegate {
                withExtendedLifetime(delegate) {
                    delegate.metalView(self, drawableSizeWillChange: newPixelSize)
                }
            }
            _drawableSize = newPixelSize
            sizeDirty = true
        }
    }

    private func resizeMetalLayerDrawable() {
        guard sizeDirty else {
            return
        }

        metalLayer?.drawableSize = drawableSize
        renderAttachmentDirtyState.insert(.colorTexturesDirty)

        sizeDirty = false
    }

    private func updateToNativeScale() {
        guard autoResizeDrawable, let screen = window?.screen else {
            return
        }
        metalLayer?.contentsScale = screen.backingScaleFactor
    }

    @objc private func _windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else {
            return
        }
        if let displayLink {
            CVDisplayLinkStop(displayLink)
        }
        displaySource?.cancel()
    }

    private func calculateRefreshesPerSecond() -> Int {
        if let displayLink {
            let cvtime = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(displayLink)
            return Int(round(Double(cvtime.timeScale) / Double(cvtime.timeValue)))
        } else {
            return 60
        }
    }

    private func colorTexturesForceUpdate(_ force: Bool) -> [MTLTexture?]? {
        guard let device else {
            return nil
        }

        if let drawable = currentDrawable {
            _colorTextures[_drawableAttachmentIndex] = drawable.texture
        }

        guard renderAttachmentDirtyState.contains(.colorTexturesDirty) else {
            return _colorTextures
        }
        for i in 0...maxValidAttachmentIndex {
            if _drawableAttachmentIndex == i {
                break
            }

            if !force,
               let colorTexture = _colorTextures[i],
               metalLayer?.drawableSize.width == CGFloat(colorTexture.width),
               metalLayer?.drawableSize.height == CGFloat(colorTexture.height),
               colorTexture.pixelFormat == colorPixelFormats[i],
               colorTexture.usage == .renderTarget {
                break
            }
            let newTexture: MTLTexture?
            if colorPixelFormats[i] != .invalid {
                // I'm not 100% sure this is the right runloop mode.
                CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                    self.resizeDrawable()
                }
                CFRunLoopWakeUp(CFRunLoopGetMain())
                resizeMetalLayerDrawable()
                let drawableSize = metalLayer?.drawableSize ?? CGSize.zero
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: colorPixelFormats[i],
                                                                          width: Int(drawableSize.width),
                                                                          height: Int(drawableSize.height),
                                                                          mipmapped: false)

                descriptor.usage = .renderTarget
                descriptor.storageMode = .private
                newTexture = device.makeTexture(descriptor: descriptor)
            } else {
                newTexture = nil
            }
            _colorTextures[i] = newTexture
        }

        renderAttachmentDirtyState.remove(.colorTexturesDirty)
        return _colorTextures
    }
}

fileprivate func DisplayLinkCallback(displayLink: CVDisplayLink,
                                        inNow: UnsafePointer<CVTimeStamp>,
                                        inOutputTime: UnsafePointer<CVTimeStamp>,
                                        flagsIn: CVOptionFlags,
                                        flagsOut: UnsafeMutablePointer<CVOptionFlags>,
                                        displayLinkContext: UnsafeMutableRawPointer?) -> CVReturn {
    guard let context = displayLinkContext else {
        return kCVReturnError
    }

    let unmanagedDisplaySource = Unmanaged<DispatchSourceUserDataAdd>.fromOpaque(context)
    let displaySource = unmanagedDisplaySource.takeUnretainedValue()

    displaySource.add(data: 1)
    return kCVReturnSuccess
}

extension CAMetalLayer: @unchecked @retroactive Sendable {}
