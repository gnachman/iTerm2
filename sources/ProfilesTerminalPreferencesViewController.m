//
//  ProfilesTerminalPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/17/14.
//
//

#import "ProfilesTerminalPreferencesViewController.h"

#import "ITAddressBookMgr.h"
#import "iTermController.h"
#import "iTermShellHistoryController.h"
#import "iTerm2SharedARC-Swift.h"

@implementation ProfilesTerminalPreferencesViewController {
    IBOutlet NSTextField *_numScrollbackLines;
    IBOutlet NSTextField *_numScrollbackLinesLabel;
    IBOutlet NSButton *_unlimitedScrollback;
    IBOutlet NSButton *_scrollbackWithStatusBar;
    IBOutlet NSButton *_scrollbackInAlternateScreen;
    IBOutlet NSPopUpButton *_characterEncoding;
    IBOutlet NSTextField *_characterEncodingLabel;
    IBOutlet NSComboBox *_terminalType;
    IBOutlet NSTextField *_terminalTypeLabel;
    IBOutlet NSTextField *_answerBackString;
    IBOutlet NSTextField *_answerBackStringLabel;
    IBOutlet NSButton *_xtermMouseReporting;
    IBOutlet NSButton *_xtermMouseReportingAllowMouseWheel;
    IBOutlet NSButton *_xtermMouseReportingAllowClicksAndDrags;
    IBOutlet NSButton *_allowTitleReporting;
    IBOutlet NSButton *_allowPasteBracketing;
    IBOutlet NSButton *_disablePrinting;
    IBOutlet NSButton *_disableAltScreen;
    IBOutlet NSButton *_disableWindowResizing;
    IBOutlet NSButton *_silenceBell;
    IBOutlet NSButton *_postNotifications;
    IBOutlet NSButton *_filterAlertsButton;
    IBOutlet NSButton *_flashingBell;
    IBOutlet NSButton *_bellIconInTabs;
    IBOutlet NSButton *_setLocaleVars;
    IBOutlet NSPopUpButton *_localeVars;
    IBOutlet NSTextField *_localeName;
    IBOutlet NSButton *_changeLocale;
    IBOutlet NSButton *_forceCommandPromptToFirstColumn;
    IBOutlet NSButton *_showMarkIndicators;
    IBOutlet NSButton *_showOffscreenCommandLine;
    IBOutlet NSButton *_allowCursorBlinkControlSequence;

    IBOutlet NSPanel *_filterAlertsPanel;
    IBOutlet NSButton *_bellAlert;
    IBOutlet NSButton *_idleAlert;
    IBOutlet NSButton *_newOutputAlert;
    IBOutlet NSButton *_sessionEndedAlert;
    IBOutlet NSButton *_terminalGeneratedAlerts;
    IBOutlet NSButton *_dragToScrollInAlternateScreenModeDisabled;
}

