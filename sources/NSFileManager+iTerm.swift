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
}
