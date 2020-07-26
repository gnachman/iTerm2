//
//  iTermRestorableStateRestorer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/26/20.
//

#import "iTermRestorableStateRestorer.h"

#import "DebugLogging.h"
#import "iTermRestorableStateRecord.h"
#import "iTermWarning.h"
#include <sys/types.h>
#include <sys/stat.h>

static NSString *const iTermRestorableStateControllerUserDefaultsKeyCount = @"NoSyncRestoreWindowsCount";

@implementation iTermRestorableStateRestorer

- (instancetype)initWithQueue:(dispatch_queue_t)queue
                     indexURL:(NSURL *)indexURL {
    self = [super init];
    if (self) {
        _queue = queue;
        _indexURL = [indexURL copy];
    }
    return self;
}

- (void)restoreWithCompletion:(void (^)(void))completion {
    DLog(@"restoreWindows");
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"NSQuitAlwaysKeepsWindows"]) {
        DLog(@"NSQuitAlwaysKeepsWindows=NO");
        completion();
        return;
    }
    NSArray *index = [self indexOfRestorableWindowsFromDisk];
    if (!index.count) {
        [self didRestore];
        completion();
        return;
    }
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
            unlink(_indexURL.path.UTF8String);
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
        [self didRestore];
        completion();
    }];
}

#pragma mark - Private

- (NSArray *)indexOfRestorableWindowsFromDisk {
    NSArray *index = [NSArray arrayWithContentsOfURL:_indexURL];
    return index;
}

// Main queue
- (void)didRestore {
    _restoring = NO;
    [[NSUserDefaults standardUserDefaults] setInteger:0
                                               forKey:iTermRestorableStateControllerUserDefaultsKeyCount];
    unlink(_indexURL.path.UTF8String);
}

- (void)reallyRestoreWindows:(NSArray *)index withCompletion:(void (^)(void))completion {
    // When all windows have finished being restored, mark the restoration as a success.
    dispatch_group_t group = dispatch_group_create();
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            completion();
        });
    });
    DLog(@"Have index:\n%@", index);
    for (id obj in index) {
        _numberOfWindowsRestored += 1;
        iTermRestorableStateRecord * _Nonnull record = [[iTermRestorableStateRecord alloc] initWithIndexEntry:obj];
        dispatch_group_enter(group);
        [self restoreRecord:record completion:^{
            unlink(record.url.path.UTF8String);
            dispatch_group_leave(group);
        }];
    }
}

- (void)restoreRecord:(iTermRestorableStateRecord *)record
           completion:(void (^)(void))completion {
    DLog(@"Restore %@", @(record.windowNumber));
    NSError *error = nil;
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:record.plaintext
                                                                                error:&error];
    unarchiver.requiresSecureCoding = NO;
    if (error) {
        DLog(@"Restoration failed with %@", error);
        completion();
        return;
    }
    [self.delegate restorableStateRestoreWithCoder:unarchiver
                                        identifier:record.identifier
                                        completion:^(NSWindow * _Nonnull window, NSError * _Nonnull error) {
        if ([window.delegate respondsToSelector:@selector(window:didDecodeRestorableState:)]) {
            [window.delegate window:window didDecodeRestorableState:unarchiver];
        }
        [unarchiver finishDecoding];
        completion();
    }];
}

@end
