import Foundation

enum IT2Error: Error, CustomStringConvertible {
    case connectionError(String)
    case apiError(String)
    case targetNotFound(String)
    case invalidArgument(String)
    /// The user declined an interactive confirmation prompt.
    case cancelled

    var exitCode: Int32 {
        switch self {
        case .connectionError: return 2
        case .apiError: return 1
        case .targetNotFound: return 3
        case .invalidArgument: return 4
        case .cancelled: return 1
        }
    }

    var description: String {
        switch self {
        case .connectionError(let msg),
             .apiError(let msg),
             .targetNotFound(let msg),
             .invalidArgument(let msg):
            return msg
        case .cancelled:
            return "Aborted!"
        }
    }

    /// How to render this error to stderr. `.cancelled` is shown verbatim (it is
    /// a user action, not a failure); everything else is prefixed with "Error: ".
    var displayMessage: String {
        switch self {
        case .cancelled:
            return description
        default:
            return "Error: \(description)"
        }
    }
}
