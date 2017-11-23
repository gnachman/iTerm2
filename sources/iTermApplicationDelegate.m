/*
 **  iTermApplicationDelegate.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **          Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: Implements the main application delegate and handles the addressbook functions.
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

#import "iTermApplicationDelegate.h"

#import "AppearancePreferencesViewController.h"
#import "ColorsMenuItemView.h"
#import "FileTransferManager.h"
#import "ITAddressBookMgr.h"
#import "iTermAPIServer.h"
#import "iTermAboutWindowController.h"
#import "iTermAppHotKeyProvider.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermBuriedSessions.h"
#import "iTermColorPresets.h"
#import "iTermController.h"
#import "iTermDisclosableView.h"
#import "iTermExpose.h"
#import "iTermFileDescriptorSocketPath.h"
#import "iTermFontPanel.h"
#import "iTermFullScreenWindowManager.h"
#import "iTermHotKeyController.h"
#import "iTermHotKeyProfileBindingController.h"
#import "iTermIntegerNumberFormatter.h"
#import "iTermLaunchServices.h"
#import "iTermLSOF.h"
#import "iTermModifierRemapper.h"
#import "iTermPreferences.h"
#import "iTermRemotePreferences.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermOpenQuicklyWindowController.h"
#import "iTermOrphanServerAdopter.h"
#import "iTermPasswordManagerWindowController.h"
#import "iTermPreferences.h"
#import "iTermPromptOnCloseReason.h"
#import "iTermProfilePreferences.h"
#import "iTermProfilesWindowController.h"
#import "iTermServiceProvider.h"
#import "iTermQuickLookController.h"
#import "iTermRemotePreferences.h"
#import "iTermRestorableSession.h"
#import "iTermSystemVersion.h"
#import "iTermTipController.h"
#import "iTermTipWindowController.h"
#import "iTermToolbeltView.h"
#import "iTermURLStore.h"
#import "iTermWarning.h"
#import "MovePaneController.h"
#import "NSApplication+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSBundle+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSStringITerm.h"
#import "NSWindow+iTerm.h"
#import "NSView+RecursiveDescription.h"
#import "PFMoveApplication.h"
#import "PreferencePanel.h"
#import "PseudoTerminal.h"
#import "PseudoTerminalRestorer.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PTYTextView.h"
#import "PTYWindow.h"
#import "QLPreviewPanel+iTerm.h"
#import "TmuxDashboardController.h"
#import "ToastWindowController.h"
#import "VT100Terminal.h"

#import <Quartz/Quartz.h>
#import <objc/runtime.h>

#include "iTermFileDescriptorClient.h"
#include <libproc.h>
#include <sys/stat.h>
#include <unistd.h>

@import Sparkle;

static NSString *kUseBackgroundPatternIndicatorKey = @"Use background pattern indicator";
NSString *kUseBackgroundPatternIndicatorChangedNotification = @"kUseBackgroundPatternIndicatorChangedNotification";
NSString *const kSavedArrangementDidChangeNotification = @"kSavedArrangementDidChangeNotification";
NSString *const kNonTerminalWindowBecameKeyNotification = @"kNonTerminalWindowBecameKeyNotification";
static NSString *const kMarkAlertAction = @"Mark Alert Action";
NSString *const kMarkAlertActionModalAlert = @"Modal Alert";
NSString *const kMarkAlertActionPostNotification = @"Post Notification";
NSString *const kShowFullscreenTabsSettingDidChange = @"kShowFullscreenTabsSettingDidChange";
NSString *const iTermRemoveAPIServerSubscriptionsNotification = @"iTermRemoveAPIServerSubscriptionsNotification";

static NSString *const kScreenCharRestorableStateKey = @"kScreenCharRestorableStateKey";
static NSString *const kURLStoreRestorableStateKey = @"kURLStoreRestorableStateKey";
static NSString *const kHotkeyWindowRestorableState = @"kHotkeyWindowRestorableState";  // deprecated
static NSString *const kHotkeyWindowsRestorableStates = @"kHotkeyWindowsRestorableState";  // deprecated
static NSString *const iTermBuriedSessionState = @"iTermBuriedSessionState";

static NSString *const kHaveWarnedAboutIncompatibleSoftware = @"NoSyncHaveWarnedAboutIncompatibleSoftware";

static NSString *const kRestoreDefaultWindowArrangementShortcut = @"R";
NSString *const iTermApplicationWillTerminate = @"iTermApplicationWillTerminate";

static BOOL gStartupActivitiesPerformed = NO;
// Prior to 8/7/11, there was only one window arrangement, always called Default.
static NSString *LEGACY_DEFAULT_ARRANGEMENT_NAME = @"Default";
static BOOL ranAutoLaunchScript = NO;
static BOOL hasBecomeActive = NO;

static NSString *const kBundlesWithAPIAccessSettingKey = @"NoSyncBundlesWithAPIAccessSettings";
static NSString *const kAPIAccessAllowed = @"allowed";
static NSString *const kAPIAccessDate = @"date";
static NSString *const kAPINextConfirmationDate = @"next confirmation";
static NSString *const kAPIAccessLocalizedName = @"app name";
static const NSTimeInterval kOneMonth = 30 * 24 * 60 * 60;


@interface iTermApplicationDelegate () <iTermAPIServerDelegate, iTermPasswordManagerDelegate>

@property(nonatomic, readwrite) BOOL workspaceSessionActive;

@end


@implementation iTermApplicationDelegate {
    iTermPasswordManagerWindowController *_passwordManagerWindowController;

    // Menu items
    IBOutlet NSMenu *bookmarkMenu;
    IBOutlet NSMenu *toolbeltMenu;
    NSMenuItem *downloadsMenu_;
    NSMenuItem *uploadsMenu_;
    IBOutlet NSMenuItem *selectTab;
    IBOutlet NSMenuItem *logStart;
    IBOutlet NSMenuItem *logStop;
    IBOutlet NSMenuItem *closeTab;
    IBOutlet NSMenuItem *closeWindow;
    IBOutlet NSMenuItem *sendInputToAllSessions;
    IBOutlet NSMenuItem *sendInputToAllPanes;
    IBOutlet NSMenuItem *sendInputNormally;
    IBOutlet NSMenuItem *irPrev;
    IBOutlet NSMenuItem *windowArrangements_;
    IBOutlet NSMenuItem *windowArrangementsAsTabs_;
    IBOutlet NSMenu *_buriedSessions;

    IBOutlet NSMenuItem *showFullScreenTabs;
    IBOutlet NSMenuItem *useTransparency;
    IBOutlet NSMenuItem *maximizePane;
    IBOutlet SUUpdater * suUpdater;
    IBOutlet NSMenuItem *_showTipOfTheDay;  // Here because we must remove it for older OS versions.
    BOOL secureInputDesired_;
    BOOL quittingBecauseLastWindowClosed_;

    // If set, skip performing launch actions.
    BOOL quiet_;
    NSDate* launchTime_;

    // Cross app request forgery prevention token. Get this with applescript and then include
    // in a URI request.
    NSString *token_;

    // Set to YES when applicationDidFinishLaunching: is called.
    BOOL finishedLaunching_;

    BOOL userHasInteractedWithAnySession_;  // Disables min 10-second running time

    // If the advanced pref to turn off app nap is enabled, then we hold a reference to this
    // NSProcessInfo-provided object to make the system think we're doing something important.
    id<NSObject> _appNapStoppingActivity;

    BOOL _sparkleRestarting;  // Is Sparkle about to restart the app?

    int _secureInputCount;

    BOOL _orphansAdopted;  // Have orphan servers been adopted?

    iTermAPIServer *_apiServer;

    NSArray<NSDictionary *> *_buriedSessionsState;
    NSMutableDictionary<id, ITMNotificationRequest *> *_newSessionSubscriptions;
    NSMutableDictionary<id, ITMNotificationRequest *> *_terminateSessionSubscriptions;
    NSMutableDictionary<id, ITMNotificationRequest *> *_layoutChangeSubscriptions;
    BOOL _layoutChanged;

    // Location of mouse when the app became inactive.
    NSPoint _savedMouseLocation;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Add ourselves as an observer for notifications.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reloadMenus:)
                                                     name:@"iTermWindowBecameKey"
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(updateAddressBookMenu:)
                                                     name:kReloadAddressBookNotification
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(buildSessionSubmenu:)
                                                     name:@"iTermNumberOfSessionsDidChange"
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(buildSessionSubmenu:)
                                                     name:@"iTermNameOfSessionDidChange"
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reloadSessionMenus:)
                                                     name:@"iTermSessionBecameKey"
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(nonTerminalWindowBecameKey:)
                                                     name:kNonTerminalWindowBecameKeyNotification
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowArrangementsDidChange:)
                                                     name:kSavedArrangementDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(toolDidToggle:)
                                                     name:@"iTermToolToggled"
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(currentSessionDidChange)
                                                     name:kCurrentSessionDidChange
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(sessionCreated:)
                                                     name:PTYSessionCreatedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(sessionCreated:)
                                                     name:PTYSessionRevivedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(sessionDidTerminate:)
                                                     name:PTYSessionTerminatedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(layoutChanged:)
                                                     name:iTermSessionDidChangeTabNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(layoutChanged:)
                                                     name:iTermTabDidChangeWindowNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(layoutChanged:)
                                                     name:iTermTabDidChangePositionInWindowNotification
                                                   object:nil];

        [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
                                                           andSelector:@selector(getUrl:withReplyEvent:)
                                                         forEventClass:kInternetEventClass
                                                            andEventID:kAEGetURL];

        launchTime_ = [[NSDate date] retain];
        _workspaceSessionActive = YES;
    }

    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [_appNapStoppingActivity release];
    [_newSessionSubscriptions release];
    [_layoutChangeSubscriptions release];
    [_terminateSessionSubscriptions release];
    [super dealloc];
}

#pragma mark - Interface Builder

- (void)awakeFromNib {
    secureInputDesired_ = [[[NSUserDefaults standardUserDefaults] objectForKey:@"Secure Input"] boolValue];

    NSMenu *viewMenu = [self topLevelViewNamed:@"View"];
    [viewMenu addItem:[NSMenuItem separatorItem]];

    ColorsMenuItemView *labelTrackView = [[[ColorsMenuItemView alloc]
                                           initWithFrame:NSMakeRect(0, 0, 180, 50)] autorelease];
    [self addMenuItemView:labelTrackView toMenu:viewMenu title:@"Current Tab Color"];
    
    if (![iTermTipController sharedInstance]) {
        [_showTipOfTheDay.menu removeItem:_showTipOfTheDay];
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if ([menuItem action] == @selector(openDashboard:)) {
        return [[iTermController sharedInstance] haveTmuxConnection];
    } else if ([menuItem action] == @selector(toggleUseBackgroundPatternIndicator:)) {
      [menuItem setState:[self useBackgroundPatternIndicator]];
      return YES;
    } else if ([menuItem action] == @selector(undo:)) {
        NSResponder *undoResponder = [self responderForMenuItem:menuItem];
        if (undoResponder) {
            return YES;
        } else {
            menuItem.title = @"Undo Close Session";
            return [[iTermController sharedInstance] hasRestorableSession];
        }
    } else if ([menuItem action] == @selector(enableMarkAlertShowsModalAlert:)) {
        [menuItem setState:[[self markAlertAction] isEqualToString:kMarkAlertActionModalAlert] ? NSOnState : NSOffState];
        return YES;
    } else if ([menuItem action] == @selector(enableMarkAlertPostsNotification:)) {
        [menuItem setState:[[self markAlertAction] isEqualToString:kMarkAlertActionPostNotification] ? NSOnState : NSOffState];
        return YES;
    } else if ([menuItem action] == @selector(makeDefaultTerminal:)) {
        return ![[iTermLaunchServices sharedInstance] iTermIsDefaultTerminal];
    } else if (menuItem == maximizePane) {
        if ([[[iTermController sharedInstance] currentTerminal] inInstantReplay]) {
            // Things get too complex if you allow this. It crashes.
            return NO;
        } else if ([[[[[iTermController sharedInstance] currentTerminal] currentTab] activeSession] isTmuxClient]) {
            return YES;
        } else if ([[[[iTermController sharedInstance] currentTerminal] currentTab] hasMaximizedPane]) {
            return YES;
        } else if ([[[[iTermController sharedInstance] currentTerminal] currentTab] hasMultipleSessions]) {
            return YES;
        } else {
            return NO;
        }
    } else if ([menuItem action] == @selector(saveCurrentWindowAsArrangement:) ||
               [menuItem action] == @selector(newSessionWithSameProfile:)) {
        return [[iTermController sharedInstance] currentTerminal] != nil;
    } else if ([menuItem action] == @selector(toggleFullScreenTabBar:)) {
        [menuItem setState:[iTermPreferences boolForKey:kPreferenceKeyShowFullscreenTabBar] ? NSOnState : NSOffState];
        return YES;
    } else if ([menuItem action] == @selector(toggleMultiLinePasteWarning:)) {
        if ([iTermWarning warningHandler]) {
            // In a test.
            return YES;
        }
        if (menuItem.tag == 0) {
            menuItem.state = ![iTermAdvancedSettingsModel noSyncDoNotWarnBeforeMultilinePaste] ? NSOnState : NSOffState;
        } else if (menuItem.tag == 1) {
            menuItem.state = ![iTermAdvancedSettingsModel promptForPasteWhenNotAtPrompt] ? NSOnState : NSOffState;
            return ![iTermAdvancedSettingsModel noSyncDoNotWarnBeforeMultilinePaste];
        } else if (menuItem.tag == 2) {
            menuItem.state = ![iTermAdvancedSettingsModel noSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt] ? NSOnState : NSOffState;
        }
        return YES;
    } else if ([menuItem action] == @selector(showTipOfTheDay:)) {
        return ![[iTermTipController sharedInstance] showingTip];
    } else if ([menuItem action] == @selector(toggleSecureInput:)) {
        menuItem.state = IsSecureEventInputEnabled() ? NSOnState : NSOffState;
        return YES;
    } else if ([menuItem action] == @selector(togglePinHotkeyWindow:)) {
        iTermProfileHotKey *profileHotkey = self.currentProfileHotkey;
        menuItem.state = profileHotkey.autoHides ? NSOffState : NSOnState;
        return profileHotkey != nil;
    } else if ([menuItem action] == @selector(clearAllDownloads:)) {
        return downloadsMenu_.submenu.itemArray.count > 2;
    } else if ([menuItem action] == @selector(clearAllUploads:)) {
        return uploadsMenu_.submenu.itemArray.count > 2;
    } else {
        return YES;
    }
}

#pragma mark - APIs

- (BOOL)isApplescriptTestApp {
    return [[[NSBundle mainBundle] bundleIdentifier] containsString:@"applescript"];
}

- (BOOL)isRunningOnTravis {
    NSString *travis = [[[NSProcessInfo processInfo] environment] objectForKey:@"TRAVIS"];
    return [travis isEqualToString:@"true"];
}

- (void)userDidInteractWithASession {
    userHasInteractedWithAnySession_ = YES;
}

- (void)openPasswordManagerToAccountName:(NSString *)name inSession:(PTYSession *)session {
    id<iTermWindowController> term = [[iTermController sharedInstance] currentTerminal];
    if (session) {
        term = session.delegate.realParentWindow;
    }
    if (term) {
        DLog(@"Open password manager as sheet in terminal %@", term);
        return [term openPasswordManagerToAccountName:name inSession:session];
    } else {
        DLog(@"Open password manager as standalone window");
        if (!_passwordManagerWindowController) {
            _passwordManagerWindowController = [[iTermPasswordManagerWindowController alloc] init];
            _passwordManagerWindowController.delegate = self;
        }
        [[_passwordManagerWindowController window] makeKeyAndOrderFront:nil];
        [_passwordManagerWindowController selectAccountName:name];
    }
}

- (BOOL)warnBeforeMultiLinePaste {
    if ([iTermWarning warningHandler]) {
        // In a test.
        return YES;
    }
    return ![iTermAdvancedSettingsModel noSyncDoNotWarnBeforeMultilinePaste];
}

- (void)makeHotKeyWindowKeyIfOpen {
    for (PseudoTerminal* term in [self terminals]) {
        if ([term isHotKeyWindow] && [[term window] alphaValue] == 1) {
            [[term window] makeKeyAndOrderFront:self];
        }
    }
}

- (void)updateMaximizePaneMenuItem {
    [maximizePane setState:[[[[iTermController sharedInstance] currentTerminal] currentTab] hasMaximizedPane] ? NSOnState : NSOffState];
}

- (void)updateUseTransparencyMenuItem {
    [useTransparency setState:[[[iTermController sharedInstance] currentTerminal] useTransparency] ? NSOnState : NSOffState];
}

- (NSString *)markAlertAction {
    NSString *action = [[NSUserDefaults standardUserDefaults] objectForKey:kMarkAlertAction];
    if (!action) {
        return kMarkAlertActionPostNotification;
    } else {
        return action;
    }
}

- (void)updateBuriedSessionsMenu {
    [_buriedSessions removeAllItems];
    for (PTYSession *session in [[iTermBuriedSessions sharedInstance] buriedSessions]) {
        NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:session.name action:@selector(disinter:) keyEquivalent:@""] autorelease];
        item.representedObject = session;
        [_buriedSessions addItem:item];
    }
}

- (void)disinter:(NSMenuItem *)menuItem {
    PTYSession *session = menuItem.representedObject;
    [[iTermBuriedSessions sharedInstance] restoreSession:session];
}

- (PseudoTerminal *)currentTerminal {
    return [[iTermController sharedInstance] currentTerminal];
}

- (NSArray*)terminals {
    return [[iTermController sharedInstance] terminals];
}

- (BOOL)useBackgroundPatternIndicator {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kUseBackgroundPatternIndicatorKey];
}

- (NSMenu *)downloadsMenu {
    if (!downloadsMenu_) {
        downloadsMenu_ = [[[NSMenuItem alloc] init] autorelease];
        downloadsMenu_.title = @"Downloads";
        NSMenu *mainMenu = [[NSApplication sharedApplication] mainMenu];
        [mainMenu insertItem:downloadsMenu_
                     atIndex:mainMenu.itemArray.count - 1];
        [downloadsMenu_ setSubmenu:[[[NSMenu alloc] initWithTitle:@"Downloads"] autorelease]];

        NSMenuItem *clearAll = [[[NSMenuItem alloc] initWithTitle:@"Clear All" action:@selector(clearAllDownloads:) keyEquivalent:@""] autorelease];
        [downloadsMenu_.submenu addItem:clearAll];
        [downloadsMenu_.submenu addItem:[NSMenuItem separatorItem]];
    }
    return [downloadsMenu_ submenu];
}

- (NSMenu *)uploadsMenu {
    if (!uploadsMenu_) {
        uploadsMenu_ = [[[NSMenuItem alloc] init] autorelease];
        uploadsMenu_.title = @"Uploads";
        NSMenu *mainMenu = [[NSApplication sharedApplication] mainMenu];
        [mainMenu insertItem:uploadsMenu_
                     atIndex:mainMenu.itemArray.count - 1];
        [uploadsMenu_ setSubmenu:[[[NSMenu alloc] initWithTitle:@"Uploads"] autorelease]];

        NSMenuItem *clearAll = [[[NSMenuItem alloc] initWithTitle:@"Clear All" action:@selector(clearAllUploads:) keyEquivalent:@""] autorelease];
        [uploadsMenu_.submenu addItem:clearAll];
        [uploadsMenu_.submenu addItem:[NSMenuItem separatorItem]];
    }
    return [uploadsMenu_ submenu];
}

- (void)updateBroadcastMenuState {
    BOOL sessions = NO;
    BOOL panes = NO;
    BOOL noBroadcast = NO;
    PseudoTerminal *frontTerminal;
    frontTerminal = [[iTermController sharedInstance] currentTerminal];
    switch ([frontTerminal broadcastMode]) {
        case BROADCAST_OFF:
            noBroadcast = YES;
            break;

        case BROADCAST_TO_ALL_TABS:
            sessions = YES;
            break;

        case BROADCAST_TO_ALL_PANES:
            panes = YES;
            break;

        case BROADCAST_CUSTOM:
            break;
    }
    [sendInputToAllSessions setState:sessions];
    [sendInputToAllPanes setState:panes];
    [sendInputNormally setState:noBroadcast];
}

- (void)postAPINotification:(ITMNotification *)notification toConnection:(id)connection {
    [_apiServer postAPINotification:notification toConnection:connection];
}

#pragma mark - Application Delegate Overrides

/**
 * The following applescript invokes this method before
 * _performStartupActivities is run and prevents it from being run. Scripts can
 * use it to launch a command in a predictable way if iTerm2 isn't running (and
 * window arrangements won't be restored, etc.)
 *
 * tell application "iTerm"
 *    open file "/com.googlecode.iterm2/commandmode"
 *    // create a terminal if needed, run commands, whatever.
 * end tell
 */
- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename {
    DLog(@"application:%@ openFile:%@", theApplication, filename);
    if ([filename hasSuffix:@".itermcolors"]) {
        DLog(@"Importing color presets from %@", filename);
        if ([iTermColorPresets importColorPresetFromFile:filename]) {
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            alert.messageText = @"Colors Scheme Imported";
            alert.informativeText = @"The color scheme was imported and added to presets. You can find it under Preferences>Profiles>Colors>Load Presets….";
            [alert runModal];
        }
        return YES;
    }
    NSLog(@"Quiet launch");
    quiet_ = YES;
    if ([filename isEqualToString:[[NSFileManager defaultManager] versionNumberFilename]]) {
        return YES;
    }
    if (filename) {
        // Verify whether filename is a script or a folder
        BOOL isDir;
        [[NSFileManager defaultManager] fileExistsAtPath:filename isDirectory:&isDir];
        iTermController *controller = [iTermController sharedInstance];
        NSMutableDictionary *bookmark = [[[controller defaultBookmark] mutableCopy] autorelease];

        if (isDir) {
            bookmark[KEY_WORKING_DIRECTORY] = filename;
            bookmark[KEY_CUSTOM_DIRECTORY] = kProfilePreferenceInitialDirectoryCustomValue;
        } else {
            // escape filename
            filename = [filename stringWithEscapedShellCharactersIncludingNewlines:YES];
            if (filename) {
                NSString *initialText = bookmark[KEY_INITIAL_TEXT];
                if (initialText && ![iTermAdvancedSettingsModel openFileOverridesSendText]) {
                    initialText = [initialText stringByAppendingFormat:@"\n%@; exit", filename];
                } else {
                    initialText = [NSString stringWithFormat:@"%@; exit", filename];
                }
                bookmark[KEY_INITIAL_TEXT] = initialText;
            }
        }

        PseudoTerminal *term = [self terminalToOpenFileIn];
        [controller launchBookmark:bookmark inTerminal:term];

        // If term is a hotkey window, reveal it.
        iTermProfileHotKey *profileHotkey = [[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:term];
        if (profileHotkey) {
            [[iTermHotKeyController sharedInstance] showWindowForProfileHotKey:profileHotkey url:nil];
        }
    }
    return (YES);
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
    DLog(@"applicationShouldTerminateAfterLastWindowClosed called");
    NSArray *terminals = [[iTermController sharedInstance] terminals];
    if (terminals.count == 1 && [terminals[0] isHotKeyWindow]) {
        // The last window wasn't really closed, it was just the hotkey window getting ordered out.
        return NO;
    }
    if (!userHasInteractedWithAnySession_) {
        DLog(@"applicationShouldTerminateAfterLastWindowClosed - user has not interacted with any session");
        if ([[NSDate date] timeIntervalSinceDate:launchTime_] < [iTermAdvancedSettingsModel minRunningTime]) {
            DLog(@"Returning NO");
            NSLog(@"Not quitting iTerm2 because it ran very briefly and had no user interaction. Set the MinRunningTime float preference to 0 to turn this feature off.");
            return NO;
        }
    }
    quittingBecauseLastWindowClosed_ =
        [iTermPreferences boolForKey:kPreferenceKeyQuitWhenAllWindowsClosed];
    DLog(@"Returning %@ from pref", @(quittingBecauseLastWindowClosed_));
    return quittingBecauseLastWindowClosed_;
}

// User clicked on the dock icon.
- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication
                    hasVisibleWindows:(BOOL)flag {
    return ![[iTermHotKeyController sharedInstance] dockIconClicked];
}

- (void)applicationDidChangeScreenParameters:(NSNotification *)aNotification
{
    // The screens' -visibleFrame is not updated when this is called. Doing a delayed perform with
    // a delay of 0 is usually, but not always enough. Not that 1 second is always enough either,
    // I suppose, but I don't want to die on this hill.
    [self performSelector:@selector(updateScreenParametersInAllTerminals)
               withObject:nil
               afterDelay:[iTermAdvancedSettingsModel updateScreenParamsDelay]];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSNotification *)theNotification {
    DLog(@"applicationShouldTerminate:");
    NSArray *terminals;

    terminals = [[iTermController sharedInstance] terminals];
    int numSessions = 0;

    iTermPromptOnCloseReason *reason = [iTermPromptOnCloseReason noReason];
    for (PseudoTerminal *term in terminals) {
        numSessions += [[term allSessions] count];

        [reason addReason:term.promptOnCloseReason];
    }

    // Display prompt if we need to
    if (!quittingBecauseLastWindowClosed_ &&  // cmd-q
        [terminals count] > 0 &&  // there are terminal windows
        [iTermPreferences boolForKey:kPreferenceKeyPromptOnQuit]) {  // preference is to prompt on quit cmd
        [reason addReason:[iTermPromptOnCloseReason alwaysConfirmQuitPreferenceEnabled]];
    }
    quittingBecauseLastWindowClosed_ = NO;
    if ([iTermPreferences boolForKey:kPreferenceKeyConfirmClosingMultipleTabs] && numSessions > 1) {
        // closing multiple sessions
        [reason addReason:[iTermPromptOnCloseReason closingMultipleSessionsPreferenceEnabled]];
    }
    if ([iTermAdvancedSettingsModel runJobsInServers] &&
        self.sparkleRestarting &&
        [iTermAdvancedSettingsModel restoreWindowContents] &&
        [[iTermController sharedInstance] willRestoreWindowsAtNextLaunch]) {
        // Nothing will be lost so just restart without asking.
        [reason addReason:[iTermPromptOnCloseReason noReason]];
    }

    if (reason.hasReason) {
        DLog(@"Showing quit alert");
        NSString *message;
        if ([[iTermController sharedInstance] shouldLeaveSessionsRunningOnQuit]) {
            message = @"Sessions will be restored automatically when iTerm2 is relaunched.";
        } else {
            message = @"All sessions will be closed.";
        }
        [NSApp activateIgnoringOtherApps:YES];
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.messageText = @"Quit iTerm2?";
        alert.informativeText = message;
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:@"Cancel"];
        iTermDisclosableView *accessory = [[iTermDisclosableView alloc] initWithFrame:NSZeroRect
                                                                               prompt:@"Details"
                                                                              message:[NSString stringWithFormat:@"You are being prompted because:\n\n%@",
                                                                                       reason.message]];
        accessory.frame = NSMakeRect(0, 0, accessory.intrinsicContentSize.width, accessory.intrinsicContentSize.height);
        accessory.requestLayout = ^{
            [alert layout];
        };
        alert.accessoryView = accessory;

        if ([alert runModal] != NSAlertFirstButtonReturn) {
            DLog(@"User declined to quit");
            return NSTerminateCancel;
        }
    }

    // Ensure [iTermController dealloc] is called before prefs are saved
    [[iTermModifierRemapper sharedInstance] setRemapModifiers:NO];

    // Prevent sessions from making their termination undoable since we're quitting.
    [[iTermController sharedInstance] setApplicationIsQuitting:YES];

    if ([iTermAdvancedSettingsModel runJobsInServers]) {
        // Restorable sessions must be killed or they'll auto-restore as orphans on the next start.
        // If jobs aren't run in servers, they'll just die normally.
        [[iTermController sharedInstance] killRestorableSessions];
    }

    // Last chance before windows get closed.
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermApplicationWillTerminate object:nil];

    // This causes all windows to be closed and all sessions to be terminated.
    [iTermController releaseSharedInstance];

    // save preferences
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (![[iTermRemotePreferences sharedInstance] customFolderChanged]) {
        [[iTermRemotePreferences sharedInstance] applicationWillTerminate];
    }

    DLog(@"applicationShouldTerminate returning Now");
    return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    DLog(@"applicationWillTerminate called");
    [[iTermModifierRemapper sharedInstance] setRemapModifiers:NO];
    DLog(@"applicationWillTerminate returning");
    TurnOffDebugLoggingSilently();
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)theApplication {
    if ([self isApplescriptTestApp]) {
        // Don't want to do this for applescript testing so we have a blank slate.
        return NO;
    }
    if (!finishedLaunching_ &&
        ([iTermPreferences boolForKey:kPreferenceKeyOpenArrangementAtStartup] ||
         [iTermPreferences boolForKey:kPreferenceKeyOpenNoWindowsAtStartup] )) {
        // There are two ways this can happen:
        // 1. System window restoration is off in System Prefs>General, the window arrangement has
        //    no windows, and iTerm2 is configured to restore it at startup.
        // 2. System window restoration is off in System Prefs>General and iTerm2 is configured to
        //    open no windows at startup.
        return NO;
    }
    if (![[NSApplication sharedApplication] isRunningUnitTests]) {
        [self newWindow:nil];
    }
    return YES;
}

