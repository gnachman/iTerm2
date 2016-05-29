//
//  NSTextField+iTerm.m
//  iTerm
//
//  Created by George Nachman on 1/27/14.
//
//

#import "NSTextField+iTerm.h"

#import "NSStringITerm.h"
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

- (NSUInteger)separatorTolerantUnsignedIntegerValue {
    NSString *digits = [[self stringValue] stringByReplacingOccurrencesOfRegex:@"[^0-9]"
                                                                    withString:@""];
    return [digits iterm_unsignedIntegerValue];
}

- (NSTextField *)replaceWithHyperlinkTo:(NSURL *)url {
    NSTextField *link = [[[NSTextField alloc] initWithFrame:self.frame] autorelease];
    link.editable = self.editable;
    link.drawsBackground = self.drawsBackground;
    link.bordered = self.bordered;

    // According to Apple these two are needed to make it clickable.
    link.allowsEditingTextAttributes = YES;
    link.selectable = YES;
    NSDictionary *attributes = @{ NSUnderlineStyleAttributeName: @(NSSingleUnderlineStyle),
                                  NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0 green:0 blue:0.93 alpha:1],
                                  NSCursorAttributeName: [NSCursor pointingHandCursor],
                                  NSLinkAttributeName: url };
    NSMutableAttributedString *attributedString = [[self.attributedStringValue mutableCopy] autorelease];
    for (NSString *key in attributes) {
        [attributedString addAttribute:key value:attributes[key] range:NSMakeRange(0, [attributedString length])];
    }
    link.attributedStringValue = attributedString;

    NSView *superview = self.superview;
    [self removeFromSuperview];
    [superview addSubview:link];

    return link;
}

@end
