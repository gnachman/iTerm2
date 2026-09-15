//
//  iTermEditKeyActionWindowController.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "iTermEditKeyActionWindowController.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermActionsModel.h"
#import "iTermFunctionCallTextFieldDelegate.h"
#import "iTermKeystrokeFormatter.h"
#import "iTermPasteSpecialViewController.h"
#import "iTermPreferences.h"
#import "iTermShortcutInputView.h"
#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"
#import "NSPopUpButton+iTerm.h"
#import "NSScreen+iTerm.h"
#import "NSTextField+iTerm.h"
#import "NSView+iTerm.h"
#import "RegexKitLite.h"

#import <SearchableComboListView/SearchableComboListView-Swift.h>

const CGFloat sideMarginWidth = 40;

@interface iTermEditKeyActionDetailView: NSView
@end

@implementation iTermEditKeyActionDetailView

- (NSView *)hitTest:(NSPoint)point {
    NSView *subview = [super hitTest:point];
    if (subview == self) {
        return nil;
    }
    return subview;
}
@end

@interface iTermEditKeyActionWindowConfiguration: NSObject
@property (nonatomic, readonly) BOOL applyHidden;
@property (nonatomic, readonly) BOOL parameterHidden;
@property (nonatomic, readonly) NSString *helpString;
@property (nonatomic, readonly) BOOL parameterLabelHidden;
@property (nonatomic, readonly) BOOL profilePopupHidden;
@property (nonatomic, readonly) BOOL selectionMovementUnitHidden;
@property (nonatomic, readonly) BOOL profileLabelHidden;
@property (nonatomic, readonly) BOOL menuToSelectPopupHidden;
@property (nonatomic, readonly) BOOL settingToTogglePopupHidden;
@property (nonatomic, readonly) BOOL shortcutFieldDisableKeyRemapping;
@property (nonatomic, readonly) BOOL colorPresetsLabelHidden;
@property (nonatomic, readonly) BOOL colorPresetsPopupHidden;
@property (nonatomic, readonly) BOOL pasteSpecialHidden;
@property (nonatomic, readonly) BOOL snippetsHidden;
@property (nonatomic, readonly) BOOL showSecondary;
@property (nonatomic, readonly) NSString *parameterPlaceholder;
@property (nonatomic, readonly) NSString *parameterLabel;
@property (nonatomic, readonly) iTermFunctionCallTextFieldDelegate *parameterDelegate;
@property (nonatomic, readonly) NSString *parameterValue;
@end

@implementation iTermEditKeyActionWindowConfiguration

