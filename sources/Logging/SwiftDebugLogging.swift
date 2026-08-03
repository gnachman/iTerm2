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
    DebugLogImpl(file.cString(using: .utf8)!, Int32(line), function.cString(using: .utf8)!, message)
}

func DLogMain(_ messageBlock: @autoclosure () -> String, file: String = #file, line: Int = #line, function: String = #function) {
    guard gDebugLogging.boolValue else {
        return
    }
    let message = messageBlock()
    // print("\(file):\(line) \(function): \(message)")
    DebugLogImpl(file.cString(using: .utf8)!, Int32(line), function.cString(using: .utf8)!, message)
}

// Retrospective log. Like DLog when debug logging is on, but when it is off the
// message is retained in a bounded in-memory ring (see RetrospectiveLogImpl) so
// the lead-up to a low-frequency event can be recovered later. The message is a
// plain String, not an @autoclosure: unlike DLog it is always evaluated (that is
// how it captures retrospectively), so the non-deferred parameter makes the cost
// explicit. Only use it for low-frequency call sites with cheap arguments.
// The message type accepted by RLog. Ordinary string literals and interpolations
// work unchanged, but it adds a redacting interpolation:
//
//   RLog("open \(redacted: url, or: url.it_redactedDescription)")
//
// `redacted:` resolves to the full value when debug logging is on (RLog feeds the
// opt-in debug log then, which should stay complete) and to the `or:` placeholder
// when off (the message is bound only for the always-on retrospective ring, which
// must not accumulate private data). Only the chosen branch is evaluated, so an
// expensive full value is never stringified on the ring path. This removes the
// need to pair an RLog breadcrumb with a separate DLog carrying the full value.
struct RLogMessage: ExpressibleByStringInterpolation {
    let rendered: String

    init(stringLiteral value: String) {
        rendered = value
    }

    init(stringInterpolation: StringInterpolation) {
        rendered = stringInterpolation.output
    }

    struct StringInterpolation: StringInterpolationProtocol {
        var output = ""

        init(literalCapacity: Int, interpolationCount: Int) {
            output.reserveCapacity(literalCapacity)
        }

        mutating func appendLiteral(_ literal: String) {
            output += literal
        }

        mutating func appendInterpolation<T>(_ value: T) {
            output += String(describing: value)
        }

        mutating func appendInterpolation(redacted full: @autoclosure () -> Any,
                                          or placeholder: @autoclosure () -> Any = "[redacted]") {
            output += gDebugLogging.boolValue ? "\(full())" : "\(placeholder())"
        }
    }
}

func RLog(_ message: RLogMessage, file: String = #file, line: Int = #line, function: String = #function) {
    RetrospectiveLogImpl(file.cString(using: .utf8)!, Int32(line), function.cString(using: .utf8)!, message.rendered)
}

// A returnable redactable, for the case a helper needs to hand back a value that
// redacts itself when interpolated (the inline `\(redacted:)` form above can't be
// returned from a function). Same rule: full when debug logging is on, redacted
// when off. Prefer `\(redacted:)` at the call site; use this only for helpers.
struct RLogRedacted: CustomStringConvertible {
    let full: Any
    let redacted: Any
    var description: String { gDebugLogging.boolValue ? "\(full)" : "\(redacted)" }
}

func XLog(_ messageBlock: @autoclosure () -> String, file: String = #file, line: Int = #line, function: String = #function) {
    guard gDebugLogging.boolValue else {
        return
    }
    let message = messageBlock()
    NSLog("\(file):\(line) \(function): \(message)")
    DebugLogImpl(file.cString(using: .utf8)!, Int32(line), function.cString(using: .utf8)!, message)
}

class iTermLogger {
    static let instance = iTermLogger()
    private static let logger = Logger(subsystem: "com.iterm2.logger", category: "main")
    let verbosePaths = Set<[String]>()
    var loggerPrefix = ""
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
    var nslog = true
    var oslog = false

    @TaskLocal
    static var logContexts = [String]()

    private func shouldLogVerbosely(level: Level) -> Bool {
        let contexts = LogContext.logContexts
        return (level.rawValue >= verbosityLevel.rawValue ||
                verbosePaths.contains(where: { contexts.starts(with: $0) }))
    }

    private func format(_ messageBlock: () -> String,
                        file: StaticString,
                        line: Int,
                        function: StaticString,
                        level: Level) -> String {
        let contexts = LogContext.logContexts
        let prefix = contexts.joined(separator: " > ")
        let formatted = "\(loggerPrefix)\(level.prefix) \(prefix.isEmpty ? "" : "\(prefix) | "))\((String(describing: file) as NSString).lastPathComponent):\(line) \(function): \(messageBlock())"
        if shouldLogVerbosely(level: level) {
            if nslog {
                if formatted.count > 1024 {
                    NSFuckingLog("%@", "\(formatted)")
                } else {
                    NSLog("%@", "\(formatted)")
                }
            }
            if oslog {
                switch level {
                case .debug:
                    Self.logger.debug("\(formatted, privacy: .public)")
                case .info:
                    Self.logger.info("\(formatted, privacy: .public)")
                case .error:
                    Self.logger.error("\(formatted, privacy: .public)")
                case .fatal:
                    Self.logger.critical("\(formatted, privacy: .public)")
                }
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
        if gDebugLogging.boolValue || shouldLogVerbosely(level: .error) {
            let message = format(messageBlock, file: file, line: line, function: function, level: .error)
            DebugLogImpl(String(describing: file), Int32(line), String(describing: function), message)
        }
    }

    public func info(_ messageBlock: @autoclosure () -> String,
                     file: StaticString = #file,
                     line: Int = #line,
                     function: StaticString = #function) {
        if gDebugLogging.boolValue || shouldLogVerbosely(level: .info) {
            let message = format(messageBlock, file: file, line: line, function: function, level: .info)
            DebugLogImpl(String(describing: file), Int32(line), String(describing: function), message)
        }
    }

    public func debug(_ messageBlock: @autoclosure () -> String,
                      file: StaticString = #file,
                      line: Int = #line,
                      function: StaticString = #function) {
        if gDebugLogging.boolValue || shouldLogVerbosely(level: .debug) {
            let message = format(messageBlock, file: file, line: line, function: function, level: .debug)
            DebugLogImpl(String(describing: file), Int32(line), String(describing: function), message)
        }
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
