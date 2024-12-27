//
//  iTermMetalView.swift
//  iTerm2
//
//  Created by George Nachman on 12/20/24.
//

import AppKit
import QuartzCore
import Metal

// https://developer.limneos.net/?ios=13.1.3&framework=MetalKit.framework&header=MTKOffscreenDrawable.h
class iTermOffscreenDrawable: NSObject, MTLDrawable, CAMetalDrawable {
    var drawableID: Int { _drawableID }

    var texture: MTLTexture { _texture! }

    private var _texture: MTLTexture? = nil
    private var _pixelFormat: MTLPixelFormat = .invalid
    private var _size: CGSize = .zero
    private var _textureDirty: Bool = false
    private var _layer: CAMetalLayer?
    private var _presentedTime: Double = 0.0
    private var _drawableID: Int = 0
    private var _device: MTLDevice?

    var device: MTLDevice {
        get { _device! }
        set { _device = newValue }
    }
    var presentedTime: Double { _presentedTime }
    var layer: CAMetalLayer { _layer! }
    var size: CGSize {
        get { _size }
        set { _size = newValue }
    }
    var pixelFormat: MTLPixelFormat {
        get { _pixelFormat }
        set { _pixelFormat = newValue }
    }

    func addPresentedHandler(_ handler: @escaping (() -> ())) {
        // TODO
    }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat, size: CGSize, drawableID: UInt) {
        // TODO
    }

    func present() {
        // TODO
    }

    func present(at presentationTime: CFTimeInterval) {
        // TODO
    }

    func present(afterMinimumDuration duration: CFTimeInterval) {
        // TODO
    }

    func addPresentedHandler(_ block: @escaping MTLDrawablePresentedHandler) {
        // TODO
    }
}

