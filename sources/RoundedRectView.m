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
        self.layer.backgroundColor = [[[NSColor darkGrayColor] colorWithAlphaComponent:0.8] CGColor];
        self.layer.borderColor = [[NSColor whiteColor] CGColor];
        self.layer.borderWidth = 1.0;
        self.layer.cornerRadius = 5.0;
        self.layer.opaque = NO;
    }

    return self;
}

- (BOOL)isOpaque {
    return NO;
}

@end
