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
    IBOutlet NSButton *_useBlur;
    IBOutlet NSSlider *_blurRadius;
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
    [self defineControl:_transparency
                    key:KEY_TRANSPARENCY
                   type:kPreferenceInfoTypeSlider];
    
    info = [self defineControl:_useBlur
                           key:KEY_BLUR
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() { _blurRadius.enabled = (_useBlur.state == NSOnState); };
    
    [self defineControl:_blurRadius
                    key:KEY_BLUR_RADIUS
                   type:kPreferenceInfoTypeSlider];
}

@end
