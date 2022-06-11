//
//  RebaseLocalFile.swift
//  FileProvider
//
//  Created by George Nachman on 6/11/22.
//

import Foundation
import FileProvider

func rebaseLocalFile(_ manager: NSFileProviderManager, path: String) async -> String {
    return await logging("rebase local->remote \(path)") {
        if !path.hasPrefix("/") {
            log("path is relative, don't rebase")
            return path
        }
        guard let root = try? await manager.getUserVisibleURL(for: NSFileProviderItemIdentifier.rootContainer) else {
            log("can't get root, don't rebase")
            return path
        }
        if !path.hasPrefix(root.path) {
            log("path is not relative to root, don't rebase")
            return path
        }
        let result = String(path.dropFirst(root.path.count))
        log("root=\(root.path)")
        log("result=\(result)")
        return result
    }
}

func rebaseRemoteFile(_ manager: NSFileProviderManager, path: String) async -> String {
    return await logging("rebase remote->local \(path)") {
        guard let root = try? await manager.getUserVisibleURL(for: NSFileProviderItemIdentifier.rootContainer) else {
            log("can't get root, don't rebase")
            return path
        }
        return rebaseRemoteFile(root, path: path)
    }
}

func rebaseRemoteFile(_ root: URL, path: String) -> String {
    return logging("rebaseRemoteFile(\(path))") {
        if !path.hasPrefix("/") {
            log("path is relative, don't rebase")
            return path
        }
        let result = (root.path as NSString).appendingPathComponent(path)
        log("root=\(root.path)")
        log("result=\(result)")
        return result
    }
}
