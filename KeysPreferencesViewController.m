//
//  KeysPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "KeysPreferencesViewController.h"
#import "HotkeyWindowController.h"
#import "PreferencePanel.h"

@implementation KeysPreferencesViewController {
    IBOutlet NSPopUpButton *_controlButton;
    IBOutlet NSPopUpButton *_leftOptionButton;
}

- (void)awakeFromNib {
    PreferenceInfo *info;

    info = [self defineControl:_controlButton
                           key:kPreferenceKeyControlRemapping
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [self startEventTapIfNecessary]; };

    info = [self defineControl:_leftOptionButton
                           key:kPreferenceKeyLeftOptionRemapping
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [self startEventTapIfNecessary]; };
}

- (void)startEventTapIfNecessary {
    PreferencePanel *prefs = [PreferencePanel sharedInstance];
    if (([prefs isAnyModifierRemapped] && ![[HotkeyWindowController sharedInstance] haveEventTap])) {
        [[HotkeyWindowController sharedInstance] beginRemappingModifiers];
    }
}

@end