- (NSMenu *)applicationDockMenu:(NSApplication *)sender {
    NSMenu* aMenu = [[NSMenu alloc] initWithTitle: @"Dock Menu"];

    PseudoTerminal *frontTerminal;
    frontTerminal = [[iTermController sharedInstance] currentTerminal];
    [aMenu addItemWithTitle:@"New Window (Default Profile)"
                     action:@selector(newWindow:)
              keyEquivalent:@""];
    [aMenu addItem:[NSMenuItem separatorItem]];
    [self newSessionMenu:aMenu
                   title:@"New Window…"
                  target:[iTermController sharedInstance]
                selector:@selector(newSessionInWindowAtIndex:)
         openAllSelector:@selector(newSessionsInNewWindow:)];
    [self newSessionMenu:aMenu
                   title:@"New Tab…"
                  target:frontTerminal
                selector:@selector(newSessionInTabAtIndex:)
         openAllSelector:@selector(newSessionsInWindow:)];
    [self _addArrangementsMenuTo:aMenu];

    return ([aMenu autorelease]);
}

- (void)applicationWillBecomeActive:(NSNotification *)aNotification {
    DLog(@"******** Become Active\n%@", [NSThread callStackSymbols]);
}

- (void)application:(NSApplication *)app willEncodeRestorableState:(NSCoder *)coder {
    DLog(@"app encoding restorable state");
    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
    [coder encodeObject:ScreenCharEncodedRestorableState() forKey:kScreenCharRestorableStateKey];
    [coder encodeObject:[[iTermURLStore sharedInstance] dictionaryValue] forKey:kURLStoreRestorableStateKey];
    [[iTermHotKeyController sharedInstance] saveHotkeyWindowStates];

    NSArray *hotkeyWindowsStates = [[iTermHotKeyController sharedInstance] restorableStates];
    if (hotkeyWindowsStates) {
        [coder encodeObject:hotkeyWindowsStates
                     forKey:kHotkeyWindowsRestorableStates];
    }

    if ([[[iTermBuriedSessions sharedInstance] buriedSessions] count]) {
        [coder encodeObject:[[iTermBuriedSessions sharedInstance] restorableState] forKey:iTermBuriedSessionState];
    }
    DLog(@"Time to save app restorable state: %@",
         @([NSDate timeIntervalSinceReferenceDate] - start));
}

- (void)application:(NSApplication *)app didDecodeRestorableState:(NSCoder *)coder {
    DLog(@"application:didDecodeRestorableState:");
    if (self.isApplescriptTestApp) {
        DLog(@"Is applescript test app");
        return;
    }
    NSDictionary *screenCharState = [coder decodeObjectForKey:kScreenCharRestorableStateKey];
    if (screenCharState) {
        ScreenCharDecodeRestorableState(screenCharState);
    }

    NSDictionary *urlStoreState = [coder decodeObjectForKey:kURLStoreRestorableStateKey];
    if (urlStoreState) {
        [[iTermURLStore sharedInstance] loadFromDictionary:urlStoreState];
    }

    NSArray *hotkeyWindowsStates = nil;
    NSDictionary *legacyState = nil;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"NSQuitAlwaysKeepsWindows"]) {
        hotkeyWindowsStates = [coder decodeObjectForKey:kHotkeyWindowsRestorableStates];
        if (hotkeyWindowsStates) {
            // We have to create the hotkey window now because we need to attach to servers before
            // launch finishes; otherwise any running hotkey window jobs will be treated as orphans.
            [[iTermHotKeyController sharedInstance] createHiddenWindowsFromRestorableStates:hotkeyWindowsStates];
        } else {
            // Restore hotkey window from pre-3.1 version.
            legacyState = [coder decodeObjectForKey:kHotkeyWindowRestorableState];
            if (legacyState) {
                [[iTermHotKeyController sharedInstance] createHiddenWindowFromLegacyRestorableState:legacyState];
            }
        }
    }
    _buriedSessionsState = [[coder decodeObjectForKey:iTermBuriedSessionState] retain];
    if (finishedLaunching_) {
        [self restoreBuriedSessionsState];
    }
    if ([iTermAdvancedSettingsModel logRestorableStateSize]) {
        NSDictionary *dict = @{ kScreenCharRestorableStateKey: screenCharState ?: @{},
                                kURLStoreRestorableStateKey: urlStoreState ?: @{},
                                kHotkeyWindowsRestorableStates: hotkeyWindowsStates ?: @[],
                                kHotkeyWindowRestorableState: legacyState ?: @{},
                                iTermBuriedSessionState: _buriedSessionsState ?: @[] };
        NSString *log = [dict sizeInfo];
        [log writeToFile:[NSString stringWithFormat:@"/tmp/statesize.app-%p.txt", self] atomically:NO encoding:NSUTF8StringEncoding error:nil];
    }
}

- (void)applicationDidResignActive:(NSNotification *)aNotification {
    DLog(@"******** Resign Active\n%@", [NSThread callStackSymbols]);
    if (secureInputDesired_) {
        DLog(@"Application resigning active. Disabling secure input.");
        [self setSecureInput:NO];
    }
    _savedMouseLocation = [NSEvent mouseLocation];
}

- (void)applicationWillHide:(NSNotification *)aNotification {
    for (NSWindow *aWindow in [[NSApplication sharedApplication] windows]) {
        [self hideToolTipsInView:[aWindow contentView]];
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification {
    hasBecomeActive = YES;
    if (secureInputDesired_) {
        DLog(@"Application becoming active. Enable secure input.");
        [self setSecureInput:YES];
    }

    // If focus follows mouse is on, find the window under the cursor and make it key. If a PTYTextView
    // is under the cursor make it first responder.
    NSPoint mouseLocation = [NSEvent mouseLocation];
    if (!NSEqualPoints(mouseLocation, _savedMouseLocation) && 
        [iTermPreferences boolForKey:kPreferenceKeyFocusFollowsMouse]) {
        NSRect mouseRect = {
            .origin = [NSEvent mouseLocation],
            .size = { 0, 0 }
        };
        for (NSWindow *window in [[iTermApplication sharedApplication] orderedWindowsPlusVisibleHotkeyPanels]) {
            if (!window.isOnActiveSpace) {
                continue;
            }
            if (!window.isVisible) {
                continue;
            }
            NSPoint pointInWindow = [window convertRectFromScreen:mouseRect].origin;
            if ([window isTerminalWindow]) {
                NSView *view = [window.contentView hitTest:pointInWindow];
                [window makeKeyAndOrderFront:nil];
                if ([view isKindOfClass:[PTYTextView class]]) {
                    [window makeFirstResponder:view];
                }
                break;
            }
        }
    }
    
    [self hideStuckToolTips];
}

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification {
    // Cleanly crash on uncaught exceptions, such as during actions.
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{ @"NSApplicationCrashOnExceptions": @YES }];

#if !DEBUG
    PFMoveToApplicationsFolderIfNecessary();
#endif
    // Start automatic debug logging if it's enabled.
    if ([iTermAdvancedSettingsModel startDebugLoggingAutomatically]) {
        TurnOnDebugLoggingSilently();
    }

    [self buildScriptMenu:nil];

    // Fix up various user defaults settings.
    [iTermPreferences initializeUserDefaults];

    // This sets up bonjour and migrates bookmarks if needed.
    [ITAddressBookMgr sharedInstance];

    // Bookmarks must be loaded for this to work since it needs to know if the hotkey's profile
    // exists.
    [self updateProcessType];

    [iTermToolbeltView populateMenu:toolbeltMenu];

    // Start tracking windows entering/exiting full screen.
    [iTermFullScreenWindowManager sharedInstance];

    // Users used to be opted into the beta by default. Make sure the user is cool with that.
    [self promptAboutRemainingInBetaIfNeeded];

    // Set the Appcast URL and when it changes update it.
    [[iTermController sharedInstance] refreshSoftwareUpdateUserDefaults];
    [iTermPreferences addObserverForKey:kPreferenceKeyCheckForTestReleases
                                  block:^(id before, id after) {
                                      [[iTermController sharedInstance] refreshSoftwareUpdateUserDefaults];
                                  }];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [self warnAboutChangeToDefaultPasteBehavior];
    if (IsTouchBarAvailable()) {
        ITERM_IGNORE_PARTIAL_BEGIN
        NSApp.automaticCustomizeTouchBarMenuItemEnabled = YES;
        ITERM_IGNORE_PARTIAL_END
    }

    if ([iTermAdvancedSettingsModel enableAPIServer]) {
        _apiServer = [[iTermAPIServer alloc] init];
        _apiServer.delegate = self;
    }

    if ([self shouldNotifyAboutIncompatibleSoftware]) {
        [self notifyAboutIncompatibleSoftware];
    }
    if ([iTermAdvancedSettingsModel disableAppNap]) {
        [[NSProcessInfo processInfo] setAutomaticTerminationSupportEnabled:YES];
        [[NSProcessInfo processInfo] disableAutomaticTermination:@"User Preference"];
        _appNapStoppingActivity =
                [[[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiatedAllowingIdleSystemSleep
                                                                reason:@"User Preference"] retain];
    }
    [iTermFontPanel makeDefault];

    finishedLaunching_ = YES;
    // Create the app support directory
    [self createVersionFile];

    // Prevent the input manager from swallowing control-q. See explanation here:
    // http://b4winckler.wordpress.com/2009/07/19/coercing-the-cocoa-text-system/
    CFPreferencesSetAppValue(CFSTR("NSQuotedKeystrokeBinding"),
                             CFSTR(""),
                             kCFPreferencesCurrentApplication);
    // This is off by default, but would wreack havoc if set globally.
    CFPreferencesSetAppValue(CFSTR("NSRepeatCountBinding"),
                             CFSTR(""),
                             kCFPreferencesCurrentApplication);

    // Ensure hotkeys are registered.
    [iTermAppHotKeyProvider sharedInstance];
    [iTermHotKeyProfileBindingController sharedInstance];

    if ([[iTermModifierRemapper sharedInstance] isAnyModifierRemapped]) {
        // Use a brief delay so windows have a chance to open before the dialog is shown.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if ([[iTermModifierRemapper sharedInstance] isAnyModifierRemapped]) {
              [[iTermModifierRemapper sharedInstance] setRemapModifiers:YES];
            }
        });
    }
    [self updateRestoreWindowArrangementsMenu:windowArrangements_ asTabs:NO];
    [self updateRestoreWindowArrangementsMenu:windowArrangementsAsTabs_ asTabs:YES];

    // register for services
    [NSApp registerServicesMenuSendTypes:[NSArray arrayWithObjects:NSStringPboardType, nil]
                                                       returnTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, NSStringPboardType, nil]];
    // Register our services provider. Registration must happen only when we're
    // ready to accept requests, so I do it after a spin of the runloop.
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSApp setServicesProvider:[[iTermServiceProvider alloc] init]];
    });

    // Sometimes, open untitled doc isn't called in Lion. We need to give application:openFile:
    // a chance to run because a "special" filename cancels performStartupActivities.
    [self checkForQuietMode];
    [self performSelector:@selector(performStartupActivities)
               withObject:nil
               afterDelay:0];
    [[NSNotificationCenter defaultCenter] postNotificationName:kApplicationDidFinishLaunchingNotification
                                                        object:nil];

    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(workspaceSessionDidBecomeActive:)
                                                               name:NSWorkspaceSessionDidBecomeActiveNotification
                                                             object:nil];

    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(workspaceSessionDidResignActive:)
                                                               name:NSWorkspaceSessionDidResignActiveNotification
                                                             object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(sparkleWillRestartApp:)
                                                 name:SUUpdaterWillRestartNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(processTypeDidChange:)
                                                 name:iTermProcessTypeDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(dynamicToolsDidChange:)
                                                 name:kDynamicToolsDidChange
                                               object:nil];

    if ([iTermAdvancedSettingsModel runJobsInServers] &&
        !self.isApplescriptTestApp) {
        [PseudoTerminalRestorer setRestorationCompletionBlock:^{
            [self restoreBuriedSessionsState];
            if ([[iTermController sharedInstance] numberOfDecodesPending] == 0) {
                _orphansAdopted = YES;
                [[iTermOrphanServerAdopter sharedInstance] openWindowWithOrphans];
            } else {
                [[NSNotificationCenter defaultCenter] addObserver:self
                                                         selector:@selector(itermDidDecodeWindowRestorableState:)
                                                             name:iTermDidDecodeWindowRestorableStateNotification
                                                           object:nil];
            }
        }];
    } else {
        [self restoreBuriedSessionsState];
    }
}

