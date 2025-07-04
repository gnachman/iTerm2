//
//  SwiftDebugLogging.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/5/21.
//

import Foundation
import OSLog
import WebExtensionsFramework

func DLog(_ messageBlock: @autoclosure () -> String, file: String = #file, line: Int = #line, function: String = #function) {
    guard gDebugLogging.boolValue else {
        return
    }
    let message = messageBlock()
    // print("\(file):\(line) \(function): \(message)")
    DebugLogImpl(file.cString(using: .utf8), Int32(line), function.cString(using: .utf8), message)
}

func XLog(_ messageBlock: @autoclosure () -> String, file: String = #file, line: Int = #line, function: String = #function) {
    guard gDebugLogging.boolValue else {
        return
    }
    let message = messageBlock()
    NSLog("\(file):\(line) \(function): \(message)")
    DebugLogImpl(file.cString(using: .utf8), Int32(line), function.cString(using: .utf8), message)
}

class iTermLogger {
    private static let logger = Logger(subsystem: "com.iterm2.logger", category: "main")
    let verbosePaths = Set<[String]>()
    enum Level: Int {
        case debug
        case info
        case error
        case fatal

        var prefix: String {
            switch self {
            case .debug: "D"
            case .info: "I"
            case .error: "ERROR"
            case .fatal: "FATAL"
            }
        }
    }
    var verbosityLevel = Level.error

    @TaskLocal
    static var logContexts = [String]()

    private func format(_ messageBlock: () -> String,
                        file: StaticString,
                        line: Int,
                        function: StaticString,
                        level: Level) -> String {
        let contexts = LogContext.logContexts
        let prefix = contexts.joined(separator: " > ")
        let formatted = level.prefix + " " + (prefix.isEmpty ? "" : "\(prefix) | ") + "\(file):\(line) \(function): \(messageBlock())"
        if level.rawValue >= verbosityLevel.rawValue ||
            verbosePaths.contains(where: { contexts.starts(with: $0) }) {
            if formatted.count > 1024 {
                NSFuckingLog("%@", "\(formatted)")
            } else {
                NSLog("%@", "\(formatted)")
            }
        }
        return formatted

    }
    public func fatalError(_ messageBlock: @autoclosure () -> String,
                           file: StaticString,
                           line: Int,
                           function: StaticString) -> Never {
        let message = format(messageBlock, file: file, line: line, function: function, level: .fatal)
        if gDebugLogging.boolValue {
            DebugLogImpl(String(describing: file),
                         Int32(line),
                         String(describing: function),
                         message)
        }
        Self.logger.error("\(message, privacy: .public)")
        it_fatalError(message)
    }

    public func error(_ messageBlock: @autoclosure () -> String,
                      file: StaticString = #file,
                      line: Int = #line,
                      function: StaticString = #function) {
        if !gDebugLogging.boolValue {
            return
        }
        let message = format(messageBlock, file: file, line: line, function: function, level: .error)
        Self.logger.error("\(message, privacy: .public)")
        DebugLogImpl(String(describing: file), Int32(line), String(describing: function), message)
    }

    public func info(_ messageBlock: @autoclosure () -> String,
                     file: StaticString = #file,
                     line: Int = #line,
                     function: StaticString = #function) {
        if !gDebugLogging.boolValue {
            return
        }
        let message = format(messageBlock, file: file, line: line, function: function, level: .info)
        Self.logger.info("\(message, privacy: .public)")
        DebugLogImpl(String(describing: file), Int32(line), String(describing: function), message)
    }

    public func debug(_ messageBlock: @autoclosure () -> String,
                      file: StaticString = #file,
                      line: Int = #line,
                      function: StaticString = #function) {
        if !gDebugLogging.boolValue {
            return
        }
        let message = format(messageBlock, file: file, line: line, function: function, level: .debug)
        Self.logger.debug("\(message, privacy: .public)")
        DebugLogImpl(String(describing: file), Int32(line), String(describing: function), message)
    }

