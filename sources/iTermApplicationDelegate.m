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
#import "iTerm2SharedARC-Swift.h"
#import "iTermAPIHelper.h"
#import "ITAddressBookMgr.h"
#import "iTermAPIConnectionIdentifierController.h"
#import "iTermAboutWindowController.h"
#import "iTermAppHotKeyProvider.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermBuiltInFunctions.h"
#import "iTermBuriedSessions.h"
#import "iTermColorPresets.h"
#import "iTermController.h"
#import "iTermDependencyEditorWindowController.h"
#import "iTermDisclosableView.h"
#import "iTermFileDescriptorSocketPath.h"
#import "iTermFontPanel.h"
#import "iTermFullScreenWindowManager.h"
#import "iTermGlobalScopeController.h"
#import "iTermGlobalSearchWindowController.h"
#import "iTermHotKeyController.h"
#import "iTermHotKeyProfileBindingController.h"
#import "iTermIntegerNumberFormatter.h"
#import "iTermLaunchExperienceController.h"
#import "iTermLaunchServices.h"
#import "iTermLoggingHelper.h"
#import "iTermLSOF.h"
#import "iTermMenuBarObserver.h"
#import "iTermMigrationHelper.h"
#import "iTermModifierRemapper.h"
#import "iTermNotificationController.h"
#import "iTermOnboardingWindowController.h"
#import "iTermPreferences.h"
#import "iTermProfileModelJournal.h"
#import "iTermPythonRuntimeDownloader.h"
#import "iTermRestorableStateController.h"
#import "iTermScriptHistory.h"
#import "iTermScriptImporter.h"
#import "iTermSessionFactory.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermOpenQuicklyWindowController.h"
#import "iTermOrphanServerAdopter.h"
#import "iTermPasswordManagerWindowController.h"
#import "iTermPasteHelper.h"
#import "iTermPreciseTimer.h"
#import "iTermPreferences.h"
#import "iTermProfilesMenuController.h"
#import "iTermPromptOnCloseReason.h"
#import "iTermProfilePreferences.h"
#import "iTermProfilesWindowController.h"
#import "iTermRecordingCodec.h"
#import "iTermScriptConsole.h"
#import "iTermScriptFunctionCall.h"
#import "iTermSecureKeyboardEntryController.h"
#import "iTermServiceProvider.h"
#import "iTermSessionLauncher.h"
#import "iTermQuickLookController.h"
#import "iTermRemotePreferences.h"
#import "iTermRestorableSession.h"
#import "iTermRemotePreferences.h"
#import "iTermScriptsMenuController.h"
#import "iTermSystemVersion.h"
#import "iTermTipController.h"
#import "iTermTipWindowController.h"
#import "iTermToolbeltView.h"
#import "iTermUntitledWindowStateMachine.h"
#import "iTermURLStore.h"
#import "iTermUserDefaults.h"
#import "iTermWarning.h"
#import "iTermWebSocketCookieJar.h"
#import "MovePaneController.h"
#import "NSAppearance+iTerm.h"
#import "NSApplication+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSBundle+iTerm.h"
#import "NSData+GZIP.h"
#import "NSFileManager+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSResponder+iTerm.h"
#import "NSStringITerm.h"
#import "NSUserDefaults+iTerm.h"
#import "NSWindow+iTerm.h"
#import "NSView+iTerm.h"
#import "NSView+RecursiveDescription.h"
#import "PreferencePanel.h"
#import "PseudoTerminal.h"
#import "PseudoTerminalRestorer.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PTYTextView.h"
#import "PTYWindow.h"
#import "QLPreviewPanel+iTerm.h"
#import "TmuxControllerRegistry.h"
#import "TmuxDashboardController.h"
#import "ToastWindowController.h"
#import "VT100Terminal.h"
#import "iTermSubpixelModelBuilder.h"
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
NSString *const iTermDidToggleAlertOnMarksInOffscreenSessionsNotification = @"iTermDidToggleAlertOnMarksInOffscreenSessionsNotification";

static NSString *const kScreenCharRestorableStateKey = @"kScreenCharRestorableStateKey";
static NSString *const kURLStoreRestorableStateKey = @"kURLStoreRestorableStateKey";
static NSString *const kHotkeyWindowRestorableState = @"kHotkeyWindowRestorableState";  // deprecated
static NSString *const kHotkeyWindowsRestorableStates = @"kHotkeyWindowsRestorableState";  // deprecated
static NSString *const iTermBuriedSessionState = @"iTermBuriedSessionState";
static NSString *const kPortholeRestorableStateKey = @"kPortholeRestorableStateKey";

static NSString *const kRestoreDefaultWindowArrangementShortcut = @"R";
NSString *const iTermApplicationWillTerminate = @"iTermApplicationWillTerminate";

static BOOL gStartupActivitiesPerformed = NO;
// Prior to 8/7/11, there was only one window arrangement, always called Default.
static NSString *LEGACY_DEFAULT_ARRANGEMENT_NAME = @"Default";
static BOOL hasBecomeActive = NO;

@interface iTermApplicationDelegate () <
    iTermGraphCodable,
    iTermOrphanServerAdopterDelegate,
    iTermPasswordManagerDelegate,
    iTermRestorableStateControllerDelegate,
    iTermUntitledWindowStateMachineDelegate,
    NSMenuDelegate>

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
    IBOutlet NSMenuItem *irPrev;
    IBOutlet NSMenuItem *windowArrangements_;
    IBOutlet NSMenuItem *windowArrangementsAsTabs_;
    IBOutlet NSMenuItem *_installPythonRuntime;
    IBOutlet NSMenu *_buriedSessions;
    NSMenu *_statusIconBuriedSessions;  // unsafe unretained
    IBOutlet NSMenu *_scriptsMenu;
    IBOutlet NSMenuItem *_composerMenuItem;
    IBOutlet NSMenuItem *_removeRecentProfilesFromDockMenuItem;
    IBOutlet NSMenuItem *showFullScreenTabs;
    IBOutlet NSMenuItem *useTransparency;
    IBOutlet NSMenuItem *maximizePane;
    IBOutlet SUUpdater * suUpdater;
    IBOutlet NSMenuItem *_showTipOfTheDay;  // Here because we must remove it for older OS versions.
    BOOL quittingBecauseLastWindowClosed_;

    IBOutlet NSMenuItem *_splitHorizontallyWithCurrentProfile;
    IBOutlet NSMenuItem *_splitVerticallyWithCurrentProfile;
    IBOutlet NSMenuItem *_splitHorizontally;
    IBOutlet NSMenuItem *_splitVertically;
    IBOutlet NSMenuItem *_triggers;
    IBOutlet NSMenuItem *_enterFullScreenMenuItem;
    IBOutlet NSMenu *_iterm2Menu;
    IBOutlet NSMenuItem *_captureGPUFrameMenuItem;
    IBOutlet NSMenuItem *_namedMarksMenuItem;

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

    BOOL _orphansAdopted;  // Have orphan servers been adopted?

    NSArray<NSDictionary *> *_buriedSessionsState;

    iTermScriptsMenuController *_scriptsMenuController;
    BOOL _disableTermination;

    iTermFocusFollowsMouseController *_focusFollowsMouseController;
    iTermGlobalScopeController *_globalScopeController;
    iTermRestorableStateController *_restorableStateController;
    iTermUntitledWindowStateMachine *_untitledWindowStateMachine;
    iTermGlobalSearchWindowController *_globalSearchWindowController;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _untitledWindowStateMachine = [[iTermUntitledWindowStateMachine alloc] init];
        _untitledWindowStateMachine.delegate = self;
        if ([iTermAdvancedSettingsModel useRestorableStateController] &&
            ![[NSApplication sharedApplication] isRunningUnitTests]) {
            _restorableStateController = [iTermRestorableStateController sharedInstance];
            _restorableStateController.delegate = self;
        }
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
                                                     name:iTermSessionBecameKey
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
                                                 selector:@selector(windowDidChangeKeyStatus:)
                                                     name:NSWindowDidBecomeKeyNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidChangeKeyStatus:)
                                                     name:NSWindowDidResignKeyNotification
                                                   object:nil];

        [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
                                                           andSelector:@selector(getUrl:withReplyEvent:)
                                                         forEventClass:kInternetEventClass
                                                            andEventID:kAEGetURL];
        [[iTermOrphanServerAdopter sharedInstance] setDelegate:self];
        launchTime_ = [[NSDate date] retain];
        _workspaceSessionActive = YES;
        _focusFollowsMouseController = [[iTermFocusFollowsMouseController alloc] init];
    }

    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [_appNapStoppingActivity release];
    [_focusFollowsMouseController release];
    [_globalScopeController release];
    [_untitledWindowStateMachine release];
    [super dealloc];
}

#pragma mark - Interface Builder

