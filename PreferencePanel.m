/*
 **  PreferencePanel.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: Implements the model and controller for the preference panel.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

/*
 * Preferences in iTerm2 are complicated, to say the least. Here is how the classes are organized.
 *
 * - PreferencePanel: There are two instances of this class: -sharedInstance and -sessionsInstance.
 *       The sharedInstance is the app settings panel, while sessionsInstance is for editing a
 *       single session (View>Edit Current Session).
 *     - GeneralPreferencesViewController:    View controller for Prefs>General
 *     - AppearancePreferencesViewController: View controller for Prefs>Appearance
 *     - KeysPreferencesViewController:       View controller for Prefs>Keys
 *     - PointerPreferencesViewController:    View controller for Prefs>Pointer
 *     - ProfilePreferencesViewController:    View controller for Prefs>Profiles
 *     - WindowArrangements:                  Owns Prefs>Arrangements
 *     - iTermAdvancedSettingsController:     Owns Prefs>Advanced
 *
 *  View controllers of tabs in PreferencePanel derive from iTermPreferencesBaseViewController.
 *  iTermPreferencesBaseViewController provides a map from NSControl* to PreferenceInfo.
 *  PreferenceInfo stores a pref's type, user defaults key, can constrain its value, and
 *  stores pointers to blocks that are run when a value is changed or a field needs to be updated
 *  for customizing how controls are bound to storage. Each view controller defines these bindings
 *  in its -awakeFromNib method.
 *
 *  User defaults are accessed through iTermPreferences, which assigns string constants to user
 *  defaults keys, defines default values for each key, and provides accessors. It also allows the
 *  exposed values to be computed from underlying values. (Currently, iTermPreferences is not used
 *  by advanced settings, but that should change).
 *
 *  Because per-profile preferences are similar, a parallel class structure exists for them.
 *  The following classes are view controllers for tabs in Prefs>Profiles:
 *
 *  - ProfilesGeneralPreferencesViewController
 *  - ProfilesColorPreferencesViewController
 *  - ProfilesTextPreferencesViewController
 *  - ProfilesWindowPreferencesViewController
 *  - ProfilesTerminalPreferencesViewController
 *  - ProfilesKeysPreferencesViewController
 *  - ProfilesAdvancedPreferencesViewController
 *
 *  These derive from iTermProfilePreferencesBaseViewController, which is just like
 *  iTermPreferencesBaseViewController, but its methods for accessing preference values take an
 *  additional profile: parameter. The analog of iTermPreferences is iTermProfilePreferences.
 *  */
#import "PreferencePanel.h"

#import "GeneralPreferencesViewController.h"
#import "ITAddressBookMgr.h"
#import "iTermApplicationDelegate.h"
#import "iTermController.h"
#import "iTermKeyBindingMgr.h"
#import "iTermKeyMappingViewController.h"
#import "iTermPreferences.h"
#import "iTermRemotePreferences.h"
#import "iTermSettingsModel.h"
#import "iTermURLSchemeController.h"
#import "iTermWarning.h"
#import "KeysPreferencesViewController.h"
#import "NSDictionary+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSPopUpButton+iTerm.h"
#import "NSStringITerm.h"
#import "PasteboardHistory.h"
#import "PointerPrefsController.h"
#import "ProfileModel.h"
#import "ProfilePreferencesViewController.h"
#import "ProfilesColorsPreferencesViewController.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "SessionView.h"
#import "WindowArrangements.h"
#include <stdlib.h>

NSString *const kRefreshTerminalNotification = @"kRefreshTerminalNotification";
NSString *const kUpdateLabelsNotification = @"kUpdateLabelsNotification";
NSString *const kKeyBindingsChangedNotification = @"kKeyBindingsChangedNotification";
NSString *const kReloadAllProfiles = @"kReloadAllProfiles";
NSString *const kPreferencePanelDidUpdateProfileFields = @"kPreferencePanelDidUpdateProfileFields";

