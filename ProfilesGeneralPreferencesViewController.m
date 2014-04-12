//
//  ProfilesGeneralPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/11/14.
//
//

#import "ProfilesGeneralPreferencesViewController.h"
#import "ITAddressBookMgr.h"

@implementation ProfilesGeneralPreferencesViewController {
    IBOutlet NSTextField *_profileNameField;
}

- (void)awakeFromNib {
    PreferenceInfo *info;
    
    info = [self defineControl:_profileNameField
                           key:KEY_NAME
                          type:kPreferenceInfoTypeStringTextField];
    info.willChange = ^() { [_profileDelegate profilesGeneralPreferencesNameWillChange]; };
}

@end
