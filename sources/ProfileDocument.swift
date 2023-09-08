//
//  ProfileDocument.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/19/23.
//

import Foundation

// This is responsible for handling the NSDocument recents list, which is in the context menu
// of the dock tile *even when the app is not running*.
@objc
class ProfileDocument: NSObject {
    private static let queue = DispatchQueue(label: "com.iterm2.recents")
    private static var cache = [String: String]()
    private static let folder = "Recents"

    @objc
    static func removeAllRecents() {
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    @objc
    static func open(filename: String) {
        do {
            let url = URL(fileURLWithPath: filename)
            let contents = try String(contentsOf: url)
            let parts = contents.components(separatedBy: "\n")
            guard parts.count >= 2 else {
                DLog("Invalid content: \(contents)")
                return
            }
            let (guid, name) = (parts[0], parts[1])
            guard var profile = ProfileModel.sharedInstance().bookmark(withGuid: guid) else {
                return
            }

            let controller = iTermController.sharedInstance()!
            if let newName = iTermProfilePreferences.string(forKey: KEY_NAME, inProfile: profile),
                newName != name,
                let profileWithName = ProfileModel.sharedInstance().bookmark(withName: name) {
                let selection = iTermWarning.show(
                    withTitle: "Would you like to open the profile formerly named \(name) that is now called \(newName) (which this shortcut refers to), or the profile that currently has the name \(name)?",
                    actions: [ "Open \(name)", "Open \(newName)", "Cancel"],
                    accessory: nil,
                    identifier: "NoSyncOpenRenamedProfile",
                    silenceable: .kiTermWarningTypePermanentlySilenceable,
                    heading: "Profile Renamed",
                    window: controller.currentTerminal?.window())
                switch selection {
                case .kiTermWarningSelection0:
                    // Open by GUID
                    break
                case .kiTermWarningSelection1:
                    // Open by name
                    profile = profileWithName
                default:
                    return
                }
            }
            iTermSessionLauncher.launchBookmark(profile,
                                                in: controller.currentTerminal,
                                                respectTabbingMode: false)
        } catch {
            DLog("Failed to open \(filename): \(error)")
        }
    }

    @objc
    static func addToRecents(guid: String, name: String) {
        guard iTermAdvancedSettingsModel.saveProfilesToRecentDocuments() else {
            return
        }
        guard let appSupport = FileManager.default.applicationSupportDirectory() else {
            return
        }
        let basePath = appSupport.appending(pathComponent: folder)
        queue.async {
            let linkURL = URL(fileURLWithPath: basePath.appending(pathComponent: "New “\(name)” tab"))
            if cache[guid] != name {
                try? FileManager.default.createDirectory(atPath: basePath, withIntermediateDirectories: false)
                // Use a fresh UUID because profile names are subject to change and you don't want
                // to be in a situation where a profile gets renamed and you have two links
                // with different names ("Old Name" and "New Name") linking to the same .itermtab
                // file, as one will certainly disagree with the contents of the file, which also
                // lists the name.
                let path = basePath.appending(pathComponent: UUID().uuidString + ".itermtab")
                let realURL = URL(fileURLWithPath: path)
                do {
                    let contents = guid + "\n" + name
                    try contents.write(to: realURL, atomically: false, encoding: .utf8)
                } catch {
                    DLog("Failed to write to \(realURL.absoluteString): \(error)")
                    return
                }

                try? FileManager.default.removeItem(at: linkURL)
                do {
                    try FileManager.default.createSymbolicLink(atPath: linkURL.path,
                                                               withDestinationPath: realURL.lastPathComponent)
                } catch {
                    DLog("Failed to link \(linkURL.absoluteString) to \(realURL.absoluteString): \(error)")
                    return
                }
                cache[guid] = name
            }
            DispatchQueue.main.async {
                NSDocumentController.shared.noteNewRecentDocumentURL(linkURL)
            }
        }
    }
}
