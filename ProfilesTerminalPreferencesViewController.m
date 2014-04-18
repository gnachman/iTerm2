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
    IBOutlet NSButton *_unlimitedScrollback;
    IBOutlet NSButton *_scrollbackWithStatusBar;
    IBOutlet NSButton *_scrollbackInAlternateScreen;
}

- (void)awakeFromNib {
    PreferenceInfo *info;
    info = [self defineControl:_numScrollbackLines
                           key:KEY_SCROLLBACK_LINES
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(0, 10 * 1000 * 1000);
    
    info = [self defineControl:_unlimitedScrollback
                           key:KEY_UNLIMITED_SCROLLBACK
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() {
        BOOL unlimited = [self boolForKey:KEY_UNLIMITED_SCROLLBACK];
        _numScrollbackLines.enabled = !unlimited;
        if (unlimited) {
            _numScrollbackLines.stringValue = @"";
        } else {
            _numScrollbackLines.intValue = [self intForKey:KEY_SCROLLBACK_LINES];
        }
    };

    [self defineControl:_scrollbackWithStatusBar
                    key:KEY_SCROLLBACK_WITH_STATUS_BAR
                   type:kPreferenceInfoTypeCheckbox];
    
    [self defineControl:_scrollbackInAlternateScreen
                    key:KEY_SCROLLBACK_IN_ALTERNATE_SCREEN
                   type:kPreferenceInfoTypeCheckbox];
}

@end
