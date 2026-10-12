//
//  NSResponder+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/10/18.
//

#import "NSResponder+iTerm.h"

#import "DebugLogging.h"
#import "NSObject+iTerm.h"

#import <objc/runtime.h>

@implementation NSResponder (iTerm)

- (BOOL)it_wantsScrollWheelMomentumEvents {
    return NO;
}

- (void)it_scrollWheelMomentum:(NSEvent *)event {
}

- (BOOL)it_preferredFirstResponder {
    NSTextView *textView = [NSTextView castFrom:self];
    if (textView) {
        id delegate = [textView delegate];
        if ([delegate respondsToSelector:_cmd]) {
            return [(NSResponder *)delegate it_preferredFirstResponder];
        }
    }
    return NO;
}

- (BOOL)it_isTerminalResponder {
    return NO;
}

@end