- (instancetype)initWithTag:(int)tag
       functionCallDelegate:(iTermFunctionCallTextFieldDelegate *)functionCallDelegate
 interpolatedStringDelegate:(iTermFunctionCallTextFieldDelegate *)interpolatedStringDelegate
                    context:(iTermVariablesSuggestionContext)context {
    self = [super init];
    if (self) {
        _parameterHidden = YES;
        _helpString = nil;
        _parameterLabelHidden = YES;
        _profilePopupHidden = YES;
        _selectionMovementUnitHidden = YES;
        _profileLabelHidden = YES;
        _menuToSelectPopupHidden = YES;
        _settingToTogglePopupHidden = YES;
        _shortcutFieldDisableKeyRemapping = NO;
        _colorPresetsLabelHidden = YES;
        _colorPresetsPopupHidden = YES;
        _pasteSpecialHidden = YES;
        _snippetsHidden = YES;
        _showSecondary = NO;
        _applyHidden = YES;

        switch (tag) {
            case KEY_ACTION_SEND_SNIPPET:
                _snippetsHidden = NO;
                _parameterValue = @"";
                _applyHidden = NO;
                break;

            case KEY_ACTION_COMPOSE:
                _parameterHidden = NO;
                _parameterPlaceholder = NSLocalizedStringWithDefaultValue(@"EditKeyAction.PlaceholderComposer", nil, [NSBundle mainBundle], @"Text for composer", @"Placeholder for the composer text field");
                break;

            case KEY_ACTION_HEX_CODE:
                _parameterHidden = NO;
                _parameterPlaceholder = NSLocalizedStringWithDefaultValue(@"EditKeyAction.PlaceholderHexCode", nil, [NSBundle mainBundle], @"ex: 0x7f 0x20", @"Placeholder showing example hex codes");
                _applyHidden = NO;
                break;

            case KEY_ACTION_VIM_TEXT:
            case KEY_ACTION_VIM_TEXT_NO_BROADCAST:
                _parameterHidden = NO;
                _helpString = NSLocalizedStringWithDefaultValue(@"EditKeyAction.HelpVimText", nil, [NSBundle mainBundle], @"Special characters are:\n* \\<1-to-3-digit octal>\n* \\x<1 or 2 digit hex>\n* \\u<4 digit hex>\n* \\b for backspace\n* \\e for esc\n* \\f for formfeed\n* \\n for newline and \\r for return\n* \\t for tab\n* \\\\ and \\\" for literal \\ and \"\n* <C-x> for control key\n* <M-x> for meta key.", @"Help text listing vim-style special character escapes");
                _parameterPlaceholder = NSLocalizedStringWithDefaultValue(@"EditKeyAction.PlaceholderVimText", nil, [NSBundle mainBundle], @"Enter value to send. Click help button for special characters.", @"Placeholder for vim-style text entry");
                _applyHidden = NO;
                break;

            case KEY_ACTION_TEXT:
                _parameterHidden = NO;
                _parameterPlaceholder = NSLocalizedStringWithDefaultValue(@"EditKeyAction.PlaceholderSendText", nil, [NSBundle mainBundle], @"Enter value to send", @"Placeholder for text to send");
                _applyHidden = NO;
                break;

            case KEY_ACTION_RUN_COPROCESS:
                _parameterHidden = NO;
                _parameterPlaceholder = NSLocalizedStringWithDefaultValue(@"EditKeyAction.PlaceholderRunCommand", nil, [NSBundle mainBundle], @"Enter command to run", @"Placeholder for command to run");
                _applyHidden = NO;
                break;

            case KEY_ACTION_SEND_TMUX_COMMAND:
                _parameterHidden = NO;
                _parameterPlaceholder = NSLocalizedStringWithDefaultValue(@"EditKeyAction.PlaceholderTmuxCommand", nil, [NSBundle mainBundle], @"Enter tmux command", @"Placeholder for tmux command entry");
                break;

            case KEY_ACTION_SELECT_MENU_ITEM:
                _parameterPlaceholder = NSLocalizedStringWithDefaultValue(@"EditKeyAction.PlaceholderMenuItem", nil, [NSBundle mainBundle], @"Enter name of menu item", @"Placeholder for entering a menu item name");
                _menuToSelectPopupHidden = NO;
                _parameterValue = @"";
                break;

            case KEY_ACTION_ESCAPE_SEQUENCE:
                _parameterHidden = NO;
                _parameterPlaceholder = NSLocalizedStringWithDefaultValue(@"EditKeyAction.PlaceholderEscapeChars", nil, [NSBundle mainBundle], @"characters to send", @"Placeholder for characters to send in an escape sequence");
                _parameterLabelHidden = NO;
                _parameterLabel = NSLocalizedStringWithDefaultValue(@"EditKeyAction.EscapeLabel", nil, [NSBundle mainBundle], @"Esc+", @"Label prefix shown before escape sequence field");
                _applyHidden = NO;
                break;

            case KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE:
            case KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE:
            case KEY_ACTION_NEW_TAB_WITH_PROFILE:
            case KEY_ACTION_NEW_WINDOW_WITH_PROFILE:
                _profileLabelHidden = NO;
                _profilePopupHidden = NO;
                _parameterValue = @"";
                break;

            case KEY_ACTION_SET_PROFILE:
                _profileLabelHidden = NO;
                _profilePopupHidden = NO;
                _parameterValue = @"";
                _applyHidden = NO;
                break;

            case KEY_ACTION_LOAD_COLOR_PRESET:
                _colorPresetsLabelHidden = NO;
                _colorPresetsPopupHidden = NO;
                _parameterValue = @"";
                _applyHidden = NO;
                break;

            case KEY_ACTION_DO_NOT_REMAP_MODIFIERS:
                _shortcutFieldDisableKeyRemapping = YES;
                _parameterValue = @"";
                _helpString = NSLocalizedStringWithDefaultValue(@"EditKeyAction.HelpDoNotRemap", nil, [NSBundle mainBundle], @"This action lets you exempt a keystroke from modifier remapping. For example, if you remap ⌘ to ⌥ but you want ⌘-Tab to work as though ⌘ were unmapped just for that keystroke, you would use this action and set the keyboard shortcut to ⌘-Tab", @"Help text for the Do Not Remap Modifiers action");
                _parameterValue = @"";
                break;

            case KEY_ACTION_REMAP_LOCALLY:
                _shortcutFieldDisableKeyRemapping = YES;
                _parameterValue = @"";
                _helpString = NSLocalizedStringWithDefaultValue(@"EditKeyAction.HelpRemapLocally", nil, [NSBundle mainBundle], @"This action applies modifier remapping but prevents other programs from seeing the keystroke. For example, if you've swapped ⌘ and ^ and want physical ^-tab to switch tabs in iTerm2 instead of triggering the app switcher: bind ^-tab to this action. The system won't see the remapped ⌘-tab (so no app switcher), but iTerm2 receives it and can switch tabs.", @"Help text for the Remap Modifiers in iTerm2 Only action");
                _parameterValue = @"";
                break;

            case KEY_ACTION_BYPASS:
                _helpString = NSLocalizedStringWithDefaultValue(@"EditKeyAction.HelpBypass", nil, [NSBundle mainBundle], @"Prevents the keystroke from being sent to the terminal while allowing macOS to handle it normally. For example, if F1 triggers a  macOS Shortcut, binding F1 to Bypass Terminal stops it from sending a control sequence to the terminal but still lets the system shortcut work.", @"Help text for the Bypass Terminal action");
                break;

            case KEY_ACTION_IGNORE:
                _helpString = NSLocalizedStringWithDefaultValue(@"EditKeyAction.HelpIgnore", nil, [NSBundle mainBundle], @"Prevents the keystroke from having any effect within iTerm2. Modifier remapping remains unaffected.", @"Help text for the Ignore action");
                break;

            case KEY_ACTION_NEXT_MRU_TAB:
                _parameterValue = @"";
                _helpString = NSLocalizedStringWithDefaultValue(@"EditKeyAction.HelpNextMRUTab", nil, [NSBundle mainBundle], @"Switches tabs in most-recently-used order, like ⌘-Tab in macOS. Hold a modifier and tap repeatedly to walk back through tab history; release the modifier to commit your selection. A single tap with no modifier held jumps to the previously-selected tab, so binding this to a plain key acts as a toggle between the two most recent tabs.", @"Help text for the Cycle Tabs Forward action");
                break;

            case KEY_ACTION_PREVIOUS_MRU_TAB:
                _parameterValue = @"";
                _helpString = NSLocalizedStringWithDefaultValue(@"EditKeyAction.HelpPreviousMRUTab", nil, [NSBundle mainBundle], @"Switches tabs in reverse most-recently-used order. Hold a modifier and tap repeatedly to walk forward through tab history (oldest first); release the modifier to commit your selection. A single tap with no modifier held jumps to the least-recently-used tab.", @"Help text for the Cycle Tabs Backward action");
                break;

            case KEY_ACTION_FIND_REGEX:
                _parameterHidden = NO;
                _parameterPlaceholder = NSLocalizedStringWithDefaultValue(@"EditKeyAction.PlaceholderRegex", nil, [NSBundle mainBundle], @"Regular Expression", @"Placeholder for regular expression entry");
                _applyHidden = NO;
                break;

            case KEY_ACTION_COPY_MODE:
                _parameterHidden = NO;
                _parameterPlaceholder = NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionCopyModeCommands", nil, [NSBundle mainBundle], @"Copy Mode Commands", @"Copy mode commands label/placeholder");
                _applyHidden = NO;
                _helpString = NSLocalizedStringWithDefaultValue(@"EditKeyAction.HelpCopyMode", nil, [NSBundle mainBundle], @"Enter copy mode commands to move cursor, toggle selection, and so on. This key binding enters Copy Mode and then acts as though you had pressed the keys listed here. [See a list of all the commands](https://iterm2.com/documentation-copymode.html). Use vim syntax for control, option, and function keys (e.g., `<C-x>` or `<Up>`.", @"Help text for the Copy Mode action");
                break;

            case KEY_ACTION_TOGGLE_SETTING:
                _parameterPlaceholder = NSLocalizedStringWithDefaultValue(@"EditKeyAction.PlaceholderMenuItem", nil, [NSBundle mainBundle], @"Enter name of menu item", @"Placeholder for entering a menu item name");
                _settingToTogglePopupHidden = NO;
                _parameterValue = @"";
                break;

            case KEY_ACTION_INVOKE_SCRIPT_FUNCTION:
                _parameterHidden = NO;
                _parameterPlaceholder = NSLocalizedStringWithDefaultValue(@"EditKeyAction.PlaceholderFunctionCall", nil, [NSBundle mainBundle], @"Function Call", @"Placeholder for function call entry");
                if (functionCallDelegate) {
                    _parameterDelegate = functionCallDelegate;
                } else {
                    _parameterDelegate =
                    [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:context]
                                                                       passthrough:nil
                                                                     functionsOnly:YES];
                }
                _applyHidden = NO;
                break;

            case KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION:
            case KEY_ACTION_PASTE_SPECIAL:
                _pasteSpecialHidden = NO;
                _parameterValue = @"";
                _applyHidden = NO;
                break;

            case KEY_ACTION_MOVE_END_OF_SELECTION_LEFT:
            case KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT:
            case KEY_ACTION_MOVE_START_OF_SELECTION_LEFT:
            case KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT:
                _parameterValue = @"";
                _selectionMovementUnitHidden = NO;
                _parameterValue = @"";
                break;

            case KEY_ACTION_SEQUENCE:
                _showSecondary = YES;
                _parameterValue = @"";
                break;

            case KEY_ACTION_COPY_INTERPOLATED_STRING:
                _parameterHidden = NO;
                _parameterPlaceholder = NSLocalizedStringWithDefaultValue(@"EditKeyAction.PlaceholderInterpolatedString", nil, [NSBundle mainBundle], @"Enter interpolated string (evaluated in session context)", @"Placeholder for interpolated string entry");
                if (interpolatedStringDelegate) {
                    _parameterDelegate = interpolatedStringDelegate;
                } else {
                    _parameterDelegate =
                    [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:context]
                                                                       passthrough:nil
                                                                     functionsOnly:NO];
                }
                _helpString = NSLocalizedStringWithDefaultValue(@"EditKeyAction.HelpCopyInterpolated", nil, [NSBundle mainBundle], @"You can use this to copy information about the current session to the clipboard. [Learn more about interpolated strings](https://iterm2.com/documentation-scripting-fundamentals.html)", @"Help text for the Copy Interpolated String action");
                break;

            case KEY_ACTION_SCROLL_END:
            case KEY_ACTION_SCROLL_HOME:
            case KEY_ACTION_SCROLL_LINE_DOWN:
            case KEY_ACTION_SCROLL_LINE_UP:
            case KEY_ACTION_SCROLL_PAGE_DOWN:
            case KEY_ACTION_SCROLL_PAGE_UP:
            case KEY_ACTION_SEND_C_H_BACKSPACE:
            case KEY_ACTION_SEND_C_QM_BACKSPACE:
            case KEY_ACTION_DECREASE_HEIGHT:
            case KEY_ACTION_INCREASE_HEIGHT:
            case KEY_ACTION_DECREASE_WIDTH:
            case KEY_ACTION_INCREASE_WIDTH:
            case KEY_ACTION_TOGGLE_MOUSE_REPORTING:
            case KEY_ACTION_PASTE_OR_SEND:
            case KEY_ACTION_ALERT_ON_NEXT_MARK:
            case KEY_ACTION_COPY_OR_SEND:
                _parameterValue = @"";
                break;

            default:
                _parameterValue = @"";
                break;
        }
    }
    return self;
}

@end

@interface iTermEditKeyActionWindowController () <
    iTermKeyActionSequenceTableViewControllerDelegate,
    iTermPasteSpecialViewControllerDelegate,
    iTermSearchableComboViewDelegate,
    iTermShortcutInputViewDelegate,
    NSTextFieldDelegate>

@property(nonatomic, assign) BOOL ok;

@end

