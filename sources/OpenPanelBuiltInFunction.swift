//
//  OpenPanelBuiltInFunction.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/8/22.
//

import AppKit
import UniformTypeIdentifiers

@objc(iTermOpenPanelBuiltInFunction)
class OpenPanelBuiltInFunction: NSObject, iTermBuiltInFunctionProtocol {
    struct Options: OptionSet {
        // Shared with SavePanel
        static let canCreateDirectories = Options(rawValue: 1 << 0)
        static let treatsFilePackagesAsDirectories = Options(rawValue: 1 << 1)
        static let showsHiddenFiles = Options(rawValue: 1 << 2)

        // Specific to OpenPanel
        static let resolvesAliases = Options(rawValue: 1 << 32)
        static let canChooseDirectories = Options(rawValue: 1 << 33)
        static let allowsMultipleSelection = Options(rawValue: 1 << 34)
        static let canChooseFiles = Options(rawValue: 1 << 35)

        let rawValue: Int
    }
    @objc static func register() {
        let pathArgName = "path"
        let optionsArgName = "options"
        let extensionsArgName = "extensions"

        // Text for OK button
        let promptArgName = "prompt"

        // Text for panel title
        let messageArgName = "message"

        let builtInFunction = iTermBuiltInFunction(
            name: "open_panel",
            arguments: [pathArgName: NSString.self,
                     optionsArgName: NSNumber.self,
                  extensionsArgName: NSArray.self,
                      promptArgName: NSString.self,
                     messageArgName: NSString.self ],
            optionalArguments: Set([pathArgName,
                                    optionsArgName,
                                    extensionsArgName,
                                    promptArgName,
                                    messageArgName]),
            defaultValues: [:],
            context: .app) { parameters, completion in
                let panel = NSOpenPanel()

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
                let options = Options(rawValue: parameters[optionsArgName] as? Int ?? 0)

                panel.canCreateDirectories = options.contains(.canCreateDirectories)
                panel.treatsFilePackagesAsDirectories = options.contains(.treatsFilePackagesAsDirectories)
                panel.showsHiddenFiles = options.contains(.showsHiddenFiles)
                panel.resolvesAliases = options.contains(.resolvesAliases)
                panel.canChooseDirectories = options.contains(.canChooseDirectories)
                panel.allowsMultipleSelection = options.contains(.allowsMultipleSelection)
                panel.canChooseFiles = options.contains(.canChooseFiles)

                let response = panel.runModal()
                if response == .OK {
                    completion(panel.urls.map { $0.path }, nil)
                } else {
                    completion(nil, nil)
                }
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction,
                                                        namespace: "iterm2")
    }
}
