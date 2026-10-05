//
//  TmuxPaneKeyMode.swift
//  iTerm2SharedARC
//
//  Parses tmux's #{pane_key_mode} format variable, which reports how the
//  application running in a pane has asked for keys to be encoded. tmux is the
//  authority on this for a tmux -CC pane, because tmux is the application's
//  terminal; iTerm2 only eavesdrops on the pane's raw output. The modifyOtherKeys
//  level is applied on attach; the whole value is shown in the Terminal State
//  menu.
//

import Foundation

@objc(iTermTmuxPaneKeyMode)
class TmuxPaneKeyMode: NSObject {
    // The xterm modifyOtherKeys level, or -1 when the value does not describe one.
    @objc let modifyOtherKeys: Int

    // The Kitty keyboard protocol flags, or 0 when the pane is not using it.
    @objc let kittyFlags: Int

    private init(modifyOtherKeys: Int, kittyFlags: Int) {
        self.modifyOtherKeys = modifyOtherKeys
        self.kittyFlags = kittyFlags
        super.init()
    }

    // Returns nil when the value is absent or unrecognized, which is what tmux
    // versions without #{pane_key_mode} (before 3.5) report.
    //
    // tmux reports these as mutually exclusive: a pane using the Kitty protocol
    // is described only as "Kitty <flags>", with no modifyOtherKeys level, so
    // modifyOtherKeys is -1 there.
    @objc(modeForString:)
    static func mode(for string: String?) -> TmuxPaneKeyMode? {
        guard let string, !string.isEmpty else {
            return nil
        }
        switch string {
        case "VT10x":
            return TmuxPaneKeyMode(modifyOtherKeys: 0, kittyFlags: 0)
        case "Ext 1":
            return TmuxPaneKeyMode(modifyOtherKeys: 1, kittyFlags: 0)
        case "Ext 2":
            return TmuxPaneKeyMode(modifyOtherKeys: 2, kittyFlags: 0)
        default:
            break
        }
        // "Kitty <flags>", where flags is the protocol's raw bitmask. This is the
        // format introduced by https://github.com/tmux/tmux/pull/5615, which
        // teaches tmux to track the Kitty keyboard protocol per pane.
        guard let flags = kittyFlags(inString: string) else {
            return nil
        }
        return TmuxPaneKeyMode(modifyOtherKeys: -1, kittyFlags: flags)
    }

    private static func kittyFlags(inString string: String) -> Int? {
        let prefix = "Kitty "
        guard string.hasPrefix(prefix) else {
            return nil
        }
        let digits = string.dropFirst(prefix.count)
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return nil
        }
        // A pane cannot ask for flags outside the protocol's range, and a value we
        // do not understand is safer ignored than half-applied.
        guard let flags = Int(digits), flags <= 0b11111 else {
            return nil
        }
        return flags
    }
}
