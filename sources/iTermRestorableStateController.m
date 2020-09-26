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

extern NSString *const iTermApplicationWillTerminate;

@interface iTermRestorableStateController()<iTermRestorableStateRestoring, iTermRestorableStateSaving>
@end

@implementation iTermRestorableStateController {
    id<iTermRestorableStateSaver> _saver;
    id<iTermRestorableStateRestorer> _restorer;
    iTermRestorableStateDriver *_driver;
}

+ (BOOL)stateRestorationEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"NSQuitAlwaysKeepsWindows"];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        dispatch_queue_t queue = dispatch_queue_create("com.iterm2.restorable-state", DISPATCH_QUEUE_SERIAL);
        NSString *appSupport = [[NSFileManager defaultManager] applicationSupportDirectory];
        if (!appSupport) {
            DLog(@"ERROR - No app support directory.");
            return nil;
        }
        NSString *savedState = [appSupport stringByAppendingPathComponent:@"SavedState"];
        [[NSFileManager defaultManager] createDirectoryAtPath:savedState
                                  withIntermediateDirectories:YES
                                                   attributes:@{ NSFilePosixPermissions: @(01700) }
                                                        error:nil];
        [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @(01700) }
                                         ofItemAtPath:savedState
                                                error:nil];

        const BOOL erase = ![iTermRestorableStateController stateRestorationEnabled];
        if ([iTermAdvancedSettingsModel storeStateInSqlite]) {
            NSURL *url = [NSURL fileURLWithPath:[savedState stringByAppendingPathComponent:@"restorable-state.sqlite"]];
            iTermRestorableStateSQLite *sqlite = [[iTermRestorableStateSQLite alloc] initWithURL:url
                                                                                           erase:erase];
            sqlite.delegate = self;
            _saver = sqlite;
            _restorer = sqlite;
        } else {
            NSURL *indexURL = [NSURL fileURLWithPath:[savedState stringByAppendingPathComponent:@"Index.plist"]];
            iTermRestorableStateSaver *saver = [[iTermRestorableStateSaver alloc] initWithQueue:queue indexURL:indexURL];
            _saver = saver;
            saver.delegate = self;

            iTermRestorableStateRestorer *restorer = [[iTermRestorableStateRestorer alloc] initWithIndexURL:indexURL
                                                                                                      erase:erase];
            restorer.delegate = self;
            _restorer = restorer;
        }
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillTerminate:)
                                                     name:iTermApplicationWillTerminate
                                                   object:nil];

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
    assert([NSThread isMainThread]);
    if (![iTermRestorableStateController stateRestorationEnabled]) {
        return;
    }
    if (_driver.restoring) {
        DLog(@"Currently restoring. Set needsSave.");
        _driver.needsSave = YES;
        return;
    }
    [_driver save];
}

- (void)restoreWindowsWithCompletion:(void (^)(void))completion {
    assert([NSThread isMainThread]);
    if (![iTermRestorableStateController stateRestorationEnabled]) {
        completion();
        return;
    }
    __weak __typeof(self) weakSelf = self;
    [_driver restoreWithReady:^{
        [weakSelf.delegate restorableStateDidFinishRequestingRestorations:self];
    }
                   completion:^{
        [weakSelf didRestore];
        completion();
    }];
}

#pragma mark - Private

// NOTE! This is iTermApplicationWillTerminate, not NSApplicationWillTerminateNotification.
// That's important because it runs while iTermController still exists.
- (void)applicationWillTerminate:(NSNotification *)notification {
    DLog(@"application will terminate");
    if (![iTermRestorableStateController stateRestorationEnabled]) {
        DLog(@"State restoration disabled. Erase state.");
        [_driver erase];
        return;
    }
    if (_driver.restoring) {
        DLog(@"Still restoring so don't save");
        return;
    }
    DLog(@"Calling saveSynchronously.");
    [_driver saveSynchronously];
    _driver = nil;
}
 
- (void)didRestore {
    assert([NSThread isMainThread]);
    if (![iTermRestorableStateController stateRestorationEnabled]) {
        return;
    }
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
                              completion:(nonnull void (^)(NSWindow *,
                                                           NSError *))completion {
    [self.delegate restorableStateRestoreWithRecord:record
                                         identifier:identifier
                                         completion:completion];
}

- (void)restorableStateRestoreApplicationStateWithRecord:(nonnull iTermEncoderGraphRecord *)record {
    [self.delegate restorableStateRestoreApplicationStateWithRecord:record];
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