@implementation PreferencePanel {
    ProfileModel *_profileModel;
    BOOL oneBookmarkMode;
    IBOutlet GeneralPreferencesViewController *_generalPreferencesViewController;
    IBOutlet KeysPreferencesViewController *_keysViewController;
    IBOutlet ProfilePreferencesViewController *_profilesViewController;

    // instant replay
    BOOL defaultInstantReplay;

    NSUserDefaults *_userDefaults;

    IBOutlet NSToolbar* toolbar;
    IBOutlet NSTabView* tabView;
    IBOutlet NSToolbarItem* globalToolbarItem;
    IBOutlet NSTabViewItem* globalTabViewItem;
    IBOutlet NSToolbarItem* appearanceToolbarItem;
    IBOutlet NSTabViewItem* appearanceTabViewItem;
    IBOutlet NSToolbarItem* keyboardToolbarItem;
    IBOutlet NSToolbarItem* arrangementsToolbarItem;
    IBOutlet NSTabViewItem* keyboardTabViewItem;
    IBOutlet NSTabViewItem* arrangementsTabViewItem;
    IBOutlet NSToolbarItem* bookmarksToolbarItem;
    IBOutlet NSTabViewItem* bookmarksTabViewItem;
    IBOutlet NSToolbarItem* mouseToolbarItem;
    IBOutlet NSTabViewItem* mouseTabViewItem;
    IBOutlet NSToolbarItem* advancedToolbarItem;
    IBOutlet NSTabViewItem* advancedTabViewItem;
    NSString *globalToolbarId;
    NSString *appearanceToolbarId;
    NSString *keyboardToolbarId;
    NSString *arrangementsToolbarId;
    NSString *bookmarksToolbarId;
    NSString *mouseToolbarId;
    NSString *advancedToolbarId;

    // This class is not well named. It is a lot like a view controller for the window
    // arrangements tab.
    IBOutlet WindowArrangements *arrangements_;

    BOOL _haveAwoken;  // Can kill this when profiles stuff is migrated
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] initWithProfileModel:[ProfileModel sharedInstance]
                                         userDefaults:[NSUserDefaults standardUserDefaults]
                                      oneBookmarkMode:NO];
    });
    return instance;
}

+ (instancetype)sessionsInstance {
    static id instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] initWithProfileModel:[ProfileModel sessionsInstance]
                                         userDefaults:nil
                                      oneBookmarkMode:YES];
    });
    return instance;
}

- (id)initWithProfileModel:(ProfileModel*)model
              userDefaults:(NSUserDefaults*)userDefaults
           oneBookmarkMode:(BOOL)obMode {
    self = [super initWithWindowNibName:@"PreferencePanel"];
    if (self) {
        _profileModel = model;
        _userDefaults = userDefaults;

        [toolbar setSelectedItemIdentifier:globalToolbarId];

        oneBookmarkMode = obMode;
    }
    return self;
}

#pragma mark - View layout

- (void)awakeFromNib {
    // Because the ProfilePreferencesViewController awakes before PreferencePanel, it calls
    // profilePreferencesModelDidAwakeFromNib which in turn calls this to ensure everything is
    // initialized so that the rest of [-ProfilePreferencesViewController awakeFromNib] can run
    // successfully. This is an awful hack and will go away.
    if (_haveAwoken) {
        return;
    }

    [[self window] setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
    bookmarksToolbarId = [bookmarksToolbarItem itemIdentifier];
    globalToolbarId = [globalToolbarItem itemIdentifier];
    appearanceToolbarId = [appearanceToolbarItem itemIdentifier];
    keyboardToolbarId = [keyboardToolbarItem itemIdentifier];
    arrangementsToolbarId = [arrangementsToolbarItem itemIdentifier];
    mouseToolbarId = [mouseToolbarItem itemIdentifier];
    advancedToolbarId = [advancedToolbarItem itemIdentifier];

    [toolbar setSelectedItemIdentifier:globalToolbarId];

    if (oneBookmarkMode) {
        [self layoutSubviewsForEditCurrentSessionMode];
    }
}

- (void)layoutSubviewsForEditCurrentSessionMode {
    [self selectProfilesTab];
    [_profilesViewController layoutSubviewsForEditCurrentSessionMode];
    [toolbar setVisible:NO];

    NSRect newFrame = [[self window] frame];
    newFrame.size.width = [_profilesViewController size].width + 26;
    [[self window] setFrame:newFrame display:YES];
}

#pragma mark - API

- (void)selectProfilesTab {
    [tabView selectTabViewItem:bookmarksTabViewItem];
    [toolbar setSelectedItemIdentifier:bookmarksToolbarId];
}

- (void)openToProfileWithGuid:(NSString*)guid {
    [self window];
    [self selectProfilesTab];
    [_profilesViewController selectGeneralTab];
    [self run];
    [_profilesViewController openToProfileWithGuid:guid];
}

- (BOOL)importColorPresetFromFile:(NSString*)filename {
    return [_profilesViewController importColorPresetFromFile:filename];
}

- (WindowArrangements *)arrangements {
    return arrangements_;
}

#pragma mark - NSWindowController

- (void)windowWillLoad {
    // We finally set our autosave window frame name and restore the one from the user's defaults.
    [self setWindowFrameAutosaveName:@"Preferences"];
}

#pragma mark - NSWindowDelegate

- (void)windowWillClose:(NSNotification *)aNotification {
    [self savePreferences];
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:kNonTerminalWindowBecameKeyNotification
                                                        object:nil
                                                      userInfo:nil];
}

