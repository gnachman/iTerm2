//
//  PointerPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "PointerPreferencesViewController.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "NSObject+iTerm.h"
#import "PreferencePanel.h"

NSString *const kPointerPrefsChangedNotification = @"kPointerPrefsChangedNotification";
NSString *const kPointerPrefsSemanticHistoryEnabledChangedNotification = @"kPointerPrefsSemanticHistoryEnabledChangedNotification";

@implementation PointerPreferencesViewController {
    IBOutlet NSTabView *_tabView;

    // Cmd-click to launch url.
    IBOutlet NSButton *_cmdSelection;

    // Control-click doesn't open the context menu, is mouse-reported as right click.
    IBOutlet NSButton *_controlLeftClickActsLikeRightClick;
    IBOutlet NSButton *_rightClickActsLikeRightClick;

    // Opt-click moves cursor.
    IBOutlet NSButton *_optionClickMovesCursor;

    // Three finger click emulates middle button.
    IBOutlet NSButton *_threeFingerEmulatesMiddle;

    // Focus follows mouse.
    IBOutlet NSButton *_focusFollowsMouse;
    IBOutlet NSButton *_focusFollowsMouseIncludingSubviews;

    // Focus on right or middle click
    IBOutlet NSButton *_focusOnRightOrMiddleClick;

    IBOutlet NSButton *_reportHorizontalScrollEvents;

    // Quick Look.
    IBOutlet NSButton *_quickLookUsesBrowserEngine;
    IBOutlet NSTextField *_quickLookPluginNote;
    IBOutlet NSPopUpButton *_quickLookHoverMode;
    IBOutlet NSTextField *_quickLookHoverDelay;
    IBOutlet NSTextField *_quickLookHoverAutoCloseDelay;
    // Not bound to a key of its own: checked means the close delay is 0 (never close).
    IBOutlet NSButton *_quickLookHoverNeverClose;
    IBOutlet NSTextField *_quickLookHoverDomainAllowlist;
    PreferenceInfo *_quickLookHoverAutoCloseDelayInfo;
}

