//
//  iTermBrowserKeyBindingActionPerformer.swift
//  iTerm2
//
//  Created by George Nachman on 6/24/25.
//

@available(macOS 11, *)
class iTermBrowserKeyBindingActionPerformer {
    weak var delegate: iTermBrowserActionPerforming?

    func perform(keyBindingAction action: iTermKeyBindingAction, event: NSEvent) -> Bool {
        let parameter = action.parameter as NSString

        switch action.keyAction {
        case .ACTION_DO_NOT_REMAP_MODIFIERS, .ACTION_REMAP_LOCALLY, .ACTION_INVALID, .ACTION_BYPASS,
                .ACTION_IGNORE:
            return true

        case .ACTION_NEXT_SESSION, .ACTION_NEXT_WINDOW, .ACTION_PREVIOUS_SESSION,
                .ACTION_PREVIOUS_WINDOW, .ACTION_SELECT_PANE_LEFT, .ACTION_SELECT_PANE_RIGHT,
                .ACTION_SELECT_PANE_ABOVE, .ACTION_SELECT_PANE_BELOW, .ACTION_TOGGLE_FULLSCREEN,
                .ACTION_SELECT_MENU_ITEM, .ACTION_NEW_WINDOW_WITH_PROFILE,
                .ACTION_NEW_TAB_WITH_PROFILE, .ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE,
                .ACTION_SPLIT_VERTICALLY_WITH_PROFILE, .ACTION_NEXT_PANE, .ACTION_PREVIOUS_PANE,
                .ACTION_NEXT_MRU_TAB, .ACTION_MOVE_TAB_LEFT, .ACTION_MOVE_TAB_RIGHT,
                .ACTION_PREVIOUS_MRU_TAB, .ACTION_TOGGLE_HOTKEY_WINDOW_PINNING, .ACTION_UNDO,
                .ACTION_DECREASE_HEIGHT, .ACTION_INCREASE_HEIGHT, .ACTION_DECREASE_WIDTH,
                .ACTION_INCREASE_WIDTH, .ACTION_SWAP_PANE_LEFT, .ACTION_SWAP_PANE_RIGHT,
                .ACTION_SWAP_PANE_ABOVE, .ACTION_SWAP_PANE_BELOW, .FIND_AGAIN_DOWN, .FIND_AGAIN_UP,
                .ACTION_INVOKE_SCRIPT_FUNCTION, .ACTION_DUPLICATE_TAB, .ACTION_MOVE_TO_SPLIT_PANE,
                .ACTION_COMPOSE, .ACTION_SEND_TMUX_COMMAND, .ACTION_SEQUENCE,
                .ACTION_SWAP_WITH_NEXT_PANE, .ACTION_SWAP_WITH_PREVIOUS_PANE,
                .ACTION_ALERT_ON_NEXT_MARK, .ACTION_COPY_MODE, .ACTION_COPY_INTERPOLATED_STRING:
            // PTYSession's implementation of these is just fine.
            return false

        case .ACTION_SET_PROFILE:
            let profile = ProfileModel.sharedInstance().bookmark(withGuid: action.parameter) as? NSDictionary
            guard let profile, profile.profileIsBrowser else {
                DLog("Profile not a browser: \(profile.d)\n\(Thread.callStackSymbols)")
                return true
            }
            return false

        case .ACTION_SCROLL_END:
            delegate?.actionPerformingScroll(movement: .end)
        case .ACTION_SCROLL_HOME:
            delegate?.actionPerformingScroll(movement: .home)
        case .ACTION_SCROLL_LINE_DOWN:
            delegate?.actionPerformingScroll(movement: .down)
        case .ACTION_SCROLL_LINE_UP:
            delegate?.actionPerformingScroll(movement: .up)
        case .ACTION_SCROLL_PAGE_DOWN:
            delegate?.actionPerformingScroll(movement: .pageDown)
        case .ACTION_SCROLL_PAGE_UP:
            delegate?.actionPerformingScroll(movement: .pageUp)

        case .ACTION_ESCAPE_SEQUENCE, .ACTION_IR_FORWARD, .ACTION_IR_BACKWARD,
                .ACTION_SEND_C_H_BACKSPACE, .ACTION_SEND_C_QM_BACKSPACE, .ACTION_RUN_COPROCESS,
                .ACTION_TOGGLE_MOUSE_REPORTING:
            // Bindings that do not make sense in a browser are "handled".
            return true

        case .ACTION_LOAD_COLOR_PRESET, .ACTION_FIND_REGEX, .ACTION_PASTE_SPECIAL,
                .ACTION_PASTE_SPECIAL_FROM_SELECTION:
            // Not yet implemented, but should be!
            return true

            // Variations of sending text
        case .ACTION_HEX_CODE:
            if let data = NSString.data(forHexCodes: parameter as String) {
                delegate?.actionPerformingSend(
                    data: data,
                    broadcastAllowed: true)
            }
        case .ACTION_TEXT:
            delegate?.actionPerformingSend(
                data: iTermKeyBindingAction.escapedText(parameter as String,
                                                        mode: action.escaping).lossyData,
                broadcastAllowed: true)
        case .ACTION_VIM_TEXT:
            delegate?.actionPerformingSend(
                data: iTermKeyBindingAction.escapedText(parameter as String,
                                                        mode: action.vimEscaping).lossyData,
                broadcastAllowed: true)
        case .ACTION_SEND_SNIPPET:
            if let snippet  = iTermSnippetsModel.sharedInstance().snippet(withActionKey: parameter) {
                delegate?.actionPerformingSend(
                    data: snippet.value.lossyData, broadcastAllowed: true)
            }

        case .ACTION_MOVE_END_OF_SELECTION_LEFT:
            if let unit = PTYTextViewSelectionExtensionUnit(rawValue: parameter.integerValue) {
                delegate?.actionPerformingExtendSelect(
                    start: false,
                    forward: false,
                    by: unit)
            }
        case .ACTION_MOVE_END_OF_SELECTION_RIGHT:
            if let unit = PTYTextViewSelectionExtensionUnit(rawValue: parameter.integerValue) {
                delegate?.actionPerformingExtendSelect(
                    start: false,
                    forward: true,
                    by: unit)
            }
        case .ACTION_MOVE_START_OF_SELECTION_LEFT:
            if let unit = PTYTextViewSelectionExtensionUnit(rawValue: parameter.integerValue) {
                delegate?.actionPerformingExtendSelect(
                    start: true,
                    forward: false,
                    by: unit)
            }
        case .ACTION_MOVE_START_OF_SELECTION_RIGHT:
            if let unit = PTYTextViewSelectionExtensionUnit(rawValue: parameter.integerValue) {
                delegate?.actionPerformingExtendSelect(
                    start: true,
                    forward: true,
                    by: unit)
            }

        case .ACTION_COPY_OR_SEND:
            if let data = data(for: event) {
                Task {
                    if await delegate?.actionPerformingHasSelection() == true {
                        delegate?.actionPerformingCopyToClipboard()
                    } else {
                        delegate?.actionPerformingSend(data: data, broadcastAllowed: true)
                    }
                }
            }

        case .ACTION_PASTE_OR_SEND:
            if !NSString.fromPasteboard().isEmpty {
                delegate?.actionPerformingPasteFromClipboard()
            } else if let data = data(for: event) {
                delegate?.actionPerformingSend(data: data,
                                                  broadcastAllowed: true)
            }
        @unknown default:
            break
        }

        return true
    }

    private func data(for event: NSEvent) -> Data? {
        return event.characters?.lossyData
    }
}