- (void)awakeFromNib {
    NSMenu *viewMenu = [self topLevelViewNamed:@"View"];
    [viewMenu addItem:[NSMenuItem separatorItem]];

    ColorsMenuItemView *labelTrackView = [[[ColorsMenuItemView alloc]
                                           initWithFrame:NSMakeRect(0, 0, 180, 50)] autorelease];
    [self addMenuItemView:labelTrackView toMenu:viewMenu title:@"Current Tab Color"];

    if (![iTermTipController sharedInstance]) {
        [_showTipOfTheDay.menu removeItem:_showTipOfTheDay];
    }

    if ([iTermAdvancedSettingsModel showHintsInSplitPaneMenuItems]) {
        _splitHorizontally.title = [@"─⃞ " stringByAppendingString:_splitHorizontally.title];
        _splitHorizontallyWithCurrentProfile.title = [@"─⃞ " stringByAppendingString:_splitHorizontallyWithCurrentProfile.title];
        _splitVertically.title = [@"│⃞ " stringByAppendingString:_splitVertically.title];
        _splitVerticallyWithCurrentProfile.title = [@"│⃞ " stringByAppendingString:_splitVerticallyWithCurrentProfile.title];
    }

#if !BETA
    [_iterm2Menu removeItem:_captureGPUFrameMenuItem];
#endif

    [[iTermBuriedSessions sharedInstance] setMenus:[NSArray arrayWithObjects:_buriedSessions, _statusIconBuriedSessions, nil]];
    _triggers.submenu.delegate = self;
    _namedMarksMenuItem.submenu.delegate = self;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if ([menuItem action] == @selector(toggleUseBackgroundPatternIndicator:)) {
      [menuItem setState:[self useBackgroundPatternIndicator]];
      return YES;
    } else if ([menuItem action] == @selector(undoCloseSession:)) {
        return [[iTermController sharedInstance] hasRestorableSession];
    } else if ([menuItem action] == @selector(undo:)) {
        NSResponder *undoResponder = [self responderForMenuItem:menuItem];
        if (undoResponder) {
            return YES;
        } else {
            menuItem.title = @"Undo Close Session";
            return [[iTermController sharedInstance] hasRestorableSession];
        }
    } else if ([menuItem action] == @selector(enableMarkAlertShowsModalAlert:)) {
        [menuItem setState:[[self markAlertAction] isEqualToString:kMarkAlertActionModalAlert] ? NSControlStateValueOn : NSControlStateValueOff];
        return YES;
    } else if ([menuItem action] == @selector(enableMarkAlertPostsNotification:)) {
        [menuItem setState:[[self markAlertAction] isEqualToString:kMarkAlertActionPostNotification] ? NSControlStateValueOn : NSControlStateValueOff];
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
               [menuItem action] == @selector(newSessionWithSameProfile:) ||
               [menuItem action] == @selector(newWindowWithSameProfile:)) {
        return [[iTermController sharedInstance] currentTerminal] != nil;
    } else if ([menuItem action] == @selector(toggleFullScreenTabBar:)) {
        [menuItem setState:[iTermPreferences boolForKey:kPreferenceKeyShowFullscreenTabBar] ? NSControlStateValueOn : NSControlStateValueOff];
        return YES;
    } else if ([menuItem action] == @selector(toggleMultiLinePasteWarning:)) {
        if ([iTermWarning warningHandler]) {
            // In a test.
            return YES;
        }
        if (menuItem.tag == 0) {
            menuItem.state = ![iTermAdvancedSettingsModel noSyncDoNotWarnBeforeMultilinePaste] ? NSControlStateValueOn : NSControlStateValueOff;
        } else if (menuItem.tag == 1) {
            menuItem.state = ![iTermAdvancedSettingsModel promptForPasteWhenNotAtPrompt] ? NSControlStateValueOn : NSControlStateValueOff;
            return ![iTermAdvancedSettingsModel noSyncDoNotWarnBeforeMultilinePaste];
        } else if (menuItem.tag == 2) {
            menuItem.state = ![iTermAdvancedSettingsModel noSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt] ? NSControlStateValueOn : NSControlStateValueOff;
        }
        return YES;
    } else if ([menuItem action] == @selector(showTipOfTheDay:)) {
        return ![[iTermTipController sharedInstance] showingTip];
    } else if ([menuItem action] == @selector(toggleSecureInput:)) {
        iTermSecureKeyboardEntryController *controller = [iTermSecureKeyboardEntryController sharedInstance];
        if (controller.isEnabled) {
            if (controller.isDesired) {
                menuItem.state = NSControlStateValueOn;
            } else {
                menuItem.state = NSControlStateValueMixed;
            }
        } else {
            menuItem.state = controller.isDesired ? NSControlStateValueOn : NSControlStateValueOff;
        }
        return YES;
    } else if ([menuItem action] == @selector(togglePinHotkeyWindow:)) {
        iTermProfileHotKey *profileHotkey = self.currentProfileHotkey;
        menuItem.state = profileHotkey.autoHides ? NSControlStateValueOff : NSControlStateValueOn;
        return profileHotkey != nil;
    } else if ([menuItem action] == @selector(clearAllDownloads:)) {
        return downloadsMenu_.submenu.itemArray.count > 2;
    } else if ([menuItem action] == @selector(clearAllUploads:)) {
        return uploadsMenu_.submenu.itemArray.count > 2;
    } else if (menuItem.action == @selector(debugLogging:)) {
        menuItem.state = gDebugLogging ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    } else if (menuItem.action == @selector(arrangeSplitPanesEvenly:)) {
        PTYTab *tab = [[[iTermController sharedInstance] currentTerminal] currentTab];
        return (tab.sessions.count > 0 && !tab.isMaximized);
    } else if (menuItem.action == @selector(promptToConvertTabsToSpacesWhenPasting:)) {
        menuItem.state = [iTermPasteHelper promptToConvertTabsToSpacesWhenPasting] ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    } else if (menuItem.action == @selector(newTmuxWindow:) ||
               menuItem.action == @selector(newTmuxTab:)) {
        return [[TmuxControllerRegistry sharedInstance] numberOfClients];
    } else if (menuItem.action == @selector(toggleTriggerEnabled:)) {
        // For some dumb reason this menu item doesn't know how to check the responder chain properly.
        NSResponder *realResponder = [self firstResponderForMenuItem:menuItem];
        if (!realResponder) {
            return NO;
        }
        if ([realResponder respondsToSelector:@selector(validateMenuItem:)]) {
            return [realResponder validateMenuItem:menuItem];
        }
        return YES;
    } else if (menuItem.action == @selector(toggleDisableTransparencyForActiveWindow:)) {
        const BOOL value = [iTermPreferences boolForKey:kPreferenceKeyDisableTransparencyForKeyWindow];
        menuItem.state = value ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    } else if (menuItem.action == @selector(toggleAlertOnMarksInOffscreenSessions:)) {
        menuItem.state = [iTermPreferences boolForKey:kPreferenceKeyAlertOnMarksInOffscreenSessions];
        return YES;
    } else {
        return YES;
    }
}

- (NSResponder *)firstResponderForMenuItem:(NSMenuItem *)menuItem {
    NSResponder *responder = [[NSApp keyWindow] firstResponder];
    while (responder) {
        if ([responder respondsToSelector:menuItem.action]) {
            return responder;
        }
        responder = [responder nextResponder];
    }
    return nil;
}

#pragma mark - APIs

- (BOOL)isAppleScriptTestApp {
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
        [session reveal];  // Unbury if needed. Otherwise there is no parent window. Issue 9734
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
    [maximizePane setState:[[[[iTermController sharedInstance] currentTerminal] currentTab] hasMaximizedPane] ? NSControlStateValueOn : NSControlStateValueOff];
}

- (void)updateUseTransparencyMenuItem {
    [useTransparency setState:[[[iTermController sharedInstance] currentTerminal] useTransparency] ? NSControlStateValueOn : NSControlStateValueOff];
}

- (NSString *)markAlertAction {
    NSString *action = [[NSUserDefaults standardUserDefaults] objectForKey:kMarkAlertAction];
    if (!action) {
        return kMarkAlertActionPostNotification;
    } else {
        return action;
    }
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

- (BOOL)toggleFullScreenHasCmdEnterShortcut {
    return [[_enterFullScreenMenuItem keyEquivalent] isEqualToString:@"\r"];
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
    if ([[filename pathExtension] isEqualToString:@"its"]) {
        if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
            return NO;
        }
        [iTermScriptImporter importScriptFromURL:[NSURL fileURLWithPath:filename]
                                   userInitiated:NO
                                 offerAutoLaunch:NO
                                   callbackQueue:dispatch_get_main_queue()
                                         avoidUI:NO
                                      completion:^(NSString * _Nullable errorMessage, BOOL quiet, NSURL *location) {
                                          if (quiet) {
                                              return;
                                          }
                                          [self->_scriptsMenuController importDidFinishWithErrorMessage:errorMessage
                                                                                               location:location
                                                                                            originalURL:[NSURL fileURLWithPath:filename]];
                                      }];
        return YES;
    }
    if ([[filename pathExtension] isEqualToString:@"itermtab"]) {
        [ProfileDocument openWithFilename:filename];
        return YES;
    }
    if ([filename hasSuffix:@".itermcolors"]) {
        DLog(@"Importing color presets from %@", filename);
        if ([iTermColorPresets importColorPresetFromFile:filename]) {
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            alert.messageText = @"Colors Scheme Imported";
            alert.informativeText = @"The color scheme was imported and added to presets. You can find it under Settings > Profiles > Colors > Load Presets….";
            [alert runModal];
        }
        return YES;
    }
    if ([filename.pathExtension isEqualToString:@"itr"]) {
        [iTermRecordingCodec loadRecording:[NSURL fileURLWithPath:filename]];
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

                const iTermWarningSelection selection =
                    [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"OK to run “%@”?", filename]
                                               actions:@[ @"OK", @"Cancel" ]
                                            identifier:@"NoSyncConfirmRunOpenFile"
                                           silenceable:kiTermWarningTypePermanentlySilenceable
                                                window:nil];
                if (selection != kiTermWarningSelection0) {
                    return YES;
                }

                // Escape it again because KEY_INITIAL_TEXT is a swifty string.
                bookmark[KEY_INITIAL_TEXT] = [initialText stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
            }
        }

        PseudoTerminal *windowController = [self terminalToOpenFileIn];
        if (!windowController) {
            bookmark[KEY_DISABLE_AUTO_FRAME] = @YES;
            DLog(@"Disable auto frame. Profile is:\n%@", bookmark);
        }
        DLog(@"application:openFile: launching new session in window %@", windowController);
        [iTermSessionLauncher launchBookmark:bookmark
                                  inTerminal:windowController
                          respectTabbingMode:NO
                                  completion:^(PTYSession *session) {
            PseudoTerminal *term = (id)session.delegate.realParentWindow;
            if (!term) {
                return;
            }
            // If term is a hotkey window, reveal it.
            iTermProfileHotKey *profileHotkey = [[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:term];
            if (!profileHotkey) {
                return;
            }
            DLog(@"application:openFile: revealing hotkey window");
            [[iTermHotKeyController sharedInstance] showWindowForProfileHotKey:profileHotkey url:nil];
        }];
    }
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
    DLog(@"applicationShouldTerminateAfterLastWindowClosed called");
    NSArray *terminals = [[iTermController sharedInstance] terminals];
    if (terminals.count > 0) {
        // The last window wasn't really closed, it was just the hotkey window getting ordered out or a window entering fullscreen.
        DLog(@"Not quitting automatically. Terminals are %@", terminals);
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

- (void)didToggleTraditionalFullScreenMode {
    // LOL
    // When you have only one window, and you do windowController.window = something new
    // then it thinks you closed the only window and asks if you want to terminate the
    // app. We run into this problem with compact windows, as other window types are
    // able to simply change the window style without actually replacing the window.
    // This awful hack catches that case. It takes two spins of the runloop because
    // everything is terrible.
    _disableTermination = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            _disableTermination = NO;
        });
    });
    [[iTermPresentationController sharedInstance] update];
}

- (BOOL)systemIsShuttingDown {
    NSAppleEventDescriptor *currentAppleEvent = [[NSAppleEventManager sharedAppleEventManager] currentAppleEvent];
    NSAppleEventDescriptor *reason = [currentAppleEvent attributeDescriptorForKeyword:kEventParamReason];
    switch (reason.typeCodeValue) {
        case kAEShutDown:
        case kAERestart:
        case kAEReallyLogOut:
            return YES;
        default:
            return NO;
    }
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSNotification *)theNotification {
    DLog(@"applicationShouldTerminate:");
    NSArray *terminals;
    if (_disableTermination) {
        return NSTerminateCancel;
    }
    
    terminals = [[iTermController sharedInstance] terminals];
    int numSessions = 0;

    iTermPromptOnCloseReason *reason = [iTermPromptOnCloseReason noReason];
    if (![self systemIsShuttingDown] || ![iTermPreferences boolForKey:kPreferenceKeyNeverBlockSystemShutdown]) {
        for (PseudoTerminal *term in terminals) {
            numSessions += [[term allSessions] count];

            [reason addReason:term.promptOnCloseReason];
        }

        // Display prompt if we need to
        if (!quittingBecauseLastWindowClosed_ &&  // cmd-q
            [iTermPreferences boolForKey:kPreferenceKeyPromptOnQuit]) {  // preference is to prompt on quit cmd
            if (terminals.count > 0) {
                [reason addReason:[iTermPromptOnCloseReason alwaysConfirmQuitPreferenceEnabled]];
            } else if ([iTermPreferences boolForKey:kPreferenceKeyPromptOnQuitEvenIfThereAreNoWindows]) {
                [reason addReason:[iTermPromptOnCloseReason alwaysConfirmQuitPreferenceEvenIfThereAreNoWindowsEnabled]];
            }
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
            reason = [iTermPromptOnCloseReason noReason];
        }
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
                                                                               prompt:@"Why am I being prompted?"
                                                                              message:[NSString stringWithFormat:@"You are being prompted because:\n\n%@",
                                                                                       reason.message]];
        iTermAccessoryViewUnfucker *unfucker = [[iTermAccessoryViewUnfucker alloc] initWithView:accessory];
        accessory.frame = NSMakeRect(0, 0, accessory.intrinsicContentSize.width, accessory.intrinsicContentSize.height);
        accessory.requestLayout = ^{
            [unfucker layout];
            [alert layout];
            [alert layout];
        };
        [unfucker layout];
        alert.accessoryView = unfucker;
        [alert layout];
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
    DLog(@"Post applicationWillTerminate which triggers saving restorable state.");
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermApplicationWillTerminate object:nil];

    // This causes all windows to be closed and all sessions to be terminated.
    DLog(@"Will release shared instance");
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
    [iTermController releaseSharedInstance];
    [[iTermModifierRemapper sharedInstance] setRemapModifiers:NO];
    DLog(@"applicationWillTerminate returning");
    TurnOffDebugLoggingSilently();
    [iTermUserDefaults setIgnoreSystemWindowRestoration:[iTermAdvancedSettingsModel useRestorableStateController]];
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)theApplication {
    DLog(@"Open untitled file");
    if ([iTermRestorableStateController shouldIgnoreOpenUntitledFile] &&
        _restorableStateController.numberOfWindowsRestored > 0) {
        DLog(@"Already restored one of our own windows so not opening an untitled file during window state restoration.");
        return NO;
    }
    if ([self isAppleScriptTestApp]) {
        DLog(@"Nope, am applescript test app");
        // Don't want to do this for applescript testing so we have a blank slate.
        return NO;
    }
    DLog(@"finishedLaunching=%@ openArrangementAtStartup=%@ openNoWindowsAtStartup=%@ alwaysOpenWindowAtStartup=%@",
         @(finishedLaunching_),
         @([iTermPreferences boolForKey:kPreferenceKeyOpenArrangementAtStartup]),
         @([iTermPreferences boolForKey:kPreferenceKeyOpenNoWindowsAtStartup]),
         @([iTermPreferences boolForKey:kPreferenceKeyAlwaysOpenWindowAtStartup]));

    if (![iTermAdvancedSettingsModel openUntitledFile]) {
        DLog(@"Opening untitled files is disabled");
        return NO;
    }
    [_untitledWindowStateMachine maybeOpenUntitledFile];
    return YES;
}

