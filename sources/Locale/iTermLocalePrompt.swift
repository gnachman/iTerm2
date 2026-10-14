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

    // A sheet is only usable on a window the user can actually see. A hotkey window is ordered
    // in with an alpha of 0 while its first session launches, and a sheet on it is invisible:
    // the user sees nothing, keyboard focus is trapped in the sheet, and the hotkey window
    // cannot appear until the sheet is answered blind. Use an app-modal alert in that case.
    static func shouldPresentAsSheet(isVisible: Bool,
                                     alphaValue: CGFloat,
                                     isMiniaturized: Bool) -> Bool {
        return isVisible && alphaValue > 0 && !isMiniaturized
    }

    // Returns `window` if a locale-related alert can be shown as a sheet on it, or nil if it
    // must be app-modal instead.
    @objc(sheetParentForWindow:)
    static func sheetParent(for window: NSWindow?) -> NSWindow? {
        guard let window else {
            return nil
        }
        if shouldPresentAsSheet(isVisible: window.isVisible,
                                alphaValue: window.alphaValue,
                                isMiniaturized: window.isMiniaturized) {
            return window
        }
        DLog("Not using a sheet on \(window): visible=\(window.isVisible) alpha=\(window.alphaValue) miniaturized=\(window.isMiniaturized)")
        return nil
    }

    @objc(requestLocaleFromUserForProfile:inWindow:cancelUsesC:)
    @discardableResult
    func requestLocaleFromUser(profileName: String?, window: NSWindow?, cancelUsesC: Bool) -> [String: String]? {
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
            RLog("locale -a failed with return code \(rc)")
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
        menu?.addItem(withTitle: String(localized: "LocalePrompt.WrongEncodingSection", defaultValue: "Locales with wrong encoding", comment: "Disabled section header in a menu listing locales that use the wrong encoding"), action: #selector(Placeholder.placeholder(_:)), keyEquivalent: "")
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
    var message = String(localized: "LocalePrompt.Message", defaultValue: "No valid UNIX locale exists for your computer’s current language and country. This may cause command-line apps to misbehave. Please select one from the list below.", comment: "Explanation shown when no valid UNIX locale exists for the user’s language and country")
    @objc var allowRemember = true
    private let profileName: String?
    var arrangementName: String?
    // Shows the alert as a sheet on the given window, or app-modal if it is nil. Replaceable
    // for testing.
    var presenter: (NSAlert, NSWindow?) -> NSApplication.ModalResponse = { alert, sheetParent in
        if let sheetParent {
            return alert.runSheetModal(for: sheetParent)
        }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

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
        alert.addButton(withTitle: iTermLocalizedOK())
        alert.addButton(withTitle: cancelUsesC ? String(localized: "LocalePrompt.UseMinimalPOSIX", defaultValue: "Use Minimal POSIX Locale", comment: "Button that selects a minimal POSIX locale instead of cancelling") : iTermLocalizedCancel())

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
                alert.suppressionButton?.title = String(localized: "LocalePrompt.SaveToArrangement", defaultValue: "Save selection to arrangement \(arrangementName)", comment: "Suppression checkbox that saves the locale selection to an arrangement; placeholder is the arrangement name")
            } else {
                alert.suppressionButton?.title = String(localized: "LocalePrompt.SaveToProfile", defaultValue: "Save selection to profile \(profileName)", comment: "Suppression checkbox that saves the locale selection to a profile; placeholder is the profile name")
            }
        }
        let popup = self.popup
        let timer = Timer(timeInterval: 0, repeats: false) { _ in
            alert.layout()
            popup.window?.makeFirstResponder(popup)
        }
        RunLoop.main.add(timer, forMode: .common)

        let result = presenter(alert, iTermLocalePrompt.sheetParent(for: window))
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
