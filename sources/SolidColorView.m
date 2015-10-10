//
//  SolidColorView.m
//  iTerm
//
//  Created by George Nachman on 12/6/11.
//

#import "SolidColorView.h"

@implementation SolidColorView
@synthesize color = color_;

- (instancetype)initWithFrame:(NSRect)frame color:(NSColor*)color
{
    self = [super initWithFrame:frame];
    if (self) {
        color_ = [color retain];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p frame=%@ isHidden=%@ alphaValue=%@>",
            [self class], self, NSStringFromRect(self.frame), @(self.isHidden), @(self.alphaValue)];
}

- (void)drawRect:(NSRect)dirtyRect
{
    [color_ setFill];
    NSRectFill(dirtyRect);
    [super drawRect:dirtyRect];
}

- (void)setColor:(NSColor*)color
{
    [color_ autorelease];
    color_ = [color retain];
    [self setNeedsDisplay:YES];
}

- (BOOL)isFlipped
{
    return isFlipped_;
}

- (void)setFlipped:(BOOL)value
{
    isFlipped_ = value;
}

- (void)dealloc
{
    [color_ release];
    [super dealloc];
}
@end
