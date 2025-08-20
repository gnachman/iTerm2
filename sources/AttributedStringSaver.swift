//
//  AttributedStringSaver.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/30/24.
//

import AppKit
import UniformTypeIdentifiers

@objc(iTermAttributedStringSaver)
class AttributedStringSaver: NSObject {
    private let promise: iTermRenegablePromise<NSAttributedString>
    @objc var documentAttributes: [NSAttributedString.DocumentAttributeKey: Any] = [:]

    @objc(initWithPromise:)
    init(_ promise: iTermRenegablePromise<NSAttributedString>) {
        self.promise = promise
    }

    @MainActor
    @objc(saveWithDefaultName:window:)
    func save(defaultName: String, window: NSWindow) {
        let savePanel = iTermModernSavePanel()
        let searchPaths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let path = searchPaths.first ?? ""
        NSSavePanel.setDirectoryURL(URL(fileURLWithPath: path),
                                    onceForID: "SaveAttributedString",
                                    savePanel: savePanel)
        savePanel.nameFieldStringValue = defaultName + ".rtf"
        savePanel.canCreateDirectories = true
        savePanel.showsHiddenFiles = true
        savePanel.allowsOtherFileTypes = false
        savePanel.canSelectHiddenExtension = true
        savePanel.isExtensionHidden = false
        savePanel.preferredSSHIdentity = .localhost

        savePanel.allowedContentTypes = [ UTType.rtf ]

        savePanel.beginSheetModal(for: window) { response in
            self.finish(savePanel: savePanel, window: window, response: response)
        }
    }

    private func finish(savePanel: iTermModernSavePanel,
                        window: NSWindow,
                        response: NSApplication.ModalResponse) {
        guard response == .OK, let item = savePanel.item else {
            return
        }
        promise.wait().whenFirst { [weak window] attributedString in
            if let window {
                reallySave(window: window, item: item, attributedString: attributedString)
            }
        }
    }

    private func reallySave(window: NSWindow,
                            item: iTermSavePanelItem,
                            attributedString: NSAttributedString) {
        do {
            let documentAttributes: [NSAttributedString.DocumentAttributeKey: Any] = [
                .documentType: NSAttributedString.DocumentType.rtf
            ].merging(self.documentAttributes) { (_, new) in new }

            let range = NSRange(location: 0, length: attributedString.length)
            let rtfData = try attributedString.data(from: range,
                                                    documentAttributes: documentAttributes)
            Task {
                try await rtfData.writeTo(saveItem: item)
            }
        } catch {
            _ = iTermWarning.show(withTitle: "There was a problem saving the file: \(error.localizedDescription)",
                                  actions: ["OK"],
                                  accessory: nil,
                                  identifier: nil,
                                  silenceable: .kiTermWarningTypePersistent,
                                  heading: "Could Not Save File",
                                  window: window)
        }
    }
}