#pragma mark - Handle calls to current first responder

// Shell>Close
- (void)closeCurrentSession:(id)sender
{
    if ([[self window] isKeyWindow]) {
        [self closeWindow:self];
    }
}

// Shell>Close Terminal Window
- (void)closeWindow:(id)sender
{
    [[self window] close];
}

#pragma mark - IBActions

- (IBAction)showGlobalTabView:(id)sender {
    [tabView selectTabViewItem:globalTabViewItem];
}

- (IBAction)showAppearanceTabView:(id)sender {
    [tabView selectTabViewItem:appearanceTabViewItem];
}

- (IBAction)showBookmarksTabView:(id)sender {
    [tabView selectTabViewItem:bookmarksTabViewItem];
}

- (IBAction)showKeyboardTabView:(id)sender {
    [tabView selectTabViewItem:keyboardTabViewItem];
}

- (IBAction)showArrangementsTabView:(id)sender {
    [tabView selectTabViewItem:arrangementsTabViewItem];
}

- (IBAction)showMouseTabView:(id)sender {
    [tabView selectTabViewItem:mouseTabViewItem];
}

- (IBAction)showAdvancedTabView:(id)sender {
    [tabView selectTabViewItem:advancedTabViewItem];
}

#pragma mark - NSToolbarDelegate and ToolbarItemValidation

- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem {
    return TRUE;
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSString *)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag
{
    if (!flag) {
        return nil;
    }
    NSDictionary *theDict = @{ globalToolbarId: globalToolbarItem,
                               appearanceToolbarId: appearanceToolbarItem,
                               bookmarksToolbarId: bookmarksToolbarItem,
                               keyboardToolbarId: keyboardToolbarItem,
                               arrangementsToolbarId: arrangementsToolbarItem,
                               mouseToolbarId: mouseToolbarItem,
                               advancedToolbarId: advancedToolbarItem };
    return theDict[itemIdentifier];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    return @[ globalToolbarId,
              appearanceToolbarId,
              bookmarksToolbarId,
              keyboardToolbarId,
              arrangementsToolbarId,
              mouseToolbarId,
              advancedToolbarId ];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    return [NSArray arrayWithObjects:globalToolbarId, appearanceToolbarId, bookmarksToolbarId,
            keyboardToolbarId, arrangementsToolbarId, mouseToolbarId, nil];
}

- (NSArray *)toolbarSelectableItemIdentifiers: (NSToolbar *)toolbar
{
    // Optional delegate method: Returns the identifiers of the subset of
    // toolbar items that are selectable.
    return @[ globalToolbarId,
              appearanceToolbarId,
              bookmarksToolbarId,
              keyboardToolbarId,
              arrangementsToolbarId,
              mouseToolbarId,
              advancedToolbarId ];
}

#pragma mark - NSUserDefaults wrangling

- (void)savePreferences {
    if (!_userDefaults) {
        // In one-bookmark mode _userDefaults is nil but this function doesn't
        // affect bookmarks.
        return;
    }

    [_userDefaults setObject:[_profileModel rawData] forKey: @"New Bookmarks"];

    [_userDefaults synchronize];
}

#pragma mark - Utilities

- (int)modifierTagToMask:(int)tag
{
    switch (tag) {
        case MOD_TAG_ANY_COMMAND:
            return NSCommandKeyMask;

        case MOD_TAG_CMD_OPT:
            return NSCommandKeyMask | NSAlternateKeyMask;

        case MOD_TAG_OPTION:
            return NSAlternateKeyMask;

        default:
            NSLog(@"Unexpected value for modifierTagToMask: %d", tag);
            return NSCommandKeyMask | NSAlternateKeyMask;
    }
}

// Pick out the digits from s and clamp it to a range.
- (int)intForString:(NSString *)s inRange:(NSRange)range
{
    NSString *i = [s stringWithOnlyDigits];

    int val = 0;
    if ([i length]) {
        val = [i intValue];
    }
    val = MAX(val, range.location);
    val = MIN(val, range.location + range.length);
    return val;
}

