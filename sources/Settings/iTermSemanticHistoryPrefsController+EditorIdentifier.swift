//
//  iTermSemanticHistoryPrefsController+EditorIdentifier.swift
//  iTerm2SharedARC
//

import Foundation

@objc
extension iTermSemanticHistoryPrefsController {
    // Returns the known editor constant (such as kZedAppIdentifier) that names
    // the same app as bundleId, or nil if bundleId is not a known editor.
    //
    // Bundle IDs compare case-insensitively, as Launch Services does. This
    // matters because some constants differ in case from the shipping app: Zed
    // is dev.zed.Zed but kZedAppIdentifier is dev.zed.zed. The constants can't
    // simply be corrected because saved preferences hold them, so callers that
    // start from a real bundle ID normalize it here and then compare against
    // the constants exactly.
    @objc(editorIdentifierForBundleId:)
    static func editorIdentifier(forBundleId bundleId: String?) -> String? {
        guard let bundleId else {
            return nil
        }
        return editorsInPreferenceOrder().first {
            $0.caseInsensitiveCompare(bundleId) == .orderedSame
        }
    }
}
