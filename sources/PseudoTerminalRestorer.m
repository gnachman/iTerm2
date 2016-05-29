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
static BOOL gWaitingForFullScreen;

@implementation PseudoTerminalRestorer

+ (BOOL)willOpenWindows {
    return queuedBlocks.count > 0;
}

+ (BOOL)useElCapitanFullScreenLogic {
    return [NSWindow instancesRespondToSelector:@selector(maxFullScreenContentSize)];
}

+ (void)runQueuedBlocks {
    if ([self useElCapitanFullScreenLogic]) {
        [self runQueuedBlocks_10_11_andLater];
    } else {
      [self runQueuedBlocks_10_10_andEarlier];
    }
}

// The windows must be open one iteration of mainloop after the application
// finishes launching. Otherwise, on OS 10.7, non-lion-style fullscreen windows
// open but the menu bar stays up.
+ (void)runQueuedBlocks_10_10_andEarlier {
    DLog(@"runQueuedBlocks (<=10.10) starting");
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

// 10.11 wants this to happen right away.
+ (void)runQueuedBlocks_10_11_andLater {
    DLog(@"runQueuedBlocks (10.11+) starting");
    while (queuedBlocks.count) {
        if (gWaitingForFullScreen) {
            DLog(@"waiting for fullscreen");
            return;
        }
        DLog(@"Running queued block...");
        VoidBlock block = [queuedBlocks firstObject];
        block();
        [queuedBlocks removeObjectAtIndex:0];
        DLog(@"Finished running queued block");
    }
    DLog(@"Ran all queued blocks");
    [queuedBlocks release];
    queuedBlocks = nil;
}

+ (void)restoreWindowWithIdentifier:(NSString *)identifier
                              state:(NSCoder *)state
                  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler {
    if ([[NSApplication sharedApplication] isRunningUnitTests]) {
        completionHandler(nil, nil);
        return;
    }
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
            DLog(@"Create a new terminal %@", term);
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
            if (![self useElCapitanFullScreenLogic] || !term.togglingLionFullScreen) {
                // In 10.10 or earlier, or 10.11 and a nonfullscreen window.
                completionHandler([term window], nil);
                DLog(@"Registering terminal window");
                [[iTermController sharedInstance] addTerminalWindow:term];
            } else {
                // 10.11 and this is a fullscreen window.
                // Keep any more blocks from running until this window finishes entering fullscreen.
                gWaitingForFullScreen = YES;
                DLog(@"Set gWaitingForFullScreen=YES and set callback on %@", term);

                [completionHandler retain];
                term.didEnterLionFullscreen = ^(PseudoTerminal *theTerm) {
                    // Finished entering fullscreen. Run the completion handler
                    // and open more windows.
                    DLog(@"%@ finished entering fullscreen, running completion handler", theTerm);
                    completionHandler([theTerm window], nil);
                    [completionHandler release];
                    DLog(@"Registering terminal window");
                    [[iTermController sharedInstance] addTerminalWindow:term];
                    gWaitingForFullScreen = NO;
                    [PseudoTerminalRestorer runQueuedBlocks];
                };
            }
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

