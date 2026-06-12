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
    @objc var arrangementName: String?
    let encoding: String.Encoding

    @objc
    init(encoding: UInt) {
        self.encoding = .init(rawValue: encoding)
    }

    @objc(requestLocaleFromUserForProfile:inWindow:cancelUsesC:)
    @discardableResult
    func requestLocaleFromUser(profileName: String?, window: NSWindow, cancelUsesC: Bool) -> [String: String]? {
        let alert = iTermLocalePromptAlert(languages: NSLocale.preferredLanguages,
                                           profileName: profileName,
                                           encoding: encoding)
        alert.allowRemember = allowRemember
        alert.arrangementName = arrangementName
        if let defaultLocale {
            alert.select(locale: defaultLocale)
        }
        if let message {
            alert.message = message
        }
        let (locale, remember, title) = alert.run(window: window, cancelUsesC: cancelUsesC)
        self.remember = remember
        selectedLocale = locale
        selectedTitle = title
        return locale.map { ["LANG": $0] }
    }
}

@objc
extension NSPopUpButton {
    private static let validLocales: [String] = {
        let runner = iTermBufferedCommandRunner(command: "/usr/bin/locale",
                                                withArguments: [ "-a" ],
                                                path: "/")
        runner.maximumOutputSize = NSNumber(value: 1024 * 1024)
        let rc = runner.blockingRun()
        if rc != 0 {
            DLog("locale -a failed with return code \(rc)")
            return []
        }
        var data = runner.output ?? Data()
        return (String(data: data, encoding: .utf8) ?? "").components(separatedBy: "\n").filter { !$0.isEmpty }
    }()

    @nonobjc
    func populateWithLocales(encoding: String.Encoding) {
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

        var good: [LocaleComponents] = []
        var bad: [LocaleComponents] = []

        for components in sortedLocaleComponents {
            if components.encoding != "UTF-8" && encoding == .utf8 {
                bad.append(components)
            } else {
                good.append(components)
            }
        }
        for components in good {
            if let quality = index[components.languageCode], quality < defaultIndexQuality {
                defaultIndex = menu!.items.count
                defaultIndexQuality = quality
            }
            menu?.addItem(withTitle: components.title, action: nil, keyEquivalent: "")
            menu?.items.last?.representedObject = components.locale
        }
        @objc class Placeholder: NSObject, NSMenuItemValidation {
            static let instance = Placeholder()
            @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
                return false
            }
            @objc func placeholder(_ sender: Any) {
                it_fatalError()
            }
        }
        menu?.addItem(.separator())
        menu?.addItem(withTitle: "Locales with wrong encoding", action: #selector(Placeholder.placeholder(_:)), keyEquivalent: "")
        menu?.items.last?.target = Placeholder.instance
        for components in bad {
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
    var arrangementName: String?

    init(languages: [String], profileName: String?, encoding: String.Encoding) {
        self.languages = languages
        self.profileName = profileName
        allowRemember = profileName != nil
        popup.populateWithLocales(encoding: encoding)
    }

    func select(locale: String) {
        if let i = popup.menu?.indexOfItem(withRepresentedObject: locale), i >= 0 {
            popup.select(popup.menu!.items[i])
        }
    }

    func run(window: NSWindow?, cancelUsesC: Bool) -> (String?, Bool, String?) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: cancelUsesC ? "Use Minimal POSIX Locale" : "Cancel")

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
            if let arrangementName {
                alert.suppressionButton?.title = "Save selection to arrangement \(arrangementName)"
            } else {
                alert.suppressionButton?.title = "Save selection to profile \(profileName)"
            }
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
