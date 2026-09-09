//
//  iTermKeyBindingAction.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/20.
//

#import "iTermKeyBindingAction.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "ITAddressBookMgr.h"
#import "iTermPasteSpecialViewController.h"
#import "iTermSnippetsModel.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "PTYTextView.h"  // just for PTYTextViewSelectionExtensionUnit
#import "ProfileModel.h"

NSString *const iTermKeyBindingDictionaryKeyAction = @"Action";
NSString *const iTermKeyBindingDictionaryKeyParameter = @"Text";
NSString *const iTermKeyBindingDictionaryKeyLabel = @"Label";
NSString *const iTermKeyBindingDictionaryKeyVersion = @"Version";
NSString *const iTermKeyBindingDictionaryKeyEscaping = @"Escaping";
NSString *const iTermKeyBindingDictionaryKeyApplyMode = @"Apply Mode";


static NSString *GetProfileName(NSString *guid) {
    return [[[ProfileModel sharedInstance] bookmarkWithGuid:guid] objectForKey:KEY_NAME];
}

@implementation iTermKeyBindingAction {
    NSDictionary *_dictionary;
}

+ (NSString *)escapedText:(NSString *)text mode:(iTermSendTextEscaping)escaping {
    NSString *temp = text;
    switch (escaping) {
        case iTermSendTextEscapingNone:
            return text;
        case iTermSendTextEscapingCommon:
            return [temp stringByReplacingCommonlyEscapedCharactersWithControls];
        case iTermSendTextEscapingCompatibility:
            temp = [temp stringByReplacingEscapedChar:'n' withString:@"\n"];
            temp = [temp stringByReplacingEscapedChar:'e' withString:@"\e"];
            temp = [temp stringByReplacingEscapedChar:'a' withString:@"\a"];
            temp = [temp stringByReplacingEscapedChar:'t' withString:@"\t"];
            return temp;
        case iTermSendTextEscapingVimAndCompatibility:
            temp = [temp stringByExpandingVimSpecialCharacters];
            temp = [temp stringByReplacingEscapedChar:'n' withString:@"\n"];
            temp = [temp stringByReplacingEscapedChar:'e' withString:@"\e"];
            temp = [temp stringByReplacingEscapedChar:'a' withString:@"\a"];
            temp = [temp stringByReplacingEscapedChar:'t' withString:@"\t"];
            return temp;
        case iTermSendTextEscapingVim:
            return [temp stringByExpandingVimSpecialCharacters];
    }
    assert(NO);
    return @"";
}


+ (instancetype)fromString:(NSString *)string {
    NSData *decoded = [[NSData alloc] initWithBase64EncodedString:string options:0];
    if (!decoded) {
        return nil;
    }
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:decoded options:0 error:nil];
    if (!dict) {
        return nil;
    }
    return [self withDictionary:dict];
}