- (void)willRestoreWindow {
    [_untitledWindowStateMachine didRestoreSomeWindows];
}

- (NSMenu *)applicationDockMenu:(NSApplication *)sender {
    NSMenu* aMenu = [[NSMenu alloc] initWithTitle: @"Dock Menu"];

    [aMenu addItemWithTitle:@"New Window (Default Profile)"
                     action:@selector(newWindow:)
              keyEquivalent:@""];
    [aMenu addItem:[NSMenuItem separatorItem]];
    [self newSessionMenu:aMenu
                   title:@"New Window…"
                selector:@selector(newSessionInWindowAtIndex:)
         openAllSelector:@selector(newSessionsInNewWindow:)];
    [self newSessionMenu:aMenu
                   title:@"New Tab…"
                selector:@selector(newSessionInTabAtIndex:)
         openAllSelector:@selector(newSessionsInWindow:)];
    [self addArrangementsToDockMenu:aMenu];

    return ([aMenu autorelease]);
}

- (void)applicationWillBecomeActive:(NSNotification *)aNotification {
    DLog(@"******** Become Active\n%@", [NSThread callStackSymbols]);
}

- (void)application:(NSApplication *)app willEncodeRestorableState:(NSCoder *)coder {
    // ********
    // * NOTE *
    // ********
    // If you change this also change -restorableStateEncoderAppStateWithEncoder.
    if ([iTermAdvancedSettingsModel storeStateInSqlite]) {
        DLog(@"Using sqlite-based restoration so not saving anything.");
        return;
    }
    DLog(@"app encoding restorable state");
    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
    [coder encodeObject:ScreenCharEncodedRestorableState() forKey:kScreenCharRestorableStateKey];
    [coder encodeObject:[[iTermURLStore sharedInstance] dictionaryValue] forKey:kURLStoreRestorableStateKey];
    [coder encodeObject:PortholeRegistry.instance.dictionaryValue forKey:kPortholeRestorableStateKey];

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
    DLog(@"application:didDecodeRestorableState: starting");
    if ([iTermAdvancedSettingsModel storeStateInSqlite]) {
        DLog(@"Using sqlite-based restoration so not restoring anything.");
        return;
    }
    if (self.isAppleScriptTestApp) {
        DLog(@"Is applescript test app");
        return;
    }
    NSDictionary *screenCharState = [coder decodeObjectForKey:kScreenCharRestorableStateKey];
    if (screenCharState) {
        ScreenCharDecodeRestorableState(screenCharState);
    }

    NSDictionary *portholeState = [coder decodeObjectForKey:kPortholeRestorableStateKey];
    if ([NSDictionary castFrom:portholeState]) {
        [PortholeRegistry.instance load:portholeState];
    }

    NSDictionary *urlStoreState = [coder decodeObjectForKey:kURLStoreRestorableStateKey];
    if (urlStoreState) {
        [[iTermURLStore sharedInstance] loadFromDictionary:urlStoreState];
    }

    NSArray *hotkeyWindowsStates = nil;
    NSDictionary *legacyState = nil;
    hotkeyWindowsStates = [coder decodeObjectForKey:kHotkeyWindowsRestorableStates];
    if (hotkeyWindowsStates) {
        // We have to create the hotkey window now because we need to attach to servers before
        // launch finishes; otherwise any running hotkey window jobs will be treated as orphans.
        const NSInteger count = [[iTermHotKeyController sharedInstance] createHiddenWindowsFromRestorableStates:hotkeyWindowsStates];
        if (count > 0 && ![iTermPreferences boolForKey:kPreferenceKeyAlwaysOpenWindowAtStartup]) {
            [_untitledWindowStateMachine didRestoreSomeWindows];
        }
    }

    _buriedSessionsState = [[coder decodeObjectForKey:iTermBuriedSessionState] retain];
    if (finishedLaunching_) {
        [self restoreBuriedSessionsState];
    }
    if ([iTermAdvancedSettingsModel logRestorableStateSize]) {
        NSDictionary *dict = @{ kScreenCharRestorableStateKey: screenCharState ?: @{},
                                kPortholeRestorableStateKey: portholeState ?: @{},
                                kURLStoreRestorableStateKey: urlStoreState ?: @{},
                                kHotkeyWindowsRestorableStates: hotkeyWindowsStates ?: @[],
                                kHotkeyWindowRestorableState: legacyState ?: @{},
                                iTermBuriedSessionState: _buriedSessionsState ?: @[] };
        NSString *log = [dict sizeInfo];
        [log writeToFile:[NSString stringWithFormat:@"/tmp/statesize.app-%p.txt", self] atomically:NO encoding:NSUTF8StringEncoding error:nil];
    }
    DLog(@"application:didDecodeRestorableState: finished");
}

- (void)applicationDidResignActive:(NSNotification *)aNotification {
    DLog(@"******** Resign Active\n%@", [NSThread callStackSymbols]);
    [_restorableStateController saveRestorableState];
    [iTermUserDefaults setIgnoreSystemWindowRestoration:[iTermAdvancedSettingsModel useRestorableStateController]];
}

- (void)applicationWillHide:(NSNotification *)aNotification {
    for (NSWindow *aWindow in [[NSApplication sharedApplication] windows]) {
        [self hideToolTipsInView:[aWindow contentView]];
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification {
    hasBecomeActive = YES;
    [self hideStuckToolTips];
    iTermPreciseTimerClearLogs();
}

void TurnOnDebugLoggingAutomatically(void) {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
      static NSString *const iTermDisableDebugLoggingNotificationName = @"iTermDisableDebugLoggingNotificationName";
        [[NSNotificationCenter defaultCenter] addObserverForName:iTermDisableDebugLoggingNotificationName object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
            TurnOffDebugLoggingSilently();
            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"StartDebugLoggingAutomatically"];
        }];
      [[iTermNotificationController sharedInstance] postNotificationWithTitle:@"Debug logging turned on"
                                                                       detail:@"You may notice worse performance while debug logging is on."
                                                     callbackNotificationName:iTermDisableDebugLoggingNotificationName
                                                 callbackNotificationUserInfo:@{}
                                                            actionButtonTitle:@"Disable"];
      TurnOnDebugLoggingSilently();
  });
}

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification {
    DLog(@"Begin");
    if ([iTermUserDefaults importPath]) {
        [iTerm2ImportExport finishImporting];
        assert(NO);
    }
    if (![iTermAdvancedSettingsModel saveProfilesToRecentDocuments]) {
        [_removeRecentProfilesFromDockMenuItem.menu removeItem:_removeRecentProfilesFromDockMenuItem];
        [ProfileDocument removeAllRecents];
    }
    [iTermMenuBarObserver sharedInstance];
    // Cleanly crash on uncaught exceptions, such as during actions.
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{ @"NSApplicationCrashOnExceptions": @YES }];

    [iTermLaunchExperienceController applicationWillFinishLaunching];
    // Start automatic debug logging if it's enabled.
    if ([iTermAdvancedSettingsModel startDebugLoggingAutomatically]) {
        TurnOnDebugLoggingAutomatically();
    }
    DLog(@"applicationWillFinishLaunching:");

    _globalScopeController = [[iTermGlobalScopeController alloc] init];

    DLog(@"registerBuiltInFunctions");
    [PTYSession registerBuiltInFunctions];
    DLog(@"registerBuiltInFunctions");
    [PTYTab registerBuiltInFunctions];
    DLog(@"registerStandardFunctions");
    [iTermBuiltInFunctions registerStandardFunctions];

    DLog(@"migrateApplicationSupportDirectoryIfNeeded");
    [iTermMigrationHelper migrateApplicationSupportDirectoryIfNeeded];
    DLog(@"buildScriptMenu");
    [self buildScriptMenu:nil];

    // Fix up various user defaults settings.
    DLog(@"initializeUserDefaults");
    [iTermPreferences initializeUserDefaults];
    DLog(@"performMigrations");
    [iTermUserDefaults performMigrations];

    // Enable restoring windows to their original Spaces if needed.
    // This has to happen after -initializeUserDefaults and before this method returns.
    const BOOL restoreWorkspace = ([[NSUserDefaults standardUserDefaults] boolForKey:@"NoSyncWindowRestoresWorkspaceAtLaunch"] ||
                                   [iTermPreferences boolForKey:kPreferenceKeyRestoreWindowsToSameSpaces]);
    if (restoreWorkspace) {
        DLog(@"Set NSWindowRestoresWorkspaceAtLaunch=YES");
        // Based on https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/browser/chrome_browser_main_mac.mm#128:
        // Windows don't go back to their original workspaces, except on restart. When Sparkle
        // upgrades, treat it like a system restart.
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{ @"NSWindowRestoresWorkspaceAtLaunch": @YES }];
    }

    // This sets up bonjour and migrates bookmarks if needed.
    DLog(@"Make ITAddressBookMgr");
    [ITAddressBookMgr sharedInstance];

    // Bookmarks must be loaded for this to work since it needs to know if the hotkey's profile
    // exists.
    DLog(@"updateProcessType");
    [self updateProcessType];

    DLog(@"iTermToolbeltView populateMenu");
    [iTermToolbeltView populateMenu:toolbeltMenu];

    // Start tracking windows entering/exiting full screen.
    DLog(@"Make iTermFullScreenWindowManager");
    [iTermFullScreenWindowManager sharedInstance];

    DLog(@"complainIfNightlyBuildIsTooOld");
    [self complainIfNightlyBuildIsTooOld];

    // Set the Appcast URL and when it changes update it.
    DLog(@"refreshSoftwareUpdateUserDefaults");
    [[iTermController sharedInstance] refreshSoftwareUpdateUserDefaults];
    DLog(@"Add observers");
    [iTermPreferences addObserverForKey:kPreferenceKeyCheckForTestReleases
                                  block:^(id before, id after) {
                                      [[iTermController sharedInstance] refreshSoftwareUpdateUserDefaults];
                                  }];
    [iTermLoggingHelper observeNotificationsWithHandler:^(NSString * _Nonnull guid) {
        [[PreferencePanel sharedInstance] openToProfileWithGuid:guid
                                                            key:KEY_AUTOLOG];
    }];

    if ([iTermPreferences boolForKey:kPreferenceKeyOpenArrangementAtStartup] ||
        [iTermPreferences boolForKey:kPreferenceKeyOpenNoWindowsAtStartup]) {
        DLog(@"disableInitialUntitledWindow");
        [_untitledWindowStateMachine disableInitialUntitledWindow];
    }

    NSError *error = nil;
    DLog(@"Start iTermSecretServer");
    [[iTermSecretServer instance] listenAndReturnError:&error];
    if (error) {
        DLog(@"Secret server failed to start: %@", error);
    }

    DLog(@"willFinishLaunching");
    if (_restorableStateController) {
        // The system doesn't tell us when it's done invoking NSWindowRestoration calls. My guess
        // is that it's a spin after applicationWillFinishLaunching. We care because we won't make
        // the database writable until we know we don't need to use old records any more.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self restoreWindows];
        });
    } else {
        [_untitledWindowStateMachine didFinishRestoringWindows];
    }

    [[iTermInputSourceForcer sharedInstance] begin];
}

