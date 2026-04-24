//
//  iTermToolbeltSplitView.m
//  iTerm2
//
//  Created by George Nachman on 7/5/15.
//
//

#import "iTermToolbeltSplitView.h"

@implementation iTermToolbeltSplitView {
    NSColor *_dividerColor;
}

- (void)dealloc {
    [_dividerColor release];
    [super dealloc];
}

- (void)setDividerColor:(NSColor *)dividerColor {
    [_dividerColor autorelease];
    _dividerColor = [dividerColor copy];
    [self setNeedsDisplay:YES];
}

- (NSColor *)dividerColor {
    return _dividerColor;
}

@end