- (NSMenu *)statusBarMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *item;

    item = [[[NSMenuItem alloc] initWithTitle:@"Preferences"
                                       action:@selector(showAndOrderFrontRegardlessPrefWindow:)
                                keyEquivalent:@""] autorelease];
    [menu addItem:item];
    
    item = [[[NSMenuItem alloc] initWithTitle:@"Bring All Windows to Front"
                                       action:@selector(arrangeInFront:)
                                keyEquivalent:@""] autorelease];
    [menu addItem:item];

    item = [[[NSMenuItem alloc] initWithTitle:@"Check For Updates"
                                       action:@selector(checkForUpdatesFromMenu:)
                                keyEquivalent:@""] autorelease];
    [menu addItem:item];

    item = [[[NSMenuItem alloc] initWithTitle:@"Quit iTerm2"
                                       action:@selector(terminate:)
                                keyEquivalent:@""] autorelease];
    [menu addItem:item];
    return menu;
}

#pragma mark - Notifications

- (void)workspaceSessionDidBecomeActive:(NSNotification *)notification {
    _workspaceSessionActive = YES;
}

- (void)workspaceSessionDidResignActive:(NSNotification *)notification {
    _workspaceSessionActive = NO;
}

- (void)sparkleWillRestartApp:(NSNotification *)notification {
    [NSApp invalidateRestorableState];
    [[NSApp windows] makeObjectsPerformSelector:@selector(invalidateRestorableState)];
    _sparkleRestarting = YES;
}

- (void)itermDidDecodeWindowRestorableState:(NSNotification *)notification {
    if (!_orphansAdopted && [[iTermController sharedInstance] numberOfDecodesPending] == 0) {
        _orphansAdopted = YES;
        [[iTermOrphanServerAdopter sharedInstance] openWindowWithOrphans];
    }
}

- (void)dynamicToolsDidChange:(NSNotification *)notification {
    [iTermToolbeltView populateMenu:toolbeltMenu];
}

- (void)processTypeDidChange:(NSNotification *)notification {
    [self updateProcessType];
}

- (void)windowArrangementsDidChange:(id)sender {
    [self updateRestoreWindowArrangementsMenu:windowArrangements_ asTabs:NO];
    [self updateRestoreWindowArrangementsMenu:windowArrangementsAsTabs_ asTabs:YES];
}

- (void)toolDidToggle:(NSNotification *)notification {
    NSString *theName = [notification object];
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        [[term toolbelt] toggleToolWithName:theName];
        [term refreshTools];
    }
    NSMenuItem *menuItem = [toolbeltMenu itemWithTitle:theName];

    NSInteger newState = ([menuItem state] == NSOnState) ? NSOffState : NSOnState;
    [menuItem setState:newState];
}

- (void)sessionCreated:(NSNotification *)notification {
    PTYSession *session = notification.object;
    [_newSessionSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
        ITMNotification *notification = [[[ITMNotification alloc] init] autorelease];
        notification.newSessionNotification = [[[ITMNewSessionNotification alloc] init] autorelease];
        notification.newSessionNotification.uniqueIdentifier = session.guid;
        [[[iTermApplication sharedApplication] delegate] postAPINotification:notification toConnection:key];
    }];
}

- (void)layoutChanged:(NSNotification *)notification {
    if (!_layoutChanged) {
        _layoutChanged = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            _layoutChanged = NO;
            [_layoutChangeSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
                ITMNotification *notification = [[[ITMNotification alloc] init] autorelease];
                notification.layoutChangedNotification.listSessionsResponse = [self newListSessionsResponse];
                [[[iTermApplication sharedApplication] delegate] postAPINotification:notification toConnection:key];
            }];
        });
    }
}

- (void)sessionDidTerminate:(NSNotification *)notification {
    PTYSession *session = notification.object;
    [_terminateSessionSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
        ITMNotification *notification = [[[ITMNotification alloc] init] autorelease];
        notification.terminateSessionNotification = [[[ITMTerminateSessionNotification alloc] init] autorelease];
        notification.terminateSessionNotification.uniqueIdentifier = session.guid;
        [[[iTermApplication sharedApplication] delegate] postAPINotification:notification toConnection:key];
    }];
}

- (void)getUrl:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent {
    NSString *urlStr = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
    NSURL *url = [NSURL URLWithString:urlStr];
    NSString *scheme = [url scheme];

    Profile *profile = [[iTermLaunchServices sharedInstance] profileForScheme:scheme];
    if (!profile) {
        profile = [[ProfileModel sharedInstance] defaultBookmark];
    }
    if (profile) {
        iTermProfileHotKey *profileHotkey = [[iTermHotKeyController sharedInstance] profileHotKeyForGUID:profile[KEY_GUID]];
        PseudoTerminal *term = [[iTermController sharedInstance] currentTerminal];
        BOOL launch = NO;
        if (profileHotkey) {
            const BOOL newWindowCreated = [[iTermHotKeyController sharedInstance] showWindowForProfileHotKey:profileHotkey
                                                                                                         url:url];
            if (!newWindowCreated) {
                launch = YES;
                term = profileHotkey.windowController;
            }
        } else {
            launch = YES;
        }
        if (launch) {
            [[iTermController sharedInstance] launchBookmark:profile
                                                  inTerminal:term
                                                     withURL:urlStr
                                            hotkeyWindowType:iTermHotkeyWindowTypeNone
                                                     makeKey:NO
                                                 canActivate:NO
                                                     command:nil
                                                       block:nil];
        }
    }
}

- (void)reloadMenus:(NSNotification *)aNotification {
    PseudoTerminal *frontTerminal = [self currentTerminal];
    if (frontTerminal != [aNotification object]) {
        return;
    }

    [self buildSessionSubmenu: aNotification];
    // reset the close tab/window shortcuts
    [closeTab setAction:@selector(closeCurrentTab:)];
    [closeTab setTarget:frontTerminal];
    [closeTab setKeyEquivalent:@"w"];
    [closeWindow setKeyEquivalent:@"W"];
    [closeWindow setKeyEquivalentModifierMask: NSCommandKeyMask];
}

- (void)nonTerminalWindowBecameKey:(NSNotification *)aNotification {
    [closeTab setAction:nil];
    [closeTab setKeyEquivalent:@""];
    [closeWindow setKeyEquivalent:@"w"];
    [closeWindow setKeyEquivalentModifierMask:NSCommandKeyMask];
}

- (void)updateAddressBookMenu:(NSNotification*)aNotification {
    DLog(@"Updating address book menu");
    JournalParams params;
    params.selector = @selector(newSessionInTabAtIndex:);
    params.openAllSelector = @selector(newSessionsInWindow:);
    params.alternateSelector = @selector(newSessionInWindowAtIndex:);
    params.alternateOpenAllSelector = @selector(newSessionsInWindow:);
    params.target = [iTermController sharedInstance];

    [ProfileModel applyJournal:[aNotification userInfo]
                         toMenu:bookmarkMenu
                 startingAtItem:5
                         params:&params];
}

#pragma mark - Startup Helpers

- (void)promptAboutRemainingInBetaIfNeeded {
    // For a long time—too long—users were opted into the beta program. There are too many of them
    // and they don't know it and some of them feel bad feelings. So we'll help them get out. I
    // don't like spamming you with crap so let's just do this for a few weeks and that'll fix
    // almost all of the problem.
    if ([NSDate timeIntervalSinceReferenceDate] > 489542400) {  // Midnight GMT July 7 2016
        return;
    }
    static NSString *kHaveAskedAboutBetaKey = @"NoSyncConfirmBeta";
    const BOOL haveAsked = [[NSUserDefaults standardUserDefaults] boolForKey:kHaveAskedAboutBetaKey];
    if (haveAsked) {
        return;
    }
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kHaveAskedAboutBetaKey];

    if ([NSBundle it_isNightlyBuild]) {
        return;
    }
    
    const BOOL inBeta = [iTermPreferences boolForKey:kPreferenceKeyCheckForTestReleases];
    if (!inBeta) {
        return;
    }

    const BOOL isEarlyAdopter = [NSBundle it_isEarlyAdopter];
    if (isEarlyAdopter) {
        // Early adopters who are already beta testers won't get prompted.
        // They are the new "real" beta testers.
        return;
    }

    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = @"Beta Test Program";
    alert.informativeText = @"Would you like to beta test versions of iTerm2 when it updates?";
    [alert addButtonWithTitle:@"Yes, I Want Beta Test Versions"];
    [alert addButtonWithTitle:@"No, Release Versions Only"];
    const NSModalResponse response = [alert runModal];

    const BOOL wantBeta = (response == NSAlertFirstButtonReturn);
    [[NSUserDefaults standardUserDefaults] setBool:wantBeta
                                            forKey:kPreferenceKeyCheckForTestReleases];
}

// This performs startup activities as long as they haven't been run before.
- (void)performStartupActivities {
    if (gStartupActivitiesPerformed) {
        return;
    }
    gStartupActivitiesPerformed = YES;
    if (quiet_) {
        // iTerm2 was launched with "open file" that turns off startup activities.
        return;
    }
    [[iTermController sharedInstance] setStartingUp:YES];
    // Check if we have an autolaunch script to execute. Do it only once, i.e. at application launch.
    NSString *autolaunchScriptPath = [[NSFileManager defaultManager] autolaunchScriptPath];
    if (ranAutoLaunchScript == NO &&
        [[NSFileManager defaultManager] fileExistsAtPath:autolaunchScriptPath]) {
        ranAutoLaunchScript = YES;

        NSAppleScript *autoLaunchScript;
        NSDictionary *errorInfo = [NSDictionary dictionary];
        NSURL *aURL = [NSURL fileURLWithPath:autolaunchScriptPath];

        // Make sure our script suite registry is loaded
        [NSScriptSuiteRegistry sharedScriptSuiteRegistry];

        autoLaunchScript = [[NSAppleScript alloc] initWithContentsOfURL:aURL
                                                                  error:&errorInfo];
        [autoLaunchScript executeAndReturnError:&errorInfo];
        [autoLaunchScript release];
    } else {
        if ([WindowArrangements defaultArrangementName] == nil &&
            [WindowArrangements arrangementWithName:LEGACY_DEFAULT_ARRANGEMENT_NAME] != nil) {
            [WindowArrangements makeDefaultArrangement:LEGACY_DEFAULT_ARRANGEMENT_NAME];
        }

        if ([iTermPreferences boolForKey:kPreferenceKeyOpenBookmark]) {
            // Open bookmarks window at startup.
            [self showBookmarkWindow:nil];
        }

        if ([iTermPreferences boolForKey:kPreferenceKeyOpenArrangementAtStartup]) {
            // Open the saved arrangement at startup.
            [[iTermController sharedInstance] loadWindowArrangementWithName:[WindowArrangements defaultArrangementName]];
        } else if (![iTermPreferences boolForKey:kPreferenceKeyOpenNoWindowsAtStartup] &&
                   ![PseudoTerminalRestorer willOpenWindows] &&
                   [[[iTermController sharedInstance] terminals] count] == 0 &&
                   ![self isApplescriptTestApp] &&
                   [[[iTermHotKeyController sharedInstance] profileHotKeys] count] == 0 &&
                   [[[iTermBuriedSessions sharedInstance] buriedSessions] count] == 0) {
            [self newWindow:nil];
        }
    }

    [[iTermController sharedInstance] setStartingUp:NO];
    [PTYSession removeAllRegisteredSessions];
    ranAutoLaunchScript = YES;

    [[iTermTipController sharedInstance] applicationDidFinishLaunching];
}