- (void)restoreWindows {
    DLog(@"restoreWindows");
    [_restorableStateController restoreWindowsWithCompletion:^{
        DLog(@"Window restoration is totally complete");
        [_untitledWindowStateMachine didFinishRestoringWindows];
        ScreenCharGarbageCollectImages();
    }];
}

- (void)turnOffMetalCaptureEnabledIfNeeded {
    NSString *key = @"MetalCaptureEnabledDate";
    NSNumber *n = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (!n) {
        return;
    }
    if (n.doubleValue < [NSDate timeIntervalSinceReferenceDate]) {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"MetalCaptureEnabled"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    DLog(@"didFinishLaunching");
    [iTermLaunchExperienceController applicationDidFinishLaunching];
    [[iTermLaunchServices sharedInstance] registerForiTerm2Scheme];
    if (IsTouchBarAvailable()) {
        NSApp.automaticCustomizeTouchBarMenuItemEnabled = YES;
    }

    if ([iTermAdvancedSettingsModel disableAppNap]) {
        [[NSProcessInfo processInfo] setAutomaticTerminationSupportEnabled:YES];
        [[NSProcessInfo processInfo] disableAutomaticTermination:@"User Preference"];
        _appNapStoppingActivity =
                [[[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiatedAllowingIdleSystemSleep
                                                                reason:@"User Preference"] retain];
    }
    [self turnOffMetalCaptureEnabledIfNeeded];
    [iTermFontPanel makeDefault];

    finishedLaunching_ = YES;
    // Create the app support directory
    [self createVersionFile];

    // Prevent the input manager from swallowing control-q. See explanation here:
    // https://web.archive.org/web/20111102073237/https://b4winckler.wordpress.com/2009/07/19/coercing-the-cocoa-text-system
    CFPreferencesSetAppValue(CFSTR("NSQuotedKeystrokeBinding"),
                             CFSTR(""),
                             kCFPreferencesCurrentApplication);
    // This is off by default, but would wreak havoc if set globally.
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
    [self updateRestoreWindowArrangementsMenu:windowArrangements_ asTabs:NO fromDock:NO];
    [self updateRestoreWindowArrangementsMenu:windowArrangementsAsTabs_ asTabs:YES fromDock:NO];

    // register for services
    [NSApp registerServicesMenuSendTypes:@[ NSPasteboardTypeString ]
                             returnTypes:@[ NSPasteboardTypeFileURL,
                                            NSPasteboardTypeString ]];
    // Register our services provider. Registration must happen only when we're
    // ready to accept requests, so I do it after a spin of the runloop.
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSApp setServicesProvider:[[[iTermServiceProvider alloc] init] autorelease]];
    });

    // Sometimes, open untitled doc isn't called in Lion. We need to give application:openFile:
    // a chance to run because a "special" filename cancels performStartupActivities.
    [self checkForQuietMode];
    [self performSelector:@selector(performStartupActivities)
               withObject:nil
               afterDelay:0];

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
        !self.isAppleScriptTestApp) {
        DLog(@"Set post-retoration completion block from appDidFinishLaunching");
        [PseudoTerminalRestorer setPostRestorationCompletionBlock:^{
            DLog(@"Running post-retoration completion block from appDidFinishLaunching");
            [self restoreBuriedSessionsState];
            if ([[iTermController sharedInstance] numberOfDecodesPending] == 0) {
                _orphansAdopted = YES;
                [[iTermOrphanServerAdopter sharedInstance] openWindowWithOrphansWithCompletion:nil];
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
    if ([iTermAPIHelper isEnabled]) {
        [iTermAPIHelper sharedInstance];  // starts the server. Won't ask the user since it's enabled.
    }
    // This causes it to enable secure keyboard entry if needed.
    [iTermSecureKeyboardEntryController sharedInstance];
    [iTermUserDefaults setIgnoreSystemWindowRestoration:[iTermAdvancedSettingsModel useRestorableStateController]];
}

- (NSMenu *)statusBarMenu {
    NSMenu *menu = [[[NSMenu alloc] init] autorelease];
    NSMenuItem *item;

    item = [[[NSMenuItem alloc] initWithTitle:@"Settings"
                                       action:@selector(showAndOrderFrontRegardlessPrefWindow:)
                                keyEquivalent:@""] autorelease];
    [menu addItem:item];

    item = [[[NSMenuItem alloc] initWithTitle:@"Bring All Windows to Front"
                                       action:@selector(arrangeInFront:)
                                keyEquivalent:@""] autorelease];
    [menu addItem:item];

    item = [[[NSMenuItem alloc] init] autorelease];
    _statusIconBuriedSessions = [[[NSMenu alloc] init] autorelease];
    item.submenu = _statusIconBuriedSessions;
    item.title = @"Buried Sessions";
    [menu addItem:item];

    [[iTermBuriedSessions sharedInstance] setMenus:[NSArray arrayWithObjects:_buriedSessions, _statusIconBuriedSessions, nil]];

    item = [[[NSMenuItem alloc] initWithTitle:@"Check For Updates"
                                       action:@selector(checkForUpdatesFromMenu:)
                                keyEquivalent:@""] autorelease];
    [menu addItem:item];

    NSMenuItem *mainMenuItem = [[[NSMenuItem alloc] initWithTitle:@"Main Menu" action:nil keyEquivalent:@""] autorelease];
    mainMenuItem.submenu = [[NSApp mainMenu] it_deepCopy];
    [menu addItem:mainMenuItem];
    
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
    iTermRestorableStateController.forceSaveState = YES;
}

- (void)itermDidDecodeWindowRestorableState:(NSNotification *)notification {
    DLog(@"orphansAdopted=%@", @(_orphansAdopted));
    if (!_orphansAdopted && [[iTermController sharedInstance] numberOfDecodesPending] == 0) {
        _orphansAdopted = YES;
        [[iTermOrphanServerAdopter sharedInstance] openWindowWithOrphansWithCompletion:nil];
    }
}

- (void)dynamicToolsDidChange:(NSNotification *)notification {
    [iTermToolbeltView populateMenu:toolbeltMenu];
}

- (void)processTypeDidChange:(NSNotification *)notification {
    [self updateProcessType];
}

- (void)windowArrangementsDidChange:(id)sender {
    [self updateRestoreWindowArrangementsMenu:windowArrangements_ asTabs:NO fromDock:NO];
    [self updateRestoreWindowArrangementsMenu:windowArrangementsAsTabs_ asTabs:YES fromDock:NO];
}

- (void)toolDidToggle:(NSNotification *)notification {
    NSString *theName = [notification object];
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        [[term toolbelt] toggleToolWithName:theName];
        [term refreshTools];
    }
    NSMenuItem *menuItem = [toolbeltMenu itemWithTitle:theName];

    NSInteger newState = ([menuItem state] == NSControlStateValueOn) ? NSControlStateValueOff : NSControlStateValueOn;
    [menuItem setState:newState];
}

- (void)revealSessionID:(NSString *)sessionID {
    NSString *guid = [sessionID it_stringBySplittingOnFirstSubstring:@":"].secondObject;
    for (PseudoTerminal *window in [[iTermController sharedInstance] terminals]) {
        for (PTYSession *session in window.allSessions) {
            if ([session.guid isEqualToString:guid]) {
                [session reveal];
                return;
            }
        }
    }
    for (PTYSession *session in [[iTermBuriedSessions sharedInstance] buriedSessions]) {
        if ([session.guid isEqualToString:guid]) {
            [session reveal];
            return;
        }
    }
}

- (void)revealWithURL:(NSURL *)url {
    NSURLComponents *components = [[[NSURLComponents alloc] initWithURL:url resolvingAgainstBaseURL:NO] autorelease];
    NSURLQueryItem *item = [components.queryItems objectPassingTest:^BOOL(NSURLQueryItem *item, NSUInteger index, BOOL *stop) {
        return [item.name isEqualToString:@"sessionid"];
    }];
    if (item) {
        [self revealSessionID:item.value];
        return;
    }
}

- (BOOL)handleInternalURL:(NSURL *)url {
    return [self handleiTerm2URL:url internal:YES];
}

// Internal means we don't go through AppKit's URL handling; it's a direct call within the app.
- (BOOL)handleiTerm2URL:(NSURL *)url internal:(BOOL)internal {
    NSURLComponents *components = [[[NSURLComponents alloc] initWithURL:url resolvingAgainstBaseURL:NO] autorelease];
    if ([components.path isEqualToString:@"reveal"]) {
        [self revealWithURL:url];
        return YES;
    }
    if ([components.path isEqualToString:@"explain"]) {
        [[iTermCommandExplainer instance] explainWithURL:url];
        return YES;
    }
    if ([components.path isEqualToString:@"copy-block"]) {
        NSString *guid = [components.queryItems objectPassingTest:^BOOL(NSURLQueryItem *element, NSUInteger index, BOOL *stop) {
            return [element.name isEqualToString:@"guid"];
        }].value;
        if (!guid) {
            guid = [[[iTermController sharedInstance] currentTerminal] currentSession].guid;
        }
        NSString *blockID = [components.queryItems objectPassingTest:^BOOL(NSURLQueryItem *element, NSUInteger index, BOOL *stop) {
            return [element.name isEqualToString:@"block"];
        }].value;
        if (guid && blockID) {
            PTYSession *session = [[iTermController sharedInstance] sessionWithGUID:guid];
            if (!session) {
                DLog(@"No session with guid %@", guid);
                return YES;
            }
            [session copyTextFromBlockWithID:blockID];
        }
        return YES;
    }
    if ([components.path isEqualToString:@"/command"]) {
        [self runCommandFromURL:components internal:internal];
        return YES;
    }
    if (internal) {
        if ([components.path isEqualToString:@"disable-command-selection"]) {
            [self disableCommandSelection];
            return YES;
        }
    }
    return NO;
}

- (void)disableCommandSelection {
    [iTermPreferences setBool:NO forKey:kPreferenceKeyClickToSelectCommand];
    [[PreferencePanel sharedInstance] openToPreferenceWithKey:kPreferenceKeyClickToSelectCommand];
}

- (void)runCommandFromURL:(NSURLComponents *)components internal:(BOOL)internal {
    NSString *hostname = [components.host sanitizedHostname];
    NSString *username = [components.user sanitizedUsername];
    NSString *command = [[[components.queryItems objectPassingTest:^BOOL(NSURLQueryItem *element, NSUInteger index, BOOL *stop) {
        return [element.name isEqualToString:@"c"];
    }].value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] removingInvisibles];
    NSString *directory = [components.queryItems objectPassingTest:^BOOL(NSURLQueryItem *element, NSUInteger index, BOOL *stop) {
        return [element.name isEqualToString:@"d"];
    }].value;
    const BOOL silent = [components.queryItems objectPassingTest:^BOOL(NSURLQueryItem *element, NSUInteger index, BOOL *stop) {
        return [element.name isEqualToString:@"silent"];
    }];
    if (@available(macOS 11, *)) {
        iTermCommandURLHandler *handler = [[[iTermCommandURLHandler alloc] initWithCommand:command
                                                                                  hostname:hostname
                                                                                  username:username
                                                                                 directory:directory
                                                                                  offerTab:(iTermController.sharedInstance.currentTerminal != nil)
                                                                                    silent:silent] autorelease];
        [handler showWithCompletion:^(iTermCommandURLHandler *handler) {
            if ([handler.action isEqualTo: iTermCommandURLHandler.openInWindow]) {
                [[iTermController sharedInstance] openWindow:YES
                                                     command:handler.command
                                                   directory:handler.directory
                                                    hostname:handler.hostname
                                                    username:handler.username];
            } else if ([handler.action isEqualTo: iTermCommandURLHandler.openInTab]) {
                [[iTermController sharedInstance] openWindow:NO
                                                     command:handler.command
                                                   directory:handler.directory
                                                    hostname:handler.hostname
                                                    username:handler.username];
            } else if ([handler.action isEqualTo: iTermCommandURLHandler.runInCurrentTab]) {
                [[[[iTermController sharedInstance] currentTerminal] currentSession] runCommand:handler.command
                                                                                    inDirectory:handler.directory
                                                                                         onHost:handler.hostname
                                                                                         asUser:handler.username];
            } else if ([handler.action isEqual:iTermCommandURLHandler.runSilently] && internal) {
                NSArray<NSString *> *parts = [handler.command componentsInShellCommand];
                if (parts.count > 0) {
                    [iTermBufferedCommandRunner runCommandWithPath:@"/bin/sh"
                                                         arguments:@[ @"-c", handler.command ?: @"" ]
                                                            window:[[[iTermController sharedInstance] currentTerminal] window]];
                }
            }
        }];
    }
}

- (void)getUrl:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent {
    NSString *urlStr = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
    NSURL *url = [NSURL URLWithString:urlStr];
    NSString *scheme = [url scheme];

    if ([scheme isEqualToString:@"iterm2"]) {
        [self handleiTerm2URL:url internal:NO];
        return;
    }
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
            [iTermSessionLauncher launchBookmark:profile
                                      inTerminal:term
                                         withURL:urlStr
                                hotkeyWindowType:iTermHotkeyWindowTypeNone
                                         makeKey:NO
                                     canActivate:NO
                              respectTabbingMode:YES
                                           index:nil
                                         command:nil
                                     makeSession:nil
                                  didMakeSession:nil
                                      completion:nil];
        }
    }
}

