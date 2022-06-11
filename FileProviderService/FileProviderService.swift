//
//  FileProviderService.swift
//  FileProviderService
//
//  Created by George Nachman on 6/5/22.
//

import Foundation
import FileProvider

@available(macOS 11.0, *)
public struct SSHConnectionIdentifier: Codable, Hashable, CustomDebugStringConvertible {
    public let identity: SSHIdentity
    public var name: String { identity.compactDescription }

    public var stringIdentifier: String {
        return identity.stringIdentifier
    }
    
    public var debugDescription: String {
        return stringIdentifier
    }

    public init(_ identity: SSHIdentity) {
        self.identity = identity
    }

    public init?(stringIdentifier string: String) {
        let parts = string.components(separatedBy: ";")
        guard parts.count == 2 else {
            return nil
        }
        guard let identity = SSHIdentity(stringIdentifier: parts[1]) else {
            return nil
        }
        self.identity = identity
    }
}

@available(macOS 11.0, *)
public struct SSHListFilesItem: Codable, CustomDebugStringConvertible {
    // Path is relative
    public let path: String

    public var debugDescription: String {
        return path
    }

    public init(_ path: String) {
        self.path = path
    }
}

// I failed to extend Result to be codable and I don't know why.
@available(macOS 11.0, *)
public enum iTermResult<Success: Codable, Failure: Codable>: Codable {
    case success(Success)
    case failure(Failure)

    enum Key: CodingKey {
        case rawValue
        case associatedValue
    }

    enum RawCases: Codable {
        case success
        case failure
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .success(let value):
            try container.encode(RawCases.success, forKey: .rawValue)
            try container.encode(value, forKey: .associatedValue)
        case .failure(let value):
            try container.encode(RawCases.failure, forKey: .rawValue)
            try container.encode(value, forKey: .associatedValue)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        switch try container.decode(RawCases.self, forKey: .rawValue) {
        case .success:
            self = .success(try container.decode(Success.self, forKey: .associatedValue))
        case .failure:
            self = .failure(try container.decode(Failure.self, forKey: .associatedValue))
        }
    }
}

@available(macOS 11.0, *)
public enum FetchError: Error, Codable {
    case disconnected
    case fileNotFound
    case accessDenied
    case other
}

// This odious class and its equally odious neighbor exist because XPC payloads must be
// NSSecureCoding and I want to use synthesized coders and I also refuse to implement manual coding
// for NSCoding when I have a perfectly good synthesized coder. To make matters worse, these can't
// be generic because generics can't have statics which prevents their conformance to
// NSSecureCoding. And to make matters worse, generics can't be @objc. So duplicate code and have a
// few drinks and move on with life.
@available(macOS 11.0, *)
public class MainAppToExtension: NSObject, NSSecureCoding {
    public static var supportsSecureCoding = true
    public let value: MainAppToExtensionPayload

    init(_ value: MainAppToExtensionPayload) {
        self.value = value
    }

    public convenience init(events: [MainAppToExtensionPayload.Event]) {
        self.init(MainAppToExtensionPayload(events: events))
    }

    public func encode(with coder: NSCoder) {
        let encoder = JSONEncoder()
        let data = try! encoder.encode(value)
        coder.encode(data as NSData, forKey: "data")
    }

    public required init?(coder: NSCoder) {
        guard let data = coder.decodeObject(of: NSData.self, forKey: "data") else {
            return nil
        }
        let decoder = JSONDecoder()
        guard let value = try? decoder.decode(MainAppToExtensionPayload.self, from: data as Data) else {
            return nil
        }
        self.value = value
    }
}

@available(macOS 11.0, *)
public class ExtensionToMainApp: NSObject, NSSecureCoding {
    public static var supportsSecureCoding = true
    public let value: ExtensionToMainAppPayload

    public init(_ value: ExtensionToMainAppPayload) {
        self.value = value
    }

    public convenience init(events: [ExtensionToMainAppPayload.Event]) {
        self.init(ExtensionToMainAppPayload(events: events))
    }

    public func encode(with coder: NSCoder) {
        let encoder = JSONEncoder()
        let data = try! encoder.encode(value)
        coder.encode(data as NSData, forKey: "data")
    }

    public required init?(coder: NSCoder) {
        guard let data = coder.decodeObject(of: NSData.self, forKey: "data") else {
            return nil
        }
        let decoder = JSONDecoder()
        guard let value = try? decoder.decode(ExtensionToMainAppPayload.self, from: data as Data) else {
            return nil
        }
        self.value = value
    }
}


