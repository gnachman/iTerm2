//
//  FileProviderLogging.swift
//  FileProvider
//
//  Created by George Nachman on 6/8/22.
//

import Foundation
import OSLog

@available(macOS 11.0, *)
struct iTermLogger {
    private static let logger = Logger(subsystem: "com.iterm2.logger", category: "main")
    public func info(_ messageBlock: @autoclosure () -> String,
                     file: String = #file,
                     line: Int = #line,
                     function: String = #function) {
        if !gDebugLogging.boolValue {
            return
        }
        let message = messageBlock()
        Self.logger.info("\(message, privacy: .public)")
        DebugLogImpl(file, Int32(line), function, message)
    }

    public func debug(_ messageBlock: @autoclosure () -> String,
                     file: String = #file,
                     line: Int = #line,
                     function: String = #function) {
        if !gDebugLogging.boolValue {
            return
        }
        let message = messageBlock()
        Self.logger.debug("\(message, privacy: .public)")
        DebugLogImpl(file, Int32(line), function, message)
    }
}

@objc(FileProviderLogging) class FileProviderLogging: NSObject {
    @objc static var callback: ((String) -> ())? = nil

    @available(macOS 11.0, *)
    static let logger = iTermLogger()
}

class LogContext {
    @TaskLocal
    static var logContexts = ["FileProvider"]
}

public func log(_ message: String) {
    if #available(macOS 11.0, *) {
        let prefix = LogContext.logContexts.joined(separator: " > ")
        FileProviderLogging.logger.info("FileProviderLog: \(prefix): \(message)")
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
