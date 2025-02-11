//
//  Result+iTerm.swift
//  iTerm2
//
//  Created by George Nachman on 2/25/25.
//

extension Result: Codable where Success: Codable, Failure: Codable {
    enum CodingKeys: String, CodingKey {
        case success, failure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.success) {
            let value = try container.decode(Success.self, forKey: .success)
            self = .success(value)
        } else if container.contains(.failure) {
            let error = try container.decode(Failure.self, forKey: .failure)
            self = .failure(error)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .success,
                in: container,
                debugDescription: "Expected either a success or failure key"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .success(let value):
            try container.encode(value, forKey: .success)
        case .failure(let error):
            try container.encode(error, forKey: .failure)
        }
    }
}

extension Result {
    func map<T>(success: (Success) -> T, failure: (Failure) -> T) -> T {
        switch self {
        case .success(let s):
            return success(s)
        case .failure(let f):
            return failure(f)
        }
    }
}
