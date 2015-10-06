//
//  AppearancePreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "AppearancePreferencesViewController.h"
#import "PreferencePanel.h"

@implementation AppearancePreferencesViewController {
    // This is actually the tab style. See TAB_STYLE_XXX defines.
    IBOutlet NSPopUpButton *_tabStyle;

    // Tab position within window. See TAB_POSITION_XXX defines.
    IBOutlet NSPopUpButton *_tabPosition;
    
    // Hide tab bar when there is only one session
    IBOutlet NSButton *_hideTab;

    // Remove tab number from tabs.
    IBOutlet NSButton *_hideTabNumber;
    
    // Remove close button from tabs.
    IBOutlet NSButton *_hideTabCloseButton;

    // Hide activity indicator.
    IBOutlet NSButton *_hideActivityIndicator;

    // Show per-pane title bar with split panes.
    IBOutlet NSButton *_showPaneTitles;

    // Hide menu bar in non-lion fullscreen.
    IBOutlet NSButton *_hideMenuBarInFullscreen;

    IBOutlet NSButton *_flashTabBarInFullscreenWhenSwitchingTabs;

    // Show window number in title bar.
    IBOutlet NSButton *_windowNumber;

    // Show job name in title
    IBOutlet NSButton *_jobName;

    // Show bookmark name in title.
    IBOutlet NSButton *_showBookmarkName;

    // Dim text (and non-default background colors).
    IBOutlet NSButton *_dimOnlyText;

    // Dimming amount.
    IBOutlet NSSlider *_dimmingAmount;

    // Dim inactive split panes.
    IBOutlet NSButton *_dimInactiveSplitPanes;

    // Dim background windows.
    IBOutlet NSButton *_dimBackgroundWindows;

    // Window border.
    IBOutlet NSButton *_showWindowBorder;

    // Hide scrollbar.
    IBOutlet NSButton *_hideScrollbar;

    // Disable transparency in fullscreen by default.
    IBOutlet NSButton *_disableFullscreenTransparency;
}

- (void)awakeFromNib {
    PreferenceInfo *info;

    info = [self defineControl:_tabPosition
                           key:kPreferenceKeyTabPosition
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [self postRefreshNotification]; };

    info = [self defineControl:_tabStyle
                           key:kPreferenceKeyTabStyle
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [self postRefreshNotification]; };

    
    info = [self defineControl:_hideTab
                           key:kPreferenceKeyHideTabBar
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self postRefreshNotification]; };
    
    info = [self defineControl:_hideTabNumber
                           key:kPreferenceKeyHideTabNumber
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self postRefreshNotification]; };
    
    info = [self defineControl:_hideTabCloseButton
                           key:kPreferenceKeyHideTabCloseButton
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self postRefreshNotification]; };

    info = [self defineControl:_hideActivityIndicator
                           key:kPreferenceKeyHideTabActivityIndicator
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self postRefreshNotification]; };

    info = [self defineControl:_showPaneTitles
                           key:kPreferenceKeyShowPaneTitles
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self postRefreshNotification]; };

    info = [self defineControl:_hideMenuBarInFullscreen
                           key:kPreferenceKeyHideMenuBarInFullscreen
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self postRefreshNotification]; };

    [self defineControl:_flashTabBarInFullscreenWhenSwitchingTabs
                    key:kPreferenceKeyFlashTabBarInFullscreen
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_windowNumber
                           key:kPreferenceKeyShowWindowNumber
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self postUpdateLabelsNotification]; };

    info = [self defineControl:_jobName
                           key:kPreferenceKeyShowJobName
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self postUpdateLabelsNotification]; };

    info = [self defineControl:_showBookmarkName
                           key:kPreferenceKeyShowProfileName
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self postUpdateLabelsNotification]; };

    info = [self defineControl:_dimOnlyText
                           key:kPreferenceKeyDimOnlyText
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self postRefreshNotification]; };

    info = [self defineControl:_dimmingAmount
                           key:kPreferenceKeyDimmingAmount
                          type:kPreferenceInfoTypeSlider];
    info.onChange = ^() { [self postRefreshNotification]; };

    info = [self defineControl:_dimInactiveSplitPanes
                           key:kPreferenceKeyDimInactiveSplitPanes
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self postRefreshNotification]; };

    info = [self defineControl:_dimBackgroundWindows
                           key:kPreferenceKeyDimBackgroundWindows
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self postRefreshNotification]; };

    info = [self defineControl:_showWindowBorder
                           key:kPreferenceKeyShowWindowBorder
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self postRefreshNotification]; };

    info = [self defineControl:_hideScrollbar
                           key:kPreferenceKeyHideScrollbar
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self postRefreshNotification]; };

    info = [self defineControl:_disableFullscreenTransparency
                           key:kPreferenceKeyDisableFullscreenTransparencyByDefault
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self postRefreshNotification]; };
}

- (void)postUpdateLabelsNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:kUpdateLabelsNotification
                                                        object:nil
                                                      userInfo:nil];
}

@end