- (void)createVersionFile {
    NSDictionary *myDict = [[NSBundle bundleForClass:[self class]] infoDictionary];
    NSString *versionString = [myDict objectForKey:@"CFBundleVersion"];
    [versionString writeToFile:[[NSFileManager defaultManager] versionNumberFilename]
                    atomically:NO
                      encoding:NSUTF8StringEncoding
                         error:nil];
}

- (BOOL)quietFileExists {
    return [[NSFileManager defaultManager] fileExistsAtPath:[[NSFileManager defaultManager] quietFilePath]];
}

- (void)checkForQuietMode {
    if ([self quietFileExists]) {
        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:[[NSFileManager defaultManager] quietFilePath]
                                                   error:&error];
        if (error) {
            NSLog(@"Failed to remove %@: %@; not launching in quiet mode", [[NSFileManager defaultManager] quietFilePath], error);
        } else {
            NSLog(@"%@ exists, launching in quiet mode", [[NSFileManager defaultManager] quietFilePath]);
            quiet_ = YES;
        }
    }
}

- (BOOL)shouldNotifyAboutIncompatibleSoftware {
    // Pending discussions:
    // Docker: https://github.com/docker/kitematic/pull/855
    // LaunchBar: https://twitter.com/launchbar/status/620975715278790657?cn=cmVwbHk%3D&refsrc=email
    // Pathfinder: https://twitter.com/gnachman/status/659409608642007041
    // Tower: Filed a bug. Tracking with issue 4722 on my side
    
    // This is disabled because it looks like everyone is there or almost there. I can remove this
    // code soon.
//#define SHOW_INCOMPATIBILITY_WARNING_AT_STARTUP

#ifdef SHOW_INCOMPATIBILITY_WARNING_AT_STARTUP
    static NSString *const kTimeOfFirstLaunchForIncompatibilityWarnings = @"NoSyncTimeOfFirstLaunchForIncompatibilityWarnings";
    static const NSTimeInterval kMinimumDelayBeforeWarningAboutIncompatibility = 24 * 60 * 60;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval timeOfFirstLaunchForIncompatibilityWarnings =
        [[NSUserDefaults standardUserDefaults] doubleForKey:kTimeOfFirstLaunchForIncompatibilityWarnings];
    if (!timeOfFirstLaunchForIncompatibilityWarnings) {
        [[NSUserDefaults standardUserDefaults] setDouble:now
                                                  forKey:kTimeOfFirstLaunchForIncompatibilityWarnings];
    } else if (now - timeOfFirstLaunchForIncompatibilityWarnings > kMinimumDelayBeforeWarningAboutIncompatibility) {
        return ![[NSUserDefaults standardUserDefaults] boolForKey:kHaveWarnedAboutIncompatibleSoftware];
    }
#endif
    return NO;
}

- (NSString *)shortVersionStringOfAppWithBundleId:(NSString *)bundleId {
    NSString *bundlePath =
            [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:bundleId];
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    NSDictionary *info = [bundle infoDictionary];
    NSString *version = info[@"CFBundleShortVersionString"];
    return version;
}

- (BOOL)version:(NSString *)version newerThan:(NSString *)otherVersion {
    id<SUVersionComparison> comparator = [SUStandardVersionComparator defaultComparator];
    NSInteger result = [comparator compareVersion:version toVersion:otherVersion];
    return result == NSOrderedDescending;
}

- (void)notifyAboutIncompatibleVersionOf:(NSString *)name url:(NSString *)urlString upgradeAvailable:(BOOL)upgradeAvailable {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = @"Incompatible Software Detected";
    [alert addButtonWithTitle:@"OK"];
    if (upgradeAvailable) {
        alert.informativeText = [NSString stringWithFormat:@"You need to upgrade %@ to use it with this version of iTerm2.", name];
    } else {
        alert.informativeText = [NSString stringWithFormat:@"You have a version of %@ installed which is not compatible with this version of iTerm2.", name];
        [alert addButtonWithTitle:@"Learn More"];
    }

    if ([alert runModal] == NSAlertSecondButtonReturn) {
        NSURL *url = [NSURL URLWithString:urlString];
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

- (BOOL)notifyAboutIncompatibleSoftware {
    BOOL found = NO;

    NSString *dockerVersion = [self shortVersionStringOfAppWithBundleId:@"com.apple.ScriptEditor.id.dockerquickstartterminalapp"];
    if (dockerVersion && ![self version:dockerVersion newerThan:@"1.3.0"]) {
        [self notifyAboutIncompatibleVersionOf:@"Docker Quickstart Terminal"
                                           url:@"https://gitlab.com/gnachman/iterm2/wikis/dockerquickstartincompatible"
                              upgradeAvailable:NO];
        found = YES;
    }

    NSString *launchBarVersion = [self shortVersionStringOfAppWithBundleId:@"at.obdev.LaunchBar"];
    if (launchBarVersion && ![self version:launchBarVersion newerThan:@"6.6.2"]) {
        [self notifyAboutIncompatibleVersionOf:@"LaunchBar"
                                           url:@"https://gitlab.com/gnachman/iterm2/wikis/dockerquickstartincompatible"
                              upgradeAvailable:NO];
        found = YES;
    }

    NSString *pathfinderVersion = [self shortVersionStringOfAppWithBundleId:@"com.cocoatech.PathFinder"];
    if (pathfinderVersion && ![self version:pathfinderVersion newerThan:@"7.3.3"]) {
        [self notifyAboutIncompatibleVersionOf:@"Pathfinder"
                                           url:@"https://gitlab.com/gnachman/iterm2/wikis/pathfinder7compatibility"
                              upgradeAvailable:NO];
        found = YES;
    }

    NSString *towerVersion = [self shortVersionStringOfAppWithBundleId:@"com.fournova.Tower2"];
    if (towerVersion && ![self version:towerVersion newerThan:@"2.3.4"]) {
        [self notifyAboutIncompatibleVersionOf:@"Tower"
                                           url:@"https://gitlab.com/gnachman/iterm2/wikis/towercompatibility"
                              upgradeAvailable:NO];
        found = YES;
    }
    
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kHaveWarnedAboutIncompatibleSoftware];
    return found;
}

- (IBAction)checkForIncompatibleSoftware:(id)sender {
    if (![self notifyAboutIncompatibleSoftware]) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.messageText = @"No Incompatible Software Detected";
        alert.informativeText = @"No third-party software that is known to be incompatible with iTerm2’s new Applescript interfaces was found.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    }
}

- (IBAction)checkForUpdatesFromMenu:(id)sender {
    [suUpdater checkForUpdates:(sender)];
}

- (void)warnAboutChangeToDefaultPasteBehavior {
    static NSString *const kHaveWarnedAboutPasteConfirmationChange = @"NoSyncHaveWarnedAboutPasteConfirmationChange";
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kHaveWarnedAboutPasteConfirmationChange]) {
        // Safety check that we definitely don't show this twice.
        return;
    }
    NSString *identifier = [iTermAdvancedSettingsModel noSyncDoNotWarnBeforeMultilinePasteUserDefaultsKey];
    if ([iTermWarning identifierIsSilenced:identifier]) {
        return;
    }

    NSArray *warningList = @[ @"3.0.0", @"3.0.1", @"3.0.2", @"3.0.3", @"3.0.4", @"3.0.5", @"3.0.6", @"3.0.7", @"3.0.8", @"3.0.9", @"3.0.10" ];
    if ([warningList containsObject:[iTermPreferences appVersionBeforeThisLaunch]]) {
        [iTermWarning showWarningWithTitle:@"iTerm2 no longer warns before a multi-line paste, unless you are at the shell prompt."
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:nil
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Important Change"];
    }

    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kHaveWarnedAboutPasteConfirmationChange];
}

#pragma mark - Main Menu

- (void)updateRestoreWindowArrangementsMenu:(NSMenuItem *)menuItem asTabs:(BOOL)asTabs {
    [WindowArrangements refreshRestoreArrangementsMenu:menuItem
                                          withSelector:asTabs ? @selector(restoreWindowArrangementAsTabs:) : @selector(restoreWindowArrangement:)
                                       defaultShortcut:kRestoreDefaultWindowArrangementShortcut
                                            identifier:asTabs ? @"Restore Window Arrangement as Tabs" : @"Restore Window Arrangement"];
}

- (NSMenu *)topLevelViewNamed:(NSString *)menuName {
    NSMenu *appMenu = [NSApp mainMenu];
    NSMenuItem *topLevelMenuItem = [appMenu itemWithTitle:menuName];
    NSMenu *menu = [topLevelMenuItem submenu];
    return menu;
}

- (void)addMenuItemView:(NSView *)view toMenu:(NSMenu *)menu title:(NSString *)title {
    NSMenuItem *newItem;
    newItem = [[[NSMenuItem alloc] initWithTitle:title
                                       action:@selector(changeTabColorToMenuAction:)
                                keyEquivalent:@""] autorelease];
    [newItem setView:view];
    [menu addItem:newItem];
}

- (void)newSessionMenu:(NSMenu *)superMenu
                 title:(NSString*)title
                target:(id)aTarget
              selector:(SEL)selector
       openAllSelector:(SEL)openAllSelector {
    //new window menu
    NSMenuItem *newMenuItem;
    NSMenu *bookmarksMenu;
    newMenuItem = [[NSMenuItem alloc] initWithTitle:title
                                             action:nil
                                      keyEquivalent:@""];
    [superMenu addItem:newMenuItem];
    [newMenuItem release];

    // Create the bookmark submenus for new session
    // Build the bookmark menu
    bookmarksMenu = [[[NSMenu alloc] init] autorelease];

    [[iTermController sharedInstance] addBookmarksToMenu:bookmarksMenu
                                            withSelector:selector
                                         openAllSelector:openAllSelector
                                              startingAt:0];
    [newMenuItem setSubmenu:bookmarksMenu];
}

- (NSMenu*)bookmarksMenu {
    return bookmarkMenu;
}

- (void)_addArrangementsMenuTo:(NSMenu *)theMenu {
    NSMenuItem *container = [theMenu addItemWithTitle:@"Restore Arrangement"
                                               action:nil
                                        keyEquivalent:@""];
    NSMenu *subMenu = [[[NSMenu alloc] init] autorelease];
    [container setSubmenu:subMenu];
    [self updateRestoreWindowArrangementsMenu:container asTabs:NO];
}

- (void)buildSessionSubmenu:(NSNotification *)aNotification {
    [self updateMaximizePaneMenuItem];

    // build a submenu to select tabs
    PseudoTerminal *currentTerminal = [self currentTerminal];

    if (currentTerminal != [aNotification object] ||
        ![[currentTerminal window] isKeyWindow]) {
        return;
    }

    NSMenu *aMenu = [[NSMenu alloc] initWithTitle: @"SessionMenu"];
    PTYTabView *aTabView = [currentTerminal tabView];
    NSArray *tabViewItemArray = [aTabView tabViewItems];
    int i=1;

    // clear whatever menu we already have
    [selectTab setSubmenu:nil];

    for (NSTabViewItem *aTabViewItem in tabViewItemArray) {
        PTYTab *aTab = [aTabViewItem identifier];
        NSMenuItem *aMenuItem;

        if ([aTab activeSession]) {
            aMenuItem  = [[NSMenuItem alloc] initWithTitle:[[aTab activeSession] name]
                                                    action:@selector(selectSessionAtIndexAction:)
                                             keyEquivalent:@""];
            [aMenuItem setTag:i-1];
            [aMenu addItem:aMenuItem];
            [aMenuItem release];
        }
        i++;
    }

    [selectTab setSubmenu:aMenu];

    [aMenu release];
}

- (void)_removeItemsFromMenu:(NSMenu*)menu {
    while ([menu numberOfItems] > 0) {
        NSMenuItem* item = [menu itemAtIndex:0];
        NSMenu* sub = [item submenu];
        if (sub) {
            [self _removeItemsFromMenu:sub];
        }
        [menu removeItemAtIndex:0];
    }
}

// This is called whenever a tab becomes key or logging starts/stops.
- (void)reloadSessionMenus:(NSNotification *)aNotification {
    [self updateMaximizePaneMenuItem];

    PseudoTerminal *currentTerminal = [self currentTerminal];
    PTYSession* aSession = [aNotification object];

    if (currentTerminal != [[aSession delegate] parentWindow] ||
        ![[currentTerminal window] isKeyWindow]) {
        return;
    }

    if (aSession == nil || [aSession exited]) {
        [logStart setEnabled: NO];
        [logStop setEnabled: NO];
    } else {
        [logStart setEnabled: ![aSession logging]];
        [logStop setEnabled: [aSession logging]];
    }
}

#pragma mark - Actions

