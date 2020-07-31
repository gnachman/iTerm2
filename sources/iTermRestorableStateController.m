//
//  iTermRestorableStateController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/18/20.
//

#import "iTermRestorableStateController.h"

#import "DebugLogging.h"
#import "NSFileManager+iTerm.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermRestorableStateDriver.h"
#import "iTermRestorableStateSQLite.h"

@interface iTermRestorableStateController()<iTermRestorableStateRestoring, iTermRestorableStateSaving>
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

        if ([iTermAdvancedSettingsModel storeStateInSqlite]) {
            NSURL *url = [NSURL fileURLWithPath:[savedState stringByAppendingPathComponent:@"restorable-state.sqlite"]];
            iTermRestorableStateSQLite *sqlite = [[iTermRestorableStateSQLite alloc] initWithURL:url];
            sqlite.delegate = self;
            _saver = sqlite;
            _restorer = sqlite;
        } else {
            NSURL *indexURL = [NSURL fileURLWithPath:[savedState stringByAppendingPathComponent:@"Index.plist"]];
            iTermRestorableStateSaver *saver = [[iTermRestorableStateSaver alloc] initWithQueue:queue indexURL:indexURL];
            _saver = saver;
            saver.delegate = self;

            iTermRestorableStateRestorer *restorer = [[iTermRestorableStateRestorer alloc] initWithIndexURL:indexURL];
            restorer.delegate = self;
            _restorer = restorer;
        }
        _driver = [[iTermRestorableStateDriver alloc] init];
        _driver.restorer = _restorer;
        _driver.saver = _saver;
    }
    return self;
}

#pragma mark - APIs

- (NSInteger)numberOfWindowsRestored {
    return _driver.numberOfWindowsRestored;
}

- (void)saveRestorableState {
    if (_driver.restoring) {
        DLog(@"Currently restoring. Set needsSave.");
        _driver.needsSave = YES;
        return;
    }
    [_driver save];
}

- (void)restoreWindows {
    __weak __typeof(self) weakSelf = self;
    [_driver restoreWithCompletion:^{
        [weakSelf didRestore];
    }];
}

#pragma mark - Private

- (void)didRestore {
    if (_driver.needsSave) {
        [_driver save];
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

- (void)restorableStateRestoreWithRecord:(nonnull iTermEncoderGraphRecord *)record
                              identifier:(nonnull NSString *)identifier
                              completion:(nonnull void (^)(NSWindow * _Nonnull,
                                                           NSError * _Nonnull))completion {
    [self.delegate restorableStateRestoreWithRecord:record
                                         identifier:identifier
                                         completion:completion];
}


#pragma mark - iTermRestorableStateSaving

- (NSArray<NSWindow *> *)restorableStateWindows {
    return [self.delegate restorableStateWindows];
}

- (BOOL)restorableStateWindowNeedsRestoration:(NSWindow *)window {
    return [self.delegate restorableStateWindowNeedsRestoration:window];
}

- (void)restorableStateEncodeWithCoder:(NSCoder *)coder
                                window:(NSWindow *)window {
    return [self.delegate restorableStateEncodeWithCoder:coder window:window];
}

@end
