//
//  iTermWindowSizeView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/4/19.
//

#import "iTermWindowSizeView.h"

#import "NSTextField+iTerm.h"
#import "NSView+iTerm.h"

const CGFloat iTermWindowSizeViewMargin = 12;

@implementation iTermWindowSizeView {
    NSVisualEffectView *_vev;
    NSTextField *_label;
    NSTextField *_detailLabel;
}

- (instancetype)initWithDetail:(NSString *)detail {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _detail = [detail copy];
        _vev = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
        _vev.material = NSVisualEffectMaterialHUDWindow;
        _vev.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        _vev.wantsLayer = YES;
        [self addSubview:_vev];

        _label = [NSTextField newLabelStyledTextField];
        _label.font = [NSFont systemFontOfSize:22];
        _label.alignment = NSTextAlignmentCenter;
        [_vev addSubview:_label];

        if (detail) {
            _detailLabel = [NSTextField newLabelStyledTextField];
            _detailLabel.font = [NSFont systemFontOfSize:14];
            _detailLabel.alignment = NSTextAlignmentCenter;
            _detailLabel.alphaValue = 0.75;
            [_vev addSubview:_detailLabel];
        }
    }
    return self;
}

- (void)setWindowSize:(VT100GridSize)size {
    _label.stringValue = [NSString stringWithFormat:@"%@ ⨉ %@", @(size.width), @(size.height)];
    [_label sizeToFit];

    if (self.detail) {
        _detailLabel.stringValue = self.detail;
        [_detailLabel sizeToFit];
    }

    [self layoutSelf];
}

- (void)layoutSelf {
    NSPoint center = CGPointMake(NSMidX(self.frame), NSMidY(self.frame));
    const CGFloat width = MAX(_label.frame.size.width, _detailLabel.frame.size.width);
    CGFloat height = _label.frame.size.height + iTermWindowSizeViewMargin * 2;
    if (self.detail) {
        height += iTermWindowSizeViewMargin + _detailLabel.frame.size.height;
    }
    const NSSize size = NSMakeSize(width + iTermWindowSizeViewMargin * 2,
                                   height + iTermWindowSizeViewMargin * 2);
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

    NSRect frame = NSInsetRect(bounds, iTermWindowSizeViewMargin, iTermWindowSizeViewMargin);
    if (self.detail) {
        frame.size.height = _detailLabel.frame.size.height;
        _detailLabel.frame = frame;
        frame.origin.y += _detailLabel.frame.size.height + iTermWindowSizeViewMargin;
        frame.size.height = _label.frame.size.height;
        _label.frame = frame;
    } else {
        frame.size.height = _label.frame.size.height;
        frame.origin.y = [self retinaRound:(NSHeight(bounds) - NSHeight(frame)) / 2.0];
        _label.frame = frame;
    }

}

@end
