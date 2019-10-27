//
//  SolidColorView.m
//  iTerm
//
//  Created by George Nachman on 12/6/11.
//

#import "SolidColorView.h"
#import <objc/runtime.h>

@implementation iTermBaseSolidColorView {
    BOOL _isFlipped;
}

@synthesize color = _color;

- (instancetype)initWithFrame:(NSRect)frame color:(NSColor *)color {
    self = [super initWithFrame:frame];
    if (self) {
        _color = color;
        if (self.solidColorViewUsesLayer) {
            self.wantsLayer = YES;
            self.layer.backgroundColor = [color CGColor];
        }
    }
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        if (self.solidColorViewUsesLayer) {
            self.wantsLayer = YES;
        }
    }
    return self;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        if (self.solidColorViewUsesLayer) {
            self.wantsLayer = YES;
        }
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p frame=%@ isHidden=%@ alphaValue=%@>",
            [self class], self, NSStringFromRect(self.frame), @(self.isHidden), @(self.alphaValue)];
}

- (void)drawRect:(NSRect)dirtyRect {
    if (self.solidColorViewUsesLayer) {
        return;
    }
    [self.color setFill];
    NSRectFill(dirtyRect);
    [super drawRect:dirtyRect];
}

- (void)setColor:(NSColor *)color {
    _color = color;
    if (self.solidColorViewUsesLayer) {
        self.layer.backgroundColor = [color CGColor];
    } else {
        [self setNeedsDisplay:YES];
    }
}

- (BOOL)isFlipped {
    return _isFlipped;
}

- (void)setFlipped:(BOOL)value {
    _isFlipped = value;
}

- (BOOL)solidColorViewUsesLayer {
    return NO;
}

@end

@implementation iTermLegacySolidColorView

- (BOOL)solidColorViewUsesLayer {
    return NO;
}

@end

@implementation SolidColorView

- (BOOL)solidColorViewUsesLayer {
    if (@available(macOS 10.14, *)) {
        return YES;
    }
    return NO;
}

@end

@implementation iTermLayerBackedSolidColorView

- (BOOL)solidColorViewUsesLayer {
    return YES;
}

@end

