//
//  NSAlert+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/6/18.
//

#import "NSAlert+iTerm.h"
#import "DebugLogging.h"

@implementation NSAlert (iTerm)

- (NSModalResponse)runSheetModalForWindow:(NSWindow *)window {
    DLog(@"Run sheet modal for window %@", window);

    [NSApp activateIgnoringOtherApps:YES];
    [self beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
        [NSApp stopModalWithCode:returnCode];
    }];
    return [NSApp runModalForWindow:[self window]];
}

@end
