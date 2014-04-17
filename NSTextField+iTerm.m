//
//  NSTextField+iTerm.m
//  iTerm
//
//  Created by George Nachman on 1/27/14.
//
//

#import "NSTextField+iTerm.h"
#import "RegexKitLite.h"

@implementation NSTextField (iTerm)

- (BOOL)textFieldIsFirstResponder {
    BOOL inFocus = NO;
    
    // If the textfield's widow's first responder is a text view and
    // the default editor for the text field exists and
    // the textfield is the textfield's window's first responder's delegate
    inFocus = ([[[self window] firstResponder] isKindOfClass:[NSTextView class]] &&
               [[self window] fieldEditor:NO forObject:nil] !=nil &&
               [self isEqualTo:(id)[(NSTextView *)[[self window] firstResponder] delegate]]);

    return inFocus;
}

- (void)setLabelEnabled:(BOOL)enabled {
    self.textColor = enabled ? [NSColor blackColor] : [NSColor disabledControlTextColor];
}

- (int)separatorTolerantIntValue {
    NSString *digits = [[self stringValue] stringByReplacingOccurrencesOfRegex:@"[^0-9]"
                                                                    withString:@""];
    if ([[self stringValue] hasPrefix:@"-"]) {
        return -[digits intValue];
    } else {
        return [digits intValue];
    }
}

@end
