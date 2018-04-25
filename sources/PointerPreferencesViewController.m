//
//  PointerPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "PointerPreferencesViewController.h"
#import "PreferencePanel.h"

NSString *const kPointerPrefsChangedNotification = @"kPointerPrefsChangedNotification";
NSString *const kPointerPrefsSemanticHistoryEnabledChangedNotification = @"kPointerPrefsSemanticHistoryEnabledChangedNotification";

@implementation PointerPreferencesViewController {
    // Cmd-click to launch url.
    __weak IBOutlet NSButton *_cmdSelection;

    // Control-click doesn't open the context menu, is mouse-reported as right click.
    __weak IBOutlet NSButton *_controlLeftClickActsLikeRightClick;

    // Opt-click moves cursor.
    __weak IBOutlet NSButton *_optionClickMovesCursor;

    // Three finger click emulates middle button.
    __weak IBOutlet NSButton *_threeFingerEmulatesMiddle;

    // Focus follows mouse.
    __weak IBOutlet NSButton *_focusFollowsMouse;

    // Triple click selects full, wrapped lines.
    __weak IBOutlet NSButton *_tripleClickSelectsFullLines;

    // Double click perform smart selection
    __weak IBOutlet NSButton *_doubleClickPerformsSmartSelection;
}

- (void)awakeFromNib {
    PreferenceInfo *info;

    info = [self defineControl:_cmdSelection
                           key:kPreferenceKeyCmdClickOpensURLs
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() {
        [[NSNotificationCenter defaultCenter] postNotificationName:kPointerPrefsSemanticHistoryEnabledChangedNotification
                                                            object:nil];
    };

    [self defineControl:_controlLeftClickActsLikeRightClick
                    key:kPreferenceKeyControlLeftClickBypassesContextMenu
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_optionClickMovesCursor
                    key:kPreferenceKeyOptionClickMovesCursor
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_threeFingerEmulatesMiddle
                           key:kPreferenceKeyThreeFingerEmulatesMiddle
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() {
        [self postRefreshNotification];
        [[NSNotificationCenter defaultCenter] postNotificationName:kPointerPrefsChangedNotification
                                                            object:nil
                                                          userInfo:nil];
    };

    [self defineControl:_focusFollowsMouse
                    key:kPreferenceKeyFocusFollowsMouse
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_tripleClickSelectsFullLines
                    key:kPreferenceKeyTripleClickSelectsFullWrappedLines
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_doubleClickPerformsSmartSelection
                    key:kPreferenceKeyDoubleClickPerformsSmartSelection
                   type:kPreferenceInfoTypeCheckbox];
}

@end