- (IBAction)makeDefaultTerminal:(id)sender {
    [[iTermLaunchServices sharedInstance] makeITermDefaultTerminal];
}

- (IBAction)unmakeDefaultTerminal:(id)sender {
    [[iTermLaunchServices sharedInstance] makeTerminalDefaultTerminal];
}

- (void)restoreWindowArrangement:(id)sender {
    [[iTermController sharedInstance] loadWindowArrangementWithName:[sender title]];
}

- (void)restoreWindowArrangementAsTabs:(id)sender {
    [[iTermController sharedInstance] loadWindowArrangementWithName:[sender title] asTabs:YES];
}

- (IBAction)togglePinHotkeyWindow:(id)sender {
    iTermProfileHotKey *profileHotkey = self.currentProfileHotkey;
    profileHotkey.autoHides = !profileHotkey.autoHides;
}

- (IBAction)openPasswordManager:(id)sender {
    DLog(@"Menu item selected");
    [self openPasswordManagerToAccountName:nil inSession:nil];
}

- (IBAction)toggleToolbeltTool:(NSMenuItem *)menuItem {
    if ([iTermToolbeltView numberOfVisibleTools] == 1 && [menuItem state] == NSOnState) {
        return;
    }
    [iTermToolbeltView toggleShouldShowTool:[menuItem title]];
}

- (IBAction)toggleFullScreenTabBar:(id)sender {
    BOOL value = [iTermPreferences boolForKey:kPreferenceKeyShowFullscreenTabBar];
    [iTermPreferences setBool:!value forKey:kPreferenceKeyShowFullscreenTabBar];
    [[NSNotificationCenter defaultCenter] postNotificationName:kShowFullscreenTabsSettingDidChange
                                                        object:nil
                                                      userInfo:nil];
}

- (IBAction)newWindow:(id)sender {
    DLog(@"newWindow: invoked");
    BOOL cancel;
    BOOL tmux = [self possiblyTmuxValueForWindow:YES cancel:&cancel];
    if (!cancel) {
        [[iTermController sharedInstance] newWindow:sender possiblyTmux:tmux];
    }
}

- (IBAction)newSessionWithSameProfile:(id)sender
{
    [[iTermController sharedInstance] newSessionWithSameProfile:sender];
}

- (IBAction)newSession:(id)sender
{
    DLog(@"iTermApplicationDelegate newSession:");
    BOOL cancel;
    BOOL tmux = [self possiblyTmuxValueForWindow:NO cancel:&cancel];
    if (!cancel) {
        [[iTermController sharedInstance] newSession:sender possiblyTmux:tmux];
    }
}

- (IBAction)arrangeHorizontally:(id)sender
{
    [[iTermController sharedInstance] arrangeHorizontally];
}

- (IBAction)showPrefWindow:(id)sender {
    [[PreferencePanel sharedInstance] run];
    [[[PreferencePanel sharedInstance] window] makeKeyAndOrderFront:self];
}

- (IBAction)showAndOrderFrontRegardlessPrefWindow:(id)sender {
    [self showPrefWindow:sender];
    [[[PreferencePanel sharedInstance] window] orderFrontRegardless];
}

- (IBAction)showBookmarkWindow:(id)sender
{
    [[iTermProfilesWindowController sharedInstance] showWindow:sender];
}

- (IBAction)biggerFont:(id)sender {
    for (PTYSession *session in [self sessionsToAdjustFontSize]) {
        [session changeFontSizeDirection:1];
    }
}

- (IBAction)smallerFont:(id)sender {
    for (PTYSession *session in [self sessionsToAdjustFontSize]) {
        [session changeFontSizeDirection:-1];
    }
}

- (IBAction)returnToDefaultSize:(id)sender {
    PseudoTerminal *frontTerminal = [[iTermController sharedInstance] currentTerminal];
    PTYSession *session = [frontTerminal currentSession];
    if (![sender isAlternate]) {
        for (PTYSession *session in [self sessionsToAdjustFontSize]) {
            [session changeFontSizeDirection:0];
        }
    } else {
        [session changeFontSizeDirection:0];
    }
    if ([sender isAlternate]) {
        NSDictionary *abEntry = [session originalProfile];
        [frontTerminal sessionInitiatedResize:session
                                        width:[[abEntry objectForKey:KEY_COLUMNS] intValue]
                                       height:[[abEntry objectForKey:KEY_ROWS] intValue]];
    }
}

- (IBAction)pasteFaster:(id)sender
{
    [self changePasteSpeedBy:1.5
                    bytesKey:@"QuickPasteBytesPerCall"
                defaultBytes:1024
                    delayKey:@"QuickPasteDelayBetweenCalls"
                defaultDelay:.01];
}

- (IBAction)pasteSlower:(id)sender
{
    [self changePasteSpeedBy:0.66
                    bytesKey:@"QuickPasteBytesPerCall"
                defaultBytes:1024
                    delayKey:@"QuickPasteDelayBetweenCalls"
                defaultDelay:.01];
}

- (IBAction)pasteSlowlyFaster:(id)sender
{
    [self changePasteSpeedBy:1.5
                    bytesKey:@"SlowPasteBytesPerCall"
                defaultBytes:16
                    delayKey:@"SlowPasteDelayBetweenCalls"
                defaultDelay:0.125];
}

- (IBAction)pasteSlowlySlower:(id)sender
{
    [self changePasteSpeedBy:0.66
                    bytesKey:@"SlowPasteBytesPerCall"
                defaultBytes:16
                    delayKey:@"SlowPasteDelayBetweenCalls"
                defaultDelay:0.125];
}

- (IBAction)undo:(id)sender {
    NSResponder *undoResponder = [self responderForMenuItem:sender];
    if (undoResponder) {
        [undoResponder performSelector:@selector(undo:) withObject:sender];
    } else {
        iTermController *controller = [iTermController sharedInstance];
        iTermRestorableSession *restorableSession = [controller popRestorableSession];
        if (restorableSession) {
            PseudoTerminal *term;
            PTYTab *tab;

            switch (restorableSession.group) {
                case kiTermRestorableSessionGroupSession:
                    // Restore a single session.
                    DLog(@"Restore a single session");
                    term = [controller terminalWithGuid:restorableSession.terminalGuid];
                    if (term) {
                        DLog(@"resuse an existing window");
                        // Reuse an existing window
                        tab = [term tabWithUniqueId:restorableSession.tabUniqueId];
                        if (tab) {
                            // Add to existing tab by destroying and recreating it.
                            [term recreateTab:tab
                              withArrangement:restorableSession.arrangement
                                     sessions:restorableSession.sessions
                                       revive:YES];
                        } else {
                            // Create a new tab and add the session to it.
                            [restorableSession.sessions[0] revive];
                            [term addRevivedSession:restorableSession.sessions[0]];
                        }
                    } else {
                        DLog(@"Create a new window");
                        // Create a new term and add the session to it.
                        term = [[[PseudoTerminal alloc] initWithSmartLayout:YES
                                                                 windowType:WINDOW_TYPE_NORMAL
                                                            savedWindowType:WINDOW_TYPE_NORMAL
                                                                     screen:-1] autorelease];
                        if (term) {
                            [[iTermController sharedInstance] addTerminalWindow:term];
                            term.terminalGuid = restorableSession.terminalGuid;
                            [restorableSession.sessions[0] revive];
                            [term addRevivedSession:restorableSession.sessions[0]];
                            [term fitWindowToTabs];
                        }
                    }
                    break;

                case kiTermRestorableSessionGroupTab:
                    // Restore a tab, possibly with multiple sessions in split panes.
                    DLog(@"Restore a tab, possibly with multiple sessions in split panes");
                    term = [controller terminalWithGuid:restorableSession.terminalGuid];
                    BOOL fitTermToTabs = NO;
                    if (!term) {
                        // Create a new window
                        DLog(@"Create a new window");
                        term = [[[PseudoTerminal alloc] initWithSmartLayout:YES
                                                                 windowType:WINDOW_TYPE_NORMAL
                                                            savedWindowType:WINDOW_TYPE_NORMAL
                                                                     screen:-1] autorelease];
                        [[iTermController sharedInstance] addTerminalWindow:term];
                        term.terminalGuid = restorableSession.terminalGuid;
                        fitTermToTabs = YES;
                    }
                    // Add a tab to it.
                    DLog(@"Add a tab to the window");
                    [term addTabWithArrangement:restorableSession.arrangement
                                       uniqueId:restorableSession.tabUniqueId
                                       sessions:restorableSession.sessions
                                   predecessors:restorableSession.predecessors];
                    if (fitTermToTabs) {
                        [term fitWindowToTabs];
                    }
                    break;

                case kiTermRestorableSessionGroupWindow:
                    // Restore a widow.
                    DLog(@"Restore a widow");
                    term = [PseudoTerminal terminalWithArrangement:restorableSession.arrangement
                                                          sessions:restorableSession.sessions
                                          forceOpeningHotKeyWindow:YES];
                    [[iTermController sharedInstance] addTerminalWindow:term];
                    term.terminalGuid = restorableSession.terminalGuid;
                    break;
            }
        }
    }
}

- (IBAction)toggleMultiLinePasteWarning:(NSButton *)sender {
    if (sender.tag == 0) {
        [iTermAdvancedSettingsModel setNoSyncDoNotWarnBeforeMultilinePaste:![iTermAdvancedSettingsModel noSyncDoNotWarnBeforeMultilinePaste]];
    } else if (sender.tag == 1) {
        [iTermAdvancedSettingsModel setPromptForPasteWhenNotAtPrompt:![iTermAdvancedSettingsModel promptForPasteWhenNotAtPrompt]];
    } else if (sender.tag == 2) {
        [iTermAdvancedSettingsModel setNoSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt:![iTermAdvancedSettingsModel noSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt]];
    }
}

- (IBAction)maximizePane:(id)sender {
    [[[iTermController sharedInstance] currentTerminal] toggleMaximizeActivePane];
    [self updateMaximizePaneMenuItem];
}

- (IBAction)toggleUseTransparency:(id)sender {
    [[[iTermController sharedInstance] currentTerminal] toggleUseTransparency:sender];
    [self updateUseTransparencyMenuItem];
}

- (IBAction)toggleSecureInput:(id)sender {
    // Set secureInputDesired_ to the opposite of the current state.
    secureInputDesired_ = !IsSecureEventInputEnabled();
    DLog(@"toggleSecureInput called. Setting desired to %d", (int)secureInputDesired_);

    // Try to set the system's state of secure input to the desired state.
    [self setSecureInput:secureInputDesired_];

    // Save the preference, independent of whether it succeeded or not.
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:secureInputDesired_]
                                              forKey:@"Secure Input"];
}

- (IBAction)debugLogging:(id)sender {
  ToggleDebugLogging();
}

- (IBAction)openQuickly:(id)sender {
    [[iTermOpenQuicklyWindowController sharedInstance] presentWindow];
}

- (IBAction)showAbout:(id)sender {
    [[iTermAboutWindowController sharedInstance] showWindow:self];
}

- (IBAction)exposeForTabs:(id)sender {
    [iTermExpose toggle];
}

- (void)clearAllDownloads:(id)sender {
    [[FileTransferManager sharedInstance] removeAllDownloads];
}

- (void)clearAllUploads:(id)sender{
    [[FileTransferManager sharedInstance] removeAllUploads];
}

- (IBAction)showHelp:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.iterm2.com/documentation.html"]];
}

- (IBAction)buildScriptMenu:(id)sender {
    static NSString *kScriptTitle = @"Scripts";
    static const int kScriptMenuItemIndex = 5;
    if ([[[[NSApp mainMenu] itemAtIndex:kScriptMenuItemIndex] title] isEqualToString:kScriptTitle]) {
        [[NSApp mainMenu] removeItemAtIndex:kScriptMenuItemIndex];
    }

    // create menu item with no title and set image
    NSMenuItem *scriptMenuItem = [[[NSMenuItem alloc] initWithTitle:kScriptTitle action: nil keyEquivalent: @""] autorelease];

    // create submenu
    int count = 0;
    NSMenu *scriptMenu = [[NSMenu alloc] initWithTitle:kScriptTitle];
    [scriptMenuItem setSubmenu: scriptMenu];
    // populate the submenu with ascripts found in the script directory
    NSString *scriptsPath = [[NSFileManager defaultManager] scriptsPath];
    NSDirectoryEnumerator *directoryEnumerator =
        [[NSFileManager defaultManager] enumeratorAtPath:scriptsPath];
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    for (NSString *file in directoryEnumerator) {
        NSString *path = [scriptsPath stringByAppendingPathComponent:file];
        if ([workspace isFilePackageAtPath:path]) {
            [directoryEnumerator skipDescendents];
        }
        if ([[file pathExtension] isEqualToString:@"scpt"] ||
            [[file pathExtension] isEqualToString:@"app"] ) {
            NSMenuItem *scriptItem = [[NSMenuItem alloc] initWithTitle:file
                                                                action:@selector(launchScript:)
                                                         keyEquivalent:@""];
            [scriptItem setTarget:[iTermController sharedInstance]];
            [scriptMenu addItem:scriptItem];
            count++;
            [scriptItem release];
        }
    }
    if (count > 0) {
            [scriptMenu addItem:[NSMenuItem separatorItem]];
            NSMenuItem *scriptItem = [[NSMenuItem alloc] initWithTitle:@"Refresh"
                                                                action:@selector(buildScriptMenu:)
                                                         keyEquivalent:@""];
            [scriptItem setTarget:self];
            [scriptMenu addItem:scriptItem];
            count++;
            [scriptItem release];
    }
    [scriptMenu release];

    // add new menu item
    if (count) {
        [[NSApp mainMenu] insertItem:scriptMenuItem atIndex:kScriptMenuItemIndex];
        [scriptMenuItem setTitle:kScriptTitle];
    }
}