#pragma mark - Hotkey Window

- (NSTextField*)hotkeyField {
    return _keysViewController.hotkeyField;
}

#pragma mark - Accessors

- (NSString *)currentProfileGuid {
    return [_profilesViewController selectedProfile][KEY_GUID];
}

- (float)fsTabDelay {
    return [iTermPreferences floatForKey:kPreferenceKeyTimeToHoldCmdToShowTabsInFullScreen];
}

- (BOOL)trimTrailingWhitespace
{
    return [iTermSettingsModel trimWhitespaceOnCopy];
}

- (float)legacyMinimumContrast
{
    return [_userDefaults objectForKey:@"MinimumContrast"] ? [[_userDefaults objectForKey:@"MinimumContrast"] floatValue] : 0;;
}

- (BOOL)allowClipboardAccess
{
    return [iTermPreferences boolForKey:kPreferenceKeyAllowClipboardAccessFromTerminal];
}

- (BOOL)copySelection
{
    return [iTermPreferences boolForKey:kPreferenceKeySelectionCopiesText];
}

- (BOOL)copyLastNewline {
    return [iTermPreferences boolForKey:kPreferenceKeyCopyLastNewline];
}

- (BOOL)legacyPasteFromClipboard {
    // This is used for migrating old prefs to the new configurable pointer action system.
    return [_userDefaults boolForKey:@"PasteFromClipboard"];
}

- (BOOL)threeFingerEmulatesMiddle {
    return [iTermPreferences boolForKey:kPreferenceKeyThreeFingerEmulatesMiddle];
}

- (BOOL)hideTab {
    return [iTermPreferences boolForKey:kPreferenceKeyHideTabBar];
}

- (int)tabViewType {
    return [iTermPreferences intForKey:kPreferenceKeyTabPosition];
}

- (int)windowStyle {
    return [iTermPreferences intForKey:kPreferenceKeyWindowStyle];
}

- (int)openTmuxWindowsIn {
    return [iTermPreferences intForKey:kPreferenceKeyOpenTmuxWindowsIn];
}

- (BOOL)autoHideTmuxClientSession {
    return [iTermPreferences boolForKey:kPreferenceKeyAutoHideTmuxClientSession];
}

- (int)tmuxDashboardLimit {
    return [iTermPreferences intForKey:kPreferenceKeyTmuxDashboardLimit];
}

- (BOOL)promptOnQuit
{
    return [iTermPreferences boolForKey:kPreferenceKeyPromptOnQuit];
}

- (BOOL)onlyWhenMoreTabs
{
    return [iTermPreferences boolForKey:kPreferenceKeyConfirmClosingMultipleTabs];
}

- (BOOL)focusFollowsMouse {
    return [iTermPreferences boolForKey:kPreferenceKeyFocusFollowsMouse];
}

- (BOOL)tripleClickSelectsFullLines {
    return [iTermPreferences boolForKey:kPreferenceKeyTripleClickSelectsFullWrappedLines];
}

- (BOOL)enableBonjour
{
    return [iTermPreferences boolForKey:kPreferenceKeyAddBonjourHostsToProfiles];
}

