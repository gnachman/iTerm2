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

    @objc(saveWithDefaultName:window:)
    func save(defaultName: String, window: NSWindow) {
        let savePanel = NSSavePanel()
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

        if #available(macOS 11, *) {
            savePanel.allowedContentTypes = [ UTType.flatRTFD ]
        }
        savePanel.allowedFileTypes = [ "rtf" ]

        savePanel.beginSheetModal(for: window) { response in
            self.finish(savePanel: savePanel, window: window, response: response)
        }
    }

    private func finish(savePanel: NSSavePanel,
                        window: NSWindow,
                        response: NSApplication.ModalResponse) {
        guard response == .OK, let url = savePanel.url else {
            return
        }
        promise.wait().whenFirst { [weak window] attributedString in
            if let window {
                reallySave(window: window, url: url, attributedString: attributedString)
            }
        }
    }

    private func reallySave(window: NSWindow,
                            url: URL,
                            attributedString: NSAttributedString) {
        do {
            let documentAttributes: [NSAttributedString.DocumentAttributeKey: Any] = [
                .documentType: NSAttributedString.DocumentType.rtf
            ].merging(self.documentAttributes) { (_, new) in new }

            let range = NSRange(location: 0, length: attributedString.length)
            let rtfData = try attributedString.data(from: range,
                                                    documentAttributes: documentAttributes)
            try rtfData.write(to: url)
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
