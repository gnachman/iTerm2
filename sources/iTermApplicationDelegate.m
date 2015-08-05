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

#import "ColorsMenuItemView.h"
#import "HotkeyWindowController.h"
#import "ITAddressBookMgr.h"
#import "iTermAboutWindowController.h"
#import "iTermController.h"
#import "iTermExpose.h"
#import "iTermFileDescriptorSocketPath.h"
#import "iTermFontPanel.h"
#import "iTermIntegerNumberFormatter.h"
#import "iTermPreferences.h"
#import "iTermRemotePreferences.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermOpenQuicklyWindowController.h"
#import "iTermOrphanServerAdopter.h"
#import "iTermProfilesWindowController.h"
#import "iTermPasswordManagerWindowController.h"
#import "iTermRestorableSession.h"
#import "iTermTipController.h"
#import "iTermURLSchemeController.h"
#import "iTermWarning.h"
#import "iTermTipWindowController.h"
#import "NSApplication+iTerm.h"
#import "NSStringITerm.h"
#import "NSView+RecursiveDescription.h"
#import "PreferencePanel.h"
#import "PseudoTerminal.h"
#import "PseudoTerminalRestorer.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PTYTextView.h"
#import "PTYWindow.h"
#import "Sparkle/SUUpdater.h"
#import "ToastWindowController.h"
#import "VT100Terminal.h"
#import <objc/runtime.h>
#include "iTermFileDescriptorClient.h"
#include <sys/stat.h>
#include <unistd.h>

static NSString *APP_SUPPORT_DIR = @"~/Library/Application Support/iTerm";
static NSString *SCRIPT_DIRECTORY = @"~/Library/Application Support/iTerm/Scripts";
static NSString* AUTO_LAUNCH_SCRIPT = @"~/Library/Application Support/iTerm/AutoLaunch.scpt";
static NSString *ITERM2_FLAG = @"~/Library/Application Support/iTerm/version.txt";
static NSString *ITERM2_QUIET = @"~/Library/Application Support/iTerm/quiet";
static NSString *kUseBackgroundPatternIndicatorKey = @"Use background pattern indicator";
NSString *kUseBackgroundPatternIndicatorChangedNotification = @"kUseBackgroundPatternIndicatorChangedNotification";
NSString *const kSavedArrangementDidChangeNotification = @"kSavedArrangementDidChangeNotification";
NSString *const kNonTerminalWindowBecameKeyNotification = @"kNonTerminalWindowBecameKeyNotification";
static NSString *const kMarkAlertAction = @"Mark Alert Action";
NSString *const kMarkAlertActionModalAlert = @"Modal Alert";
NSString *const kMarkAlertActionPostNotification = @"Post Notification";

static NSString *const kScreenCharRestorableStateKey = @"kScreenCharRestorableStateKey";
static NSString *const kHotkeyWindowRestorableState = @"kHotkeyWindowRestorableState";

// There was an older userdefaults key "Multi-Line Paste Warning" that had the opposite semantics.
// This was changed for compatibility with the iTermWarning mechanism.
NSString *const kMultiLinePasteWarningUserDefaultsKey = @"NoSyncDoNotWarnBeforeMultilinePaste";

static BOOL gStartupActivitiesPerformed = NO;
// Prior to 8/7/11, there was only one window arrangement, always called Default.
static NSString *LEGACY_DEFAULT_ARRANGEMENT_NAME = @"Default";
static BOOL ranAutoLaunchScript = NO;
static BOOL hasBecomeActive = NO;

@interface iTermApplicationDelegate () <iTermPasswordManagerDelegate>

@property(nonatomic, readwrite) BOOL workspaceSessionActive;

@end


@implementation iTermApplicationDelegate {
    iTermPasswordManagerWindowController *_passwordManagerWindowController;

    // Menu items
    IBOutlet NSMenu     *bookmarkMenu;
    IBOutlet NSMenu     *toolbeltMenu;
    NSMenuItem *downloadsMenu_;
    NSMenuItem *uploadsMenu_;
    IBOutlet NSMenuItem *selectTab;
    IBOutlet NSMenuItem *previousTerminal;
    IBOutlet NSMenuItem *nextTerminal;
    IBOutlet NSMenuItem *logStart;
    IBOutlet NSMenuItem *logStop;
    IBOutlet NSMenuItem *closeTab;
    IBOutlet NSMenuItem *closeWindow;
    IBOutlet NSMenuItem *sendInputToAllSessions;
    IBOutlet NSMenuItem *sendInputToAllPanes;
    IBOutlet NSMenuItem *sendInputNormally;
    IBOutlet NSMenuItem *toggleBookmarksView;
    IBOutlet NSMenuItem *irNext;
    IBOutlet NSMenuItem *irPrev;
    IBOutlet NSMenuItem *windowArrangements_;

    IBOutlet NSMenuItem *secureInput;
    IBOutlet NSMenuItem *showFullScreenTabs;
    IBOutlet NSMenuItem *useTransparency;
    IBOutlet NSMenuItem *maximizePane;
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
}

