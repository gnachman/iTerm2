//
//  AsyncFileProviderLogging.swift
//  iTermFileProvider
//
//  Created by George Nachman on 12/9/22.
//

import Foundation

// The only purpose of this file is to sequester code that uses Swift concurrency where it will
// not be linked into iTerm2SandboxedWorker. I have a request out to DTS to figure out why
// but it won't launch because it can't find libswift_concurrency.dylib.

@available(macOS 10.15, *)
public func logging<T>(_ prefix: String, closure: () async throws -> T) async rethrows -> T {
    return try await LogContext.$logContexts.withValue(LogContext.logContexts + [prefix]) {
        log("begin")
        do {
            defer {
                log("end")
            }
            return try await closure()
        } catch {
            log("Exiting logging scope with uncaught error \(error)")
            throw error
        }
    }
}

