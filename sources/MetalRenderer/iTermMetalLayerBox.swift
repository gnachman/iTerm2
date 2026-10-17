//
//  iTermMetalLayerBox.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/25/25.
//

import Foundation
import Metal

class iTermMetalLayerBox {
    struct LayerContext: Equatable {
        init(_ metalLayer: CAMetalLayer) {
            device = metalLayer.device
            framebufferOnly = metalLayer.framebufferOnly
            presentsWithTransaction = metalLayer.presentsWithTransaction
            pixelFormat = metalLayer.pixelFormat
            colorspace = metalLayer.colorspace
            size = metalLayer.drawableSize
        }

        static func == (lhs: LayerContext, rhs: LayerContext) -> Bool {
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

    // Guards a CAMetalLayer with a TimedMutex so the main thread can give up
    // instead of waiting up to a second while nextDrawable() holds the lock.
    private final class LockedLayer {
        private let mutex = TimedMutex()
        private let layer: CAMetalLayer

        init(_ layer: CAMetalLayer) {
            self.layer = layer
        }

        @discardableResult
        func access<Result>(_ block: (CAMetalLayer) throws -> Result) rethrows -> Result {
            return try mutex.sync {
                return try block(layer)
            }
        }

        // Throws TimedMutex.Timeout if the lock can't be acquired in time.
        @discardableResult
        func access<Result>(timeout: TimeInterval,
                            _ block: (CAMetalLayer) throws -> Result) throws -> Result {
            return try mutex.sync(timeout: timeout) {
                return try block(layer)
            }
        }
    }

    private let metalLayer: LockedLayer
    private let _layerContext: MutableAtomicObject<LayerContext>

    init(metalLayer: CAMetalLayer) {
        self.metalLayer = .init(metalLayer)
        self._layerContext = .init(.init(metalLayer))
    }
}

extension iTermMetalLayerBox {
    var layerContext: LayerContext {
        _layerContext.value
    }

    var device: MTLDevice? {
        get {
            return metalLayer.access { $0.device }
        }
        set {
            metalLayer.access {
                $0.device = newValue
                _layerContext.value = .init($0)
            }
        }
    }

    var delegate: CALayerDelegate? {
        get {
            metalLayer.access { $0.delegate }
        }
        set {
            metalLayer.access { $0.delegate = newValue }
        }

    }
    var framebufferOnly: Bool {
        get {
            return metalLayer.access { $0.framebufferOnly }
        }
        set {
            metalLayer.access {
                $0.framebufferOnly = newValue
                _layerContext.value = .init($0)
            }
        }
    }

    var presentsWithTransaction: Bool {
        get {
            return metalLayer.access { $0.presentsWithTransaction }
        }
        set {
            // This is assigned on every frame but almost never changes. Check the
            // cached value first so the main thread doesn't wait on the layer lock,
            // which nextDrawable() can hold for up to a second. Issue 13139.
            if _layerContext.value.presentsWithTransaction == newValue {
                return
            }
            metalLayer.access {
                $0.presentsWithTransaction = newValue
                _layerContext.value = .init($0)
            }
        }
    }

    var pixelFormat: MTLPixelFormat {
        get {
            return metalLayer.access { $0.pixelFormat }
        }
        set {
            metalLayer.access {
                $0.pixelFormat = newValue
                _layerContext.value = .init($0)
            }
        }
    }

    var wantsExtendedDynamicRangeContent: Bool {
        get {
            return metalLayer.access { $0.wantsExtendedDynamicRangeContent }
        }
        set {
            metalLayer.access {
                $0.wantsExtendedDynamicRangeContent = newValue
            }
        }
    }

    var colorspace: CGColorSpace? {
        get {
            return metalLayer.access { $0.colorspace }
        }
        set {
            metalLayer.access {
                $0.colorspace = newValue
                _layerContext.value = .init($0)
            }
        }
    }

    var drawableSize: CGSize {
        return metalLayer.access { $0.drawableSize }
    }

    // Throws TimedMutex.Timeout if the layer lock can't be acquired within
    // `timeout`, which happens when nextDrawable() is stuck holding it. Issue 13139.
    func setDrawableSize(_ size: CGSize, timeout: TimeInterval) throws {
        try metalLayer.access(timeout: timeout) {
            $0.drawableSize = size
            _layerContext.value = .init($0)
        }
    }

    var preferredDevice: MTLDevice? {
        return metalLayer.access { $0.preferredDevice }
    }

    var contentsScale: CGFloat {
        get {
            return metalLayer.access { $0.contentsScale }
        }
        set {
            metalLayer.access { $0.contentsScale = newValue }
        }
    }

    // Holds the layer lock until nextDrawable returns, which is bounded only by
    // the layer's allowsNextDrawableTimeout (set at layer creation in
    // iTermMetalView.initCommon). That property must not be set here: it pushes
    // an implicit CATransaction that aborts off the main thread.
    //
    // Throws if the drawable size is invalid.
    func nextDrawable() throws -> CAMetalDrawable? {
        return try metalLayer.access { layer in
            return try Self.nextDrawable(layer)
        }
    }

    func nextContextualizedDrawable() -> (CAMetalDrawable, LayerContext)? {
        return metalLayer.access { layer in
            if let drawable = try? Self.nextDrawable(layer) {
                // The access to layerContext is not a data race because it is only mutated while
                // both metalLayer and layerContext are locked.
                return (drawable, layerContext)
            }
            return nil
        }
    }

    // Must be called with metalLayer locked so the size can't change between
    // the check and the call to nextDrawable.
    private static func nextDrawable(_ layer: CAMetalLayer) throws -> CAMetalDrawable? {
        // A zero-dimension drawable size makes QuartzCore's nextDrawable divide by
        // a drawable dimension and crash with EXC_ARITHMETIC.
        let size = layer.drawableSize
        guard size.width >= 1, size.height >= 1 else {
            throw iTermMetalLayerBoxError.invalidDrawableSize(size)
        }
        return layer.nextDrawable()
    }
}

enum iTermMetalLayerBoxError: Error {
    case invalidDrawableSize(CGSize)
}

/// Helper class for acquiring Metal drawables with context validation.
/// Created on the main thread, can be used from any thread to acquire a drawable
/// and later validate that the layer context hasn't changed since acquisition.
@objc class iTermDrawableAcquisitionHelper: NSObject {
    private let box: iTermMetalLayerBox
    private var capturedContext: iTermMetalLayerBox.LayerContext?

    init(box: iTermMetalLayerBox) {
        self.box = box
        super.init()
    }

    /// Acquires a drawable from the Metal layer and captures the current layer context.
    /// Can be called from any thread.
    /// - Returns: The acquired drawable, or nil if unavailable.
    @objc func acquireDrawable() -> CAMetalDrawable? {
        if let tuple = box.nextContextualizedDrawable() {
            capturedContext = tuple.1
            return tuple.0
        }
        return nil
    }

    /// Checks if the layer context is still the same as when the drawable was acquired.
    /// This should be called before presenting to ensure the drawable is still compatible
    /// with the current view state (size, scale factor, etc.).
    /// - Returns: true if the context matches, false if it has changed.
    @objc func isContextStillValid() -> Bool {
        guard let captured = capturedContext else {
            return false
        }
        return captured == box.layerContext
    }
}
