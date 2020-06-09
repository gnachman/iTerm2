//
//  iTermRestorableStateController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/18/20.
//

#import "iTermRestorableStateController.h"

#import "DebugLogging.h"
#import "iTermRestorableStateRecord.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSData+iTerm.h"
#import "NSFileManager+iTerm.h"

#import <AppKit/AppKit.h>
#import <CommonCrypto/CommonCryptor.h>
#include <sys/types.h>
#include <sys/stat.h>

static NSString *const iTermRestorableStateControllerUserDefaultsKeyCount = @"NoSyncRestoreWindowsCount";

@implementation iTermRestorableStateController {
    dispatch_queue_t _queue;
    BOOL _restoring;
    BOOL _needsSave;
    NSArray<iTermRestorableStateRecord *> *_records;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.iterm2.restorable-state", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - APIs

- (void)saveRestorableState {
    if (_restoring) {
        _needsSave = YES;
        return;
    }
    _needsSave = NO;
    
    NSMutableArray<iTermRestorableStateRecord *> *recordsToKeepUnchanged = [NSMutableArray array];
    NSMutableArray<iTermRestorableStateRecord *> *recordsNeedingNewContent = [NSMutableArray array];
    for (NSWindow *window in [self.delegate restorableStateControllerWindows:self]) {
        iTermRestorableStateRecord *record = [_records objectPassingTest:^BOOL(iTermRestorableStateRecord *element, NSUInteger index, BOOL *stop) {
            return element.windowNumber == window.windowNumber;
        }];
        const BOOL needsRestoration = [self.delegate restorableStateController:self
                                                        windowNeedsRestoration:window];
        if (record && needsRestoration) {
            [recordsToKeepUnchanged addObject:record];
            continue;
        }
        if (!needsRestoration) {
            continue;
        }
        assert(!record);
        
        NSData *plaintext = [self restorableStateForWindow:window];
        if (!plaintext) {
            continue;
        }

        record = [[iTermRestorableStateRecord alloc] initWithWindowNumber:window.windowNumber
                                                               identifier:window.identifier
                                                                      key:[NSData randomAESKey]
                                                                plaintext:plaintext];
        [recordsNeedingNewContent addObject:record];
    }
    dispatch_async(_queue, ^{
        NSArray<NSURL *> *fileURLsToKeep = [[recordsToKeepUnchanged arrayByAddingObjectsFromArray:recordsNeedingNewContent] mapWithBlock:^id(iTermRestorableStateRecord *record) {
            return record.url;
        }];
        fileURLsToKeep = [fileURLsToKeep arrayByAddingObject:[self urlForIndex]];
        [self eraseFilesExcept:fileURLsToKeep];
        [self encryptAndSaveUnchangedRecords:recordsToKeepUnchanged
                              updatedRecords:recordsNeedingNewContent];
    });
}

- (BOOL)haveWindowsToRestore {
    NSURL *indexURL = [self urlForIndex];
    return [[NSFileManager defaultManager] fileExistsAtPath:indexURL.path];
}

- (void)restoreWindows {
    NSArray *index = [self indexOfRestorableWindowsFromDisk];
    if (!index.count) {
        [self didRestore];
        return;
    }
    const NSInteger count = [[NSUserDefaults standardUserDefaults] integerForKey:iTermRestorableStateControllerUserDefaultsKeyCount];
    if (count > 1) {
        const iTermWarningSelection selection =
        [iTermWarning showWarningWithTitle:@"Some windows had trouble restoring last time iTerm2 launched. Try again?"
                                   actions:@[ @"OK", @"Cancel" ]
                                 accessory:nil
                                identifier:@"RestoreFullScreenWindowS"
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Restore Full Screen Windows?"
                                    window:nil];
        if (selection == kiTermWarningSelection1) {
            unlink([self urlForIndex].path.UTF8String);
            [[NSUserDefaults standardUserDefaults] setInteger:0
                                                       forKey:iTermRestorableStateControllerUserDefaultsKeyCount];
            return;
        }
    }
    [[NSUserDefaults standardUserDefaults] setInteger:count + 1
                                               forKey:iTermRestorableStateControllerUserDefaultsKeyCount];
    _restoring = YES;
    [self reallyRestoreWindows:index withCompletion:^{
        [self didRestore];
    }];
}

#pragma mark - Save

// _queue
- (void)eraseFilesExcept:(NSArray<NSURL *> *)fileURLsToKeep {
    NSString *appSupport = [[NSFileManager defaultManager] applicationSupportDirectoryWithoutSpacesWithoutCreatingSymlink];
    NSString *savedState = [appSupport stringByAppendingPathComponent:@"SavedState"];
    NSDirectoryEnumerator *enumerator =
    [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:savedState] includingPropertiesForKeys:nil
                                            options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
                                       errorHandler:nil];
    for (NSURL *url in enumerator) {
        if ([fileURLsToKeep containsObject:url]) {
            continue;
        }
        unlink(url.path.UTF8String);
    }
}

