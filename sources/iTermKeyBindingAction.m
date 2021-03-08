//
//  iTermKeyBindingAction.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/20.
//

#import "iTermKeyBindingAction.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermPasteSpecialViewController.h"
#import "iTermSnippetsModel.h"
#import "PTYTextView.h"  // just for PTYTextViewSelectionExtensionUnit
#import "ProfileModel.h"

static NSString *const iTermKeyBindingDictionaryKeyAction = @"Action";
static NSString *const iTermKeyBindingDictionaryKeyParameter = @"Text";
static NSString *const iTermKeyBindingDictionaryKeyLabel = @"Label";
static NSString *const iTermKeyBindingDictionaryKeyVersion = @"Version";


static NSString *GetProfileName(NSString *guid) {
    return [[[ProfileModel sharedInstance] bookmarkWithGuid:guid] objectForKey:KEY_NAME];
}

@implementation iTermKeyBindingAction

+ (instancetype)withDictionary:(NSDictionary *)dictionary {
    return [[self alloc] initWithDictionary:dictionary];
}

+ (instancetype)withAction:(KEY_ACTION)action
                 parameter:(NSString *)parameter
  useCompatibilityEscaping:(BOOL)useCompatibilityEscaping {
    return [[self alloc] initWithDictionary:@{ iTermKeyBindingDictionaryKeyAction: @(action),
                                               iTermKeyBindingDictionaryKeyParameter: parameter ?: @"",
                                               iTermKeyBindingDictionaryKeyVersion: useCompatibilityEscaping ? @0: @1
    }];
}

+ (instancetype)withAction:(KEY_ACTION)action
                 parameter:(NSString *)parameter
                     label:(NSString *)label
  useCompatibilityEscaping:(BOOL)useCompatibilityEscaping {
    if (label) {
        return [[self alloc] initWithDictionary:@{ iTermKeyBindingDictionaryKeyAction: @(action),
                                                   iTermKeyBindingDictionaryKeyParameter: parameter ?: @"",
                                                   iTermKeyBindingDictionaryKeyLabel: label,
                                                   iTermKeyBindingDictionaryKeyVersion: useCompatibilityEscaping ? @0: @1
        }];
    } else {
        return [[self alloc] initWithDictionary:@{ iTermKeyBindingDictionaryKeyAction: @(action),
                                                   iTermKeyBindingDictionaryKeyParameter: parameter ?: @"",
                                                   iTermKeyBindingDictionaryKeyVersion: useCompatibilityEscaping ? @0: @1
        }];
    }
}