- (NSString *)stringValue {
    NSDictionary *dict = [self dictionaryValue];
    if (!dict) {
        return nil;
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    if (!json) {
        return nil;
    }
    NSData *data = [json base64EncodedDataWithOptions:0];
    if (!data) {
        return nil;
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+ (instancetype)withDictionary:(NSDictionary *)dictionary {
    return [[self alloc] initWithDictionary:dictionary];
}

+ (instancetype)withAction:(KEY_ACTION)action
                 parameter:(NSString *)parameter
                  escaping:(iTermSendTextEscaping)escaping
                 applyMode:(iTermActionApplyMode)applyMode {
    return [[self alloc] initWithDictionary:@{ iTermKeyBindingDictionaryKeyAction: @(action),
                                               iTermKeyBindingDictionaryKeyParameter: parameter ?: @"",
                                               iTermKeyBindingDictionaryKeyVersion: @2,
                                               iTermKeyBindingDictionaryKeyEscaping: @(escaping),
                                               iTermKeyBindingDictionaryKeyApplyMode: @(applyMode)
    }];
}

+ (instancetype)withAction:(KEY_ACTION)action
                 parameter:(NSString *)parameter
                     label:(NSString *)label
                  escaping:(iTermSendTextEscaping)escaping
                 applyMode:(iTermActionApplyMode)applyMode {
    if (label) {
        return [[self alloc] initWithDictionary:@{ iTermKeyBindingDictionaryKeyAction: @(action),
                                                   iTermKeyBindingDictionaryKeyParameter: parameter ?: @"",
                                                   iTermKeyBindingDictionaryKeyLabel: label,
                                                   iTermKeyBindingDictionaryKeyVersion: @2,
                                                   iTermKeyBindingDictionaryKeyEscaping: @(escaping),
                                                   iTermKeyBindingDictionaryKeyApplyMode: @(applyMode)
        }];
    } else {
        return [[self alloc] initWithDictionary:@{ iTermKeyBindingDictionaryKeyAction: @(action),
                                                   iTermKeyBindingDictionaryKeyParameter: parameter ?: @"",
                                                   iTermKeyBindingDictionaryKeyVersion: @2,
                                                   iTermKeyBindingDictionaryKeyEscaping: @(escaping),
                                                   iTermKeyBindingDictionaryKeyApplyMode: @(applyMode)
        }];
    }
}

+ (NSString *)stringForSelectionMovementUnit:(PTYTextViewSelectionExtensionUnit)unit {
    switch (unit) {
        case kPTYTextViewSelectionExtensionUnitLine:
            return NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SelectionUnit.ByLine", nil, [NSBundle mainBundle], @"By Line", @"Selection movement unit shown in a key-binding action name, as in “Move End of Selection Left By Line”");
        case kPTYTextViewSelectionExtensionUnitCharacter:
            return NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SelectionUnit.ByCharacter", nil, [NSBundle mainBundle], @"By Character", @"Selection movement unit shown in a key-binding action name");
        case kPTYTextViewSelectionExtensionUnitWord:
            return NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SelectionUnit.ByWord", nil, [NSBundle mainBundle], @"By Word", @"Selection movement unit shown in a key-binding action name");
        case kPTYTextViewSelectionExtensionUnitBigWord:
            return NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SelectionUnit.ByBigWord", nil, [NSBundle mainBundle], @"By WORD", @"Selection movement unit shown in a key-binding action name; WORD is a vi term for a whitespace-delimited word and is intentionally uppercase");
        case kPTYTextViewSelectionExtensionUnitMark:
            return NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SelectionUnit.ByMark", nil, [NSBundle mainBundle], @"By Mark", @"Selection movement unit shown in a key-binding action name");
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
        _applyMode = [dictionary[iTermKeyBindingDictionaryKeyApplyMode] unsignedIntegerValue];

        const int version = [dictionary[iTermKeyBindingDictionaryKeyVersion] intValue];
        if (version == 0) {
            _escaping = iTermSendTextEscapingCompatibility;
        } else if (version == 1) {
            _escaping = iTermSendTextEscapingCommon;
        } else {
            _escaping = [dictionary[iTermKeyBindingDictionaryKeyEscaping] unsignedIntegerValue];
        }
        _dictionary = [dictionary copy];
    }
    return self;
}

- (NSDictionary *)dictionaryValue {
    if (_dictionary) {
        return _dictionary;
    }
    // This is complicated because it wants to avoid changing the dictionary unless it is necessary.
    int version;
    id escaping;
    switch (_escaping) {
        case iTermSendTextEscapingCompatibility:
            version = 0;
            escaping = [NSNull null];
            break;
        case iTermSendTextEscapingCommon:
            version = 1;
            escaping = [NSNull null];
            break;
        default:
            version = 2;
            escaping = @(_escaping);
            break;
    }
    NSDictionary *temp = @{ iTermKeyBindingDictionaryKeyAction: @(_keyAction),
                            iTermKeyBindingDictionaryKeyParameter: _parameter ?: @"",
                            iTermKeyBindingDictionaryKeyLabel: _label ?: [NSNull null],
                            iTermKeyBindingDictionaryKeyVersion: @(version),
                            iTermKeyBindingDictionaryKeyEscaping: escaping,
                            iTermKeyBindingDictionaryKeyApplyMode: @(_applyMode)
    };
    return [temp dictionaryByRemovingNullValues];
}

- (iTermSendTextEscaping)vimEscaping {
    switch (_escaping) {
        case iTermSendTextEscapingNone:
        case iTermSendTextEscapingCommon:
        case iTermSendTextEscapingVim:
            return iTermSendTextEscapingVim;
        case iTermSendTextEscapingCompatibility:
        case iTermSendTextEscapingVimAndCompatibility:
            return iTermSendTextEscapingVimAndCompatibility;
    }
}

- (NSString *)displayName {
    NSString *actionString = nil;

    switch (_keyAction) {
        case KEY_ACTION_MOVE_TAB_LEFT:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.MoveTabLeft", nil, [NSBundle mainBundle], @"Move Tab Left", @"Key binding action name");
            break;
        case KEY_ACTION_MOVE_TAB_RIGHT:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.MoveTabRight", nil, [NSBundle mainBundle], @"Move Tab Right", @"Key binding action name");
            break;
        case KEY_ACTION_NEXT_MRU_TAB:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.CycleTabsForward", nil, [NSBundle mainBundle], @"Cycle Tabs Forward", @"Key binding action name");
            break;
        case KEY_ACTION_PREVIOUS_MRU_TAB:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.CycleTabsBackward", nil, [NSBundle mainBundle], @"Cycle Tabs Backward", @"Key binding action name");
            break;
        case KEY_ACTION_NEXT_PANE:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.NextPane", nil, [NSBundle mainBundle], @"Next Pane", @"Key binding action name");
            break;
        case KEY_ACTION_PREVIOUS_PANE:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.PreviousPane", nil, [NSBundle mainBundle], @"Previous Pane", @"Key binding action name");
            break;
        case KEY_ACTION_NEXT_SESSION:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.NextTab", nil, [NSBundle mainBundle], @"Next Tab", @"Key binding action name");
            break;
        case KEY_ACTION_NEXT_WINDOW:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.NextWindow", nil, [NSBundle mainBundle], @"Next Window", @"Key binding action name");
            break;
        case KEY_ACTION_PREVIOUS_SESSION:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.PreviousTab", nil, [NSBundle mainBundle], @"Previous Tab", @"Key binding action name");
            break;
        case KEY_ACTION_PREVIOUS_WINDOW:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.PreviousWindow", nil, [NSBundle mainBundle], @"Previous Window", @"Key binding action name");
            break;
        case KEY_ACTION_SCROLL_END:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.ScrollToEnd", nil, [NSBundle mainBundle], @"Scroll To End", @"Key binding action name");
            break;
        case KEY_ACTION_SCROLL_HOME:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.ScrollToTop", nil, [NSBundle mainBundle], @"Scroll To Top", @"Key binding action name");
            break;
        case KEY_ACTION_SCROLL_LINE_DOWN:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.ScrollOneLineDown", nil, [NSBundle mainBundle], @"Scroll One Line Down", @"Key binding action name");
            break;
        case KEY_ACTION_SCROLL_LINE_UP:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.ScrollOneLineUp", nil, [NSBundle mainBundle], @"Scroll One Line Up", @"Key binding action name");
            break;
        case KEY_ACTION_SCROLL_PAGE_DOWN:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.ScrollOnePageDown", nil, [NSBundle mainBundle], @"Scroll One Page Down", @"Key binding action name");
            break;
        case KEY_ACTION_SCROLL_PAGE_UP:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.ScrollOnePageUp", nil, [NSBundle mainBundle], @"Scroll One Page Up", @"Key binding action name");
            break;
        case KEY_ACTION_ESCAPE_SEQUENCE:
            actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SendEscapeSequence", nil, [NSBundle mainBundle], @"Send ^[ %@", @"Key binding action name; sends an escape sequence. ^[ represents the escape character and %@ is the sequence to send"), _parameter];
            break;
        case KEY_ACTION_HEX_CODE:
            actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SendHexCodes", nil, [NSBundle mainBundle], @"Send Hex Codes: %@", @"Key binding action name; %@ is a list of hexadecimal byte codes to send"), _parameter];
            break;
        case KEY_ACTION_VIM_TEXT:
            actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SendText", nil, [NSBundle mainBundle], @"Send: “%@”", @"Key binding action name; %@ is the text to send"), _parameter];
            break;
        case KEY_ACTION_VIM_TEXT_NO_BROADCAST:
            actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SendTextNoBroadcast", nil, [NSBundle mainBundle], @"Send (no broadcast): “%@”", @"Key binding action name; sends text without broadcasting. %@ is the text to send"), _parameter];
            break;
        case KEY_ACTION_TEXT:
            actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SendText", nil, [NSBundle mainBundle], @"Send: “%@”", @"Key binding action name; %@ is the text to send"), _parameter];
            break;
        case KEY_ACTION_SEND_SNIPPET: {
            iTermSnippet *snippet = [[iTermSnippetsModel sharedInstance] snippetWithActionKey:_parameter];
            if (snippet) {
                actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SendSnippet", nil, [NSBundle mainBundle], @"Send Snippet “%@”", @"Key binding action name; %@ is the snippet title"), snippet.displayTitle];
            } else {
                actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SendDeletedSnippet", nil, [NSBundle mainBundle], @"Send Deleted Snippet (no action)", @"Key binding action name shown when the referenced snippet has been deleted");
            }
            break;
        }
        case KEY_ACTION_COMPOSE:
            actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.Compose", nil, [NSBundle mainBundle], @"Compose “%@”", @"Key binding action name; %@ is the text to compose"), _parameter];
            break;
        case KEY_ACTION_SEND_TMUX_COMMAND:
            actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SendTmuxCommand", nil, [NSBundle mainBundle], @"tmux: %@", @"Key binding action name; sends a tmux command. %@ is the command"), _parameter];
            break;
        case KEY_ACTION_RUN_COPROCESS:
            actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.RunCoprocess", nil, [NSBundle mainBundle], @"Run Coprocess “%@”", @"Key binding action name; %@ is the coprocess command"),
						    _parameter];
            break;
        case KEY_ACTION_SELECT_MENU_ITEM: {
            NSArray *parts = [_parameter componentsSeparatedByString:@"\n"];
            actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SelectMenuItem", nil, [NSBundle mainBundle], @"Select Menu Item “%@”", @"Key binding action name; %@ is the menu item title"), parts.firstObject];
            break;
        }
        case KEY_ACTION_NEW_WINDOW_WITH_PROFILE:
            if ([[ProfileModel sharedInstance] bookmarkWithGuid:_parameter]) {
                actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.NewWindowWithProfile", nil, [NSBundle mainBundle], @"New Window with “%@” Profile", @"Key binding action name; %@ is the profile name"), GetProfileName(_parameter)];
            } else {
                actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.NewWindowWithUnavailableProfile", nil, [NSBundle mainBundle], @"New Window with unavailable Profile", @"Key binding action name shown when the referenced profile no longer exists");
            }
            break;
        case KEY_ACTION_NEW_TAB_WITH_PROFILE:
            if ([[ProfileModel sharedInstance] bookmarkWithGuid:_parameter]) {
                actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.NewTabWithProfile", nil, [NSBundle mainBundle], @"New Tab with “%@” Profile", @"Key binding action name; %@ is the profile name"), GetProfileName(_parameter)];
            } else {
                actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.NewTabWithUnavailableProfile", nil, [NSBundle mainBundle], @"New Tab with unavailable Profile", @"Key binding action name shown when the referenced profile no longer exists");
            }
            break;
        case KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE:
            if ([[ProfileModel sharedInstance] bookmarkWithGuid:_parameter]) {
                actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SplitHorizontallyWithProfile", nil, [NSBundle mainBundle], @"Split Horizontally with “%@” Profile", @"Key binding action name; %@ is the profile name"), GetProfileName(_parameter)];
            } else {
                actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SplitHorizontallyWithUnavailableProfile", nil, [NSBundle mainBundle], @"Split Horizontally with unavailable Profile", @"Key binding action name shown when the referenced profile no longer exists");
            }
            break;
        case KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE:
            if ([[ProfileModel sharedInstance] bookmarkWithGuid:_parameter]) {
                actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SplitVerticallyWithProfile", nil, [NSBundle mainBundle], @"Split Vertically with “%@” Profile", @"Key binding action name; %@ is the profile name"), GetProfileName(_parameter)];
            } else {
                actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SplitVerticallyWithUnavailableProfile", nil, [NSBundle mainBundle], @"Split Vertically with unavailable Profile", @"Key binding action name shown when the referenced profile no longer exists");
            }
            break;
        case KEY_ACTION_SET_PROFILE:
            if ([[ProfileModel sharedInstance] bookmarkWithGuid:_parameter]) {
                actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.ChangeProfileTo", nil, [NSBundle mainBundle], @"Change Profile to “%@”", @"Key binding action name; %@ is the profile name"), GetProfileName(_parameter)];
            } else {
                actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.ChangeProfileToUnavailable", nil, [NSBundle mainBundle], @"Change Profile to unavailable profile", @"Key binding action name shown when the referenced profile no longer exists");
            }
            break;
        case KEY_ACTION_LOAD_COLOR_PRESET:
            actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.LoadColorPreset", nil, [NSBundle mainBundle], @"Load Color Preset “%@”", @"Key binding action name; %@ is the color preset name"), _parameter];
            break;
        case KEY_ACTION_SEND_C_H_BACKSPACE:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SendCtrlHBackspace", nil, [NSBundle mainBundle], @"Send ^H Backspace", @"Key binding action name; ^H is a control character");
            break;
        case KEY_ACTION_SEND_C_QM_BACKSPACE:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SendCtrlQuestionBackspace", nil, [NSBundle mainBundle], @"Send ^? Backspace", @"Key binding action name; ^? is a control character");
            break;
        case KEY_ACTION_IGNORE:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.Ignore", nil, [NSBundle mainBundle], @"Ignore", @"Key binding action name; ignores the keystroke");
            break;
        case KEY_ACTION_BYPASS:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.BypassTerminal", nil, [NSBundle mainBundle], @"Bypass Terminal", @"Key binding action name");
            break;
        case KEY_ACTION_IR_FORWARD:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.UnsupportedCommand", nil, [NSBundle mainBundle], @"Unsupported Command", @"Key binding action name shown for a command that is no longer supported");
            break;
        case KEY_ACTION_IR_BACKWARD:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.StartInstantReplay", nil, [NSBundle mainBundle], @"Start Instant Replay", @"Key binding action name");
            break;
        case KEY_ACTION_SELECT_PANE_LEFT:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SelectSplitPaneOnLeft", nil, [NSBundle mainBundle], @"Select Split Pane on Left", @"Key binding action name");
            break;
        case KEY_ACTION_SELECT_PANE_RIGHT:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SelectSplitPaneOnRight", nil, [NSBundle mainBundle], @"Select Split Pane on Right", @"Key binding action name");
            break;
        case KEY_ACTION_SELECT_PANE_ABOVE:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SelectSplitPaneAbove", nil, [NSBundle mainBundle], @"Select Split Pane Above", @"Key binding action name");
            break;
        case KEY_ACTION_SELECT_PANE_BELOW:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SelectSplitPaneBelow", nil, [NSBundle mainBundle], @"Select Split Pane Below", @"Key binding action name");
            break;
        case KEY_ACTION_DO_NOT_REMAP_MODIFIERS:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.DoNotRemapModifiers", nil, [NSBundle mainBundle], @"Do Not Remap Modifiers", @"Key binding action name");
            break;
        case KEY_ACTION_REMAP_LOCALLY:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.RemapModifiersInITerm2Only", nil, [NSBundle mainBundle], @"Remap Modifiers in iTerm2 Only", @"Key binding action name");
            break;
        case KEY_ACTION_TOGGLE_FULLSCREEN:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.ToggleFullscreen", nil, [NSBundle mainBundle], @"Toggle Fullscreen", @"Key binding action name");
            break;
        case KEY_ACTION_TOGGLE_HOTKEY_WINDOW_PINNING:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.TogglePinHotkeyWindow", nil, [NSBundle mainBundle], @"Toggle Pin Hotkey Window", @"Key binding action name");
            break;
        case KEY_ACTION_UNDO:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.Undo", nil, [NSBundle mainBundle], @"Undo", @"Key binding action name");
            break;
        case KEY_ACTION_FIND_REGEX:
            actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.FindRegex", nil, [NSBundle mainBundle], @"Find Regex “%@”", @"Key binding action name; %@ is the regular expression to find"), _parameter];
            break;
        case KEY_FIND_AGAIN_DOWN:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.FindAgainDown", nil, [NSBundle mainBundle], @"Find Again Down", @"Key binding action name");
            break;
        case KEY_FIND_AGAIN_UP:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.FindAgainUp", nil, [NSBundle mainBundle], @"Find Again Up", @"Key binding action name");
            break;
        case KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION: {
            NSString *pasteDetails =
                [iTermPasteSpecialViewController descriptionForCodedSettings:_parameter];
            if (pasteDetails.length) {
                actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.PasteFromSelectionWithDetails", nil, [NSBundle mainBundle], @"Paste from Selection: %@", @"Key binding action name; %@ describes the paste-special settings"), pasteDetails];
            } else {
                actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.PasteFromSelection", nil, [NSBundle mainBundle], @"Paste from Selection", @"Key binding action name");
            }
            break;
        }
        case KEY_ACTION_PASTE_SPECIAL: {
            NSString *pasteDetails =
                [iTermPasteSpecialViewController descriptionForCodedSettings:_parameter];
            if (pasteDetails.length) {
                actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.PasteWithDetails", nil, [NSBundle mainBundle], @"Paste: %@", @"Key binding action name; %@ describes the paste-special settings"), pasteDetails];
            } else {
                actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.Paste", nil, [NSBundle mainBundle], @"Paste", @"Key binding action name");
            }
            break;
        }
        case KEY_ACTION_MOVE_END_OF_SELECTION_LEFT:
            actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.MoveEndOfSelectionLeft", nil, [NSBundle mainBundle], @"Move End of Selection Left %@", @"Key binding action name; %@ is a movement unit such as “By Word”"),
                            [self.class stringForSelectionMovementUnit:_parameter.integerValue]];
            break;
        case KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT:
            actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.MoveEndOfSelectionRight", nil, [NSBundle mainBundle], @"Move End of Selection Right %@", @"Key binding action name; %@ is a movement unit such as “By Word”"),
                            [self.class stringForSelectionMovementUnit:_parameter.integerValue]];
            break;
        case KEY_ACTION_MOVE_START_OF_SELECTION_LEFT:
            actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.MoveStartOfSelectionLeft", nil, [NSBundle mainBundle], @"Move Start of Selection Left %@", @"Key binding action name; %@ is a movement unit such as “By Word”"),
                            [self.class stringForSelectionMovementUnit:_parameter.integerValue]];
            break;
        case KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT:
            actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.MoveStartOfSelectionRight", nil, [NSBundle mainBundle], @"Move Start of Selection Right %@", @"Key binding action name; %@ is a movement unit such as “By Word”"),
                            [self.class stringForSelectionMovementUnit:_parameter.integerValue]];
            break;

        case KEY_ACTION_DECREASE_HEIGHT:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.DecreaseHeight", nil, [NSBundle mainBundle], @"Decrease Height", @"Key binding action name");
            break;
        case KEY_ACTION_INCREASE_HEIGHT:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.IncreaseHeight", nil, [NSBundle mainBundle], @"Increase Height", @"Key binding action name");
            break;

        case KEY_ACTION_DECREASE_WIDTH:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.DecreaseWidth", nil, [NSBundle mainBundle], @"Decrease Width", @"Key binding action name");
            break;
        case KEY_ACTION_INCREASE_WIDTH:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.IncreaseWidth", nil, [NSBundle mainBundle], @"Increase Width", @"Key binding action name");
            break;

        case KEY_ACTION_SWAP_PANE_LEFT:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SwapWithSplitPaneOnLeft", nil, [NSBundle mainBundle], @"Swap With Split Pane on Left", @"Key binding action name");
            break;
        case KEY_ACTION_SWAP_PANE_RIGHT:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SwapWithSplitPaneOnRight", nil, [NSBundle mainBundle], @"Swap With Split Pane on Right", @"Key binding action name");
            break;
        case KEY_ACTION_SWAP_PANE_ABOVE:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SwapWithSplitPaneAbove", nil, [NSBundle mainBundle], @"Swap With Split Pane Above", @"Key binding action name");
            break;
        case KEY_ACTION_SWAP_PANE_BELOW:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SwapWithSplitPaneBelow", nil, [NSBundle mainBundle], @"Swap With Split Pane Below", @"Key binding action name");
            break;
        case KEY_ACTION_TOGGLE_MOUSE_REPORTING:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.ToggleMouseReporting", nil, [NSBundle mainBundle], @"Toggle Mouse Reporting", @"Key binding action name");
            break;
        case KEY_ACTION_INVOKE_SCRIPT_FUNCTION:
            actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.CallFunction", nil, [NSBundle mainBundle], @"Call %@", @"Key binding action name; invokes a script function. %@ is the function invocation"), _parameter];
            break;
        case KEY_ACTION_DUPLICATE_TAB:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.DuplicateTab", nil, [NSBundle mainBundle], @"Duplicate Tab", @"Key binding action name");
            break;
        case KEY_ACTION_SEQUENCE: {
            NSArray<NSString *> *names = [[_parameter keyBindingActionsFromSequenceParameter] mapWithBlock:^id _Nullable(iTermKeyBindingAction * _Nonnull action) {
                return [action displayName];
            }];
            NSString *separator = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SequenceSeparator", nil, [NSBundle mainBundle], @", then ", @"Separator between actions in a key-binding sequence, as in “Action A, then Action B”");
            return [names componentsJoinedByString:separator];
        }
        default:
            actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.UnknownActionID", nil, [NSBundle mainBundle], @"Unknown Action ID %d", @"Key binding action name shown for an unrecognized action; %d is the numeric action identifier"), _keyAction];
            break;
        case KEY_ACTION_MOVE_TO_SPLIT_PANE:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.MoveToSplitPane", nil, [NSBundle mainBundle], @"Move to Split Pane", @"Key binding action name");
            break;
        case KEY_ACTION_SWAP_WITH_NEXT_PANE:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SwapWithNextPane", nil, [NSBundle mainBundle], @"Swap with Next Pane", @"Key binding action name");
            break;
        case KEY_ACTION_SWAP_WITH_PREVIOUS_PANE:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.SwapWithPreviousPane", nil, [NSBundle mainBundle], @"Swap with Previous Pane", @"Key binding action name");
            break;
        case KEY_ACTION_COPY_OR_SEND:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.CopyOrSend", nil, [NSBundle mainBundle], @"Copy Selection or Send ^C", @"Key binding action name; ^C is a control character");
            break;
        case KEY_ACTION_PASTE_OR_SEND:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.PasteOrSend", nil, [NSBundle mainBundle], @"Paste or Send ^V", @"Key binding action name; ^V is a control character");
            break;
        case KEY_ACTION_ALERT_ON_NEXT_MARK:
            actionString = NSLocalizedStringWithDefaultValue(@"KeyBindingAction.AlertOnNextMark", nil, [NSBundle mainBundle], @"Alert on Next Mark", @"Key binding action name");
            break;
        case KEY_ACTION_COPY_INTERPOLATED_STRING:
            actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.CopyInterpolatedString", nil, [NSBundle mainBundle], @"Copy Interpolated String “%@”", @"Key binding action name; %@ is the interpolated string expression"), _parameter];
            break;
        case KEY_ACTION_COPY_MODE:
            actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.CopyMode", nil, [NSBundle mainBundle], @"Copy mode: %@", @"Key binding action name; %@ is the copy-mode command"), _parameter];
            break;
        case KEY_ACTION_TOGGLE_SETTING:
            actionString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.ToggleSetting", nil, [NSBundle mainBundle], @"Toggle %@", @"Key binding action name; %@ is the name of the setting to toggle"), self.toggleSettingLabel];
            break;
    }

    switch (self.applyMode) {
        case iTermActionApplyModeCurrentSession:
            return actionString;
        case iTermActionApplyModeAllSessions:
            return [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.ApplyMode.AllSessions", nil, [NSBundle mainBundle], @"In all sessions, %@", @"Prefix applied to a key-binding action name when it targets all sessions; %@ is the action, as in “In all sessions, Next Tab”"), actionString];
        case iTermActionApplyModeUnfocusedSessions:
            return [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.ApplyMode.UnfocusedSessions", nil, [NSBundle mainBundle], @"In unfocused sessions, %@", @"Prefix applied to a key-binding action name when it targets unfocused sessions; %@ is the action"), actionString];
        case iTermActionApplyModeAllInWindow:
            return [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.ApplyMode.AllInWindow", nil, [NSBundle mainBundle], @"In all sessions in the window, %@", @"Prefix applied to a key-binding action name when it targets all sessions in the window; %@ is the action"), actionString];
        case iTermActionApplyModeAllInTab:
            return [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.ApplyMode.AllInTab", nil, [NSBundle mainBundle], @"In all sessions in the tab, %@", @"Prefix applied to a key-binding action name when it targets all sessions in the tab; %@ is the action"), actionString];
        case iTermActionApplyModeBroadcasting:
            return [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"KeyBindingAction.ApplyMode.Broadcasting", nil, [NSBundle mainBundle], @"In all broadcasted-to sessions, %@", @"Prefix applied to a key-binding action name when it targets broadcasted-to sessions; %@ is the action"), actionString];
    }
    return actionString;
}

- (BOOL)sendsText {
    switch (self.keyAction) {
        case KEY_ACTION_ESCAPE_SEQUENCE:
        case KEY_ACTION_HEX_CODE:
        case KEY_ACTION_TEXT:
        case KEY_ACTION_SEND_SNIPPET:
        case KEY_ACTION_COMPOSE:
        case KEY_ACTION_SEND_TMUX_COMMAND:
        case KEY_ACTION_VIM_TEXT:
        case KEY_ACTION_VIM_TEXT_NO_BROADCAST:
        case KEY_ACTION_RUN_COPROCESS:
        case KEY_ACTION_SEND_C_H_BACKSPACE:
        case KEY_ACTION_SEND_C_QM_BACKSPACE:
        case KEY_ACTION_PASTE_SPECIAL:
        case KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION:
        case KEY_ACTION_COPY_OR_SEND:
        case KEY_ACTION_PASTE_OR_SEND:
            return YES;
            
        case KEY_ACTION_IGNORE:
        case KEY_ACTION_BYPASS:
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
        case KEY_ACTION_SWAP_WITH_NEXT_PANE:
        case KEY_ACTION_SWAP_WITH_PREVIOUS_PANE:
        case KEY_ACTION_ALERT_ON_NEXT_MARK:
        case KEY_ACTION_COPY_INTERPOLATED_STRING:
        case KEY_ACTION_COPY_MODE:
        case KEY_ACTION_TOGGLE_SETTING:
            break;

        case KEY_ACTION_SEQUENCE:
            return [[self.parameter keyBindingActionsFromSequenceParameter] anyWithBlock:^BOOL(iTermKeyBindingAction *action) {
                return action.sendsText;
            }];
    }
    return NO;
}

- (BOOL)isActionable {
    switch (self.keyAction) {
        case KEY_ACTION_DO_NOT_REMAP_MODIFIERS:
        case KEY_ACTION_REMAP_LOCALLY:
        case KEY_ACTION_BYPASS:
            return NO;

        case KEY_ACTION_IGNORE:
        case KEY_ACTION_ESCAPE_SEQUENCE:
        case KEY_ACTION_HEX_CODE:
        case KEY_ACTION_TEXT:
        case KEY_ACTION_VIM_TEXT:
        case KEY_ACTION_VIM_TEXT_NO_BROADCAST:
        case KEY_ACTION_SEND_SNIPPET:
        case KEY_ACTION_COMPOSE:
        case KEY_ACTION_SEND_TMUX_COMMAND:
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
        case KEY_ACTION_SWAP_WITH_NEXT_PANE:
        case KEY_ACTION_SWAP_WITH_PREVIOUS_PANE:
        case KEY_ACTION_COPY_OR_SEND:
        case KEY_ACTION_PASTE_OR_SEND:
        case KEY_ACTION_ALERT_ON_NEXT_MARK:
        case KEY_ACTION_COPY_INTERPOLATED_STRING:
        case KEY_ACTION_COPY_MODE:
        case KEY_ACTION_TOGGLE_SETTING:
            break;

        case KEY_ACTION_SEQUENCE:
            return [[self.parameter keyBindingActionsFromSequenceParameter] anyWithBlock:^BOOL(iTermKeyBindingAction *action) {
                return action.isActionable;
            }];
    }
    return YES;
}

@end

@implementation NSString(iTermKeyBindingAction)

+ (instancetype)parameterForKeyBindingActionSequence:(NSArray<iTermKeyBindingAction *> *)actions {
    NSArray<NSDictionary *> *dicts = [actions mapWithBlock:^id _Nullable(iTermKeyBindingAction * _Nonnull action) {
        return action.dictionaryValue;
    }];
    NSData *data = [NSJSONSerialization dataWithJSONObject:dicts options:0 error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

- (NSArray<iTermKeyBindingAction *> *)keyBindingActionsFromSequenceParameter {
    NSArray<NSDictionary *> *dicts = [NSJSONSerialization JSONObjectWithData:[self dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![dicts isKindOfClass:[NSArray class]]) {
        return @[];
    }
    return [dicts mapWithBlock:^id _Nullable(NSDictionary * _Nonnull dict) {
        if (![dict isKindOfClass:[NSDictionary class]]) {
            return nil;
        }
        return [iTermKeyBindingAction withDictionary:dict];
    }];
}

@end

@implementation iTermKeyBindingAction(ParameterHelper)

- (NSDictionary *)toggleSettingDict {
    NSData *data = [self.parameter dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return nil;
    }
    NSDictionary *dict = [NSDictionary castFrom:[NSJSONSerialization JSONObjectWithData:data
                                                                                options:0
                                                                                  error:nil]];
    if (!dict) {
        return nil;
    }
    return dict;
}

- (NSString *)toggleSettingKey {
    return [NSString castFrom:self.toggleSettingDict[@"key"]];
}

- (NSString *)toggleSettingLabel {
    return [NSString castFrom:self.toggleSettingDict[@"label"]];
}

- (BOOL)toggleSettingIsProfile {
    return [[NSNumber castFrom:self.toggleSettingDict[@"isProfile"]] boolValue];
}

+ (NSString *)toggleSettingParameterForKey:(NSString *)key
                                 isProfile:(BOOL)isProfile
                                     label:(NSString *)label {
    NSDictionary *dict = @{ @"key": key,
                            @"isProfile": @(isProfile),
                            @"label": label };
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    if (!data) {
        return @"";
    }
    return [data stringWithEncoding:NSUTF8StringEncoding] ?: @"";
}

@end
