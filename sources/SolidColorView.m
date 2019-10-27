//
//  SolidColorView.m
//  iTerm
//
//  Created by George Nachman on 12/6/11.
//

#import "SolidColorView.h"

@implementation SolidColorView {
    BOOL _isFlipped;
}

@synthesize color = _color;

- (instancetype)initWithFrame:(NSRect)frame color:(NSColor*)color {
    self = [super initWithFrame:frame];
    if (self) {
        _color = [color retain];
    }
    return self;
}

- (void)dealloc {
    [_color release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p frame=%@ isHidden=%@ alphaValue=%@>",
            [self class], self, NSStringFromRect(self.frame), @(self.isHidden), @(self.alphaValue)];
}

- (void)drawRect:(NSRect)dirtyRect {
    [_color setFill];
    NSRectFill(dirtyRect);
    [super drawRect:dirtyRect];
}

- (void)setColor:(NSColor*)color {
    [_color autorelease];
    _color = [color retain];
    [self setNeedsDisplay:YES];
}

- (BOOL)isFlipped {
    return _isFlipped;
}

- (void)setFlipped:(BOOL)value {
    _isFlipped = value;
}

@end

@implementation iTermLayerBackedSolidColorView {
    BOOL _isFlipped;
}

@synthesize color = _color;

- (instancetype)initWithFrame:(NSRect)frame color:(NSColor *)color {
    self = [self initWithFrame:frame];
    if (self) {
        _color = [color retain];
    }
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
    }
    return self;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.wantsLayer = YES;
    }
    return self;
}

- (void)dealloc {
    [_color release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p frame=%@ isHidden=%@ alphaValue=%@>",
            [self class], self, NSStringFromRect(self.frame), @(self.isHidden), @(self.alphaValue)];
}

- (void)setColor:(NSColor *)color {
    [_color autorelease];
    _color = [color retain];
    self.layer.backgroundColor = [color CGColor];
}

- (BOOL)isFlipped {
    return _isFlipped;
}

- (void)setFlipped:(BOOL)value {
    _isFlipped = value;
}

@end