@implementation iTermEditKeyActionWindowController {
    IBOutlet NSView *_detail;
    IBOutlet NSView *_secondaryComboViewContainer;
    IBOutlet NSTextField *_secondaryActionLabel;
    IBOutlet NSView *_sequenceContainer;
    iTermSearchableComboView *_secondaryComboView;
    IBOutlet iTermKeyActionSequenceTableViewController *_sequenceTableViewController;

    IBOutlet iTermShortcutInputView *_shortcutField;
    IBOutlet NSTextField *_keyboardShortcutLabel;
    IBOutlet NSTextField *_touchBarLabel;
    IBOutlet NSView *_comboViewContainer;
    iTermSearchableComboView *_comboView;
    IBOutlet NSTextField *_parameter;
    IBOutlet NSTextField *_parameterLabel;
    IBOutlet NSPopUpButton *_profilePopup;
    IBOutlet NSPopUpButton *_selectionMovementUnit;
    IBOutlet iTermMenuItemPopupView *_menuToSelectPopup;
    IBOutlet iTermSettingPopupView *_settingToTogglePopup;
    IBOutlet NSTextField *_profileLabel;
    IBOutlet NSTextField *_colorPresetsLabel;
    IBOutlet NSPopUpButton *_colorPresetsPopup;
    IBOutlet NSPopUpButton *_snippetsPopup;
    IBOutlet NSView *_pasteSpecialViewContainer;
    IBOutlet NSButton *_okButton;
    NSPopUpButton *_applyButton;
    IBOutlet NSButton *_helpButton;
    IBOutlet NSTextField *_errorLabel;
    iTermEditKeyActionWindowConfiguration *_config;

    iTermPasteSpecialViewController *_pasteSpecialViewController;
    iTermFunctionCallTextFieldDelegate *_functionCallDelegate;
    iTermFunctionCallTextFieldDelegate *_interpolatedStringDelegate;
    iTermFunctionCallTextFieldDelegate *_labelDelegate;
}

- (instancetype)initWithContext:(iTermVariablesSuggestionContext)context
                           mode:(iTermEditKeyActionWindowControllerMode)mode
                    profileType:(ProfileType)profileType {
    self = [super initWithWindowNibName:@"iTermEditKeyActionWindowController" owner:self];
    if (self) {
        _profileType = profileType;
        _suggestContext = context;
        _mode = mode;
    }
    return self;
}