- (void)reloadMenus:(NSNotification *)aNotification {
    PseudoTerminal *frontTerminal = [self currentTerminal];
    if (frontTerminal != [aNotification object]) {
        return;
    }

    [self buildSessionSubmenu: aNotification];
}

- (void)updateAddressBookMenu:(NSNotification *)aNotification {
    DLog(@"Updating Profile menu");
    iTermProfileModelJournalParams *params = [[[iTermProfileModelJournalParams alloc] init] autorelease];
    if ([iTermAdvancedSettingsModel openProfilesInNewWindow]) {
        params.selector = @selector(newSessionInWindowAtIndex:);
        params.alternateSelector = @selector(newSessionInTabAtIndex:);
        [bookmarkMenu itemAtIndex:2].title = [[bookmarkMenu itemAtIndex:2].title stringByReplacingOccurrencesOfString:@"Window" withString:@"Tab"];
        [bookmarkMenu itemAtIndex:3].title = [[bookmarkMenu itemAtIndex:3].title stringByReplacingOccurrencesOfString:@"Window" withString:@"Tab"];
    } else {
        params.selector = @selector(newSessionInTabAtIndex:);
        params.alternateSelector = @selector(newSessionInWindowAtIndex:);
        [bookmarkMenu itemAtIndex:2].title = [[bookmarkMenu itemAtIndex:2].title stringByReplacingOccurrencesOfString:@"Tab" withString:@"Window"];
        [bookmarkMenu itemAtIndex:3].title = [[bookmarkMenu itemAtIndex:3].title stringByReplacingOccurrencesOfString:@"Tab" withString:@"Window"];
    }
    params.openAllSelector = @selector(newSessionsInWindow:);
    params.alternateOpenAllSelector = @selector(newSessionsInWindow:);
    params.target = [iTermController sharedInstance];

    NSDictionary<NSString *, NSNumber *> *shortcutsChanged =
    [iTermProfilesMenuController applyJournal:[aNotification userInfo]
                                       toMenu:bookmarkMenu
                               startingAtItem:5
                                       params:params];
    // See issue 6254.
    NSNumber *fShortcut = shortcutsChanged[@"F"];
    if (fShortcut) {
        if (fShortcut.boolValue) {
            // Added a menu item with cmd-ctrl-F as the shortcut. Change enter full screen to cmd-enter.
            [_enterFullScreenMenuItem setKeyEquivalent:@"\n"];
            [_enterFullScreenMenuItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
        } else {
            // Removed a menu item with cmd-ctrl-F as the shortcut. Change enter full screen to cmd-F.
            [_enterFullScreenMenuItem setKeyEquivalent:@"f"];
            [_enterFullScreenMenuItem setKeyEquivalentModifierMask:(NSEventModifierFlagCommand |
                                                                    NSEventModifierFlagControl)];
        }
    }
}

#pragma mark - Startup Helpers

- (void)complainIfNightlyBuildIsTooOld {
    if (![NSBundle it_isNightlyBuild]) {
        return;
    }
    NSTimeInterval age = -[[NSBundle it_buildDate] timeIntervalSinceNow];
    if (age > 30 * 24 * 60 * 60) {
        iTermWarningSelection selection =
        [iTermWarning showWarningWithTitle:@"This nightly build is over 30 days old. Consider updating soon: you may be suffering from awful bugs in blissful ignorance."
                                   actions:@[ @"I’ll Take My Chances", @"Update Now" ]
                                identifier:@"NoSyncVeryOldNightlyBuildWarning"
                               silenceable:kiTermWarningTypeSilenceableForOneMonth
                                    window:nil];
        if (selection == kiTermWarningSelection1) {
            [[SUUpdater sharedUpdater] checkForUpdates:nil];
        }
    }
}

// This performs startup activities as long as they haven't been run before.
- (void)performStartupActivities {
    DLog(@"performStartupActivities");
    if (gStartupActivitiesPerformed) {
        DLog(@"Already done");
        return;
    }
    gStartupActivitiesPerformed = YES;
    if (quiet_) {
        DLog(@"Launched in quiet mode. Return early.");
        // iTerm2 was launched with "open file" that turns off startup activities.
        [_untitledWindowStateMachine didFinishInitialization];
        return;
    }
    [[iTermController sharedInstance] setStartingUp:YES];

    // Check if we have an autolaunch script to execute. Do it only once, i.e. at application launch.
    BOOL ranAutoLaunchScripts = NO;
    if (![self isAppleScriptTestApp] &&
        ![[NSApplication sharedApplication] isRunningUnitTests]) {
        ranAutoLaunchScripts = [self.scriptsMenuController runAutoLaunchScriptsIfNeeded];
    }
    DLog(@"ranAutoLaunchScripts=%@", @(ranAutoLaunchScripts));

    if ([WindowArrangements defaultArrangementName] == nil &&
        [WindowArrangements arrangementWithName:LEGACY_DEFAULT_ARRANGEMENT_NAME] != nil) {
        [WindowArrangements makeDefaultArrangement:LEGACY_DEFAULT_ARRANGEMENT_NAME];
    }

    if ([iTermPreferences boolForKey:kPreferenceKeyOpenBookmark]) {
        // Open bookmarks window at startup.
        [[iTermProfilesWindowController sharedInstance] showWindow:nil];
    }

    DLog(@"terminals=%@", [[iTermController sharedInstance] terminals]);
    DLog(@"profileHotKeys=%@", [[iTermHotKeyController sharedInstance] profileHotKeys]);
    DLog(@"buriedSessions=%@", [[iTermBuriedSessions sharedInstance] buriedSessions]);

    if ([iTermPreferences boolForKey:kPreferenceKeyOpenArrangementAtStartup]) {
        // Open the saved arrangement at startup.
        [[iTermController sharedInstance] loadWindowArrangementWithName:[WindowArrangements defaultArrangementName]];
    } else if ([self shouldOpenUntitledFileAfterRunningAutoLaunchScripts:ranAutoLaunchScripts]) {
        // This opens the initial untitled window when needed. -applicationOpenUntitledFile is
        // called for both the initial window (unreliably) and also when clicking on the dock with
        // no windows.
        [_untitledWindowStateMachine maybeOpenUntitledFile];
    }
    [_untitledWindowStateMachine didFinishInitialization];

    [[iTermController sharedInstance] setStartingUp:NO];
    [PTYSession removeAllRegisteredSessions];

    [iTermLaunchExperienceController performStartupActivities];
}

- (BOOL)shouldOpenUntitledFileAfterRunningAutoLaunchScripts:(BOOL)ranAutoLaunchScripts {
    if ([self isAppleScriptTestApp]) {
        return NO;
    }
    if ([[NSApplication sharedApplication] isRunningUnitTests]) {
        return NO;
    }
    if (![iTermAdvancedSettingsModel openNewWindowAtStartup]) {
        return NO;
    }

    if ([iTermPreferences boolForKey:kPreferenceKeyOpenArrangementAtStartup]) {
        return NO;
    }
    if ([iTermPreferences boolForKey:kPreferenceKeyOpenNoWindowsAtStartup]) {
        return NO;
    }
    if ([[[iTermController sharedInstance] terminals] count] > 0) {
        return NO;
    }
    const BOOL alwaysOpen = [iTermPreferences boolForKey:kPreferenceKeyAlwaysOpenWindowAtStartup];
    if (alwaysOpen) {
        return YES;
    }
    if (ranAutoLaunchScripts) {
        return NO;
    }
    if ([[[iTermHotKeyController sharedInstance] profileHotKeys] count] > 0) {
        return NO;
    }
    if ([[[iTermBuriedSessions sharedInstance] buriedSessions] count] > 0) {
        return NO;
    }
    return YES;
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

- (IBAction)copyPerformanceStats:(id)sender {
    NSString *copyString = iTermPreciseTimerGetSavedLogs();
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    [pboard declareTypes:[NSArray arrayWithObject:NSPasteboardTypeString] owner:self];
    [pboard setString:copyString forType:NSPasteboardTypeString];
}

- (IBAction)checkForUpdatesFromMenu:(id)sender {
    [suUpdater checkForUpdates:(sender)];
}

- (IBAction)removeFileProvider:(id)sender {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermRemoveFileProvider" object:nil];
}

- (IBAction)addFileProvider:(id)sender {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermAddFileProvider" object:nil];
}

#pragma mark - Main Menu

- (SEL)restoreWindowArrangementSelectorAsTabs:(BOOL)asTabs fromDock:(BOOL)fromDock {
    if (fromDock) {
        if (asTabs) {
            return @selector(restoreWindowArrangementAfterDelayAsTabs:);
        } else {
            return @selector(restoreWindowArrangementAfterDelay:);
        }
    } else {
        if (asTabs) {
            return @selector(restoreWindowArrangementAsTabs:);
        } else {
            return @selector(restoreWindowArrangement:);
        }
    }
}

- (void)updateRestoreWindowArrangementsMenu:(NSMenuItem *)menuItem asTabs:(BOOL)asTabs fromDock:(BOOL)fromDock {
    SEL selector = [self restoreWindowArrangementSelectorAsTabs:asTabs fromDock:fromDock];
    [WindowArrangements refreshRestoreArrangementsMenu:menuItem
                                          withSelector:selector
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
    newItem = [[[iTermTabColorMenuItem alloc] initWithTitle:title
                                                     action:@selector(changeTabColorToMenuAction:)
                                              keyEquivalent:@""] autorelease];
    [newItem setView:view];
    [menu addItem:newItem];
}

- (void)newSessionMenu:(NSMenu *)superMenu
                 title:(NSString*)title
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
                                               supermenu:superMenu
                                            withSelector:selector
                                         openAllSelector:openAllSelector
                                              startingAt:0];
    [newMenuItem setSubmenu:bookmarksMenu];
}

- (NSMenu*)bookmarksMenu {
    return bookmarkMenu;
}

- (void)addArrangementsToDockMenu:(NSMenu *)theMenu {
    NSMenuItem *container = [theMenu addItemWithTitle:@"Restore Arrangement"
                                               action:nil
                                        keyEquivalent:@""];
    NSMenu *subMenu = [[[NSMenu alloc] init] autorelease];
    [container setSubmenu:subMenu];
    [self updateRestoreWindowArrangementsMenu:container asTabs:NO fromDock:YES];
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
            aMenuItem  = [[NSMenuItem alloc] initWithTitle:[[[aTab activeSession] name] removingHTMLFromTabTitleIfNeeded]
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
}

#pragma mark - Actions

- (IBAction)findGlobally:(id)sender {
    if (!_globalSearchWindowController) {
        _globalSearchWindowController = [[iTermGlobalSearchWindowController alloc] init];
    }
    [_globalSearchWindowController activate];
}

- (IBAction)promptToConvertTabsToSpacesWhenPasting:(id)sender {
    [iTermPasteHelper togglePromptToConvertTabsToSpacesWhenPasting];
}

- (IBAction)makeDefaultTerminal:(id)sender {
    [[iTermLaunchServices sharedInstance] makeITermDefaultTerminal];
}

- (IBAction)unmakeDefaultTerminal:(id)sender {
    [[iTermLaunchServices sharedInstance] makeTerminalDefaultTerminal];
}

- (void)restoreWindowArrangementAfterDelay:(id)sender {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[iTermController sharedInstance] loadWindowArrangementWithName:[sender title]];
    });
}

