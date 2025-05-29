//
//  SystemFolderIconProvider.swift.swift
//  iTerm2
//
//  Created by George Nachman on 6/9/25.
//

import Foundation
import AppKit

class SystemFolderIconProvider {

    // Cache for loaded icons
    private static var iconCache: [String: NSImage] = [:]

    // Complete mapping from CoreTypes.bundle Info.plist for all folder types
    private static let folderUTIMap: [String: String] = [
        // Special system folders (using _UTTypeTemplateIconFile for sidebar versions)
        "com.apple.downloads-folder": "SidebarDownloadsFolder.icns",
        "com.apple.desktop-folder": "SidebarDesktopFolder.icns",
        "com.apple.documents-folder": "SidebarDocumentsFolder.icns",
        "com.apple.applications-folder": "SidebarApplicationsFolder.icns",
        "com.apple.server-applications-folder": "SidebarGenericFolder.icns",
        "com.apple.library-folder": "SidebarGenericFolder.icns",
        "com.apple.document-type.system-folder": "SidebarGenericFolder.icns",
        "com.apple.movie-folder": "SidebarMoviesFolder.icns",
        "com.apple.music-folder": "SidebarMusicFolder.icns",
        "com.apple.pictures-folder": "SidebarPicturesFolder.icns",
        "com.apple.public-folder": "SidebarGenericFolder.icns",
        "com.apple.home-folder": "SidebarHomeFolder.icns",
        "com.apple.developer-folder": "SidebarGenericFolder.icns",
        "com.apple.users-folder": "SidebarGenericFolder.icns",
        "com.apple.utilities-folder": "SidebarUtilitiesFolder.icns",

        // Special folder types
        "com.apple.finder.burn-folder": "SidebarBurnFolder.icns",
        "com.apple.finder.smart-folder": "SidebarSmartFolder.icns",
        "com.apple.finder.recent-items": "SidebarRecents.icns",
        "com.apple.drop-folder": "SidebarDropBoxFolder.icns",

        // Generic folder
        "public.folder": "SidebarGenericFolder.icns",

        // This is my hack which I use to represent a server.
        "com.apple.imac": "SidebariMac.icns",
    ]

    // Map standard directories to their UTIs
    private static let systemDirectoryMap: [(FileManager.SearchPathDirectory, String)] = [
        (.downloadsDirectory, "com.apple.downloads-folder"),
        (.desktopDirectory, "com.apple.desktop-folder"),
        (.documentDirectory, "com.apple.documents-folder"),
        (.musicDirectory, "com.apple.music-folder"),
        (.picturesDirectory, "com.apple.pictures-folder"),
        (.moviesDirectory, "com.apple.movie-folder"),
        (.applicationDirectory, "com.apple.applications-folder"),
        (.libraryDirectory, "com.apple.library-folder")
    ]

    // Map special folder names to their UTIs (for folders like Developer, Utilities)
    private static let specialFolderNames: [String: String] = [
        "Developer": "com.apple.developer-folder",
        "Utilities": "com.apple.utilities-folder",
        "Users": "com.apple.users-folder",
        "Public": "com.apple.public-folder"
    ]

    /// Get the appropriate icon for a folder path
    static func iconForFolder(at url: URL) -> NSImage? {
        // First check if it's a special system folder by path
        if let uti = getUTIForSystemFolder(url: url) {
            return iconForUTI(uti)
        }

        // Check for special folder names
        let folderName = url.lastPathComponent
        if let uti = specialFolderNames[folderName] {
            return iconForUTI(uti)
        }

        // Check if it's a special file type (burn folder, smart folder, etc.)
        if let uti = getUTIForSpecialFileType(url: url) {
            return iconForUTI(uti)
        }

        // Fall back to generic folder icon
        return iconForUTI("public.folder")
    }

    /// Get icon for a specific UTI
    static func iconForUTI(_ uti: String) -> NSImage? {
        guard let iconFile = folderUTIMap[uti] else {
            return iconForUTI("public.folder") // fallback
        }

        return loadIconFromCoreTypes(named: iconFile)
    }

    /// Determine UTI for system folders by comparing paths
    private static func getUTIForSystemFolder(url: URL) -> String? {
        let fileManager = FileManager.default

        for (searchPath, uti) in systemDirectoryMap {
            do {
                let standardURL = try fileManager.url(for: searchPath,
                                                    in: .userDomainMask,
                                                    appropriateFor: nil,
                                                    create: false)
                if url.standardized.path == standardURL.standardized.path {
                    return uti
                }
            } catch {
                continue
            }
        }

        // Check for home folder
        if url.standardized.path == fileManager.homeDirectoryForCurrentUser.standardized.path {
            return "com.apple.home-folder"
        }

        return nil
    }

    /// Check for special file types (burn folders, smart folders, etc.)
    private static func getUTIForSpecialFileType(url: URL) -> String? {
        // Check file extensions for special folder types
        let pathExtension = url.pathExtension.lowercased()

        switch pathExtension {
        case "fpbf": // Burn folder
            return "com.apple.finder.burn-folder"
        case "savedsearch": // Smart folder
            return "com.apple.finder.smart-folder"
        default:
            break
        }

        // Check for drop folder (this would require additional logic to detect drop folders)
        // Drop folders are regular folders with special properties

        return nil
    }

    /// Load a specific icon from CoreTypes.bundle
    static func loadIconFromCoreTypes(named iconFile: String) -> NSImage? {
        // Check cache first
        if let cachedIcon = iconCache[iconFile] {
            return cachedIcon
        }

        // Path to CoreTypes bundle
        let coreTypesPath = "/System/Library/CoreServices/CoreTypes.bundle"
        guard let bundle = Bundle(path: coreTypesPath) else {
            return nil
        }

        // Remove .icns extension if present for resource lookup
        let resourceName = iconFile.replacingOccurrences(of: ".icns", with: "")

        // Try to load the icon
        var image: NSImage?

        if let iconPath = bundle.path(forResource: resourceName, ofType: "icns") {
            image = NSImage(contentsOfFile: iconPath)
        }

        // Cache the result (even if nil)
        iconCache[iconFile] = image

        return image
    }

    /// Get all folder UTIs defined in the system
    static func getAllFolderUTIs() -> [String] {
        return Array(folderUTIMap.keys).sorted()
    }

    /// Get the total count of folder UTIs (for debugging)
    static func getFolderUTICount() -> Int {
        return folderUTIMap.count
    }
}
