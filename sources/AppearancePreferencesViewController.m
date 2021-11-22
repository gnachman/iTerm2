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

@interface AppearancePreferencesViewController()<NSTabViewDelegate>
@end

@implementation AppearancePreferencesViewController {
    // This is actually the tab style. See TAB_STYLE_XXX defines.
    IBOutlet NSPopUpButton *_tabStyle;
    IBOutlet NSTextField *_tabStyleLabel;

    // Tab position within window. See TAB_POSITION_XXX defines.
    IBOutlet NSPopUpButton *_tabPosition;
    IBOutlet NSTextField *_tabPositionLabel;

    IBOutlet NSPopUpButton *_statusBarPosition;
    IBOutlet NSTextField *_statusBarPositionLabel;

    IBOutlet NSButton *_perPaneStatusBars;

    // Hide tab bar when there is only one session
    IBOutlet NSButton *_hideTab;

    IBOutlet NSButton *_preserveWindowSizeWhenTabBarVisibilityChanges;

    // Remove tab number from tabs.
    IBOutlet NSButton *_hideTabNumber;

    // Tabs have close buttons?
    IBOutlet NSButton *_tabsHaveCloseButtons;

    // Hide activity indicator.
    IBOutlet NSButton *_hideActivityIndicator;

    // Show new-output indicator
    IBOutlet NSButton *_showNewOutputIndicator;

    // Show per-pane title bar with split panes.
    IBOutlet NSButton *_showPaneTitles;

    // Separate background images per pane
    IBOutlet NSButton *_separateBackgroundImages;
    
    // Hide menu bar in non-lion fullscreen.
    IBOutlet NSButton *_hideMenuBarInFullscreen;

    // Exclude from dock and cmd-tab (LSUIElement)
    IBOutlet NSButton *_uiElement;
    IBOutlet NSButton *_uiElementRequiresHotkeyWindows;

    IBOutlet NSButton *_flashTabBarInFullscreenWhenSwitchingTabs;
    IBOutlet NSButton *_showTabBarInFullscreen;

    IBOutlet NSButton *_stretchTabsToFillBar;
    IBOutlet NSButton *_htmlTabTitles;

    // Show window number in title bar.
    IBOutlet NSButton *_windowNumber;

    // Dim text (and non-default background colors).
    IBOutlet NSButton *_dimOnlyText;

    // Dimming amount.
    IBOutlet NSSlider *_dimmingAmount;
    IBOutlet NSTextField *_dimmingAmountLabel;

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

    // Draw line under title bar when the tab bar is not visible
    IBOutlet NSButton *_enableDivisionView;

    IBOutlet NSButton *_enableProxyIcon;

    IBOutlet NSTabView *_tabView;
    NSRect _desiredFrame;

    IBOutlet NSTextField *_sideMarginsLabel;
    IBOutlet NSTextField *_sideMargins;
    IBOutlet NSStepper *_sideMarginsStepper;

    IBOutlet NSTextField *_topBottomMarginsLabel;
    IBOutlet NSTextField *_topBottomMargins;
    IBOutlet NSStepper *_topBottomMarginsStepper;
}

