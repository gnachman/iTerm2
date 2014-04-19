//
//  ProfilesSessionViewController.m
//  iTerm
//
//  Created by George Nachman on 4/18/14.
//
//

#import "ProfilesSessionPreferencesViewController.h"
#import "ITAddressBookMgr.h"

@implementation ProfilesSessionPreferencesViewController {
    IBOutlet NSButton *_closeSessionsOnEnd;
    IBOutlet NSMatrix *_promptBeforeClosing;
}

- (void)awakeFromNib {
    PreferenceInfo *info;
    [self defineControl:_closeSessionsOnEnd
                    key:KEY_CLOSE_SESSIONS_ON_END
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_promptBeforeClosing
                    key:KEY_PROMPT_CLOSE
                   type:kPreferenceInfoTypeMatrix
         settingChanged:^(id sender) {
             [self setInt:[_promptBeforeClosing selectedTag] forKey:KEY_PROMPT_CLOSE];
         }
                 update:^BOOL {
                     [_promptBeforeClosing selectCellWithTag:[self intForKey:KEY_PROMPT_CLOSE]];
                     return YES;
                 }];
}

@end
