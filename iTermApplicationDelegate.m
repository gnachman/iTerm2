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
#import "iTermController.h"
#import "ITAddressBookMgr.h"
#import "PreferencePanel.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "VT100Terminal.h"
#import "PTYWindow.h"
#import "PTYTextView.h"
#import "NSStringITerm.h"
#import "ProfilesWindow.h"
#import "PTYTab.h"
#import "iTermExpose.h"
#import "ColorsMenuItemView.h"
#import "iTermFontPanel.h"
#import "PseudoTerminalRestorer.h"
#import "ToastWindowController.h"
#include <unistd.h>
#include <sys/stat.h>

static NSString *APP_SUPPORT_DIR = @"~/Library/Application Support/iTerm";
static NSString *SCRIPT_DIRECTORY = @"~/Library/Application Support/iTerm/Scripts";
static NSString* AUTO_LAUNCH_SCRIPT = @"~/Library/Application Support/iTerm/AutoLaunch.scpt";
static NSString *ITERM2_FLAG = @"~/Library/Application Support/iTerm/version.txt";
static NSString *ITERM2_QUIET = @"~/Library/Application Support/iTerm/quiet";
static NSString *kUseBackgroundPatternIndicatorKey = @"Use background pattern indicator";
NSString *kUseBackgroundPatternIndicatorChangedNotification = @"kUseBackgroundPatternIndicatorChangedNotification";
static BOOL gStartupActivitiesPerformed = NO;
// Prior to 8/7/11, there was only one window arrangement, always called Default.
static NSString *LEGACY_DEFAULT_ARRANGEMENT_NAME = @"Default";
NSMutableString* gDebugLogStr = nil;
NSMutableString* gDebugLogStr2 = nil;
static BOOL ranAutoLaunchScript = NO;
BOOL gDebugLogging = NO;
int gDebugLogFile = -1;
static BOOL hasBecomeActive = NO;

@interface iTermApplicationDelegate ()

- (void)_updateToolbeltMenuItem;

@end

@implementation iTermAboutWindow

- (IBAction)closeCurrentSession:(id)sender
{
    [self close];
}

@end


@implementation iTermApplicationDelegate

// NSApplication delegate methods
- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
    // Check the system version for minimum requirements.
    SInt32 gSystemVersion;
    Gestalt(gestaltSystemVersion, &gSystemVersion);
    if (gSystemVersion < 0x1050) {
        NSRunAlertPanel(@"Sorry", @"iTerm2 requires OS 10.5 or newer.", @"OK", nil, nil);
        [NSApp terminate: self];
    }

    // set the TERM_PROGRAM environment variable
    putenv("TERM_PROGRAM=iTerm.app");

    [self buildScriptMenu:nil];

    // read preferences
    [PreferencePanel migratePreferences];
    [PreferencePanel sharedInstance];
    [ITAddressBookMgr sharedInstance];

    [ToolbeltView populateMenu:toolbeltMenu];
    [self _updateToolbeltMenuItem];
    [self setFutureApplicationPresentationOptions:NSApplicationPresentationFullScreen unset:0];
}

- (void)setFutureApplicationPresentationOptions:(int)flags unset:(int)antiflags
{
    if ([NSApp respondsToSelector:@selector(presentationOptions)]) {
        // This crazy hackery is done so that we can use 10.6 and 10.7 features
        // while compiling against the 10.5 SDK.

        // presentationOptions =  [NSApp presentationOptions]
        NSMethodSignature *presentationOptionsSignature = [NSApp->isa
            instanceMethodSignatureForSelector:@selector(presentationOptions)];
        NSInvocation *presentationOptionsInvocation = [NSInvocation
            invocationWithMethodSignature:presentationOptionsSignature];
        [presentationOptionsInvocation setTarget:NSApp];
        [presentationOptionsInvocation setSelector:@selector(presentationOptions)];
        [presentationOptionsInvocation invoke];

        NSUInteger presentationOptions;
        [presentationOptionsInvocation getReturnValue:&presentationOptions];

        presentationOptions |= flags;
        presentationOptions &= ~antiflags;

        // [NSAppObj setPresentationOptions:presentationOptions];
        NSMethodSignature *setSig = [NSApp->isa instanceMethodSignatureForSelector:@selector(setPresentationOptions:)];
        NSInvocation *setInv = [NSInvocation invocationWithMethodSignature:setSig];
        [setInv setTarget:NSApp];
        [setInv setSelector:@selector(setPresentationOptions:)];
        [setInv setArgument:&presentationOptions atIndex:2];
        [setInv invoke];
    } else {
        // Emulate setPresentationOptions API for OS 10.5.
        if (flags & NSApplicationPresentationAutoHideMenuBar) {
            SetSystemUIMode(kUIModeAllHidden, kUIOptionAutoShowMenuBar);
        } else if (antiflags & NSApplicationPresentationAutoHideMenuBar) {
            SetSystemUIMode(kUIModeNormal, 0);
        }

    }
}