- (NSArray<iTermSearchableComboViewGroup *> *)groupsForPrimary:(BOOL)primary {
    NSArray<iTermSearchableComboViewGroup *> *groups = @[
        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.GroupGeneral", nil, [NSBundle mainBundle], @"General", @"Action group: General") items:[@[
            primary ? [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionIgnore", nil, [NSBundle mainBundle], @"Ignore", @"Action name: Ignore") tag:KEY_ACTION_IGNORE] : [NSNull null],
            primary ? [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionBypassTerminal", nil, [NSBundle mainBundle], @"Bypass Terminal", @"Action name: Bypass Terminal") tag:KEY_ACTION_BYPASS] : [NSNull null],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSelectMenuItem", nil, [NSBundle mainBundle], @"Select Menu Item…", @"Action name: Select Menu Item") tag:KEY_ACTION_SELECT_MENU_ITEM],
        ] arrayByRemovingNulls]]
    ];
    if (self.mode == iTermEditKeyActionWindowControllerModeKeyboardShortcut) {
        groups = [groups arrayByAddingObjectsFromArray:[@[
            primary ? [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.GroupModifierRemapping", nil, [NSBundle mainBundle], @"Modifier Remapping", @"Action group: Modifier Remapping") items:@[
                [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionDoNotRemapModifiers", nil, [NSBundle mainBundle], @"Do Not Remap Modifiers", @"Action name: Do Not Remap Modifiers") tag:KEY_ACTION_DO_NOT_REMAP_MODIFIERS],
                [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionRemapLocally", nil, [NSBundle mainBundle], @"Remap Modifiers in iTerm2 Only", @"Action name: Remap Modifiers in iTerm2 Only") tag:KEY_ACTION_REMAP_LOCALLY],
            ]] : [NSNull null],
            [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.GroupRecentTabs", nil, [NSBundle mainBundle], @"Recent Tabs", @"Action group: Recent Tabs") items:@[
                [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionCycleTabsForward", nil, [NSBundle mainBundle], @"Cycle Tabs Forward", @"Action name: Cycle Tabs Forward") tag:KEY_ACTION_NEXT_MRU_TAB],
                [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionCycleTabsBackward", nil, [NSBundle mainBundle], @"Cycle Tabs Backward", @"Action name: Cycle Tabs Backward") tag:KEY_ACTION_PREVIOUS_MRU_TAB],
            ]],
        ] arrayByRemovingNulls]];
    }

    const BOOL hideTerminalOnlyItems = (_profileType & ProfileTypeTerminal) == 0;
    groups = [groups arrayByAddingObjectsFromArray:[@[
        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.GroupMiscellaneous", nil, [NSBundle mainBundle], @"Miscellaneous", @"Action group: Miscellaneous") items:[@[
            hideTerminalOnlyItems ? [NSNull null] : [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionRunCoprocess", nil, [NSBundle mainBundle], @"Run Coprocess", @"Action name: Run Coprocess") tag:KEY_ACTION_RUN_COPROCESS],
            hideTerminalOnlyItems ? [NSNull null] : [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionStartInstantReplay", nil, [NSBundle mainBundle], @"Start Instant Replay", @"Action name: Start Instant Replay") tag:KEY_ACTION_IR_BACKWARD],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionUndo", nil, [NSBundle mainBundle], @"Undo", @"Action name: Undo") tag:KEY_ACTION_UNDO],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSendTmuxCommand", nil, [NSBundle mainBundle], @"Send tmux Command", @"Action name: Send tmux Command") tag:KEY_ACTION_SEND_TMUX_COMMAND],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionAlertOnNextMark", nil, [NSBundle mainBundle], @"Alert on Next Mark", @"Action name: Alert on Next Mark") tag:KEY_ACTION_ALERT_ON_NEXT_MARK],
        ] arrayByRemovingNulls]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.GroupNewTabOrWindow", nil, [NSBundle mainBundle], @"New Tab or Window", @"Action group: New Tab or Window") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionNewWindowWithProfile", nil, [NSBundle mainBundle], @"New Window with Profile", @"Action name: New Window with Profile") tag:KEY_ACTION_NEW_WINDOW_WITH_PROFILE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionNewTabWithProfile", nil, [NSBundle mainBundle], @"New Tab with Profile", @"Action name: New Tab with Profile") tag:KEY_ACTION_NEW_TAB_WITH_PROFILE],
        [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionDuplicateTab", nil, [NSBundle mainBundle], @"Duplicate Tab", @"Action name: Duplicate Tab") tag:KEY_ACTION_DUPLICATE_TAB],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.GroupSplit", nil, [NSBundle mainBundle], @"Split", @"Action group: Split") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSplitHorizontallyWithProfile", nil, [NSBundle mainBundle], @"Split Horizontally with Profile", @"Action name: Split Horizontally with Profile") tag:KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSplitVerticallyWithProfile", nil, [NSBundle mainBundle], @"Split Vertically with Profile", @"Action name: Split Vertically with Profile") tag:KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.GroupProfile", nil, [NSBundle mainBundle], @"Profile", @"Action group: Profile") items:[@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionChangeProfile", nil, [NSBundle mainBundle], @"Change Profile", @"Action name: Change Profile") tag:KEY_ACTION_SET_PROFILE],
            hideTerminalOnlyItems ? [NSNull null] : [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionLoadColorPreset", nil, [NSBundle mainBundle], @"Load Color Preset", @"Action name: Load Color Preset") tag:KEY_ACTION_LOAD_COLOR_PRESET],
        ] arrayByRemovingNulls]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.GroupNavigateTabs", nil, [NSBundle mainBundle], @"Navigate Tabs", @"Action group: Navigate Tabs") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionNextTab", nil, [NSBundle mainBundle], @"Next Tab", @"Action name: Next Tab") tag:KEY_ACTION_NEXT_SESSION],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionPreviousTab", nil, [NSBundle mainBundle], @"Previous Tab", @"Action name: Previous Tab") tag:KEY_ACTION_PREVIOUS_SESSION],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.GroupReorderTabs", nil, [NSBundle mainBundle], @"Reorder Tabs", @"Action group: Reorder Tabs") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionMoveTabLeft", nil, [NSBundle mainBundle], @"Move Tab Left", @"Action name: Move Tab Left") tag:KEY_ACTION_MOVE_TAB_LEFT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionMoveTabRight", nil, [NSBundle mainBundle], @"Move Tab Right", @"Action name: Move Tab Right") tag:KEY_ACTION_MOVE_TAB_RIGHT],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.GroupNavigateWindows", nil, [NSBundle mainBundle], @"Navigate Windows", @"Action group: Navigate Windows") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionNextWindow", nil, [NSBundle mainBundle], @"Next Window", @"Action name: Next Window") tag:KEY_ACTION_NEXT_WINDOW],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionPreviousWindow", nil, [NSBundle mainBundle], @"Previous Window", @"Action name: Previous Window") tag:KEY_ACTION_PREVIOUS_WINDOW],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.GroupNavigatePanes", nil, [NSBundle mainBundle], @"Navigate Panes", @"Action group: Navigate Panes") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionNextPane", nil, [NSBundle mainBundle], @"Next Pane", @"Action name: Next Pane") tag:KEY_ACTION_NEXT_PANE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionPreviousPane", nil, [NSBundle mainBundle], @"Previous Pane", @"Action name: Previous Pane") tag:KEY_ACTION_PREVIOUS_PANE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSelectPaneAbove", nil, [NSBundle mainBundle], @"Select Split Pane Above", @"Action name: Select Split Pane Above") tag:KEY_ACTION_SELECT_PANE_ABOVE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSelectPaneBelow", nil, [NSBundle mainBundle], @"Select Split Pane Below", @"Action name: Select Split Pane Below") tag:KEY_ACTION_SELECT_PANE_BELOW],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSelectPaneLeft", nil, [NSBundle mainBundle], @"Select Split Pane On Left", @"Action name: Select Split Pane On Left") tag:KEY_ACTION_SELECT_PANE_LEFT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSelectPaneRight", nil, [NSBundle mainBundle], @"Select Split Pane On Right", @"Action name: Select Split Pane On Right") tag:KEY_ACTION_SELECT_PANE_RIGHT],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.GroupResizePane", nil, [NSBundle mainBundle], @"Resize Pane", @"Action group: Resize Pane") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionDecreaseHeight", nil, [NSBundle mainBundle], @"Decrease Height", @"Action name: Decrease Height") tag:KEY_ACTION_DECREASE_HEIGHT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionIncreaseHeight", nil, [NSBundle mainBundle], @"Increase Height", @"Action name: Increase Height") tag:KEY_ACTION_INCREASE_HEIGHT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionDecreaseWidth", nil, [NSBundle mainBundle], @"Decrease Width", @"Action name: Decrease Width") tag:KEY_ACTION_DECREASE_WIDTH],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionIncreaseWidth", nil, [NSBundle mainBundle], @"Increase Width", @"Action name: Increase Width") tag:KEY_ACTION_INCREASE_WIDTH],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.GroupScroll", nil, [NSBundle mainBundle], @"Scroll", @"Action group: Scroll") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionScrollToEnd", nil, [NSBundle mainBundle], @"Scroll to End", @"Action name: Scroll to End") tag:KEY_ACTION_SCROLL_END],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionScrollToTop", nil, [NSBundle mainBundle], @"Scroll to Top", @"Action name: Scroll to Top") tag:KEY_ACTION_SCROLL_HOME],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionScrollLineDown", nil, [NSBundle mainBundle], @"Scroll One Line Down", @"Action name: Scroll One Line Down") tag:KEY_ACTION_SCROLL_LINE_DOWN],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionScrollLineUp", nil, [NSBundle mainBundle], @"Scroll One Line Up", @"Action name: Scroll One Line Up") tag:KEY_ACTION_SCROLL_LINE_UP],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionScrollPageDown", nil, [NSBundle mainBundle], @"Scroll One Page Down", @"Action name: Scroll One Page Down") tag:KEY_ACTION_SCROLL_PAGE_DOWN],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionScrollPageUp", nil, [NSBundle mainBundle], @"Scroll One Page Up", @"Action name: Scroll One Page Up") tag:KEY_ACTION_SCROLL_PAGE_UP],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.GroupSplitPanes", nil, [NSBundle mainBundle], @"Split Panes", @"Action group: Split Panes") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSwapPaneAbove", nil, [NSBundle mainBundle], @"Swap With Split Pane Above", @"Action name: Swap With Split Pane Above") tag:KEY_ACTION_SWAP_PANE_ABOVE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSwapPaneBelow", nil, [NSBundle mainBundle], @"Swap With Split Pane Below", @"Action name: Swap With Split Pane Below") tag:KEY_ACTION_SWAP_PANE_BELOW],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSwapPaneLeft", nil, [NSBundle mainBundle], @"Swap With Split Pane on Left", @"Action name: Swap With Split Pane on Left") tag:KEY_ACTION_SWAP_PANE_LEFT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSwapPaneRight", nil, [NSBundle mainBundle], @"Swap With Split Pane on Right", @"Action name: Swap With Split Pane on Right") tag:KEY_ACTION_SWAP_PANE_RIGHT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSwapWithNextPane", nil, [NSBundle mainBundle], @"Swap With Next Pane", @"Action name: Swap With Next Pane") tag:KEY_ACTION_SWAP_WITH_NEXT_PANE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSwapWithPreviousPane", nil, [NSBundle mainBundle], @"Swap With Previous Pane", @"Action name: Swap With Previous Pane") tag:KEY_ACTION_SWAP_WITH_PREVIOUS_PANE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionMoveToSplitPane", nil, [NSBundle mainBundle], @"Move Session to Split Pane", @"Action name: Move Session to Split Pane") tag:KEY_ACTION_MOVE_TO_SPLIT_PANE],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.GroupSendKeystrokes", nil, [NSBundle mainBundle], @"Send Keystrokes", @"Action group: Send Keystrokes") items:[@[
            hideTerminalOnlyItems ? [NSNull null] : [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSendCHBackspace", nil, [NSBundle mainBundle], @"Send ^H Backspace", @"Action name: Send Control-H Backspace") tag:KEY_ACTION_SEND_C_H_BACKSPACE],
            hideTerminalOnlyItems ? [NSNull null] : [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSendCQMBackspace", nil, [NSBundle mainBundle], @"Send ^? Backspace", @"Action name: Send Control-Question-Mark Backspace") tag:KEY_ACTION_SEND_C_QM_BACKSPACE],
            hideTerminalOnlyItems ? [NSNull null] : [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSendEscapeSequence", nil, [NSBundle mainBundle], @"Send Escape Sequence", @"Action name: Send Escape Sequence") tag:KEY_ACTION_ESCAPE_SEQUENCE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSendHexCode", nil, [NSBundle mainBundle], @"Send Hex Code", @"Action name: Send Hex Code") tag:KEY_ACTION_HEX_CODE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSendText", nil, [NSBundle mainBundle], @"Send Text", @"Action name: Send Text") tag:KEY_ACTION_TEXT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSendVimText", nil, [NSBundle mainBundle], @"Send Text with “vim” Special Chars", @"Action name: Send Text with vim special characters") tag:KEY_ACTION_VIM_TEXT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSendTextNoBroadcast", nil, [NSBundle mainBundle], @"Send Text without Broadcasting", @"Action name: Send Text without Broadcasting") tag:KEY_ACTION_VIM_TEXT_NO_BROADCAST],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSendSnippet", nil, [NSBundle mainBundle], @"Send Snippet", @"Action name: Send Snippet") tag:KEY_ACTION_SEND_SNIPPET],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionCompose", nil, [NSBundle mainBundle], @"Compose…", @"Action name: Compose") tag:KEY_ACTION_COMPOSE],
        ] arrayByRemovingNulls]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.GroupSearch", nil, [NSBundle mainBundle], @"Search", @"Action group: Search") items:[@[
            hideTerminalOnlyItems ? [NSNull null] : [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionFindRegex", nil, [NSBundle mainBundle], @"Find Regular Expression…", @"Action name: Find Regular Expression") tag:KEY_ACTION_FIND_REGEX],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionFindAgainDown", nil, [NSBundle mainBundle], @"Find Again Down", @"Action name: Find Again Down") tag:KEY_FIND_AGAIN_DOWN],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionFindAgainUp", nil, [NSBundle mainBundle], @"Find Again Up", @"Action name: Find Again Up") tag:KEY_FIND_AGAIN_UP],
        ] arrayByRemovingNulls]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.GroupPasteboard", nil, [NSBundle mainBundle], @"Pasteboard", @"Action group: Pasteboard") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionPaste", nil, [NSBundle mainBundle], @"Paste…", @"Action name: Paste") tag:KEY_ACTION_PASTE_SPECIAL],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionPasteFromSelection", nil, [NSBundle mainBundle], @"Paste from Selection…", @"Action name: Paste from Selection") tag:KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionCopyOrSend", nil, [NSBundle mainBundle], @"Copy or Send ^C", @"Action name: Copy or Send Control-C") tag:KEY_ACTION_COPY_OR_SEND],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionPasteOrSend", nil, [NSBundle mainBundle], @"Paste or Send ^V", @"Action name: Paste or Send Control-V") tag:KEY_ACTION_PASTE_OR_SEND],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionCopyInterpolatedString", nil, [NSBundle mainBundle], @"Copy Interpolated String", @"Action name: Copy Interpolated String") tag:KEY_ACTION_COPY_INTERPOLATED_STRING],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionCopyModeCommands", nil, [NSBundle mainBundle], @"Copy Mode Commands", @"Action name: Copy Mode Commands") tag:KEY_ACTION_COPY_MODE],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.GroupToggles", nil, [NSBundle mainBundle], @"Toggles", @"Action group: Toggles") items:[@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionToggleFullscreen", nil, [NSBundle mainBundle], @"Toggle Fullscreen", @"Action name: Toggle Fullscreen") tag:KEY_ACTION_TOGGLE_FULLSCREEN],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionTogglePinHotkeyWindow", nil, [NSBundle mainBundle], @"Toggle Pin Hotkey Window", @"Action name: Toggle Pin Hotkey Window") tag:KEY_ACTION_TOGGLE_HOTKEY_WINDOW_PINNING],
            hideTerminalOnlyItems ? [NSNull null] : [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionToggleMouseReporting", nil, [NSBundle mainBundle], @"Toggle Mouse Reporting", @"Action name: Toggle Mouse Reporting") tag:KEY_ACTION_TOGGLE_MOUSE_REPORTING],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionToggleSetting", nil, [NSBundle mainBundle], @"Toggle Setting", @"Action name: Toggle Setting") tag:KEY_ACTION_TOGGLE_SETTING],
        ] arrayByRemovingNulls]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.GroupSelection", nil, [NSBundle mainBundle], @"Selection", @"Action group: Selection") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionMoveStartSelectionBack", nil, [NSBundle mainBundle], @"Move Start of Selection Back", @"Action name: Move Start of Selection Back") tag:KEY_ACTION_MOVE_START_OF_SELECTION_LEFT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionMoveStartSelectionForward", nil, [NSBundle mainBundle], @"Move Start of Selection Forward", @"Action name: Move Start of Selection Forward") tag:KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionMoveEndSelectionBack", nil, [NSBundle mainBundle], @"Move End of Selection Back", @"Action name: Move End of Selection Back") tag:KEY_ACTION_MOVE_END_OF_SELECTION_LEFT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionMoveEndSelectionForward", nil, [NSBundle mainBundle], @"Move End of Selection Forward", @"Action name: Move End of Selection Forward") tag:KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.GroupScripting", nil, [NSBundle mainBundle], @"Scripting", @"Action group: Scripting") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionInvokeScriptFunction", nil, [NSBundle mainBundle], @"Invoke Script Function…", @"Action name: Invoke Script Function") tag:KEY_ACTION_INVOKE_SCRIPT_FUNCTION],
        ]],

        primary ? [[iTermSearchableComboViewGroup alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.GroupComposition", nil, [NSBundle mainBundle], @"Composition", @"Action group: Composition") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ActionSequence", nil, [NSBundle mainBundle], @"Sequence…", @"Action name: Sequence") tag:KEY_ACTION_SEQUENCE],
        ]] : [NSNull null],
    ] arrayByRemovingNulls]];
    return groups;
}

