//
//  RoundedRectView.m
//  iTerm
//
//  Created by George Nachman on 3/13/13.
//
//

#import "RoundedRectView.h"

@implementation RoundedRectView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setWantsLayer:YES];
        self.layer = [[CALayer alloc] init];
        self.layer.backgroundColor = [[NSColor clearColor] CGColor];
        self.layer.opaque = NO;
    }

    return self;
}

- (BOOL)isOpaque {
    return NO;
}

@end
