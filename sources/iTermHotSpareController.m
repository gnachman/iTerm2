//
//  iTermHotSpareController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/5/20.
//

#import "iTermHotSpareController.h"
#import "NSTimer+iTerm.h"

@interface iTermClientServerProtocolMessageBox(HotSpare)
- (BOOL)matchesLaunchRequest:(const iTermMultiServerRequestLaunch *)launchRequest;
@end

@implementation iTermClientServerProtocolMessageBox(HotSpare)

static BOOL TwoDimensionalArraysEqual(const char **lhs, int ln,
                                      const char **rhs, int rn) {
    if (ln != rn) {
        return NO;
    }
    for (int i = 0; i < ln; i++) {
        if (strcmp(lhs[i], rhs[i])) {
            return NO;
        }
    }
    return YES;
}

#warning TODO: Environment differs in many ways. ITERM2_COOKIE, LANG, LC_CTYPE, LC_TERMINAL_VERSION, TERM_SESSION_ID, ITERM_SESSION_ID, and perhaps more. We need a way to set the environment in hot spares after they launch.
- (BOOL)matchesLaunchRequest:(const iTermMultiServerRequestLaunch *)launchRequest {
    const iTermMultiServerReportChild mine = self.decoded->payload.reportChild;
    return (!strcmp(mine.path, launchRequest->path) &&
            TwoDimensionalArraysEqual(mine.argv, mine.argc, launchRequest->argv, launchRequest->argc) &&
            mine.isUTF8 == launchRequest->isUTF8 &&
            !strcmp(mine.pwd, launchRequest->pwd));
}

@end

@implementation iTermHotSpareController {
    NSMutableArray<iTermClientServerProtocolMessageBox *> *_available;
    iTermClientServerProtocolMessageBox *_lastLaunch;
    BOOL _creatingHotSpare;
}

+ (void)restartTimerWithTarget:(id)target {
    dispatch_async(dispatch_get_main_queue(), ^{
        static NSTimer *timer;
        [timer invalidate];
        timer = [NSTimer scheduledWeakTimerWithTimeInterval:10 target:target selector:@selector(maybeCreateHotSpare) userInfo:nil repeats:NO];
    });
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue {
    self = [super init];
    if (self) {
        _queue = queue;
        _available = [NSMutableArray array];
    }
    return self;
}

- (void)addHotSpareWithChildReport:(iTermMultiServerReportChild)report {
    [_available addObject:[iTermClientServerProtocolMessageBox withChildReport:&report]];
    NSLog(@"addHotSpareWithChildReport: available is now %@", @(_available.count));
}

- (BOOL)requestHotSpareForLaunchRequest:(const iTermMultiServerRequestLaunch *)launchRequest
                                handler:(void (^ NS_NOESCAPE)(iTermMultiServerReportChild))handler {
    const NSInteger index = [_available indexOfObjectPassingTest:^BOOL(iTermClientServerProtocolMessageBox * _Nonnull box,
                                                                       NSUInteger idx,
                                                                       BOOL * _Nonnull stop) {
        return [box matchesLaunchRequest:launchRequest];
    }];
    if (index == NSNotFound) {
#warning TODO: Kill it and make a new one if there was a mismatch.
        NSLog(@"requestHotSpare failing. Have %@ available", @(_available.count));
        return NO;
    }
    NSLog(@"requestHotSpare found a spare, using it.");
    iTermClientServerProtocolMessageBox *box = _available[index];
    [_available removeObjectAtIndex:index];
    handler(box.decoded->payload.reportChild);
    if (_available.count == 0) {
        [self reallyCreateHotSpare];
    }
    return YES;
}

- (void)didLaunchRegularChildWithReport:(iTermMultiServerReportChild)report {
    _lastLaunch = [iTermClientServerProtocolMessageBox withChildReport:&report];
    [self rescheduleIdleTimerIfNeeded];
}

- (void)rescheduleIdleTimerIfNeeded {
    if (_available.count > 0) {
        return;
    }
    [self.class restartTimerWithTarget:self];
}

- (void)maybeCreateHotSpare {
    assert([NSThread isMainThread]);
    dispatch_async(_queue, ^{
        if (self->_available.count > 0) {
            return;
        }
        [self reallyCreateHotSpare];
    });
}

- (void)reallyCreateHotSpare {
    if (_creatingHotSpare || !_lastLaunch) {
        NSLog(@"reallyCreateHotSpare: already creating or no last launch");
        return;
    }
    __weak __typeof(self) weakSelf = self;
    _creatingHotSpare = YES;
    NSLog(@"reallyCreateHotSpare: will create");
    [self.delegate hotSpareControllerCreateHotSpare:self
                                             report:_lastLaunch
                                         completion:^{
        [weakSelf finishedCreatingHotSpare];
    }];
}

- (void)finishedCreatingHotSpare {
    NSLog(@"reallyCreateHotSpare: finished. available is now %@", @(_available.count));
    _creatingHotSpare = NO;
}

@end
