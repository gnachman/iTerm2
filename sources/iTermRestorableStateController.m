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
#import "iTermUserDefaults.h"

static BOOL gShouldIgnoreOpenUntitledFile;
extern NSString *const iTermApplicationWillTerminate;

@interface NSApplication(Private)
// This is true when "System Prefs > Desktop & Dock > Close windows when quitting an
// app" is on but you choose to log out/restart and turn on the "restore
// windows when logging back in" checkbox. That checkbox supercedes the "close
// windows when quitting an app" setting. I discovered this private API by
// reversing -[NSApplication(NSAppleEventHandling) _handleAEQuit], which is
// called when closing apps after logging out.
- (BOOL)shouldRestoreStateOnNextLaunch;
@end

@interface iTermRestorableStateController()<iTermRestorableStateRestoring, iTermRestorableStateSaving>
@end

@implementation iTermRestorableStateController {
    id<iTermRestorableStateSaver> _saver;
    id<iTermRestorableStateRestorer> _restorer;
    iTermRestorableStateDriver *_driver;
    BOOL _ready;
    NSMutableDictionary<NSString *, void (^)(NSWindow *, NSError *)> *_systemCallbacks;
    dispatch_group_t _completionGroup;
}

+ (BOOL)shouldIgnoreOpenUntitledFile {
    return gShouldIgnoreOpenUntitledFile;
}

+ (void)setShouldIgnoreOpenUntitledFile:(BOOL)value {
    gShouldIgnoreOpenUntitledFile = value;
}


+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static id instance;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

+ (BOOL)stateRestorationEnabled {
    return ([[NSUserDefaults standardUserDefaults] boolForKey:@"NSQuitAlwaysKeepsWindows"] ||
            [self shouldRestoreStateOnNextLaunch]);
}

+ (BOOL)shouldRestoreStateOnNextLaunch {
    return self.forceSaveState || [NSApp shouldRestoreStateOnNextLaunch];
}

static BOOL gForceSaveState;

+ (BOOL)forceSaveState {
    return gForceSaveState;
}

