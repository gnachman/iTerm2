//
//  OrchestratorError.swift
//  iTerm2SharedARC
//

import Foundation

// Errors thrown by the orchestrator dispatcher. Caught at the
// dispatch entrypoint and converted to OrchestratorResult.error so
// the LLM never sees a Swift exception. it always gets a
// well-formed tool_result with a code/message it can reason about.
enum OrchestratorError: Error {
    case unknownTool(String)
    case unknownWorkgroup(String)
    case unknownRole(workgroupID: String, role: String, available: [String] = [])
    case ambiguousWorkgroup(name: String, candidateIDs: [String])
    case permissionDenied
    case targetNoLongerExists(OrchestratorTarget)
    case malformedArgs(reason: String)
    case timeout
    case unsupported(reason: String)
    case notImplemented(String)

    var code: String {
        switch self {
        case .unknownTool: return "unknown_tool"
        case .unknownWorkgroup: return "unknown_workgroup"
        case .unknownRole: return "unknown_role"
        case .ambiguousWorkgroup: return "ambiguous_workgroup"
        case .permissionDenied: return "permission_denied"
        case .targetNoLongerExists: return "target_no_longer_exists"
        case .malformedArgs: return "malformed_args"
        case .timeout: return "timeout"
        case .unsupported: return "unsupported"
        case .notImplemented: return "not_implemented"
        }
    }

    var message: String {
        switch self {
        case .unknownTool(let name):
            return "No such tool: \(name)"
        case .unknownWorkgroup(let id):
            return "No active workgroup matches \u{201C}\(id)\u{201D}"
        case .unknownRole(let workgroupID, let role, let available):
            var msg = "Workgroup \(workgroupID) has no role \u{201C}\(role)\u{201D}"
            if !available.isEmpty {
                let quoted = available.map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", ")
                msg += ". Available roles: \(quoted)"
            }
            return msg
        case .ambiguousWorkgroup(let name, let candidateIDs):
            return "Workgroup name \u{201C}\(name)\u{201D} matches \(candidateIDs.count) active workgroups; use the workgroup_id instead. Candidates: \(candidateIDs.joined(separator: ", "))"
        case .permissionDenied:
            return "User denied permission for this action."
        case .targetNoLongerExists(let target):
            return "Target session no longer exists: workgroup=\(target.workgroupID) role=\(target.role)"
        case .malformedArgs(let reason):
            return "Malformed arguments: \(reason)"
        case .timeout:
            return "The operation timed out."
        case .unsupported(let reason):
            return "Unsupported: \(reason)"
        case .notImplemented(let detail):
            return "Not implemented yet: \(detail)"
        }
    }

    var asResult: OrchestratorResult {
        return .error(code: code, message: message)
    }
}
