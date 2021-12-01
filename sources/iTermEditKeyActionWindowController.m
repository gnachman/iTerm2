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
#import "RegexKitLite.h"

#import <SearchableComboListView/SearchableComboListView-Swift.h>

const CGFloat sideMarginWidth = 20;

@interface iTermEditKeyActionWindowController () <
    iTermSearchableComboViewDelegate,
    iTermShortcutInputViewDelegate,
    NSTextFieldDelegate>

@property(nonatomic, assign) BOOL ok;

@end

@implementation iTermEditKeyActionWindowController {
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
    IBOutlet NSTextField *_profileLabel;
    IBOutlet NSTextField *_colorPresetsLabel;
    IBOutlet NSPopUpButton *_colorPresetsPopup;
    IBOutlet NSPopUpButton *_snippetsPopup;
    IBOutlet NSView *_pasteSpecialViewContainer;
    IBOutlet NSButton *_okButton;

    iTermPasteSpecialViewController *_pasteSpecialViewController;
    iTermFunctionCallTextFieldDelegate *_functionCallDelegate;
    iTermFunctionCallTextFieldDelegate *_labelDelegate;
}

- (instancetype)initWithContext:(iTermVariablesSuggestionContext)context
                           mode:(iTermEditKeyActionWindowControllerMode)mode {
    self = [super initWithWindowNibName:@"iTermEditKeyActionWindowController"];
    if (self) {
        _suggestContext = context;
        _mode = mode;
    }
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];

    NSArray<iTermSearchableComboViewGroup *> *groups = @[
        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"General" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Ignore" tag:KEY_ACTION_IGNORE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Select Menu Item..." tag:KEY_ACTION_SELECT_MENU_ITEM],
        ]],
    ];
    if (self.mode == iTermEditKeyActionWindowControllerModeKeyboardShortcut) {
        groups = [groups arrayByAddingObjectsFromArray:@[
            [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Modifier Remapping" items:@[
                [[iTermSearchableComboViewItem alloc] initWithLabel:@"Do Not Remap Modifiers" tag:KEY_ACTION_DO_NOT_REMAP_MODIFIERS],
                [[iTermSearchableComboViewItem alloc] initWithLabel:@"Remap Modifiers in iTerm2 Only" tag:KEY_ACTION_REMAP_LOCALLY],
            ]],
            [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Cycle" items:@[
                [[iTermSearchableComboViewItem alloc] initWithLabel:@"Cycle Tabs Forward" tag:KEY_ACTION_NEXT_MRU_TAB],
                [[iTermSearchableComboViewItem alloc] initWithLabel:@"Cycle Tabs Backward" tag:KEY_ACTION_PREVIOUS_MRU_TAB],
            ]],
        ]];
    }

    groups = [groups arrayByAddingObjectsFromArray:@[
        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Miscellaneous" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Run Coprocess" tag:KEY_ACTION_RUN_COPROCESS],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Start Instant Replay" tag:KEY_ACTION_IR_BACKWARD],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Undo" tag:KEY_ACTION_UNDO],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"New Tab or Window" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"New Window with Profile" tag:KEY_ACTION_NEW_WINDOW_WITH_PROFILE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"New Tab with Profile" tag:KEY_ACTION_NEW_TAB_WITH_PROFILE],
        [[iTermSearchableComboViewItem alloc] initWithLabel:@"Duplicate Tab" tag:KEY_ACTION_DUPLICATE_TAB],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Split" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Split Horizontally with Profile" tag:KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Split Vertically with Profile" tag:KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Profile" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Change Profile" tag:KEY_ACTION_SET_PROFILE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Load Color Preset" tag:KEY_ACTION_LOAD_COLOR_PRESET],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Navigate Tabs" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Next Tab" tag:KEY_ACTION_NEXT_SESSION],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Previous Tab" tag:KEY_ACTION_PREVIOUS_SESSION],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Reorder Tabs" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Move Tab Left" tag:KEY_ACTION_MOVE_TAB_LEFT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Move Tab Right" tag:KEY_ACTION_MOVE_TAB_RIGHT],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Navigate Windows" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Next Window" tag:KEY_ACTION_NEXT_WINDOW],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Previous Window" tag:KEY_ACTION_PREVIOUS_WINDOW],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Navigate Panes" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Next Pane" tag:KEY_ACTION_NEXT_PANE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Previous Pane" tag:KEY_ACTION_PREVIOUS_PANE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Select Split Pane Above" tag:KEY_ACTION_SELECT_PANE_ABOVE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Select Split Pane Below" tag:KEY_ACTION_SELECT_PANE_BELOW],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Select Split Pane On Left" tag:KEY_ACTION_SELECT_PANE_LEFT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Select Split Pane On Right" tag:KEY_ACTION_SELECT_PANE_RIGHT],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Resize Pane" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Decrease Height" tag:KEY_ACTION_DECREASE_HEIGHT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Increase Height" tag:KEY_ACTION_INCREASE_HEIGHT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Decrease Width" tag:KEY_ACTION_DECREASE_WIDTH],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Increase Width" tag:KEY_ACTION_INCREASE_WIDTH],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Scroll" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Scroll to End" tag:KEY_ACTION_SCROLL_END],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Scroll to Top" tag:KEY_ACTION_SCROLL_HOME],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Scroll One Line Down" tag:KEY_ACTION_SCROLL_LINE_DOWN],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Scroll One Line Up" tag:KEY_ACTION_SCROLL_LINE_UP],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Scroll One Page Down" tag:KEY_ACTION_SCROLL_PAGE_DOWN],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Scroll One Page Up" tag:KEY_ACTION_SCROLL_PAGE_UP],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Split Panes" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Swap With Split Pane Above" tag:KEY_ACTION_SWAP_PANE_ABOVE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Swap With Split Pane Below" tag:KEY_ACTION_SWAP_PANE_BELOW],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Swap With Split Pane on Left" tag:KEY_ACTION_SWAP_PANE_LEFT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Swap With Split Pane on Right" tag:KEY_ACTION_SWAP_PANE_RIGHT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Move Session to Split Pane" tag:KEY_ACTION_MOVE_TO_SPLIT_PANE],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Send Keystrokes" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Send ^H Backspace" tag:KEY_ACTION_SEND_C_H_BACKSPACE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Send ^? Backspace" tag:KEY_ACTION_SEND_C_QM_BACKSPACE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Send Escape Sequence" tag:KEY_ACTION_ESCAPE_SEQUENCE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Send Hex Code" tag:KEY_ACTION_HEX_CODE],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Send Text" tag:KEY_ACTION_TEXT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Send Text with “vim” Special Chars" tag:KEY_ACTION_VIM_TEXT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Send Snippet" tag:KEY_ACTION_SEND_SNIPPET],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Compose…" tag:KEY_ACTION_COMPOSE],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Search" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Find Regular Expression…" tag:KEY_ACTION_FIND_REGEX],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Find Again Down" tag:KEY_FIND_AGAIN_DOWN],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Find Again Up" tag:KEY_FIND_AGAIN_UP],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Pasteboard" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Paste…" tag:KEY_ACTION_PASTE_SPECIAL],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Paste from Selection…" tag:KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Toggles" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Toggle Fullscreen" tag:KEY_ACTION_TOGGLE_FULLSCREEN],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Toggle Pin Hotkey Window" tag:KEY_ACTION_TOGGLE_HOTKEY_WINDOW_PINNING],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Toggle Mouse Reporting" tag:KEY_ACTION_TOGGLE_MOUSE_REPORTING],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Selection" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Move Start of Selection Back" tag:KEY_ACTION_MOVE_START_OF_SELECTION_LEFT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Move Start of Selection Forward" tag:KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Move End of Selection Back" tag:KEY_ACTION_MOVE_END_OF_SELECTION_LEFT],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Move End of Selection Forward" tag:KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Scripting" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Invoke Script Function…" tag:KEY_ACTION_INVOKE_SCRIPT_FUNCTION],
        ]],
    ]];

    switch (self.mode) {
        case iTermEditKeyActionWindowControllerModeKeyboardShortcut:
            break;
        case iTermEditKeyActionWindowControllerModeTouchBarItem:
            _touchBarLabel.placeholderString = @"Label to show in Touch Bar";
            break;
        case iTermEditKeyActionWindowControllerModeUnbound:
            _touchBarLabel.placeholderString = self.titleIsInterpolated ? @"Title (Interpolated String)" : @"Title";
            break;
    }

    _comboView = [[iTermSearchableComboView alloc] initWithGroups:groups defaultTitle:@"Select Action…"];
    [_comboViewContainer addSubview:_comboView];
    _comboView.frame = _comboViewContainer.bounds;
    _comboView.delegate = self;

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
    _parameter.stringValue = self.parameterValue ?: @"";
    if (self.action == KEY_ACTION_SELECT_MENU_ITEM) {
        [_menuToSelectPopup reloadData];
        NSArray *parts = [self.parameterValue componentsSeparatedByString:@"\n"];
        if (parts.count < 2) {
            [_menuToSelectPopup selectItemWithTitle:self.parameterValue];
        } else {
            if (![_menuToSelectPopup selectItemWithIdentifier:parts[1]]) {
                [_menuToSelectPopup selectItemWithTitle:parts.firstObject];
            }
        }
    }

    _pasteSpecialViewController = [[iTermPasteSpecialViewController alloc] init];
    [_pasteSpecialViewController view];

    [self updateViewsAnimated:NO];
    if (!_profilePopup.isHidden) {
        [_profilePopup populateWithProfilesSelectingGuid:self.parameterValue];
    }
    if (!_colorPresetsPopup.isHidden) {
        [_colorPresetsPopup loadColorPresetsSelecting:self.parameterValue];
    }
    if (!_snippetsPopup.isHidden) {
        [_snippetsPopup populateWithSnippetsSelectingActionKey:self.parameterValue];
    }
    if (!_selectionMovementUnit.isHidden) {
        [_selectionMovementUnit selectItemWithTag:[self.parameterValue integerValue]];
    }

    if (self.action == KEY_ACTION_PASTE_SPECIAL ||
        self.action == KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION) {
        [_pasteSpecialViewController loadSettingsFromString:self.parameterValue];
    } else {
        // Set a few defaults; otherwise everything is reasonable.
        _pasteSpecialViewController.numberOfSpacesPerTab = [iTermPreferences intForKey:kPreferenceKeyPasteSpecialSpacesPerTab];
        _pasteSpecialViewController.shouldRemoveNewlines = NO;
        _pasteSpecialViewController.shouldBase64Encode = NO;
        _pasteSpecialViewController.shouldWaitForPrompt = NO;
        _pasteSpecialViewController.shouldEscapeShellCharsWithBackslash = NO;
    }
    _pasteSpecialViewController.view.frame = _pasteSpecialViewController.view.bounds;
    NSRect theFrame = _pasteSpecialViewContainer.frame;
    CGFloat originalHeight = theFrame.size.height;
    theFrame.size = _pasteSpecialViewController.view.bounds.size;
    theFrame.origin.y -= (theFrame.size.height - originalHeight);
    _pasteSpecialViewContainer.frame = theFrame;
    [_pasteSpecialViewContainer addSubview:_pasteSpecialViewController.view];
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