- (IBAction)saveWindowArrangement:(id)sender {
    [[iTermController sharedInstance] saveWindowArrangement:YES];
}

- (IBAction)saveCurrentWindowAsArrangement:(id)sender {
    [[iTermController sharedInstance] saveWindowArrangement:NO];
}

// TODO(georgen): Disable "Edit Current Session..." when there are no current sessions.
- (IBAction)editCurrentSession:(id)sender {
    PseudoTerminal* pty = [[iTermController sharedInstance] currentTerminal];
    if (!pty) {
        return;
    }
    [pty editCurrentSession:sender];
}

- (IBAction)toggleUseBackgroundPatternIndicator:(id)sender {
    BOOL value = [self useBackgroundPatternIndicator];
    value = !value;
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:kUseBackgroundPatternIndicatorKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:kUseBackgroundPatternIndicatorChangedNotification
                                                        object:nil];
}

- (IBAction)enableMarkAlertShowsModalAlert:(id)sender {
    [[NSUserDefaults standardUserDefaults] setObject:kMarkAlertActionModalAlert forKey:kMarkAlertAction];
}

- (IBAction)enableMarkAlertPostsNotification:(id)sender {
    [[NSUserDefaults standardUserDefaults] setObject:kMarkAlertActionPostNotification forKey:kMarkAlertAction];
}

- (IBAction)showTipOfTheDay:(id)sender {
    [[iTermTipController sharedInstance] showTip];
}

- (IBAction)openDashboard:(id)sender {
    [[TmuxDashboardController sharedInstance] showWindow:nil];
}

- (IBAction)openSourceLicenses:(id)sender {
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"Licenses" withExtension:@"txt"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

#pragma mark - Private

- (void)updateProcessType {
    [[iTermApplication sharedApplication] setIsUIElement:[iTermPreferences boolForKey:kPreferenceKeyUIElement]];
}

- (PseudoTerminal *)terminalToOpenFileIn {
    if ([iTermAdvancedSettingsModel openFileInNewWindows]) {
        return nil;
    } else {
        return [self currentTerminal];
    }
}

- (void)updateScreenParametersInAllTerminals {
    // Make sure that all top-of-screen windows are the proper width.
    for (PseudoTerminal* term in [self terminals]) {
        [term screenParametersDidChange];
    }
}

- (iTermProfileHotKey *)currentProfileHotkey {
    PseudoTerminal *term = [[iTermController sharedInstance] currentTerminal];
    return [[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:term];
}

- (BOOL)possiblyTmuxValueForWindow:(BOOL)isWindow cancel:(BOOL *)cancel {
    *cancel = NO;
    static NSString *const kPossiblyTmuxIdentifier = @"NoSyncNewWindowOrTabFromTmuxOpensTmux";
    if ([[[[iTermController sharedInstance] currentTerminal] currentSession] isTmuxClient]) {
        NSString *heading =
            [NSString stringWithFormat:@"What kind of %@ do you want to open?",
                isWindow ? @"window" : @"tab"];
        NSString *title =
            [NSString stringWithFormat:@"The current session is a tmux session. "
                                       @"Would you like to create a new tmux %@ or use the default profile?",
                                       isWindow ? @"window" : @"tab"];
        NSString *tmuxAction = isWindow ? @"New tmux Window" : @"New tmux Tab";
        iTermWarningSelection selection = [iTermWarning showWarningWithTitle:title
                                                                     actions:@[ tmuxAction, @"Use Default Profile", @"Cancel" ]
                                                                   accessory:nil
                                                                  identifier:kPossiblyTmuxIdentifier
                                                                 silenceable:kiTermWarningTypePermanentlySilenceable
                                                                     heading:heading];
        *cancel = (selection == kiTermWarningSelection2);
        return (selection == kiTermWarningSelection0);
    } else {
        return NO;
    }
}

- (void)hideToolTipsInView:(NSView *)aView {
    [aView removeAllToolTips];
    for (NSView *subview in [aView subviews]) {
        [self hideToolTipsInView:subview];
    }
}

- (NSArray<PTYSession *> *)sessionsToAdjustFontSize {
    PTYSession *session = [[[iTermController sharedInstance] currentTerminal] currentSession];
    if (!session) {
        return nil;
    }
    if ([iTermAdvancedSettingsModel fontChangeAffectsBroadcastingSessions]) {
        NSArray<PTYSession *> *broadcastSessions = [[[iTermController sharedInstance] currentTerminal] broadcastSessions];
        if ([broadcastSessions containsObject:session]) {
            return broadcastSessions;
        }
    }
    return @[ session ];
}

- (NSString *)formatBytes:(double)bytes {
    if (bytes < 1) {
        return [NSString stringWithFormat:@"%.04lf bytes", bytes];
    } else if (bytes < 1024) {
        return [NSString stringWithFormat:@"%d bytes", (int)bytes];
    } else if (bytes < 10240) {
        return [NSString stringWithFormat:@"%.1lf kB", bytes / 10];
    } else if (bytes < 1048576) {
        return [NSString stringWithFormat:@"%d kB", (int)bytes / 1024];
    } else if (bytes < 10485760) {
        return [NSString stringWithFormat:@"%.1lf MB", bytes / 1048576];
    } else if (bytes < 1024.0 * 1024.0 * 1024.0) {
        return [NSString stringWithFormat:@"%.0lf MB", bytes / 1048576];
    } else if (bytes < 1024.0 * 1024.0 * 1024.0 * 10) {
        return [NSString stringWithFormat:@"%.1lf GB", bytes / (1024.0 * 1024.0 * 1024.0)];
    } else {
        return [NSString stringWithFormat:@"%.0lf GB", bytes / (1024.0 * 1024.0 * 1024.0)];
    }
}

- (void)changePasteSpeedBy:(double)factor
                  bytesKey:(NSString *)bytesKey
              defaultBytes:(int)defaultBytes
                  delayKey:(NSString *)delayKey
              defaultDelay:(float)defaultDelay {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    int bytes = [defaults integerForKey:bytesKey];
    if (!bytes) {
        bytes = defaultBytes;
    }
    float delay = [defaults floatForKey:delayKey];
    if (!delay) {
        delay = defaultDelay;
    }
    bytes *= factor;
    delay /= factor;
    bytes = MAX(1, MIN(1024 * 1024, bytes));
    delay = MAX(0.001, MIN(10, delay));
    [defaults setInteger:bytes forKey:bytesKey];
    [defaults setFloat:delay forKey:delayKey];
    double rate = bytes;
    rate /= delay;

    [ToastWindowController showToastWithMessage:[NSString stringWithFormat:@"Pasting at up to %@/sec", [self formatBytes:rate]]];
}

- (void)setSecureInput:(BOOL)secure {
    if (secure && _secureInputCount > 0) {
        XLog(@"Want to turn on secure input but it's already on");
        return;
    }

    if (!secure && _secureInputCount == 0) {
        XLog(@"Want to turn off secure input but it's already off");
        return;
    }
    DLog(@"Before: IsSecureEventInputEnabled returns %d", (int)IsSecureEventInputEnabled());
    if (secure) {
        OSErr err = EnableSecureEventInput();
        DLog(@"EnableSecureEventInput err=%d", (int)err);
        if (err) {
            NSLog(@"EnableSecureEventInput failed with error %d", (int)err);
        } else {
            ++_secureInputCount;
        }
    } else {
        OSErr err = DisableSecureEventInput();
        DLog(@"DisableSecureEventInput err=%d", (int)err);
        if (err) {
            XLog(@"DisableSecureEventInput failed with error %d", (int)err);
        } else {
            --_secureInputCount;
        }
    }
    DLog(@"After: IsSecureEventInputEnabled returns %d", (int)IsSecureEventInputEnabled());
}

- (void)hideStuckToolTips {
    if ([iTermAdvancedSettingsModel hideStuckTooltips]) {
        for (NSWindow *window in [NSApp windows]) {
            if ([NSStringFromClass([window class]) isEqualToString:@"NSToolTipPanel"]) {
                [window close];
            }
        }
    }
}

- (void)restoreBuriedSessionsState {
    if (_buriedSessionsState) {
        [[iTermBuriedSessions sharedInstance] restoreFromState:_buriedSessionsState];
        [_buriedSessionsState release];
        _buriedSessionsState = nil;
    }
}

- (NSArray *)allResponders {
    NSMutableArray *responders = [NSMutableArray array];
    NSResponder *responder = [[NSApp keyWindow] firstResponder];
    while (responder) {
        [responders addObject:responder];
        responder = [responder nextResponder];
    }
    return responders;
}

- (NSResponder *)responderForMenuItem:(NSMenuItem *)menuItem {
    for (NSResponder *responder in [self allResponders]) {
        if ([responder respondsToSelector:@selector(undo:)] &&
            [responder respondsToSelector:@selector(validateMenuItem:)] &&
            [responder validateMenuItem:menuItem]) {
            return responder;
        }
    }
    return nil;
}

- (void)newSessionInWindowAtIndex:(id)sender {
    [[iTermController sharedInstance] newSessionInWindowAtIndex:sender];
}

#pragma mark - iTermPasswordManagerDelegate

- (void)iTermPasswordManagerEnterPassword:(NSString *)password {
  [[[[iTermController sharedInstance] currentTerminal] currentSession] enterPassword:password];
}

- (BOOL)iTermPasswordManagerCanEnterPassword {
  PTYSession *session = [[[iTermController sharedInstance] currentTerminal] currentSession];
  return session && ![session exited];
}

- (void)currentSessionDidChange {
    [_passwordManagerWindowController update];
    PseudoTerminal *currentWindow = [[iTermController sharedInstance] currentTerminal];
    iTermQuickLookController *quickLookController = currentWindow.currentSession.quickLookController;
    if (quickLookController) {
        QLPreviewPanel *panel = [QLPreviewPanel sharedPreviewPanelIfExists];
        if (panel.currentController == currentWindow) {
            [quickLookController takeControl];
        }
    }
}

#pragma mark - iTermAPIServerDelegate

- (NSDictionary *)apiServerAuthorizeProcess:(pid_t)pid {
    NSMutableDictionary *bundles = [[[NSUserDefaults standardUserDefaults] objectForKey:kBundlesWithAPIAccessSettingKey] mutableCopy];
    if (!bundles) {
        bundles = [NSMutableDictionary dictionary];
    }

    NSString *processName = nil;
    NSString *processIdentifier = nil;

    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (app.localizedName && app.bundleIdentifier) {
        processName = app.localizedName;
        processIdentifier = app.bundleIdentifier;
    } else {
        processIdentifier = [iTermLSOF commandForProcess:pid execName:&processName];
        if (!processName || !processIdentifier) {
            XLog(@"Could not identify name for process with pid %d", (int)pid);
            return nil;
        }
        processName = [processName lastPathComponent];
    }
    NSDictionary *authorizedIdentity = @{ iTermWebSocketConnectionPeerIdentityBundleIdentifier: processIdentifier };
    NSString *key = [NSString stringWithFormat:@"bundle=%@", processIdentifier];
    NSDictionary *setting = bundles[key];
    BOOL reauth = NO;
    if (setting) {
        if (![setting[kAPIAccessAllowed] boolValue]) {
            // Access permanently disallowed.
            return nil;
        }

        NSString *name = setting[kAPIAccessLocalizedName];
        if ([processName isEqualToString:name]) {
            // Access is permanently allowed and the display name is unchanged. Do we need to reauth?

            NSDate *confirm = setting[kAPINextConfirmationDate];
            if ([[NSDate date] compare:confirm] == NSOrderedAscending) {
                // No need to reauth, allow it.
                XLog(@"Allowing API access to process id %d, name %@, bundle ID %@", pid, processName, processIdentifier);
                return authorizedIdentity;
            }

            // It's been a month since API access was confirmed. Request it again.
            reauth = YES;
        }
    }
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    if (reauth) {
        alert.messageText = @"Reauthorize API Access";
        alert.informativeText = [NSString stringWithFormat:@"The application “%@” (%@) has API access, which grants it permission to see and control your activity. Would you like it to continue?", processName, processIdentifier];
    } else {
        alert.messageText = @"API Access Request";
        alert.informativeText = [NSString stringWithFormat:@"The application “%@” (%@) would like to control iTerm2. This exposes a significant amount of data in iTerm2 to %@. Allow this request?", processName, processIdentifier, processName];
    }
    [alert addButtonWithTitle:@"Deny"];
    [alert addButtonWithTitle:@"Allow"];
    if (!reauth) {
        // Reauth is always persistent so don't show the button.
        alert.suppressionButton.title = @"Remember my selection";
        alert.showsSuppressionButton = YES;
    }
    NSModalResponse response = [alert runModal];
    BOOL allow = (response == NSAlertSecondButtonReturn);

    if (reauth || alert.suppressionButton.state == NSOnState) {
        bundles[key] = @{ kAPIAccessAllowed: @(allow),
                          kAPIAccessDate: [NSDate date],
                          kAPINextConfirmationDate: [[NSDate date] dateByAddingTimeInterval:kOneMonth],
                          kAPIAccessLocalizedName: processName };
    } else {
        [bundles removeObjectForKey:key];
    }
    [[NSUserDefaults standardUserDefaults] setObject:bundles forKey:kBundlesWithAPIAccessSettingKey];

    return allow ? authorizedIdentity : nil;
}

- (PTYSession *)sessionForAPIIdentifier:(NSString *)identifier {
    if (identifier) {
        for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
            for (PTYSession *session in term.allSessions) {
                if ([session.guid isEqualToString:identifier]) {
                    return session;
                }
            }
        }
        return nil;
    } else {
        return [[[iTermController sharedInstance] currentTerminal] currentSession];
    }
}

- (void)apiServerGetBuffer:(ITMGetBufferRequest *)request
                   handler:(void (^)(ITMGetBufferResponse *))handler {
    PTYSession *session = [self sessionForAPIIdentifier:request.hasSession ? request.session : nil];
    if (!session) {
        ITMGetBufferResponse *response = [[[ITMGetBufferResponse alloc] init] autorelease];
        response.status = ITMGetBufferResponse_Status_SessionNotFound;
        handler(response);
    } else {
        handler([session handleGetBufferRequest:request]);
    }
}

- (void)apiServerGetPrompt:(ITMGetPromptRequest *)request
                   handler:(void (^)(ITMGetPromptResponse *))handler {
    PTYSession *session = [self sessionForAPIIdentifier:request.hasSession ? request.session : nil];
    if (!session) {
        ITMGetPromptResponse *response = [[[ITMGetPromptResponse alloc] init] autorelease];
        response.status = ITMGetPromptResponse_Status_SessionNotFound;
        handler(response);
    } else {
        handler([session handleGetPromptRequest:request]);
    }
}

- (ITMNotificationResponse *)handleAPINotificationRequest:(ITMNotificationRequest *)request connection:(id)connection {
    ITMNotificationResponse *response = [[ITMNotificationResponse alloc] init];
    if (!request.hasSubscribe) {
        response.status = ITMNotificationResponse_Status_RequestMalformed;
        return response;
    }
    if (!_newSessionSubscriptions) {
        _newSessionSubscriptions = [[NSMutableDictionary alloc] init];
        _terminateSessionSubscriptions = [[NSMutableDictionary alloc] init];
        _layoutChangeSubscriptions = [[NSMutableDictionary alloc] init];
    }
    NSMutableDictionary<id, ITMNotificationRequest *> *subscriptions;
    if (request.notificationType == ITMNotificationType_NotifyOnNewSession) {
        subscriptions = _newSessionSubscriptions;
    } else if (request.notificationType == ITMNotificationType_NotifyOnTerminateSession) {
        subscriptions = _terminateSessionSubscriptions;
    } else if (request.notificationType == ITMNotificationType_NotifyOnLayoutChange) {
        subscriptions = _layoutChangeSubscriptions;
    } else {
        assert(false);
    }
    if (request.subscribe) {
        if (subscriptions[connection]) {
            response.status = ITMNotificationResponse_Status_AlreadySubscribed;
            return response;
        }
        subscriptions[connection] = request;
    } else {
        if (!subscriptions[connection]) {
            response.status = ITMNotificationResponse_Status_NotSubscribed;
            return response;
        }
        [subscriptions removeObjectForKey:connection];
    }

    response.status = ITMNotificationResponse_Status_Ok;
    return response;
}

- (void)apiServerNotification:(ITMNotificationRequest *)request
                   connection:(id)connection
                      handler:(void (^)(ITMNotificationResponse *))handler {
    if (request.notificationType == ITMNotificationType_NotifyOnNewSession ||
        request.notificationType == ITMNotificationType_NotifyOnTerminateSession |
        request.notificationType == ITMNotificationType_NotifyOnLayoutChange) {
        handler([self handleAPINotificationRequest:request connection:connection]);
    } else {
        PTYSession *session = [self sessionForAPIIdentifier:request.hasSession ? request.session : nil];
        if (!session) {
            ITMNotificationResponse *response = [[[ITMNotificationResponse alloc] init] autorelease];
            response.status = ITMNotificationResponse_Status_SessionNotFound;
            handler(response);
        } else {
            handler([session handleAPINotificationRequest:request connection:connection]);
        }
    }
}

- (void)apiServerRemoveSubscriptionsForConnection:(id)connection {
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermRemoveAPIServerSubscriptionsNotification object:connection];
}

