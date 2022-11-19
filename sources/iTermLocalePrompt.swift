//
//  iTermLocalePrompt.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/17/22.
//

import AppKit
import Foundation

@objc
class iTermLocalePrompt: NSObject {
    @objc var remember = false
    @objc var selectedLocale: String?
    @objc var selectedTitle: String?
    @objc var defaultLocale: String?
    @objc var message: String?
    @objc var allowRemember = true

    @objc(requestLocaleFromUserForProfile:inWindow:)
    @discardableResult
    func requestLocaleFromUser(profileName: String?, window: NSWindow) -> [String: String]? {
        let alert = iTermLocalePromptAlert(languages: NSLocale.preferredLanguages,
                                           profileName: profileName)
        alert.allowRemember = allowRemember
        if let defaultLocale {
            alert.select(locale: defaultLocale)
        }
        if let message {
            alert.message = message
        }
        let (locale, remember, title) = alert.run(window: window)
        self.remember = remember
        selectedLocale = locale
        selectedTitle = title
        return locale.map { ["LANG": $0] }
    }
}

@objc
extension NSPopUpButton {
    private static let validLocales: [String] = {
        let task = Process()
        task.launchPath = "/usr/bin/locale"
        task.arguments = ["-a"]
        let output = Pipe()
        task.standardOutput = output
        task.standardError = output
        do {
            try ObjC.catching {
                task.launch()
            }
        } catch {
            DLog("locale -a failed with \(error)")
            return []
        }
        var data = Data()
        let handle = output.fileHandleForReading
        while true {
            let chunk = handle.availableData
            if chunk.count > 0 {
                data.append(chunk)
            } else {
                break
            }
        }
        task.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "").components(separatedBy: "\n").filter { !$0.isEmpty }
    }()

    @objc
    func populateWithLocales() {
        let sortedLocaleComponents = Self.validLocales.map {
            LocaleComponents($0)
        }.sorted { lhs, rhs in
            lhs.title < rhs.title
        }

        var defaultIndex: Int?
        var defaultIndexQuality = Int.max
        let preferredLanguages = Locale.preferredLanguages.map { LocaleComponents($0, separator: "-").languageCode }
        // If Locale.preferredLanguages is ["en-US", "en-CA", "fr-FR"] then index will be ["en": 0, "fr": 1].
        let grouped = Dictionary(grouping: 0..<preferredLanguages.count, by: { preferredLanguages[$0] })
        let index = grouped.mapValues { $0.first! }
        for components in sortedLocaleComponents {
            if let quality = index[components.languageCode], quality < defaultIndexQuality {
                defaultIndex = menu!.items.count
                defaultIndexQuality = quality
            }
            menu?.addItem(withTitle: components.title, action: nil, keyEquivalent: "")
            menu?.items.last?.representedObject = components.locale
        }
        if let defaultIndex {
            select(menu!.items[defaultIndex])
        }
    }
}

class iTermLocalePromptAlert {
    private let languages: [String]
    private var popup = NSPopUpButton(frame: .zero, pullsDown: false)
    var message = "No valid UNIX locale exists for your computer’s current language and country. This may cause command-line apps to misbehave. Please select one from the list below."
    @objc var allowRemember = true
    private let profileName: String?

    init(languages: [String], profileName: String?) {
        self.languages = languages
        self.profileName = profileName
        allowRemember = profileName != nil
        popup.populateWithLocales()
    }

    func select(locale: String) {
        if let i = popup.menu?.indexOfItem(withRepresentedObject: locale), i >= 0 {
            popup.select(popup.menu!.items[i])
        }
    }

    func run(window: NSWindow?) -> (String?, Bool, String?) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let wrapper = NSStackView()
        wrapper.orientation = .vertical
        wrapper.distribution = .fillEqually
        wrapper.alignment = .leading
        wrapper.spacing = 5
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addConstraint(NSLayoutConstraint(item: wrapper,
                                                 attribute: .width,
                                                 relatedBy: .equal,
                                                 toItem: nil,
                                                 attribute: .notAnAttribute,
                                                 multiplier: 1,
                                                 constant: 200))
        wrapper.addArrangedSubview(popup)
        alert.accessoryView = wrapper
        alert.showsSuppressionButton = allowRemember
        if allowRemember, let profileName {
            alert.suppressionButton?.title = "Save selection to profile \(profileName)"
        }
        let popup = self.popup
        let timer = Timer(timeInterval: 0, repeats: false) { _ in
            alert.layout()
            popup.window?.makeFirstResponder(popup)
        }
        RunLoop.main.add(timer, forMode: .common)

        let result = { () -> NSApplication.ModalResponse in
            if let window = window, window.isVisible {
                return alert.runSheetModal(for: window)
            } else {
                return alert.runModal()
            }
        }()
        let remember = alert.suppressionButton?.state == .on
        if result == .alertFirstButtonReturn {
            let locale = popup.selectedItem?.representedObject as? String
            return (locale, remember, popup.selectedItem?.title)
        }
        return (nil, remember, nil)
    }
}

struct LocaleComponents {
    var locale: String
    var languageCode: String
    var countryCode: String?
    var encoding: String?

    init(_ locale: String, separator: String = "_") {
        self.locale = locale
        let lcEnc = locale.components(separatedBy: ".")
        guard let lc = lcEnc.first else {
            languageCode = "C"
            return
        }
        let parts = lc.components(separatedBy: separator)
        guard parts.count == 2 else {
            languageCode = locale
            return
        }
        languageCode = parts[0]
        countryCode = parts[1]
        if lcEnc.count > 1 {
            encoding = lcEnc[1]
        }
    }

    var title: String {
        if let c = localizedCountryCode {
            if let encoding {
                return "\(localizedLanguageCode) (\(c)), \(encoding)"
            }
            return "\(localizedLanguageCode) (\(c))"
        }
        if let encoding {
            return "\(localizedLanguageCode), \(encoding)"
        }
        return localizedLanguageCode
    }

    var localizedLanguageCode: String {
        Locale.current.localizedString(forLanguageCode: languageCode) ?? languageCode
    }

    var localizedCountryCode: String? {
        if let countryCode {
            return (Locale.current as NSLocale).localizedString(forCountryCode: countryCode)
        }
        return nil
    }
}