- (void)_performIdempotentStartupActivities
{
    gStartupActivitiesPerformed = YES;
    if (quiet_) {
        // iTerm2 was launched with "open file" that turns off startup activities.
        return;
    }
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

        if ([[PreferencePanel sharedInstance] openBookmark]) {
            // Open bookmarks window at startup.
            [self showBookmarkWindow:nil];
            if ([[PreferencePanel sharedInstance] openArrangementAtStartup]) {
                // Open both bookmark window and arrangement!
                [[iTermController sharedInstance] loadWindowArrangementWithName:[WindowArrangements defaultArrangementName]];
            }
        } else if ([[PreferencePanel sharedInstance] openArrangementAtStartup]) {
            // Open the saved arrangement at startup.
            [[iTermController sharedInstance] loadWindowArrangementWithName:[WindowArrangements defaultArrangementName]];
        } else {
            if (![PseudoTerminalRestorer willOpenWindows]) {
                if ([[[iTermController sharedInstance] terminals] count] == 0) {
                    [self newWindow:nil];
                }
            }
        }
    }
    ranAutoLaunchScript = YES;
}

// This performs startup activities as long as they haven't been run before.
- (void)_performStartupActivities
{
    if (gStartupActivitiesPerformed) {
        return;
    }
    [self _performIdempotentStartupActivities];
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

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
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

    PreferencePanel* ppanel = [PreferencePanel sharedInstance];
    if ([ppanel hotkey]) {
        [[iTermController sharedInstance] registerHotkey:[ppanel hotkeyCode] modifiers:[ppanel hotkeyModifiers]];
    }
    if ([ppanel isAnyModifierRemapped]) {
        [[iTermController sharedInstance] beginRemappingModifiers];
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
}

- (BOOL)applicationShouldTerminate:(NSNotification *)theNotification
{
    NSArray *terminals;

    terminals = [[iTermController sharedInstance] terminals];
    int numSessions = 0;
    BOOL shouldShowAlert = NO;
    for (PseudoTerminal *term in terminals) {
        numSessions += [[term sessions] count];
        if ([term promptOnClose]) {
            shouldShowAlert = YES;
        }
    }

    // Display prompt if we need to
    if (!quittingBecauseLastWindowClosed_ &&  // cmd-q
        [terminals count] > 0 &&  // there are terminal windows
        [[PreferencePanel sharedInstance] promptOnQuit]) {  // preference is to prompt on quit cmd
        shouldShowAlert = YES;
    }
    quittingBecauseLastWindowClosed_ = NO;
    if ([[PreferencePanel sharedInstance] onlyWhenMoreTabs] && numSessions > 1) {
        // closing multiple sessions
        shouldShowAlert = YES;
    }
    
    if (shouldShowAlert) {
        BOOL stayput = NSRunAlertPanel(@"Quit iTerm2?",
                                       @"All sessions will be closed.",
                                       @"OK",
                                       @"Cancel",
                                       nil) != NSAlertDefaultReturn;
        if (stayput) {
            return NO;
        }
    }

    // Ensure [iTermController dealloc] is called before prefs are saved
    [[iTermController sharedInstance] stopEventTap];
    [iTermController sharedInstanceRelease];

    // save preferences
    [[PreferencePanel sharedInstance] savePreferences];
    if (![[PreferencePanel sharedInstance] customFolderChanged]) {
        if ([[PreferencePanel sharedInstance] prefsDifferFromRemote]) {
            NSString *remote = [[PreferencePanel sharedInstance] remotePrefsLocation];
            if ([remote hasPrefix:@"http://"] ||
                [remote hasPrefix:@"https://"]) {
                // If the setting is always copy, then ask. Copying isn't an option.
                if (![[NSUserDefaults standardUserDefaults] objectForKey:@"NoSyncNeverRemindPrefsChangesLost"]) {
                    if (NSRunAlertPanel(@"Preference Changes Will be Lost!",
                                        [NSString stringWithFormat:@"Your preferences are loaded from a URL and differ from your local preferences. To save your local preferences, copy ~/Library/Preferences/com.googlecode.iterm2.plist to %@ after quitting iTerm2.", remote],
                                        @"OK",
                                        @"Never Remind Me Again",
                                        nil) == NSAlertAlternateReturn) {
                        [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:YES]
                                                                  forKey:@"NoSyncNeverRemindPrefsChangesLost"];
                    }
                }
            } else {
                // Not a URL
                NSString *format;
                if ([ProfileModel migrated]) {
                    format = @"Your preferences were modified by iTerm2 as part of an upgrade process (and you might have changed them, too). "
                    @"Since you load prefs from a custom location, your local preferences will be lost if not copied to %@.";
                } else {
                    format = @"Your preferences are loaded from a custom location and differ from your local preferences."
                    @"Your local preferences will be lost if not copied to %@.";
                }
                if ([[NSUserDefaults standardUserDefaults] objectForKey:@"NoSyncNeverRemindPrefsChangesCopy"]) {
                    // Always copy
                    [[PreferencePanel sharedInstance] pushToCustomFolder:nil];
                } else if (![[NSUserDefaults standardUserDefaults] objectForKey:@"NoSyncNeverRemindPrefsChangesLost"]) {
                    // No "always" action.
                    NSAlert *alert;
                    alert = [NSAlert alertWithMessageText:@"Preference Changes Will be Lost!"
                                            defaultButton:@"Copy"
                                          alternateButton:@"Lose Changes"
                                              otherButton:nil
                                informativeTextWithFormat:format, remote];
                    [alert setShowsSuppressionButton:YES];
                    [[alert suppressionButton] setTitle:@"Always use this option."];
                    BOOL doCopy = NO;
                    switch ([alert runModal]) {
                        case NSAlertDefaultReturn:
                            doCopy = YES;
                            break;

                        case NSAlertAlternateReturn:
                            break;
                    }
                    if ([[alert suppressionButton] state] == NSOnState) {
                            [[NSUserDefaults standardUserDefaults]
                                setObject:[NSNumber numberWithBool:YES]
                                   forKey:doCopy ? @"NoSyncNeverRemindPrefsChangesCopy" :
                                                   @"NoSyncNeverRemindPrefsChangesLost"];
                    }
                    if (doCopy) {
                        [[PreferencePanel sharedInstance] pushToCustomFolder:nil];
                    }
                }
            }
        }
    }

    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    [[iTermController sharedInstance] stopEventTap];
}

