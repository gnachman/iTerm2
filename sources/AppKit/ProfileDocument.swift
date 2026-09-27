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
                    withTitle: String(localized: "ProfileDocument.RenamedPrompt", defaultValue: "Would you like to open the profile formerly named \(name) that is now called \(newName) (which this shortcut refers to), or the profile that currently has the name \(name)?", comment: "Prompt asking which profile to open when a shortcut refers to a renamed profile"),
                    actions: [ String(localized: "ProfileDocument.OpenName", defaultValue: "Open \(name)", comment: "Button to open the profile that currently has the old name"), String(localized: "ProfileDocument.OpenNewName", defaultValue: "Open \(newName)", comment: "Button to open the renamed profile the shortcut refers to"), iTermLocalizedCancel()],
                    accessory: nil,
                    identifier: "NoSyncOpenRenamedProfile",
                    silenceable: .kiTermWarningTypePermanentlySilenceable,
                    heading: String(localized: "ProfileDocument.RenamedHeading", defaultValue: "Profile Renamed", comment: "Heading of the alert shown when a profile shortcut refers to a renamed profile"),
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
            RLog("Failed to open \(filename): \(error)")
        }
    }

    // Locale-independent on-disk name for the Recents symlink. This filename is
    // effectively an identifier: both the create and cleanup paths key off it, so
    // it MUST NOT be localized. If it varied by language, switching the UI
    // language would strand the links created under the previous language on disk
    // (their targets are still valid), and macOS Recents would then show one
    // duplicate entry per language for the same profile, forever.
    static func recentsLinkFilename(name: String) -> String {
        return "New “\(name)” tab"
    }

    // Writes the realfile that backs a Recents entry and (re)creates the stable
    // symlink at linkURL pointing at it. Because linkURL's filename is
    // locale-independent (see recentsLinkFilename), calling this again for the
    // same profile overwrites the same link instead of leaving a per-language
    // duplicate behind.
    static func writeRecentLink(guid: String, name: String, linkURL: URL, basePath: String) throws {
        try? FileManager.default.createDirectory(atPath: basePath, withIntermediateDirectories: false)
        // Use a fresh UUID because profile names are subject to change and you don't want
        // to be in a situation where a profile gets renamed and you have two links
        // with different names ("Old Name" and "New Name") linking to the same .itermtab
        // file, as one will certainly disagree with the contents of the file, which also
        // lists the name.
        let path = basePath.appending(pathComponent: UUID().uuidString + ".itermtab")
        let realURL = URL(fileURLWithPath: path)
        let contents = guid + "\n" + name
        try contents.write(to: realURL, atomically: false, encoding: .utf8)

        try? FileManager.default.removeItem(at: linkURL)
        try FileManager.default.createSymbolicLink(atPath: linkURL.path,
                                                   withDestinationPath: realURL.lastPathComponent)
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
            // The symlink filename is a locale-independent identifier (see
            // recentsLinkFilename). Both the create and cleanup paths key off it,
            // so it must not change when the UI language changes.
            let linkURL = URL(fileURLWithPath: basePath.appending(pathComponent: recentsLinkFilename(name: name)))
            if cache[guid] != name {
                do {
                    try writeRecentLink(guid: guid, name: name, linkURL: linkURL, basePath: basePath)
                } catch {
                    RLog("Failed to write recent link \(linkURL.absoluteString): \(error)")
                    return
                }
                cache[guid] = name
            }
            DispatchQueue.main.async {
                // Somehow a user ended up with resolved symlinks and visible GUIDs. If that happens
                // remove them all, which is my only option. Issue 11198
                if NSDocumentController.shared.recentDocumentURLs.contains(where: { url in
                    url.pathExtension == "itermtab"
                }) {
                    NSDocumentController.shared.clearRecentDocuments(nil)
                }
                NSDocumentController.shared.noteNewRecentDocumentURL(linkURL)
            }
        }
    }
}
