//
//  PointerPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "PointerPreferencesViewController.h"

@implementation PointerPreferencesViewController {
    // Cmd-click to launch url.
    IBOutlet NSButton *_cmdSelection;

    // Control-click doesn't open the context menu, is mouse-reported as right click.
    IBOutlet NSButton *_controlLeftClickActsLikeRightClick;

    // Opt-click moves cursor
    IBOutlet NSButton *_optionClickMovesCursor;
}

- (void)awakeFromNib {
    PreferenceInfo *info;

    [self defineControl:_cmdSelection
                    key:kPreferenceKeyCmdClickOpensURLs
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_controlLeftClickActsLikeRightClick
                    key:kPreferenceKeyControlLeftClickBypassesContextMenu
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_optionClickMovesCursor
                    key:kPreferenceKeyOptionClickMovesCursor
                   type:kPreferenceInfoTypeCheckbox];
}

@end