- (PseudoTerminal *)terminalToOpenFileIn
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"OpenFileInNewWindows"]) {
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

- (BOOL)applicationOpenUntitledFile:(NSApplication *)theApplication
{
    if (!finishedLaunching_ &&
        [[PreferencePanel sharedInstance] openArrangementAtStartup]) {
        // This happens if the OS is pre 10.7 or restore windows is off in
        // 10.7's prefs->general, and the window arrangement has no windows,
        // and it's set to load the arrangement on startup.
        return NO;
    }
    [self newWindow:nil];
    return YES;
}

- (void)userDidInteractWithASession
{
    userHasInteractedWithAnySession_ = YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
    if (!userHasInteractedWithAnySession_) {
        NSNumber* pref = [[NSUserDefaults standardUserDefaults] objectForKey:@"MinRunningTime"];
        const double kMinRunningTime =  pref ? [pref floatValue] : 10;
        if ([[NSDate date] timeIntervalSinceDate:launchTime_] < kMinRunningTime) {
            NSLog(@"Not quitting iTerm2 because it ran very briefly and had no user interaction. Set the MinRunningTime float preference to 0 to turn this feature off.");
            return NO;
        }
    }
    quittingBecauseLastWindowClosed_ = [[PreferencePanel sharedInstance] quitWhenAllWindowsClosed];
    return quittingBecauseLastWindowClosed_;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag
{
    PreferencePanel* prefPanel = [PreferencePanel sharedInstance];
    if ([prefPanel hotkey] &&
        [prefPanel hotkeyTogglesWindow]) {
        // The hotkey window is configured.
        PseudoTerminal* hotkeyTerm = [[iTermController sharedInstance] hotKeyWindow];
        if (hotkeyTerm) {
            // Hide the existing window or open it if enabled by preference.
            if ([[hotkeyTerm window] alphaValue] == 1) {
                [[iTermController sharedInstance] hideHotKeyWindow:hotkeyTerm];
                return NO;
            } else if ([prefPanel dockIconTogglesWindow]) {
                [[iTermController sharedInstance] showHotKeyWindow];
                return NO;
            }
        } else if ([prefPanel dockIconTogglesWindow]) {
            // No existing hotkey window but preference is to toggle it by dock icon so open a new
            // one.
            [[iTermController sharedInstance] showHotKeyWindow];
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
    NSNumber *delay = [[NSUserDefaults standardUserDefaults] objectForKey:@"UpdateScreenParamsDelay"];
    if (!delay) {
        delay = [NSNumber numberWithInt:1];
    }
    [self performSelector:@selector(updateScreenParametersInAllTerminals)
               withObject:nil
               afterDelay:[delay intValue]];
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

    // Add ourselves as an observer for notifications.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadMenus:)
                                                 name:@"iTermWindowBecameKey"
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(updateAddressBookMenu:)
                                                 name: @"iTermReloadAddressBook"
                                               object: nil];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(buildSessionSubmenu:)
                                                 name: @"iTermNumberOfSessionsDidChange"
                                               object: nil];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(buildSessionSubmenu:)
                                                 name: @"iTermNameOfSessionDidChange"
                                               object: nil];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(reloadSessionMenus:)
                                                 name: @"iTermSessionBecameKey"
                                               object: nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(nonTerminalWindowBecameKey:)
                                                 name:@"nonTerminalWindowBecameKey"
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowArrangementsDidChange:)
                                                 name:@"iTermSavedArrangementChanged"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(toolDidToggle:)
                                                 name:@"iTermToolToggled"
                                               object:nil];

    [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
                                                       andSelector:@selector(getUrl:withReplyEvent:)
                                                     forEventClass:kInternetEventClass
                                                        andEventID:kAEGetURL];

    aboutController = nil;
    launchTime_ = [[NSDate date] retain];

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