// NSApplication delegate methods
- (void)applicationWillFinishLaunching:(NSNotification *)aNotification {
    // Start automatic debug logging if it's enabled.
    if ([iTermAdvancedSettingsModel startDebugLoggingAutomatically]) {
        TurnOnDebugLoggingSilently();
    }

    // set the TERM_PROGRAM environment variable
    putenv("TERM_PROGRAM=iTerm.app");

    [self buildScriptMenu:nil];

    // Fix up various user defaults settings.
    [iTermPreferences initializeUserDefaults];

    // This sets up bonjour and migrates bookmarks if needed.
    [ITAddressBookMgr sharedInstance];

    [iTermToolbeltView populateMenu:toolbeltMenu];

    // Set the Appcast URL and when it changes update it.
    [[iTermController sharedInstance] refreshSoftwareUpdateUserDefaults];
    [iTermPreferences addObserverForKey:kPreferenceKeyCheckForTestReleases
                                  block:^(id before, id after) {
                                      [[iTermController sharedInstance] refreshSoftwareUpdateUserDefaults];
                                  }];
}

// This performs startup activities as long as they haven't been run before.
- (void)_performStartupActivities
{
    if (gStartupActivitiesPerformed) {
        return;
    }
    gStartupActivitiesPerformed = YES;
    if (quiet_) {
        // iTerm2 was launched with "open file" that turns off startup activities.
        return;
    }
    [[iTermController sharedInstance] setStartingUp:YES];
    // Check if we have an autolauch script to execute. Do it only once, i.e. at application launch.
    if (ranAutoLaunchScript == NO &&
        [[NSFileManager defaultManager] fileExistsAtPath:[AUTO_LAUNCH_SCRIPT stringByExpandingTildeInPath]]) {
        ranAutoLaunchScript = YES;

        NSAppleScript *autoLaunchScript;
        NSDictionary *errorInfo = [NSDictionary dictionary];
        NSURL *aURL = [NSURL fileURLWithPath:[AUTO_LAUNCH_SCRIPT stringByExpandingTildeInPath]];

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

        if (![[iTermOrphanServerAdopter sharedInstance] haveOrphanServers]) {
            // We don't respect the startup preference if orphan servers are present.
            // PseudoTerminalRestorer contains similar logic and will restore sessions.
            if ([iTermPreferences boolForKey:kPreferenceKeyOpenArrangementAtStartup]) {
                // Open the saved arrangement at startup.
                [[iTermController sharedInstance] loadWindowArrangementWithName:[WindowArrangements defaultArrangementName]];
            } else if (![iTermPreferences boolForKey:kPreferenceKeyOpenNoWindowsAtStartup]) {
                if (![PseudoTerminalRestorer willOpenWindows]) {
                    if ([[[iTermController sharedInstance] terminals] count] == 0 &&
                        ![self isApplescriptTestApp]) {
                        [self newWindow:nil];
                    }
                }
            }
        }
    }
    [[iTermController sharedInstance] setStartingUp:NO];
    [PTYSession removeAllRegisteredSessions];
    ranAutoLaunchScript = YES;

    // Wait until startup activity has settled down so there's enough CPU for the animation to
    // look good.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   ^{
                       [[iTermTipController sharedInstance] applicationDidFinishLaunching];
                   });
}

- (void)_createFlag
{
    mkdir([[APP_SUPPORT_DIR stringByExpandingTildeInPath] UTF8String], 0755);
    NSDictionary *myDict = [[NSBundle bundleForClass:[self class]] infoDictionary];
    NSString *versionString = [myDict objectForKey:@"CFBundleVersion"];
    NSString *flagFilename = [ITERM2_FLAG stringByExpandingTildeInPath];
    [versionString writeToFile:flagFilename
                    atomically:NO
                      encoding:NSUTF8StringEncoding
                         error:nil];
}

- (void)_updateArrangementsMenu:(NSMenuItem *)container
{
    while ([[container submenu] numberOfItems]) {
        [[container submenu] removeItemAtIndex:0];
    }

    NSString *defaultName = [WindowArrangements defaultArrangementName];

    for (NSString *theName in [WindowArrangements allNames]) {
        NSString *theShortcut;
        if ([theName isEqualToString:defaultName]) {
            theShortcut = @"R";
        } else {
            theShortcut = @"";
        }
        [[container submenu] addItemWithTitle:theName
                                       action:@selector(restoreWindowArrangement:)
                                keyEquivalent:theShortcut];
    }
}

- (void)setDefaultTerminal:(NSString *)bundleId
{
    CFStringRef unixExecutableContentType = (CFStringRef)@"public.unix-executable";
    LSSetDefaultRoleHandlerForContentType(unixExecutableContentType,
                                          kLSRolesShell,
                                          (CFStringRef) bundleId);
}

- (IBAction)makeDefaultTerminal:(id)sender
{
    NSString *iTermBundleId = [[NSBundle mainBundle] bundleIdentifier];
    [self setDefaultTerminal:iTermBundleId];
}

- (IBAction)unmakeDefaultTerminal:(id)sender
{
    [self setDefaultTerminal:@"com.apple.terminal"];
}

- (BOOL)isDefaultTerminal
{
    LSSetDefaultHandlerForURLScheme((CFStringRef)@"iterm2",
                                    (CFStringRef)[[NSBundle mainBundle] bundleIdentifier]);
    CFStringRef unixExecutableContentType = (CFStringRef)@"public.unix-executable";
    CFStringRef unixHandler = LSCopyDefaultRoleHandlerForContentType(unixExecutableContentType, kLSRolesShell);
    NSString *iTermBundleId = [[NSBundle mainBundle] bundleIdentifier];
    BOOL result = [iTermBundleId isEqualToString:(NSString *)unixHandler];
    if (unixHandler) {
        CFRelease(unixHandler);
    }
    return result;
}

- (NSString *)quietFileName {
    return [ITERM2_QUIET stringByExpandingTildeInPath];
}

- (BOOL)quietFileExists {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self quietFileName]];
}

