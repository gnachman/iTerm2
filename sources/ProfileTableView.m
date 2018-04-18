//
//  ProfileTableView.m
//  iTerm
//
//  Created by George Nachman on 1/9/12.
//

#import "ProfileTableView.h"

@implementation ProfileTableView {
    id<ProfileTableMenuHandler> handler_;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidResignKey:)
                                                     name:NSWindowDidResignKeyNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidBecomeKey:)
                                                     name:NSWindowDidBecomeKeyNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)setMenuHandler:(id<ProfileTableMenuHandler>)handler {
    handler_ = handler;
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
    if ([handler_ respondsToSelector:@selector(menuForEvent:)]) {
        return [handler_ menuForEvent:theEvent];
    }
    return nil;
}

- (void)highlightSelectionInClipRect:(NSRect)theClipRect {
    if (!self.window.isKeyWindow) {
        return [super highlightSelectionInClipRect:theClipRect];
    }

    NSColor *color = [NSColor colorWithCalibratedRed:17/255.0 green:108/255.0 blue:214/255.0 alpha:1];

    [self.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [color set];
        NSRectFill([self rectOfRow:idx]);
    }];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    [self setNeedsDisplay];
}

- (void)windowDidResignKey:(NSNotification *)notification {
    [self setNeedsDisplay];
}

@end
