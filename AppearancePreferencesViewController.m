//
//  AppearancePreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "AppearancePreferencesViewController.h"

@implementation AppearancePreferencesViewController {
    // This is actually the tab style. See TAB_STYLE_XXX defines.
    IBOutlet NSPopUpButton *_windowStyle;
    
    // Tab position within window. See TAB_POSITION_XXX defines.
    IBOutlet NSPopUpButton *_tabPosition;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (void)awakeFromNib {
    PreferenceInfo *info;
    
    info = [self defineControl:_windowStyle
                           key:kPreferenceKeyWindowStyle
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [self postRefreshNotification]; };
    
    info = [self defineControl:_tabPosition
                           key:kPreferenceKeyTabPosition
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [self postRefreshNotification]; };
}


@end