- (void)checkForQuietMode {
    if ([self quietFileExists]) {
        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:[self quietFileName]
                                                   error:&error];
        if (error) {
            NSLog(@"Failed to remove %@: %@; not launching in quiet mode", [self quietFileName], error);
        } else {
            NSLog(@"%@ exists, launching in quiet mode", [self quietFileName]);
            quiet_ = YES;
        }
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    if (IsMavericksOrLater() && [iTermAdvancedSettingsModel disableAppNap]) {
        [[NSProcessInfo processInfo] setAutomaticTerminationSupportEnabled:YES];
        [[NSProcessInfo processInfo] disableAutomaticTermination:@"User Preference"];
        _appNapStoppingActivity =
                [[[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiatedAllowingIdleSystemSleep
                                                                reason:@"User Preference"] retain];
    }
    [iTermFontPanel makeDefault];

    finishedLaunching_ = YES;
    // Create the app support directory
    [self _createFlag];

    // Prevent the input manager from swallowing control-q. See explanation here:
    // http://b4winckler.wordpress.com/2009/07/19/coercing-the-cocoa-text-system/
    CFPreferencesSetAppValue(CFSTR("NSQuotedKeystrokeBinding"),
                             CFSTR(""),
                             kCFPreferencesCurrentApplication);
    // This is off by default, but would wreack havoc if set globally.
    CFPreferencesSetAppValue(CFSTR("NSRepeatCountBinding"),
                             CFSTR(""),
                             kCFPreferencesCurrentApplication);

    // Code could be 0 (e.g., A on an American keyboard) and char is also sometimes 0 (seen in bug 2501).
    if ([iTermPreferences boolForKey:kPreferenceKeyHotkeyEnabled] &&
        ([iTermPreferences intForKey:kPreferenceKeyHotKeyCode] ||
         [iTermPreferences intForKey:kPreferenceKeyHotkeyCharacter])) {
        [[HotkeyWindowController sharedInstance] registerHotkey:[iTermPreferences intForKey:kPreferenceKeyHotKeyCode]
                                                      modifiers:[iTermPreferences intForKey:kPreferenceKeyHotkeyModifiers]];
    }
    if ([[HotkeyWindowController sharedInstance] isAnyModifierRemapped]) {
        // Use a brief delay so windows have a chance to open before the dialog is shown.
        [[HotkeyWindowController sharedInstance] performSelector:@selector(beginRemappingModifiers)
                                                      withObject:nil
                                                      afterDelay:0.5];
    }
    [self _updateArrangementsMenu:windowArrangements_];

    // register for services
    [NSApp registerServicesMenuSendTypes:[NSArray arrayWithObjects:NSStringPboardType, nil]
                                                       returnTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, NSStringPboardType, nil]];
    // Sometimes, open untitled doc isn't called in Lion. We need to give application:openFile:
    // a chance to run because a "special" filename cancels _performStartupActivities.
    [self checkForQuietMode];
    [self performSelector:@selector(_performStartupActivities)
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

    if ([iTermAdvancedSettingsModel runJobsInServers]) {
        [PseudoTerminalRestorer setRestorationCompletionBlock:^{
            [[iTermOrphanServerAdopter sharedInstance] openWindowWithOrphans];
        }];
    }
}

- (void)workspaceSessionDidBecomeActive:(NSNotification *)notification {
    _workspaceSessionActive = YES;
}

- (void)workspaceSessionDidResignActive:(NSNotification *)notification {
    _workspaceSessionActive = NO;
}

- (void)sparkleWillRestartApp:(NSNotification *)notification {
    _sparkleRestarting = YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSNotification *)theNotification {
    DLog(@"applicationShouldTerminate:");
    NSArray *terminals;

    terminals = [[iTermController sharedInstance] terminals];
    int numSessions = 0;
    BOOL shouldShowAlert = NO;
    for (PseudoTerminal *term in terminals) {
        numSessions += [[term allSessions] count];
        if ([term promptOnClose]) {
            shouldShowAlert = YES;
        }
    }

    // Display prompt if we need to
    if (!quittingBecauseLastWindowClosed_ &&  // cmd-q
        [terminals count] > 0 &&  // there are terminal windows
        [iTermPreferences boolForKey:kPreferenceKeyPromptOnQuit]) {  // preference is to prompt on quit cmd
        shouldShowAlert = YES;
    }
    quittingBecauseLastWindowClosed_ = NO;
    if ([iTermPreferences boolForKey:kPreferenceKeyConfirmClosingMultipleTabs] && numSessions > 1) {
        // closing multiple sessions
        shouldShowAlert = YES;
    }
    if ([iTermAdvancedSettingsModel runJobsInServers] &&
        self.sparkleRestarting &&
        [iTermAdvancedSettingsModel restoreWindowContents] &&
        [[iTermController sharedInstance] willRestoreWindowsAtNextLaunch]) {
        // Nothing will be lost so just restart without asking.
        shouldShowAlert = NO;
    }

    if (shouldShowAlert) {
        DLog(@"Showing quit alert");
        NSString *message;
        if ([[iTermController sharedInstance] shouldLeaveSessionsRunningOnQuit]) {
            message = @"Sessions will be restored automatically when iTerm2 is relaunched.";
        } else {
            message = @"All sessions will be closed.";
        }
        BOOL stayput = NSRunAlertPanel(@"Quit iTerm2?",
                                       @"%@",
                                       @"OK",
                                       @"Cancel",
                                       nil,
                                       message) != NSAlertDefaultReturn;
        if (stayput) {
            DLog(@"User declined to quit");
            return NSTerminateCancel;
        }
    }

    // Ensure [iTermController dealloc] is called before prefs are saved
    [[HotkeyWindowController sharedInstance] stopEventTap];

    // Prevent sessions from making their termination undoable since we're quitting.
    [[iTermController sharedInstance] setApplicationIsQuitting:YES];

    if ([iTermAdvancedSettingsModel runJobsInServers]) {
        // Restorable sessions must be killed or they'll auto-restore as orphans on the next start.
        // If jobs aren't run in servers, they'll just die normally.
        [[iTermController sharedInstance] killRestorableSessions];
    }

    // This causes all windows to be closed and all sessions to be terminated.
    [iTermController sharedInstanceRelease];

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
    [[HotkeyWindowController sharedInstance] stopEventTap];
         DLog(@"applicationWillTerminate returning");
}

- (PseudoTerminal *)terminalToOpenFileIn
{
    if ([iTermAdvancedSettingsModel openFileInNewWindows]) {
        return nil;
    } else {
        return [self currentTerminal];
    }
}

/**
 * The following applescript invokes this method before
 * _performStartupActivites is run and prevents it from being run. Scripts can
 * use it to launch a command in a predictable way if iTerm2 isn't running (and
 * window arrangements won't be restored, etc.)
 *
 * tell application "iTerm"
 *    open file "/com.googlecode.iterm2/commandmode"
 *    // create a terminal if needed, run commands, whatever.
 * end tell
 */
- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
    if ([filename hasSuffix:@".itermcolors"]) {
        if ([[PreferencePanel sharedInstance] importColorPresetFromFile:filename]) {
            NSRunAlertPanel(@"Colors Scheme Imported", @"The color scheme was imported and added to presets. You can find it under Preferences>Profiles>Colors>Load Presets….", @"OK", nil, nil);
        }
        return YES;
    }
    NSLog(@"Quiet launch");
    quiet_ = YES;
    if ([filename isEqualToString:[ITERM2_FLAG stringByExpandingTildeInPath]]) {
        return YES;
    }
    if (filename) {
        // Verify whether filename is a script or a folder
        BOOL isDir;
        [[NSFileManager defaultManager] fileExistsAtPath:filename isDirectory:&isDir];
        if (!isDir) {
            NSString *aString = [NSString stringWithFormat:@"%@; exit;\n", [filename stringWithEscapedShellCharacters]];
            [[iTermController sharedInstance] launchBookmark:nil inTerminal:[self terminalToOpenFileIn]];
            // Sleeping a while waiting for the login.
            sleep(1);
            [[[[iTermController sharedInstance] currentTerminal] currentSession] insertText:aString];
        } else {
            NSString *aString = [NSString stringWithFormat:@"cd %@\n", [filename stringWithEscapedShellCharacters]];
            [[iTermController sharedInstance] launchBookmark:nil inTerminal:[self terminalToOpenFileIn]];
            // Sleeping a while waiting for the login.
            sleep(1);
            [[[[iTermController sharedInstance] currentTerminal] currentSession] insertText:aString];
        }
    }
    return (YES);
}

