//
//  SavePanelBuiltInFunction.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/9/22.
//

import Foundation

import AppKit
import UniformTypeIdentifiers

@objc(iTermSavePanelBuiltInFunction)
class SavePanelBuiltInFunction: NSObject, iTermBuiltInFunctionProtocol {
    struct Options: OptionSet {
        static let canCreateDirectories = Options(rawValue: 1 << 0)
        static let treatsFilePackagesAsDirectories = Options(rawValue: 1 << 1)
        static let showsHiddenFiles = Options(rawValue: 1 << 2)
        static let allowsOtherFileTypes = Options(rawValue: 1 << 3)
        static let canSelectHiddenExtension = Options(rawValue: 1 << 4)
        static let extensionHidden = Options(rawValue: 1 << 5)

        let rawValue: Int
    }
    @objc static func register() {
        let pathArgName = "path"
        let optionsArgName = "options"
        let extensionsArgName = "extensions"

        // Text for OK button
        let promptArgName = "prompt"

        // Text for panel title
        let titleArgName = "title"

        // Text for panel sub title
        let messageArgName = "message"

        // Text before name field, defaults to "Save As:"
        let nameFieldLabelArgName = "name_field_label"

        // Default filename
        let defaultFilenameArgName = "default_filename"

        let builtInFunction = iTermBuiltInFunction(
            name: "save_panel",
            arguments: [pathArgName: NSString.self,
                     optionsArgName: NSNumber.self,
                  extensionsArgName: NSArray.self,
                      promptArgName: NSString.self,
                       titleArgName: NSString.self,
                     messageArgName: NSString.self,
              nameFieldLabelArgName: NSString.self,
             defaultFilenameArgName: NSString.self,],
            optionalArguments: Set([pathArgName,
                                    optionsArgName,
                                    extensionsArgName,
                                    titleArgName,
                                    promptArgName,
                                    messageArgName,
                                    nameFieldLabelArgName,
                                    defaultFilenameArgName]),
            defaultValues: [:],
            context: .app) { parameters, completion in
                let panel = NSSavePanel()

                if let path = parameters[pathArgName] as? String {
                    panel.directoryURL = URL(fileURLWithPath: path)
                }
                if let types = parameters[extensionsArgName] as? [String] {
                    if #available(macOS 11, *) {
                        panel.allowedContentTypes = types.compactMap { UTType.init(filenameExtension: $0) }
                    } else {
                        panel.allowedFileTypes = types
                    }
                }
                if let prompt = parameters[promptArgName] as? String {
                    panel.prompt = prompt
                }
                if let message = parameters[messageArgName] as? String {
                    panel.message = message;
                }
                if let title = parameters[titleArgName] as? String {
                    panel.title = title
                }
                if let nameFieldLabel = parameters[nameFieldLabelArgName] as? String {
                    panel.nameFieldLabel = nameFieldLabel
                }
                if let defaultFilename = parameters[defaultFilenameArgName] as? String {
                    panel.nameFieldStringValue = defaultFilename
                }
                let options = Options(rawValue: parameters[optionsArgName] as? Int ?? 0)

                panel.canCreateDirectories = options.contains(.canCreateDirectories)
                panel.treatsFilePackagesAsDirectories = options.contains(.treatsFilePackagesAsDirectories)
                panel.showsHiddenFiles = options.contains(.showsHiddenFiles)
                panel.allowsOtherFileTypes = options.contains(.allowsOtherFileTypes)
                panel.canSelectHiddenExtension = options.contains(.canSelectHiddenExtension)
                panel.isExtensionHidden = options.contains(.extensionHidden)

                let response = panel.runModal()
                if response == .OK, let url = panel.url {
                    completion(url.path, nil)
                } else {
                    completion(nil, nil)
                }
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction,
                                                        namespace: "iterm2")
    }
}