- (BOOL)showToolbelt
{
    NSNumber *n = [[NSUserDefaults standardUserDefaults] objectForKey:@"Show Toolbelt"];
    if (!n) {
        n = [NSNumber numberWithBool:NO];
    }
    return [n boolValue];
}

- (IBAction)toggleToolbelt:(id)sender
{
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:![self showToolbelt]]
                                                                       forKey:@"Show Toolbelt"];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermToolbeltVisibilityChanged"
                                                        object:nil];
    [self _updateToolbeltMenuItem];
}

- (void)_updateToolbeltMenuItem
{
    [showToolbeltItem setState:[self showToolbelt] ? NSOnState : NSOffState];
}

- (IBAction)toggleToolbeltTool:(NSMenuItem *)menuItem
{
    if ([ToolbeltView numberOfVisibleTools] == 1 && [menuItem state] == NSOnState) {
        return;
    }
    [ToolbeltView toggleShouldShowTool:[menuItem title]];
}

- (void)toolDidToggle:(NSNotification *)notification
{
    NSString *theName = [notification object];
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        [[term toolbelt] toggleToolWithName:theName];
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

- (void)launchFromUrl:(NSURL *)url
{
    NSString *queryString = [url query];
    NSDictionary *query = [self dictForQueryString:queryString];

    if (![[query objectForKey:@"token"] isEqualToString:token_]) {
        NSLog(@"URL request %@ missing token", url);
        return;
    }
    [token_ release];
    token_ = nil;
    if ([query objectForKey:@"quiet"]) {
        quiet_ = YES;
    }
    PseudoTerminal *term = nil;
    BOOL doLaunch = YES;
    BOOL launchIfNeeded = NO;
    if ([[url host] isEqualToString:@"newtab"]) {
        term = [[iTermController sharedInstance] currentTerminal];
    } else if ([[url host] isEqualToString:@"newwindow"]) {
        term = nil;
    } else if ([[url host] isEqualToString:@"current"]) {
        doLaunch = NO;
    } else if ([[url host] isEqualToString:@"tryCurrent"]) {
        doLaunch = NO;
        launchIfNeeded = YES;
    } else {
        NSLog(@"Bad host: %@", [url host]);
        return;
    }
    Profile *profile = nil;
    if ([query objectForKey:@"profile"]) {
        NSString *bookmarkName = [[query objectForKey:@"profile"] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        profile = [[ProfileModel sharedInstance] bookmarkWithName:bookmarkName];
    }
    PTYSession *aSession;
    if (!doLaunch) {
        aSession = [[[iTermController sharedInstance] currentTerminal] currentSession];
    }
    if (doLaunch || (!aSession && launchIfNeeded)) {
        aSession = [[iTermController sharedInstance] launchBookmark:profile
                                                         inTerminal:term];
    }
    if ([query objectForKey:@"command"]) {
        NSData *theData;
        NSStringEncoding encoding = [[aSession TERMINAL] encoding];
        theData = [[[query objectForKey:@"command"] stringByReplacingPercentEscapesUsingEncoding:encoding] dataUsingEncoding:encoding];
        [aSession writeTask:theData];
        [aSession writeTask:[@"\r" dataUsingEncoding:encoding]];
    }
}

- (void)getUrl:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
    NSString *urlStr = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
    NSURL *url = [NSURL URLWithString: urlStr];
    NSString *urlType = [url scheme];

    if ([urlType isEqualToString:@"iterm2"]) {
        [self launchFromUrl:url];
        return;
    }
    id bm = [[PreferencePanel sharedInstance] handlerBookmarkForURL:urlType];
    if (!bm) {
        bm = [[ProfileModel sharedInstance] defaultBookmark];
    }
    if (bm) {
        PseudoTerminal *term = [[iTermController sharedInstance] currentTerminal];
        [[iTermController sharedInstance] launchBookmark:bm
                                              inTerminal:term
                                                 withURL:urlStr
                                           forObjectType:term ? iTermTabObject : iTermWindowObject];
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [super dealloc];
}

// Action methods
- (IBAction)toggleFullScreenTabBar:(id)sender
{
    [[[iTermController sharedInstance] currentTerminal] toggleFullScreenTabBar];
}

- (IBAction)newWindow:(id)sender
{
    [[iTermController sharedInstance] newWindow:sender possiblyTmux:YES];
}

- (IBAction)newSessionWithSameProfile:(id)sender
{
    [[iTermController sharedInstance] newSessionWithSameProfile:sender];
}

- (IBAction)newSession:(id)sender
{
    DLog(@"iTermApplicationDelegate newSession:");
    [[iTermController sharedInstance] newSession:sender possiblyTmux:YES];
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
}

- (IBAction)showBookmarkWindow:(id)sender
{
    [[ProfilesWindow sharedInstance] showWindow:sender];
}

- (IBAction)instantReplayPrev:(id)sender
{
    [[iTermController sharedInstance] irAdvance:-1];
}

- (IBAction)instantReplayNext:(id)sender
{
    [[iTermController sharedInstance] irAdvance:1];
}

- (void)_newSessionMenu:(NSMenu*)superMenu title:(NSString*)title target:(id)aTarget selector:(SEL)selector openAllSelector:(SEL)openAllSelector
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
    [self _newSessionMenu:aMenu
                    title:@"New Window…"
                   target:[iTermController sharedInstance]
                 selector:@selector(newSessionInWindowAtIndex:)
          openAllSelector:@selector(newSessionsInNewWindow:)];
    [self _newSessionMenu:aMenu
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
    for (PseudoTerminal* term in [self terminals]) {
        if ([term isHotKeyWindow]) {
            //NSLog(@"Visor is open; not rescuing orphans.");
            return;
        }
    }
    for (PseudoTerminal* term in [self terminals]) {
        if ([term isOrderedOut]) {
            //NSLog(@"term %p was orphaned, order front.", term);
            [[term window] orderFront:nil];
        }
    }
}

// font control
- (IBAction) biggerFont: (id) sender
{
    [[[[iTermController sharedInstance] currentTerminal] currentSession] changeFontSizeDirection:1];
}

- (IBAction) smallerFont: (id) sender
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

static void SwapDebugLog() {
        NSMutableString* temp;
        temp = gDebugLogStr;
        gDebugLogStr = gDebugLogStr2;
        gDebugLogStr2 = temp;
}

static void FlushDebugLog() {
        NSData* data = [gDebugLogStr dataUsingEncoding:NSUTF8StringEncoding];
        int written = write(gDebugLogFile, [data bytes], [data length]);
        assert(written == [data length]);
        [gDebugLogStr setString:@""];
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

// Debug logging
-(IBAction)debugLogging:(id)sender
{
    if (!gDebugLogging) {
        NSRunAlertPanel(@"Debug Logging Enabled",
                        @"Writing to /tmp/debuglog.txt",
                        @"OK", nil, nil);
        gDebugLogFile = open("/tmp/debuglog.txt", O_TRUNC | O_CREAT | O_WRONLY, S_IRUSR | S_IWUSR);
        gDebugLogStr = [[NSMutableString alloc] init];
        gDebugLogStr2 = [[NSMutableString alloc] init];
        gDebugLogging = !gDebugLogging;
    } else {
        gDebugLogging = !gDebugLogging;
        SwapDebugLog();
        FlushDebugLog();
        SwapDebugLog();
        FlushDebugLog();
        
        close(gDebugLogFile);
        gDebugLogFile=-1;
        NSRunAlertPanel(@"Debug Logging Stopped",
                        @"Please compress and send /tmp/debuglog.txt to the developers.",
                        @"OK", nil, nil);
        [gDebugLogStr release];
        [gDebugLogStr2 release];
    }
}

int DebugLogImpl(const char *file, int line, const char *function, NSString* value)
{
    if (gDebugLogging) {
        struct timeval tv;
        gettimeofday(&tv, NULL);

        [gDebugLogStr appendFormat:@"%ld.%08ld %s:%d (%s): ", (long long)tv.tv_sec, (long long)tv.tv_usec, file, line, function];
        [gDebugLogStr appendString:value];
        [gDebugLogStr appendString:@"\n"];
        if ([gDebugLogStr length] > 100000000) {
            SwapDebugLog();
            [gDebugLogStr2 setString:@""];
        }
    }
    return 1;
}

/// About window

- (NSAttributedString *)_linkTo:(NSString *)urlString title:(NSString *)title
{
    NSDictionary *linkAttributes = [NSDictionary dictionaryWithObject:[NSURL URLWithString:urlString]
                                                               forKey:NSLinkAttributeName];
    NSString *localizedTitle = NSLocalizedStringFromTableInBundle(title, @"iTerm",
                                                                  [NSBundle bundleForClass:[self class]],
                                                                  @"About");

    NSAttributedString *string = [[NSAttributedString alloc] initWithString:localizedTitle
                                                                 attributes:linkAttributes];
    return [string autorelease];
}

- (IBAction)showAbout:(id)sender
{
    // check if an About window is shown already
    if (aboutController) {
        [aboutController showWindow:self];
        return;
    }

    NSDictionary *myDict = [[NSBundle bundleForClass:[self class]] infoDictionary];
    NSString *versionString = [NSString stringWithFormat: @"Build %@\n\n", [myDict objectForKey:@"CFBundleVersion"]];

    NSAttributedString *webAString = [self _linkTo:@"http://iterm2.com/" title:@"Home Page\n"];
    NSAttributedString *bugsAString = [self _linkTo:@"http://code.google.com/p/iterm2/issues/entry" title:@"Report a bug\n\n"];
    NSAttributedString *creditsAString = [self _linkTo:@"http://code.google.com/p/iterm2/wiki/Credits" title:@"Credits"];

    NSDictionary *linkTextViewAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt: NSSingleUnderlineStyle], NSUnderlineStyleAttributeName,
        [NSColor blueColor], NSForegroundColorAttributeName,
        [NSCursor pointingHandCursor], NSCursorAttributeName,
        NULL];

    [AUTHORS setLinkTextAttributes: linkTextViewAttributes];
    [[AUTHORS textStorage] deleteCharactersInRange: NSMakeRange(0, [[AUTHORS textStorage] length])];
    [[AUTHORS textStorage] appendAttributedString:[[[NSAttributedString alloc] initWithString:versionString] autorelease]];
    [[AUTHORS textStorage] appendAttributedString: webAString];
    [[AUTHORS textStorage] appendAttributedString: bugsAString];
    [[AUTHORS textStorage] appendAttributedString: creditsAString];
    [AUTHORS setAlignment: NSCenterTextAlignment range: NSMakeRange(0, [[AUTHORS textStorage] length])];

    aboutController = [[NSWindowController alloc] initWithWindow:ABOUT];
    [aboutController showWindow:ABOUT];
}

// size
- (IBAction)returnToDefaultSize:(id)sender
{
    PseudoTerminal *frontTerminal = [[iTermController sharedInstance] currentTerminal];
    PTYTab* theTab = [frontTerminal currentTab];
    PTYSession* aSession = [theTab activeSession];

    NSDictionary *abEntry = [aSession originalAddressBookEntry];

    NSString* fontDesc = [abEntry objectForKey:KEY_NORMAL_FONT];
    NSFont* font = [ITAddressBookMgr fontWithDesc:fontDesc];
    NSFont* nafont = [ITAddressBookMgr fontWithDesc:[abEntry objectForKey:KEY_NON_ASCII_FONT]];
    float hs = [[abEntry objectForKey:KEY_HORIZONTAL_SPACING] floatValue];
    float vs = [[abEntry objectForKey:KEY_VERTICAL_SPACING] floatValue];
    PTYSession* session = [frontTerminal currentSession];
    PTYTextView* textview = [session TEXTVIEW];
    [textview setFont:font nafont:nafont horizontalSpacing:hs verticalSpacing:vs];
        if ([sender isAlternate]) {
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

- (void) nonTerminalWindowBecameKey: (NSNotification *) aNotification
{
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

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    if ([menuItem action] == @selector(toggleUseBackgroundPatternIndicator:)) {
      [menuItem setState:[self useBackgroundPatternIndicator]];
      return YES;
    } else if ([menuItem action] == @selector(makeDefaultTerminal:)) {
        return ![self isDefaultTerminal];
    } else if (menuItem == maximizePane) {
        if ([[[iTermController sharedInstance] currentTerminal] inInstantReplay]) {
            // Things get too complex if you allow this. It crashes.
            return NO;
        } else if ([[[[iTermController sharedInstance] currentTerminal] currentTab] hasMaximizedPane]) {
            return YES;
        } else if ([[[[iTermController sharedInstance] currentTerminal] currentTab] hasMultipleSessions]) {
            return YES;
        } else {
            return NO;
        }
    } else if ([menuItem action] == @selector(newSessionWithSameProfile:)) {
        return [[iTermController sharedInstance] currentTerminal] != nil;
    } else if ([menuItem action] == @selector(toggleFullScreenTabBar:)) {
        PseudoTerminal *term = [[iTermController sharedInstance] currentTerminal];
        if (!term || ![term anyFullScreen]) {
            return NO;
        } else {
            [menuItem setState:[term fullScreenTabControl] ? NSOnState : NSOffState];
            return YES;
        }
    } else {
        return YES;
    }
}

- (IBAction)buildScriptMenu:(id)sender
{
    if ([[[[NSApp mainMenu] itemAtIndex: 5] title] isEqualToString:NSLocalizedStringFromTableInBundle(@"Script",@"iTerm", [NSBundle bundleForClass: [iTermController class]], @"Script")])
            [[NSApp mainMenu] removeItemAtIndex:5];

        // add our script menu to the menu bar
    // get image
    NSImage *scriptIcon = [NSImage imageNamed: @"script"];
    [scriptIcon setScalesWhenResized: YES];
    [scriptIcon setSize: NSMakeSize(16, 16)];

    // create menu item with no title and set image
    NSMenuItem *scriptMenuItem = [[[NSMenuItem alloc] initWithTitle: @"" action: nil keyEquivalent: @""] autorelease];
    [scriptMenuItem setImage: scriptIcon];

    // create submenu
    int count = 0;
    NSMenu *scriptMenu = [[NSMenu alloc] initWithTitle: NSLocalizedStringFromTableInBundle(@"Script",@"iTerm", [NSBundle bundleForClass: [iTermController class]], @"Script")];
    [scriptMenuItem setSubmenu: scriptMenu];
    // populate the submenu with ascripts found in the script directory
    NSDirectoryEnumerator *directoryEnumerator = [[NSFileManager defaultManager] enumeratorAtPath: [SCRIPT_DIRECTORY stringByExpandingTildeInPath]];
    NSString *file;

    while ((file = [directoryEnumerator nextObject])) {
        if ([[NSWorkspace sharedWorkspace] isFilePackageAtPath:[NSString stringWithFormat:@"%@/%@",
                                                                [SCRIPT_DIRECTORY stringByExpandingTildeInPath],
                                                                file]]) {
                [directoryEnumerator skipDescendents];
        }
        if ([[file pathExtension] isEqualToString: @"scpt"] ||
            [[file pathExtension] isEqualToString: @"app"] ) {
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
            NSMenuItem *scriptItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Refresh",
                                                                                                          @"iTerm",
                                                                                                          [NSBundle bundleForClass:[iTermController class]],
                                                                                                          @"Script")
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
        [[NSApp mainMenu] insertItem:scriptMenuItem atIndex:5];
        [scriptMenuItem setTitle:NSLocalizedStringFromTableInBundle(@"Script",
                                                                    @"iTerm",
                                                                    [NSBundle bundleForClass:[iTermController class]],
                                                                    @"Script")];
    }
}

- (IBAction)saveWindowArrangement:(id)sender
{
    [[iTermController sharedInstance] saveWindowArrangement];
}

- (IBAction)loadWindowArrangement:(id)sender
{
    [[iTermController sharedInstance] loadWindowArrangementWithName:[WindowArrangements defaultArrangementName]];
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

@end

// Scripting support
@implementation iTermApplicationDelegate (KeyValueCoding)

- (BOOL)application:(NSApplication *)sender delegateHandlesKey:(NSString *)key
{
    //NSLog(@"iTermApplicationDelegate: delegateHandlesKey: '%@'", key);
    return [[iTermController sharedInstance] application:sender delegateHandlesKey:key];
}

- (NSString *)uriToken
{
    [token_ release];
    token_ = [[NSString stringWithFormat:@"%x%x", arc4random(), arc4random()] retain];
    return token_;
}

// accessors for to-one relationships:
- (PseudoTerminal *)currentTerminal
{
    return [[iTermController sharedInstance] currentTerminal];
}

- (void)setCurrentTerminal:(PseudoTerminal *)aTerminal
{
    [[iTermController sharedInstance] setCurrentTerminal: aTerminal];
    iTermApplicationDelegate *itad = [[NSApplication sharedApplication] delegate];
    [itad updateBroadcastMenuState];
}


// accessors for to-many relationships:
- (NSArray*)terminals
{
    return [[iTermController sharedInstance] terminals];
}

- (void)setTerminals:(NSArray*)terminals
{
    // no-op
}

// accessors for to-many relationships:
// (See NSScriptKeyValueCoding.h)
-(id)valueInTerminalsAtIndex:(unsigned)idx
{
    return [[iTermController sharedInstance] valueInTerminalsAtIndex:idx];
}

-(void)replaceInTerminals:(PseudoTerminal *)object atIndex:(unsigned)idx
{
    [[iTermController sharedInstance] replaceInTerminals:object atIndex:idx];
}

- (void)addInTerminals:(PseudoTerminal *) object
{
    [[iTermController sharedInstance] addInTerminals:object];
}

- (void)insertInTerminals:(PseudoTerminal *) object
{
    [[iTermController sharedInstance] insertInTerminals:object];
}

-(void)insertInTerminals:(PseudoTerminal *)object atIndex:(unsigned)idx
{
    [[iTermController sharedInstance] insertInTerminals:object atIndex:idx];
}

-(void)removeFromTerminalsAtIndex:(unsigned)idx
{
    // NSLog(@"iTerm: removeFromTerminalsAtInde %d", idx);
    [[iTermController sharedInstance] removeFromTerminalsAtIndex: idx];
}

// a class method to provide the keys for KVC:
+(NSArray*)kvcKeys
{
    return [[iTermController sharedInstance] kvcKeys];
}


@end

@implementation iTermApplicationDelegate (Find_Actions)

- (IBAction) showFindPanel: (id) sender
{
        [[iTermController sharedInstance] showHideFindBar];
}

// findNext and findPrevious are reversed here because in the search UI next
// goes backwards and previous goes forwards.
// Internally, next=forward and prev=backwards.
- (IBAction)findPrevious:(id)sender
{
    PseudoTerminal* pty = [[iTermController sharedInstance] currentTerminal];
    if (pty) {
        [[pty currentSession] searchNext];
    }
}

- (IBAction)findNext:(id)sender
{
    PseudoTerminal* pty = [[iTermController sharedInstance] currentTerminal];
    if (pty) {
        [[pty currentSession] searchPrevious];
    }
}

- (IBAction)findWithSelection:(id)sender
{
    NSString* selection = [[[[[iTermController sharedInstance] currentTerminal] currentSession] TEXTVIEW] selectedText];
    if (selection) {
        for (PseudoTerminal* pty in [[iTermController sharedInstance] terminals]) {
            for (PTYSession* session in [pty sessions]) {
                [session useStringForFind:selection];
            }
        }
    }
}

- (IBAction)jumpToSelection:(id)sender
{
    id obj = [[NSApp mainWindow] firstResponder];
    PTYTextView *textView = 
        (obj && [obj isKindOfClass:[PTYTextView class]]) ? obj : nil;
    if (textView) {
        [textView scrollToSelection];
    } else {
        NSBeep();
    }
}

@end

@implementation iTermApplicationDelegate (MoreActions)

- (void)newSessionInTabAtIndex:(id)sender
{
    [[iTermController sharedInstance] newSessionInTabAtIndex:sender];
}

- (void)newSessionInWindowAtIndex: (id) sender
{
    [[iTermController sharedInstance] newSessionInWindowAtIndex:sender];
}

@end
