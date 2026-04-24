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

    // Captured inputs for conversion (used by background block or sync resolve).
    private let string: AnyObject
    private let capturedRendition: VT100GraphicRendition
    private let capturedProtectedMode: Bool
    private let capturedConfig: VT100StringConversionConfig

    @objc let byteCount: Int
    @objc var completionHandler: (() -> Void)?

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
            completionHandler?()
        }
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
