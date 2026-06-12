//
//  iTermSplitViewAnimation.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/2/20.
//

#import "iTermSplitViewAnimation.h"

@implementation iTermSplitViewAnimation

- (instancetype)initWithSplitView:(NSSplitView*)splitView
                   dividerAtIndex:(NSInteger)dividerIndex
                             from:(CGFloat)startPosition
                               to:(CGFloat)endPosition
                         duration:(NSTimeInterval)duration
                       completion:(void (^)(void))completion {
    if (self = [super init]) {
        self.splitView = splitView;
        self.dividerIndex = dividerIndex;
        self.startPosition = startPosition;
        self.endPosition = endPosition;
        self.completion = completion;
        self.duration = duration;
        self.animationBlockingMode = NSAnimationNonblocking;
        self.animationCurve = NSAnimationEaseInOut;
        self.frameRate = 60;
    }
    return self;
}

- (void)setCurrentProgress:(NSAnimationProgress)progress {
    [super setCurrentProgress:progress];

    const CGFloat distance = self.endPosition - self.startPosition;
    const CGFloat newPosition = self.startPosition + (distance * progress);

    [self.splitView setPosition:newPosition
               ofDividerAtIndex:self.dividerIndex];

    if (progress == 1.0 && self.completion) {
        self.completion();
    }
}

@end