- (void)windowDidLoad
{
    [super windowDidLoad];

    _sequenceTableViewController.delegate = self;
    _menuToSelectPopup.delegate = self;
    _settingToTogglePopup.delegate = self;

    switch (self.mode) {
        case iTermEditKeyActionWindowControllerModeKeyboardShortcut:
            break;
        case iTermEditKeyActionWindowControllerModeTouchBarItem:
            _touchBarLabel.placeholderString = NSLocalizedStringWithDefaultValue(@"EditKeyAction.TouchBarLabelPlaceholder", nil, [NSBundle mainBundle], @"Label to show in Touch Bar", @"Placeholder for the Touch Bar label field");
            break;
        case iTermEditKeyActionWindowControllerModeUnbound:
            _touchBarLabel.placeholderString = self.titleIsInterpolated ? NSLocalizedStringWithDefaultValue(@"EditKeyAction.TitleInterpolatedPlaceholder", nil, [NSBundle mainBundle], @"Title (Interpolated String)", @"Placeholder for interpolated title field") : NSLocalizedStringWithDefaultValue(@"EditKeyAction.Title", nil, [NSBundle mainBundle], @"Title", @"Placeholder/label: Title");
            break;
    }

    _comboView = [[iTermSearchableComboView alloc] initWithGroups:[self groupsForPrimary:YES]
                                                     defaultTitle:NSLocalizedStringWithDefaultValue(@"EditKeyAction.SelectAction", nil, [NSBundle mainBundle], @"Select Action…", @"Default title for the action chooser popup")];
    [_comboViewContainer addSubview:_comboView];
    _comboView.frame = _comboViewContainer.bounds;
    _comboView.delegate = self;

    _secondaryComboView = [[iTermSearchableComboView alloc] initWithGroups:[self groupsForPrimary:NO]
                                                              defaultTitle:NSLocalizedStringWithDefaultValue(@"EditKeyAction.SelectAction", nil, [NSBundle mainBundle], @"Select Action…", @"Default title for the action chooser popup")];
    [_secondaryComboViewContainer addSubview:_secondaryComboView];
    _secondaryComboView.frame = _secondaryComboViewContainer.bounds;
    _secondaryComboView.delegate = self;

    // For some reason, the first item is checked by default. Make sure every
    // item is unchecked before making a selection.
    NSString *formattedString = @"";
    if (self.currentKeystroke) {
        formattedString = [iTermKeystrokeFormatter stringForKeystroke:self.currentKeystroke];
    }
    _shortcutField.stringValue = formattedString;
    _touchBarLabel.stringValue = self.label ?: @"";
    _okButton.enabled = [self shouldEnableOK];
    (void)[_comboView selectItemWithTag:self.action];

    _applyButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_applyButton addItemWithTitle:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ApplyToCurrentSession", nil, [NSBundle mainBundle], @"Apply to current session", @"Apply-mode menu item: current session")];
    _applyButton.menu.itemArray.lastObject.tag = iTermActionApplyModeCurrentSession;
    [_applyButton addItemWithTitle:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ApplyToAllSessions", nil, [NSBundle mainBundle], @"Apply to all sessions", @"Apply-mode menu item: all sessions")];
    _applyButton.menu.itemArray.lastObject.tag = iTermActionApplyModeAllSessions;
    [_applyButton addItemWithTitle:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ApplyToUnfocused", nil, [NSBundle mainBundle], @"Apply to all sessions except current", @"Apply-mode menu item: all sessions except current")];
    _applyButton.menu.itemArray.lastObject.tag = iTermActionApplyModeUnfocusedSessions;
    [_applyButton addItemWithTitle:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ApplyToAllInWindow", nil, [NSBundle mainBundle], @"Apply to all sessions in window", @"Apply-mode menu item: all sessions in window")];
    _applyButton.menu.itemArray.lastObject.tag = iTermActionApplyModeAllInWindow;
    [_applyButton addItemWithTitle:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ApplyToAllInTab", nil, [NSBundle mainBundle], @"Apply to all sessions in tab", @"Apply-mode menu item: all sessions in tab")];
    _applyButton.menu.itemArray.lastObject.tag = iTermActionApplyModeAllInTab;
    [_applyButton addItemWithTitle:NSLocalizedStringWithDefaultValue(@"EditKeyAction.ApplyToBroadcasted", nil, [NSBundle mainBundle], @"Apply to broadcasted-to sessions", @"Apply-mode menu item: broadcasted-to sessions")];
    _applyButton.menu.itemArray.lastObject.tag = iTermActionApplyModeBroadcasting;

    _applyButton.target = self;
    _applyButton.action = @selector(parameterDidChange:);
    [_detail addSubview:_applyButton];

    [self loadParameter:self.parameterValue
                 action:self.action
              applyMode:self.applyMode
              secondary:NO];
}

- (void)loadParameter:(NSString *)parameterValue
               action:(KEY_ACTION)action
            applyMode:(iTermActionApplyMode)applyMode
            secondary:(BOOL)secondary {
    _parameter.stringValue = parameterValue ?: @"";
    if (action == KEY_ACTION_SELECT_MENU_ITEM) {
        [_menuToSelectPopup reloadData];
        NSArray *parts = [parameterValue ?: @"" componentsSeparatedByString:@"\n"];
        NSString *storedTitle = parts.count > 0 ? parts.firstObject : nil;
        NSString *storedIdentifier = parts.count > 1 ? parts[1] : nil;
        [_menuToSelectPopup selectItemWithIdentifier:storedIdentifier title:storedTitle];
    } else if (action == KEY_ACTION_TOGGLE_SETTING) {
        [_settingToTogglePopup reloadData];
        [_settingToTogglePopup selectItemWithIdentifier:parameterValue ?: @""];
    }

    if (_pasteSpecialViewController == nil) {
        _pasteSpecialViewController = [[iTermPasteSpecialViewController alloc] init];
        _pasteSpecialViewController.profileType = _profileType;
        [_pasteSpecialViewController view];
    }

    [self updateViewsAnimated:NO secondary:secondary];

    if (!_profilePopup.isHidden) {
        [_profilePopup populateWithProfilesSelectingGuid:parameterValue ?: @""
                                            profileTypes:_profileType];
    }
    if (!_colorPresetsPopup.isHidden) {
        [_colorPresetsPopup loadColorPresetsSelecting:parameterValue ?: @""];
    }
    if (!_snippetsPopup.isHidden) {
        [_snippetsPopup populateWithSnippetsSelectingActionKey:parameterValue ?: @""];
    }
    if (!_selectionMovementUnit.isHidden) {
        [_selectionMovementUnit selectItemWithTag:[parameterValue ?: @"" integerValue]];
    }
    if (!_secondaryComboViewContainer.isHidden && !secondary) {
        [_sequenceTableViewController setActions:[parameterValue ?: @"" keyBindingActionsFromSequenceParameter]];
    }
    if (self.action == KEY_ACTION_PASTE_SPECIAL ||
        self.action == KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION) {
        [_pasteSpecialViewController loadSettingsFromString:parameterValue ?: @""];
    } else {
        // Set a few defaults; otherwise everything is reasonable.
        _pasteSpecialViewController.numberOfSpacesPerTab = [iTermPreferences intForKey:kPreferenceKeyPasteSpecialSpacesPerTab];
        _pasteSpecialViewController.shouldRemoveNewlines = NO;
        _pasteSpecialViewController.shouldBase64Encode = NO;
        _pasteSpecialViewController.shouldWaitForPrompt = NO;
        _pasteSpecialViewController.shouldEscapeShellCharsWithBackslash = NO;
    }
    _pasteSpecialViewController.view.frame = _pasteSpecialViewController.view.bounds;
    _pasteSpecialViewController.delegate = self;
    NSRect theFrame = _pasteSpecialViewContainer.frame;
    CGFloat originalHeight = theFrame.size.height;
    theFrame.size = _pasteSpecialViewController.view.bounds.size;
    theFrame.origin.y -= (theFrame.size.height - originalHeight);
    _pasteSpecialViewContainer.frame = theFrame;
    if (_pasteSpecialViewController.view.superview == nil) {
        [_pasteSpecialViewContainer addSubview:_pasteSpecialViewController.view];
    }
    _applyMode = applyMode;
    [_applyButton selectItemWithTag:applyMode];
    [self updateError];
}

- (void)setAction:(KEY_ACTION)keyAction parameter:(NSString *)parameter applyMode:(iTermActionApplyMode)applyMode {
    [self setAction:keyAction];
    _parameterValue = [parameter copy];
    _applyMode = applyMode;
}

- (void)setAction:(int)action {
    if (action == KEY_ACTION_IR_FORWARD) {
        action = KEY_ACTION_IGNORE;
    }
    _action = action;
}

- (iTermAction *)unboundAction {
    return [[iTermAction alloc] initWithTitle:self.label
                                       action:self.action
                                    parameter:self.parameterValue
                                     escaping:self.escaping
                                    applyMode:self.applyMode
                                      version:[iTermAction currentVersion]];
}

- (iTermKeystrokeOrTouchbarItem *)keystrokeOrTouchbarItem {
    switch (_mode) {
        case iTermEditKeyActionWindowControllerModeKeyboardShortcut:
            return [iTermOr first:self.currentKeystroke];
        case iTermEditKeyActionWindowControllerModeTouchBarItem:
            return [iTermOr second:[[iTermTouchbarItem alloc] initWithIdentifier:self.touchBarItemID]];
        case iTermEditKeyActionWindowControllerModeUnbound:
            return nil;
    }
}

#pragma mark - iTermShortcutInputViewDelegate

// Note: This is called directly by iTermHotKeyController when the action requires key remapping
// to be disabled so the shortcut can be input properly. In this case, |view| will be nil.
- (void)shortcutInputView:(iTermShortcutInputView *)view didReceiveKeyPressEvent:(NSEvent *)event {
    self.currentKeystroke = view.shortcut.keystroke;
    _okButton.enabled = [self shouldEnableOK];
}

- (void)setMode:(iTermEditKeyActionWindowControllerMode)mode {
    assert(NO);
}

#pragma mark - Private

- (void)updateViewsAnimated:(BOOL)animated secondary:(BOOL)secondary {
    switch (self.mode) {
        case iTermEditKeyActionWindowControllerModeUnbound:
            _keyboardShortcutLabel.stringValue = NSLocalizedStringWithDefaultValue(@"EditKeyAction.Title", nil, [NSBundle mainBundle], @"Title", @"Placeholder/label: Title");
            if (self.titleIsInterpolated) {
                if (!_labelDelegate) {
                    _labelDelegate = [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextSession]
                                                                                        passthrough:self
                                                                                      functionsOnly:NO];
                }
                _touchBarLabel.delegate = _labelDelegate;
            } else {
                _touchBarLabel.delegate = self;
            }
            _touchBarLabel.hidden = NO;
            _shortcutField.hidden = YES;
            break;
        case iTermEditKeyActionWindowControllerModeTouchBarItem:
            _keyboardShortcutLabel.stringValue = NSLocalizedStringWithDefaultValue(@"EditKeyAction.TouchBarLabelTitle", nil, [NSBundle mainBundle], @"Touch Bar Label", @"Label for the Touch Bar label field");
            _touchBarLabel.delegate = self;
            _touchBarLabel.hidden = NO;
            _shortcutField.hidden = YES;
            break;
        case iTermEditKeyActionWindowControllerModeKeyboardShortcut:
            _keyboardShortcutLabel.stringValue = NSLocalizedStringWithDefaultValue(@"EditKeyAction.KeyboardShortcutLabel", nil, [NSBundle mainBundle], @"Keyboard Shortcut:", @"Label for the keyboard shortcut field");
            _touchBarLabel.hidden = YES;
            _shortcutField.hidden = NO;
            break;
    }

    const int tag = secondary ? _secondaryComboView.selectedTag : _comboView.selectedTag;
    iTermEditKeyActionWindowConfiguration *config = [[iTermEditKeyActionWindowConfiguration alloc] initWithTag:tag
                                                                                          functionCallDelegate:_functionCallDelegate
                                                                                    interpolatedStringDelegate:_interpolatedStringDelegate
                                                                                                       context:_suggestContext];
    _config = config;
    if (config.parameterPlaceholder) {
        [_parameter.cell setPlaceholderString:config.parameterPlaceholder];
    }
    if (config.parameterLabel) {
        _parameterLabel.stringValue = config.parameterLabel;
    }
    if (config.parameterValue) {
        _parameter.stringValue = config.parameterValue;
    }
    if (config.parameterDelegate.functionsOnly) {
        _functionCallDelegate = config.parameterDelegate;
        _functionCallDelegate.passthrough = self;
    } else {
        _functionCallDelegate = nil;
    }
    if (config.parameterDelegate && !config.parameterDelegate.functionsOnly) {
        _interpolatedStringDelegate = config.parameterDelegate;
        _interpolatedStringDelegate.passthrough = self;
    } else {
        _interpolatedStringDelegate = nil;
    }
    _parameter.delegate = config.parameterDelegate ?: self;
    [_parameter setHidden:config.parameterHidden];
    _helpButton.hidden = config.helpString == nil;
    [_parameterLabel setHidden:config.parameterLabelHidden];
    [_profilePopup setHidden:config.profilePopupHidden];
    if (!config.profilePopupHidden) {
        [_profilePopup populateWithProfilesSelectingGuid:config.parameterValue ?: @""
                                            profileTypes:_profileType];
    }
    [_selectionMovementUnit setHidden:config.selectionMovementUnitHidden];
    [_profileLabel setHidden:config.profileLabelHidden];
    [_menuToSelectPopup setHidden:config.menuToSelectPopupHidden];
    [_settingToTogglePopup setHidden:config.settingToTogglePopupHidden];
    _shortcutField.disableKeyRemapping = config.shortcutFieldDisableKeyRemapping;
    [_colorPresetsLabel setHidden:config.colorPresetsLabelHidden];
    [_colorPresetsPopup setHidden:config.colorPresetsPopupHidden];
    [_snippetsPopup setHidden:config.snippetsHidden];
    [self setPasteSpecialHidden:config.pasteSpecialHidden];
    if (!secondary) {
        if (config.showSecondary) {
            NSRect frame = _detail.frame;
            frame.origin.x = NSMaxX(_sequenceContainer.frame) + 8;
            _detail.frame = frame;

        } else {
            NSRect frame = _detail.frame;
            frame.origin.x = NSMinX(_sequenceContainer.frame);
            _detail.frame = frame;
        }
        _sequenceContainer.hidden = !config.showSecondary;
        _secondaryActionLabel.hidden = !config.showSecondary;
        _secondaryComboViewContainer.hidden = !config.showSecondary;
    }
    if (_sequenceTableViewController.hasSelection) {
        (void)[_secondaryComboView selectItemWithTag:_sequenceTableViewController.selectedItem.keyAction];
    }
    _secondaryActionLabel.labelEnabled = _sequenceTableViewController.hasSelection;
    _secondaryComboView.enabled = _sequenceTableViewController.hasSelection;
    if (!_sequenceTableViewController.hasSelection) {
        (void)[_secondaryComboView selectItemWithTag:-1];
    }
    _applyButton.hidden = config.applyHidden;
    if (config.applyHidden) {
        [_applyButton selectItemWithTag:iTermActionApplyModeCurrentSession];
    } else {
        [_applyButton sizeToFit];
        NSRect applyButtonFrame = _applyButton.frame;
        applyButtonFrame.origin.x = [self desiredMinXForApplyButton];
        applyButtonFrame.origin.y = [self desiredYOriginForApplyButton];
        applyButtonFrame.size.width = _comboViewContainer.frame.size.width;
        _applyButton.frame = applyButtonFrame;
        _applyButton.autoresizingMask = 0;
    }
    [self updateFrameAnimated:animated];
}

- (CGFloat)desiredMinXForApplyButton {
    return NSMinX(_shortcutField.frame) - NSMinX(_keyboardShortcutLabel.frame) - 4;
}

- (CGFloat)desiredYOriginForApplyButton {
    NSView *lowestView = [[[_detail subviews] filteredArrayUsingBlock:^BOOL(__kindof NSView *view) {
        return !view.isHidden && view != _applyButton;
    }] minWithBlock:^NSComparisonResult(__kindof NSView *lhs, __kindof NSView *rhs) {
        return [@(NSMinY(lhs.frame)) compare:@(NSMinY(rhs.frame))];
    }];
    CGFloat bottom;
    if (lowestView) {
        bottom = NSMinY(lowestView.frame);
    } else {
        NSRect actionFrame = [_detail convertRect:_comboViewContainer.bounds fromView:_comboViewContainer];
        bottom = NSMinY(actionFrame);
    }
    return bottom - _applyButton.frame.size.height - 4;
}

- (BOOL)anyAccessoryVisible {
    return (!_sequenceContainer.isHidden ||
            [self anyNonSequenceAccessoryVisible]);
}

- (BOOL)anyNonSequenceAccessoryVisible {
    return (!_parameter.isHidden ||
            !_profilePopup.isHidden ||
            !_menuToSelectPopup.isHidden ||
            !_settingToTogglePopup.isHidden ||
            !_colorPresetsPopup.isHidden ||
            !_snippetsPopup.isHidden ||
            !_pasteSpecialViewContainer.isHidden ||
            !_parameterLabel.isHidden ||
            !_selectionMovementUnit.isHidden);
}

- (void)updateFrameAnimated:(BOOL)animated {
    NSRect rect = self.window.frame;
    rect.size = [self desiredSize];
    if (animated) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.window setFrame:rect display:YES animate:YES];
        });
    } else {
        [self.window setFrame:rect display:YES animate:NO];
    }
}

