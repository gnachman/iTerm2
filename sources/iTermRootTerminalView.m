//
//  iTermRootTerminalView.m
//  iTerm2
//
//  Created by George Nachman on 7/3/15.
//
//

#import "iTermRootTerminalView.h"
#import "PTYTabView.h"

@interface iTermRootTerminalView()

@property(nonatomic, retain) PTYTabView *tabView;

@end


@implementation iTermRootTerminalView

- (instancetype)initWithFrame:(NSRect)frameRect color:(NSColor *)color {
    self = [super initWithFrame:frameRect color:color];
    if (self) {
        self.tabView = [[[PTYTabView alloc] initWithFrame:self.bounds] autorelease];
        _tabView.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
        _tabView.autoresizesSubviews = YES;
        _tabView.allowsTruncatedLabels = NO;
        _tabView.controlSize = NSSmallControlSize;
        _tabView.tabViewType = NSNoTabsNoBorder;
        [self addSubview:_tabView];
    }
    return self;
}

@end
