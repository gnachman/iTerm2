//
//  iTermApplication+Scripting.m
//  iTerm2
//
//  Created by George Nachman on 8/26/14.
//
//

#import "iTermApplication+Scripting.h"
#import "iTermController.h"
#import "iTermScriptingWindow.h"

@implementation iTermApplication (Scripting)

- (id)valueForUndefinedKey:(NSString *)key {
    return @[];
}

- (id)currentScriptingWindow {
    return [iTermScriptingWindow scriptingWindowWithWindow:[(NSWindowController *)[[iTermController sharedInstance] currentTerminal] window]];
}

@end