- (void)awakeFromNib {
    PreferenceInfo *info;
    __weak __typeof(self) weakSelf = self;
    info = [self defineControl:_numScrollbackLines
                           key:KEY_SCROLLBACK_LINES
                   relatedView:_numScrollbackLinesLabel
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(0, 10 * 1000 * 1000);
    info.deferUpdate = YES;
    
    info = [self defineControl:_unlimitedScrollback
                           key:KEY_UNLIMITED_SCROLLBACK
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        BOOL unlimited = [strongSelf boolForKey:KEY_UNLIMITED_SCROLLBACK];
        strongSelf->_numScrollbackLines.enabled = !unlimited;
        if (unlimited) {
            strongSelf->_numScrollbackLines.stringValue = @"";
        } else {
            strongSelf->_numScrollbackLines.intValue = [strongSelf intForKey:KEY_SCROLLBACK_LINES];
        }
    };

    [self defineControl:_scrollbackWithStatusBar
                    key:KEY_SCROLLBACK_WITH_STATUS_BAR
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_scrollbackInAlternateScreen
                    key:KEY_SCROLLBACK_IN_ALTERNATE_SCREEN
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_dragToScrollInAlternateScreenModeDisabled
                    key:KEY_DRAG_TO_SCROLL_IN_ALTERNATE_SCREEN_MODE_DISABLED
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self populateEncodings];
    info = [self defineControl:_characterEncoding
                           key:KEY_CHARACTER_ENCODING
                   relatedView:_characterEncodingLabel
                          type:kPreferenceInfoTypeUnsignedIntegerPopup];
    __weak __typeof(info) weakInfo = info;
    info.onUpdate = ^BOOL() {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return NO;
        }
        assert(weakInfo);
        NSUInteger tag = [self unsignedIntegerForKey:weakInfo.key];
        [strongSelf->_characterEncoding selectItemWithTag:tag];
        [strongSelf updateCustomLocaleControls];
        return YES;
    };

    // It's a combobox, but we can safely treat it as a string text field.
    [self defineControl:_terminalType
                    key:KEY_TERMINAL_TYPE
            relatedView:_terminalTypeLabel
                   type:kPreferenceInfoTypeStringTextField];

    [self defineControl:_answerBackString
                    key:KEY_ANSWERBACK_STRING
            relatedView:_answerBackStringLabel
                   type:kPreferenceInfoTypeStringTextField];

    info = [self defineControl:_xtermMouseReporting
                           key:KEY_XTERM_MOUSE_REPORTING
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf->_xtermMouseReportingAllowMouseWheel setEnabled:[strongSelf boolForKey:KEY_XTERM_MOUSE_REPORTING]];
        [strongSelf->_xtermMouseReportingAllowClicksAndDrags setEnabled:[strongSelf boolForKey:KEY_XTERM_MOUSE_REPORTING]];
    };

    [self defineControl:_xtermMouseReportingAllowMouseWheel
                    key:KEY_XTERM_MOUSE_REPORTING_ALLOW_MOUSE_WHEEL
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_xtermMouseReportingAllowClicksAndDrags
                    key:KEY_XTERM_MOUSE_REPORTING_ALLOW_CLICKS_AND_DRAGS
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_allowTitleReporting
                    key:KEY_ALLOW_TITLE_REPORTING
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_allowPasteBracketing
                    key:KEY_ALLOW_PASTE_BRACKETING
            displayName:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_disablePrinting
                    key:KEY_DISABLE_PRINTING
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_disableAltScreen
                    key:KEY_DISABLE_SMCUP_RMCUP
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_disableWindowResizing
                    key:KEY_DISABLE_WINDOW_RESIZING
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_allowCursorBlinkControlSequence
                    key:KEY_ALLOW_CHANGE_CURSOR_BLINK
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_silenceBell
                    key:KEY_SILENCE_BELL
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_postNotifications
                           key:KEY_BOOKMARK_USER_NOTIFICATIONS
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        BOOL sendNotifications = [self boolForKey:KEY_BOOKMARK_USER_NOTIFICATIONS];
        [strongSelf->_filterAlertsButton setEnabled:sendNotifications];
    };

    [self defineUnsearchableControl:_bellAlert
                                key:KEY_SEND_BELL_ALERT
                               type:kPreferenceInfoTypeCheckbox];
    [self defineUnsearchableControl:_idleAlert
                                key:KEY_SEND_IDLE_ALERT
                               type:kPreferenceInfoTypeCheckbox];
    [self defineUnsearchableControl:_newOutputAlert
                                key:KEY_SEND_NEW_OUTPUT_ALERT
                               type:kPreferenceInfoTypeCheckbox];
    [self defineUnsearchableControl:_sessionEndedAlert
                                key:KEY_SEND_SESSION_ENDED_ALERT
                               type:kPreferenceInfoTypeCheckbox];
    [self defineUnsearchableControl:_terminalGeneratedAlerts
                                key:KEY_SEND_TERMINAL_GENERATED_ALERT
                               type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_flashingBell
                    key:KEY_FLASHING_BELL
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_bellIconInTabs
                    key:KEY_VISUAL_BELL
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_localeVars
                           key:KEY_SET_LOCALE_VARS
                   relatedView:nil
                          type:kPreferenceInfoTypePopup];
    
    info.onUpdate = ^BOOL {
        [weakSelf updateCustomLocaleControls];
        return NO;
    };
    [self updateCustomLocaleControls];

    [self defineControl:_forceCommandPromptToFirstColumn
                    key:KEY_PLACE_PROMPT_AT_FIRST_COLUMN
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_showMarkIndicators
                    key:KEY_SHOW_MARK_INDICATORS
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_showOffscreenCommandLine
                    key:KEY_SHOW_OFFSCREEN_COMMANDLINE
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self addViewToSearchIndex:_filterAlertsButton
                   displayName:@"Filter alerts"
                       phrases:@[ @"bell", @"idle", @"session ended", @"new output"]
                           key:nil];
}

- (void)layoutSubviewsForEditCurrentSessionMode {
    _terminalType.enabled = NO;
    _setLocaleVars.enabled = NO;
}