// This is the full implementation based on MTKView, but it's not thoroughly tested and certainly
// contains bugs.
@objc(iTermMetalView)
public class iTermMetalView_Full: NSView, CALayerDelegate {
    var metalLayer: CAMetalLayer? = nil
    var frameInterval: Int = 0
    var sizeDirty: Bool = false
    var drawableScaleFactor: CGSize = .zero
    var displayLink: CVDisplayLink?
    var currentInterval: Int = 0
    var displaySource: DispatchSourceUserDataAdd?
    static var drawRectSuperIMP: IMP?
    var drawRectSubIMP: IMP?
    var subClassOverridesDrawRect: Bool = false
    var deviceReset: Bool = false
    var doesNotifyOnRecommendedSizeUpdate: Bool = false
    var depthStencilTextureUsage: MTLTextureUsage = .unknown
    var multisampleColorTextureUsage: MTLTextureUsage = .unknown {
        didSet {
            if multisampleColorTextureUsage != oldValue {
                renderAttachmentDirtyState |= 0x10001
            }
        }
    }
    var _drawableAttachmentIndex = 0
    var drawableAttachmentIndex: Int {
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
    var nominalFramesPerSecond: Int = 0
    var maxValidAttachmentIndex: Int = 0
    var colorPixelFormats = [MTLPixelFormat](repeating: .invalid, count: 8)
    var _multisampleColorTextures = [MTLTexture?](repeating: nil, count: 8)
    var multisampleColorTextures: [MTLTexture?]? {
        multisampleColorTexturesForceUpdate(false)
    }
    var _colorTextures = [MTLTexture?](repeating: nil, count: 8)
    var colorTextures: [MTLTexture?]? {
        colorTexturesForceUpdate(false)
    }
    var offscreenSwapChain = [iTermOffscreenDrawable?](repeating: nil, count: 3)
    var drawableIdx: UInt = 0
    var renderAttachmentDirtyState: Int = 0
    var terminateAfterFrame: UInt = 0
    var terminateAfterSeconds: UInt = 0
    var measureAfterFrame: UInt = 0
    var measureAfterSeconds: UInt = 0
    var dumpFrameAtFrame: UInt = 0
    var dumpFrameAtSeconds: UInt = 0
    var dumpPath: String = ""
    var dumpFirstFrame: Bool = false
    var drawOffscreen: Bool = false
    var startTime: CFTimeInterval = CFTimeInterval()
    var frameNum: UInt32 = 0

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
            _depthStencilTexture = nil
            _multisampleColorTexture = nil
            metalLayer?.device = newValue
            if drawOffscreen {
                for x23 in 0...3 {
                    offscreenSwapChain[x23]?.device = newValue!
                }
            }
            renderAttachmentDirtyState |= 0x80010001
        }
        get {
            _device
        }
    }
    private var _currentDrawable: CAMetalDrawable?

    @objc
    var currentDrawable: CAMetalDrawable? {
        get {
            if let _currentDrawable {
                return _currentDrawable
            }
            if drawOffscreen {
                drawableIdx = (drawableIdx + 1) % 3

                _currentDrawable = offscreenSwapChain[Int(drawableIdx)]
                return _currentDrawable
            }
            let drawable = metalLayer?.nextDrawable()
            _currentDrawable = drawable
            if frameNum != 1 || dumpFrameAtFrame != 0 || dumpFrameAtSeconds != 0 {
                return _currentDrawable
            }
            if dumpFirstFrame && _framebufferOnly {
                metalLayer?.framebufferOnly = true
            }
            return _currentDrawable
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
    public var depthStencilAttachmentTextureUsage: MTLTextureUsage = .renderTarget {
        didSet {
            if oldValue != depthStencilAttachmentTextureUsage {
                renderAttachmentDirtyState |= 0x80000000
            }
        }
    }

    @objc
    public var multisampleColorAttachmentTextureUsage: MTLTextureUsage = .renderTarget

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
        renderAttachmentDirtyState |= 0x10001
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
    public var depthStencilPixelFormat: MTLPixelFormat = .invalid {
        didSet {
            switch depthStencilPixelFormat {
            case .invalid:
                _depthStencilTexture = nil
            case .x32_stencil8, .x24_stencil8:
                fatalError()
            default:
                break
            }
            renderAttachmentDirtyState |= 0x80000000
        }
    }

    @objc
    public var depthStencilStorageMode: MTLStorageMode = .private {
        didSet {
            if depthStencilStorageMode != oldValue {
                renderAttachmentDirtyState |= 0x80000000
            }
        }
    }

    @objc
    public var sampleCount: Int = 1 {
        didSet {
            if sampleCount <= 1 {
                _multisampleColorTexture = nil
            }
            renderAttachmentDirtyState |= 0x8001
        }
    }

    @objc
    public var clearColor: MTLClearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)

    @objc
    public var clearDepth: Double = 1.0

    @objc
    public var clearStencil: UInt32 = 0

    private var _depthStencilTexture: MTLTexture?

    @objc
    public var depthStencilTexture: MTLTexture?  {
        if (renderAttachmentDirtyState & 0x80000000) == 0 {
            return _depthStencilTexture
        }
        guard device != nil else {
            return nil
        }
        if let depthStencilTexture = _depthStencilTexture,
           Int(depthStencilTexture.width) == Int(metalLayer?.drawableSize.width ?? 0),
           Int(depthStencilTexture.height) == Int(metalLayer?.drawableSize.height ?? 0),
           depthStencilTexture.sampleCount == sampleCount,
           depthStencilTexture.pixelFormat == depthStencilPixelFormat,
           depthStencilTexture.usage == depthStencilTextureUsage,
           depthStencilTexture.storageMode == depthStencilStorageMode {
            return depthStencilTexture
        }
        if depthStencilPixelFormat == .invalid {
            return _depthStencilTexture
        }

        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            self.resizeDrawable()
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
        resizeMetalLayerDrawable()
        createDepthStencilTexture()
        return _depthStencilTexture
    }

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

    private var _multisampleColorTexture: MTLTexture?

    @objc
    public var multisampleColorTexture: MTLTexture? {
        multisampleColorTextures?[_drawableAttachmentIndex]
    }

    @objc
    public var currentRenderPassDescriptor: MTLRenderPassDescriptor? {
        guard currentDrawable != nil else {
            return nil
        }
        let descriptor = MTLRenderPassDescriptor()
        if sampleCount >= 2 {
            _ = multisampleColorTextures
            for x22 in 0...maxValidAttachmentIndex {
                descriptor.colorAttachments[x22].texture = _multisampleColorTextures[x22]
                descriptor.colorAttachments[x22].resolveTexture = _colorTextures[x22]
                descriptor.colorAttachments[x22].storeAction = .multisampleResolve
                descriptor.colorAttachments[x22].loadAction = .clear
                descriptor.colorAttachments[x22].clearColor = clearColor
            }
        } else {
            _ = colorTextures
            for x22 in 0...maxValidAttachmentIndex {
                descriptor.colorAttachments[x22].texture = _colorTextures[x22]!

                descriptor.colorAttachments[x22].loadAction = .clear
                descriptor.colorAttachments[x22].clearColor = clearColor
            }
        }
        guard let depthStencilTexture = _depthStencilTexture else {
            return descriptor
        }
        if depthStencilPixelFormat == .stencil8 {
            descriptor.depthAttachment.texture = nil
        }
        descriptor.depthAttachment.texture = depthStencilTexture
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.storeAction = .dontCare
        descriptor.depthAttachment.clearDepth = clearDepth

        switch depthStencilPixelFormat {
        case .depth32Float, .depth16Unorm:
            descriptor.stencilAttachment.texture = nil

        default:
            descriptor.stencilAttachment.texture = depthStencilTexture
            descriptor.stencilAttachment.loadAction = .clear
            descriptor.stencilAttachment.storeAction = .dontCare
            descriptor.stencilAttachment.clearStencil = clearStencil
        }
        return descriptor
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
        coder.encode(depthStencilPixelFormat, forKey: "MTKViewDepthStencilPixelFormatCoderKey")
        coder.encode(sampleCount, forKey: "MTKViewSampleCountCoderKey")
        let clearColorData = withUnsafeBytes(of: clearColor) { bytes in
            Data(bytes: bytes.baseAddress!, count: MemoryLayout<MTLClearColor>.size)
        }
        coder.encode(clearColorData, forKey: "MTKViewClearColorCoderKey")
        coder.encode(clearDepth, forKey: "MTKViewClearDepthCoderKey")
        coder.encode(clearStencil, forKey: "MTKViewClearStencilCoderKey")
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
        if coder.containsValue(forKey: "MTKViewDepthStencilPixelFormatCoderKey") {
            depthStencilPixelFormat = MTLPixelFormat(rawValue: UInt(coder.decodeInteger(forKey: "MTKViewDepthStencilPixelFormatCoderKey"))) ?? .invalid
        }
        if coder.containsValue(forKey: "MTKViewSampleCountCoderKey") {
            sampleCount = coder.decodeInteger(forKey: "MTKViewSampleCountCoderKey")
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
        if coder.containsValue(forKey: "MTKViewClearDepthCoderKey") {
            clearDepth = coder.decodeDouble(forKey: "MTKViewClearDepthCoderKey")
        }
        if coder.containsValue(forKey: "MTKViewClearStencilCoderKey") {
            clearStencil = UInt32(coder.decodeInteger(forKey: "MTKViewClearStencilCoderKey"))
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
        _depthStencilTexture = nil
        _multisampleColorTexture = nil
        renderAttachmentDirtyState = 0x80010000
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

        if frameNum == 1 {
            if dumpFirstFrame {
                dumpFrameImage(withFilename: "MTKViewFirstFrameDump")
            }
            startTime = CACurrentMediaTime()
        }
        let currentTime = CACurrentMediaTime()

        if dumpFrameAtFrame != 0 && dumpFrameAtFrame <= frameNum {
            dumpFrameImage(withFilename: "MTKViewFrameDumpAfterFrame_\(frameNum)")
            dumpFrameAtFrame = 0
        }

        let elapsed = currentTime - startTime
        if dumpFrameAtSeconds != 0 && elapsed >= Double(dumpFrameAtSeconds) {
            dumpFrameImage(withFilename: "MTKViewFrameDumpAfterSeconds_\(dumpFrameAtSeconds)")
            dumpFrameAtSeconds = 0
        }

        if measureAfterFrame != 0 && measureAfterFrame <= frameNum {
            dumpFramerate(Double(frameNum) / elapsed, withFilename: "MTKViewFramerateAfterFrame_\(frameNum)")
            measureAfterFrame = 0
        }

        if measureAfterSeconds != 0 {
            if elapsed >= Double(measureAfterSeconds) {
                dumpFramerate(Double(frameNum) / elapsed, withFilename: "MTKViewFramerateAfterSeconds_\(Int(elapsed))")
            }
        }

        if (terminateAfterFrame != 0 && frameNum >= terminateAfterFrame) || (terminateAfterSeconds != 0 && elapsed >= Double(terminateAfterSeconds)) {
            NSApplication.shared.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
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
        } else if key == "sampleCount" {
            sampleCount = 1
        } else if key == "clearDepth" {
            clearDepth = 1.0
        } else if key == "clearStencil" {
            clearStencil = 0
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
        getEnvironmentSettings()
        drawableScaleFactor = CGSize(width: 1.0, height: 1.0)
        wantsLayer = true
        metalLayer = CAMetalLayer()
        layer = metalLayer
        layerContentsRedrawPolicy = .duringViewResize
        sampleCount = 1
        paused = false
        renderAttachmentDirtyState = 0x80010001
        colorPixelFormats = [.invalid, .invalid, .invalid, .invalid, .invalid, .invalid, .invalid, .invalid]
        _colorTextures = [nil, nil, nil, nil, nil, nil, nil, nil]
        _multisampleColorTextures = [nil, nil, nil, nil, nil, nil, nil, nil]
        _drawableAttachmentIndex = 0
        maxValidAttachmentIndex = 0
        colorPixelFormat = .bgra8Unorm
        metalLayer?.device = _device
        metalLayer?.delegate = self
        metalLayer?.framebufferOnly = true
        _framebufferOnly = true
        depthStencilTextureUsage = .renderTarget  // assume that the linkedOnOrAfter check passes
        multisampleColorTextureUsage = .renderTarget
        if dumpFrameAtFrame != 0 || dumpFrameAtSeconds != 0 || dumpFirstFrame {
            metalLayer?.framebufferOnly = false
        }
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        clearDepth = 1
        clearStencil = 1
        depthStencilStorageMode = .private
        _enableSetNeedsDisplay = false
        if drawOffscreen {
            // The disassembly was ambiguous here but this code path isn't taken normally.
            fatalError()
            // Approximately what I saw it do
            // let offscreenDrawable = iTermOffscreenDrawable(device: device, pixelFormat: colorPixelFormat, size: bounds.size, drawableID: 0)
        }
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

    private func dumpFrameImage(withFilename filename: String) {
        fatalError("TODO")
    }

    private func dumpFramerate(_ framerate: Double, withFilename filename: String) {
        // TODO
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
            drawableSize = newPixelSize
            sizeDirty = true
        }
    }

    private func resizeMetalLayerDrawable() {
        guard sizeDirty else {
            return
        }

        metalLayer?.drawableSize = drawableSize
        renderAttachmentDirtyState |= 0x80010001
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

    private func createDepthStencilTexture() {
        let size = metalLayer?.drawableSize ?? .zero
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: depthStencilPixelFormat,
                                                                  width: Int(size.width),
                                                                  height: Int(size.height),
                                                                  mipmapped: false)

        descriptor.textureType = if sampleCount <= 2 { .type2D } else { .type2DMultisample }
        descriptor.usage = depthStencilTextureUsage
        descriptor.storageMode = depthStencilStorageMode
        let texture = device?.makeTexture(descriptor: descriptor)
        _depthStencilTexture = texture
        let label = switch depthStencilPixelFormat {
        case .depth16Unorm: "MTKView Depth"
        case .depth32Float: "MTKView Depth Stencil"
        case .stencil8: "MTKView Depth"
        default: "MTKView Depth Stencil"
        }
        _depthStencilTexture?.label = label
        renderAttachmentDirtyState &= 0x7fffffff
    }

    private func getEnvironmentSettings() {
        let processInfo = ProcessInfo.processInfo
        let environment = processInfo.environment
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal

        let parseUInt = { (key: String) -> UInt in
            guard let value = environment[key] else {
                return 0
            }
            return formatter.number(from: value)?.uintValue ?? 0
        }
        let parseBool = { (key: String) -> Bool in
            guard let value = environment[key] else {
                return false
            }
            return formatter.number(from: value)?.boolValue ?? false
        }
        terminateAfterFrame = parseUInt("MTK_TERMINATE_AFTER_FRAME")
        terminateAfterSeconds = parseUInt("MTK_TERMINATE_AFTER_SECONDS")
        measureAfterFrame = parseUInt("MTK_MEASURE_FRAMERATE_AFTER_FRAME")
        measureAfterSeconds = parseUInt("MTK_MEASURE_FRAMERATE_AFTER_SECONDS")
        dumpPath = environment["MTK_DUMP_PATH"] ?? "/tmp"
        dumpFrameAtFrame = parseUInt("MTK_DUMP_FRAME_AFTER_FRAME")
        dumpFrameAtSeconds = parseUInt("MTK_DUMP_FRAME_AFTER_SECONDS")
        dumpFirstFrame = parseBool("MTK_DUMP_FIRST_FRAME")
        drawOffscreen = parseBool("MTK_DRAW_OFFSCREEN")
    }

    // This is untested
    private func exportToTarga(atLocation location: String, width: Int, height: Int, size: Int, bytes: [UInt8]) {
        // Create a mutable data object for the TGA file
        let headerLength = 0x12 // Verify the actual length needed
        guard let data = NSMutableData(length: headerLength + size) else {
            return
        }

        // Get a pointer to the mutable bytes and fill in the TGA header
        let mutableBytes = data.mutableBytes.assumingMemoryBound(to: UInt8.self)
        mutableBytes[0] = 0          // ID length
        mutableBytes[1] = 2          // Color map type
        mutableBytes[2] = 0          // Image type (uncompressed true-color image)
        mutableBytes[3] = 0          // Color map specification (skip bytes as needed)
        mutableBytes[4] = 0
        mutableBytes[5] = 0
        mutableBytes[6] = 0
        mutableBytes[7] = 0
        mutableBytes[8] = 0
        mutableBytes[9] = 0
        mutableBytes[10] = 0
        mutableBytes[11] = 0
        mutableBytes[12] = UInt8(width & 0xFF)     // Image width (low byte)
        mutableBytes[13] = UInt8((width >> 8) & 0xFF) // Image width (high byte)
        mutableBytes[14] = UInt8(height & 0xFF)    // Image height (low byte)
        mutableBytes[15] = UInt8((height >> 8) & 0xFF) // Image height (high byte)
        mutableBytes[16] = 0x20     // Pixel depth (32 bits)
        mutableBytes[17] = 0        // Image descriptor (origin, alpha bits, etc.)

        // Append the raw pixel data
        memcpy(mutableBytes.advanced(by: headerLength), bytes, size)

        // Write the data to the specified location
        do {
            try data.write(to: URL(fileURLWithPath: location), options: .atomic)
        } catch {
            DLog("Error writing TGA file: \(error.localizedDescription)")
            return
        }
    }

    private func calculateRefreshesPerSecond() -> Int {
        if let displayLink {
            let cvtime = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(displayLink)
            return Int(round(Double(cvtime.timeScale) / Double(cvtime.timeValue)))
        } else {
            return 60
        }
    }

    private func multisampleColorTexturesForceUpdate(_ force: Bool) -> [MTLTexture?]? {
        _ = colorTextures
        if renderAttachmentDirtyState & 0x10000 != 0 {
            guard let device else {
                return nil
            }
            for i in 0...maxValidAttachmentIndex {
                if let multisampleColorTexture = _multisampleColorTextures[i],
                   !force,
                   multisampleColorTexture.width != Int(drawableSize.width) ||
                    multisampleColorTexture.height != Int(drawableSize.height) ||
                    multisampleColorTexture.sampleCount != sampleCount ||
                    multisampleColorTexture.pixelFormat != colorPixelFormats[i] ||
                    multisampleColorTexture.usage != multisampleColorTextureUsage {
                    continue
                }

                if sampleCount < 2 {
                    continue
                }
                let texture: MTLTexture?
                if colorPixelFormats[i] != .invalid {
                    // I'm just assuming the runloop mode, I wasn't able to track it down
                    CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                        self.resizeDrawable()
                    }
                    CFRunLoopWakeUp(CFRunLoopGetMain())
                    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: colorPixelFormats[i],
                                                                              width: Int(metalLayer?.drawableSize.width ?? 0),
                                                                              height: Int(metalLayer?.drawableSize.height ?? 0),
                                                                              mipmapped: false)
                    descriptor.textureType = .type2DMultisample
                    descriptor.sampleCount = sampleCount
                    descriptor.usage = multisampleColorTextureUsage

                    descriptor.storageMode = .private
                    texture = device.makeTexture(descriptor: descriptor)
                } else {
                    texture = nil
                }

                _multisampleColorTextures[i] = texture
            }
            renderAttachmentDirtyState &= 0xfffeffff
        }
        return multisampleColorTextures
    }

    private func colorTexturesForceUpdate(_ force: Bool) -> [MTLTexture?]? {
        guard let device else {
            return nil
        }

        if let drawable = currentDrawable {
            _colorTextures[_drawableAttachmentIndex] = drawable.texture
        }

        guard renderAttachmentDirtyState & 1 == 1 else {
            return _colorTextures
        }
        for i in 0...maxValidAttachmentIndex {
            if !drawOffscreen && _drawableAttachmentIndex == i {
                break
            }

            if !force,
               let colorTexture = _colorTextures[i],
               metalLayer?.drawableSize.width == CGFloat(colorTexture.width),
               metalLayer?.drawableSize.height == CGFloat(colorTexture.height),
               colorTexture.pixelFormat == colorPixelFormats[i],
               colorTexture.usage == multisampleColorTextureUsage {
                break
            }
            if drawOffscreen && _drawableAttachmentIndex == i {
                for x23 in 0..<3 {
                    offscreenSwapChain[x23]?.size = drawableSize
                    offscreenSwapChain[x23]?.pixelFormat = colorPixelFormats[x23]
                }
                _colorTextures[i] = currentDrawable?.texture
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

                descriptor.usage = multisampleColorTextureUsage
                descriptor.storageMode = .private
                newTexture = device.makeTexture(descriptor: descriptor)
            } else {
                newTexture = nil
            }
            _colorTextures[i] = newTexture
        }

        renderAttachmentDirtyState &= ~1
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