- (BOOL)enableGrowl
{
    for (Profile* bookmark in [[ProfileModel sharedInstance] bookmarks]) {
        if ([[bookmark objectForKey:KEY_BOOKMARK_GROWL_NOTIFICATIONS] boolValue]) {
            return YES;
        }
    }
    for (Profile* bookmark in [[ProfileModel sessionsInstance] bookmarks]) {
        if ([[bookmark objectForKey:KEY_BOOKMARK_GROWL_NOTIFICATIONS] boolValue]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)cmdSelection {
    return [iTermPreferences boolForKey:kPreferenceKeyCmdClickOpensURLs];
}

- (BOOL)optionClickMovesCursor {
    return [iTermPreferences boolForKey:kPreferenceKeyOptionClickMovesCursor];
}

- (BOOL)passOnControlLeftClick {
    return [iTermPreferences boolForKey:kPreferenceKeyControlLeftClickBypassesContextMenu];
}

- (BOOL)maxVertically {
    return [iTermPreferences boolForKey:kPreferenceKeyMaximizeVerticallyOnly];
}

- (BOOL)hideTabNumber {
    return [iTermPreferences boolForKey:kPreferenceKeyHideTabNumber];
}

- (BOOL)hideTabCloseButton {
    return [iTermPreferences boolForKey:kPreferenceKeyHideTabCloseButton];
}

- (BOOL)hideActivityIndicator {
    return [iTermPreferences boolForKey:kPreferenceKeyHideTabActivityIndicator];
}

- (BOOL)highlightTabLabels {
    return [iTermPreferences boolForKey:kPreferenceKeyHighlightTabLabels];
}

- (BOOL)hideMenuBarInFullscreen {
    return [iTermPreferences boolForKey:kPreferenceKeyHideMenuBarInFullscreen];
}

- (BOOL)openBookmark
{
    return [iTermPreferences boolForKey:kPreferenceKeyOpenBookmark];
}

- (NSString *)wordChars {
    return [iTermPreferences stringForKey:kPreferenceKeyCharactersConsideredPartOfAWordForSelection];
}

- (BOOL)hideScrollbar {
    return [iTermPreferences boolForKey:kPreferenceKeyHideScrollbar];
}

- (BOOL)showPaneTitles {
    return [iTermPreferences boolForKey:kPreferenceKeyShowPaneTitles];
}

- (BOOL)disableFullscreenTransparency {
    return [iTermPreferences boolForKey:kPreferenceKeyDisableFullscreenTransparencyByDefault];
}

- (BOOL)smartPlacement {
    return [iTermPreferences boolForKey:kPreferenceKeySmartWindowPlacement];
}

- (BOOL)adjustWindowForFontSizeChange {
    return [iTermPreferences boolForKey:kPreferenceKeyAdjustWindowForFontSizeChange];
}

- (BOOL)windowNumber {
    return [iTermPreferences boolForKey:kPreferenceKeyShowWindowNumber];
}

- (BOOL)jobName {
    return [iTermPreferences boolForKey:kPreferenceKeyShowJobName];
}

- (BOOL)showBookmarkName {
    return [iTermPreferences boolForKey:kPreferenceKeyShowProfileName];
}

- (BOOL)instantReplay
{
    return YES;
}

- (BOOL)savePasteHistory
{
    return [iTermPreferences boolForKey:kPreferenceKeySavePasteAndCommandHistory];
}

- (int)control {
    return [iTermPreferences intForKey:kPreferenceKeyControlRemapping];
}

- (int)leftOption {
    return [iTermPreferences intForKey:kPreferenceKeyLeftOptionRemapping];
}

- (int)rightOption {
    return [iTermPreferences intForKey:kPreferenceKeyRightOptionRemapping];
}

- (int)leftCommand {
    return [iTermPreferences intForKey:kPreferenceKeyLeftCommandRemapping];
}

- (int)rightCommand {
    return [iTermPreferences intForKey:kPreferenceKeyRightCommandRemapping];
}

- (BOOL)isAnyModifierRemapped
{
    return ([self control] != MOD_TAG_CONTROL ||
            [self leftOption] != MOD_TAG_LEFT_OPTION ||
            [self rightOption] != MOD_TAG_RIGHT_OPTION ||
            [self leftCommand] != MOD_TAG_LEFT_COMMAND ||
            [self rightCommand] != MOD_TAG_RIGHT_COMMAND);
}

- (int)switchTabModifier {
    return [iTermPreferences intForKey:kPreferenceKeySwitchTabModifier];
}

- (int)switchWindowModifier {
    return [iTermPreferences intForKey:kPreferenceKeySwitchWindowModifier];
}

- (BOOL)openArrangementAtStartup
{
    return [iTermPreferences boolForKey:kPreferenceKeyOpenArrangementAtStartup];
}

- (int)irMemory
{
    return [iTermPreferences intForKey:kPreferenceKeyInstantReplayMemoryMegabytes];
}

- (BOOL)hotkey {
    return [iTermPreferences boolForKey:kPreferenceKeyHotkeyEnabled];
}

- (short)hotkeyChar
{
    return [iTermPreferences intForKey:kPreferenceKeyHotkeyCharacter];
}

- (int)hotkeyCode
{
    return [iTermPreferences intForKey:kPreferenceKeyHotKeyCode];
}

- (int)hotkeyModifiers
{
    return [iTermPreferences intForKey:kPreferenceKeyHotkeyModifiers];
}

- (BOOL)dimInactiveSplitPanes {
    return [iTermPreferences boolForKey:kPreferenceKeyDimInactiveSplitPanes];
}

- (BOOL)dimBackgroundWindows {
    return [iTermPreferences boolForKey:kPreferenceKeyDimBackgroundWindows];
}

- (BOOL)animateDimming {
    return [iTermPreferences boolForKey:kPreferenceKeyAnimateDimming];
}

- (BOOL)dimOnlyText {
    return [iTermPreferences boolForKey:kPreferenceKeyDimOnlyText];
}

- (float)dimmingAmount {
    return [iTermPreferences floatForKey:kPreferenceKeyDimmingAmount];
}

- (BOOL)showWindowBorder {
    return [iTermPreferences boolForKey:kPreferenceKeyShowWindowBorder];
}

- (BOOL)lionStyleFullscreen {
    return [iTermPreferences boolForKey:kPreferenceKeyLionStyleFullscren];
}

- (BOOL)checkTestRelease
{
    return [iTermPreferences boolForKey:kPreferenceKeyCheckForTestReleases];
}

// Smart cursor color used to be a global value. This provides the default when
// migrating.
- (BOOL)legacySmartCursorColor
{
    return [_userDefaults objectForKey:@"ColorInvertedCursor"]?[[_userDefaults objectForKey:@"ColorInvertedCursor"] boolValue]: YES;
}

- (BOOL)quitWhenAllWindowsClosed
{
    return [iTermPreferences boolForKey:kPreferenceKeyQuitWhenAllWindowsClosed];
}

- (BOOL)useUnevenTabs {
    return [iTermSettingsModel useUnevenTabs];
}

- (int)minTabWidth {
    return [iTermSettingsModel minTabWidth];
}

- (int)minCompactTabWidth {
    return [iTermSettingsModel minCompactTabWidth];
}

- (int)optimumTabWidth {
    return [iTermSettingsModel optimumTabWidth];
}

- (BOOL)traditionalVisualBell {
    return [iTermSettingsModel traditionalVisualBell];
}

- (BOOL) alternateMouseScroll {
    return [iTermSettingsModel alternateMouseScroll];
}

- (float)hotkeyTermAnimationDuration {
    return [iTermSettingsModel hotkeyTermAnimationDuration];
}

- (NSString *)searchCommand
{
    return [iTermSettingsModel searchCommand];
}

- (NSTimeInterval)antiIdleTimerPeriod {
    NSTimeInterval period = [iTermSettingsModel antiIdleTimerPeriod];
    if (period > 0) {
        return period;
    } else {
        return 30;
    }
}

- (BOOL)hotkeyTogglesWindow {
    return [iTermPreferences boolForKey:kPreferenceKeyHotKeyTogglesWindow];
}

- (BOOL)hotkeyAutoHides {
    return [iTermPreferences boolForKey:kPreferenceKeyHotkeyAutoHides];
}

- (BOOL)dockIconTogglesWindow
{
    return [iTermSettingsModel dockIconTogglesWindow];
}

- (NSTimeInterval)timeBetweenBlinks
{
    return [iTermSettingsModel timeBetweenBlinks];
}

- (BOOL)autoCommandHistory
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"AutoCommandHistory"];
}

