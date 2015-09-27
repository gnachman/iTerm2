//
//  PseudoTerminalRestorer.m
//  iTerm
//
//  Created by George Nachman on 10/24/11.
//

// This ifndef affects only the Leopard configuration.

#import "PseudoTerminalRestorer.h"

#import "PseudoTerminal.h"
#import "iTermController.h"

static NSMutableArray *queuedBlocks;
typedef void (^VoidBlock)(void);
static BOOL gWaitingForFullScreen;

@implementation PseudoTerminalRestorer

#ifndef BLOCKS_NOT_AVAILABLE
+ (BOOL)willOpenWindows
{
    return queuedBlocks.count > 0;
}

+ (BOOL)useElCapitanFullScreenLogic {
    return [NSWindow instancesRespondToSelector:@selector(maxFullScreenContentSize)];
}

// The windows must be open one iteration of mainloop after the application
// finishes launching. Otherwise, on OS 10.7, non-lion-style fullscreen windows
// open but the menu bar stays up.
+ (void)runQueuedBlocks_10_10_andEarlier {
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
    while (queuedBlocks.count) {
        if (gWaitingForFullScreen) {
            return;
        }
        VoidBlock block = [queuedBlocks firstObject];
        block();
        [queuedBlocks removeObjectAtIndex:0];
    }
    [queuedBlocks release];
    queuedBlocks = nil;
}

// The windows must be open one iteration of mainloop after the application
// finishes launching. Otherwise, on OS 10.7, non-lion-style fullscreen windows
// open but the menu bar stays up.
+ (void)runQueuedBlocks
{
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
                  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler
{
    if ([[[NSUserDefaults standardUserDefaults] objectForKey:@"OpenArrangementAtStartup"] boolValue]) {
        completionHandler(nil, nil);
        return;
    }

    if (!queuedBlocks) {
        queuedBlocks = [[NSMutableArray alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:[PseudoTerminalRestorer class]
                                                 selector:@selector(runQueuedBlocks)
                                                     name:kApplicationDidFinishLaunchingNotification
                                                   object:nil];
    }
    NSDictionary *arrangement = [state decodeObjectForKey:@"ptyarrangement"];
    if (arrangement) {
        VoidBlock theBlock = ^{
            PseudoTerminal *term = [PseudoTerminal bareTerminalWithArrangement:arrangement];
            // We have to set the frame for fullscreen windows because the OS tries
            // to move it up 22 pixels for no good reason. Fullscreen, top, and
            // bottom windows will also end up broken if the screen resolution
            // has changed.
            // We MUST NOT set it for lion fullscreen because the OS knows what
            // to do with those, and we'd set it to some crazy wrong size.
            // Normal, top, and bottom windows take care of themselves.
            switch ([term windowType]) {
                case WINDOW_TYPE_FULL_SCREEN:
                case WINDOW_TYPE_TOP:
                case WINDOW_TYPE_BOTTOM:
                    [term performSelector:@selector(canonicalizeWindowFrame)
                               withObject:nil
                               afterDelay:0];
                    break;
            }

            if (![self useElCapitanFullScreenLogic] || !term.togglingLionFullScreen) {
                // In 10.10 or earlier, or 10.11 and a nonfullscreen window.
                completionHandler([term window], nil);
                [[iTermController sharedInstance] addInTerminals:term];
            } else {
                // 10.11 and this is a fullscreen window.
                // Keep any more blocks from running until this window finishes entering fullscreen.
                gWaitingForFullScreen = YES;

                [completionHandler retain];
                term.didEnterLionFullscreen = ^(PseudoTerminal *theTerm) {
                    // Finished entering fullscreen. Run the completion handler
                    // and open more windows.
                    completionHandler([theTerm window], nil);
                    [completionHandler release];
                    [[iTermController sharedInstance] addInTerminals:term];
                    gWaitingForFullScreen = NO;
                    [PseudoTerminalRestorer runQueuedBlocks];
                };
            }
        };
        [queuedBlocks addObject:[[theBlock copy] autorelease]];
    } else {
        completionHandler(nil, nil);
    }
}

#else  // BLOCKS_NOT_AVAILABLE

+ (BOOL)willOpenWindows
{
    return NO;
}

#endif  // BLOCKS_NOT_AVAILABLE

@end