- (void)awakeFromNib {
    PreferenceInfo *info;

    __weak __typeof(self) weakSelf = self;
    info = [self defineControl:_tabPosition
                           key:kPreferenceKeyTabPosition
                   relatedView:_tabPositionLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_statusBarPosition
                           key:kPreferenceKeyStatusBarPosition
                   relatedView:_statusBarPositionLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^{ [weakSelf postRefreshNotification]; };

    info = [self defineControl:_perPaneStatusBars
                           key:kPreferenceKeySeparateStatusBarsPerPane
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^{ [weakSelf postRefreshNotification]; };

    info = [self defineControl:_tabStyle
                           key:kPreferenceKeyTabStyle
                   relatedView:_tabStyleLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() {
        [weakSelf postRefreshNotification];
        [weakSelf updateProxyIconEnabled];
    };

    info = [self defineControl:_sideMargins
                           key:kPreferenceKeySideMargins
                   relatedView:_sideMarginsLabel
                          type:kPreferenceInfoTypeIntegerTextField];
    [self associateStepper:_sideMarginsStepper withPreference:info];
    info.onChange = ^{
        [weakSelf postRefreshNotification];
    };

    info = [self defineControl:_topBottomMargins
                           key:kPreferenceKeyTopBottomMargins
                   relatedView:_topBottomMarginsLabel
                          type:kPreferenceInfoTypeIntegerTextField];
    info.onChange = ^{
        [weakSelf postRefreshNotification];
    };
    [self associateStepper:_topBottomMarginsStepper withPreference:info];

    info = [self defineControl:_hideTab
                           key:kPreferenceKeyHideTabBar
                   relatedView:nil
                          type:kPreferenceInfoTypeInvertedCheckbox];
    info.onChange = ^() {
        [weakSelf postRefreshNotification];
        [weakSelf updateHiddenAndEnabled];
    };

    [self defineControl:_preserveWindowSizeWhenTabBarVisibilityChanges
                    key:kPreferenceKeyPreserveWindowSizeWhenTabBarVisibilityChanges
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_hideTabNumber
                           key:kPreferenceKeyHideTabNumber
                   relatedView:nil
                          type:kPreferenceInfoTypeInvertedCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_tabsHaveCloseButtons
                           key:kPreferenceKeyTabsHaveCloseButton
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_hideActivityIndicator
                           key:kPreferenceKeyHideTabActivityIndicator
                   relatedView:nil
                          type:kPreferenceInfoTypeInvertedCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_showNewOutputIndicator
                           key:kPreferenceKeyShowNewOutputIndicator
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_showPaneTitles
                           key:kPreferenceKeyShowPaneTitles
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_separateBackgroundImages
                           key:kPreferenceKeyPerPaneBackgroundImage
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_hideMenuBarInFullscreen
                           key:kPreferenceKeyHideMenuBarInFullscreen
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };
    
    info = [self defineControl:_uiElement
                           key:kPreferenceKeyUIElement
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.customSettingChangedHandler = ^(id sender) {
        BOOL isOn = [sender state] == NSControlStateValueOn;
        BOOL didChange = NO;
        if (isOn) {
            iTermWarningSelection selection =
                [iTermWarning showWarningWithTitle:@"When iTerm2 is excluded from the dock, you can "
                                                   @"always get back to Preferences using the status "
                                                   @"bar item. Look for an iTerm2 icon on the right "
                                                   @"side of your menu bar."
                                           actions:@[ @"Exclude From Dock and App Switcher", @"Cancel" ]
                                        identifier:nil
                                       silenceable:kiTermWarningTypePersistent
                                            window:weakSelf.view.window];
            if (selection == kiTermWarningSelection0) {
                [weakSelf setBool:YES forKey:kPreferenceKeyUIElement];
                [weakSelf setBool:NO forKey:kPreferenceKeyHideMenuBarInFullscreen];
                didChange = YES;
            }
        } else {
            didChange = YES;
            [weakSelf setBool:NO forKey:kPreferenceKeyUIElement];
        }
        if (didChange) {
            __strong __typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                if (isOn) {
                    strongSelf->_hideMenuBarInFullscreen.state = NSControlStateValueOff;
                }
            }
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermProcessTypeDidChangeNotification
                                                            object:nil];
        [weakSelf updateHiddenAndEnabled];
    };

    info = [self defineControl:_uiElementRequiresHotkeyWindows
                           key:kPreferenceKeyUIElementRequiresHotkeys
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.shouldBeEnabled = ^BOOL{
        return [weakSelf boolForKey:kPreferenceKeyUIElement];
    };
    info.observer = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermProcessTypeDidChangeNotification
                                                            object:nil];
        [weakSelf updateHiddenAndEnabled];
    };

    info = [self defineControl:_flashTabBarInFullscreenWhenSwitchingTabs
                    key:kPreferenceKeyFlashTabBarInFullscreen
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kRefreshTerminalNotification object:nil];
    };

    [self updateHiddenAndEnabled];

    info = [self defineControl:_showTabBarInFullscreen
                           key:kPreferenceKeyShowFullscreenTabBar
                   relatedView:nil
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
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_htmlTabTitles
                           key:kPreferenceKeyHTMLTabTitles
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_windowNumber
                           key:kPreferenceKeyShowWindowNumber
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postUpdateLabelsNotification]; };

    info = [self defineControl:_dimOnlyText
                           key:kPreferenceKeyDimOnlyText
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_dimmingAmount
                           key:kPreferenceKeyDimmingAmount
                   relatedView:_dimmingAmountLabel
                          type:kPreferenceInfoTypeSlider];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_dimInactiveSplitPanes
                           key:kPreferenceKeyDimInactiveSplitPanes
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_dimBackgroundWindows
                           key:kPreferenceKeyDimBackgroundWindows
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_showWindowBorder
                           key:kPreferenceKeyShowWindowBorder
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };
    info = [self defineControl:_hideScrollbar
                           key:kPreferenceKeyHideScrollbar
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_disableFullscreenTransparency
                           key:kPreferenceKeyDisableFullscreenTransparencyByDefault
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_enableDivisionView
                           key:kPreferenceKeyEnableDivisionView
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_enableProxyIcon
                           key:kPreferenceKeyEnableProxyIcon
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf postRefreshNotification]; };
    [self updateProxyIconEnabled];
}

- (void)updateProxyIconEnabled {
    const iTermPreferencesTabStyle tabStyle = [self intForKey:kPreferenceKeyTabStyle];
    _enableProxyIcon.enabled = (tabStyle != TAB_STYLE_MINIMAL);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)postUpdateLabelsNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:kUpdateLabelsNotification
                                                        object:nil
                                                      userInfo:nil];
}

- (void)showFullscreenTabsSettingDidChange:(NSNotification *)notification {
    _showTabBarInFullscreen.state =
        [iTermPreferences boolForKey:kPreferenceKeyShowFullscreenTabBar] ? NSControlStateValueOn : NSControlStateValueOff;
    [self updateHiddenAndEnabled];
}

- (void)updateHiddenAndEnabled {
    // Enable flashing tabs in fullscreen when it's possible for the tab bar in fullscreen to be
    // hidden: either it's not always visible or it's hidden when there's a single tab. The single-
    // tab case is relevant when going from two tabs to one, which could be considered a "switch".
    _flashTabBarInFullscreenWhenSwitchingTabs.enabled =
        (![iTermPreferences boolForKey:kPreferenceKeyShowFullscreenTabBar] ||
         [iTermPreferences boolForKey:kPreferenceKeyHideTabBar]);

    // Can't preserve size if you can't hide the tab bar.
    _preserveWindowSizeWhenTabBarVisibilityChanges.enabled = (_hideTab.state != NSControlStateValueOn);
    [self updateEnabledState];

    _hideMenuBarInFullscreen.enabled = (![self boolForKey:kPreferenceKeyUIElement] ||
                                        [self boolForKey:kPreferenceKeyUIElementRequiresHotkeys]);
}

- (NSTabView *)tabView {
    return _tabView;
}

- (CGFloat)minimumWidth {
    return 374;
}

@end
