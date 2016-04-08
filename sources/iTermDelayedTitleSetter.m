//
//  iTermDelayedTitleSetter.m
//  iTerm2
//
//  Created by George Nachman on 11/15/15.
//
//

#import "iTermDelayedTitleSetter.h"

NSString *const kDelayedTitleSetterSetTitle = @"kDelayedTitleSetterSetTitle";
NSString *const kDelayedTitleSetterTitleKey = @"title";

static const NSTimeInterval kDelay = 0.1;

@interface iTermDelayedTitleSetter()
@property(nonatomic, assign) NSTimer *timer;
@property(nonatomic, copy) NSString *pendingTitle;
@end

@implementation iTermDelayedTitleSetter

- (void)dealloc {
    [_pendingTitle release];
    [super dealloc];
}

- (void)setTitle:(NSString *)title {
    self.pendingTitle = title;
    if (!self.timer) {
        self.timer = [NSTimer scheduledTimerWithTimeInterval:kDelay
                                                      target:self
                                                    selector:@selector(timerDidFire:)
                                                    userInfo:nil
                                                     repeats:NO];
    }
}

- (void)timerDidFire:(NSTimer *)timer {
    self.timer = nil;
    NSString *newTitle = [[self.pendingTitle retain] autorelease];
    self.pendingTitle = nil;
    if (newTitle) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kDelayedTitleSetterSetTitle
                                                            object:self.window
                                                          userInfo:@{ kDelayedTitleSetterTitleKey: newTitle }];
    }
}

@end