- (BOOL)isApplescriptTestApp {
    return [[[NSBundle mainBundle] bundleIdentifier] containsString:@"applescript"];
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)theApplication
{
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

- (void)userDidInteractWithASession
{
    userHasInteractedWithAnySession_ = YES;
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

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag
{
    if ([iTermPreferences boolForKey:kPreferenceKeyHotkeyEnabled] &&
        [iTermPreferences boolForKey:kPreferenceKeyHotKeyTogglesWindow]) {
        // The hotkey window is configured.
        PseudoTerminal* hotkeyTerm = [[HotkeyWindowController sharedInstance] hotKeyWindow];
        if (hotkeyTerm) {
            // Hide the existing window or open it if enabled by preference.
            if ([[hotkeyTerm window] alphaValue] == 1) {
                [[HotkeyWindowController sharedInstance] hideHotKeyWindow:hotkeyTerm];
                return NO;
            } else if ([iTermAdvancedSettingsModel dockIconTogglesWindow]) {
                [[HotkeyWindowController sharedInstance] showHotKeyWindow];
                return NO;
            }
        } else if ([iTermAdvancedSettingsModel dockIconTogglesWindow]) {
            // No existing hotkey window but preference is to toggle it by dock icon so open a new
            // one.
            [[HotkeyWindowController sharedInstance] showHotKeyWindow];
            return NO;
        }
    }
    return YES;
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

- (void)updateScreenParametersInAllTerminals {
    // Make sure that all top-of-screen windows are the proper width.
    for (PseudoTerminal* term in [self terminals]) {
        [term screenParametersDidChange];
    }
}

// init
- (id)init
{
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
        [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
                                                           andSelector:@selector(getUrl:withReplyEvent:)
                                                         forEventClass:kInternetEventClass
                                                            andEventID:kAEGetURL];

        launchTime_ = [[NSDate date] retain];
        _workspaceSessionActive = YES;
    }

    return self;
}

- (void)windowArrangementsDidChange:(id)sender
{
    [self _updateArrangementsMenu:windowArrangements_];
}

- (void)restoreWindowArrangement:(id)sender
{
    [[iTermController sharedInstance] loadWindowArrangementWithName:[sender title]];
}

- (void)awakeFromNib
{
    secureInputDesired_ = [[[NSUserDefaults standardUserDefaults] objectForKey:@"Secure Input"] boolValue];

    NSMenu *appMenu = [NSApp mainMenu];
    NSMenuItem *viewMenuItem = [appMenu itemWithTitle:@"View"];
    NSMenu *viewMenu = [viewMenuItem submenu];

    [viewMenu addItem: [NSMenuItem separatorItem]];
    ColorsMenuItemView *labelTrackView = [[[ColorsMenuItemView alloc]
                                           initWithFrame:NSMakeRect(0, 0, 180, 50)] autorelease];
    NSMenuItem *item;
    item = [[[NSMenuItem alloc] initWithTitle:@"Current Tab Color"
                                       action:@selector(changeTabColorToMenuAction:)
                                keyEquivalent:@""] autorelease];
    [item setView:labelTrackView];
    [viewMenu addItem:item];
}

- (IBAction)openPasswordManager:(id)sender {
    [self openPasswordManagerToAccountName:nil];
}

- (void)openPasswordManagerToAccountName:(NSString *)name {
    PseudoTerminal *term = [[iTermController sharedInstance] currentTerminal];

    if (term) {
        return [term openPasswordManagerToAccountName:name];
    } else {
        if (!_passwordManagerWindowController) {
            _passwordManagerWindowController = [[iTermPasswordManagerWindowController alloc] init];
            _passwordManagerWindowController.delegate = self;
        }
        [[_passwordManagerWindowController window] makeKeyAndOrderFront:nil];
        [_passwordManagerWindowController selectAccountName:name];
    }
}

- (void)genericCloseSheet:(NSWindow *)sheet
               returnCode:(int)returnCode
              contextInfo:(id)contextInfo {
    [sheet close];
    [_passwordManagerWindowController release];
    _passwordManagerWindowController = nil;
}

- (IBAction)toggleToolbeltTool:(NSMenuItem *)menuItem
{
    if ([iTermToolbeltView numberOfVisibleTools] == 1 && [menuItem state] == NSOnState) {
        return;
    }
    [iTermToolbeltView toggleShouldShowTool:[menuItem title]];
}

- (void)toolDidToggle:(NSNotification *)notification
{
    NSString *theName = [notification object];
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        [[term toolbelt] toggleToolWithName:theName];
        [term refreshTools];
    }
    NSMenuItem *menuItem = [toolbeltMenu itemWithTitle:theName];

    NSInteger newState = ([menuItem state] == NSOnState) ? NSOffState : NSOnState;
    [menuItem setState:newState];
}

- (NSDictionary *)dictForQueryString:(NSString *)query
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (NSString *kvp in [query componentsSeparatedByString:@"&"]) {
        NSRange r = [kvp rangeOfString:@"="];
        if (r.location != NSNotFound) {
            [dict setObject:[kvp substringFromIndex:r.location + 1]
                     forKey:[kvp substringToIndex:r.location]];
        } else {
            [dict setObject:@"" forKey:kvp];
        }
    }
    return dict;
}

