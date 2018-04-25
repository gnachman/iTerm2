//
//  AppearancePreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "AppearancePreferencesViewController.h"
#import "iTermHotKeyController.h"
#import "iTermApplicationDelegate.h"
#import "iTermWarning.h"
#import "PreferencePanel.h"

NSString *const iTermProcessTypeDidChangeNotification = @"iTermProcessTypeDidChangeNotification";

@implementation AppearancePreferencesViewController {
    // This is actually the tab style. See TAB_STYLE_XXX defines.
    __weak IBOutlet NSPopUpButton *_tabStyle;

    // Tab position within window. See TAB_POSITION_XXX defines.
    __weak IBOutlet NSPopUpButton *_tabPosition;

    // Hide tab bar when there is only one session
    __weak IBOutlet NSButton *_hideTab;

    // Remove tab number from tabs.
    __weak IBOutlet NSButton *_hideTabNumber;

    // Remove close button from tabs.
    __weak IBOutlet NSButton *_hideTabCloseButton;

    // Hide activity indicator.
    __weak IBOutlet NSButton *_hideActivityIndicator;

    // Show new-output indicator
    __weak IBOutlet NSButton *_showNewOutputIndicator;

    // Show per-pane title bar with split panes.
    __weak IBOutlet NSButton *_showPaneTitles;

    // Hide menu bar in non-lion fullscreen.
    __weak IBOutlet NSButton *_hideMenuBarInFullscreen;

    // Exclude from dock and cmd-tab (LSUIElement)
    __weak IBOutlet NSButton *_uiElement;

    __weak IBOutlet NSButton *_flashTabBarInFullscreenWhenSwitchingTabs;
    __weak IBOutlet NSButton *_showTabBarInFullscreen;

    __weak IBOutlet NSButton *_stretchTabsToFillBar;

    // Show window number in title bar.
    __weak IBOutlet NSButton *_windowNumber;

    // Show job name in title
    __weak IBOutlet NSButton *_jobName;

    // Show bookmark name in title.
    __weak IBOutlet NSButton *_showBookmarkName;

    // Dim text (and non-default background colors).
    __weak IBOutlet NSButton *_dimOnlyText;

    // Dimming amount.
    __weak IBOutlet NSSlider *_dimmingAmount;

    // Dim inactive split panes.
    __weak IBOutlet NSButton *_dimInactiveSplitPanes;

    // Dim background windows.
    __weak IBOutlet NSButton *_dimBackgroundWindows;

    // Window border.
    __weak IBOutlet NSButton *_showWindowBorder;

    // Hide scrollbar.
    __weak IBOutlet NSButton *_hideScrollbar;

    // Disable transparency in fullscreen by default.
    __weak IBOutlet NSButton *_disableFullscreenTransparency;

    // Draw line under title bar when the tab bar is not visible
    __weak IBOutlet NSButton *_enableDivisionView;

    __weak IBOutlet NSButton *_enableProxyIcon;
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
                          type:kPreferenceInfoTypeInvertedCheckbox];
    info.onChange = ^() {
        [self postRefreshNotification];
        [self updateFlashTabsVisibility];
    };

    info = [self defineControl:_hideTabNumber
                           key:kPreferenceKeyHideTabNumber
                          type:kPreferenceInfoTypeInvertedCheckbox];
    info.onChange = ^() { [self postRefreshNotification]; };

    info = [self defineControl:_hideTabCloseButton
                           key:kPreferenceKeyHideTabCloseButton
                          type:kPreferenceInfoTypeInvertedCheckbox];
    info.onChange = ^() { [self postRefreshNotification]; };

    info = [self defineControl:_hideActivityIndicator
                           key:kPreferenceKeyHideTabActivityIndicator
                          type:kPreferenceInfoTypeInvertedCheckbox];
    info.onChange = ^() { [self postRefreshNotification]; };

    info = [self defineControl:_showNewOutputIndicator
                           key:kPreferenceKeyShowNewOutputIndicator
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

    info = [self defineControl:_uiElement
                           key:kPreferenceKeyUIElement
                          type:kPreferenceInfoTypeCheckbox];
    info.customSettingChangedHandler = ^(id sender) {
        BOOL isOn = [sender state] == NSOnState;
        if (isOn) {
            iTermWarningSelection selection =
                [iTermWarning showWarningWithTitle:@"When iTerm2 is excluded from the dock, you can "
                                                   @"always get back to Preferences using the status "
                                                   @"bar item. Look for an iTerm2 icon on the right "
                                                   @"side of your menu bar."
                                           actions:@[ @"Exclude From Dock and App Switcher", @"Cancel" ]
                                        identifier:nil
                                       silenceable:kiTermWarningTypePersistent];
            if (selection == kiTermWarningSelection0) {
                [self setBool:YES forKey:kPreferenceKeyUIElement];
            }
        } else {
            [self setBool:NO forKey:kPreferenceKeyUIElement];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermProcessTypeDidChangeNotification
                                                            object:nil];
    };

    [self defineControl:_flashTabBarInFullscreenWhenSwitchingTabs
                    key:kPreferenceKeyFlashTabBarInFullscreen
                   type:kPreferenceInfoTypeCheckbox];
    [self updateFlashTabsVisibility];

    info = [self defineControl:_showTabBarInFullscreen
                           key:kPreferenceKeyShowFullscreenTabBar
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() {
        [[NSNotificationCenter defaultCenter] postNotificationName:kShowFullscreenTabsSettingDidChange
                                                            object:nil];
    };

    // There's a menu item to change this setting. We want the control to reflect it.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showFullscreenTabsSettingDidChange:)
                                                 name:kShowFullscreenTabsSettingDidChange
                                               object:nil];

    info = [self defineControl:_stretchTabsToFillBar
                           key:kPreferenceKeyStretchTabsToFillBar
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self postRefreshNotification]; };

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

    info = [self defineControl:_enableDivisionView
                           key:kPreferenceKeyEnableDivisionView
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self postRefreshNotification]; };

    info = [self defineControl:_enableProxyIcon
                           key:kPreferenceKeyEnableProxyIcon
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self postRefreshNotification]; };
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)postUpdateLabelsNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:kUpdateLabelsNotification
                                                        object:nil
                                                      userInfo:nil];
}

- (void)showFullscreenTabsSettingDidChange:(NSNotification *)notification {
    _showTabBarInFullscreen.state =
        [iTermPreferences boolForKey:kPreferenceKeyShowFullscreenTabBar] ? NSOnState : NSOffState;
    [self updateFlashTabsVisibility];
}

- (void)updateFlashTabsVisibility {
    // Enable flashing tabs in fullscreen when it's possible for the tab bar in fullscreen to be
    // hidden: either it's not always visible or it's hidden when there's a single tab. The single-
    // tab case is relevant when going from two tabs to one, which could be considered a "switch".
    _flashTabBarInFullscreenWhenSwitchingTabs.enabled =
        (![iTermPreferences boolForKey:kPreferenceKeyShowFullscreenTabBar] ||
         [iTermPreferences boolForKey:kPreferenceKeyHideTabBar]);
}

@end
