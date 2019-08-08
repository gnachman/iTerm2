//
//  iTermWindowSizeView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/4/19.
//

#import "iTermWindowSizeView.h"

#import "NSTextField+iTerm.h"

const CGFloat iTermWindowSizeViewMargin = 12;

@implementation iTermWindowSizeView {
    NSVisualEffectView *_vev;
    NSTextField *_label;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _vev = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
        _vev.material = NSVisualEffectMaterialHUDWindow;
        _vev.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        _vev.wantsLayer = YES;
        [self addSubview:_vev];
        _label = [NSTextField newLabelStyledTextField];
        _label.font = [NSFont systemFontOfSize:22];
        _label.alignment = NSTextAlignmentCenter;
        [_vev addSubview:_label];
    }
    return self;
}

- (void)setWindowSize:(VT100GridSize)size {
    _label.stringValue = [NSString stringWithFormat:@"%@ ⨉ %@", @(size.width), @(size.height)];
    [_label sizeToFit];

    [self layoutSelf];
}

- (void)layoutSelf {
    NSPoint center = CGPointMake(NSMidX(self.frame), NSMidY(self.frame));
    const NSSize size = NSMakeSize(_label.frame.size.width + iTermWindowSizeViewMargin * 2,
                                   _label.frame.size.height + iTermWindowSizeViewMargin * 2);
    self.frame = NSMakeRect(center.x - size.width / 2,
                            center.y - size.height / 2,
                            size.width,
                            size.height);
    [self layoutSubviews];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self layoutSubviews];
}

- (void)layoutSubviews {
    NSRect bounds = self.bounds;
    _vev.frame = bounds;
    _label.frame = NSInsetRect(bounds, iTermWindowSizeViewMargin, iTermWindowSizeViewMargin);
}

@end
