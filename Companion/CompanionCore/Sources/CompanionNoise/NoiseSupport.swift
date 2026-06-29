//
//  NoiseSupport.swift
//  CompanionCore
//
//  Runtime bootstrap and error plumbing for the noise-c bindings.
//

import Foundation
import CNoise

/// An error returned by a noise-c call. `code` is the NOISE_ERROR_* value (or a
/// synthetic negative value for binding-level problems).
public struct NoiseError: Error, CustomStringConvertible, Equatable {
    public let code: Int32
    public let operation: String

    public init(code: Int32, operation: String) {
        self.code = code
        self.operation = operation
    }

    public var description: String {
        "Noise error \(code) during \(operation)"
    }

    /// Synthetic codes for problems that originate in the Swift bindings rather
    /// than noise-c itself. Kept well away from noise-c's positive code space.
    static let missingRemoteKey = NoiseError(code: -1000, operation: "missing remote static public key")
}

enum NoiseRuntime {
    // noise_init() wires up the library's RNG and registration tables. It is
    // safe and cheap to call, and must run before any other noise-c call.
    private static let didInit: Bool = {
        return noise_init() == CNoiseErrorNone
    }()

    static func ensureInitialized() {
        _ = didInit
    }
}

/// Throw a NoiseError unless `code` is NOISE_ERROR_NONE.
@discardableResult
func noiseCheck(_ code: Int32, _ operation: String) throws -> Int32 {
    guard code == CNoiseErrorNone else {
        throw NoiseError(code: code, operation: operation)
    }
    return code
}