- (void)getUrl:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent {
    NSString *urlStr = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
    NSURL *url = [NSURL URLWithString: urlStr];
    NSString *scheme = [url scheme];

    Profile *profile = [[iTermURLSchemeController sharedInstance] profileForScheme:scheme];
    if (!profile) {
        profile = [[ProfileModel sharedInstance] defaultBookmark];
    }
    if (profile) {
        PseudoTerminal *term = [[iTermController sharedInstance] currentTerminal];
        [[iTermController sharedInstance] launchBookmark:profile
                                              inTerminal:term
                                                 withURL:urlStr
                                                isHotkey:NO
                                                 makeKey:NO
                                                 command:nil
                                                   block:nil];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_appNapStoppingActivity release];
    [super dealloc];
}

// Action methods
- (IBAction)toggleFullScreenTabBar:(id)sender
{
    [[[iTermController sharedInstance] currentTerminal] toggleFullScreenTabBar];
}

- (BOOL)possiblyTmuxValueForWindow:(BOOL)isWindow {
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
                                                                     actions:@[ tmuxAction, @"Use Default Profile" ]
                                                                   accessory:nil
                                                                  identifier:kPossiblyTmuxIdentifier
                                                                 silenceable:kiTermWarningTypePermanentlySilenceable
                                                                     heading:heading];
        return (selection == kiTermWarningSelection0);
    } else {
        return NO;
    }
}

- (IBAction)newWindow:(id)sender
{
    [[iTermController sharedInstance] newWindow:sender possiblyTmux:[self possiblyTmuxValueForWindow:YES]];
}

- (IBAction)newSessionWithSameProfile:(id)sender
{
    [[iTermController sharedInstance] newSessionWithSameProfile:sender];
}

- (IBAction)newSession:(id)sender
{
    DLog(@"iTermApplicationDelegate newSession:");
    [[iTermController sharedInstance] newSession:sender possiblyTmux:[self possiblyTmuxValueForWindow:NO]];
}

// navigation
- (IBAction)previousTerminal:(id)sender
{
    [[iTermController sharedInstance] previousTerminal:sender];
}

- (IBAction)nextTerminal:(id)sender
{
    [[iTermController sharedInstance] nextTerminal:sender];
}

- (IBAction)arrangeHorizontally:(id)sender
{
    [[iTermController sharedInstance] arrangeHorizontally];
}

- (IBAction)showPrefWindow:(id)sender
{
    [[PreferencePanel sharedInstance] run];
    [[[PreferencePanel sharedInstance] window] makeKeyAndOrderFront:self];
}

- (IBAction)showBookmarkWindow:(id)sender
{
    [[iTermProfilesWindowController sharedInstance] showWindow:sender];
}