- (void)restoreWindowArrangement:(id)sender {
    [[iTermController sharedInstance] loadWindowArrangementWithName:[sender title]];
}

- (void)restoreWindowArrangementAfterDelayAsTabs:(id)sender {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[iTermController sharedInstance] loadWindowArrangementWithName:[sender title] asTabsInTerminal:[[iTermController sharedInstance] currentTerminal]];
    });
}

- (void)restoreWindowArrangementAsTabs:(id)sender {
    [[iTermController sharedInstance] loadWindowArrangementWithName:[sender title] asTabsInTerminal:[[iTermController sharedInstance] currentTerminal]];
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
    if ([iTermToolbeltView numberOfVisibleTools] == 1 && [menuItem state] == NSControlStateValueOn) {
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

- (IBAction)newWindowWithSameProfile:(id)sender
{
    [[iTermController sharedInstance] newSessionWithSameProfile:sender
                                                      newWindow:YES];
}

- (IBAction)newSessionWithSameProfile:(id)sender
{
    [[iTermController sharedInstance] newSessionWithSameProfile:sender
                                                      newWindow:NO];
}

- (IBAction)newSession:(id)sender {
    [self newTabAtIndex:nil];
}

- (void)newTabAtIndex:(NSNumber *)index {
    DLog(@"iTermApplicationDelegate newSession:");
    BOOL cancel;
    BOOL tmux = [self possiblyTmuxValueForWindow:NO cancel:&cancel];
    if (cancel) {
        DLog(@"Cancel");
        return;
    }
    [[iTermController sharedInstance] newSession:nil possiblyTmux:tmux index:index];
}

- (IBAction)arrangeHorizontally:(id)sender
{
    [[iTermController sharedInstance] arrangeHorizontally];
}

- (IBAction)arrangeSplitPanesEvenly:(id)sender {
    [[[[iTermController sharedInstance] currentTerminal] currentTab] arrangeSplitPanesEvenly];
}

- (IBAction)newTmuxWindow:(id)sender {
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        TmuxController *controller = [[term uniqueTmuxControllers] firstObject];
        if (controller) {
            [term newTmuxWindow:nil];
            return;
        }
    }
}

- (IBAction)newTmuxTab:(id)sender {
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        TmuxController *controller = [[term uniqueTmuxControllers] firstObject];
        if (controller) {
            [term newTmuxTab:nil];
            return;
        }
    }
}

- (IBAction)showPrefWindow:(id)sender {
    [[PreferencePanel sharedInstance] run];
    [[[PreferencePanel sharedInstance] window] makeKeyAndOrderFront:self];
}

- (IBAction)showAndOrderFrontRegardlessPrefWindow:(id)sender {
    [self showPrefWindow:sender];
    [[[PreferencePanel sharedInstance] window] orderFrontRegardless];
}

- (IBAction)showBookmarkWindow:(id)sender {
    [NSApp activateIgnoringOtherApps:YES];
    [[iTermProfilesWindowController sharedInstance] showWindow:sender];
}

- (IBAction)pasteFaster:(id)sender
{
    [self changePasteSpeedBy:1.5
                    bytesKey:@"QuickPasteBytesPerCall"
                defaultBytes:iTermQuickPasteBytesPerCallDefaultValue
                    delayKey:@"QuickPasteDelayBetweenCalls"
                defaultDelay:.01];
}

- (IBAction)pasteSlower:(id)sender
{
    [self changePasteSpeedBy:0.66
                    bytesKey:@"QuickPasteBytesPerCall"
                defaultBytes:iTermQuickPasteBytesPerCallDefaultValue
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
        [self undoCloseSession:nil];
    }
}

- (IBAction)undoCloseSession:(id)sender {
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
                    DLog(@"reuse an existing window");
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
                                                             windowType:iTermWindowDefaultType()
                                                        savedWindowType:iTermWindowDefaultType()
                                                                 screen:-1
                                                                profile:nil] autorelease];
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
                                                             windowType:iTermWindowDefaultType()
                                                        savedWindowType:iTermWindowDefaultType()
                                                                 screen:-1
                                                                profile:nil] autorelease];
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
                                                         named:nil
                                                      sessions:restorableSession.sessions
                                      forceOpeningHotKeyWindow:YES];
                [[iTermController sharedInstance] addTerminalWindow:term];
                term.terminalGuid = restorableSession.terminalGuid;
                break;
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

- (IBAction)toggleDisableTransparencyForActiveWindow:(id)sender {
    const BOOL oldValue = [iTermPreferences boolForKey:kPreferenceKeyDisableTransparencyForKeyWindow];
    [iTermPreferences setBool:!oldValue forKey:kPreferenceKeyDisableTransparencyForKeyWindow];
    [[[NSApp keyWindow] contentView] setNeedsDisplay:YES];
}

- (IBAction)toggleSecureInput:(id)sender {
    [[iTermSecureKeyboardEntryController sharedInstance] toggle];
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

- (void)clearAllDownloads:(id)sender {
    [[FileTransferManager sharedInstance] removeAllDownloads];
}

- (void)clearAllUploads:(id)sender{
    [[FileTransferManager sharedInstance] removeAllUploads];
}

- (IBAction)showHelp:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.iterm2.com/documentation.html"]];
}

- (iTermScriptsMenuController *)scriptsMenuController {
    if (!_scriptsMenuController) {
        _scriptsMenuController = [[iTermScriptsMenuController alloc] initWithMenu:_scriptsMenu];
        _scriptsMenuController.installRuntimeMenuItem = _installPythonRuntime;
    }
    return _scriptsMenuController;
}

- (IBAction)installPythonRuntime:(id)sender {  // Explicit request from menu item
    if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
        return;
    }
    [[iTermPythonRuntimeDownloader sharedInstance] downloadOptionalComponentsIfNeededWithConfirmation:NO
                                                                                        pythonVersion:nil
                                                                            minimumEnvironmentVersion:0
                                                                                   requiredToContinue:NO
                                                                                       withCompletion:
     ^(iTermPythonRuntimeDownloaderStatus status) {
         if (status == iTermPythonRuntimeDownloaderStatusNotNeeded) {
             [iTermWarning showWarningWithTitle:@"You’re up to date!"
                                        actions:@[ @"OK" ]
                                      accessory:nil
                                     identifier:nil
                                    silenceable:kiTermWarningTypePersistent
                                        heading:@"Python Runtime"
                                         window:nil];
         }
     }];
}

- (IBAction)installAlreadyDownloadedPythonRuntime:(id)sender {
    __weak NSOpenPanel *panel = [[NSOpenPanel alloc] init];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (panel.URL != nil && result == NSModalResponseOK) {
            [[iTermPythonRuntimeDownloader sharedInstance] installPythonEnvironmentFromZip:panel.URL.path
                                                                                completion:^(NSError *error) {
                if (!error) {
                    [iTermWarning showWarningWithTitle:@"Installed successfully!"
                                               actions:@[ @"OK" ]
                                             accessory:nil
                                            identifier:nil
                                           silenceable:kiTermWarningTypePersistent
                                               heading:@"Python Runtime"
                                                window:nil];
                } else {
                    [iTermWarning showWarningWithTitle:error.localizedDescription ?: @"Unknown error"
                                               actions:@[ @"OK" ]
                                             accessory:nil
                                            identifier:nil
                                           silenceable:kiTermWarningTypePersistent
                                               heading:@"Error Installing Python Runtime"
                                                window:nil];
                }
            }];
        }
    }];
}

- (IBAction)buildScriptMenu:(id)sender {
    [iTermScriptConsole sharedInstance];
    [self.scriptsMenuController build];
}

