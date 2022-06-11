//
//  FileProviderItem.swift
//  iTermFileProvider
//
//  Created by George Nachman on 6/4/22.
//

import FileProvider
import UniformTypeIdentifiers
import FileProviderService

class RootListFileProviderItem: NSObject, NSFileProviderItem {
    private static var versions = [[SSHConnectionIdentifier]: NSFileProviderItemVersion]()
    // TODO: implement an initializer to create an item from your extension's backing model
    // TODO: implement the accessors to return the values from your extension's backing model
    private let connections: [SSHConnectionIdentifier]
    private let version: NSFileProviderItemVersion

    // TODO: Should be /, not 1F1E597D-2050-4809-ACC8-2A5504466A05
    //NSFileProviderItemIdentifier(rawValue: "1F1E597D-2050-4809-ACC8-2A5504466A05")
    static let itemIdentifier = NSFileProviderItemIdentifier.rootContainer

    init(_ connections: [SSHConnectionIdentifier]) {
        logger.debug("Extension: RootListFileProviderItem: init with \(connections.count) connections")
        self.connections = connections
        if let version = Self.versions[connections] {
            self.version = version
        } else {
            let contentVersion = connections.map { $0.stringIdentifier }.sorted().joined(separator: ";")
            logger.debug("Extension: RootListFileProviderItem: define version \(contentVersion, privacy: .public)")
            version = NSFileProviderItemVersion(contentVersion: contentVersion.data(using: .utf8)!,
                                                metadataVersion: Data())
            Self.versions[connections] = version
        }
        super.init()
    }
    
    var itemIdentifier: NSFileProviderItemIdentifier {
        let identifier = Self.itemIdentifier
        logger.debug("Extension: RootListFileProviderItem: return itemIdentifier of \(identifier.rawValue, privacy: .public)")
        return identifier
    }
    
    var parentItemIdentifier: NSFileProviderItemIdentifier {
        logger.debug("Extension: RootListFileProviderItem: return parent of \(NSFileProviderItemIdentifier.rootContainer.rawValue, privacy: .public)")
        return NSFileProviderItemIdentifier.rootContainer
    }
    
    var capabilities: NSFileProviderItemCapabilities {
        logger.debug("Extension: RootListFileProviderItem: return capabilities of [.allowsReading]")
        return [.allowsReading]
    }
    
    var itemVersion: NSFileProviderItemVersion {
        logger.debug("Extension: RootListFileProviderItem: return version of \(self.version, privacy: .public)")
        return version
    }
    
    var filename: String {
        logger.debug("Extension: RootListFileProviderItem: return filename of randomfilenameforroot")
        return "randomfilenameforroot"
    }
    
    var contentType: UTType {
        logger.debug("Extension: RootListFileProviderItem: return contentType of .folder")
        return .folder
    }

    override var debugDescription: String {
        return "<RootListFileProviderItem with \(connections.count) connections>"
    }
}

// Represents the root of a single remote host.
class ConnectionRootFileProviderItem: NSObject, NSFileProviderItem {
    private let identifier: NSFileProviderItemIdentifier
    private let name: String

    init(_ sshid: SSHConnectionIdentifier) {
        identifier = NSFileProviderItemIdentifier(sshid.stringIdentifier)
        name = sshid.name
        super.init()
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        return identifier
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        return RootListFileProviderItem.itemIdentifier
    }

    var capabilities: NSFileProviderItemCapabilities {
        return [.allowsReading, .allowsWriting, .allowsDeleting, .allowsAddingSubItems, .allowsContentEnumerating]
    }

    var itemVersion: NSFileProviderItemVersion {
        return NSFileProviderItemVersion.init(contentVersion: Data(), metadataVersion: Data())
    }

    var filename: String {
        return name
    }

    var contentType: UTType {
        return .folder
    }
}
