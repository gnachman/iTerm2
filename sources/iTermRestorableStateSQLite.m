//
//  iTermRestorableStateSQLite.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import "iTermRestorableStateSQLite.h"

#import "DebugLogging.h"
#import "iTermGraphDatabase.h"
#import "iTermThreadSafety.h"
#import "NSArray+iTerm.h"
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

- (void)didFinishRestoring {
    // Does nothing because the point of this thing is to not redo unnecessary work.
}

- (NSKeyedUnarchiver *)unarchiver {
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding:NO];
    archiver.requiresSecureCoding = NO;
    [archiver encodeInteger:_index forKey:@"index"];
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
        _windows = [_record recordArrayWithKey:@"windows"];
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
    NSString *identifier = [_windows[i] stringWithKey:@"__identifier"];
    NSError *error = nil;
    NSInteger windowNumber = [_windows[i] integerWithKey:@"__windowNumber" error:&error];
    if (error || !identifier) {
        DLog(@"identifier=%@, error=%@", identifier, error);
        return nil;
    }
    return [[iTermRestorableStateSQLiteRecord alloc] initWithIndex:i
                                                      windowNumber:windowNumber
                                                        identifier:identifier ?: @""];
}

- (id)objectAtIndexedSubscript:(NSUInteger)idx {
    if (idx >= _windows.count) {
        return nil;
    }
    return _windows[idx];
}

@end

@implementation iTermRestorableStateSQLite {
    iTermGraphDatabase *_db;
    NSInteger _generation;
}

+ (void)unlinkDatabaseAtURL:(NSURL *)url {
    [[[[iTermSqliteDatabaseFactory alloc] init] withURL:url] unlink];
}

- (instancetype)initWithURL:(NSURL *)url erase:(BOOL)erase {
    self = [super init];
    if (self) {
        if (erase) {
            [self.class unlinkDatabaseAtURL:url];
        }

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
    if (!windowRecord) {
        completion();
        return;
    }
    NSString *identifier = windowRecord.identifier;
    assert(identifier.length > 0);
    [self.delegate restorableStateRestoreWithRecord:windowRecord
                                         identifier:identifier
                                         completion:^(NSWindow *window,
                                                      NSError *error) {
        completion();
    }];
}

- (void)restoreApplicationState {
    if (!_db.record) {
        return;
    }
    [self.delegate restorableStateRestoreApplicationStateWithRecord:_db.record];
}

- (void)eraseStateRestorationData {
    [_db.db close];
    [self.class unlinkDatabaseAtURL:_db.url];
    _db = nil;
}

#pragma mark - iTermRestorableStateSaver

- (void)saveSynchronously:(BOOL)sync withCompletion:(void (^)(void))completion {
    _generation += 1;
    const NSInteger generation = _generation;
    NSArray<NSWindow *> *windows = [self.delegate restorableStateWindows];
    NSArray<NSString *> *identifiers = [windows mapWithBlock:^id(NSWindow *window) {
        if (![window.delegate conformsToProtocol:@protocol(iTermGraphCodable)]) {
            return nil;
        }
        if (![window.delegate conformsToProtocol:@protocol(iTermUniquelyIdentifiable)]) {
            return nil;
        }
        id<iTermUniquelyIdentifiable> identifiable = (id<iTermUniquelyIdentifiable>)window.delegate;
        return identifiable.stringUniqueIdentifier;
    }];
    void (^update)(iTermGraphEncoder * _Nonnull) = ^(iTermGraphEncoder * _Nonnull encoder) {
        // Encode state for each window.
        [encoder encodeArrayWithKey:@"windows"
                         generation:generation
                        identifiers:identifiers
                            options:0
                              block:^BOOL(NSString * _Nonnull identifier,
                                          NSInteger index,
                                          iTermGraphEncoder * _Nonnull subencoder) {
            NSWindow *window = windows[index];
            [subencoder encodeString:identifier forKey:@"__identifier"];
            [subencoder encodeNumber:@(window.windowNumber) forKey:@"__windowNumber"];
            id<iTermGraphCodable> codable = (id<iTermGraphCodable>)window.delegate;
            return [codable encodeGraphWithEncoder:subencoder];
        }];

        // Encode app-global state
        id<NSApplicationDelegate> appDelegate = [NSApp delegate];
        if ([appDelegate conformsToProtocol:@protocol(iTermGraphCodable)]) {
            id<iTermGraphCodable> codable = (id<iTermGraphCodable>)appDelegate;
            [codable encodeGraphWithEncoder:encoder];
        }
    };

    iTermCallback *callback =
    [iTermCallback onThread:[iTermThread main] block:^(iTermMainThreadState *state,
                                                       id  _Nullable result) {
        completion();
    }];

    [_db updateSynchronously:sync block:update completion:callback];
}

@end