- (void)awakeFromNib {
    PreferenceInfo *info;

    __weak __typeof(self) weakSelf = self;
    info = [self defineControl:_cmdSelection
                           key:kPreferenceKeyCmdClickOpensURLs
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() {
        [[NSNotificationCenter defaultCenter] postNotificationName:kPointerPrefsSemanticHistoryEnabledChangedNotification
                                                            object:nil];
    };

    [self defineControl:_controlLeftClickActsLikeRightClick
                    key:kPreferenceKeyControlLeftClickBypassesContextMenu
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_rightClickActsLikeRightClick
                    key:kPreferenceKeyRightClickClickBypassesContextMenu
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_optionClickMovesCursor
                    key:kPreferenceKeyOptionClickMovesCursor
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_threeFingerEmulatesMiddle
                           key:kPreferenceKeyThreeFingerEmulatesMiddle
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() {
        [weakSelf postRefreshNotification];
        [[NSNotificationCenter defaultCenter] postNotificationName:kPointerPrefsChangedNotification
                                                            object:nil
                                                          userInfo:nil];
    };

    [self defineControl:_focusFollowsMouse
                    key:kPreferenceKeyFocusFollowsMouse
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    info = [self defineControl:_focusFollowsMouseIncludingSubviews
                           key:kPreferenceKeyFocusFollowsMouseIncludingSubviews
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.shouldBeEnabled = ^BOOL {
        return [weakSelf boolForKey:kPreferenceKeyFocusFollowsMouse];
    };
    [info addShouldBeEnabledDependencyOnSetting:kPreferenceKeyFocusFollowsMouse
                                     controller:self];
    // defineControl: already updated the enabled state, before shouldBeEnabled existed.
    [self updateEnabledStateForInfo:info];
    [self defineControl:_focusOnRightOrMiddleClick
                    key:kPreferenceKeyFocusOnRightOrMiddleClick
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_reportHorizontalScrollEvents
                    key:kPreferenceKeyReportHorizontalScrollEvents
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineQuickLookControls];
}

- (void)defineQuickLookControls {
    __weak __typeof(self) weakSelf = self;
    PreferenceInfo *info;

    info = [self defineControl:_quickLookUsesBrowserEngine
                           key:kPreferenceKeyQuickLookUsesBrowserEngine
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [weakSelf updateQuickLookPluginNote];
    };

    info = [self defineControl:_quickLookHoverMode
                           key:kPreferenceKeyQuickLookHoverMode
                   relatedView:nil
                          type:kPreferenceInfoTypePopup];
    info.observer = ^{
        // The dependencies below catch changes made elsewhere, but they are delivered
        // asynchronously. Update right away when the change comes from this pane.
        [weakSelf updateEnabledState];
        [weakSelf updateQuickLookNeverClose];
    };

    BOOL (^hoverIsOn)(void) = ^BOOL{
        return [weakSelf intForKey:kPreferenceKeyQuickLookHoverMode] != iTermQuickLookHoverModeOff;
    };

    info = [self defineSecondsField:_quickLookHoverDelay key:kPreferenceKeyQuickLookHoverDelay];
    [self setShouldBeEnabled:hoverIsOn
                     forInfo:info
                dependencies:@[ kPreferenceKeyQuickLookHoverMode ]];

    info = [self defineSecondsField:_quickLookHoverAutoCloseDelay key:kPreferenceKeyQuickLookHoverAutoCloseDelay];
    info.observer = ^{
        [weakSelf updateQuickLookNeverClose];
    };
    // Deliberately not dependent on its own key: typing 0 must not disable the field mid-edit.
    // “Never” updates it explicitly.
    [self setShouldBeEnabled:^BOOL{
        return hoverIsOn() && [weakSelf doubleForKey:kPreferenceKeyQuickLookHoverAutoCloseDelay] > 0;
    }
                     forInfo:info
                dependencies:@[ kPreferenceKeyQuickLookHoverMode ]];
    _quickLookHoverAutoCloseDelayInfo = info;

    info = [self defineControl:_quickLookHoverDomainAllowlist
                           key:kPreferenceKeyQuickLookHoverDomainAllowlist
                   relatedView:nil
                          type:kPreferenceInfoTypeStringTextField];
    [self setShouldBeEnabled:hoverIsOn
                     forInfo:info
                dependencies:@[ kPreferenceKeyQuickLookHoverMode ]];

    [self updateQuickLookPluginNote];
    [self updateQuickLookNeverClose];
}

static NSNumberFormatter *PointerPreferencesSecondsFormatter(NSLocale *locale) {
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.locale = locale;
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.usesGroupingSeparator = NO;
    formatter.maximumFractionDigits = 3;
    return formatter;
}

+ (NSNumber *)quickLookSecondsFromString:(NSString *)string locale:(NSLocale *)locale {
    NSString *trimmed = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSNumber *number = [PointerPreferencesSecondsFormatter(locale) numberFromString:trimmed];
    if (number) {
        return number;
    }
    // Accept a period as the decimal separator in every locale.
    return [PointerPreferencesSecondsFormatter([NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]) numberFromString:trimmed];
}

+ (NSString *)quickLookStringFromSeconds:(double)seconds locale:(NSLocale *)locale {
    return [PointerPreferencesSecondsFormatter(locale) stringFromNumber:@(seconds)];
}

// Defines a field holding a number of seconds, read and shown with the user’s decimal separator.
// Custom get/set blocks are supplied so the non-integer default is not type-checked against
// kPreferenceInfoTypeDoubleTextField (which otherwise requires whole-number defaults), and so
// parsing follows the locale. Negative values are stored as 0. Text that isn’t a number (for
// example an empty field mid-edit) leaves the setting alone; ending the edit shows the stored value.
- (PreferenceInfo *)defineSecondsField:(NSTextField *)field key:(NSString *)key {
    __weak __typeof(self) weakSelf = self;
    __weak NSTextField *weakField = field;
    void (^showStoredValue)(void) = ^{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        NSTextField *strongField = weakField;
        if (!strongSelf || !strongField) {
            return;
        }
        strongField.stringValue = [PointerPreferencesViewController quickLookStringFromSeconds:[strongSelf doubleForKey:key]
                                                                                       locale:[NSLocale currentLocale]];
    };
    PreferenceInfo *info = [self defineControl:field
                                           key:key
                                   relatedView:nil
                                          type:kPreferenceInfoTypeDoubleTextField
                                settingChanged:^(id sender) {
        NSNumber *seconds = [PointerPreferencesViewController quickLookSecondsFromString:[sender stringValue]
                                                                                  locale:[NSLocale currentLocale]];
        if (!seconds) {
            return;
        }
        [weakSelf setDouble:MAX(0, seconds.doubleValue) forKey:key];
    }
                                        update:^BOOL{
        if (!weakSelf || !weakField) {
            return NO;
        }
        showStoredValue();
        return YES;
    }];
    info.controlTextDidEndEditing = ^(NSNotification *notification) {
        showStoredValue();
    };
    return info;
}

- (void)setShouldBeEnabled:(BOOL (^)(void))shouldBeEnabled
                   forInfo:(PreferenceInfo *)info
              dependencies:(NSArray<NSString *> *)keys {
    info.shouldBeEnabled = shouldBeEnabled;
    for (NSString *key in keys) {
        [info addShouldBeEnabledDependencyOnSetting:key controller:self];
    }
    // defineControl: already updated the enabled state, before shouldBeEnabled existed.
    [self updateEnabledStateForInfo:info];
}

// The note under the browser engine checkbox explains why the setting has no effect.
- (void)updateQuickLookPluginNote {
    NSString *note = nil;
    if (![self boolForKey:kPreferenceKeyQuickLookUsesBrowserEngine]) {
        // No note: the setting is off.
    } else if (![iTermAdvancedSettingsModel browserProfiles]) {
        note = NSLocalizedStringWithDefaultValue(@"PointerPreferences.QuickLookBrowserProfilesOff",
                                                 nil,
                                                 [NSBundle mainBundle],
                                                 @"“Enable browser-style profiles” is off in Settings > Advanced; using the basic preview.",
                                                 @"Note under the Quick Look browser engine checkbox when the advanced setting that enables the built-in browser is off");
    } else if (![iTermBrowserGateway browserAllowedCheckingIfNot:YES]) {
        note = NSLocalizedStringWithDefaultValue(@"PointerPreferences.QuickLookPluginNotInstalled",
                                                 nil,
                                                 [NSBundle mainBundle],
                                                 @"Browser Plugin not installed; using the basic preview.",
                                                 @"Note under the Quick Look browser engine checkbox when the Browser Plugin is not installed");
    }
    _quickLookPluginNote.hidden = (note == nil);
    if (note) {
        _quickLookPluginNote.stringValue = note;
    }
}

- (void)updateQuickLookNeverClose {
    _quickLookHoverNeverClose.state = ([self doubleForKey:kPreferenceKeyQuickLookHoverAutoCloseDelay] <= 0 ?
                                       NSControlStateValueOn : NSControlStateValueOff);
    _quickLookHoverNeverClose.enabled = ([self intForKey:kPreferenceKeyQuickLookHoverMode] !=
                                         iTermQuickLookHoverModeOff);
}

- (IBAction)quickLookHoverNeverCloseChanged:(id)sender {
    const BOOL never = (_quickLookHoverNeverClose.state == NSControlStateValueOn);
    NSNumber *defaultDelay = [NSNumber castFrom:[self defaultValueForKey:kPreferenceKeyQuickLookHoverAutoCloseDelay]];
    [self setDouble:never ? 0 : defaultDelay.doubleValue
             forKey:kPreferenceKeyQuickLookHoverAutoCloseDelay];
    [self updateValueForInfo:_quickLookHoverAutoCloseDelayInfo];
    [self updateEnabledStateForInfo:_quickLookHoverAutoCloseDelayInfo];
    [self updateQuickLookNeverClose];
}

- (NSTabView *)tabView {
    return _tabView;
}

- (CGFloat)minimumWidth {
    return 186;
}

@end
