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
                _parameterPlaceholder = ITLocalize(@"EditKeyActionWindowController_Placeholder_TextForComposer", @"Text for composer",@"Placeholder text in initWithTag:(int)tag");
                break;

            case KEY_ACTION_HEX_CODE:
                _parameterHidden = NO;
                _parameterPlaceholder = ITLocalize(@"EditKeyActionWindowController_Placeholder_Ex0x7f0x20", @"ex: 0x7f 0x20",@"Placeholder text in initWithTag:(int)tag");
                _applyHidden = NO;
                break;

            case KEY_ACTION_VIM_TEXT:
            case KEY_ACTION_VIM_TEXT_NO_BROADCAST:
                _parameterHidden = NO;
                _helpString = ITLocalize(@"EditKeyActionWindowController_Facing_SpecialCharactersAreN1To3", @"Special characters are:\n* \\<1-to-3-digit octal>\n* \\x<1 or 2 digit hex>\n* \\u<4 digit hex>\n* \\b for backspace\n* \\e for esc\n* \\f for formfeed\n* \\n for newline and \\r for return\n* \\t for tab\n* \\\\ and \\\" for literal \\ and \"\n* <C-x> for control key\n* <M-x> for meta key.", @"Help text listing special characters supported by key-action parameters");
                _parameterPlaceholder = ITLocalize(@"EditKeyActionWindowController_Placeholder_EnterValueToSendClickHelpButton", @"Enter value to send. Click help button for special characters.",@"Placeholder text in initWithTag:(int)tag");
                _applyHidden = NO;
                break;

            case KEY_ACTION_TEXT:
                _parameterHidden = NO;
                _parameterPlaceholder = ITLocalize(@"EditKeyActionWindowController_Placeholder_EnterValueToSend", @"Enter value to send",@"Placeholder text in initWithTag:(int)tag");
                _applyHidden = NO;
                break;

            case KEY_ACTION_RUN_COPROCESS:
                _parameterHidden = NO;
                _parameterPlaceholder = ITLocalize(@"EditKeyActionWindowController_Placeholder_EnterCommandToRun", @"Enter command to run",@"Placeholder text in initWithTag:(int)tag");
                _applyHidden = NO;
                break;

            case KEY_ACTION_SEND_TMUX_COMMAND:
                _parameterHidden = NO;
                _parameterPlaceholder = ITLocalize(@"EditKeyActionWindowController_Placeholder_EnterTmuxCommand", @"Enter tmux command",@"Placeholder text in initWithTag:(int)tag");
                break;

            case KEY_ACTION_SELECT_MENU_ITEM:
                _parameterPlaceholder = ITLocalize(@"EditKeyActionWindowController_Placeholder_EnterNameOfMenuItem", @"Enter name of menu item",@"Placeholder text in initWithTag:(int)tag");
                _menuToSelectPopupHidden = NO;
                _parameterValue = @"";
                break;

            case KEY_ACTION_ESCAPE_SEQUENCE:
                _parameterHidden = NO;
                _parameterPlaceholder = ITLocalize(@"EditKeyActionWindowController_Placeholder_CharactersToSend", @"characters to send",@"Placeholder text in initWithTag:(int)tag");
                _parameterLabelHidden = NO;
                _parameterLabel = ITLocalize(@"EditKeyActionWindowController_Esc", @"Esc+", @"Label text in initWithTag:");
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
                _helpString = ITLocalize(@"EditKeyActionWindowController_Facing_ThisActionLetsYouExemptAKeystroke", @"This action lets you exempt a keystroke from modifier remapping. For example, if you remap ⌘ to ⌥ but you want ⌘-Tab to work as though ⌘ were unmapped just for that keystroke, you would use this action and set the keyboard shortcut to ⌘-Tab", @"Text shown in initWithTag");
                _parameterValue = @"";
                break;

            case KEY_ACTION_REMAP_LOCALLY:
                _shortcutFieldDisableKeyRemapping = YES;
                _parameterValue = @"";
                _helpString = ITLocalize(@"EditKeyActionWindowController_Facing_ThisActionAppliesModifierRemappingButPrevents", @"This action applies modifier remapping but prevents other programs from seeing the keystroke. For example, if you've swapped ⌘ and ^ and want physical ^-tab to switch tabs in iTerm2 instead of triggering the app switcher: bind ^-tab to this action. The system won't see the remapped ⌘-tab (so no app switcher), but iTerm2 receives it and can switch tabs.", @"Text shown in initWithTag");
                _parameterValue = @"";
                break;

            case KEY_ACTION_BYPASS:
                _helpString = ITLocalize(@"EditKeyActionWindowController_Facing_PreventsTheKeystrokeFromBeingSentTo", @"Prevents the keystroke from being sent to the terminal while allowing macOS to handle it normally. For example, if F1 triggers a  macOS Shortcut, binding F1 to Bypass Terminal stops it from sending a control sequence to the terminal but still lets the system shortcut work.", @"Text shown in initWithTag");
                break;

            case KEY_ACTION_IGNORE:
                _helpString = ITLocalize(@"EditKeyActionWindowController_Facing_PreventsTheKeystrokeFromHavingAnyEffect", @"Prevents the keystroke from having any effect within iTerm2. Modifier remapping remains unaffected.", @"Text shown in initWithTag:: Prevents the keystroke from having any effect within iTerm2. Modifier remapping remains unaffected.");
                break;

            case KEY_ACTION_NEXT_MRU_TAB:
                _parameterValue = @"";
                _helpString = ITLocalize(@"EditKeyActionWindowController_Facing_SwitchesTabsInMostRecentlyUsedOrder", @"Switches tabs in most-recently-used order, like ⌘-Tab in macOS. Hold a modifier and tap repeatedly to walk back through tab history; release the modifier to commit your selection. A single tap with no modifier held jumps to the previously-selected tab, so binding this to a plain key acts as a toggle between the two most recent tabs.", @"Text shown in initWithTag");
                break;

            case KEY_ACTION_PREVIOUS_MRU_TAB:
                _parameterValue = @"";
                _helpString = ITLocalize(@"EditKeyActionWindowController_Facing_SwitchesTabsInReverseMostRecentlyUsed", @"Switches tabs in reverse most-recently-used order. Hold a modifier and tap repeatedly to walk forward through tab history (oldest first); release the modifier to commit your selection. A single tap with no modifier held jumps to the least-recently-used tab.", @"Text shown in initWithTag");
                break;

            case KEY_ACTION_FIND_REGEX:
                _parameterHidden = NO;
                _parameterPlaceholder = ITLocalize(@"EditKeyActionWindowController_Placeholder_RegularExpression", @"Regular Expression",@"Placeholder text in initWithTag:(int)tag");
                _applyHidden = NO;
                break;

            case KEY_ACTION_COPY_MODE:
                _parameterHidden = NO;
                _parameterPlaceholder = ITLocalize(@"EditKeyActionWindowController_Placeholder_CopyModeCommands", @"Copy Mode Commands",@"Placeholder text in initWithTag:(int)tag");
                _applyHidden = NO;
                _helpString = ITLocalize(@"EditKeyActionWindowController_Facing_EnterCopyModeCommandsToMoveCursor", @"Enter copy mode commands to move cursor, toggle selection, and so on. This key binding enters Copy Mode and then acts as though you had pressed the keys listed here. [See a list of all the commands](https://iterm2.com/documentation-copymode.html). Use vim syntax for control, option, and function keys (e.g., `<C-x>` or `<Up>`.", @"Text shown in initWithTag");
                break;

            case KEY_ACTION_TOGGLE_SETTING:
                _parameterPlaceholder = ITLocalize(@"EditKeyActionWindowController_Placeholder_EnterNameOfMenuItem", @"Enter name of menu item",@"Placeholder text in initWithTag:(int)tag");
                _settingToTogglePopupHidden = NO;
                _parameterValue = @"";
                break;

            case KEY_ACTION_INVOKE_SCRIPT_FUNCTION:
                _parameterHidden = NO;
                _parameterPlaceholder = ITLocalize(@"EditKeyActionWindowController_Placeholder_FunctionCall", @"Function Call",@"Placeholder text in initWithTag:(int)tag");
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
                _parameterPlaceholder = ITLocalize(@"EditKeyActionWindowController_Placeholder_EnterInterpolatedStringEvaluatedInSessionContext", @"Enter interpolated string (evaluated in session context)",@"Placeholder text in initWithTag:(int)tag");
                if (interpolatedStringDelegate) {
                    _parameterDelegate = interpolatedStringDelegate;
                } else {
                    _parameterDelegate =
                    [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:context]
                                                                       passthrough:nil
                                                                     functionsOnly:NO];
                }
                _helpString = ITLocalize(@"EditKeyActionWindowController_Facing_YouCanUseThisToCopyInformation", @"You can use this to copy information about the current session to the clipboard. [Learn more about interpolated strings](https://iterm2.com/documentation-scripting-fundamentals.html)", @"Text shown in initWithTag");
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
        [[iTermSearchableComboViewGroup alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_General", @"General", @"Label text in groupsForPrimary:") items:[@[
            primary ? [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_Ignore", @"Ignore", @"Label text in groupsForPrimary:") tag:KEY_ACTION_IGNORE] : [NSNull null],
            primary ? [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_BypassTerminal", @"Bypass Terminal", @"Label text in groupsForPrimary:") tag:KEY_ACTION_BYPASS] : [NSNull null],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SelectMenuItem", @"Select Menu Item...", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SELECT_MENU_ITEM],
        ] arrayByRemovingNulls]]
    ];
    if (self.mode == iTermEditKeyActionWindowControllerModeKeyboardShortcut) {
        groups = [groups arrayByAddingObjectsFromArray:[@[
            primary ? [[iTermSearchableComboViewGroup alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_ModifierRemapping", @"Modifier Remapping", @"Label text in groupsForPrimary:") items:@[
                [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_DoNotRemapModifiers", @"Do Not Remap Modifiers", @"Label text in groupsForPrimary:") tag:KEY_ACTION_DO_NOT_REMAP_MODIFIERS],
                [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_RemapModifiersInITerm2Only", @"Remap Modifiers in iTerm2 Only", @"Label text in groupsForPrimary:") tag:KEY_ACTION_REMAP_LOCALLY],
            ]] : [NSNull null],
            [[iTermSearchableComboViewGroup alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_RecentTabs", @"Recent Tabs", @"Label text in groupsForPrimary:") items:@[
                [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_CycleTabsForward", @"Cycle Tabs Forward", @"Label text in groupsForPrimary:") tag:KEY_ACTION_NEXT_MRU_TAB],
                [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_CycleTabsBackward", @"Cycle Tabs Backward", @"Label text in groupsForPrimary:") tag:KEY_ACTION_PREVIOUS_MRU_TAB],
            ]],
        ] arrayByRemovingNulls]];
    }

    const BOOL hideTerminalOnlyItems = (_profileType & ProfileTypeTerminal) == 0;
    groups = [groups arrayByAddingObjectsFromArray:[@[
        [[iTermSearchableComboViewGroup alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_Miscellaneous", @"Miscellaneous", @"Label text in groupsForPrimary:") items:[@[
            hideTerminalOnlyItems ? [NSNull null] : [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_RunCoprocess", @"Run Coprocess", @"Label text in groupsForPrimary:") tag:KEY_ACTION_RUN_COPROCESS],
            hideTerminalOnlyItems ? [NSNull null] : [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_StartInstantReplay", @"Start Instant Replay", @"Label text in groupsForPrimary:") tag:KEY_ACTION_IR_BACKWARD],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_Undo", @"Undo", @"Label text in groupsForPrimary:") tag:KEY_ACTION_UNDO],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SendTmuxCommand", @"Send tmux Command", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SEND_TMUX_COMMAND],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_AlertOnNextMark", @"Alert on Next Mark", @"Label text in groupsForPrimary:") tag:KEY_ACTION_ALERT_ON_NEXT_MARK],
        ] arrayByRemovingNulls]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_NewTabOrWindow", @"New Tab or Window", @"Label text in groupsForPrimary:") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_NewWindowWithProfile", @"New Window with Profile", @"Label text in groupsForPrimary:") tag:KEY_ACTION_NEW_WINDOW_WITH_PROFILE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_NewTabWithProfile", @"New Tab with Profile", @"Label text in groupsForPrimary:") tag:KEY_ACTION_NEW_TAB_WITH_PROFILE],
        [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_DuplicateTab", @"Duplicate Tab", @"Label text in groupsForPrimary:") tag:KEY_ACTION_DUPLICATE_TAB],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_Split", @"Split", @"Label text in groupsForPrimary:") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SplitHorizontallyWithProfile", @"Split Horizontally with Profile", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SplitVerticallyWithProfile", @"Split Vertically with Profile", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_Profile", @"Profile", @"Label text in groupsForPrimary:") items:[@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_ChangeProfile", @"Change Profile", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SET_PROFILE],
            hideTerminalOnlyItems ? [NSNull null] : [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_LoadColorPreset", @"Load Color Preset", @"Label text in groupsForPrimary:") tag:KEY_ACTION_LOAD_COLOR_PRESET],
        ] arrayByRemovingNulls]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_NavigateTabs", @"Navigate Tabs", @"Label text in groupsForPrimary:") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_NextTab", @"Next Tab", @"Label text in groupsForPrimary:") tag:KEY_ACTION_NEXT_SESSION],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_PreviousTab", @"Previous Tab", @"Label text in groupsForPrimary:") tag:KEY_ACTION_PREVIOUS_SESSION],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_ReorderTabs", @"Reorder Tabs", @"Label text in groupsForPrimary:") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_MoveTabLeft", @"Move Tab Left", @"Label text in groupsForPrimary:") tag:KEY_ACTION_MOVE_TAB_LEFT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_MoveTabRight", @"Move Tab Right", @"Label text in groupsForPrimary:") tag:KEY_ACTION_MOVE_TAB_RIGHT],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_NavigateWindows", @"Navigate Windows", @"Label text in groupsForPrimary:") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_NextWindow", @"Next Window", @"Label text in groupsForPrimary:") tag:KEY_ACTION_NEXT_WINDOW],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_PreviousWindow", @"Previous Window", @"Label text in groupsForPrimary:") tag:KEY_ACTION_PREVIOUS_WINDOW],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_NavigatePanes", @"Navigate Panes", @"Label text in groupsForPrimary:") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_NextPane", @"Next Pane", @"Label text in groupsForPrimary:") tag:KEY_ACTION_NEXT_PANE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_PreviousPane", @"Previous Pane", @"Label text in groupsForPrimary:") tag:KEY_ACTION_PREVIOUS_PANE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SelectSplitPaneAbove", @"Select Split Pane Above", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SELECT_PANE_ABOVE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SelectSplitPaneBelow", @"Select Split Pane Below", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SELECT_PANE_BELOW],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SelectSplitPaneOnLeft", @"Select Split Pane On Left", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SELECT_PANE_LEFT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SelectSplitPaneOnRight", @"Select Split Pane On Right", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SELECT_PANE_RIGHT],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_ResizePane", @"Resize Pane", @"Label text in groupsForPrimary:") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_DecreaseHeight", @"Decrease Height", @"Label text in groupsForPrimary:") tag:KEY_ACTION_DECREASE_HEIGHT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_IncreaseHeight", @"Increase Height", @"Label text in groupsForPrimary:") tag:KEY_ACTION_INCREASE_HEIGHT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_DecreaseWidth", @"Decrease Width", @"Label text in groupsForPrimary:") tag:KEY_ACTION_DECREASE_WIDTH],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_IncreaseWidth", @"Increase Width", @"Label text in groupsForPrimary:") tag:KEY_ACTION_INCREASE_WIDTH],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_Scroll", @"Scroll", @"Label text in groupsForPrimary:") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_ScrollToEnd", @"Scroll to End", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SCROLL_END],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_ScrollToTop", @"Scroll to Top", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SCROLL_HOME],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_ScrollOneLineDown", @"Scroll One Line Down", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SCROLL_LINE_DOWN],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_ScrollOneLineUp", @"Scroll One Line Up", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SCROLL_LINE_UP],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_ScrollOnePageDown", @"Scroll One Page Down", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SCROLL_PAGE_DOWN],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_ScrollOnePageUp", @"Scroll One Page Up", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SCROLL_PAGE_UP],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SplitPanes", @"Split Panes", @"Label text in groupsForPrimary:") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SwapWithSplitPaneAbove", @"Swap With Split Pane Above", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SWAP_PANE_ABOVE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SwapWithSplitPaneBelow", @"Swap With Split Pane Below", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SWAP_PANE_BELOW],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SwapWithSplitPaneOnLeft", @"Swap With Split Pane on Left", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SWAP_PANE_LEFT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SwapWithSplitPaneOnRight", @"Swap With Split Pane on Right", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SWAP_PANE_RIGHT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SwapWithNextPane", @"Swap With Next Pane", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SWAP_WITH_NEXT_PANE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SwapWithPreviousPane", @"Swap With Previous Pane", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SWAP_WITH_PREVIOUS_PANE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_MoveSessionToSplitPane", @"Move Session to Split Pane", @"Label text in groupsForPrimary:") tag:KEY_ACTION_MOVE_TO_SPLIT_PANE],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SendKeystrokes", @"Send Keystrokes", @"Label text in groupsForPrimary:") items:[@[
            hideTerminalOnlyItems ? [NSNull null] : [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SendHBackspace", @"Send ^H Backspace", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SEND_C_H_BACKSPACE],
            hideTerminalOnlyItems ? [NSNull null] : [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SendBackspace", @"Send ^? Backspace", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SEND_C_QM_BACKSPACE],
            hideTerminalOnlyItems ? [NSNull null] : [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SendEscapeSequence", @"Send Escape Sequence", @"Label text in groupsForPrimary:") tag:KEY_ACTION_ESCAPE_SEQUENCE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SendHexCode", @"Send Hex Code", @"Label text in groupsForPrimary:") tag:KEY_ACTION_HEX_CODE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SendText", @"Send Text", @"Label text in groupsForPrimary:") tag:KEY_ACTION_TEXT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SendTextWithVimSpecialChars", @"Send Text with “vim” Special Chars", @"Label text in groupsForPrimary:") tag:KEY_ACTION_VIM_TEXT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SendTextWithoutBroadcasting", @"Send Text without Broadcasting", @"Label text in groupsForPrimary:") tag:KEY_ACTION_VIM_TEXT_NO_BROADCAST],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_SendSnippet", @"Send Snippet", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SEND_SNIPPET],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_Compose", @"Compose…", @"Label text in groupsForPrimary:") tag:KEY_ACTION_COMPOSE],
        ] arrayByRemovingNulls]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_Search", @"Search", @"Label text in groupsForPrimary:") items:[@[
            hideTerminalOnlyItems ? [NSNull null] : [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_FindRegularExpression", @"Find Regular Expression…", @"Label text in groupsForPrimary:") tag:KEY_ACTION_FIND_REGEX],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_FindAgainDown", @"Find Again Down", @"Label text in groupsForPrimary:") tag:KEY_FIND_AGAIN_DOWN],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_FindAgainUp", @"Find Again Up", @"Label text in groupsForPrimary:") tag:KEY_FIND_AGAIN_UP],
        ] arrayByRemovingNulls]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_Pasteboard", @"Pasteboard", @"Label text in groupsForPrimary:") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_Paste", @"Paste…", @"Label text in groupsForPrimary:") tag:KEY_ACTION_PASTE_SPECIAL],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_PasteFromSelection", @"Paste from Selection…", @"Label text in groupsForPrimary:") tag:KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_CopyOrSendC", @"Copy or Send ^C", @"Label text in groupsForPrimary:") tag:KEY_ACTION_COPY_OR_SEND],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_PasteOrSendV", @"Paste or Send ^V", @"Label text in groupsForPrimary:") tag:KEY_ACTION_PASTE_OR_SEND],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_CopyInterpolatedString", @"Copy Interpolated String", @"Label text in groupsForPrimary:") tag:KEY_ACTION_COPY_INTERPOLATED_STRING],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_CopyModeCommands", @"Copy Mode Commands", @"Label text in groupsForPrimary:") tag:KEY_ACTION_COPY_MODE],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_Toggles", @"Toggles", @"Label text in groupsForPrimary:") items:[@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_ToggleFullscreen", @"Toggle Fullscreen", @"Label text in groupsForPrimary:") tag:KEY_ACTION_TOGGLE_FULLSCREEN],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_TogglePinHotkeyWindow", @"Toggle Pin Hotkey Window", @"Label text in groupsForPrimary:") tag:KEY_ACTION_TOGGLE_HOTKEY_WINDOW_PINNING],
            hideTerminalOnlyItems ? [NSNull null] : [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_ToggleMouseReporting", @"Toggle Mouse Reporting", @"Label text in groupsForPrimary:") tag:KEY_ACTION_TOGGLE_MOUSE_REPORTING],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_ToggleSetting", @"Toggle Setting", @"Label text in groupsForPrimary:") tag:KEY_ACTION_TOGGLE_SETTING],
        ] arrayByRemovingNulls]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_Selection", @"Selection", @"Label text in groupsForPrimary:") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_MoveStartOfSelectionBack", @"Move Start of Selection Back", @"Label text in groupsForPrimary:") tag:KEY_ACTION_MOVE_START_OF_SELECTION_LEFT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_MoveStartOfSelectionForward", @"Move Start of Selection Forward", @"Label text in groupsForPrimary:") tag:KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_MoveEndOfSelectionBack", @"Move End of Selection Back", @"Label text in groupsForPrimary:") tag:KEY_ACTION_MOVE_END_OF_SELECTION_LEFT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_MoveEndOfSelectionForward", @"Move End of Selection Forward", @"Label text in groupsForPrimary:") tag:KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_Scripting", @"Scripting", @"Label text in groupsForPrimary:") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_InvokeScriptFunction", @"Invoke Script Function…", @"Label text in groupsForPrimary:") tag:KEY_ACTION_INVOKE_SCRIPT_FUNCTION],
        ]],

        primary ? [[iTermSearchableComboViewGroup alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_Composition", @"Composition", @"Label text in groupsForPrimary:") items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:ITLocalize(@"EditKeyActionWindowController_Sequence", @"Sequence…", @"Label text in groupsForPrimary:") tag:KEY_ACTION_SEQUENCE],
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
            _touchBarLabel.placeholderString = ITLocalize(@"EditKeyActionWindowController_Placeholder_LabelToShowInTouchBar", @"Label to show in Touch Bar", @"Placeholder text for the Touch Bar label in windowDidLoad");
            break;
        case iTermEditKeyActionWindowControllerModeUnbound:
            _touchBarLabel.placeholderString = self.titleIsInterpolated ? ITLocalize(@"EditKeyActionWindowController_Placeholder_TitleInterpolatedString", @"Title (Interpolated String)", @"Placeholder text for an interpolated Touch Bar title in windowDidLoad") : ITLocalize(@"EditKeyActionWindowController_Placeholder_Title", @"Title", @"Placeholder text for the Touch Bar title in windowDidLoad");
            break;
    }

    _comboView = [[iTermSearchableComboView alloc] initWithGroups:[self groupsForPrimary:YES]
                                                     defaultTitle:ITLocalize(@"EditKeyActionWindowController_SelectAction", @"Select Action…", @"Title in windowDidLoad")];
    [_comboViewContainer addSubview:_comboView];
    _comboView.frame = _comboViewContainer.bounds;
    _comboView.delegate = self;

    _secondaryComboView = [[iTermSearchableComboView alloc] initWithGroups:[self groupsForPrimary:NO]
                                                              defaultTitle:ITLocalize(@"EditKeyActionWindowController_SelectAction", @"Select Action…", @"Title in windowDidLoad")];
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
    [_applyButton addItemWithTitle:ITLocalize(@"EditKeyActionWindowController_Menu_ApplyToCurrentSession", @"Apply to current session", @"Button title in windowDidLoad")];
    _applyButton.menu.itemArray.lastObject.tag = iTermActionApplyModeCurrentSession;
    [_applyButton addItemWithTitle:ITLocalize(@"EditKeyActionWindowController_Menu_ApplyToAllSessions", @"Apply to all sessions", @"Button title in windowDidLoad")];
    _applyButton.menu.itemArray.lastObject.tag = iTermActionApplyModeAllSessions;
    [_applyButton addItemWithTitle:ITLocalize(@"EditKeyActionWindowController_Menu_ApplyToAllSessionsExceptCurrent", @"Apply to all sessions except current", @"Button title in windowDidLoad")];
    _applyButton.menu.itemArray.lastObject.tag = iTermActionApplyModeUnfocusedSessions;
    [_applyButton addItemWithTitle:ITLocalize(@"EditKeyActionWindowController_Menu_ApplyToAllSessionsInWindow", @"Apply to all sessions in window", @"Button title in windowDidLoad")];
    _applyButton.menu.itemArray.lastObject.tag = iTermActionApplyModeAllInWindow;
    [_applyButton addItemWithTitle:ITLocalize(@"EditKeyActionWindowController_Menu_ApplyToAllSessionsInTab", @"Apply to all sessions in tab", @"Button title in windowDidLoad")];
    _applyButton.menu.itemArray.lastObject.tag = iTermActionApplyModeAllInTab;
    [_applyButton addItemWithTitle:ITLocalize(@"EditKeyActionWindowController_Menu_ApplyToBroadcastedToSessions", @"Apply to broadcasted-to sessions", @"Button title in windowDidLoad")];
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
        if (parts.count < 2) {
            [_menuToSelectPopup selectItemWithTitle:parameterValue ?: @""];
        } else {
            if (![_menuToSelectPopup selectItemWithIdentifier:parts[1]]) {
                [_menuToSelectPopup selectItemWithTitle:parts.firstObject];
            }
        }
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
            _keyboardShortcutLabel.stringValue = ITLocalize(@"EditKeyActionWindowController_Title", @"Title", @"Label text in updateViewsAnimated:");
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
            _keyboardShortcutLabel.stringValue = ITLocalize(@"EditKeyActionWindowController_TouchBarLabel", @"Touch Bar Label", @"Label text in updateViewsAnimated:");
            _touchBarLabel.delegate = self;
            _touchBarLabel.hidden = NO;
            _shortcutField.hidden = YES;
            break;
        case iTermEditKeyActionWindowControllerModeKeyboardShortcut:
            _keyboardShortcutLabel.stringValue = ITLocalize(@"EditKeyActionWindowController_KeyboardShortcut", @"Keyboard Shortcut:", @"Label text in updateViewsAnimated:");
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
            if (_menuToSelectPopup.selectedIdentifier.length) {
              return [NSString stringWithFormat:@"%@\n%@",
                      _menuToSelectPopup.selectedTitle, _menuToSelectPopup.selectedIdentifier ?: @""];
            } else {
                return _menuToSelectPopup.selectedTitle;
            }
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