- (NSAttributedString *)attributedStringForLocale:(NSString *)lang {
    NSString *title = [iTermLocaleGuesser titleForLocale:lang] ?: @"(No description available)";
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] init];
    NSFont *monoFont = [NSFont userFixedPitchFontOfSize:[NSFont systemFontSize]];
    NSAttributedString *langAS = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"LANG=%@", lang]
                                                                 attributes:@{ NSFontAttributeName: monoFont} ];
    NSAttributedString *titleAS = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\u2002\u2002\u2002%@", title]
                                                                  attributes:@{NSForegroundColorAttributeName: [[NSColor textColor] colorWithAlphaComponent:0.5] }];
    [attributedString appendAttributedString:langAS];
    [attributedString appendAttributedString:titleAS];
    return attributedString;
}

- (void)updateCustomLocaleControls {
    _changeLocale.hidden = YES;
    _localeName.stringValue = @"";

    switch ((iTermSetLocalVarsMode)[self unsignedIntegerForKey:KEY_SET_LOCALE_VARS]) {
        case iTermSetLocalVarsModeCustom: {
            _changeLocale.hidden = NO;
            if ([self stringForKey:KEY_CUSTOM_LOCALE].length) {
                _localeName.attributedStringValue = [self attributedStringForLocale:[self stringForKey:KEY_CUSTOM_LOCALE]];
            } else {
                _localeName.stringValue = @"No locale selected.";
            }
            break;
        }
        case iTermSetLocalVarsModeSetAutomatically: {
            _changeLocale.hidden = YES;
            iTermLocaleGuesser *localeGuesser = [[iTermLocaleGuesser alloc] initWithEncoding:[self unsignedIntegerForKey:KEY_CHARACTER_ENCODING]];
            NSString *lang = [localeGuesser valueForLanguageEnvironmentVariable];
            if (lang.length) {
                _localeName.attributedStringValue = [self attributedStringForLocale:lang];
            } else {
                _localeName.stringValue = @"No valid locale exists for this machine’s language and country.";
            }
            break;
        }
        case iTermSetLocalVarsModeDoNotSet:
            _changeLocale.hidden = YES;
            _localeName.stringValue = @"$LANG will not be set.";
            break;
    }
}

#pragma mark - Character Encoding

- (void)populateEncodings {
    [_characterEncoding removeAllItems];
    for (NSNumber *anEncoding in [self sortedEncodings]) {
        NSString *theTitle = [NSString localizedNameOfStringEncoding:[anEncoding unsignedIntValue]];
        [_characterEncoding addItemWithTitle:theTitle];
        [[_characterEncoding lastItem] setTag:[anEncoding unsignedIntValue]];
    }
}

// Comparator for sorting encodings
static NSInteger CompareEncodingByLocalizedName(id a, id b, void *unused) {
    NSString *localizedA = [NSString localizedNameOfStringEncoding:[a unsignedIntValue]];
    NSString *localizedB = [NSString localizedNameOfStringEncoding:[b unsignedIntValue]];
    return [localizedA caseInsensitiveCompare:localizedB];
}

- (NSArray *)sortedEncodings {
    NSStringEncoding const *encodingPtr;
    NSMutableArray *encodings = [NSMutableArray array];

    for (encodingPtr = [NSString availableStringEncodings]; *encodingPtr; ++encodingPtr) {
        [encodings addObject:@(*encodingPtr)];
    }
    [encodings sortUsingFunction:CompareEncodingByLocalizedName context:NULL];

    return encodings;
}


#pragma mark - Action

- (IBAction)help:(id)sender {
    [iTermShellHistoryController showInformationalMessageInWindow:self.view.window];
}

- (IBAction)showFilterAlertsPanel:(id)sender {
    __weak __typeof(self) weakSelf = self;
    [self.view.window beginSheet:_filterAlertsPanel completionHandler:^(NSModalResponse returnCode) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf->_filterAlertsPanel close];
        }
    }];
}

- (IBAction)closeFilterAlertsPanel:(id)sender {
    [_filterAlertsPanel.sheetParent endSheet:_filterAlertsPanel];
}

- (IBAction)changeCustomLocale:(id)sender {
    iTermLocalePrompt *prompt = [[iTermLocalePrompt alloc] init];
    prompt.defaultLocale = [self stringForKey:KEY_CUSTOM_LOCALE];
    prompt.message = @"Select your preferred locale:";
    prompt.allowRemember = NO;
    [prompt requestLocaleFromUserForProfile:nil inWindow:self.view.window];
    NSString *locale = prompt.selectedLocale;
    if (locale) {
        [self setString:locale forKey:KEY_CUSTOM_LOCALE];
        [self updateCustomLocaleControls];
    }
}

@end
