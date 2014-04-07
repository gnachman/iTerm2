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
#import "PSMTabBarControl.h"

@implementation KeysPreferencesViewController {
    IBOutlet NSPopUpButton *_controlButton;
    IBOutlet NSPopUpButton *_leftOptionButton;
    IBOutlet NSPopUpButton *_rightOptionButton;
    IBOutlet NSPopUpButton *_leftCommandButton;
    IBOutlet NSPopUpButton *_rightCommandButton;

    IBOutlet NSPopUpButton *_switchTabModifierButton;
    IBOutlet NSPopUpButton *_switchWindowModifierButton;
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

    info = [self defineControl:_rightOptionButton
                           key:kPreferenceKeyRightOptionRemapping
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [self startEventTapIfNecessary]; };

    info = [self defineControl:_leftCommandButton
                           key:kPreferenceKeyLeftCommandRemapping
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [self startEventTapIfNecessary]; };

    info = [self defineControl:_rightCommandButton
                           key:kPreferenceKeyRightCommandRemapping
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [self startEventTapIfNecessary]; };

    // ---------------------------------------------------------------------------------------------
    info = [self defineControl:_switchTabModifierButton
                           key:kPreferenceKeySwitchTabModifier
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [self postModifierChangedNotification]; };

    info = [self defineControl:_switchWindowModifierButton
                           key:kPreferenceKeySwitchWindowModifier
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [self postModifierChangedNotification]; };
}

- (void)startEventTapIfNecessary {
    PreferencePanel *prefs = [PreferencePanel sharedInstance];
    if (([prefs isAnyModifierRemapped] && ![[HotkeyWindowController sharedInstance] haveEventTap])) {
        [[HotkeyWindowController sharedInstance] beginRemappingModifiers];
    }
}

- (void)postModifierChangedNotification {
    PreferencePanel *prefs = [PreferencePanel sharedInstance];
    NSDictionary *userInfo =
        @{ kPSMTabModifierKey: @([prefs modifierTagToMask:[prefs switchTabModifier]]) };
    [[NSNotificationCenter defaultCenter] postNotificationName:kPSMModifierChangedNotification
                                                        object:nil
                                                      userInfo:userInfo];
}

@end