    func assert(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String, file: StaticString, line: Int, function: StaticString) {
        if !condition() {
            fatalError(message(), file: file, line: Int(line), function: function)
        }
    }

    func preconditionFailure(_ message: @autoclosure () -> String, file: StaticString, line: Int, function: StaticString) -> Never {
        fatalError(message(), file: file, line: Int(line), function: function)
    }

    func inContext<T>(_ prefix: String, closure: () throws -> T) rethrows -> T {
        return try logging(prefix, closure: closure)
    }

    func inContext<T>(_ prefix: String, closure: () async throws -> T) async rethrows -> T {
        return try await logging(prefix, closure: closure)
    }

    public func logging<T>(_ prefix: String, closure: () throws -> T) rethrows -> T {
        return try iTermLogger.$logContexts.withValue(iTermLogger.logContexts + [prefix]) {
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
    public func logging<T>(_ prefix: String, closure: () async throws -> T) async rethrows -> T {
        return try await iTermLogger.$logContexts.withValue(iTermLogger.logContexts + [prefix]) {
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
}

@objc(iTermCallbackLogging)
class iTermCallbackLogging: NSObject {
    @objc static var callback: ((String) -> ())? = nil

    @available(macOS 11.0, *)
    static let logger = iTermLogger()
}

public class LogContext {
    @TaskLocal
    static var logContexts = ["Root"]
}

public func log(_ message: String) {
    if #available(macOS 11.0, *) {
        let prefix = LogContext.logContexts.joined(separator: " > ")
        iTermCallbackLogging.logger.info("\(prefix): \(message)")
    }
    iTermCallbackLogging.callback?(message)
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

@_transparent
func it_assert(
    _ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #file,
    line: UInt = #line,
    function: StaticString = #function
) {
    if !condition() {
        let logMessage = "[ASSERT FAILED] \(message())"
        LogForNextCrash(file.utf8Start,
                        Int32(line),
                        function.utf8Start,
                        logMessage,
                        true)

        assertionFailure("\(file):\(line) in \(function): \(logMessage)")
        iTermCrashWithMessage(file.utf8Start,
                              Int32(line),
                              function.utf8Start,
                              logMessage)
    }
}

@_transparent
func it_fatalError(
    _ message: @autoclosure () -> String = "",
    file: StaticString = #file,
    line: UInt = #line,
    function: StaticString = #function
) -> Never {
    let logMessage = "[FATAL ERROR] \(message())"
    LogForNextCrash(file.utf8Start,
                    Int32(line),
                    function.utf8Start,
                    logMessage,
                    true)
    iTermCrashWithMessage(file.utf8Start,
                          Int32(line),
                          function.utf8Start,
                          logMessage)
}

@_transparent
func it_preconditionFailure(
    _ message: @autoclosure () -> String = "",
    file: StaticString = #file,
    line: UInt = #line,
    function: StaticString = #function
) -> Never {
    let logMessage = "[FATAL ERROR] \(message())"
    LogForNextCrash(file.utf8Start,
                    Int32(line),
                    function.utf8Start,
                    logMessage,
                    true)
    iTermCrashWithMessage(file.utf8Start,
                          Int32(line),
                          function.utf8Start,
                          logMessage)
}

@available(*, unavailable, message: "Use it_assert instead of assert")
public func assert(
    _ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #file,
    line: UInt = #line
) {
}

@available(*, unavailable, message: "Use it_fatalError instead of fatalError")
public func fatalError(
    _ message: @autoclosure () -> String = "",
    file: StaticString = #file,
    line: UInt = #line
) -> Never {
    abort()
}

@available(*, unavailable, message: "Use it_fatalError instead of fatalError")
public func preconditionFailure(
    _ message: @autoclosure () -> String = "",
    file: StaticString = #file,
    line: UInt = #line
) -> Never {
    abort()
}

extension iTermLogger: BrowserExtensionLogger {}
