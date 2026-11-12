import AppKit

/// The same explicit opening choices are used by project rows and file-tree entries.
final class iTermProjectTerminalMenu {
    static func make(target: AnyObject, action: Selector, canOpen: (iTermOpenStyle) -> Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let choices: [(iTermOpenStyle, String)] = [
            (.tab, String(localized: "Projects.OpenTerminalNewTab", defaultValue: "New Tab", comment: "Open a new terminal in the chosen directory in a new tab")),
            (.verticalSplit, String(localized: "Projects.OpenTerminalSplitRight", defaultValue: "Split Left and Right", comment: "Open a new terminal beside the current pane, with a vertical divider")),
            (.horizontalSplit, String(localized: "Projects.OpenTerminalSplitDown", defaultValue: "Split Top and Bottom", comment: "Open a new terminal below the current pane, with a horizontal divider")),
            (.window, String(localized: "Projects.OpenTerminalNewWindow", defaultValue: "New Window", comment: "Open a new terminal in the chosen directory in a separate window"))
        ]
        for (style, title) in choices {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = target
            item.tag = Int(style.rawValue)
            item.isEnabled = canOpen(style)
            if !item.isEnabled {
                item.toolTip = String(localized: "Projects.TerminalModeUnavailable", defaultValue: "This opening mode is unavailable for the current terminal or layout.", comment: "Tooltip for a disabled terminal opening menu item")
            }
            menu.addItem(item)
        }
        return menu
    }
}
