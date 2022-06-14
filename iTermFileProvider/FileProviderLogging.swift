//
//  FileProviderLogging.swift
//  FileProvider
//
//  Created by George Nachman on 6/8/22.
//

import Foundation
import OSLog

@available(macOS 11.0, *)
let logger = Logger(subsystem: "com.themcnachmans.FileProvider", category: "main")

@available(macOS 11.0, *)
class LogContext {
    @TaskLocal
    static var logContexts = ["FileProvider"]
}

@available(macOS 11.0, *)
public func log(_ message: String) {
    let prefix = LogContext.logContexts.joined(separator: " > ")
    logger.error("QQQ \(prefix, privacy: .public): \(message, privacy: .public)")
}

@available(macOS 11.0, *)
public func logging<T>(_ prefix: String, closure: () throws -> T) rethrows -> T {
    return try LogContext.$logContexts.withValue(LogContext.logContexts + [prefix]) {
        log("begin")
        do {
            defer {
                log("end")
            }
            return try closure()
        } catch {
            log("Exiting logging scope with uncaught error \(error)")
            throw error
        }
    }
}

@available(macOS 11.0, *)
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

