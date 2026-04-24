//
//  iTermRestorableStateRestorer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/26/20.
//

#import "iTermRestorableStateRestorer.h"

#import "DebugLogging.h"
#import "NSObject+iTerm.h"
#import "iTermRestorableStateRecord.h"
#include <sys/types.h>
#include <sys/stat.h>

@interface iTermRestorableStateRestorerIndex: NSObject<iTermRestorableStateIndex>
@property (nonatomic, readonly) NSArray<NSDictionary *> *entries;
@property (nonatomic, readonly) NSURL *url;
@end

@implementation iTermRestorableStateRestorerIndex

- (instancetype)initWithURL:(NSURL *)url {
    self = [super init];
    if (self) {
        _url = url;
        _entries = [NSArray arrayWithContentsOfURL:url];
    }
    return self;
}

- (NSUInteger)restorableStateIndexNumberOfWindows {
    return _entries.count;
}

- (void)restorableStateIndexUnlink {
    unlink(_url.path.UTF8String);
}

- (id<iTermRestorableStateRecord>)restorableStateRecordAtIndex:(NSUInteger)i {
    return [[iTermRestorableStateRecord alloc] initWithIndexEntry:_entries[i]];
}

@end

@implementation iTermRestorableStateRestorer

- (instancetype)initWithIndexURL:(NSURL *)indexURL erase:(BOOL)erase {
    self = [super init];
    if (self) {
        _indexURL = [indexURL copy];
        if (erase) {
            [self eraseStateRestorationDataSynchronously:YES];
        }
    }
    return self;
}

#pragma mark - iTermRestorableStateRestorationImpl

- (void)loadRestorableStateIndexWithCompletion:(void (^)(id<iTermRestorableStateIndex>))completion {
    completion([[iTermRestorableStateRestorerIndex alloc] initWithURL:_indexURL]);
}

- (void)restoreWindowWithRecord:(id<iTermRestorableStateRecord>)record
                     completion:(void (^)(NSString * _Nonnull, NSWindow * _Nonnull))completion {
    NSKeyedUnarchiver *unarchiver = record.unarchiver;
    [self.delegate restorableStateRestoreWithCoder:unarchiver
                                        identifier:record.identifier
                                        completion:^(NSWindow * _Nonnull window, NSError * _Nonnull error) {
        if ([window.delegate respondsToSelector:@selector(window:didDecodeRestorableState:)]) {
            [window.delegate window:window didDecodeRestorableState:unarchiver];
        }
        [unarchiver finishDecoding];
        completion(record.identifier, window);
    }];
}

- (void)restoreApplicationState {
    // This goes through the regular mechanism.
}

- (void)eraseStateRestorationDataSynchronously:(BOOL)sync {
    [[NSFileManager defaultManager] removeItemAtURL:_indexURL error:nil];
}

@end
