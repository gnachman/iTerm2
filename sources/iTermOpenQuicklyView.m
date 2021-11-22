//
//  iTermOpenQuicklyView.m
//  iTerm
//
//  Created by George Nachman on 7/13/14.
//
//

#import "iTermOpenQuicklyView.h"
#import "NSView+iTerm.h"

@implementation iTermOpenQuicklyView {
    NSVisualEffectView *_visualEffectView;
    NSView *_container;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)awakeFromNib {
    // Flip subviews
    NSArray *subviews = [self subviews];
    CGFloat height = self.bounds.size.height;
    for (NSView *view in subviews) {
        NSRect frame = view.frame;
        frame.origin.y = height - NSMaxY(frame);
        view.frame = frame;
    }

    _container = [[NSView alloc] initWithFrame:self.bounds];
    [self insertSubview:_container atIndex:0];

    _visualEffectView = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
    _visualEffectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    if (@available(macOS 10.16, *)) {
        _visualEffectView.material = NSVisualEffectMaterialMenu;
    } else {
        _visualEffectView.material = NSVisualEffectMaterialSheet;
    }
    _visualEffectView.state = NSVisualEffectStateActive;
    [_container addSubview:_visualEffectView];

    // Even though this is set in IB, we have to set it manually.
    self.autoresizesSubviews = NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    return;
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    _container.frame = self.bounds;
    _visualEffectView.frame = _container.bounds;
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize {
    [super resizeWithOldSuperviewSize:oldSize];
    _container.frame = self.bounds;
    _visualEffectView.frame = _container.bounds;
}

@end
