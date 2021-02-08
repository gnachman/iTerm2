//
//  iTermRestorableStateDriver.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import "iTermRestorableStateDriver.h"

#import "DebugLogging.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"

static NSString *const iTermRestorableStateControllerUserDefaultsKeyCount = @"NoSyncRestoreWindowsCount";

@implementation iTermRestorableStateDriver {
    BOOL _saving;
}

#pragma mark - Save

- (void)save {
    assert([NSThread isMainThread]);
    [self saveSynchronously:NO];
}

- (void)saveSynchronously {
    assert([NSThread isMainThread]);
    [self saveSynchronously:YES];
}

- (void)saveSynchronously:(BOOL)sync {
    assert([NSThread isMainThread]);
    DLog(@"save sync=%@ saver=%@", @(sync), _saver);
    if (_saving) {
        DLog(@"Currently saving. Set needsSave.");
        _needsSave = YES;
        return;
    }
    __weak __typeof(self) weakSelf = self;
    const BOOL saved = [_saver saveSynchronously:sync withCompletion:^{
        [weakSelf didSave];
    }];
    // Do this after saveSynchronously:withCompletion:. It guarantees not to run its completion block
    // synchronously. It could fail if it was already busy saving, in which case we don't want
    // to reset _needsSave. Considering it is busy, the other guy will eventually finish and cause
    // didSave to be called, and it will try again.
    _needsSave = !saved;
}

// Main queue
- (void)didSave {
    assert([NSThread isMainThread]);
    DLog(@"didSave");
    _saving = NO;
    if (_needsSave) {
        DLog(@"needsSave was YES");
        [self save];
    }
}

#pragma mark - Restore

- (void)restoreWithSystemCallbacks:(NSMutableDictionary<NSString *, void (^)(NSWindow *, NSError *)> *)callbacks
                             ready:(void (^)(void))ready
                        completion:(void (^)(void))completion {
    DLog(@"restoreWindows");
    if (!self.restorer) {
        DLog(@"Have no restorer.");
        ready();
        completion();
        return;
    }
    __weak __typeof(self) weakSelf = self;
    DLog(@"Loading restorable state index…");
    [self.restorer loadRestorableStateIndexWithCompletion:^(id<iTermRestorableStateIndex> index) {
        [weakSelf restoreWithIndex:index callbacks:callbacks ready:ready completion:completion];
    }];
}

- (void)restoreWithIndex:(id<iTermRestorableStateIndex>)index
               callbacks:(NSMutableDictionary<NSString *, void (^)(NSWindow *, NSError *)> *)callbacks
                   ready:(void (^)(void))ready
              completion:(void (^)(void))completion {
    DLog(@"Have an index. Proceeding to restore windows.");
    const NSInteger count = [[NSUserDefaults standardUserDefaults] integerForKey:iTermRestorableStateControllerUserDefaultsKeyCount];
    if (count > 1) {
        const iTermWarningSelection selection =
        [iTermWarning showWarningWithTitle:@"Some windows had trouble restoring last time iTerm2 launched. Try again?"
                                   actions:@[ @"OK", @"Cancel" ]
                                 accessory:nil
                                identifier:@"RestoreWindows"
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Restore Windows?"
                                    window:nil];
        if (selection == kiTermWarningSelection1) {
            [index restorableStateIndexUnlink];
            [[NSUserDefaults standardUserDefaults] setInteger:0
                                                       forKey:iTermRestorableStateControllerUserDefaultsKeyCount];
            DLog(@"Ready after warning");
            ready();
            completion();
            return;
        }
    }
    [[NSUserDefaults standardUserDefaults] setInteger:count + 1
                                               forKey:iTermRestorableStateControllerUserDefaultsKeyCount];
    DLog(@"set restoring to YES");
    _restoring = YES;
    [self reallyRestoreWindows:index callbacks:callbacks withCompletion:^{
        [self didRestoreFromIndex:index];
        completion();
    }];
    DLog(@"Ready - normal case");
    ready();
}

// Main queue
- (void)didRestoreFromIndex:(id<iTermRestorableStateIndex>)index {
    DLog(@"set restoring to NO");
    _restoring = NO;
    [[NSUserDefaults standardUserDefaults] setInteger:0
                                               forKey:iTermRestorableStateControllerUserDefaultsKeyCount];
    [index restorableStateIndexUnlink];
}

// Main queue
- (void)reallyRestoreWindows:(id<iTermRestorableStateIndex>)index
                   callbacks:(NSMutableDictionary<NSString *, void (^)(NSWindow *, NSError *)> *)callbacks
              withCompletion:(void (^)(void))completion {
    [self.restorer restoreApplicationState];

    const NSInteger count = [index restorableStateIndexNumberOfWindows];

    // When all windows have finished being restored, mark the restoration as a success.
    dispatch_group_t group = dispatch_group_create();
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            for (NSInteger i = 0; i < count; i++) {
                [[index restorableStateRecordAtIndex:i] didFinishRestoring];
            }
            completion();
        });
    });
    DLog(@"Restoring from index:\n%@", index);
    for (NSInteger i = 0; i < count; i++) {
        DLog(@"driver: restore window number %@", @(i));
        _numberOfWindowsRestored += 1;
        dispatch_group_enter(group);
        [self.restorer restoreWindowWithRecord:[index restorableStateRecordAtIndex:i]
                                    completion:^(NSString *windowIdentifier, NSWindow *window) {
            DLog(@"driver: restoration of window number %@ with identifier %@ finished", @(i), windowIdentifier);
            if (windowIdentifier) {
                void (^callback)(NSWindow *, NSError *) = callbacks[windowIdentifier];
                if (callback) {
                    DLog(@"Restorable state driver: Invoke callback callback with window %@", window);
                    [callbacks removeObjectForKey:windowIdentifier];
                    callback(window, nil);
                    DLog(@"Restorable state driver: Returned from callback callback with window %@", window);
                } else {
                    DLog(@"No callback");
                }
            }
            dispatch_group_leave(group);
        }];
    }
}

#pragma mark - Erase

- (void)eraseSynchronously:(BOOL)sync {
    [self.restorer eraseStateRestorationDataSynchronously:sync];
}

@end
