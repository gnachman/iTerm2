//
//  FileProviderService.swift
//  FileProviderService
//
//  Created by George Nachman on 6/5/22.
//

import Foundation
import FileProvider

@available(macOS 11.0, *)
public struct ListResult: CustomDebugStringConvertible, Codable {
    public var files: [RemoteFile]
    public var nextPage: Data?

    public var debugDescription: String {
        return "<ListResult: files=\(files) nextPage=\(nextPage?.description ?? "(nil)")>"
    }

    public init(files: [RemoteFile], nextPage: Data?) {
        self.files = files
        self.nextPage = nextPage
    }
}

public enum FileSorting: Codable {
    case byDate
    case byName
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

public enum iTermFileProviderServiceError: Error, Codable, CustomDebugStringConvertible {
    case todo
    case notFound(String)
    case unknown(String)
    case notAFile(String)
    case permissionDenied(String)
    case internalError(String)  // e.g., URL with contents not readable
    
    public var debugDescription: String {
        switch self {
        case .todo:
            return "<todo>"
        case .notFound(let item):
            return "<notFound \(item)>"
        case .unknown(let reason):
            return "<unknown \(reason)>"
        case .notAFile(let file):
            return "<notAFile \(file)>"
        case .permissionDenied(let file):
            return "<permissionDenied \(file)>"
        case .internalError(let reason):
            return "<internalError \(reason)>"
        }
    }

    public static func wrap<T>(_ closure: () throws -> T) throws -> T {
        do {
            return try closure()
        } catch let error as iTermFileProviderServiceError {
            throw error
        } catch {
            throw iTermFileProviderServiceError.internalError(error.localizedDescription)
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

@available(macOS 11.0, *)
public class MainAppToExtensionPayload: NSObject, Codable {
    public struct Event: Codable, CustomDebugStringConvertible {
        public enum Kind: Codable, CustomDebugStringConvertible {
            case list(iTermResult<ListResult, iTermFileProviderServiceError>)
            case lookup(iTermResult<RemoteFile, iTermFileProviderServiceError>)
            case subscribe
            case fetch(iTermResult<Data, iTermFileProviderServiceError>)
            case delete(iTermFileProviderServiceError?)
            case ln(iTermResult<RemoteFile, iTermFileProviderServiceError>)
            case mv(iTermResult<RemoteFile, iTermFileProviderServiceError>)
            case mkdir(iTermFileProviderServiceError?)
            case create(iTermFileProviderServiceError?)
            case replaceContents(iTermResult<RemoteFile, iTermFileProviderServiceError>)
            case setModificationDate(iTermResult<RemoteFile, iTermFileProviderServiceError>)
            case chmod(iTermResult<RemoteFile, iTermFileProviderServiceError>)

            public var debugDescription: String {
                switch self {
                case .list(let result):
                    return "<list \(result)>"
                case .lookup(let result):
                    return "<lookup \(result)>"
                case .subscribe:
                    return "<subscribe>"
                case .fetch(let result):
                    return "<fetch \(result)>"
                case .delete(let result):
                    return "<delete \(result.debugDescriptionOrNil)>"
                case .ln(let result):
                    return "<ln \(result)>"
                case .mv(let result):
                    return "<mv \(result)>"
                case .mkdir(let result):
                    return "<mkdir \(result.debugDescriptionOrNil)>"
                case .create(let result):
                    return "<create \(result.debugDescriptionOrNil)>"
                case .replaceContents(let result):
                    return "<replaceContents \(result)>"
                case .setModificationDate(let result):
                    return "<setModificationDate \(result)>"
                case .chmod(let result):
                    return "<chmod \(result)>"
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
            case list(path: String, requestedPage: Data?, sort: FileSorting, pageSize: Int?)
            case lookup(path: String)
            case subscribe(paths: [String])
            case fetch(path: String)
            case delete(file: RemoteFile, recursive: Bool)
            case ln(source: String, file: RemoteFile)
            case mv(file: RemoteFile, newParent: String, newName: String)
            case mkdir(file: RemoteFile)
            case create(file: RemoteFile, content: Data)
            case replaceContents(file: RemoteFile, url: URL)
            case setModificationDate(file: RemoteFile, date: Date)
            case chmod(file: RemoteFile, permissions: RemoteFile.Permissions)

            public var debugDescription: String {
                switch self {
                case let .list(path: path, requestedPage: requestedPage, sort: sort, pageSize: pageSize):
                    return "<list path=\(path) page=\(requestedPage.stringOrHex) sort=\(sort) pageSize=\(pageSize.debugDescriptionOrNil)>"
                case let .lookup(path: path):
                    return "<lookup \(path)>"
                case let .subscribe(paths: paths):
                    return "<subscribe \(paths.joined(separator: ", "))>"
                case let .fetch(path: path):
                    return "<fetch \(path)>"
                case let .delete(file: file, recursive: recursive):
                    return "<delete \(file) recursive=\(recursive)>"
                case let .ln(source: source, file: file):
                    return "<ln \(source) -> \(file)>"
                case let .mv(file: file, newParent: newParent, newName: newName):
                    return "<mv \(file) to parent \(newParent) with name \(newName)>"
                case let .mkdir(file: file):
                    return "<mkdir \(file)>"
                case let .create(file: file, content: content):
                    return "<create \(file) content size=\(content.count)>"
                case let .replaceContents(file: file, url: url):
                    return "<replaceContents \(file) \(url)>"
                case let .setModificationDate(file: file, date: date):
                    return "<setModificationDate \(file) \(date)>"
                case let .chmod(file: file, permissions: permissions):
                    return "<chmod \(file) \(permissions)>"
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

