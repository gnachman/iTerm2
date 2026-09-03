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
            return ITLocalize(@"KeyBindingAction_Facing_ByLine", @"By Line", @"Text shown in stringForSelectionMovementUnit:: By Line");
        case kPTYTextViewSelectionExtensionUnitCharacter:
            return ITLocalize(@"KeyBindingAction_Facing_ByCharacter", @"By Character", @"Text shown in stringForSelectionMovementUnit:: By Character");
        case kPTYTextViewSelectionExtensionUnitWord:
            return ITLocalize(@"KeyBindingAction_Facing_ByWord", @"By Word", @"Text shown in stringForSelectionMovementUnit:: By Word");
        case kPTYTextViewSelectionExtensionUnitBigWord:
            return ITLocalize(@"KeyBindingAction_Facing_ByWord_2", @"By WORD", @"Text shown in stringForSelectionMovementUnit:: By WORD");
        case kPTYTextViewSelectionExtensionUnitMark:
            return ITLocalize(@"KeyBindingAction_Facing_ByMark", @"By Mark", @"Text shown in stringForSelectionMovementUnit:: By Mark");
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
            actionString = ITLocalize(@"KeyBindingAction_Action_MoveTabLeft", @"Move Tab Left", @"Action title in displayName");
            break;
        case KEY_ACTION_MOVE_TAB_RIGHT:
            actionString = ITLocalize(@"KeyBindingAction_Action_MoveTabRight", @"Move Tab Right", @"Action title in displayName");
            break;
        case KEY_ACTION_NEXT_MRU_TAB:
            actionString = ITLocalize(@"KeyBindingAction_Action_CycleTabsForward", @"Cycle Tabs Forward", @"Action title in displayName");
            break;
        case KEY_ACTION_PREVIOUS_MRU_TAB:
            actionString = ITLocalize(@"KeyBindingAction_Action_CycleTabsBackward", @"Cycle Tabs Backward", @"Action title in displayName");
            break;
        case KEY_ACTION_NEXT_PANE:
            actionString = ITLocalize(@"KeyBindingAction_Action_NextPane", @"Next Pane", @"Action title in displayName");
            break;
        case KEY_ACTION_PREVIOUS_PANE:
            actionString = ITLocalize(@"KeyBindingAction_Action_PreviousPane", @"Previous Pane", @"Action title in displayName");
            break;
        case KEY_ACTION_NEXT_SESSION:
            actionString = ITLocalize(@"KeyBindingAction_Action_NextTab", @"Next Tab", @"Action title in displayName");
            break;
        case KEY_ACTION_NEXT_WINDOW:
            actionString = ITLocalize(@"KeyBindingAction_Action_NextWindow", @"Next Window", @"Action title in displayName");
            break;
        case KEY_ACTION_PREVIOUS_SESSION:
            actionString = ITLocalize(@"KeyBindingAction_Action_PreviousTab", @"Previous Tab", @"Action title in displayName");
            break;
        case KEY_ACTION_PREVIOUS_WINDOW:
            actionString = ITLocalize(@"KeyBindingAction_Action_PreviousWindow", @"Previous Window", @"Action title in displayName");
            break;
        case KEY_ACTION_SCROLL_END:
            actionString = ITLocalize(@"KeyBindingAction_Action_ScrollToEnd", @"Scroll To End", @"Action title in displayName");
            break;
        case KEY_ACTION_SCROLL_HOME:
            actionString = ITLocalize(@"KeyBindingAction_Action_ScrollToTop", @"Scroll To Top", @"Action title in displayName");
            break;
        case KEY_ACTION_SCROLL_LINE_DOWN:
            actionString = ITLocalize(@"KeyBindingAction_Action_ScrollOneLineDown", @"Scroll One Line Down", @"Action title in displayName");
            break;
        case KEY_ACTION_SCROLL_LINE_UP:
            actionString = ITLocalize(@"KeyBindingAction_Action_ScrollOneLineUp", @"Scroll One Line Up", @"Action title in displayName");
            break;
        case KEY_ACTION_SCROLL_PAGE_DOWN:
            actionString = ITLocalize(@"KeyBindingAction_Action_ScrollOnePageDown", @"Scroll One Page Down", @"Action title in displayName");
            break;
        case KEY_ACTION_SCROLL_PAGE_UP:
            actionString = ITLocalize(@"KeyBindingAction_Action_ScrollOnePageUp", @"Scroll One Page Up", @"Action title in displayName");
            break;
        case KEY_ACTION_ESCAPE_SEQUENCE:
            actionString = [NSString stringWithFormat:@"%@ %@", ITLocalize(@"KeyBindingAction_Action_Send", @"Send ^[", @"Action title in displayName"), _parameter];
            break;
        case KEY_ACTION_HEX_CODE:
            actionString = [NSString stringWithFormat: @"%@ %@", ITLocalize(@"KeyBindingAction_Action_SendHexCodes", @"Send Hex Codes:", @"Action title in displayName"), _parameter];
            break;
        case KEY_ACTION_VIM_TEXT:
            actionString = [NSString stringWithFormat:@"%@ \"%@\"", ITLocalize(@"KeyBindingAction_Action_Send_2", @"Send:", @"Action title in displayName"), _parameter];
            break;
        case KEY_ACTION_VIM_TEXT_NO_BROADCAST:
            actionString = [NSString stringWithFormat:@"%@ \"%@\"", ITLocalize(@"KeyBindingAction_Action_SendNoBroadcast", @"Send (no broadcast):", @"Action title in displayName"), _parameter];
            break;
        case KEY_ACTION_TEXT:
            actionString = [NSString stringWithFormat:@"%@ \"%@\"", ITLocalize(@"KeyBindingAction_Action_Send_2", @"Send:", @"Action title in displayName"), _parameter];
            break;
        case KEY_ACTION_SEND_SNIPPET: {
            iTermSnippet *snippet = [[iTermSnippetsModel sharedInstance] snippetWithActionKey:_parameter];
            if (snippet) {
                actionString = [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_Action_SendSnippet_FORMAT", @"Send Snippet “%1$@”", @"Action title in displayName"), snippet.displayTitle];
            } else {
                actionString = ITLocalize(@"KeyBindingAction_Action_SendDeletedSnippetNoAction", @"Send Deleted Snippet (no action)", @"Action title in displayName");
            }
            break;
        }
        case KEY_ACTION_COMPOSE:
            actionString = [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_Action_Compose_FORMAT", @"Compose “%1$@”", @"Action title in displayName"), _parameter];
            break;
        case KEY_ACTION_SEND_TMUX_COMMAND:
            actionString = [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_Action_Tmux_FORMAT", @"tmux: %1$@", @"Action title in displayName"), _parameter];
            break;
        case KEY_ACTION_RUN_COPROCESS:
            actionString = [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_Action_RunCoprocess_FORMAT", @"Run Coprocess \"%1$@\"", @"Action title in displayName"),
						    _parameter];
            break;
        case KEY_ACTION_SELECT_MENU_ITEM: {
            NSArray *parts = [_parameter componentsSeparatedByString:@"\n"];
            actionString = [NSString stringWithFormat:@"%@ “%@”", ITLocalize(@"KeyBindingAction_Action_SelectMenuItem", @"Select Menu Item", @"Action title in displayName"), parts.firstObject];
            break;
        }
        case KEY_ACTION_NEW_WINDOW_WITH_PROFILE:
            if ([[ProfileModel sharedInstance] bookmarkWithGuid:_parameter]) {
                actionString = [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_Action_NewWindowWithProfile_FORMAT", @"New Window with \"%1$@\" Profile", @"Action title in displayName"), GetProfileName(_parameter)];
            } else {
                actionString = ITLocalize(@"KeyBindingAction_Action_NewWindowWithUnavailableProfile", @"New Window with unavailable Profile", @"Action title in displayName");
            }
            break;
        case KEY_ACTION_NEW_TAB_WITH_PROFILE:
            if ([[ProfileModel sharedInstance] bookmarkWithGuid:_parameter]) {
                actionString = [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_Action_NewTabWithProfile_FORMAT", @"New Tab with \"%1$@\" Profile", @"Action title in displayName"), GetProfileName(_parameter)];
            } else {
                actionString = ITLocalize(@"KeyBindingAction_Action_NewTabWithUnavailableProfile", @"New Tab with unavailable Profile", @"Action title in displayName");
            }
            break;
        case KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE:
            if ([[ProfileModel sharedInstance] bookmarkWithGuid:_parameter]) {
                actionString = [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_Action_SplitHorizontallyWithProfile_FORMAT", @"Split Horizontally with \"%1$@\" Profile", @"Action title in displayName"), GetProfileName(_parameter)];
            } else {
                actionString = ITLocalize(@"KeyBindingAction_Action_SplitHorizontallyWithUnavailableProfile", @"Split Horizontally with unavailable Profile", @"Action title in displayName");
            }
            break;
        case KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE:
            if ([[ProfileModel sharedInstance] bookmarkWithGuid:_parameter]) {
                actionString = [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_Action_SplitVerticallyWithProfile_FORMAT", @"Split Vertically with \"%1$@\" Profile", @"Action title in displayName"), GetProfileName(_parameter)];
            } else {
                actionString = ITLocalize(@"KeyBindingAction_Action_SplitVerticallyWithUnavailableProfile", @"Split Vertically with unavailable Profile", @"Action title in displayName");
            }
            break;
        case KEY_ACTION_SET_PROFILE:
            if ([[ProfileModel sharedInstance] bookmarkWithGuid:_parameter]) {
                actionString = [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_Action_ChangeProfileTo_FORMAT", @"Change Profile to \"%1$@\"", @"Action title in displayName"), GetProfileName(_parameter)];
            } else {
                actionString = ITLocalize(@"KeyBindingAction_Action_ChangeProfileToUnavailableProfile", @"Change Profile to unavailable profile", @"Action title in displayName");
            }
            break;
        case KEY_ACTION_LOAD_COLOR_PRESET:
            actionString = [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_Action_LoadColorPreset_FORMAT", @"Load Color Preset \"%1$@\"", @"Action title in displayName"), _parameter];
            break;
        case KEY_ACTION_SEND_C_H_BACKSPACE:
            actionString = ITLocalize(@"KeyBindingAction_Action_SendHBackspace", @"Send ^H Backspace", @"Action title in displayName");
            break;
        case KEY_ACTION_SEND_C_QM_BACKSPACE:
            actionString = ITLocalize(@"KeyBindingAction_Action_SendBackspace", @"Send ^? Backspace", @"Action title in displayName");
            break;
        case KEY_ACTION_IGNORE:
            actionString = ITLocalize(@"KeyBindingAction_Action_Ignore", @"Ignore", @"Action title in displayName");
            break;
        case KEY_ACTION_BYPASS:
            actionString = ITLocalize(@"KeyBindingAction_Action_BypassTerminal", @"Bypass Terminal", @"Action title in displayName");
            break;
        case KEY_ACTION_IR_FORWARD:
            actionString = ITLocalize(@"KeyBindingAction_Action_UnsupportedCommand", @"Unsupported Command", @"Action title in displayName");
            break;
        case KEY_ACTION_IR_BACKWARD:
            actionString = ITLocalize(@"KeyBindingAction_Action_StartInstantReplay", @"Start Instant Replay", @"Action title in displayName");
            break;
        case KEY_ACTION_SELECT_PANE_LEFT:
            actionString = ITLocalize(@"KeyBindingAction_Action_SelectSplitPaneOnLeft", @"Select Split Pane on Left", @"Action title in displayName");
            break;
        case KEY_ACTION_SELECT_PANE_RIGHT:
            actionString = ITLocalize(@"KeyBindingAction_Action_SelectSplitPaneOnRight", @"Select Split Pane on Right", @"Action title in displayName");
            break;
        case KEY_ACTION_SELECT_PANE_ABOVE:
            actionString = ITLocalize(@"KeyBindingAction_Action_SelectSplitPaneAbove", @"Select Split Pane Above", @"Action title in displayName");
            break;
        case KEY_ACTION_SELECT_PANE_BELOW:
            actionString = ITLocalize(@"KeyBindingAction_Action_SelectSplitPaneBelow", @"Select Split Pane Below", @"Action title in displayName");
            break;
        case KEY_ACTION_DO_NOT_REMAP_MODIFIERS:
            actionString = ITLocalize(@"KeyBindingAction_Action_DoNotRemapModifiers", @"Do Not Remap Modifiers", @"Action title in displayName");
            break;
        case KEY_ACTION_REMAP_LOCALLY:
            actionString = ITLocalize(@"KeyBindingAction_Action_RemapModifiersInITerm2Only", @"Remap Modifiers in iTerm2 Only", @"Action title in displayName");
            break;
        case KEY_ACTION_TOGGLE_FULLSCREEN:
            actionString = ITLocalize(@"KeyBindingAction_Action_ToggleFullscreen", @"Toggle Fullscreen", @"Action title in displayName");
            break;
        case KEY_ACTION_TOGGLE_HOTKEY_WINDOW_PINNING:
            actionString = ITLocalize(@"KeyBindingAction_Action_TogglePinHotkeyWindow", @"Toggle Pin Hotkey Window", @"Action title in displayName");
            break;
        case KEY_ACTION_UNDO:
            actionString = ITLocalize(@"KeyBindingAction_Action_Undo", @"Undo", @"Action title in displayName");
            break;
        case KEY_ACTION_FIND_REGEX:
            actionString = [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_Action_FindRegex_FORMAT", @"Find Regex “%1$@”", @"Action title in displayName"), _parameter];
            break;
        case KEY_FIND_AGAIN_DOWN:
            actionString = ITLocalize(@"KeyBindingAction_Action_FindAgainDown", @"Find Again Down", @"Action title in displayName");
            break;
        case KEY_FIND_AGAIN_UP:
            actionString = ITLocalize(@"KeyBindingAction_Action_FindAgainUp", @"Find Again Up", @"Action title in displayName");
            break;
        case KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION: {
            NSString *pasteDetails =
                [iTermPasteSpecialViewController descriptionForCodedSettings:_parameter];
            if (pasteDetails.length) {
                actionString = [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_Action_PasteFromSelection_FORMAT", @"Paste from Selection: %1$@", @"Action title in displayName"), pasteDetails];
            } else {
                actionString = ITLocalize(@"KeyBindingAction_Action_PasteFromSelection", @"Paste from Selection", @"Action title in displayName");
            }
            break;
        }
        case KEY_ACTION_PASTE_SPECIAL: {
            NSString *pasteDetails =
                [iTermPasteSpecialViewController descriptionForCodedSettings:_parameter];
            if (pasteDetails.length) {
                actionString = [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_Action_Paste_FORMAT", @"Paste: %1$@", @"Action title in displayName"), pasteDetails];
            } else {
                actionString = ITLocalize(@"COMMON_PASTE", @"Paste", @"Action title in displayName");
            }
            break;
        }
        case KEY_ACTION_MOVE_END_OF_SELECTION_LEFT:
            actionString = [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_Action_MoveEndOfSelectionLeft_FORMAT", @"Move End of Selection Left %1$@", @"Action title in displayName"),
                            [self.class stringForSelectionMovementUnit:_parameter.integerValue]];
            break;
        case KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT:
            actionString = [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_Action_MoveEndOfSelectionRight_FORMAT", @"Move End of Selection Right %1$@", @"Action title in displayName"),
                            [self.class stringForSelectionMovementUnit:_parameter.integerValue]];
            break;
        case KEY_ACTION_MOVE_START_OF_SELECTION_LEFT:
            actionString = [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_Action_MoveStartOfSelectionLeft_FORMAT", @"Move Start of Selection Left %1$@", @"Action title in displayName"),
                            [self.class stringForSelectionMovementUnit:_parameter.integerValue]];
            break;
        case KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT:
            actionString = [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_Action_MoveStartOfSelectionRight_FORMAT", @"Move Start of Selection Right %1$@", @"Action title in displayName"),
                            [self.class stringForSelectionMovementUnit:_parameter.integerValue]];
            break;

        case KEY_ACTION_DECREASE_HEIGHT:
            actionString = ITLocalize(@"KeyBindingAction_Action_DecreaseHeight", @"Decrease Height", @"Action title in displayName");
            break;
        case KEY_ACTION_INCREASE_HEIGHT:
            actionString = ITLocalize(@"KeyBindingAction_Action_IncreaseHeight", @"Increase Height", @"Action title in displayName");
            break;

        case KEY_ACTION_DECREASE_WIDTH:
            actionString = ITLocalize(@"KeyBindingAction_Action_DecreaseWidth", @"Decrease Width", @"Action title in displayName");
            break;
        case KEY_ACTION_INCREASE_WIDTH:
            actionString = ITLocalize(@"KeyBindingAction_Action_IncreaseWidth", @"Increase Width", @"Action title in displayName");
            break;

        case KEY_ACTION_SWAP_PANE_LEFT:
            actionString = ITLocalize(@"KeyBindingAction_Action_SwapWithSplitPaneOnLeft", @"Swap With Split Pane on Left", @"Action title in displayName");
            break;
        case KEY_ACTION_SWAP_PANE_RIGHT:
            actionString = ITLocalize(@"KeyBindingAction_Action_SwapWithSplitPaneOnRight", @"Swap With Split Pane on Right", @"Action title in displayName");
            break;
        case KEY_ACTION_SWAP_PANE_ABOVE:
            actionString = ITLocalize(@"KeyBindingAction_Action_SwapWithSplitPaneAbove", @"Swap With Split Pane Above", @"Action title in displayName");
            break;
        case KEY_ACTION_SWAP_PANE_BELOW:
            actionString = ITLocalize(@"KeyBindingAction_Action_SwapWithSplitPaneBelow", @"Swap With Split Pane Below", @"Action title in displayName");
            break;
        case KEY_ACTION_TOGGLE_MOUSE_REPORTING:
            actionString = ITLocalize(@"KeyBindingAction_Action_ToggleMouseReporting", @"Toggle Mouse Reporting", @"Action title in displayName");
            break;
        case KEY_ACTION_INVOKE_SCRIPT_FUNCTION:
            actionString = [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_Action_Call_FORMAT", @"Call %1$@", @"Action title in displayName"), _parameter];
            break;
        case KEY_ACTION_DUPLICATE_TAB:
            actionString = ITLocalize(@"KeyBindingAction_Action_DuplicateTab", @"Duplicate Tab", @"Action title in displayName");
            break;
        case KEY_ACTION_SEQUENCE: {
            NSArray<NSString *> *names = [[_parameter keyBindingActionsFromSequenceParameter] mapWithBlock:^id _Nullable(iTermKeyBindingAction * _Nonnull action) {
                return [action displayName];
            }];
            return [names componentsJoinedByString:ITLocalize(@"KeyBindingAction_Facing_Then", @", then ", @"Text shown in displayName: , then ")];
        }
        default:
            actionString = [NSString stringWithFormat: @"%@ %d", ITLocalize(@"KeyBindingAction_Action_UnknownActionId", @"Unknown Action ID", @"Action title in displayName"), _keyAction];
            break;
        case KEY_ACTION_MOVE_TO_SPLIT_PANE:
            actionString = ITLocalize(@"KeyBindingAction_Action_MoveToSplitPane", @"Move to Split Pane", @"Action title in displayName");
            break;
        case KEY_ACTION_SWAP_WITH_NEXT_PANE:
            actionString = ITLocalize(@"KeyBindingAction_Action_SwapWithNextPane", @"Swap with Next Pane", @"Action title in displayName");
            break;
        case KEY_ACTION_SWAP_WITH_PREVIOUS_PANE:
            actionString = ITLocalize(@"KeyBindingAction_Action_SwapWithPreviousPane", @"Swap with Previous Pane", @"Action title in displayName");
            break;
        case KEY_ACTION_COPY_OR_SEND:
            actionString = ITLocalize(@"KeyBindingAction_Action_CopySelectionOrSendC", @"Copy Selection or Send ^C", @"Action title in displayName");
            break;
        case KEY_ACTION_PASTE_OR_SEND:
            actionString = ITLocalize(@"KeyBindingAction_Action_PasteOrSendV", @"Paste or Send ^V", @"Action title in displayName");
            break;
        case KEY_ACTION_ALERT_ON_NEXT_MARK:
            actionString = ITLocalize(@"KeyBindingAction_Action_AlertOnNextMark", @"Alert on Next Mark", @"Action title in displayName");
            break;
        case KEY_ACTION_COPY_INTERPOLATED_STRING:
            actionString = [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_Action_CopyInterpolatedString_FORMAT", @"Copy Interpolated String “%1$@”", @"Action title in displayName"), _parameter];
            break;
        case KEY_ACTION_COPY_MODE:
            actionString = [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_Action_CopyMode_FORMAT", @"Copy mode: %1$@", @"Action title in displayName"), _parameter];
            break;
        case KEY_ACTION_TOGGLE_SETTING:
            actionString = [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_Action_Toggle_FORMAT", @"Toggle %1$@", @"Action title in displayName"), self.toggleSettingLabel];
            break;
    }

    switch (self.applyMode) {
        case iTermActionApplyModeCurrentSession:
            return actionString;
        case iTermActionApplyModeAllSessions:
            return [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_FormattedFacing_InAllSessions_FORMAT", @"In all sessions, %1$@",@"Formatted user-facing text in displayName"), actionString];
        case iTermActionApplyModeUnfocusedSessions:
            return [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_FormattedFacing_InUnfocusedSessions_FORMAT", @"In unfocused sessions, %1$@",@"Formatted user-facing text in displayName"), actionString];
        case iTermActionApplyModeAllInWindow:
            return [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_FormattedFacing_InAllSessionsInTheWindow_FORMAT", @"In all sessions in the window, %1$@",@"Formatted user-facing text in displayName"), actionString];
        case iTermActionApplyModeAllInTab:
            return [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_FormattedFacing_InAllSessionsInTheTab_FORMAT", @"In all sessions in the tab, %1$@",@"Formatted user-facing text in displayName"), actionString];
        case iTermActionApplyModeBroadcasting:
            return [NSString stringWithFormat:ITLocalize(@"KeyBindingAction_FormattedFacing_InAllBroadcastedToSessions_FORMAT", @"In all broadcasted-to sessions, %1$@",@"Formatted user-facing text in displayName"), actionString];
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