//    Side margin                     Side margin
//    |                               |
//   |-|                             |-|
//   +---------------------------------+
//   |                                 |
//   |  Keyboard shortcut: [        ]  |
//   |             Action: [v Popup ]  |  _
//   |         Basic Accessory         |  _|-- Basic accessory height
//   |                                 |
//   |                  [Cancel] [OK]  |
//   +---------------------------------+
//      |---------------------------|
//      Normal width excluding margins
//
//   +---------------------------------+  -
//   |                                 |  |
//   |  Keyboard shortcut: [        ]  |  |
//   |             Action: [v Popup ]  |  |-- Height excluding accessory
//   |                                 |  |
//   |                   [Cancel] [OK] |  |
//   +---------------------------------+  -

- (NSSize)desiredSize {
    return NSMakeSize(self.desiredWidthExcludingMargins + sideMarginWidth,
                      self.desiredHeight);
}

- (CGFloat)desiredWidthExcludingMargins {
    CGFloat normalWidthExcludingMargins = 402;
    if (!_helpButton.isHidden) {
        normalWidthExcludingMargins += _helpButton.frame.size.width + 6;
    }
    if (!_secondaryComboViewContainer.isHidden) {
        return NSMaxX(_detail.frame) - NSMinX(_sequenceContainer.frame);
    }
    if (!_pasteSpecialViewContainer.hidden) {
        return MAX(normalWidthExcludingMargins,
                   _pasteSpecialViewController.view.frame.size.width);
    }
    if (!_parameter.isHidden) {
        return NSMaxX(_parameter.frame);
    }
    return normalWidthExcludingMargins;
}

