//
//  iTermRestorableStateSQLite.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import "iTermRestorableStateSQLite.h"

#import "DebugLogging.h"
#import "iTermGeneration.h"
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

- (NSKeyedUnarchiver * _Nullable)unarchiver {
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
        RLog(@"identifier=%@, error=%@", identifier, error);
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
    NSURL *_url;
}

+ (void)unlinkDatabaseAtURL:(NSURL *)url {
    [[[iTermSqliteDatabaseImpl alloc] initWithURL:url lockName:@"lock"] unlink];
}

- (instancetype)initWithURL:(NSURL *)url erase:(BOOL)erase {
    self = [super init];
    if (self) {
        if (erase) {
            [self.class unlinkDatabaseAtURL:url];
        }
        _url = url;
        [self initializeDb];
    }
    return self;
}

- (void)initializeDb {
    if (_db) {
        return;
    }
    iTermSqliteDatabaseImpl *sqliteDb = [[iTermSqliteDatabaseImpl alloc] initWithURL:_url
                                                                            lockName:@"lock"];
    sqliteDb.timeoutHandler = ^BOOL {
        __block BOOL result = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = NSLocalizedStringWithDefaultValue(@"RestorableState.SlowRestoreTitle", nil, [NSBundle mainBundle], @"Still restoring your windows…", @"Alert title shown when window restoration is slow");
            alert.informativeText = NSLocalizedStringWithDefaultValue(@"RestorableState.SlowRestoreBody", nil, [NSBundle mainBundle], @"iTerm2 is taking longer than usual to verify your saved windows and tabs. This usually means the system is busy and it’s safe to keep waiting, but a damaged state restoration database could also cause it. You can discard the saved windows instead if you’d rather not wait.", @"Explanation shown when window restoration is slow");
            // Keep Waiting is added first so it is the default action (triggered by Return).
            [alert addButtonWithTitle:NSLocalizedStringWithDefaultValue(@"RestorableState.KeepWaiting", nil, [NSBundle mainBundle], @"Keep Waiting", @"Default button to keep waiting for window restoration")];
            [alert addButtonWithTitle:NSLocalizedStringWithDefaultValue(@"RestorableState.DiscardSavedWindows", nil, [NSBundle mainBundle], @"Discard Saved Windows", @"Button to discard saved windows instead of waiting for restoration")];
            result = ([alert runModal] == NSAlertSecondButtonReturn);
        });
        return result;
    };
    iTermGraphDatabase *db = [[iTermGraphDatabase alloc] initWithDatabase:sqliteDb];
    _db = db;
}

- (void)loadRestorableStateIndexWithCompletion:(void (^)(id<iTermRestorableStateIndex>))completion {
    if (!_db) {
        completion(nil);
        return;
    }
    DLog(@"Add a when-ready callback to %@", _db);
    [_db whenReady:^{
        DLog(@"db is ready now");
        completion([[iTermRestorableStateSQLiteIndex alloc] initWithGraphRecord:self->_db.record]);
        [self->_db doHousekeeping];
    }];
}

- (void)restoreWindowWithRecord:(id<iTermRestorableStateRecord>)record
                     completion:(void (^)(NSString *windowIdentifier, NSWindow *window))completion {
    NSKeyedUnarchiver *coder = record.unarchiver;
    NSInteger i = -1;
    @try {
        i = [coder decodeIntegerForKey:@"index"];
        [coder finishDecoding];
    } @catch (NSException *exception) {
        RLog(@"Failed to decode index: %@", exception);
        completion(nil, nil);
        return;
    }
    assert(i >= 0);

    DLog(@"Create index...");
    iTermRestorableStateSQLiteIndex *windowIndex =
        [[iTermRestorableStateSQLiteIndex alloc] initWithGraphRecord:_db.record];
    iTermEncoderGraphRecord *windowRecord = windowIndex[i];
    DLog(@"Done creating index");
    if (!windowRecord) {
        RLog(@"Have no windowRecord");
        completion(nil, nil);
        return;
    }

    NSString *identifier = windowRecord.identifier;
    RLog(@"Will restore window %@", identifier);
    assert(identifier.length > 0);
    [self.delegate restorableStateRestoreWithRecord:windowRecord
                                         identifier:identifier
                                         completion:^(NSWindow *window,
                                                      NSError *error) {
        RLog(@"did restore window %@", identifier);
        completion(identifier, window);
    }];
}

- (void)restoreApplicationState {
    if (!_db.record) {
        return;
    }
    [self.delegate restorableStateRestoreApplicationStateWithRecord:_db.record];
}

- (void)eraseStateRestorationDataSynchronously:(BOOL)sync {
    [self initializeDb];
    [_db invalidateSynchronously:sync];
    _db = nil;
}

#pragma mark - iTermRestorableStateSaver

- (BOOL)saveSynchronously:(BOOL)sync withCompletion:(void (^)(void))completion {
    DLog(@"saveSynchronously:%@", @(sync));
    assert([NSThread isMainThread]);

    [self initializeDb];

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
        // The windows array is rewritten on every save. Allocate here rather than earlier because
        // the database runs this only after loading, which raises the generation floor above
        // everything it holds.
        const NSInteger generation = iTermGenerationNext();
        // Encode state for each window.
        [encoder encodeArrayWithKey:@"windows"
                         generation:generation
                        identifiers:identifiers
                            options:0
                              block:^BOOL(NSString * _Nonnull identifier,
                                          NSInteger index,
                                          iTermGraphEncoder * _Nonnull subencoder,
                                          BOOL *stop) {
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

    const BOOL result = [_db updateSynchronously:sync block:update completion:callback];
    if (sync) {
        // A synchronous save is the final save at quit. The connection is never closed, so
        // without this the WAL (as large as the biggest recent transaction) stays on disk.
        // This runs asynchronously on the database thread to avoid blocking the main thread.
        // If the app exits before it finishes, the checkpoint is safely abandoned.
        [_db truncateWAL];
    }
    return result;
}

@end