- (IBAction)openREPL:(id)sender {
    if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
        return;
    }
    [[iTermPythonRuntimeDownloader sharedInstance] downloadOptionalComponentsIfNeededWithConfirmation:YES
                                                                                        pythonVersion:nil
                                                                            minimumEnvironmentVersion:0
                                                                                   requiredToContinue:YES
                                                                                       withCompletion:
     ^(iTermPythonRuntimeDownloaderStatus status) {
        switch (status) {
            case iTermPythonRuntimeDownloaderStatusRequestedVersionNotFound:
            case iTermPythonRuntimeDownloaderStatusCanceledByUser:
            case iTermPythonRuntimeDownloaderStatusUnknown:
            case iTermPythonRuntimeDownloaderStatusWorking:
            case iTermPythonRuntimeDownloaderStatusError:
                return;
            case iTermPythonRuntimeDownloaderStatusNotNeeded:
            case iTermPythonRuntimeDownloaderStatusDownloaded:
                break;
        }
        if (![iTermAPIHelper sharedInstanceFromExplicitUserAction]) {
            return;
        }
        NSString *apython = [[[[[iTermPythonRuntimeDownloader sharedInstance] pathToStandardPyenvPythonWithPythonVersion:nil] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"apython"] stringWithBackslashEscapedShellCharactersIncludingNewlines:YES];
        NSURL *bannerURL = [[NSBundle mainBundle] URLForResource:@"repl_banner" withExtension:@"txt"];
        NSString *bannerText = [NSString stringWithContentsOfURL:bannerURL encoding:NSUTF8StringEncoding error:nil];
        NSString *cookie = [[iTermWebSocketCookieJar sharedInstance] randomStringForCookie];
        NSString *key = [[NSUUID UUID] UUIDString];
        NSString *identifier = [[iTermAPIConnectionIdentifierController sharedInstance] identifierForKey:key];
        iTermScriptHistoryEntry *entry = [[[iTermScriptHistoryEntry alloc] initWithName:@"REPL"
                                                                               fullPath:nil
                                                                             identifier:identifier
                                                                              relaunch:nil] autorelease];
        [[iTermScriptHistory sharedInstance] addHistoryEntry:entry];
        NSDictionary *environment = @{ @"ITERM2_COOKIE": cookie,
                                       @"ITERM2_KEY": key };

        [[iTermController sharedInstance] openSingleUseWindowWithCommand:apython
                                                               arguments:@[ @"--banner=\\\"\\\"" ]
                                                                  inject:[bannerText dataUsingEncoding:NSUTF8StringEncoding]
                                                             environment:environment
                                                                     pwd:nil
                                                                 options:iTermSingleUseWindowOptionsDoNotEscapeArguments
                                                          didMakeSession:nil
                                                              completion:nil];
    }];
}

- (IBAction)removeRecentProfilesFromDockMenu:(id)sender {
    [ProfileDocument removeAllRecents];
}

- (IBAction)openDependencyEditor:(id)sender {
    [[iTermDependencyEditorWindowController sharedInstance] open];
}

- (IBAction)openScriptConsole:(id)sender {
    [[[iTermScriptConsole sharedInstance] window] makeKeyAndOrderFront:nil];
}

- (IBAction)revealScriptsInFinder:(id)sender {
    [_scriptsMenuController revealScriptsInFinder];
}

- (IBAction)exportScript:(id)sender {
    if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
        return;
    }
    [_scriptsMenuController chooseAndExportScript];
}

- (IBAction)importScript:(id)sender {
    [_scriptsMenuController chooseAndImportScript];
}

- (IBAction)newPythonScript:(id)sender {
    if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
        return;
    }
    [_scriptsMenuController newPythonScript];
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

- (NSString *)gpuUnavailableStringForReason:(iTermMetalUnavailableReason)reason {
    return iTermMetalUnavailableReasonDescription(reason);
}

- (IBAction)gpuRendererAvailability:(id)sender {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = @"GPU Renderer Availability";
    PseudoTerminal *term = [[iTermController sharedInstance] currentTerminal];
    PTYSession *session = [term currentSession];
    PTYTab *tab = [term tabForSession:session];
    NSString *reason = [self gpuUnavailableStringForReason:tab.metalUnavailableReason];
    if (reason) {
        alert.informativeText = [NSString stringWithFormat:@"GPU rendering is off in the current session because %@", reason];
    } else {
        alert.informativeText = @"GPU rendering is enabled for the current session.";
    }
    [alert runModal];
}

- (IBAction)openSourceLicenses:(id)sender {
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:@"Licenses" withExtension:@"txt"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (IBAction)loadRecording:(id)sender {
    [iTermRecordingCodec loadRecording];
}

- (IBAction)toggleAlertOnMarksInOffscreenSessions:(id)sender {
    [iTermPreferences setBool:![iTermPreferences boolForKey:kPreferenceKeyAlertOnMarksInOffscreenSessions]
                    forKey:kPreferenceKeyAlertOnMarksInOffscreenSessions];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermDidToggleAlertOnMarksInOffscreenSessionsNotification object:nil];
}


#pragma mark - Private

- (void)updateProcessType {
    BOOL enableLSUI = [iTermPreferences boolForKey:kPreferenceKeyUIElement];

    if ([iTermPreferences boolForKey:kPreferenceKeyUIElementRequiresHotkeys]) {
        const BOOL onlyHotKeyWindowsOpen = [self.terminals allWithBlock:^BOOL(PseudoTerminal *term) { return term.isHotKeyWindow; }];

        enableLSUI = enableLSUI && onlyHotKeyWindowsOpen;
    }
    
    [[iTermApplication sharedApplication] setIsUIElement:enableLSUI];
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
    static NSString *const legacyKey = @"NoSyncNewWindowOrTabFromTmuxOpensTmux";
    NSString *key;
    if ([iTermWarning identifierIsSilenced:legacyKey]) {
        key = legacyKey;
    } else if (isWindow) {
        key = @"NoSyncNewWindowFromTmuxOpensTmux";
    } else {
        key = @"NoSyncNewTabFromTmuxOpensTmux";
    }

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
                                                                  identifier:key
                                                                 silenceable:kiTermWarningTypePermanentlySilenceable
                                                                     heading:heading
                                                                      window:[[[iTermController sharedInstance] currentTerminal] window]];
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

    [ToastWindowController showToastWithMessage:[NSString stringWithFormat:@"Pasting at up to %@/sec", [NSString it_formatBytes:rate]]];
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

- (void)iTermPasswordManagerEnterPassword:(NSString *)password broadcast:(BOOL)broadcast {
  [[[[iTermController sharedInstance] currentTerminal] currentSession] enterPassword:password];
}

- (BOOL)iTermPasswordManagerCanEnterUserName {
    return YES;
}

- (void)iTermPasswordManagerEnterUserName:(NSString *)username broadcast:(BOOL)broadcast {
    [[[[iTermController sharedInstance] currentTerminal] currentSession] writeTask:[username stringByAppendingString:@"\n"]];
}

- (BOOL)iTermPasswordManagerCanEnterPassword {
  PTYSession *session = [[[iTermController sharedInstance] currentTerminal] currentSession];
  return session && ![session exited];
}

- (BOOL)iTermPasswordManagerCanBroadcast {
    return NO;
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

- (void)windowDidChangeKeyStatus:(NSNotification *)notification {
    DLog(@"%@:\n%@", notification.name, [NSThread callStackSymbols]);
}

#pragma mark - iTermOrphanServerAdopterDelegate

- (void)orphanServerAdopterOpenSessionForConnection:(iTermGeneralServerConnection)generalConnection
                                           inWindow:(id)desiredWindow
                                         completion:(void (^)(PTYSession *session))completion {
    assert([iTermAdvancedSettingsModel runJobsInServers]);

    void (^makeSession)(NSDictionary * _Nonnull,
                        PseudoTerminal * _Nonnull,
                        void (^ _Nonnull)(PTYSession * _Nonnull)) =
    ^(NSDictionary * _Nonnull profile,
      PseudoTerminal * _Nonnull term,
      void (^ _Nonnull didMakeSession)(PTYSession * _Nonnull)) {
        [self makeSessionWithConnection:generalConnection windowController:term completion:didMakeSession];
    };

    [iTermSessionLauncher launchBookmark:nil
                              inTerminal:desiredWindow
                                 withURL:nil
                        hotkeyWindowType:iTermHotkeyWindowTypeNone
                                 makeKey:NO
                             canActivate:NO
                      respectTabbingMode:NO
                                   index:nil
                                 command:nil
                             makeSession:makeSession
                          didMakeSession:^(PTYSession * _Nonnull session) {
        [session showOrphanAnnouncement];
        completion(session);
    }
                              completion:nil];
}

- (void)orphanServerAdopterOpenSessionForPartialAttachment:(id<iTermPartialAttachment>)partialAttachment
                                                  inWindow:(id)window
                                                completion:(void (^)(PTYSession *))completion {
    assert([iTermAdvancedSettingsModel runJobsInServers]);

    void (^makeSession)(NSDictionary * _Nonnull,
                        PseudoTerminal * _Nonnull,
                        void (^ _Nonnull)(PTYSession * _Nonnull)) =
    ^(NSDictionary * _Nonnull profile,
      PseudoTerminal * _Nonnull term,
      void (^ _Nonnull didMakeSession)(PTYSession * _Nonnull)) {
        [self makeSessionWithPartialAttachment:partialAttachment
                              windowController:term
                                    completion:didMakeSession];
    };

    [iTermSessionLauncher launchBookmark:nil
                              inTerminal:window
                                 withURL:nil
                        hotkeyWindowType:iTermHotkeyWindowTypeNone
                                 makeKey:NO
                             canActivate:NO
                      respectTabbingMode:NO
                                   index:nil
                                 command:nil
                             makeSession:makeSession
                          didMakeSession:^(PTYSession * _Nonnull session) {
        [session showOrphanAnnouncement];
        completion(session);
    }
                              completion:nil];
}

- (void)makeSessionWithConnection:(iTermGeneralServerConnection)generalConnection
                 windowController:(PseudoTerminal *)term
                       completion:(void (^)(PTYSession *))didMakeSession {
    Profile *defaultProfile = [[ProfileModel sharedInstance] defaultBookmark];
    PTYSession *session = [[term.sessionFactory newSessionWithProfile:defaultProfile
                                                               parent:nil] autorelease];
    [term addSessionInNewTab:session];
    iTermGeneralServerConnection temp = generalConnection;
    iTermSessionAttachOrLaunchRequest *launchRequest =
    [iTermSessionAttachOrLaunchRequest launchRequestWithSession:session
                                                      canPrompt:NO
                                                     objectType:iTermWindowObject
                                            hasServerConnection:YES
                                               serverConnection:temp
                                                      urlString:nil
                                                   allowURLSubs:NO
                                                    environment:@{}
                                                    customShell:[ITAddressBookMgr customShellForProfile:defaultProfile]
                                                         oldCWD:nil
                                                 forceUseOldCWD:NO
                                                        command:nil
                                                         isUTF8:nil
                                                  substitutions:nil
                                               windowController:term
                                                          ready:^(BOOL ok) { didMakeSession(ok ? session : nil); }
                                                     completion:nil];
    [term.sessionFactory attachOrLaunchWithRequest:launchRequest];
}

- (void)makeSessionWithPartialAttachment:(id<iTermPartialAttachment>)partialAttachment
                        windowController:(PseudoTerminal *)term
                              completion:(void (^)(PTYSession *))didMakeSession {
    Profile *defaultProfile = [[ProfileModel sharedInstance] defaultBookmark];
    PTYSession *session = [[term.sessionFactory newSessionWithProfile:defaultProfile
                                                               parent:nil] autorelease];
    [term addSessionInNewTab:session];
    iTermSessionAttachOrLaunchRequest *launchRequest =
    [iTermSessionAttachOrLaunchRequest launchRequestWithSession:session
                                                      canPrompt:NO
                                                     objectType:iTermWindowObject
                                            hasServerConnection:NO
                                               serverConnection:(iTermGeneralServerConnection){}
                                                      urlString:nil
                                                   allowURLSubs:NO
                                                    environment:@{}
                                                    customShell:[ITAddressBookMgr customShellForProfile:defaultProfile]
                                                         oldCWD:nil
                                                 forceUseOldCWD:NO
                                                        command:nil
                                                         isUTF8:nil
                                                  substitutions:nil
                                               windowController:term
                                                          ready:^(BOOL ok) { didMakeSession(ok ? session : nil); }
                                                     completion:nil];
    launchRequest.partialAttachment = partialAttachment;
    [term.sessionFactory attachOrLaunchWithRequest:launchRequest];
}

#pragma mark - iTermRestorableStateControllerDelegate

- (void)restorableStateDidFinishRequestingRestorations:(iTermRestorableStateController *)sender {
    DLog(@"All restorations requested. Set external restoration complete");
    [PseudoTerminalRestorer runQueuedBlocks];
    [PseudoTerminalRestorer externalRestorationDidComplete];

    if (!iTermRestorableStateController.forceSaveState) {
        // Reset this because it's only meant to be temporary.
        [iTermPreferences setBool:NO forKey:@"NoSyncWindowRestoresWorkspaceAtLaunch"];
    }
}

- (NSArray<NSWindow *> *)restorableStateWindows {
    return [[[iTermController sharedInstance] terminals] mapWithBlock:^id(PseudoTerminal *term) {
        if (term.isHotKeyWindow) {
            return nil;
        }
        return term.window;
    }];
}

- (BOOL)restorableStateWindowNeedsRestoration:(NSWindow *)window {
    PseudoTerminal *term = [PseudoTerminal castFrom:window.delegate];
    if (!term) {
        return NO;
    }
    return [term getAndResetRestorableState];
}

- (void)restorableStateRestoreWithCoder:(NSCoder *)coder
                             identifier:(NSString *)identifier
                             completion:(void (^)(NSWindow * _Nonnull, NSError * _Nonnull))completion {
    DLog(@"Enqueue(1) restoration for window with identifier %@", identifier);
    [_untitledWindowStateMachine didRestoreSomeWindows];
    [PseudoTerminalRestorer restoreWindowWithIdentifier:identifier
                                    pseudoTerminalState:[[[PseudoTerminalState alloc] initWithCoder:coder] autorelease]
                                                 system:NO
                                      completionHandler:completion];
}

- (void)restorableStateRestoreWithRecord:(nonnull iTermEncoderGraphRecord *)record
                              identifier:(nonnull NSString *)identifier
                              completion:(nonnull void (^)(NSWindow *, NSError *))completion {
    DLog(@"Enqueue(2) restoration for window with identifier %@", identifier);
    [_untitledWindowStateMachine didRestoreSomeWindows];
    NSDictionary *dict = [NSDictionary castFrom:record.propertyListValue];
    if (!dict) {
        NSError *error = [[[NSError alloc] initWithDomain:@"com.iterm2.app-delegate" code:1 userInfo:nil] autorelease];
        completion(nil, error);
        return;
    }

    PseudoTerminalState *state = [[PseudoTerminalState alloc] initWithDictionary:dict];
    DLog(@"Will restore window with state %p", state);
    [PseudoTerminalRestorer restoreWindowWithIdentifier:identifier
                                    pseudoTerminalState:state
                                                 system:NO
                                      completionHandler:^(NSWindow *window, NSError *error) {
        DLog(@"Did restore window with state %p", state);
        [state autorelease];
        if (error || !window) {
            completion(window, error);
            return;
        }
        PseudoTerminal *term = [PseudoTerminal castFrom:window.delegate];
        if (!term) {
            completion(window, error);
            return;
        }
        DLog(@"Call asyncRestoreState for identifier %@", identifier);
        [term asyncRestoreState:state
                        timeout: ^(NSArray *partialAttachments) { [[iTermOrphanServerAdopter sharedInstance] adoptPartialAttachments:partialAttachments]; }
                     completion: ^{
            DLog(@"Async restore finished for identifier %@", identifier);
            completion(window, error);
        }];
    }];
}


- (void)restorableStateEncodeWithCoder:(NSCoder *)coder
                                window:(NSWindow *)window {
    PseudoTerminal *term = [PseudoTerminal castFrom:window.delegate];
    if (!term) {
        return;
    }
    [term window:window willEncodeRestorableState:coder];
    [window encodeRestorableStateWithCoder:coder];
}

// ********
// * NOTE *
// ********
// If you change this also change -application:willEncodeRestorableState:.
- (BOOL)encodeGraphWithEncoder:(iTermGraphEncoder *)encoder {
    static NSInteger generation;
    if ([[iTermApplication sharedApplication] it_restorableStateInvalid] ||
        [[iTermHotKeyController sharedInstance] anyProfileHotkeyWindowHasInvalidState]) {
        ++generation;
    }
    [iTermApplication sharedApplication].it_restorableStateInvalid = NO;
    return [encoder encodeChildWithKey:@"app"
                            identifier:@""
                            generation:generation
                                 block:^BOOL(iTermGraphEncoder * _Nonnull encoder) {
        DLog(@"app encoding restorable state");
        NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
        [encoder encodeChildWithKey:kScreenCharRestorableStateKey
                         identifier:@""
                         generation:ScreenCharGeneration()
                              block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
            [subencoder mergeDictionary:ScreenCharEncodedRestorableState()];
            return YES;
        }];

        [encoder encodeChildWithKey:kURLStoreRestorableStateKey
                         identifier:@""
                         generation:[[iTermURLStore sharedInstance] generation]
                              block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
            [[iTermURLStore sharedInstance] encodeGraphWithEncoder:subencoder];
            return YES;
        }];

        [encoder encodeChildWithKey:kHotkeyWindowsRestorableStates
                         identifier:@""
                         generation:iTermGenerationAlwaysEncode
                              block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
            return [[iTermHotKeyController sharedInstance] encodeGraphWithEncoder:subencoder];
        }];

        [PortholeRegistry.instance encodeAsChildWith:encoder key:kPortholeRestorableStateKey];

        if ([[[iTermBuriedSessions sharedInstance] buriedSessions] count]) {
            // TODO: Why doesn't this encode window content?
            [encoder encodeObject:[[iTermBuriedSessions sharedInstance] restorableState] key:iTermBuriedSessionState];
        }
        DLog(@"Time to save app restorable state: %@",
             @([NSDate timeIntervalSinceReferenceDate] - start));
        return YES;
    }];
}

