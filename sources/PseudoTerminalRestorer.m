
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
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermController.h"
#import "iTermOrphanServerAdopter.h"
#import "iTermPreferences.h"
#import "iTermRestorableStateController.h"
#import "iTermUserDefaults.h"
#import "NSApplication+iTerm.h"
#import "NSObject+iTerm.h"
#import "PseudoTerminal.h"
#import "PseudoTerminal+Private.h"
#import "PseudoTerminal+WindowStyle.h"

static NSMutableArray *queuedBlocks;
typedef void (^VoidBlock)(void);
static BOOL gWaitingForFullScreen;
static void (^gPostRestorationCompletionBlock)(void);
static BOOL gRanQueuedBlocks;
static BOOL gExternalRestorationDidComplete;

NSString *const iTermWindowStateKeyGUID = @"guid";

@implementation PseudoTerminalState

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _arrangement = [[NSDictionary castFrom:[coder decodeObjectForKey:kTerminalWindowStateRestorationWindowArrangementKey]] retain];
        _coder = [coder retain];
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)arrangement {
    self = [super init];
    if (self) {
        _arrangement = [arrangement retain];
    }
    return self;
}

- (void)dealloc {
    [_arrangement release];
    [_coder release];
    [super dealloc];
}

@end

@implementation PseudoTerminalRestorer

+ (BOOL)willOpenWindows {
    return queuedBlocks.count > 0;
}

+ (void)runQueuedBlocks {
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
    gRanQueuedBlocks = YES;
    [self runPostRestorationBlockIfNeeded];
}

+ (void)runPostRestorationBlockIfNeeded {
    if (gPostRestorationCompletionBlock && gExternalRestorationDidComplete) {
        DLog(@"run post-restoration block %p", gPostRestorationCompletionBlock);
        gPostRestorationCompletionBlock();
        [gPostRestorationCompletionBlock release];
        gPostRestorationCompletionBlock = nil;
    }
}

+ (void)externalRestorationDidComplete {
    DLog(@"external restoration completed");
    gExternalRestorationDidComplete = YES;
    [self runPostRestorationBlockIfNeeded];
}

+ (void)setPostRestorationCompletionBlock:(void (^)(void))postRestorationCompletionBlock {
    DLog(@"set post-restoration completion block");
    if (gRanQueuedBlocks && gExternalRestorationDidComplete) {
        postRestorationCompletionBlock();
    } else {
        if (gPostRestorationCompletionBlock) {
            void (^oldBlock)(void) = [[gPostRestorationCompletionBlock retain] autorelease];
            gPostRestorationCompletionBlock = [^{
                DLog(@"call older postrestoration block");
                oldBlock();
                [oldBlock release];
                postRestorationCompletionBlock();
            } copy];
            DLog(@"replace postretoration block %p with new one %p", oldBlock, gPostRestorationCompletionBlock);
        } else {
            gPostRestorationCompletionBlock = [postRestorationCompletionBlock copy];
            DLog(@"postrestoration block is now %p", gPostRestorationCompletionBlock);
        }
    }
}

+ (void (^)(void))postRestorationCompletionBlock {
    return gPostRestorationCompletionBlock;
}

+ (void)restoreWindowWithIdentifier:(NSString *)identifier
                              state:(NSCoder *)state
                  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler {
    [self restoreWindowWithIdentifier:identifier
                  pseudoTerminalState:[[[PseudoTerminalState alloc] initWithCoder:state] autorelease]
                               system:YES
                    completionHandler:completionHandler];
}

