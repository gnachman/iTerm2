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
    [self saveSynchronously:NO];
}

- (void)saveSynchronously {
    [self saveSynchronously:YES];
}

- (void)saveSynchronously:(BOOL)sync {
    DLog(@"save");
    if (_saving) {
        DLog(@"Currently saving. Set needsSave.");
        _needsSave = YES;
        return;
    }
    _needsSave = NO;
    __weak __typeof(self) weakSelf;
    [_saver saveSynchronously:sync withCompletion:^{
        [weakSelf didSave];
    }];
}

// Main queue
- (void)didSave {
    DLog(@"didSave");
    _saving = NO;
    if (_needsSave) {
        DLog(@"needsSave was YES");
        [self save];
    }
}

#pragma mark - Restore

- (void)restoreWithCompletion:(void (^)(void))completion {
    DLog(@"restoreWindows");
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"NSQuitAlwaysKeepsWindows"]) {
        DLog(@"NSQuitAlwaysKeepsWindows=NO");
        completion();
        return;
    }
    id<iTermRestorableStateIndex> index = [self.restorer restorableStateIndex];

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
            completion();
            return;
        }
    }
    [[NSUserDefaults standardUserDefaults] setInteger:count + 1
                                               forKey:iTermRestorableStateControllerUserDefaultsKeyCount];
    _restoring = YES;
    [self reallyRestoreWindows:index withCompletion:^{
        [self didRestoreFromIndex:index];
        completion();
    }];
}

// Main queue
- (void)didRestoreFromIndex:(id<iTermRestorableStateIndex>)index {
    _restoring = NO;
    [[NSUserDefaults standardUserDefaults] setInteger:0
                                               forKey:iTermRestorableStateControllerUserDefaultsKeyCount];
    [index restorableStateIndexUnlink];
}

// Main queue
- (void)reallyRestoreWindows:(id<iTermRestorableStateIndex>)index
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
        _numberOfWindowsRestored += 1;
        dispatch_group_enter(group);
        [self.restorer restoreWindowWithRecord:[index restorableStateRecordAtIndex:i]
                                    completion:^{
            dispatch_group_leave(group);
        }];
    }
}

#pragma mark - Erase

- (void)erase {
    [self.restorer eraseStateRestorationData];
}

@end