- (CGFloat)desiredHeight {
    const CGFloat heightExcludingAccessory = 126;
    return heightExcludingAccessory + [self accessoryHeight];
}

- (CGFloat)accessoryHeight {
    CGFloat height = 0;
    if (!_applyButton.isHidden) {
        height += _applyButton.frame.size.height + 4;
    }
    if (![self anyAccessoryVisible]) {
        return height;
    }
    if (!_sequenceContainer.isHidden) {
        height += MAX(NSHeight(_sequenceContainer.frame), self.nonSequenceAccessoryHeight);
        return height;
    }
    return height + [self nonSequenceAccessoryHeight];
}

- (CGFloat)nonSequenceAccessoryHeight {
    if (![self anyNonSequenceAccessoryVisible]) {
        return 0;
    }
    if (!_parameter.isHidden) {
        if (_errorLabel.isHidden) {
            return NSHeight(_parameter.frame);
        } else {
            return NSMaxY(_parameter.frame) - NSMinY(_errorLabel.frame);
        }
    }
    if (!_pasteSpecialViewContainer.isHidden) {
        return _pasteSpecialViewController.view.frame.size.height;
    }
    const CGFloat basicAccessoryHeight = 31;
    return basicAccessoryHeight;
}

- (void)setPasteSpecialHidden:(BOOL)hidden {
    _pasteSpecialViewContainer.hidden = hidden;
}

- (BOOL)shouldEnableOK {
    switch (self.mode) {
        case iTermEditKeyActionWindowControllerModeUnbound:
            break;
        case iTermEditKeyActionWindowControllerModeTouchBarItem:
            if (!_touchBarLabel.stringValue.length) {
                return NO;
            }
            break;
        case iTermEditKeyActionWindowControllerModeKeyboardShortcut:
            if (!self.currentKeystroke) {
                return NO;
            }
            break;
    }
    return YES;
}

#pragma mark - Actions

- (IBAction)help:(id)sender {
    [[NSView castFrom:sender] it_showWarningWithMarkdown:_config.helpString];
}


