//
//  iTermSessionPicker.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/5/19.
//

#import "iTermSessionPicker.h"

#import "iTermApplication.h"
#import "iTermController.h"
#import "iTermHelpMessageViewController.h"
#import "NSImage+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSWindow+iTerm.h"
#import "PTYSession.h"
#import "SessionView.h"

@implementation iTermSessionPicker {
    SessionView *_sessionView;
    BOOL _done;
    NSPopover *_popover;
}

- (PTYSession *)pickSession {
    NSWindow *window = [[[iTermApplication sharedApplication] orderedWindowsPlusVisibleHotkeyPanels] firstObject];
    if (!window) {
        return nil;
    }
    NSStatusItem *item = [self addStatusBarItem];
    [[NSCursor crosshairCursor] set];
    while (!_done) {
        NSModalSession session = [NSApp beginModalSessionForWindow:window];
        NSRunLoop *myRunLoop = [NSRunLoop currentRunLoop];
        // This keeps the runloop blocking when nothing else is going on.
        NSPort *port = [NSMachPort port];
        [myRunLoop addPort:port
                   forMode:NSDefaultRunLoopMode];
        NSTimer *timer = [NSTimer timerWithTimeInterval:1/60.0
                                                 target:self
                                               selector:@selector(chooseSessionUnderCursor:)
                                               userInfo:nil
                                                repeats:YES];
        [myRunLoop addTimer:timer forMode:NSDefaultRunLoopMode];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didSelectSessionView:)
                                                     name:SessionViewWasSelectedForInspectionNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(abort:)
                                                     name:NSApplicationWillResignActiveNotification
                                                   object:nil];

        SessionView *sessionView = _sessionView;
        while (sessionView == _sessionView && !_done) {
            if ([NSApp runModalSession:session] != NSModalResponseContinue) {
                break;
            }
            [myRunLoop runMode:NSDefaultRunLoopMode
                    beforeDate:[NSDate distantFuture]];
        }
        [timer invalidate];
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        [NSApp endModalSession:session];

        window = _sessionView.window;
    }
    [[NSStatusBar systemStatusBar] removeStatusItem:item];
    [_sessionView setSplitSelectionMode:kSplitSelectionModeOff move:NO session:nil];
    [[NSCursor arrowCursor] set];
    return [PTYSession castFrom:_sessionView.delegate];
}

- (NSStatusItem *)addStatusBarItem {
    NSStatusItem *item = [[NSStatusBar systemStatusBar] statusItemWithLength:22];
    NSImage *image = [NSImage it_imageNamed:@"StopStatusIcon" forClass:self.class];
    item.title = @"";
    item.image = image;
    item.highlightMode = YES;
    item.button.target = self;
    item.button.action = @selector(abort:);

    iTermHelpMessageViewController *viewController = [[iTermHelpMessageViewController alloc] initWithNibName:@"iTermHelpMessageViewController"
                                                                                                      bundle:[NSBundle bundleForClass:self.class]];
    [viewController setMessage:@"Click the stop icon exit picker mode without making a selection."];

    // Create popover
    NSPopover *popover = [[NSPopover alloc] init];
    [popover setContentSize:viewController.view.frame.size];
    [popover setBehavior:NSPopoverBehaviorTransient];
    [popover setAnimates:YES];
    [popover setContentViewController:viewController];

    // Show popover
    [popover showRelativeToRect:item.button.bounds
                         ofView:item.button
                  preferredEdge:NSMinYEdge];
    _popover = popover;

    return item;
}

- (void)abort:(id)sender {
    [_sessionView setSplitSelectionMode:kSplitSelectionModeOff move:NO session:nil];
    _sessionView = nil;
    _done = YES;
}

- (void)didSelectSessionView:(NSNotification *)notification {
    _sessionView = notification.object;
    _done = YES;
}

- (void)chooseSessionUnderCursor:(NSTimer *)timer {
    NSRect mouseRect = {
        .origin = [NSEvent mouseLocation],
        .size = { 0, 0 }
    };
    NSView *view = [self viewAtMouseRect:mouseRect];
    while (view && ![view isKindOfClass:[SessionView class]]) {
        view = view.superview;
    }
    if (view) {
        if (_sessionView == view) {
            return;
        }
        [_sessionView setSplitSelectionMode:kSplitSelectionModeOff move:NO session:nil];
        _sessionView = (SessionView *)view;
        [_sessionView setSplitSelectionMode:kSplitSelectionModeInspect move:NO session:nil];
    }
}

- (NSView *)viewAtMouseRect:(NSRect)mouseRect {
    NSArray<NSWindow *> *frontToBackWindows = [[iTermApplication sharedApplication] orderedWindowsPlusVisibleHotkeyPanels];
    for (NSWindow *window in frontToBackWindows) {
        if (!window.isOnActiveSpace) {
            continue;
        }
        if (!window.isVisible) {
            continue;
        }
        NSPoint pointInWindow = [window convertRectFromScreen:mouseRect].origin;
        if ([window isTerminalWindow]) {
            NSView *view = [window.contentView hitTest:pointInWindow];
            if (view) {
                return view;
            }
        }
    }
    return nil;
}

@end
