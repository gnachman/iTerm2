//
//  ProfilesTerminalPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/17/14.
//
//

#import "ProfilesTerminalPreferencesViewController.h"
#import "ITAddressBookMgr.h"

@implementation ProfilesTerminalPreferencesViewController {
    IBOutlet NSTextField *_numScrollbackLines;
}

- (void)awakeFromNib {
    PreferenceInfo *info;
    info = [self defineControl:_numScrollbackLines
                           key:KEY_SCROLLBACK_LINES
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(0, 10 * 1000 * 1000);
}

@end
