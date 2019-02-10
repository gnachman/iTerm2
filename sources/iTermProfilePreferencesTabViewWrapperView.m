//
//  iTermProfilePreferencesTabViewWrapperView.m
//  iTerm2
//
//  Created by George Nachman on 2/9/19.
//

#import "iTermProfilePreferencesTabViewWrapperView.h"

@implementation iTermProfilePreferencesTabViewWrapperView {
    IBOutlet NSView *_tabView;
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize {
    [super resizeWithOldSuperviewSize:oldSize];
    NSRect frame = self.bounds;
    frame.size.width = MAX(frame.size.width, 565);
    _tabView.frame = frame;
}

@end
