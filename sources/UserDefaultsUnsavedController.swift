//
//  UserDefaultsUnsavedController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/3/24.
//

import Foundation


@available(macOS, introduced: 11)
@objc
fileprivate class UnsavedUserDefaultsViewController: NSViewController {
    private var button: ButtonWithCustomCursor?
    private let rightMargin = 8.0
    private let innerMargin = 0.0
    var onClick: (() -> ())?
    let size = CGFloat(22)

    var disabled = false {
        didSet {
            button?.isHidden = disabled
        }
    }

    @objc
    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let button = ButtonWithCustomCursor()
        button.cursor = NSCursor.pointingHand
        button.isBordered = false
        button.target = self
        button.action = #selector(handleClick(_:))
        button.autoresizingMask = []
        button.frame = NSRect(x: 0, y: 0, width: size, height: size)
        self.button = button

        let image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)
        image?.isTemplate = true
        button.contentTintColor = .red
        button.image = image

        view = NSView()
        view.frame = NSRect(x: 0, y: 0, width: button.bounds.width, height: button.bounds.height)
        view.autoresizingMask = []
        view.addSubview(button)
        if disabled {
            view.isHidden = true
        }
    }

    @objc func handleClick(_ sender: Any) {
        onClick?()
    }
}

@objc
class UserDefaultsUnsavedView: NSView {
}

@available(macOS, introduced: 11)
@objc(iTermUserDefaultsUnsavedController)
class UserDefaultsUnsavedController: NSTitlebarAccessoryViewController {
    private var observer: AnyObject?
    private static let hideKey = "NoSyncHideUnsavedSettingsNotification"

    @objc static var allowed: Bool {
        return !UserDefaults.standard.bool(forKey: hideKey)
    }

    init() {
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .left
    }

    required init?(coder: NSCoder) {
        it_fatalError("not implemented")
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private let innerVC = UnsavedUserDefaultsViewController()

    override func loadView() {
        let size = innerVC.size
        view = UserDefaultsUnsavedView()
        let topMargin = CGFloat(3)
        view.frame = NSRect(x: 0, y: 0, width: size, height: size + topMargin)
        view.autoresizingMask = []

        let subview = innerVC.view
        view.addSubview(subview)
        subview.frame = NSRect(x: 0, y: view.frame.height - size - topMargin, width: size, height: size)
        subview.autoresizingMask = [.minYMargin]

        check()
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                               object: nil,
                                               queue: nil) { [weak self] notif in
            if let object = notif.object, let string = object as? String {
                self?.userDefaultsDidChange(string)
            } else {
                self?.userDefaultsDidChange(nil)
            }
        }
        innerVC.onClick = { [weak self] in
            self?.handleClick()
        }
    }

    private func handleClick() {
        guard let event = NSApp.currentEvent else {
            return
        }
        let menu = SimpleContextMenu()
        if iTermRemotePreferences.sharedInstance().remoteLocationIsURL {
            menu.addItem(title: "Disable Loading Settings from URL") { [weak self] in
                self?.disableRemotePrefs()
            }
        } else {
            menu.addItem(title: "Save Settings") { [weak self] in
                self?.save()
            }
            menu.addItem(title: "Save Settings Automatically") { [weak self] in
                self?.enableAutosave()
            }
            menu.addItem(title: "Hide Unsaved Changes Notification") { [weak self] in
                self?.hideNotification()
            }
        }
        menu.show(in: view, for: event)
    }

    private func disableRemotePrefs() {
        UserDefaults.standard.set(false, forKey: kPreferenceKeyLoadPrefsFromCustomFolder)
    }

    private func save() {
        iTermRemotePreferences.sharedInstance().saveLocalUserDefaultsToRemotePrefs()
        check()
    }

    private func enableAutosave() {
        save()
        UserDefaults.standard.setValue(true, 
                                       forKey: kPreferenceKeyNeverRemindPrefsChangesLostForFileHaveSelection)
        UserDefaults.standard.setValue(iTermPreferenceSavePrefsMode.always.rawValue,
                                       forKey: kPreferenceKeyNeverRemindPrefsChangesLostForFileSelection)
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: kPreferenceDidChangeFromOtherPanel),
                                        object: nil,
                                        userInfo: [kPreferenceDidChangeFromOtherPanelKeyUserInfoKey: kPreferenceKeyNeverRemindPrefsChangesLostForFileSelection])
    }

    private func hideNotification() {
        UserDefaults.standard.setValue(true, forKey: Self.hideKey)
        if let i = view.window?.titlebarAccessoryViewControllers.firstIndex(of: self) {
            view.window?.removeTitlebarAccessoryViewController(at: i)
        }
    }

    private var checking = false

    private func userDefaultsDidChange(_ key: String?) {
        if iTermRemotePreferences.sharedInstance().remoteLocationIsURL {
            checkAsynchronously()
            return
        }
        if iTermRemotePreferences.sharedInstance().shouldSaveAutomatically() {
            return
        }
        if checking {
            return
        }
        checkAsynchronously()
    }

    private func checkAsynchronously() {
        checking = true
        DispatchQueue.main.async { [weak self] in
            self?.check()
        }
    }

    private func check() {
        checking = false
        let differs = iTermRemotePreferences.sharedInstance().localPrefsDifferFromSavedRemotePrefsRespectingDefaults()
        innerVC.disabled = !differs
    }
}
