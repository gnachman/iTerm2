//
//  iTermRestorableStateSQLite.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import "iTermRestorableStateSQLite.h"

#import "DebugLogging.h"
#import "iTermGraphSQLEncoder.h"
#import "iTermGraphDatabase.h"
#import "iTermThreadSafety.h"
#import "NSObject+iTerm.h"

@interface iTermRestorableStateSQLiteRecord: NSObject<iTermRestorableStateRecord>
@end

@implementation iTermRestorableStateSQLiteRecord {
    NSInteger _index;
    NSString *_identifier;
    NSInteger _windowNumber;
}

- (instancetype)initWithIndex:(NSInteger)i
                 windowNumber:(NSInteger)windowNumber
                   identifier:(NSString *)identifier {
    self = [super init];
    if (self) {
        _index = i;
        _windowNumber = windowNumber;
        _identifier = [identifier copy];
    }
    return self;
}

- (void)unlink {
    // Does nothing because the point of this thing is to not redo unnecessary work.
}

- (NSKeyedUnarchiver *)unarchiver {
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding:NO];
    archiver.requiresSecureCoding = NO;
    [archiver encodeObject:@(_index) forKey:@"index"];
    [archiver finishEncoding];

    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:archiver.encodedData
                                                                                error:nil];
    return unarchiver;
}

- (NSString *)identifier {
    return _identifier;
}

- (nonnull id<iTermRestorableStateRecord>)recordWithPayload:(nonnull id)payload {
    return self;
}


- (NSInteger)windowNumber {
    return _windowNumber;
}


@end

@interface iTermRestorableStateSQLiteIndex: NSObject<iTermRestorableStateIndex>
@end

@implementation iTermRestorableStateSQLiteIndex {
    iTermEncoderGraphRecord *_record;
    NSArray<iTermEncoderGraphRecord *> *_windows;
}

- (instancetype)initWithGraphRecord:(iTermEncoderGraphRecord *)record {
    self = [super init];
    if (self) {
        _record = record;
        _windows = [_record arrayWithKey:@"windows"];
    }
    return self;
}

- (NSUInteger)restorableStateIndexNumberOfWindows {
    return _windows.count;
}

- (void)restorableStateIndexUnlink {
    // Does nothing because the point of this thing is to not redo unnecessary work.
}

- (id<iTermRestorableStateRecord>)restorableStateRecordAtIndex:(NSUInteger)i {
    NSString *identifier = [_windows[i] stringWithKey:@"identifier"];
    NSError *error = nil;
    NSInteger windowNumber = [_windows[i] integerWithKey:@"windowNumber" error:&error];
    if (error || !identifier) {
        DLog(@"identifier=%@, error=%@", identifier, error);
        return nil;
    }
    return [[iTermRestorableStateSQLiteRecord alloc] initWithIndex:i
                                                      windowNumber:windowNumber
                                                        identifier:identifier ?: @""];
}

- (id)objectAtIndexedSubscript:(NSUInteger)idx {
    return _windows[idx];
}

@end

@implementation iTermRestorableStateSQLite {
    iTermGraphDatabase *_db;
}

- (instancetype)initWithURL:(NSURL *)url {
    self = [super init];
    if (self) {
        _db = [[iTermGraphDatabase alloc] initWithURL:url
                                      databaseFactory:[[iTermSqliteDatabaseFactory alloc] init]];
    }
    return self;
}

- (id<iTermRestorableStateIndex>)restorableStateIndex {
    return [[iTermRestorableStateSQLiteIndex alloc] initWithGraphRecord:_db.record];
}

- (void)restoreWindowWithRecord:(id<iTermRestorableStateRecord>)record
                     completion:(void (^)(void))completion {
    NSKeyedUnarchiver *coder = record.unarchiver;
    NSInteger i = -1;
    @try {
        i = [coder decodeIntegerForKey:@"index"];
        [coder finishDecoding];
    } @catch (NSException *exception) {
        DLog(@"Failed to decode index: %@", exception);
        completion();
        return;
    }
    assert(i >= 0);

    iTermRestorableStateSQLiteIndex *windowIndex =
        [[iTermRestorableStateSQLiteIndex alloc] initWithGraphRecord:_db.record];
    iTermEncoderGraphRecord *windowRecord = windowIndex[i];
    NSString *identifier = [windowRecord stringWithKey:@"identifier"];
    [self.delegate restorableStateRestoreWithRecord:windowRecord
                                         identifier:identifier
                                         completion:^(NSWindow * _Nonnull window,
                                                      NSError * _Nonnull error) {
        completion();
    }];
}

#pragma mark - iTermRestorableStateSaver

- (void)saveWithCompletion:(void (^)(void))completion {
    void (^update)(iTermGraphEncoder * _Nonnull) = ^(iTermGraphEncoder * _Nonnull encoder) {
        for (NSWindow *window in [self.delegate restorableStateWindows]) {
            if ([window.delegate conformsToProtocol:@protocol(iTermGraphCodable)]) {
                id<iTermGraphCodable> codable = (id<iTermGraphCodable>)window.delegate;
                [codable encodeGraphWithEncoder:encoder];
            }
        }
    };

    iTermCallback *callback =
    [iTermCallback onThread:[iTermThread main] block:^(iTermMainThreadState *state,
                                                       id  _Nullable result) {
        completion();
    }];

    [_db update:update completion:callback];
}

@end
