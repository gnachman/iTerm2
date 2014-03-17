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

@implementation PseudoTerminalRestorer

+ (BOOL)willOpenWindows
{
    return queuedBlocks.count > 0;
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
                case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
                case WINDOW_TYPE_TOP:
                case WINDOW_TYPE_TOP_PARTIAL:
                case WINDOW_TYPE_BOTTOM:
                case WINDOW_TYPE_BOTTOM_PARTIAL:
                    [term performSelector:@selector(canonicalizeWindowFrame)
                               withObject:nil
                               afterDelay:0];
                    break;
            }
            completionHandler([term window], nil);
            [[iTermController sharedInstance] addInTerminals:term];
        };
        [queuedBlocks addObject:[[theBlock copy] autorelease]];
    } else {
        completionHandler(nil, nil);
    }
}

@end

