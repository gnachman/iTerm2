//
//  FileProviderLogging.swift
//  FileProvider
//
//  Created by George Nachman on 6/8/22.
//

import Foundation
import OSLog

let logger = Logger(subsystem: "com.themcnachmans.FileProvider", category: "main")

class LogContext {
    @TaskLocal
    static var logContexts = ["FileProvider"]
}

func log(_ message: String) {
    let prefix = LogContext.logContexts.joined(separator: " > ")
    logger.info("\(prefix, privacy: .public): \(message, privacy: .public)")
}

func logging<T>(_ prefix: String, closure: () throws -> T) rethrows -> T {
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

func logging<T>(_ prefix: String, closure: () async throws -> T) async rethrows -> T {
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