+ (NSString *)stringForSelectionMovementUnit:(PTYTextViewSelectionExtensionUnit)unit {
    switch (unit) {
        case kPTYTextViewSelectionExtensionUnitLine:
            return @"By Line";
        case kPTYTextViewSelectionExtensionUnitCharacter:
            return @"By Character";
        case kPTYTextViewSelectionExtensionUnitWord:
            return @"By Word";
        case kPTYTextViewSelectionExtensionUnitBigWord:
            return @"By WORD";
        case kPTYTextViewSelectionExtensionUnitMark:
            return @"By Mark";
    }
    XLog(@"Unrecognized selection movement unit %@", @(unit));
    return @"";
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    if (dictionary != nil && ![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    self = [super init];
    if (self) {
        _keyAction = [dictionary[iTermKeyBindingDictionaryKeyAction] intValue];
        _parameter = [dictionary[iTermKeyBindingDictionaryKeyParameter] ?: @"" copy];
        _label = [dictionary[iTermKeyBindingDictionaryKeyLabel] ?: @"" copy];
        _useCompatibilityEscaping = ([dictionary[iTermKeyBindingDictionaryKeyVersion] intValue] == 0);
    }
    return self;
}

- (NSDictionary *)dictionaryValue {
    if (_label) {
        return @{ iTermKeyBindingDictionaryKeyAction: @(_keyAction),
                  iTermKeyBindingDictionaryKeyParameter: _parameter ?: @"",
                  iTermKeyBindingDictionaryKeyLabel: _label,
                  iTermKeyBindingDictionaryKeyVersion: _useCompatibilityEscaping ? @0 : @1
        };
    } else {
        return @{ iTermKeyBindingDictionaryKeyAction: @(_keyAction),
                  iTermKeyBindingDictionaryKeyParameter: _parameter ?: @"",
                  iTermKeyBindingDictionaryKeyVersion: _useCompatibilityEscaping ? @0 : @1
        };
    }
}

- (NSString *)displayName {
    NSString *actionString = nil;

    switch (_keyAction) {
        case KEY_ACTION_MOVE_TAB_LEFT:
            actionString = @"Move Tab Left";
            break;
        case KEY_ACTION_MOVE_TAB_RIGHT:
            actionString = @"Move Tab Right";
            break;
        case KEY_ACTION_NEXT_MRU_TAB:
            actionString = @"Cycle Tabs Forward";
            break;
        case KEY_ACTION_PREVIOUS_MRU_TAB:
            actionString = @"Cycle Tabs Backward";
            break;
        case KEY_ACTION_NEXT_PANE:
            actionString = @"Next Pane";
            break;
        case KEY_ACTION_PREVIOUS_PANE:
            actionString = @"Previous Pane";
            break;
        case KEY_ACTION_NEXT_SESSION:
            actionString = @"Next Tab";
            break;
        case KEY_ACTION_NEXT_WINDOW:
            actionString = @"Next Window";
            break;
        case KEY_ACTION_PREVIOUS_SESSION:
            actionString = @"Previous Tab";
            break;
        case KEY_ACTION_PREVIOUS_WINDOW:
            actionString = @"Previous Window";
            break;
        case KEY_ACTION_SCROLL_END:
            actionString = @"Scroll To End";
            break;
        case KEY_ACTION_SCROLL_HOME:
            actionString = @"Scroll To Top";
            break;
        case KEY_ACTION_SCROLL_LINE_DOWN:
            actionString = @"Scroll One Line Down";
            break;
        case KEY_ACTION_SCROLL_LINE_UP:
            actionString = @"Scroll One Line Up";
            break;
        case KEY_ACTION_SCROLL_PAGE_DOWN:
            actionString = @"Scroll One Page Down";
            break;
        case KEY_ACTION_SCROLL_PAGE_UP:
            actionString = @"Scroll One Page Up";
            break;
        case KEY_ACTION_ESCAPE_SEQUENCE:
            actionString = [NSString stringWithFormat:@"%@ %@", @"Send ^[", _parameter];
            break;
        case KEY_ACTION_HEX_CODE:
            actionString = [NSString stringWithFormat: @"%@ %@", @"Send Hex Codes:", _parameter];
            break;
        case KEY_ACTION_VIM_TEXT:
            actionString = [NSString stringWithFormat:@"%@ \"%@\"", @"Send:", _parameter];
            break;
        case KEY_ACTION_TEXT:
            actionString = [NSString stringWithFormat:@"%@ \"%@\"", @"Send:", _parameter];
            break;
        case KEY_ACTION_SEND_SNIPPET: {
            iTermSnippet *snippet = [[iTermSnippetsModel sharedInstance] snippetWithActionKey:_parameter];
            if (snippet) {
                actionString = [NSString stringWithFormat:@"Send Snippet “%@”", snippet.displayTitle];
            } else {
                actionString = @"Send Deleted Snippet (no action)";
            }
            break;
        }
        case KEY_ACTION_RUN_COPROCESS:
            actionString = [NSString stringWithFormat:@"Run Coprocess \"%@\"",
						    _parameter];
            break;
        case KEY_ACTION_SELECT_MENU_ITEM: {
            NSArray *parts = [_parameter componentsSeparatedByString:@"\n"];
            actionString = [NSString stringWithFormat:@"%@ “%@”", @"Select Menu Item", parts.firstObject];
            break;
        }
        case KEY_ACTION_NEW_WINDOW_WITH_PROFILE:
            actionString = [NSString stringWithFormat:@"New Window with \"%@\" Profile", GetProfileName(_parameter)];
            break;
        case KEY_ACTION_NEW_TAB_WITH_PROFILE:
            actionString = [NSString stringWithFormat:@"New Tab with \"%@\" Profile", GetProfileName(_parameter)];
            break;
        case KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE:
            actionString = [NSString stringWithFormat:@"Split Horizontally with \"%@\" Profile", GetProfileName(_parameter)];
            break;
        case KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE:
            actionString = [NSString stringWithFormat:@"Split Vertically with \"%@\" Profile", GetProfileName(_parameter)];
            break;
        case KEY_ACTION_SET_PROFILE:
            actionString = [NSString stringWithFormat:@"Change Profile to \"%@\"", GetProfileName(_parameter)];
            break;
        case KEY_ACTION_LOAD_COLOR_PRESET:
            actionString = [NSString stringWithFormat:@"Load Color Preset \"%@\"", _parameter];
            break;
        case KEY_ACTION_SEND_C_H_BACKSPACE:
            actionString = @"Send ^H Backspace";
            break;
        case KEY_ACTION_SEND_C_QM_BACKSPACE:
            actionString = @"Send ^? Backspace";
            break;
        case KEY_ACTION_IGNORE:
            actionString = @"Ignore";
            break;
        case KEY_ACTION_IR_FORWARD:
            actionString = @"Unsupported Command";
            break;
        case KEY_ACTION_IR_BACKWARD:
            actionString = @"Start Instant Replay";
            break;
        case KEY_ACTION_SELECT_PANE_LEFT:
            actionString = @"Select Split Pane on Left";
            break;
        case KEY_ACTION_SELECT_PANE_RIGHT:
            actionString = @"Select Split Pane on Right";
            break;
        case KEY_ACTION_SELECT_PANE_ABOVE:
            actionString = @"Select Split Pane Above";
            break;
        case KEY_ACTION_SELECT_PANE_BELOW:
            actionString = @"Select Split Pane Below";
            break;
        case KEY_ACTION_DO_NOT_REMAP_MODIFIERS:
            actionString = @"Do Not Remap Modifiers";
            break;
        case KEY_ACTION_REMAP_LOCALLY:
            actionString = @"Remap Modifiers in iTerm2 Only";
            break;
        case KEY_ACTION_TOGGLE_FULLSCREEN:
            actionString = @"Toggle Fullscreen";
            break;
        case KEY_ACTION_TOGGLE_HOTKEY_WINDOW_PINNING:
            actionString = @"Toggle Pin Hotkey Window";
            break;
        case KEY_ACTION_UNDO:
            actionString = @"Undo";
            break;
        case KEY_ACTION_FIND_REGEX:
            actionString = [NSString stringWithFormat:@"Find Regex “%@”", _parameter];
            break;
        case KEY_FIND_AGAIN_DOWN:
            actionString = @"Find Again Down";
            break;
        case KEY_FIND_AGAIN_UP:
            actionString = @"Find Again Up";
            break;
        case KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION: {
            NSString *pasteDetails =
                [iTermPasteSpecialViewController descriptionForCodedSettings:_parameter];
            if (pasteDetails.length) {
                actionString = [NSString stringWithFormat:@"Paste from Selection: %@", pasteDetails];
            } else {
                actionString = @"Paste from Selection";
            }
            break;
        }
        case KEY_ACTION_PASTE_SPECIAL: {
            NSString *pasteDetails =
                [iTermPasteSpecialViewController descriptionForCodedSettings:_parameter];
            if (pasteDetails.length) {
                actionString = [NSString stringWithFormat:@"Paste: %@", pasteDetails];
            } else {
                actionString = @"Paste";
            }
            break;
        }
        case KEY_ACTION_MOVE_END_OF_SELECTION_LEFT:
            actionString = [NSString stringWithFormat:@"Move End of Selection Left %@",
                            [self.class stringForSelectionMovementUnit:_parameter.integerValue]];
            break;
        case KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT:
            actionString = [NSString stringWithFormat:@"Move End of Selection Right %@",
                            [self.class stringForSelectionMovementUnit:_parameter.integerValue]];
            break;
        case KEY_ACTION_MOVE_START_OF_SELECTION_LEFT:
            actionString = [NSString stringWithFormat:@"Move Start of Selection Left %@",
                            [self.class stringForSelectionMovementUnit:_parameter.integerValue]];
            break;
        case KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT:
            actionString = [NSString stringWithFormat:@"Move Start of Selection Right %@",
                            [self.class stringForSelectionMovementUnit:_parameter.integerValue]];
            break;

        case KEY_ACTION_DECREASE_HEIGHT:
            actionString = @"Decrease Height";
            break;
        case KEY_ACTION_INCREASE_HEIGHT:
            actionString = @"Increase Height";
            break;

        case KEY_ACTION_DECREASE_WIDTH:
            actionString = @"Decrease Width";
            break;
        case KEY_ACTION_INCREASE_WIDTH:
            actionString = @"Increase Width";
            break;

        case KEY_ACTION_SWAP_PANE_LEFT:
            actionString = @"Swap With Split Pane on Left";
            break;
        case KEY_ACTION_SWAP_PANE_RIGHT:
            actionString = @"Swap With Split Pane on Right";
            break;
        case KEY_ACTION_SWAP_PANE_ABOVE:
            actionString = @"Swap With Split Pane Above";
            break;
        case KEY_ACTION_SWAP_PANE_BELOW:
            actionString = @"Swap With Split Pane Below";
            break;
        case KEY_ACTION_TOGGLE_MOUSE_REPORTING:
            actionString = @"Toggle Mouse Reporting";
            break;
        case KEY_ACTION_INVOKE_SCRIPT_FUNCTION:
            actionString = [NSString stringWithFormat:@"Call %@", _parameter];
            break;
        case KEY_ACTION_DUPLICATE_TAB:
            actionString = @"Duplicate Tab";
            break;
        default:
            actionString = [NSString stringWithFormat: @"%@ %d", @"Unknown Action ID", _keyAction];
            break;
        case KEY_ACTION_MOVE_TO_SPLIT_PANE:
            actionString = @"Move to Split Pane";
            break;
    }

    return actionString;
}

- (BOOL)sendsText {
    switch (self.keyAction) {
        case KEY_ACTION_ESCAPE_SEQUENCE:
        case KEY_ACTION_HEX_CODE:
        case KEY_ACTION_TEXT:
        case KEY_ACTION_SEND_SNIPPET:
        case KEY_ACTION_VIM_TEXT:
        case KEY_ACTION_RUN_COPROCESS:
        case KEY_ACTION_SEND_C_H_BACKSPACE:
        case KEY_ACTION_SEND_C_QM_BACKSPACE:
        case KEY_ACTION_PASTE_SPECIAL:
        case KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION:
            return YES;
            
        case KEY_ACTION_IGNORE:
        case KEY_ACTION_INVALID:
        case KEY_ACTION_NEXT_SESSION:
        case KEY_ACTION_NEXT_WINDOW:
        case KEY_ACTION_PREVIOUS_SESSION:
        case KEY_ACTION_PREVIOUS_WINDOW:
        case KEY_ACTION_SCROLL_END:
        case KEY_ACTION_SCROLL_HOME:
        case KEY_ACTION_SCROLL_LINE_DOWN:
        case KEY_ACTION_SCROLL_LINE_UP:
        case KEY_ACTION_SCROLL_PAGE_DOWN:
        case KEY_ACTION_SCROLL_PAGE_UP:
        case KEY_ACTION_IR_FORWARD:
        case KEY_ACTION_IR_BACKWARD:
        case KEY_ACTION_SELECT_PANE_LEFT:
        case KEY_ACTION_SELECT_PANE_RIGHT:
        case KEY_ACTION_SELECT_PANE_ABOVE:
        case KEY_ACTION_SELECT_PANE_BELOW:
        case KEY_ACTION_DO_NOT_REMAP_MODIFIERS:
        case KEY_ACTION_TOGGLE_FULLSCREEN:
        case KEY_ACTION_REMAP_LOCALLY:
        case KEY_ACTION_SELECT_MENU_ITEM:
        case KEY_ACTION_NEW_WINDOW_WITH_PROFILE:
        case KEY_ACTION_NEW_TAB_WITH_PROFILE:
        case KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE:
        case KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE:
        case KEY_ACTION_NEXT_PANE:
        case KEY_ACTION_PREVIOUS_PANE:
        case KEY_ACTION_NEXT_MRU_TAB:
        case KEY_ACTION_MOVE_TAB_LEFT:
        case KEY_ACTION_MOVE_TAB_RIGHT:
        case KEY_ACTION_FIND_REGEX:
        case KEY_ACTION_SET_PROFILE:
        case KEY_ACTION_PREVIOUS_MRU_TAB:
        case KEY_ACTION_LOAD_COLOR_PRESET:
        case KEY_ACTION_TOGGLE_HOTKEY_WINDOW_PINNING:
        case KEY_ACTION_UNDO:
        case KEY_ACTION_MOVE_END_OF_SELECTION_LEFT:
        case KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT:
        case KEY_ACTION_MOVE_START_OF_SELECTION_LEFT:
        case KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT:
        case KEY_ACTION_DECREASE_HEIGHT:
        case KEY_ACTION_INCREASE_HEIGHT:
        case KEY_ACTION_DECREASE_WIDTH:
        case KEY_ACTION_INCREASE_WIDTH:
        case KEY_ACTION_SWAP_PANE_LEFT:
        case KEY_ACTION_SWAP_PANE_RIGHT:
        case KEY_ACTION_SWAP_PANE_ABOVE:
        case KEY_ACTION_SWAP_PANE_BELOW:
        case KEY_FIND_AGAIN_DOWN:
        case KEY_FIND_AGAIN_UP:
        case KEY_ACTION_TOGGLE_MOUSE_REPORTING:
        case KEY_ACTION_INVOKE_SCRIPT_FUNCTION:
        case KEY_ACTION_DUPLICATE_TAB:
        case KEY_ACTION_MOVE_TO_SPLIT_PANE:
            break;
    }
    return NO;
}

- (BOOL)isActionable {
    switch (self.keyAction) {
        case KEY_ACTION_DO_NOT_REMAP_MODIFIERS:
        case KEY_ACTION_REMAP_LOCALLY:
            return NO;

        case KEY_ACTION_IGNORE:
        case KEY_ACTION_ESCAPE_SEQUENCE:
        case KEY_ACTION_HEX_CODE:
        case KEY_ACTION_TEXT:
        case KEY_ACTION_VIM_TEXT:
        case KEY_ACTION_SEND_SNIPPET:
        case KEY_ACTION_RUN_COPROCESS:
        case KEY_ACTION_SEND_C_H_BACKSPACE:
        case KEY_ACTION_SEND_C_QM_BACKSPACE:
        case KEY_ACTION_INVALID:
        case KEY_ACTION_NEXT_SESSION:
        case KEY_ACTION_NEXT_WINDOW:
        case KEY_ACTION_PREVIOUS_SESSION:
        case KEY_ACTION_PREVIOUS_WINDOW:
        case KEY_ACTION_SCROLL_END:
        case KEY_ACTION_SCROLL_HOME:
        case KEY_ACTION_SCROLL_LINE_DOWN:
        case KEY_ACTION_SCROLL_LINE_UP:
        case KEY_ACTION_SCROLL_PAGE_DOWN:
        case KEY_ACTION_SCROLL_PAGE_UP:
        case KEY_ACTION_IR_FORWARD:
        case KEY_ACTION_IR_BACKWARD:
        case KEY_ACTION_SELECT_PANE_LEFT:
        case KEY_ACTION_SELECT_PANE_RIGHT:
        case KEY_ACTION_SELECT_PANE_ABOVE:
        case KEY_ACTION_SELECT_PANE_BELOW:
        case KEY_ACTION_TOGGLE_FULLSCREEN:
        case KEY_ACTION_SELECT_MENU_ITEM:
        case KEY_ACTION_NEW_WINDOW_WITH_PROFILE:
        case KEY_ACTION_NEW_TAB_WITH_PROFILE:
        case KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE:
        case KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE:
        case KEY_ACTION_NEXT_PANE:
        case KEY_ACTION_PREVIOUS_PANE:
        case KEY_ACTION_NEXT_MRU_TAB:
        case KEY_ACTION_MOVE_TAB_LEFT:
        case KEY_ACTION_MOVE_TAB_RIGHT:
        case KEY_ACTION_FIND_REGEX:
        case KEY_ACTION_SET_PROFILE:
        case KEY_ACTION_PREVIOUS_MRU_TAB:
        case KEY_ACTION_LOAD_COLOR_PRESET:
        case KEY_ACTION_PASTE_SPECIAL:
        case KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION:
        case KEY_ACTION_TOGGLE_HOTKEY_WINDOW_PINNING:
        case KEY_ACTION_UNDO:
        case KEY_ACTION_MOVE_END_OF_SELECTION_LEFT:
        case KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT:
        case KEY_ACTION_MOVE_START_OF_SELECTION_LEFT:
        case KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT:
        case KEY_ACTION_DECREASE_HEIGHT:
        case KEY_ACTION_INCREASE_HEIGHT:
        case KEY_ACTION_DECREASE_WIDTH:
        case KEY_ACTION_INCREASE_WIDTH:
        case KEY_ACTION_SWAP_PANE_LEFT:
        case KEY_ACTION_SWAP_PANE_RIGHT:
        case KEY_ACTION_SWAP_PANE_ABOVE:
        case KEY_ACTION_SWAP_PANE_BELOW:
        case KEY_FIND_AGAIN_DOWN:
        case KEY_FIND_AGAIN_UP:
        case KEY_ACTION_TOGGLE_MOUSE_REPORTING:
        case KEY_ACTION_INVOKE_SCRIPT_FUNCTION:
        case KEY_ACTION_DUPLICATE_TAB:
        case KEY_ACTION_MOVE_TO_SPLIT_PANE:
            break;
    }
    return YES;
}

@end