- (IBAction)instantReplayPrev:(id)sender
{
    [[iTermController sharedInstance] irAdvance:-1];
}

- (IBAction)instantReplayNext:(id)sender
{
    [[iTermController sharedInstance] irAdvance:1];
}

- (void)newSessionMenu:(NSMenu*)superMenu
                 title:(NSString*)title
                target:(id)aTarget
              selector:(SEL)selector
       openAllSelector:(SEL)openAllSelector
{
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

- (NSMenu*)bookmarksMenu
{
    return bookmarkMenu;
}

- (void)_addArrangementsMenuTo:(NSMenu *)theMenu
{
    NSMenuItem *container = [theMenu addItemWithTitle:@"Restore Arrangement"
                                               action:nil
                                        keyEquivalent:@""];
    NSMenu *subMenu = [[[NSMenu alloc] init] autorelease];
    [container setSubmenu:subMenu];
    [self _updateArrangementsMenu:container];
}

- (NSMenu *)applicationDockMenu:(NSApplication *)sender
{
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

- (void)applicationWillBecomeActive:(NSNotification *)aNotification
{
    DLog(@"******** Become Active");
}

- (void)hideToolTipsInView:(NSView *)aView {
    [aView removeAllToolTips];
    for (NSView *subview in [aView subviews]) {
        [self hideToolTipsInView:subview];
    }
}

- (void)applicationWillHide:(NSNotification *)aNotification
{
    for (NSWindow *aWindow in [[NSApplication sharedApplication] windows]) {
        [self hideToolTipsInView:[aWindow contentView]];
    }
}


// font control
- (IBAction)biggerFont: (id) sender
{
    [[[[iTermController sharedInstance] currentTerminal] currentSession] changeFontSizeDirection:1];
}

- (IBAction)smallerFont: (id) sender
{
    [[[[iTermController sharedInstance] currentTerminal] currentSession] changeFontSizeDirection:-1];
}

- (NSString *)formatBytes:(double)bytes
{
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
              defaultDelay:(float)defaultDelay
{
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
                    term = [controller terminalWithGuid:restorableSession.terminalGuid];
                    if (term) {
                        // Reuse an existing window
                        tab = [term tabWithUniqueId:restorableSession.tabUniqueId];
                        if (tab) {
                            // Add to existing tab by destroying and recreating it.
                            [term recreateTab:tab
                              withArrangement:restorableSession.arrangement
                                     sessions:restorableSession.sessions];
                        } else {
                            // Create a new tab and add the session to it.
                            [restorableSession.sessions[0] revive];
                            [term addRevivedSession:restorableSession.sessions[0]];
                        }
                    } else {
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
                    term = [controller terminalWithGuid:restorableSession.terminalGuid];
                    BOOL fitTermToTabs = NO;
                    if (!term) {
                        // Create a new window
                        term = [[[PseudoTerminal alloc] initWithSmartLayout:YES
                                                                 windowType:WINDOW_TYPE_NORMAL
                                                            savedWindowType:WINDOW_TYPE_NORMAL
                                                                     screen:-1] autorelease];
                        [[iTermController sharedInstance] addTerminalWindow:term];
                        term.terminalGuid = restorableSession.terminalGuid;
                        fitTermToTabs = YES;
                    }
                    // Add a tab to it.
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
                    term = [PseudoTerminal terminalWithArrangement:restorableSession.arrangement
                                                          sessions:restorableSession.sessions];
                    [[iTermController sharedInstance] addTerminalWindow:term];
                    term.terminalGuid = restorableSession.terminalGuid;
                    break;
            }
        }
    }
}

- (IBAction)toggleMultiLinePasteWarning:(id)sender {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setBool:![userDefaults boolForKey:kMultiLinePasteWarningUserDefaultsKey]
                   forKey:kMultiLinePasteWarningUserDefaultsKey];
}

- (int)promptForNumberOfSpacesToConverTabsToWithDefault:(int)defaultValue {
    NSAlert *alert = [NSAlert alertWithMessageText:@"Converting tabs to spaces."
                                     defaultButton:@"Ok"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@"How many spaces for each tab?"];
    NSTextField *input = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 50, 24)] autorelease];
    input.formatter = [[[iTermIntegerNumberFormatter alloc] init] autorelease];
    input.stringValue = [NSString stringWithFormat:@"%d", defaultValue];
    alert.accessoryView = input;
    [alert layout];
    [[alert window] makeFirstResponder:input];
    if ([alert runModal] == NSAlertDefaultReturn) {
        NSInteger n = [input integerValue];
        if (n > 0) {
            return n;
        }
    }
    return -1;
}

- (BOOL)warnBeforeMultiLinePaste {
    if ([iTermWarning warningHandler]) {
        // In a test.
        return YES;
    }
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    return ![userDefaults boolForKey:kMultiLinePasteWarningUserDefaultsKey];
}

- (IBAction)maximizePane:(id)sender
{
    [[[iTermController sharedInstance] currentTerminal] toggleMaximizeActivePane];
    [self updateMaximizePaneMenuItem];
}

- (IBAction)toggleUseTransparency:(id)sender
{
    [[[iTermController sharedInstance] currentTerminal] toggleUseTransparency:sender];
    [self updateUseTransparencyMenuItem];
}

