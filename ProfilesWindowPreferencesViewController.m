//
//  ProfilesWindowPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/16/14.
//
//

#import "ProfilesWindowPreferencesViewController.h"
#import "ITAddressBookMgr.h"
#import "PreferencePanel.h"

@implementation ProfilesWindowPreferencesViewController {
    IBOutlet NSSlider *_transparency;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)awakeFromNib {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProfile)  // In superclass
                                                 name:kReloadAllProfiles
                                               object:nil];

    PreferenceInfo *info;
    info = [self defineControl:_transparency
                           key:KEY_TRANSPARENCY
                          type:kPreferenceInfoTypeSlider];
}

@end