+ (void)setForceSaveState:(BOOL)forceSaveState {
    gForceSaveState = forceSaveState;
    [[NSUserDefaults standardUserDefaults] setBool:forceSaveState forKey:@"NoSyncWindowRestoresWorkspaceAtLaunch"];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _systemCallbacks = [NSMutableDictionary dictionary];
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

        // NOTE: I used to erase state at this point if window restoration was globally disabled,
        // but doing so breaks restoring state when logging back in. See the comment on
        // shouldRestoreStateOnNextLaunch above.
        if ([iTermAdvancedSettingsModel storeStateInSqlite]) {
            NSURL *url = [NSURL fileURLWithPath:[savedState stringByAppendingPathComponent:@"restorable-state.sqlite"]];
            iTermRestorableStateSQLite *sqlite = [[iTermRestorableStateSQLite alloc] initWithURL:url
                                                                                           erase:NO];
            sqlite.delegate = self;
            _saver = sqlite;
            _restorer = sqlite;
        } else {
            NSURL *indexURL = [NSURL fileURLWithPath:[savedState stringByAppendingPathComponent:@"Index.plist"]];
            iTermRestorableStateSaver *saver = [[iTermRestorableStateSaver alloc] initWithQueue:queue indexURL:indexURL];
            _saver = saver;
            saver.delegate = self;

            iTermRestorableStateRestorer *restorer = [[iTermRestorableStateRestorer alloc] initWithIndexURL:indexURL
                                                                                                      erase:NO];
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
    if (!_ready) {
        DLog(@"Still initializing. Set needsSave.");
        _driver.needsSave = YES;
        return;
    }
    [_driver save];
}

// NOTE: Window restoration happens unconditionally. The decision of whether to use state
// restoration must be made before state is *saved* not before it is restored. See the comment on
// shouldRestoreStateOnNextLaunch above.
- (void)restoreWindowsWithCompletion:(void (^)(void))completion {
    _completionGroup = dispatch_group_create();
    dispatch_group_enter(_completionGroup);
    assert([NSThread isMainThread]);
    __weak __typeof(self) weakSelf = self;
    [_driver restoreWithSystemCallbacks:_systemCallbacks
                                  ready:^{
        [weakSelf.delegate restorableStateDidFinishRequestingRestorations:self];
    }
                             completion:^{
        DLog(@"Restoration did complete");
        [weakSelf completeInitialization];
        completion();
    }];
}

- (void)didSkipRestoration {
    DLog(@"did skip restoration");
    [self completeInitialization];
}

- (void)setSystemRestorationCallback:(void (^)(NSWindow *, NSError *))callback
                    windowIdentifier:(NSString *)windowIdentifier {
    if (_ready) {
        DLog(@"Unexpected window restoration call with id %@", windowIdentifier);
        callback(nil, nil);
        return;
    }
    _systemCallbacks[windowIdentifier] = [callback copy];
}

#pragma mark - Private

// NOTE! This is iTermApplicationWillTerminate, not NSApplicationWillTerminateNotification.
// That's important because it runs while iTermController still exists. Also, it's actually
// called from applicationShouldTerminate because waiting until willTerminate is too late - the
// windows have already been closed.
- (void)applicationWillTerminate:(NSNotification *)notification {
    DLog(@"application will terminate");
    if (![iTermRestorableStateController stateRestorationEnabled]) {
        DLog(@"State restoration disabled. Erase state.");
        [_driver eraseSynchronously:YES];
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

// All restoration activities (if any) are complete and it's now save to save to the db.
- (void)completeInitialization {
    DLog(@"completeInitialization");
    assert([NSThread isMainThread]);
    _ready = YES;
    dispatch_group_leave(_completionGroup);
    if (![iTermRestorableStateController stateRestorationEnabled]) {
        // Just in case we don't get a chance to erase the state later.
        DLog(@"State restoration is disabled so erase db");
        [_driver eraseSynchronously:NO];
    } else if (_driver.needsSave) {
        [_driver save];
    }
    [self invokeRemainingCompletionBlocksAsFailure];
}

// Run system callbacks that were never married up to windows as failures.
- (void)invokeRemainingCompletionBlocksAsFailure {
    NSMutableDictionary<NSString *, void (^)(NSWindow *, NSError *)> *temp = [_systemCallbacks copy];
    [_systemCallbacks removeAllObjects];

    iTermRestorableStateController.shouldIgnoreOpenUntitledFile = YES;
    [temp enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull windowIdentifier, void (^ _Nonnull completion)(NSWindow *, NSError *), BOOL * _Nonnull stop) {
        DLog(@"Running system callback with nil for %@", windowIdentifier);
        completion(nil, nil);
    }];
    iTermRestorableStateController.shouldIgnoreOpenUntitledFile = NO;
}

#pragma mark - iTermRestorableStateRestoring

- (void)restorableStateRestoreWithCoder:(NSCoder *)coder
                             identifier:(NSString *)identifier
                             completion:(void (^)(NSWindow *, NSError *))completion {
    [self.delegate restorableStateRestoreWithCoder:coder
                                        identifier:identifier
                                        completion:^(NSWindow * _Nullable window, NSError * _Nullable error) {
        completion(window, error);
        [self didRestoreWindow:window];
    }];
}

- (void)restorableStateRestoreWithRecord:(nonnull iTermEncoderGraphRecord *)record
                              identifier:(nonnull NSString *)identifier
                              completion:(nonnull void (^)(NSWindow *,
                                                           NSError *))completion {
    [self.delegate restorableStateRestoreWithRecord:record
                                         identifier:identifier
                                         completion:^(NSWindow * _Nullable window, NSError * _Nullable error) {
        DLog(@"iTermRestorableStateController's completion block calling the completion block for window %@", window);
        completion(window, error);
        DLog(@"iTermRestorableStateController's completion block calling didRestoreWindow:%@", window);
        __weak __typeof(window) weakWindow = window;
        dispatch_group_notify(self->_completionGroup, dispatch_get_main_queue(), ^{
            __strong __typeof(window) strongWindow = weakWindow;
            if (strongWindow) {
                [self didRestoreWindow:strongWindow];
            }
        });
        DLog(@"iTermRestorableStateController's completion block returning");
    }];
}

- (void)restorableStateRestoreApplicationStateWithRecord:(nonnull iTermEncoderGraphRecord *)record {
    [self.delegate restorableStateRestoreApplicationStateWithRecord:record];
}

- (void)didRestoreWindow:(NSWindow *)window {
    if (![window.delegate conformsToProtocol:@protocol(iTermRestorableWindowController)]) {
        return;
    }
    id<iTermRestorableWindowController> controller = (id<iTermRestorableWindowController>)[window delegate];
    [controller didFinishRestoringWindow];
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
