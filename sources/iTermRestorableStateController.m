//
//  iTermRestorableStateController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/18/20.
//

#import "iTermRestorableStateController.h"

#import "DebugLogging.h"
#import "NSFileManager+iTerm.h"
#import "iTermRestorableStateDriver.h"

@interface iTermRestorableStateController()<iTermRestorableStateRestoring>
@end

@implementation iTermRestorableStateController {
    id<iTermRestorableStateSaver> _saver;
    id<iTermRestorableStateRestorer> _restorer;
    iTermRestorableStateDriver *_driver;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        dispatch_queue_t queue = dispatch_queue_create("com.iterm2.restorable-state", DISPATCH_QUEUE_SERIAL);
        NSString *appSupport = [[NSFileManager defaultManager] applicationSupportDirectory];
        NSString *savedState = [appSupport stringByAppendingPathComponent:@"SavedState"];
        NSURL *indexURL = [NSURL fileURLWithPath:[savedState stringByAppendingPathComponent:@"Index.plist"]];
        _saver = [[iTermRestorableStateSaver alloc] initWithQueue:queue indexURL:indexURL];
        iTermRestorableStateRestorer *restorer = [[iTermRestorableStateRestorer alloc] initWithIndexURL:indexURL];
        restorer.delegate = self;
        _restorer = restorer;
        _driver = [[iTermRestorableStateDriver alloc] init];
        _driver.restorer = _restorer;
    }
    return self;
}

#pragma mark - APIs

- (void)setDelegate:(id<iTermRestorableStateControllerDelegate>)delegate {
    _delegate = delegate;
    _saver.delegate = delegate;
}

- (NSInteger)numberOfWindowsRestored {
    return _driver.numberOfWindowsRestored;
}

- (void)saveRestorableState {
    if (_driver.restoring) {
        DLog(@"Currently restoring. Set needsSave.");
        _saver.needsSave = YES;
        return;
    }
    [_saver save];
}

- (void)restoreWindows {
    __weak __typeof(self) weakSelf = self;
    [_driver restoreWithCompletion:^{
        [weakSelf didRestore];
    }];
}

#pragma mark - Private

- (void)didRestore {
    if (_saver.needsSave) {
        [_saver save];
    }
}

#pragma mark - iTermRestorableStateRestoring

- (void)restorableStateRestoreWithCoder:(NSCoder *)coder
                             identifier:(NSString *)identifier
                             completion:(void (^)(NSWindow *, NSError *))completion {
    [self.delegate restorableStateRestoreWithCoder:coder
                                        identifier:identifier
                                        completion:completion];
}


@end
