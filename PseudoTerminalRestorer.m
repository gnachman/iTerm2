//
//  PseudoTerminalRestorer.m
//  iTerm
//
//  Created by George Nachman on 10/24/11.
//

#import "PseudoTerminalRestorer.h"
#import "PseudoTerminal.h"
#import "iTermController.h"

@implementation PseudoTerminalRestorer

+ (void)restoreWindowWithIdentifier:(NSString *)identifier
                              state:(NSCoder *)state
                  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler
{
    if ([[[NSUserDefaults standardUserDefaults] objectForKey:@"OpenArrangementAtStartup"] boolValue]) {
        completionHandler(nil, nil);
        return;
    }

    NSDictionary *arrangement = [state decodeObjectForKey:@"ptyarrangement"];
    if (arrangement) {
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
        completionHandler([term window], nil);
        [[iTermController sharedInstance] addInTerminals:term];
    } else {
        completionHandler(nil, nil);
    }
}

@end
