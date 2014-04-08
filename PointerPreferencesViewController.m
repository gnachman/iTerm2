//
//  PointerPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "PointerPreferencesViewController.h"

@implementation PointerPreferencesViewController {
    // cmd-click to launch url
    IBOutlet NSButton *_cmdSelection;
}

- (void)awakeFromNib {
    PreferenceInfo *info;

    [self defineControl:_cmdSelection
                    key:kPreferenceKeyCmdClickOpensURLs
                   type:kPreferenceInfoTypeCheckbox];
}

@end
