//
//  SwiftDebugLogging.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/5/21.
//

import Foundation
import OSLog

func DLog(_ messageBlock: @autoclosure () -> String, file: String = #file, line: Int = #line, function: String = #function) {
    guard gDebugLogging.boolValue else {
        return
    }
    let message = messageBlock()
    // print("\(file):\(line) \(function): \(message)")
    DebugLogImpl(file.cString(using: .utf8), Int32(line), function.cString(using: .utf8), message)
}

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

public class LogContext {
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


public extension Optional where Wrapped: CustomDebugStringConvertible {
    var debugDescriptionOrNil: String {
        switch self {
        case .none:
            return "(nil)"
        case .some(let obj):
            return obj.debugDescription
        }
    }
}

public extension Optional where Wrapped: CustomStringConvertible {
    var descriptionOrNil: String {
        switch self {
        case .none:
            return "(nil)"
        case .some(let obj):
            return obj.description
        }
    }
}

public extension Optional where Wrapped == Data {
    var stringOrHex: String {
        switch self {
        case .some(let data):
            return data.stringOrHex
        case .none:
            return "(nil)"
        }
    }
}

extension Int: CustomDebugStringConvertible {
    public var debugDescription: String {
        return String(self)
    }
}

public extension DataProtocol {
    var hexified: String { map { .init(format: "%02x", $0) }.joined() }
}

public extension Data {
    var stringOrHex: String {
        if let s = String(data: self, encoding: .utf8) {
            return s
        }
        return hexified
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
