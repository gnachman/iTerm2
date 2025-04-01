//
//  NSFileManager+iTerm.swift
//  iTerm2
//
//  Created by George Nachman on 2/5/25.
//

extension FileManager {
    @objc
    func it_promptToCreateEnclosingDirectory(for filePath: String,
                                             title: String,
                                             identifier: String,
                                             window: NSWindow?) -> Bool {
        let directoryPath = (filePath as NSString).deletingLastPathComponent
        var isDir: ObjCBool = false

        if fileExists(atPath: directoryPath, isDirectory: &isDir) && isDir.boolValue {
            return true
        }
        let selection = iTermWarning.show(withTitle: "Would you like to create the directory at \(directoryPath)?",
                                          actions: ["OK", "Cancel"],
                                          accessory: nil,
                                          identifier: "CreateDirectory_" + identifier,
                                          silenceable: .kiTermWarningTypePermanentlySilenceable,
                                          heading: title,
                                          window: window
                                          )
        if selection == .kiTermWarningSelection0 {
            do {
                try createDirectory(atPath: directoryPath,
                                    withIntermediateDirectories: true,
                                    attributes: nil)
                return true
            } catch {
                let selection = iTermWarning.show(withTitle: "Failed to create \(directoryPath):\n\n\(error.localizedDescription)",
                                                  actions: ["Try Again", "Cancel"],
                                                  accessory: nil,
                                                  identifier: nil,
                                                  silenceable: .kiTermWarningTypePersistent,
                                                  heading: title,
                                                  window: window)
                if selection == .kiTermWarningSelection0 {
                    return it_promptToCreateEnclosingDirectory(for: filePath,
                                                               title: title,
                                                               identifier: identifier,
                                                               window: window)
                }
            }
        }
        return false
    }

    func isWritableByRoot(path: String) -> Bool {
        // I have to go directly to user defaults rather than through
        // iTermAdvancedSettingsModel because this is called during
        // iTermAdvancedSettingsModel.initialize, so its values may not be
        // loaded yet.
        let pathsToIgnore = UserDefaults.standard.string(forKey: "PathsToIgnore")?.components(
            separatedBy: ",") ?? []
        let isLocal = FileManager.default.fileIsLocal(
            path,
            additionalNetworkPaths: pathsToIgnore,
            allowNetworkMounts: false)
        if !isLocal {
            // On network directory
            return false
        }

        var fs = statfs()
        guard statfs(path, &fs) == 0 else {
            return false
        }

        // Copy f_fstypename to a local variable to avoid overlapping accesses
        let fsFstypenameCopy = fs.f_fstypename
        let fsType = withUnsafePointer(to: fsFstypenameCopy) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: fsFstypenameCopy)) {
                String(cString: $0)
            }
        }

        let ignoreOwnership = (fs.f_flags & UInt32(MNT_IGNORE_OWNERSHIP)) != 0
        let lowerFsType = fsType.lowercased()

        if lowerFsType == "apfs" || lowerFsType.contains("hfs") {
            return true
        }

        if lowerFsType == "exfat" || lowerFsType == "msdos" {
            return true
        }

        return ignoreOwnership
    }
}