@available(macOS 11.0, *)
public class MainAppToExtensionPayload: NSObject, Codable {
    public struct Event: Codable, CustomDebugStringConvertible {
        public enum Kind: Codable, CustomDebugStringConvertible {
            case connectionList([SSHConnectionIdentifier])
            case fileList(iTermResult<[SSHListFilesItem], FetchError>)
            case fetch(iTermResult<Data, FetchError>)
            case invalidConnection

            public var debugDescription: String {
                switch self {
                case .connectionList(let ids):
                    return "<connectionList \(ids.map { $0.debugDescription }.joined(separator: ", "))>"
                case .fileList(let result):
                    switch result {
                    case .success(let items):
                        return "<fileList \(items.map { $0.debugDescription }.joined(separator: ", "))>"
                    case .failure(let error):
                        return "<fileList error=\(String(describing: error))>"
                    }
                case .fetch(let result):
                    switch result {
                    case .success(let data):
                        return "<fetch success: \(data.count) bytes>"
                    case .failure(let error):
                        return "<fetch error: \(error)>"
                    }
                case .invalidConnection:
                    return "<invalidConnection>"
                }
            }
        }
        public let kind: Kind
        public let eventID: String

        public init(kind: Kind, eventID: String) {
            self.kind = kind
            self.eventID = eventID
        }

        public var debugDescription: String {
            return "<MainAppToExtensionPayload.Event: id=\(eventID) kind=\(kind.debugDescription)>"
        }
    }

    public let events: [Event]

    public init(events: [Event]) {
        self.events = events
    }

    public override var debugDescription: String {
        return "<MainAppToExtension: \(events.map { $0.debugDescription }.joined(separator: "; "))>"
    }
}

@available(macOS 11.0, *)
public class ExtensionToMainAppPayload: NSObject, Codable {
    public struct Event: Codable, CustomDebugStringConvertible {
        public enum Kind: Codable, CustomDebugStringConvertible {
            case invalid
            case listConnections
            case listFiles(connection: SSHConnectionIdentifier, path: String)
            case fetch(connection: SSHConnectionIdentifier, path: String)

            public var debugDescription: String {
                switch self {
                case .invalid:
                    return "<invalid>"
                case .listConnections:
                    return "<listConnections>"
                case .listFiles(connection: _, path: let path):
                    return "<listFiles path=\(path)>"
                case .fetch(connection: _, path: let path):
                    return "<fetch path=\(path)>"
                }
            }
        }
        public let kind: Kind
        public let eventID: String

        public init(kind: Kind, eventID: String) {
            self.kind = kind
            self.eventID = eventID
        }

        public init(kind: Kind) {
            self.kind = kind
            eventID = UUID().uuidString
        }

        public func response(_ responseKind: MainAppToExtensionPayload.Event.Kind) -> MainAppToExtensionPayload.Event {
            return MainAppToExtensionPayload.Event(kind: responseKind, eventID: eventID)
        }

        public var debugDescription: String {
            return "<ExtensionToMainAppPayload.Event id=\(eventID) kind=\(kind.debugDescription)>"
        }
    }

    public let events: [Event]

    public init(events: [Event]) {
        self.events = events
    }

    public override var debugDescription: String {
        return "<ExtensionToMainApp: \(events.map { $0.debugDescription }.joined(separator: "; "))>"
    }
}

@available(macOS 11.0, *)
@objc public protocol iTermFileProviderServiceV1 {
    func poll(_ m2e: MainAppToExtension) async throws -> ExtensionToMainApp
}

@available(macOS 11.0, *)
public let iTermFileProviderServiceName = NSFileProviderServiceName("com.googlecode.iterm2.FileProviderService")

@available(macOS 11.0, *)
public let iTermFileProviderServiceInterface: NSXPCInterface = {
    let interface = NSXPCInterface(with: iTermFileProviderServiceV1.self)
    // Specify the classes that Set may contain in the XPC interface.
    interface.setClasses(NSSet(array: [MainAppToExtension.self]) as! Set<AnyHashable>,
                         for: #selector(iTermFileProviderServiceV1.poll(_:)), argumentIndex: 0, ofReply: false)

    interface.setClasses(NSSet(array: [ExtensionToMainApp.self]) as! Set<AnyHashable>,
                         for: #selector(iTermFileProviderServiceV1.poll(_:)), argumentIndex: 0, ofReply: true)
    return interface
}()