+ (void)restoreWindowWithIdentifier:(NSString *)identifier
                pseudoTerminalState:(PseudoTerminalState *)state
                             system:(BOOL)system
                  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler {
    if (system && [iTermUserDefaults ignoreSystemWindowRestoration]) {
        DLog(@"Ignore system window restoration because we're using our own restorable state controller.");
        NSString *guid = [state.coder decodeObjectForKey:iTermWindowStateKeyGUID];
        if (!guid) {
            DLog(@"GUID missing.");
            iTermRestorableStateController.shouldIgnoreOpenUntitledFile = YES;
            completionHandler(nil, nil);
            iTermRestorableStateController.shouldIgnoreOpenUntitledFile = NO;
        } else {
            DLog(@"Save completion handler in restorable state controller for window %@", guid);
            [[iTermRestorableStateController sharedInstance] setSystemRestorationCallback:completionHandler
                                                                         windowIdentifier:guid];
        }
        DLog(@"return");
        return;
    }
    if ([[NSApplication sharedApplication] isRunningUnitTests]) {
        completionHandler(nil, nil);
        return;
    }
    if ([iTermAdvancedSettingsModel startDebugLoggingAutomatically]) {
        TurnOnDebugLoggingSilently();
    }

    DLog(@"Restore window with identifier %@", identifier);
    if ([[[NSBundle mainBundle] bundleIdentifier] containsString:@"applescript"]) {
        // Disable window restoration for iTerm2ForAppleScriptTesting
        DLog(@"Abort because bundle ID contains applescript");
        completionHandler(nil, nil);
        return;
    }
    if ([[NSApplication sharedApplication] isRunningUnitTests]) {
        DLog(@"Abort because this is a unit test.");
        completionHandler(nil, nil);
        return;
    }
    [[[iTermApplication sharedApplication] delegate] willRestoreWindow];

    if ([iTermPreferences boolForKey:kPreferenceKeyOpenArrangementAtStartup]) {
        DLog(@"Abort because opening arrangement at startup");
        NSDictionary *arrangement = state.arrangement;
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
    }
    NSDictionary *arrangement = [state.arrangement retain];
    if (arrangement) {
        DLog(@"Have an arrangement");
        VoidBlock theBlock = ^{
            DLog(@"PseudoTerminalRestorer block running for id %@", identifier);
            DLog(@"Creating term");
            PseudoTerminal *term = [PseudoTerminal bareTerminalWithArrangement:arrangement
                                                      forceOpeningHotKeyWindow:NO];
            [arrangement autorelease];
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
                case WINDOW_TYPE_MAXIMIZED:
                case WINDOW_TYPE_COMPACT_MAXIMIZED:
                    DLog(@"Canonicalizing window frame");
                    [term performSelector:@selector(canonicalizeWindowFrame)
                               withObject:nil
                               afterDelay:0];
                    break;

                case WINDOW_TYPE_LEFT:
                case WINDOW_TYPE_RIGHT:
                case WINDOW_TYPE_NORMAL:
                case WINDOW_TYPE_LEFT_PARTIAL:
                case WINDOW_TYPE_NO_TITLE_BAR:
                case WINDOW_TYPE_COMPACT:
                case WINDOW_TYPE_RIGHT_PARTIAL:
                case WINDOW_TYPE_LION_FULL_SCREEN:
                case WINDOW_TYPE_ACCESSORY:
                    break;
            }

            DLog(@"Invoking completion handler");
            if (!term.togglingLionFullScreen) {
                DLog(@"In 10.10 or earlier, or 10.11 and a nonfullscreen window");
                term.restoringWindow = YES;
                completionHandler([term window], nil);
                term.restoringWindow = NO;
                DLog(@"Registering terminal window");
                [[iTermController sharedInstance] addTerminalWindow:term];
            } else {
                DLog(@"10.11 and this is a fullscreen window.");
                // Keep any more blocks from running until this window finishes entering fullscreen.
                gWaitingForFullScreen = YES;
                DLog(@"Set gWaitingForFullScreen=YES and set callback on %@", term);

                [completionHandler retain];
                term.didEnterLionFullscreen = ^(PseudoTerminal *theTerm) {
                    // Finished entering fullscreen. Run the completion handler
                    // and open more windows.
                    DLog(@"%@ finished entering fullscreen, running completion handler", theTerm);
                    term.restoringWindow = YES;
                    completionHandler([theTerm window], nil);
                    term.restoringWindow = NO;
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

+ (void)setRestorationCompletionBlock:(void(^)(void))completion {
    if (queuedBlocks) {
        [queuedBlocks addObject:[[completion copy] autorelease]];
    } else {
        completion();
    }
}

@end

