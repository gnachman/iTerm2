//
//  Deadline.swift
//  CompanionCore
//
//  Bounds an async operation with a wall-clock deadline, failing with a
//  descriptive TransportError instead of letting callers hang forever.
//

import Foundation
import CompanionProtocol

func withDeadline<T: Sendable>(seconds: TimeInterval,
                               label: String,
                               _ body: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            CompanionLog.log("Deadline exceeded: \(label)")
            throw TransportError.connectionFailed("\(label) timed out after \(Int(seconds)) seconds")
        }
        guard let result = try await group.next() else {
            throw TransportError.closed
        }
        group.cancelAll()
        return result
    }
}