- (void)restorableStateRestoreApplicationStateWithRecord:(iTermEncoderGraphRecord *)record {
    if (self.isAppleScriptTestApp) {
        DLog(@"Is applescript test app");
        return;
    }
    iTermEncoderGraphRecord *app = [record childRecordWithKey:@"app" identifier:@""];
    if (!app) {
        DLog(@"No app record");
        return;
    }
    NSDictionary *screenCharState = [app objectWithKey:kScreenCharRestorableStateKey
                                                 class:[NSDictionary class]];
    [NSDictionary castFrom:[[app childRecordWithKey:kScreenCharRestorableStateKey identifier:@""] propertyListValue]];
    if (screenCharState) {
        ScreenCharDecodeRestorableState(screenCharState);
    }

    iTermEncoderGraphRecord *portholeRecord = [app childRecordWithKey:kPortholeRestorableStateKey
                                                           identifier:@""];
    if (portholeRecord) {
        [PortholeRegistry.instance decodeRecord:portholeRecord];
    }

    iTermEncoderGraphRecord *urlStoreRecord = [app childRecordWithKey:kURLStoreRestorableStateKey identifier:@""];
    if (urlStoreRecord) {
        [[iTermURLStore sharedInstance] loadFromGraphRecord:urlStoreRecord];
    }

    iTermEncoderGraphRecord *hotkeyWindowsStates = [app childRecordWithKey:kHotkeyWindowsRestorableStates identifier:@""];
    if (hotkeyWindowsStates) {
        // We have to create the hotkey window now because we need to attach to servers before
        // launch finishes; otherwise any running hotkey window jobs will be treated as orphans.
        const BOOL createdAny = [[iTermHotKeyController sharedInstance] createHiddenWindowsByDecoding:hotkeyWindowsStates];
        if (createdAny && ![iTermPreferences boolForKey:kPreferenceKeyAlwaysOpenWindowAtStartup]) {
            [_untitledWindowStateMachine didRestoreSomeWindows];
        }
    }

    _buriedSessionsState = [[NSArray fromGraphRecord:app withKey:iTermBuriedSessionState] retain];

    if (finishedLaunching_) {
        [self restoreBuriedSessionsState];
    }
    if ([iTermAdvancedSettingsModel logRestorableStateSize]) {
        NSDictionary *dict = @{ kScreenCharRestorableStateKey: screenCharState ?: @{},
                                kPortholeRestorableStateKey: [PortholeRegistry.instance dictionaryValue] ?: @{},
                                kURLStoreRestorableStateKey: urlStoreRecord.propertyListValue ?: @{},
                                iTermBuriedSessionState: _buriedSessionsState ?: @[] };
        NSString *log = [dict sizeInfo];
        [log writeToFile:[NSString stringWithFormat:@"/tmp/statesize.app-%p.txt", self] atomically:NO encoding:NSUTF8StringEncoding error:nil];
    }
    DLog(@"restorableStateRestoreApplicationStateWithRecord: finished");
}

#pragma mark - iTermUntitledWindowStateMachineDelegate

- (void)untitledWindowStateMachineCreateNewWindow:(iTermUntitledWindowStateMachine *)sender {
    DLog(@"untitledWindowStateMachineCreateNewWindow");
    [self newWindow:nil];
}

#pragma mark - NSMenuDelegate

- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu == _triggers.submenu) {
        // Remove all tagged items. This includes the last separator and items for triggers.
        while (_triggers.submenu.itemArray.lastObject.tag != 0) {
            [_triggers.submenu removeItemAtIndex:_triggers.submenu.itemArray.count - 1];
        }

        PTYSession *currentSession = [[[iTermController sharedInstance] currentTerminal] currentSession];
        if (!currentSession) {
            return;
        }

        NSArray<iTermTuple<NSString *, NSNumber *> *> *triggers = [currentSession triggerTuples];
        if (triggers.count) {
            [_triggers.submenu addItem:[NSMenuItem separatorItem]];
            _triggers.submenu.itemArray.lastObject.tag = 1;
        }
        [triggers enumerateObjectsUsingBlock:^(iTermTuple<NSString *,NSNumber *> * _Nonnull tuple, NSUInteger idx, BOOL * _Nonnull stop) {
            [_triggers.submenu addItemWithTitle:tuple.firstObject
                                         action:@selector(toggleTriggerEnabled:)
                                  keyEquivalent:@""];
            NSMenuItem *item = _triggers.submenu.itemArray.lastObject;
            item.representedObject = @(idx);
            item.tag = 1;
            item.state = tuple.secondObject.boolValue ? NSControlStateValueOn : NSControlStateValueOff;
            item.target = self;
        }];
    } else if (menu == _namedMarksMenuItem.submenu) {
        [menu removeAllItems];

        // Populate the submenu with dynamic menu items
        NSArray<id<VT100ScreenMarkReading>> *namedMarks = [[[[[[iTermController sharedInstance] currentTerminal] currentSession] screen] namedMarks] sortedArrayUsingComparator:^NSComparisonResult(id<VT100ScreenMarkReading> lhs, id<VT100ScreenMarkReading> rhs) {
            return [@(lhs.entry.interval.location) compare:@(rhs.entry.interval.location)];
        }];
        for (id<VT100ScreenMarkReading> mark in namedMarks) {
            NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:mark.name ?: @"Unnamed Mark"
                                                              action:@selector(navigateToNamedMark:)
                                                       keyEquivalent:@""];
            menuItem.representedObject = mark.guid;
            [menu addItem:menuItem];
        }
    }
}

- (void)navigateToNamedMark:(NSMenuItem *)menuItem {
    [[[[iTermController sharedInstance] currentTerminal] currentSession] scrollToMarkWithGUID:menuItem.representedObject ?: @""];
}

- (void)menuWillOpen:(NSMenu *)menu {
    DLog(@"menu will open");
}

- (void)toggleTriggerEnabled:(id)sender {
    [[self firstResponderForMenuItem:sender] it_performNonObjectReturningSelector:_cmd withObject:sender];
}

@end
