import Foundation

enum IT2Error: Error, CustomStringConvertible {
    case connectionError(String)
    case apiError(String)
    case targetNotFound(String)
    case invalidArgument(String)

    var exitCode: Int32 {
        switch self {
        case .connectionError: return 2
        case .apiError: return 1
        case .targetNotFound: return 3
        case .invalidArgument: return 4
        }
    }

    var description: String {
        switch self {
        case .connectionError(let msg),
             .apiError(let msg),
             .targetNotFound(let msg),
             .invalidArgument(let msg):
            return msg
        }
    }
}
