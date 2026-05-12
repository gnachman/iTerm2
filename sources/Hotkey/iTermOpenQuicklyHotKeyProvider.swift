import Foundation

// Owns the registration of the global Open Quickly hotkey based on user prefs.
// Call -invalidate after changing the Open Quickly hotkey prefs to re-register.
//
// The window itself is an NSPanel with NSWindowStyleMaskNonactivatingPanel, so
// pressing the hotkey while another app is in front shows Open Quickly without
// activating iTerm2; activation happens later only if the user commits to a
// session.
@objc(iTermOpenQuicklyHotKeyProvider)
class OpenQuicklyHotKeyProvider: NSObject {

    @objc(sharedInstance)
    static let shared = OpenQuicklyHotKeyProvider()

    private var registeredHotKey: iTermHotKey?

    override init() {
        super.init()
        invalidate()
    }

    @objc func invalidate() {
        if let hotKey = registeredHotKey {
            iTermCarbonHotKeyController.sharedInstance().unregisterHotKey(hotKey)
            registeredHotKey = nil
        }

        let keyCode = Int(iTermPreferences.int(forKey: kPreferenceKeyOpenQuicklyHotKeyCode))
        let character = Int(iTermPreferences.int(forKey: kPreferenceKeyOpenQuicklyHotkeyCharacter))
        let modifiers = Int(iTermPreferences.int(forKey: kPreferenceKeyOpenQuicklyHotkeyModifiers))
        if keyCode == 0 && character == 0 {
            return  // Unbound.
        }

        let characters = String(format: "%C", character)
        let shortcut = iTermShortcut(keyCode: UInt(keyCode),
                                     hasKeyCode: true,
                                     modifiers: NSEvent.ModifierFlags(rawValue: UInt(modifiers)),
                                     characters: characters,
                                     charactersIgnoringModifiers: characters)
        registeredHotKey = iTermCarbonHotKeyController.sharedInstance()
            .register(shortcut,
                      target: self,
                      selector: #selector(hotKeyPressed(_:siblings:)),
                      userData: [:])
    }

    // iTermCarbonHotKeyController invokes -[target selector:siblings:] when the
    // shortcut fires. Returning nil tells the controller this hotkey handled the
    // press (no other siblings consumed).
    @objc(hotKeyPressed:siblings:)
    private func hotKeyPressed(_ userData: [AnyHashable: Any], siblings: [iTermHotKey]) -> [iTermHotKey]? {
        iTermOpenQuicklyWindowController.sharedInstance().presentWindow()
        return nil
    }
}
