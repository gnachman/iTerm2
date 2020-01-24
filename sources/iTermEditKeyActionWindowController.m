//
//  iTermEditKeyActionWindowController.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "iTermEditKeyActionWindowController.h"

#import "iTermActionsModel.h"
#import "iTermFunctionCallTextFieldDelegate.h"
#import "iTermPasteSpecialViewController.h"
#import "iTermPreferences.h"
#import "iTermShortcutInputView.h"
#import "iTermVariableScope.h"
#import "iTermKeyBindingMgr.h"
#import "NSPopUpButton+iTerm.h"
#import "RegexKitLite.h"

#import <SearchableComboListView/SearchableComboListView.h>
#import <SearchableComboListView/SearchableComboListView-Swift.h>

@interface iTermEditKeyActionWindowController () <
    iTermSearchableComboViewDelegate,
    iTermShortcutInputViewDelegate>

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
    IBOutlet NSPopUpButton *_menuToSelectPopup;
    IBOutlet NSTextField *_profileLabel;
    IBOutlet NSTextField *_colorPresetsLabel;
    IBOutlet NSPopUpButton *_colorPresetsPopup;
    IBOutlet NSView *_pasteSpecialViewContainer;

    iTermPasteSpecialViewController *_pasteSpecialViewController;
    iTermFunctionCallTextFieldDelegate *_functionCallDelegate;
    iTermFunctionCallTextFieldDelegate *_labelDelegate;
}

- (instancetype)initWithContext:(iTermVariablesSuggestionContext)context
                           mode:(iTermEditKeyActionWindowControllerMode)mode {
    self = [super initWithWindowNibName:@"iTermEditKeyActionWindowController"];
    if (self) {
        _suggestContext = context;
    }
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];

    NSArray<iTermSearchableComboViewGroup *> *groups = @[
        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"General" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Ignore" tag:13],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Select Menu Item..." tag:25],
        ]],
    ];
    if (self.mode == iTermEditKeyActionWindowControllerModeKeyboardShortcut) {
        groups = [groups arrayByAddingObjectsFromArray:@[
            [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Modifier Remapping" items:@[
                [[iTermSearchableComboViewItem alloc] initWithLabel:@"Do Not Remap Modifiers" tag:22],
                [[iTermSearchableComboViewItem alloc] initWithLabel:@"Remap Modifiers in iTerm2 Only" tag:24],
            ]],
            [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Cycle" items:@[
                [[iTermSearchableComboViewItem alloc] initWithLabel:@"Cycle Tabs Forward" tag:32],
                [[iTermSearchableComboViewItem alloc] initWithLabel:@"Cycle Tabs Backward" tag:39],
            ]],
        ]];
    }

    groups = [groups arrayByAddingObjectsFromArray:@[
        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Miscellaneous" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Run Coprocess" tag:35],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Start Instant Replay" tag:15],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Undo" tag:44],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"New Tab or Window" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"New Window with Profile" tag:26],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"New Tab with Profile" tag:27],
        [[iTermSearchableComboViewItem alloc] initWithLabel:@"Duplicate Tab" tag:61],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Split" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Split Horizontally with Profile" tag:28],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Split Vertically with Profile" tag:29],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Profile" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Change Profile" tag:37],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Load Color Preset" tag:40],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Navigate Tabs" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Next Tab" tag:0],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Previous Tab" tag:2],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Reorder Tabs" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Move Tab Left" tag:33],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Move Tab Right" tag:34],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Navigate Windows" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Next Window" tag:1],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Previous Window" tag:3],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Navigate Panes" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Next Pane" tag:30],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Previous Pane" tag:31],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Select Split Pane Above" tag:20],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Select Split Pane Below" tag:21],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Select Split Pane On Left" tag:18],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Select Split Pane On Right" tag:19],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Resize Pane" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Decrease Height" tag:49],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Increase Height" tag:50],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Decrease Width" tag:51],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Increase Width" tag:52],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Scroll" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Scroll to End" tag:4],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Scroll to Top" tag:5],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Scroll One Line Down" tag:6],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Scroll One Line Up" tag:7],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Scroll One Page Down" tag:8],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Scroll One Page Up" tag:9],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Split Panes" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Swap With Split Pane Above" tag:55],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Swap With Split Pane Below" tag:56],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Swap With Split Pane on Left" tag:53],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Swap With Split Pane on Right" tag:54],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Move Session to Split Pane" tag:62],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Send Keystrokes" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Send ^H Backspace" tag:16],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Send ^? Backspace" tag:17],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Send Escape Sequence" tag:10],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Send Hex Code" tag:11],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Send Text" tag:12],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Send Text with &quot;vim&quot; Special Chars" tag:38],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Search" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Find Regular Expression…" tag:36],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Find Again Down" tag:57],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Find Again Up" tag:58],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Pasteboard" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Paste…" tag:41],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Paste from Selection…" tag:42],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Toggles" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Toggle Fullscreen" tag:23],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Toggle Pin Hotkey Window" tag:43],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Toggle Mouse Reporting" tag:59],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Selection" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Move Start of Selection Back" tag:47],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Move Start of Selection Forward" tag:48],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Move End of Selection Back" tag:45],
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Move End of Selection Forward" tag:46],
        ]],

        [[iTermSearchableComboViewGroup alloc] initWithLabel:@"Scripting" items:@[
            [[iTermSearchableComboViewItem alloc] initWithLabel:@"Invoke Script Function…" tag:60],
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

    _comboView = [[iTermSearchableComboView alloc] initWithGroups:groups];
    [_comboViewContainer addSubview:_comboView];
    _comboView.frame = _comboViewContainer.bounds;
    _comboView.delegate = self;

    // For some reason, the first item is checked by default. Make sure every
    // item is unchecked before making a selection.
    NSString *formattedString = @"";
    if (self.currentKeyCombination) {
        formattedString = [iTermKeyBindingMgr formatKeyCombination:self.currentKeyCombination];
    }
    _shortcutField.stringValue = formattedString;
    _touchBarLabel.stringValue = self.label ?: @"";
    (void)[_comboView selectItemWithTag:self.action];
    _parameter.stringValue = self.parameterValue ?: @"";
    if (self.action == KEY_ACTION_SELECT_MENU_ITEM) {
        [[self class] populatePopUpButtonWithMenuItems:_menuToSelectPopup
                                         selectedTitle:[[_menuToSelectPopup selectedItem] title]
                                            identifier:_menuToSelectPopup.selectedItem.identifier];
        NSArray *parts = [self.parameterValue componentsSeparatedByString:@"\n"];
        if (parts.count < 2) {
            [_menuToSelectPopup selectItemWithTitle:self.parameterValue];
        } else {
            NSInteger index = [_menuToSelectPopup.itemArray indexOfObjectPassingTest:^BOOL(NSMenuItem * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                return [obj.identifier isEqualToString:parts[1]];
            }];
            if (index == NSNotFound) {
                [_menuToSelectPopup selectItemWithTitle:parts.firstObject];
            } else {
                [_menuToSelectPopup selectItemAtIndex:index];
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
                                     parameter:self.parameterValue];
}

- (NSString *)identifier {
    switch (_mode) {
        case iTermEditKeyActionWindowControllerModeKeyboardShortcut:
            return self.currentKeyCombination;
        case iTermEditKeyActionWindowControllerModeTouchBarItem:
            return self.touchBarItemID;
        case iTermEditKeyActionWindowControllerModeUnbound:
            return nil;
    }
}

#pragma mark - iTermShortcutInputViewDelegate

// Note: This is called directly by iTermHotKeyController when the action requires key remapping
// to be disabled so the shortcut can be input properly. In this case, |view| will be nil.
- (void)shortcutInputView:(iTermShortcutInputView *)view didReceiveKeyPressEvent:(NSEvent *)event {
    self.currentKeyCombination = view.shortcut.identifier;
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
                                                                                        passthrough:nil
                                                                                      functionsOnly:NO];
                }
                _touchBarLabel.delegate = _labelDelegate;
            }
            _touchBarLabel.hidden = NO;
            _shortcutField.hidden = YES;
            break;
        case iTermEditKeyActionWindowControllerModeTouchBarItem:
            _keyboardShortcutLabel.stringValue = @"Touch Bar Label";
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
    id<NSTextFieldDelegate> parameterDelegate = nil;

    switch (tag) {
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
            !_pasteSpecialViewContainer.isHidden ||
            !_parameterLabel.isHidden ||
            !_selectionMovementUnit.isHidden);
}