- (IBAction)toggleSecureInput:(id)sender
{
    // Set secureInputDesired_ to the opposite of the current state.
    secureInputDesired_ = [secureInput state] == NSOffState;

    // Try to set the system's state of secure input to the desired state.
    if (secureInputDesired_) {
        if (EnableSecureEventInput() != noErr) {
            NSLog(@"Failed to enable secure input.");
        }
    } else {
        if (DisableSecureEventInput() != noErr) {
            NSLog(@"Failed to disable secure input.");
        }
    }

    // Set the state of the control to the new true state.
    [secureInput setState:(secureInputDesired_ && IsSecureEventInputEnabled()) ? NSOnState : NSOffState];

    // Save the preference, independent of whether it succeeded or not.
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:secureInputDesired_]
                                              forKey:@"Secure Input"];
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification
{
    hasBecomeActive = YES;
    if (secureInputDesired_) {
        if (EnableSecureEventInput() != noErr) {
            NSLog(@"Failed to enable secure input.");
        }
    }
    // Set the state of the control to the new true state.
    [secureInput setState:(secureInputDesired_ && IsSecureEventInputEnabled()) ? NSOnState : NSOffState];
}

- (void)applicationDidResignActive:(NSNotification *)aNotification
{
    if (secureInputDesired_) {
        if (DisableSecureEventInput() != noErr) {
            NSLog(@"Failed to disable secure input.");
        }
    }
    // Set the state of the control to the new true state.
    [secureInput setState:(secureInputDesired_ && IsSecureEventInputEnabled()) ? NSOnState : NSOffState];
}

- (void)application:(NSApplication *)app willEncodeRestorableState:(NSCoder *)coder {
    DLog(@"app encoding restorable state");
    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
    [coder encodeObject:ScreenCharEncodedRestorableState() forKey:kScreenCharRestorableStateKey];

    [[HotkeyWindowController sharedInstance] saveHotkeyWindowState];
    NSDictionary *hotkeyWindowState = [[HotkeyWindowController sharedInstance] restorableState];
    if (hotkeyWindowState) {
        [coder encodeObject:hotkeyWindowState
                     forKey:kHotkeyWindowRestorableState];
    }
    NSLog(@"Time to save app restorable state: %@",
          @([NSDate timeIntervalSinceReferenceDate] - start));
}

- (void)application:(NSApplication *)app didDecodeRestorableState:(NSCoder *)coder {
    NSDictionary *screenCharState = [coder decodeObjectForKey:kScreenCharRestorableStateKey];
    if (screenCharState) {
        ScreenCharDecodeRestorableState(screenCharState);
    }

    NSDictionary *hotkeyWindowState = [coder decodeObjectForKey:kHotkeyWindowRestorableState];
    if (hotkeyWindowState &&
        [[NSUserDefaults standardUserDefaults] boolForKey:@"NSQuitAlwaysKeepsWindows"]) {
        [[HotkeyWindowController sharedInstance] setRestorableState:hotkeyWindowState];

        // We have to create the hotkey window now because we need to attach to servers before
        // launch finishes; otherwise any running hotkey window jobs will be treated as orphans.
        [[HotkeyWindowController sharedInstance] createHiddenHotkeyWindow];
    }
}

// Debug logging
- (IBAction)debugLogging:(id)sender {
  ToggleDebugLogging();
}

- (IBAction)openQuickly:(id)sender {
    [[iTermOpenQuicklyWindowController sharedInstance] presentWindow];
}

// About window

- (IBAction)showAbout:(id)sender {
    [[iTermAboutWindowController sharedInstance] showWindow:self];
}

// size
- (IBAction)returnToDefaultSize:(id)sender
{
    PseudoTerminal *frontTerminal = [[iTermController sharedInstance] currentTerminal];
    PTYSession *session = [frontTerminal currentSession];
    [session changeFontSizeDirection:0];
    if ([sender isAlternate]) {
        NSDictionary *abEntry = [session originalProfile];
        [frontTerminal sessionInitiatedResize:session
                                        width:[[abEntry objectForKey:KEY_COLUMNS] intValue]
                                       height:[[abEntry objectForKey:KEY_ROWS] intValue]];
    }
}

- (IBAction)exposeForTabs:(id)sender
{
    [iTermExpose toggle];
}

// Notifications
- (void)reloadMenus:(NSNotification *)aNotification
{
    PseudoTerminal *frontTerminal = [self currentTerminal];
    if (frontTerminal != [aNotification object]) {
        return;
    }
    [previousTerminal setAction: (frontTerminal ? @selector(previousTerminal:) : nil)];
    [nextTerminal setAction: (frontTerminal ? @selector(nextTerminal:) : nil)];

    [self buildSessionSubmenu: aNotification];
    // reset the close tab/window shortcuts
    [closeTab setAction:@selector(closeCurrentTab:)];
    [closeTab setTarget:frontTerminal];
    [closeTab setKeyEquivalent:@"w"];
    [closeWindow setKeyEquivalent:@"W"];
    [closeWindow setKeyEquivalentModifierMask: NSCommandKeyMask];


    // set some menu item states
    if (frontTerminal && [[frontTerminal tabView] numberOfTabViewItems]) {
        [toggleBookmarksView setEnabled:YES];
    } else {
        [toggleBookmarksView setEnabled:NO];
    }
}

