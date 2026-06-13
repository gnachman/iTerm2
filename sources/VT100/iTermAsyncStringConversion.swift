import Foundation

@objc(iTermAsyncStringConversion)
class iTermAsyncStringConversion: NSObject {
    private enum State {
        case pending
        case complete(UnsafeMutablePointer<PreconvertedStringData>)
    }

    private static let queue = DispatchQueue(label: "com.iterm2.preconversion",
                                              qos: .userInitiated)

    private let mutex = Mutex()
    private var state: State = .pending
    // Completion-delivery coordination, distinct from `state` (which tracks the
    // converted buffer). `completed` is set once the conversion has run;
    // `delivered` guards against firing the handler more than once.
    private var completed = false
    private var delivered = false
    private var _completionHandler: (() -> Void)?

    // Captured inputs for conversion (used by background block or sync resolve).
    private let string: AnyObject
    private let capturedRendition: VT100GraphicRendition
    private let capturedProtectedMode: Bool
    private let capturedConfig: VT100StringConversionConfig

    @objc let byteCount: Int

    // The handler may be assigned after init (callers commonly do
    // `let c = init(...); c.completionHandler = ...`), and the conversion runs
    // on a background queue kicked off in init. So the conversion can finish
    // before the handler is set. Deliver exactly once: fire here if the work is
    // already done, otherwise the background completion fires it. Without this,
    // a handler set after an already-finished conversion would never run (e.g.
    // VT100Parser's outstanding-bytes counter would never be decremented).
    @objc var completionHandler: (() -> Void)? {
        get { mutex.sync { _completionHandler } }
        set {
            let fire: (() -> Void)? = mutex.sync {
                _completionHandler = newValue
                guard completed, !delivered, let handler = newValue else { return nil }
                delivered = true
                return handler
            }
            fire?()
        }
    }

    @objc init(string: AnyObject,
               stringLength: Int,
               rendition: VT100GraphicRendition,
               protectedMode: Bool,
               config: VT100StringConversionConfig) {
        self.string = string
        self.capturedRendition = rendition
        self.capturedProtectedMode = protectedMode
        self.capturedConfig = config
        byteCount = stringLength * MemoryLayout<unichar>.size

        super.init()

        Self.queue.async { [self] in
            mutex.sync {
                guard case .pending = state else { return }
                state = .complete(performConversion())
            }
            deliverCompletion()
        }
    }

    /// Marks the conversion complete and fires the handler if one is already
    /// set and hasn't fired. The matching delivery for a handler set *after*
    /// completion happens in the completionHandler setter.
    private func deliverCompletion() {
        let fire: (() -> Void)? = mutex.sync {
            completed = true
            guard !delivered, let handler = _completionHandler else { return nil }
            delivered = true
            return handler
        }
        fire?()
    }

    /// Always returns a valid result. Called on mutation thread.
    /// If the background block is running performConversion under the lock,
    /// this blocks until it finishes. If the block hasn't started, this does
    /// the conversion synchronously. Either way, no double work.
    @objc func resolve() -> UnsafeMutablePointer<PreconvertedStringData> {
        return mutex.sync {
            switch state {
            case .pending:
                let ptr = performConversion()
                state = .complete(ptr)
                return ptr
            case .complete(let ptr):
                return ptr
            }
        }
    }

    private func performConversion() -> UnsafeMutablePointer<PreconvertedStringData> {
        let pre = UnsafeMutablePointer<PreconvertedStringData>.allocate(capacity: 1)
        pre.initialize(to: PreconvertedStringData())
        iTermStringPreconverter.preconvert(pre,
                                           string: string,
                                           rendition: capturedRendition,
                                           protectedMode: capturedProtectedMode,
                                           config: capturedConfig)
        return pre
    }

    deinit {
        if case .complete(let ptr) = state {
            iTermPreconvertedStringDataFree(ptr)
            ptr.deinitialize(count: 1)
            ptr.deallocate()
        }
    }
}