- (void)updateFrameAnimated:(BOOL)animated {
    NSRect rect = self.window.frame;
    /*
     *   Side margin                     Side margin
     *   |                               |
     *  |-|                             |-|
     *  +---------------------------------+
     *  |                                 |
     *  |  Keyboard shortcut: [        ]  |
     *  |             Action: [v Popup ]  |  _
     *  |         Basic Accessory         |  _|-- Basic accessory height
     *  |                                 |
     *  |                  [Cancel] [OK]  |
     *  +---------------------------------+
     *     |---------------------------|
     *     Normal width excluding margins
     *
     *  +---------------------------------+  -
     *  |                                 |  |
     *  |  Keyboard shortcut: [        ]  |  |
     *  |             Action: [v Popup ]  |  |-- Height excluding accessory
     *  |                                 |  |
     *  |                   [Cancel] [OK] |  |
     *  +---------------------------------+  -
     *
     */
    const CGFloat heightExcludingAccessory = 126;
    const CGFloat sideMarginWidth = 20;
    const CGFloat basicAccessoryHeight = 31;
    const CGFloat normalWidthExcludingMargins = 402;
    if ([self anyAccessoryVisible]) {
        if (!_pasteSpecialViewContainer.hidden) {
            const CGFloat widthExcludingMargins = MAX(normalWidthExcludingMargins,
                                                      _pasteSpecialViewController.view.frame.size.width);
            rect.size = NSMakeSize(widthExcludingMargins + sideMarginWidth * 2,
                                   _pasteSpecialViewController.view.frame.size.height + heightExcludingAccessory);
        } else {
            rect.size = NSMakeSize(normalWidthExcludingMargins + sideMarginWidth * 2,
                                   heightExcludingAccessory + basicAccessoryHeight);
        }
    } else {
        rect.size = NSMakeSize(normalWidthExcludingMargins + sideMarginWidth * 2,
                               heightExcludingAccessory);
    }
    if (animated) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.window setFrame:rect display:YES animate:YES];
        });
    } else {
        [self.window setFrame:rect display:YES animate:NO];
    }
}