- (void)updateBroadcastMenuState
{
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

- (void) nonTerminalWindowBecameKey: (NSNotification *) aNotification {
    [closeTab setAction:nil];
    [closeTab setKeyEquivalent:@""];
    [closeWindow setKeyEquivalent:@"w"];
    [closeWindow setKeyEquivalentModifierMask:NSCommandKeyMask];
}

- (void)buildSessionSubmenu:(NSNotification *)aNotification
{
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
    NSEnumerator *enumerator = [tabViewItemArray objectEnumerator];
    NSTabViewItem *aTabViewItem;
    int i=1;

    // clear whatever menu we already have
    [selectTab setSubmenu: nil];

    while ((aTabViewItem = [enumerator nextObject])) {
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

- (void)_removeItemsFromMenu:(NSMenu*)menu
{
    while ([menu numberOfItems] > 0) {
        NSMenuItem* item = [menu itemAtIndex:0];
        NSMenu* sub = [item submenu];
        if (sub) {
            [self _removeItemsFromMenu:sub];
        }
        [menu removeItemAtIndex:0];
    }
}

- (void)updateAddressBookMenu:(NSNotification*)aNotification
{
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

- (NSMenu *)downloadsMenu
{
    if (!downloadsMenu_) {
        downloadsMenu_ = [[[NSMenuItem alloc] init] autorelease];
        downloadsMenu_.title = @"Downloads";
        NSMenu *mainMenu = [[NSApplication sharedApplication] mainMenu];
        [mainMenu insertItem:downloadsMenu_
                     atIndex:mainMenu.itemArray.count - 1];
        [downloadsMenu_ setSubmenu:[[[NSMenu alloc] initWithTitle:@"Downloads"] autorelease]];
    }
    return [downloadsMenu_ submenu];
}

- (NSMenu *)uploadsMenu
{
    if (!uploadsMenu_) {
        uploadsMenu_ = [[[NSMenuItem alloc] init] autorelease];
        uploadsMenu_.title = @"Uploads";
        NSMenu *mainMenu = [[NSApplication sharedApplication] mainMenu];
        [mainMenu insertItem:uploadsMenu_
                     atIndex:mainMenu.itemArray.count - 1];
        [uploadsMenu_ setSubmenu:[[[NSMenu alloc] initWithTitle:@"Uploads"] autorelease]];
    }
    return [uploadsMenu_ submenu];
}

// This is called whenever a tab becomes key or logging starts/stops.
- (void)reloadSessionMenus:(NSNotification *)aNotification
{
    [self updateMaximizePaneMenuItem];

    PseudoTerminal *currentTerminal = [self currentTerminal];
    PTYSession* aSession = [aNotification object];

    if (currentTerminal != [[aSession tab] parentWindow] ||
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

- (void)makeHotKeyWindowKeyIfOpen
{
    for (PseudoTerminal* term in [self terminals]) {
        if ([term isHotKeyWindow] && [[term window] alphaValue] == 1) {
            [[term window] makeKeyAndOrderFront:self];
        }
    }
}

- (void)updateMaximizePaneMenuItem
{
    [maximizePane setState:[[[[iTermController sharedInstance] currentTerminal] currentTab] hasMaximizedPane] ? NSOnState : NSOffState];
}

- (void)updateUseTransparencyMenuItem
{
    [useTransparency setState:[[[iTermController sharedInstance] currentTerminal] useTransparency] ? NSOnState : NSOffState];
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

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    if ([menuItem action] == @selector(toggleUseBackgroundPatternIndicator:)) {
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
        return ![self isDefaultTerminal];
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
        PseudoTerminal *term = [[iTermController sharedInstance] currentTerminal];
        if (!term || ![term anyFullScreen]) {
            return NO;
        } else {
            [menuItem setState:[term fullScreenTabControl] ? NSOnState : NSOffState];
            return YES;
        }
    } else if ([menuItem action] == @selector(toggleMultiLinePasteWarning:)) {
        menuItem.state = [self warnBeforeMultiLinePaste] ? NSOnState : NSOffState;
        return YES;
    } else {
        return YES;
    }
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
    NSDirectoryEnumerator *directoryEnumerator =
        [[NSFileManager defaultManager] enumeratorAtPath:[SCRIPT_DIRECTORY stringByExpandingTildeInPath]];
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    for (NSString *file in directoryEnumerator) {
        NSString *path = [[SCRIPT_DIRECTORY stringByExpandingTildeInPath] stringByAppendingPathComponent:file];
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

- (IBAction)saveWindowArrangement:(id)sender
{
    [[iTermController sharedInstance] saveWindowArrangement:YES];
}

- (IBAction)saveCurrentWindowAsArrangement:(id)sender
{
    [[iTermController sharedInstance] saveWindowArrangement:NO];
}

// TODO(georgen): Disable "Edit Current Session..." when there are no current sessions.
- (IBAction)editCurrentSession:(id)sender
{
    PseudoTerminal* pty = [[iTermController sharedInstance] currentTerminal];
    if (!pty) {
        return;
    }
    [pty editCurrentSession:sender];
}

- (BOOL)useBackgroundPatternIndicator
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:kUseBackgroundPatternIndicatorKey];
}

- (IBAction)toggleUseBackgroundPatternIndicator:(id)sender
{
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

- (NSString *)markAlertAction {
    NSString *action = [[NSUserDefaults standardUserDefaults] objectForKey:kMarkAlertAction];
    if (!action) {
        return kMarkAlertActionPostNotification;
    } else {
        return action;
    }
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
}

- (PseudoTerminal *)currentTerminal {
    return [[iTermController sharedInstance] currentTerminal];
}

- (NSArray*)terminals {
    return [[iTermController sharedInstance] terminals];
}

@end

@implementation iTermApplicationDelegate (MoreActions)

- (void)newSessionInWindowAtIndex: (id) sender
{
    [[iTermController sharedInstance] newSessionInWindowAtIndex:sender];
}

@end
