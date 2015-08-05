//
//  PseudoTerminalRestorer.m
//  iTerm
//
//  Created by George Nachman on 10/24/11.
//

// This ifndef affects only the Leopard configuration.

#import "PseudoTerminalRestorer.h"
#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermController.h"
#import "iTermOrphanServerAdopter.h"
#import "iTermPreferences.h"
#import "NSApplication+iTerm.h"
#import "PseudoTerminal.h"

static NSMutableArray *queuedBlocks;
typedef void (^VoidBlock)(void);

@implementation PseudoTerminalRestorer

+ (BOOL)willOpenWindows {
    return queuedBlocks.count > 0;
}

// The windows must be open one iteration of mainloop after the application
// finishes launching. Otherwise, on OS 10.7, non-lion-style fullscreen windows
// open but the menu bar stays up.
+ (void)runQueuedBlocks {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0),
                   dispatch_get_current_queue(),
                   ^{
                       for (VoidBlock block in queuedBlocks) {
                           block();
                       }
                       [queuedBlocks release];
                       queuedBlocks = nil;
                   });
}

+ (void)restoreWindowWithIdentifier:(NSString *)identifier
                              state:(NSCoder *)state
                  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler {
    if ([iTermAdvancedSettingsModel startDebugLoggingAutomatically]) {
        TurnOnDebugLoggingSilently();
    }

    DLog(@"Restore window with identifier %@", identifier);
    if ([[[NSBundle mainBundle] bundleIdentifier] containsString:@"applescript"]) {
        // Disable window restoration for iTerm2ForApplescriptTesting
        DLog(@"Abort because bundle ID contains applescript");
        completionHandler(nil, nil);
        return;
    }
    if ([[NSApplication sharedApplication] isRunningUnitTests]) {
        DLog(@"Abort because this is a unit test.");
        completionHandler(nil, nil);
        return;
    }

    if (![[iTermOrphanServerAdopter sharedInstance] haveOrphanServers]) {
        // We don't respect the startup preference if orphan servers are present. Just restore things
        // as best we can.
        if ([iTermPreferences boolForKey:kPreferenceKeyOpenArrangementAtStartup]) {
            DLog(@"Abort because opening arrangement at startup");
            NSDictionary *arrangement =
                [state decodeObjectForKey:kPseudoTerminalStateRestorationWindowArrangementKey];
            if (arrangement) {
                [PseudoTerminal registerSessionsInArrangement:arrangement];
            }
            completionHandler(nil, nil);
            return;
        } else if ([iTermPreferences boolForKey:kPreferenceKeyOpenNoWindowsAtStartup]) {
            DLog(@"Abort because opening no windows at startup");
            completionHandler(nil, nil);
            return;
        }
    }

    if (!queuedBlocks) {
        DLog(@"This is the first run of PseudoTerminalRestorer");
        queuedBlocks = [[NSMutableArray alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:[PseudoTerminalRestorer class]
                                                 selector:@selector(runQueuedBlocks)
                                                     name:kApplicationDidFinishLaunchingNotification
                                                   object:nil];
    }
    NSDictionary *arrangement = [state decodeObjectForKey:kPseudoTerminalStateRestorationWindowArrangementKey];
    if (arrangement) {
        DLog(@"Have an arrangement");
        VoidBlock theBlock = ^{
            DLog(@"PseudoTerminalRestorer block running for id %@", identifier);
            DLog(@"Creating term");
            PseudoTerminal *term = [PseudoTerminal bareTerminalWithArrangement:arrangement];
            if (!term) {
                DLog(@"Failed to create term");
                completionHandler(nil, nil);
                return;
            }
            // We have to set the frame for fullscreen windows because the OS tries
            // to move it up 22 pixels for no good reason. Fullscreen, top, and
            // bottom windows will also end up broken if the screen resolution
            // has changed.
            // We MUST NOT set it for lion fullscreen because the OS knows what
            // to do with those, and we'd set it to some crazy wrong size.
            // Normal, top, and bottom windows take care of themselves.
            switch ([term windowType]) {
                case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
                case WINDOW_TYPE_TOP:
                case WINDOW_TYPE_TOP_PARTIAL:
                case WINDOW_TYPE_BOTTOM:
                case WINDOW_TYPE_BOTTOM_PARTIAL:
                    DLog(@"Canonicalizing window frame");
                    [term performSelector:@selector(canonicalizeWindowFrame)
                               withObject:nil
                               afterDelay:0];
                    break;
            }

            DLog(@"Invoking completion handler");
            completionHandler([term window], nil);
            DLog(@"Registering terminal window");
            [[iTermController sharedInstance] addTerminalWindow:term];
            DLog(@"Done running block for id %@", identifier);
        };
        DLog(@"Queueing block to run");
        [queuedBlocks addObject:[[theBlock copy] autorelease]];
        DLog(@"Returning");
    } else {
        DLog(@"Abort because no arrangement");
        completionHandler(nil, nil);
    }
}

+ (void)setRestorationCompletionBlock:(void(^)())completion {
    if (queuedBlocks) {
        [queuedBlocks addObject:[[completion copy] autorelease]];
    } else {
        completion();
    }
}

@end