- (void)apiServerRegisterTool:(ITMRegisterToolRequest *)request
                 peerIdentity:(NSDictionary *)peerIdentity
                      handler:(void (^)(ITMRegisterToolResponse *))handler {
    ITMRegisterToolResponse *response = [[[ITMRegisterToolResponse alloc] init] autorelease];
    if (!request.hasName || !request.hasIdentifier || !request.hasURL) {
        response.status = ITMRegisterToolResponse_Status_RequestMalformed;
        handler(response);
        return;
    }
    NSURL *url = [NSURL URLWithString:request.URL];
    if (!url || !url.host) {
        response.status = ITMRegisterToolResponse_Status_RequestMalformed;
        handler(response);
        return;
    }

    NSString *bundleId = peerIdentity[iTermWebSocketConnectionPeerIdentityBundleIdentifier];
    if (![request.identifier hasPrefix:bundleId]) {
        response.status = ITMRegisterToolResponse_Status_PermissionDenied;
        handler(response);
        return;
    }

    if ([[iTermToolbeltView builtInToolNames] containsObject:request.name]) {
        response.status = ITMRegisterToolResponse_Status_PermissionDenied;
        handler(response);
        return;
    }

    [iTermToolbeltView registerDynamicToolWithIdentifier:request.identifier
                                                    name:request.name
                                                     URL:request.URL
                               revealIfAlreadyRegistered:request.revealIfAlreadyRegistered];
}

- (void)apiServerSetProfileProperty:(ITMSetProfilePropertyRequest *)request
                            handler:(void (^)(ITMSetProfilePropertyResponse *))handler {
    PTYSession *session = [self sessionForAPIIdentifier:request.hasSession ? request.session : nil];
    if (!session) {
        ITMSetProfilePropertyResponse *response = [[[ITMSetProfilePropertyResponse alloc] init] autorelease];
        response.status = ITMSetProfilePropertyResponse_Status_SessionNotFound;
        handler(response);
        return;
    }

    NSError *error = nil;
    id value = [NSJSONSerialization JSONObjectWithData:[request.jsonValue dataUsingEncoding:NSUTF8StringEncoding]
                                               options:NSJSONReadingAllowFragments
                                                 error:&error];
    if (!value || error) {
        XLog(@"JSON parsing error %@ for value in request %@", error, request);
        ITMSetProfilePropertyResponse *response = [[[ITMSetProfilePropertyResponse alloc] init] autorelease];
        response.status = ITMSetProfilePropertyResponse_Status_RequestMalformed;
        handler(response);
    }

    handler([session handleSetProfilePropertyForKey:request.key value:value]);
}

- (void)apiServerListSessions:(ITMListSessionsRequest *)request
                      handler:(void (^)(ITMListSessionsResponse *))handler {
    handler([self newListSessionsResponse]);
}

- (ITMListSessionsResponse *)newListSessionsResponse {
    ITMListSessionsResponse *response = [[[ITMListSessionsResponse alloc] init] autorelease];
    for (PseudoTerminal *window in [[iTermController sharedInstance] terminals]) {
        ITMListSessionsResponse_Window *windowMessage = [[[ITMListSessionsResponse_Window alloc] init] autorelease];
        windowMessage.windowId = window.terminalGuid;

        for (PTYTab *tab in window.tabs) {
            ITMListSessionsResponse_Tab *tabMessage = [[[ITMListSessionsResponse_Tab alloc] init] autorelease];
            tabMessage.tabId = [@(tab.uniqueId) stringValue];

            for (PTYSession *session in tab.sessions) {
                ITMListSessionsResponse_Session *sessionMessage = [[[ITMListSessionsResponse_Session alloc] init] autorelease];
                sessionMessage.uniqueIdentifier = session.guid;
                [tabMessage.sessionsArray addObject:sessionMessage];
            }

            [windowMessage.tabsArray addObject:tabMessage];
        }

        [response.windowsArray addObject:windowMessage];
    }
    return response;
}

- (void)apiServerSendText:(ITMSendTextRequest *)request handler:(void (^)(ITMSendTextResponse *))handler {
    PTYSession *session = [self sessionForAPIIdentifier:request.hasSession ? request.session : nil];
    if (!session || session.exited) {
        ITMSendTextResponse *response = [[[ITMSendTextResponse alloc] init] autorelease];
        response.status = ITMSendTextResponse_Status_SessionNotFound;
        handler(response);
        return;
    }
    [session writeTask:request.text];
    ITMSendTextResponse *response = [[[ITMSendTextResponse alloc] init] autorelease];
    response.status = ITMSendTextResponse_Status_Ok;
    handler(response);
}

- (void)apiServerCreateTab:(ITMCreateTabRequest *)request handler:(void (^)(ITMCreateTabResponse *))handler {
    PseudoTerminal *term = nil;
    if (request.hasWindowId) {
        term = [[iTermController sharedInstance] terminalWithGuid:request.windowId];
        if (!term) {
            ITMCreateTabResponse *response = [[[ITMCreateTabResponse alloc] init] autorelease];
            response.status = ITMCreateTabResponse_Status_InvalidWindowId;
            handler(response);
            return;
        }
    }

    Profile *profile = [[ProfileModel sharedInstance] defaultBookmark];
    if (request.hasProfileName) {
        profile = [[ProfileModel sharedInstance] bookmarkWithName:request.profileName];
        if (!profile) {
            ITMCreateTabResponse *response = [[[ITMCreateTabResponse alloc] init] autorelease];
            response.status = ITMCreateTabResponse_Status_InvalidProfileName;
            handler(response);
            return;
        }
    }

    PTYSession *session = [[iTermController sharedInstance] launchBookmark:profile
                                                                inTerminal:term
                                                                   withURL:nil
                                                          hotkeyWindowType:iTermHotkeyWindowTypeNone
                                                                   makeKey:YES
                                                               canActivate:YES
                                                                   command:request.hasCommand ? request.command : nil
                                                                     block:nil];
    if (!session) {
        ITMCreateTabResponse *response = [[[ITMCreateTabResponse alloc] init] autorelease];
        response.status = ITMCreateTabResponse_Status_MissingSubstitution;
        handler(response);
        return;
    }

    term = [[iTermController sharedInstance] terminalWithSession:session];
    PTYTab *tab = [term tabForSession:session];

    ITMCreateTabResponse_Status status = ITMCreateTabResponse_Status_Ok;

    if (request.hasTabIndex) {
        NSInteger sourceIndex = [term indexOfTab:tab];
        if (term.numberOfTabs > request.tabIndex && sourceIndex != NSNotFound) {
            [term.tabBarControl moveTabAtIndex:sourceIndex toIndex:request.tabIndex];
        } else {
            status = ITMCreateTabResponse_Status_InvalidTabIndex;
        }
    }

    ITMCreateTabResponse *response = [[[ITMCreateTabResponse alloc] init] autorelease];
    response.status = status;
    response.windowId = term.terminalGuid;
    response.tabId = tab.uniqueId;
    response.sessionId = session.guid;
    handler(response);
}

- (void)apiServerSplitPane:(ITMSplitPaneRequest *)request handler:(void (^)(ITMSplitPaneResponse *))handler {
    PTYSession *session = [self sessionForAPIIdentifier:request.hasSession ? request.session : nil];
    PseudoTerminal *term = session ? [[iTermController sharedInstance] terminalWithSession:session] : nil;
    if (!term || !session || session.exited) {
        ITMSplitPaneResponse *response = [[[ITMSplitPaneResponse alloc] init] autorelease];
        response.status = ITMSplitPaneResponse_Status_SessionNotFound;
        handler(response);
        return;
    }

    Profile *profile = [[ProfileModel sharedInstance] defaultBookmark];
    if (request.hasProfileName) {
        profile = [[ProfileModel sharedInstance] bookmarkWithName:request.profileName];
        if (!profile) {
            ITMSplitPaneResponse *response = [[[ITMSplitPaneResponse alloc] init] autorelease];
            response.status = ITMSplitPaneResponse_Status_InvalidProfileName;
            handler(response);
            return;
        }
    }

    PTYSession *newSession = [term splitVertically:request.splitDirection == ITMSplitPaneRequest_SplitDirection_Vertical
                                            before:request.before
                                           profile:profile
                                     targetSession:session];
    if (newSession == nil && !session.isTmuxClient) {
        ITMSplitPaneResponse *response = [[[ITMSplitPaneResponse alloc] init] autorelease];
        response.status = ITMSplitPaneResponse_Status_CannotSplit;
        handler(response);
        return;
    }

    ITMSplitPaneResponse *response = [[[ITMSplitPaneResponse alloc] init] autorelease];
    response.status = ITMSplitPaneResponse_Status_Ok;
    if (newSession != nil) {
        response.sessionId = newSession.guid;
    }
    handler(response);
}

@end
