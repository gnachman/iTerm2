//
//  iTermAnnouncement.m
//  iTerm
//
//  Created by George Nachman on 5/16/14.
//
//

#import "iTermAnnouncementViewController.h"
#import "DebugLogging.h"
#import "SolidColorView.h"

@interface iTermAnnouncementViewController ()
@property(nonatomic, copy) NSArray *actions;
@property(nonatomic, assign) iTermAnnouncementViewStyle style;
@end

@implementation iTermAnnouncementViewController {
    BOOL _dismissing;
    NSTimer *_timer;
    BOOL _visible;
    NSTimeInterval _timeout;
    BOOL _didTimeout;
}

+ (instancetype)announcementWithTitle:(NSString *)title
                                style:(iTermAnnouncementViewStyle)style
                          withActions:(NSArray *)actions
                           completion:(void (^)(int))completion {
    iTermAnnouncementViewController *announcement = [[[self alloc] init] autorelease];
    announcement.title = title;
    announcement.actions = actions;
    announcement.completion = completion;
    announcement.style = style;
    return announcement;
}

- (void)dealloc {
    [_actions release];
    [_completion release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p title=\"%@\" dismissing=%d>",
            self.class, self, self.title, (int)_dismissing];
}

- (void)loadView {
    [self retain];
    self.view = [iTermAnnouncementView announcementViewWithTitle:self.title
                                                           style:_style
                                                         actions:self.actions
                                                           block:^(int index) {
                                                               DLog(@"Outer completion block invoked for announcement %@", self);
                                                               if (!_dismissing) {
                                                                   DLog(@"Invoking inner completion block with index %d", index);
                                                                   self.completion(index);
                                                                   [self dismiss];
                                                               }
                                                               [self release];
                                                           }];
}

- (void)setDismissOnKeyDown:(BOOL)dismissOnKeyDown {
    if (!dismissOnKeyDown || _dismissOnKeyDown) {
        // Because of limitations in the view's implementation this can never be unset.
        return;
    }
    _dismissOnKeyDown = dismissOnKeyDown;
    if (dismissOnKeyDown) {
        [(iTermAnnouncementView *)self.view addDismissOnKeyDownLabel];
    }
}

- (void)dismiss {
    DLog(@"Dismiss announcment %@ from\n%@", self, [NSThread callStackSymbols]);
    if (!_dismissing) {
        _dismissing = YES;
        _visible = NO;
        [(iTermAnnouncementView *)self.view willDismiss];
        self.completion(-2);
        [_delegate announcementWillDismiss:self];
    }
}

- (void)setTimeout:(NSTimeInterval)timeout {
    _timeout = timeout;
    [_timer invalidate];
    _timer = [NSTimer scheduledTimerWithTimeInterval:timeout
                                              target:self
                                            selector:@selector(didTimeout)
                                            userInfo:nil
                                             repeats:NO];
}

- (void)didTimeout {
    _timer = nil;
    [self dismiss];
    _didTimeout = YES;
}

- (BOOL)shouldBecomeVisible {
    return !_didTimeout;
}

- (void)didBecomeVisible {
    _visible = YES;
    if (_timeout) {
        [self setTimeout:_timeout];
    }
}

@end
