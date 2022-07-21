//
//  FileProviderLogging.swift
//  FileProvider
//
//  Created by George Nachman on 6/8/22.
//

import Foundation
import OSLog

@available(macOS 11.0, *)
let logger = Logger(subsystem: "com.iterm2.FileProvider", category: "main")

@objc(FileProviderLogging) class FileProviderLogging: NSObject {
    @objc static var callback: ((String) -> ())? = nil
}

class LogContext {
    @TaskLocal
    static var logContexts = ["FileProvider"]
}

public func log(_ message: String) {
    if #available(macOS 11.0, *) {
        let prefix = LogContext.logContexts.joined(separator: " > ")
        logger.error("FileProviderLog: \(prefix, privacy: .public): \(message, privacy: .public)")
    }
    FileProviderLogging.callback?(message)
}

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