- (void)updateViewsAnimated:(BOOL)animated {
    int tag = _comboView.selectedTag;
    switch (self.mode) {
        case iTermEditKeyActionWindowControllerModeUnbound:
            _keyboardShortcutLabel.stringValue = @"Title";
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
            _keyboardShortcutLabel.stringValue = @"Touch Bar Label";
            _touchBarLabel.delegate = self;
            _touchBarLabel.hidden = NO;
            _shortcutField.hidden = YES;
            break;
        case iTermEditKeyActionWindowControllerModeKeyboardShortcut:
            _keyboardShortcutLabel.stringValue = @"Keyboard Shortcut";
            _touchBarLabel.hidden = YES;
            _shortcutField.hidden = NO;
            break;
    }

    BOOL parameterHidden = YES;
    BOOL parameterLabelHidden = YES;
    BOOL profilePopupHidden = YES;
    BOOL selectionMovementUnitHidden = YES;
    BOOL profileLabelHidden = YES;
    BOOL menuToSelectPopupHidden = YES;
    BOOL shortcutFieldDisableKeyRemapping = NO;
    BOOL colorPresetsLabelHidden = YES;
    BOOL colorPresetsPopupHidden = YES;
    BOOL pasteSpecialHidden = YES;
    BOOL snippetsHidden = YES;
    id<NSTextFieldDelegate> parameterDelegate = nil;

    switch (tag) {
        case KEY_ACTION_SEND_SNIPPET:
            snippetsHidden = NO;
            break;
        case KEY_ACTION_COMPOSE:
            parameterHidden = NO;
            [[_parameter cell] setPlaceholderString:@"Text for composer"];
            break;

        case KEY_ACTION_HEX_CODE:
            parameterHidden = NO;
            [[_parameter cell] setPlaceholderString:@"ex: 0x7f 0x20"];
            break;

        case KEY_ACTION_VIM_TEXT:
        case KEY_ACTION_TEXT:
            parameterHidden = NO;
            [[_parameter cell] setPlaceholderString:@"Enter value to send"];
            break;

        case KEY_ACTION_RUN_COPROCESS:
            parameterHidden = NO;
            [[_parameter cell] setPlaceholderString:@"Enter command to run"];
            break;

        case KEY_ACTION_SELECT_MENU_ITEM:
            [[_parameter cell] setPlaceholderString:@"Enter name of menu item"];
            menuToSelectPopupHidden = NO;
            break;

        case KEY_ACTION_ESCAPE_SEQUENCE:
            parameterHidden = NO;
            [[_parameter cell] setPlaceholderString:@"characters to send"];
            parameterLabelHidden = NO;
            [_parameterLabel setStringValue:@"Esc+"];
            break;

        case KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE:
        case KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE:
        case KEY_ACTION_NEW_TAB_WITH_PROFILE:
        case KEY_ACTION_NEW_WINDOW_WITH_PROFILE:
        case KEY_ACTION_SET_PROFILE:
            profileLabelHidden = NO;
            profilePopupHidden = NO;
            break;

        case KEY_ACTION_LOAD_COLOR_PRESET:
            colorPresetsLabelHidden = NO;
            colorPresetsPopupHidden = NO;
            break;

        case KEY_ACTION_DO_NOT_REMAP_MODIFIERS:
        case KEY_ACTION_REMAP_LOCALLY:
            shortcutFieldDisableKeyRemapping = YES;
            [_parameter setStringValue:@""];
            parameterLabelHidden = NO;
            [_parameterLabel setStringValue:@"Modifier remapping disabled: type the actual key combo you want to affect."];
            break;

        case KEY_ACTION_FIND_REGEX:
            parameterHidden = NO;
            [[_parameter cell] setPlaceholderString:@"Regular Expression"];
            break;

        case KEY_ACTION_INVOKE_SCRIPT_FUNCTION:
            parameterHidden = NO;
            [[_parameter cell] setPlaceholderString:@"Function Call"];
            if (!_functionCallDelegate) {
                _functionCallDelegate = [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:_suggestContext]
                                                                                           passthrough:nil
                                                                                         functionsOnly:YES];
            }
            parameterDelegate = _functionCallDelegate;
            break;

        case KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION:
        case KEY_ACTION_PASTE_SPECIAL:
            pasteSpecialHidden = NO;
            break;

        case KEY_ACTION_MOVE_END_OF_SELECTION_LEFT:
        case KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT:
        case KEY_ACTION_MOVE_START_OF_SELECTION_LEFT:
        case KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT:
            [_parameter setStringValue:@""];
            selectionMovementUnitHidden = NO;
            break;

        default:
            [_parameter setStringValue:@""];
            break;
    }

    [_parameter setHidden:parameterHidden];
    [_parameterLabel setHidden:parameterLabelHidden];
    [_profilePopup setHidden:profilePopupHidden];
    [_selectionMovementUnit setHidden:selectionMovementUnitHidden];
    [_profileLabel setHidden:profileLabelHidden];
    [_menuToSelectPopup setHidden:menuToSelectPopupHidden];
    _shortcutField.disableKeyRemapping = shortcutFieldDisableKeyRemapping;
    [_colorPresetsLabel setHidden:colorPresetsLabelHidden];
    [_colorPresetsPopup setHidden:colorPresetsPopupHidden];
    [_snippetsPopup setHidden:snippetsHidden];
    [self setPasteSpecialHidden:pasteSpecialHidden];
    _parameter.delegate = parameterDelegate;
    if (!parameterDelegate && _functionCallDelegate) {
        _functionCallDelegate = nil;
    }

    [self updateFrameAnimated:animated];
}