- (void)setAutoCommandHistory:(BOOL)value
{
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:@"AutoCommandHistory"];
}

#pragma mark - Update view contents

- (void)run {
    [_generalPreferencesViewController updateEnabledState];
    [_profilesViewController selectFirstProfileIfNecessary];
    [self showWindow:self];
    [[self window] makeKeyAndOrderFront:self];
}

- (void)underlyingBookmarkDidChange
{
    Profile *profile = [_profilesViewController selectedProfile];
    if (profile) {
        [self updateBookmarkFields:profile];
    }
}

// Update the values in form fields to reflect the bookmark's state
- (void)updateBookmarkFields:(NSDictionary *)dict
{
    [_profilesViewController updateSubviewsForProfile:dict];
    if (_profilesViewController.tabView.isHidden) {
        return;
    }

    NSString* name;
    name = [dict objectForKey:KEY_NAME];

    NSString* imageFilename = [dict objectForKey:KEY_BACKGROUND_IMAGE_LOCATION];
    if (!imageFilename) {
        imageFilename = @"";
    }

    // Epilogue
    [_profilesViewController reloadData];

    [[NSNotificationCenter defaultCenter] postNotificationName:kPreferencePanelDidUpdateProfileFields
                                                        object:nil
                                                      userInfo:nil];
}

- (void)changeFont:(id)fontManager {
  [_profilesViewController changeFont:fontManager];
}

- (ProfileModel *)profilePreferencesModel {
    return _profileModel;
}

- (void)profilePreferencesModelDidAwakeFromNib {
    [self awakeFromNib];
}

@end

