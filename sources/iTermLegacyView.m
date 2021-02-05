//
//  iTermLegacyView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/5/21.
//

#import "iTermLegacyView.h"

@implementation iTermLegacyView

- (void)drawRect:(NSRect)dirtyRect {
    [self.delegate legacyView:self drawRect:dirtyRect];
}

- (BOOL)isFlipped {
    return YES;
}

@end
