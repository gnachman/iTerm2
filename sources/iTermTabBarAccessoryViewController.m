//
//  iTermTabBarAccessoryViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/21/18.
//

#import "iTermTabBarAccessoryViewController.h"
#import "iTermAdvancedSettingsModel.h"

// TODO: FB7781183
@interface iTermHackAroundBigSurBugView: NSView
- (instancetype)init API_DEPRECATED("Bug supposedly fixed in macOS 12.", macosx(10.16, 11));
@end

@implementation iTermHackAroundBigSurBugView: NSView

- (instancetype)init {
    return [super init];
}
- (BOOL)isFlipped {
    return YES;
}
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [self layoutSubviews];
}
- (void)addSubview:(NSView *)view {
    [super addSubview:view];
    [self layoutSubviews];
}
- (void)layoutSubviews {
    for (NSView *view in self.subviews) {
        view.frame = NSMakeRect(0, 0, self.frame.size.width, self.frame.size.height - 4);
    }
}
@end

@interface iTermTabBarAccessoryViewController ()
@end

@implementation iTermTabBarAccessoryViewController {
    NSView *_view;
    iTermHackAroundBigSurBugView *_hack;
}

- (instancetype)initWithView:(NSView *)view {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        if (@available(macOS 12.0, *)) {
            // Apple says they fixed the bug in Monterey (macOS 12)
        } else {
            if ([iTermAdvancedSettingsModel allowTabbarInTitlebarAccessoryBigSur]) {
                if (@available(macOS 10.16, *)) {
                    _hack = [[iTermHackAroundBigSurBugView alloc] init];
                }
            }
        }
        _view = view;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p fullScreenMinHeight=%@ frame=%@ window=%p alpha=%@ hidden=%@>",
            NSStringFromClass([self class]),
            self,
            @(self.fullScreenMinHeight),
            NSStringFromRect(self.view.frame),
            self.view.window,
            @(self.view.alphaValue),
            @(self.view.isHidden)];
}

- (void)loadView {
    if (_hack) {
        _hack.frame = NSMakeRect(0, 0, _view.frame.size.width, _view.frame.size.height + 4);
        [_hack addSubview:_view];
        self.view = _hack;
        return;
    }
    self.view = _view;
}

- (__kindof NSView *)realView {
    return _view;
}

@end