- (BOOL)anyAccessoryVisible {
    return (!_parameter.isHidden ||
            !_profilePopup.isHidden ||
            !_menuToSelectPopup.isHidden ||
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
    return NSMakeSize(self.desiredWidthExcludingMargins + sideMarginWidth * 2,
                      self.desiredHeight);
}

- (CGFloat)desiredWidthExcludingMargins {
    const CGFloat normalWidthExcludingMargins = 402;
    if (!_pasteSpecialViewContainer.hidden) {
        return MAX(normalWidthExcludingMargins,
                   _pasteSpecialViewController.view.frame.size.width);
    }
    if (!_parameter.isHidden) {
        return NSMaxX(_parameter.frame) - sideMarginWidth;
    }
    return normalWidthExcludingMargins;
}

- (CGFloat)desiredHeight {
    const CGFloat heightExcludingAccessory = 126;
    return heightExcludingAccessory + [self accessoryHeight];
}

- (CGFloat)accessoryHeight {
    const CGFloat basicAccessoryHeight = 31;
    if (![self anyAccessoryVisible]) {
        return 0;
    }
    if (!_parameter.isHidden) {
        return NSHeight(_parameter.frame);
    }
    if (!_pasteSpecialViewContainer.isHidden) {
        return _pasteSpecialViewController.view.frame.size.height;
    }
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

    self.action = _comboView.selectedTag;

    switch (self.action) {
        case KEY_ACTION_SELECT_MENU_ITEM:
            if (_menuToSelectPopup.selectedIdentifier.length) {
              self.parameterValue = [NSString stringWithFormat:@"%@\n%@", _menuToSelectPopup.selectedTitle, _menuToSelectPopup.selectedIdentifier ?: @""];
            } else {
                self.parameterValue = _menuToSelectPopup.selectedTitle;
            }
            break;

        case KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE:
        case KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE:
        case KEY_ACTION_NEW_TAB_WITH_PROFILE:
        case KEY_ACTION_NEW_WINDOW_WITH_PROFILE:
        case KEY_ACTION_SET_PROFILE:
            self.parameterValue = [[_profilePopup selectedItem] representedObject];
            break;

        case KEY_ACTION_LOAD_COLOR_PRESET:
            self.parameterValue = [[_colorPresetsPopup selectedItem] title];
            break;

        case KEY_ACTION_SEND_SNIPPET:
            self.parameterValue = [[_snippetsPopup selectedItem] representedObject];
            break;

        case KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION:
        case KEY_ACTION_PASTE_SPECIAL:
            self.parameterValue = [_pasteSpecialViewController stringEncodedSettings];
            break;

        case KEY_ACTION_MOVE_END_OF_SELECTION_LEFT:
        case KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT:
        case KEY_ACTION_MOVE_START_OF_SELECTION_LEFT:
        case KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT:
            self.parameterValue = [@(_selectionMovementUnit.selectedTag) description];
            break;

        case KEY_ACTION_COMPOSE:
        default:
            self.parameterValue = [_parameter stringValue];
            break;
    }
    self.ok = YES;
    [self.window.sheetParent endSheet:self.window];
}

- (IBAction)cancel:(id)sender {
    self.ok = NO;
    [self.window.sheetParent endSheet:self.window];
}

#pragma mark - iTermSearchableComboViewDelegate

- (void)searchableComboView:(iTermSearchableComboView *)view didSelectItem:(iTermSearchableComboViewItem *)didSelectItem {
    NSString *guid = [[_profilePopup selectedItem] representedObject];
    [_profilePopup populateWithProfilesSelectingGuid:guid];
    [_colorPresetsPopup loadColorPresetsSelecting:_colorPresetsPopup.selectedItem.representedObject];
    [_snippetsPopup populateWithSnippetsSelectingActionKey:_snippetsPopup.selectedItem.representedObject];
    [_menuToSelectPopup reloadData];
    [self updateViewsAnimated:YES];
}

#pragma mark - NSTextEditing

- (void)controlTextDidChange:(NSNotification *)notification {
    _okButton.enabled = [self shouldEnableOK];
}

@end