- (IBAction)parameterDidChange:(id)sender {
    if (!_secondaryComboViewContainer.isHidden) {
        [_sequenceTableViewController reloadCurrentItem:[self secondaryAction]];
    }
    [self updateError];
}

- (IBAction)ok:(id)sender {
    switch (self.mode) {
        case iTermEditKeyActionWindowControllerModeUnbound:
            self.label = _touchBarLabel.stringValue ?: @"";
            break;
        case iTermEditKeyActionWindowControllerModeTouchBarItem:
            if (!_touchBarLabel.stringValue.length) {
                DLog(@"Beep: empty touch bar label");
                NSBeep();
                return;
            }
            self.label = _touchBarLabel.stringValue;
            break;
        case iTermEditKeyActionWindowControllerModeKeyboardShortcut:
            if (!self.currentKeystroke) {
                DLog(@"Beep: no key combo");
                NSBeep();
                return;
            }
            break;
    }

    const KEY_ACTION keyAction = _comboView.selectedTag;
    const BOOL secondary = !_secondaryComboViewContainer.hidden;
    const BOOL hasApplyMode = !secondary && !_applyButton.isHidden;
    [self setAction:keyAction
          parameter:[self parameterValueForAction:keyAction]
          applyMode:hasApplyMode ? _applyButton.selectedTag : iTermActionApplyModeCurrentSession];

    self.ok = YES;
    [self.window.sheetParent endSheet:self.window];
}

- (NSString *)parameterValueForAction:(KEY_ACTION)action {
    switch (action) {
        case KEY_ACTION_SELECT_MENU_ITEM:
            return [iTermMenuItemBinding storedParameterForIdentifier:_menuToSelectPopup.selectedIdentifier
                                                                title:_menuToSelectPopup.selectedTitle
                                                         hasSelection:_menuToSelectPopup.hasSelection
                                                             original:self.parameterValue
                                                      identifierFirst:NO];
        case KEY_ACTION_TOGGLE_SETTING:
            return _settingToTogglePopup.selectedIdentifier;

        case KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE:
        case KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE:
        case KEY_ACTION_NEW_TAB_WITH_PROFILE:
        case KEY_ACTION_NEW_WINDOW_WITH_PROFILE:
        case KEY_ACTION_SET_PROFILE:
            return [[_profilePopup selectedItem] representedObject];

        case KEY_ACTION_LOAD_COLOR_PRESET:
            return [[_colorPresetsPopup selectedItem] title];

        case KEY_ACTION_SEND_SNIPPET:
            return [[_snippetsPopup selectedItem] representedObject];

        case KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION:
        case KEY_ACTION_PASTE_SPECIAL:
            return [_pasteSpecialViewController stringEncodedSettings];

        case KEY_ACTION_MOVE_END_OF_SELECTION_LEFT:
        case KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT:
        case KEY_ACTION_MOVE_START_OF_SELECTION_LEFT:
        case KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT:
            return [@(_selectionMovementUnit.selectedTag) description];

        case KEY_ACTION_COMPOSE:
        default:
            return [_parameter stringValue];

        case KEY_ACTION_SEQUENCE:
            return [NSString parameterForKeyBindingActionSequence:_sequenceTableViewController.actions];
    }
    return @"";
}

- (IBAction)cancel:(id)sender {
    self.ok = NO;
    [self.window.sheetParent endSheet:self.window];
}

#pragma mark - iTermSearchableComboViewDelegate

- (iTermKeyBindingAction *)secondaryAction {
    const KEY_ACTION action = _secondaryComboView.selectedTag;
    return [iTermKeyBindingAction withAction:action
                                   parameter:[self parameterValueForAction:action]
                                    escaping:self.escaping
                                   applyMode:_applyButton.isHidden ? iTermActionApplyModeCurrentSession : _applyButton.selectedTag];
}

- (void)searchableComboView:(iTermSearchableComboView *)view didSelectItem:(iTermSearchableComboViewItem *)didSelectItem {
    if (view == _comboView) {
        _parameterValue = @"";
    }
    if (view == _comboView || view == _secondaryComboView) {
        NSString *guid = [[_profilePopup selectedItem] representedObject];
        [_profilePopup populateWithProfilesSelectingGuid:guid
                                            profileTypes:_profileType];
        [_colorPresetsPopup loadColorPresetsSelecting:_colorPresetsPopup.selectedItem.representedObject];
        [_snippetsPopup populateWithSnippetsSelectingActionKey:_snippetsPopup.selectedItem.representedObject];
        [_menuToSelectPopup reloadData];
        [_settingToTogglePopup reloadData];
        const BOOL secondary = (view == _secondaryComboView);
        if (secondary) {
            [_sequenceTableViewController setActionForCurrentItem:view.selectedTag];
        }
        [self updateViewsAnimated:YES secondary:secondary];
        if (!_secondaryComboViewContainer.isHidden) {
            [_sequenceTableViewController reloadCurrentItem:[self secondaryAction]];
        }
    } else if (view == _menuToSelectPopup.comboView && view != nil) {
        [_sequenceTableViewController reloadCurrentItem:[self secondaryAction]];
    } else if (view == _settingToTogglePopup.comboView && view != nil) {
        [_sequenceTableViewController reloadCurrentItem:[self secondaryAction]];
    }
    [self updateError];
}

- (void)updateSyntaxErrorsForCopyMode {
    iTermVimKeyParser *parser = [[iTermVimKeyParser alloc] initWithString:_parameter.stringValue];
    NSError *error = nil;
    [parser eventsWithError:&error];
    if (error) {
        self.error = error.localizedDescription;
    } else {
        self.error = nil;
    }
}

- (void)setError:(NSString *)errorString {
    if (!errorString) {
        _errorLabel.hidden = YES;

        NSRect frame = _parameter.frame;
        const CGFloat maxY = NSMaxY(_parameter.frame);
        frame.origin.y = NSMinY(_errorLabel.frame);
        frame.size.height = maxY - NSMinY(frame);
        _parameter.frame = frame;
    } else {
        _errorLabel.stringValue = errorString;
        _errorLabel.hidden = NO;

        NSRect frame = _parameter.frame;
        const CGFloat maxY = NSMaxY(_parameter.frame);
        frame.origin.y = NSMaxY(_errorLabel.frame) + 4;
        frame.size.height = maxY - NSMinY(frame);
        _parameter.frame = frame;
    }
}
#pragma mark - NSTextEditing

- (void)controlTextDidChange:(NSNotification *)notification {
    _okButton.enabled = [self shouldEnableOK];
    if (!_secondaryComboViewContainer.isHidden) {
        [_sequenceTableViewController reloadCurrentItem:[self secondaryAction]];
    }
    [self updateError];
}

- (void)updateError {
    if (_secondaryComboViewContainer.isHidden) {
        const KEY_ACTION action = _comboView.selectedTag;
        if (action == KEY_ACTION_COPY_MODE) {
            [self updateSyntaxErrorsForCopyMode];
        } else {
            self.error = nil;
        }
    } else {
        const KEY_ACTION action = _secondaryComboView.selectedTag;
        if (action == KEY_ACTION_COPY_MODE) {
            [self updateSyntaxErrorsForCopyMode];
        } else {
            self.error = nil;
        }
    }
}

#pragma mark - iTermKeyActionSequenceTableViewControllerDelegate

- (void)keyActionSequenceTableViewController:(iTermKeyActionSequenceTableViewController *)sender
                          selectionDidChange:(iTermKeyBindingAction *)action {
    [self updateViewsAnimated:NO secondary:YES];
    [self loadParameter:action.parameter
                 action:action.keyAction
              applyMode:action.applyMode
              secondary:YES];
}

- (void)keyActionSequenceTableViewControllerDidChange:(iTermKeyActionSequenceTableViewController *)sender
                                              actions:(NSArray<iTermKeyBindingAction *> * _Nonnull)actions {
    if (sender.hasSelection) {
        iTermKeyBindingAction *action = sender.selectedItem;
        [self loadParameter:action.parameter
                     action:action.keyAction
                  applyMode:_applyMode
                  secondary:YES];
    } else {
        [self updateViewsAnimated:NO secondary:YES];
    }
}

#pragma mark - iTermPasteSpecialViewControllerDelegate

- (void)pasteSpecialViewSpeedDidChange {
    [self parameterDidChange:nil];
}

- (void)pasteSpecialTransformDidChange {
    [self parameterDidChange:nil];
}

@end
