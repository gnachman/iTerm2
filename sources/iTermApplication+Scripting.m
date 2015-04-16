//
//  iTermApplication+Scripting.m
//  iTerm2
//
//  Created by George Nachman on 8/26/14.
//
//

#import "iTermApplication+Scripting.h"
#import "iTermController.h"

@implementation iTermApplication (Scripting)

- (id)valueForUndefinedKey:(NSString *)key {
    return @[];
}

- (id)currentWindow {
    return [(NSWindowController *)[[iTermController sharedInstance] currentTerminal] window];
}

@end
