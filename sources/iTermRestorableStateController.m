//
//  iTermRestorableStateController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/18/20.
//

#import "iTermRestorableStateController.h"

#import "DebugLogging.h"
#import "NSFileManager+iTerm.h"

@implementation iTermRestorableStateController {
    iTermRestorableStateSaver *_saver;
    iTermRestorableStateRestorer *_restorer;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        dispatch_queue_t queue = dispatch_queue_create("com.iterm2.restorable-state", DISPATCH_QUEUE_SERIAL);
        NSString *appSupport = [[NSFileManager defaultManager] applicationSupportDirectory];
        NSString *savedState = [appSupport stringByAppendingPathComponent:@"SavedState"];
        NSURL *indexURL = [NSURL fileURLWithPath:[savedState stringByAppendingPathComponent:@"Index.plist"]];
        _saver = [[iTermRestorableStateSaver alloc] initWithQueue:queue indexURL:indexURL];
        _restorer = [[iTermRestorableStateRestorer alloc] initWithQueue:queue indexURL:indexURL];
    }
    return self;
}

#pragma mark - APIs

- (void)setDelegate:(id<iTermRestorableStateControllerDelegate>)delegate {
    _delegate = delegate;
    _saver.delegate = delegate;
    _restorer.delegate = delegate;
}

- (NSInteger)numberOfWindowsRestored {
    return _restorer.numberOfWindowsRestored;
}

- (void)saveRestorableState {
    if (_restorer.restoring) {
        DLog(@"Currently restoring. Set needsSave.");
        _saver.needsSave = YES;
        return;
    }
    [_saver save];
}

- (void)restoreWindows {
    __weak __typeof(self) weakSelf = self;
    [_restorer restoreWithCompletion:^{
        [weakSelf didRestore];
    }];
}

#pragma mark - Private

- (void)didRestore {
    if (_saver.needsSave) {
        [_saver save];
    }
}

@end