- (NSData *)restorableStateForWindow:(NSWindow *)window {
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *coder = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    coder.outputFormat = NSPropertyListBinaryFormat_v1_0;
    [self.delegate restorableStateController:self encodeWithCoder:coder window:window];
    [coder finishEncoding];

    return data;
}

// Runs on _queue
- (void)encryptAndSaveUnchangedRecords:(NSArray<iTermRestorableStateRecord *> *)recordsToKeepUnchanged
                        updatedRecords:(NSArray<iTermRestorableStateRecord *> *)recordsNeedingNewContent {
    NSMutableArray *plist = [NSMutableArray new];
    [recordsNeedingNewContent enumerateObjectsUsingBlock:^(iTermRestorableStateRecord * _Nonnull record, NSUInteger idx, BOOL * _Nonnull stop) {
        [record save];
        [plist addObject:record.indexEntry];
    }];
    [recordsToKeepUnchanged enumerateObjectsUsingBlock:^(iTermRestorableStateRecord * _Nonnull record, NSUInteger idx, BOOL * _Nonnull stop) {
        [plist addObject:record.indexEntry];
    }];
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                   format:NSPropertyListXMLFormat_v1_0
                                                                  options:NSPropertyListImmutable
                                                                    error:nil];
    [plistData writeReadOnlyToURL:[self urlForIndex]];
}

#pragma mark - Restore

- (NSArray *)indexOfRestorableWindowsFromDisk {
    NSURL *indexURL = [self urlForIndex];
    NSArray *index = [NSArray arrayWithContentsOfURL:indexURL];
    return index;
}

- (void)reallyRestoreWindows:(NSArray *)index withCompletion:(void (^)(void))completion {
    // When all windows have finished being restored, mark the restoration as a success.
    dispatch_group_t group = dispatch_group_create();
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            completion();
        });
    });

    for (id obj in index) {
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
    @try {
        NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:record.plaintext];
        [self.delegate restorableStateController:self
                                restoreWithCoder:unarchiver
                                      identifier:record.identifier
                                      completion:^(NSWindow * _Nonnull window, NSError * _Nonnull error) {
            if ([window.delegate respondsToSelector:@selector(window:didDecodeRestorableState:)]) {
                [window.delegate window:window didDecodeRestorableState:unarchiver];
            }
            [unarchiver finishDecoding];
            completion();
        }];
    } @catch (NSException *exception) {
        DLog(@"Restoration failed with %@", exception);
    }
}

- (void)didRestore {
    _restoring = NO;
    [[NSUserDefaults standardUserDefaults] setInteger:0
                                               forKey:iTermRestorableStateControllerUserDefaultsKeyCount];
    unlink([self urlForIndex].path.UTF8String);
    if (_needsSave) {
        [self saveRestorableState];
    }
}

#pragma mark - Common

- (NSURL *)urlForIndex {
    NSString *appSupport = [[NSFileManager defaultManager] applicationSupportDirectoryWithoutSpacesWithoutCreatingSymlink];
    NSString *savedState = [appSupport stringByAppendingPathComponent:@"SavedState"];
    return [NSURL fileURLWithPath:[savedState stringByAppendingPathComponent:@"Index.plist"]];
}

@end