- (void)setPasteSpecialHidden:(BOOL)hidden {
    _pasteSpecialViewContainer.hidden = hidden;
}

+ (void)populatePopUpButtonWithMenuItems:(NSPopUpButton *)button
                           selectedTitle:(NSString *)selectedValue
                              identifier:(NSString *)identifier {
    [self recursiveAddMenu:[NSApp mainMenu] toButtonMenu:[button menu] depth:0 ancestors:@[]];
    if (selectedValue) {
        NSMenuItem *theItem = [[button menu] itemWithTitle:selectedValue];
        if (theItem) {
            [button setTitle:selectedValue];
            [theItem setState:NSOnState];
        }
    }
}

+ (BOOL)item:(NSMenuItem *)item isWindowInWindowsMenu:(NSMenu *)menu {
    if (![[menu title] isEqualToString:@"Window"]) {
        return NO;
    }

    return ([item.title isMatchedByRegex:@"^\\d+\\. " ]);
}

+ (BOOL)ancestorsContainsProfilesMenuItem:(NSArray<NSMenuItem *> *)ancestors {
    if (ancestors.count == 0) {
        return NO;
    }
    return [ancestors[0].identifier isEqualToString:@".Profiles"];
}

+ (void)recursiveAddMenu:(NSMenu *)menu
            toButtonMenu:(NSMenu *)buttonMenu
                   depth:(int)depth
               ancestors:(NSArray<NSMenuItem *> *)ancestors {
    const BOOL descendsFromProfiles = [self ancestorsContainsProfilesMenuItem:ancestors];
    for (NSMenuItem *item in [menu itemArray]) {
        if (item.isSeparatorItem) {
            continue;
        }
        if ([item.title isEqualToString:@"Services"] ||  // exclude services menu
            [self item:item isWindowInWindowsMenu:menu]) {  // exclude windows in window menu
            continue;
        }
        NSMenuItem *theItem = [[NSMenuItem alloc] init];

        if (([item.identifier hasPrefix:iTermProfileModelNewTabMenuItemIdentifierPrefix] ||
             [item.identifier hasPrefix:iTermProfileModelNewWindowMenuItemIdentifierPrefix]) &&
            descendsFromProfiles && !item.hasSubmenu) {
            if (item.isAlternate) {
                theItem.title = [NSString stringWithFormat:@"%@ — New Window", item.title];
            } else {
                theItem.title = [NSString stringWithFormat:@"%@ — New Tab", item.title];
            }
        } else {
            theItem.title = item.title;
        }
        theItem.identifier = item.identifier;
        theItem.indentationLevel = depth;
        if (item.hasSubmenu) {
            if (depth == 0 && buttonMenu.itemArray.count) {
                [buttonMenu addItem:[NSMenuItem separatorItem]];
            }
            theItem.enabled = NO;
            [buttonMenu addItem:theItem];
            [self recursiveAddMenu:item.submenu
                      toButtonMenu:buttonMenu
                             depth:depth + 1
                         ancestors:[ancestors arrayByAddingObject:item]];
        } else {
            [buttonMenu addItem:theItem];
        }
    }
}


#pragma mark - Actions

- (IBAction)ok:(id)sender {
    switch (self.mode) {
        case iTermEditKeyActionWindowControllerModeUnbound:
            self.label = _touchBarLabel.stringValue ?: @"";
            break;
        case iTermEditKeyActionWindowControllerModeTouchBarItem:
            if (!_touchBarLabel.stringValue.length) {
                NSBeep();
                return;
            }
            self.label = _touchBarLabel.stringValue;
            break;
        case iTermEditKeyActionWindowControllerModeKeyboardShortcut:
            if (!self.currentKeyCombination) {
                NSBeep();
                return;
            }
            break;
    }

    self.action = _comboView.selectedTag;

    switch (self.action) {
        case KEY_ACTION_SELECT_MENU_ITEM:
            if (_menuToSelectPopup.selectedItem.identifier.length) {
              self.parameterValue = [NSString stringWithFormat:@"%@\n%@", _menuToSelectPopup.selectedItem.title, _menuToSelectPopup.selectedItem.identifier ?: @""];
            } else {
                self.parameterValue = [[_menuToSelectPopup selectedItem] title];
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
    [[self class] populatePopUpButtonWithMenuItems:_menuToSelectPopup
                                     selectedTitle:[[_menuToSelectPopup selectedItem] title]
                                        identifier:_menuToSelectPopup.selectedItem.identifier];
    [self updateViewsAnimated:YES];
}

@end
