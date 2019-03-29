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
    IBOutlet NSTabView *_tabView;

    // Cmd-click to launch url.
    IBOutlet NSButton *_cmdSelection;

    // Control-click doesn't open the context menu, is mouse-reported as right click.
    IBOutlet NSButton *_controlLeftClickActsLikeRightClick;

    // Opt-click moves cursor.
    IBOutlet NSButton *_optionClickMovesCursor;

    // Three finger click emulates middle button.
    IBOutlet NSButton *_threeFingerEmulatesMiddle;

    // Focus follows mouse.
    IBOutlet NSButton *_focusFollowsMouse;

    // Triple click selects full, wrapped lines.
    IBOutlet NSButton *_tripleClickSelectsFullLines;

    // Double click perform smart selection
    IBOutlet NSButton *_doubleClickPerformsSmartSelection;
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

    [self defineControl:_tripleClickSelectsFullLines
                    key:kPreferenceKeyTripleClickSelectsFullWrappedLines
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_doubleClickPerformsSmartSelection
                    key:kPreferenceKeyDoubleClickPerformsSmartSelection
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
}

- (NSTabView *)tabView {
    return _tabView;
}

- (CGFloat)minimumWidth {
    return 186;
}

@end
