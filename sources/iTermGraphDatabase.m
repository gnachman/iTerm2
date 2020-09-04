//
//  iTermGraphDatabase.m
//  iTerm2
//
//  Created by George Nachman on 7/27/20.
//

#import "iTermGraphDatabase.h"

#import "DebugLogging.h"
#import "FMDatabase.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "iTermGraphDeltaEncoder.h"
#import "iTermGraphTableTransformer.h"
#import "iTermThreadSafety.h"
#import <stdatomic.h>

@class iTermGraphDatabaseState;

@interface iTermGraphDatabaseState: iTermSynchronizedState<iTermGraphDatabaseState *>
@property (nonatomic, strong) id<iTermDatabase> db;
@end

@implementation iTermGraphDatabaseState
@end

@interface iTermGraphDatabase()
@property (atomic, readwrite) iTermEncoderGraphRecord *record;
@end

@implementation iTermGraphDatabase {
    id<iTermDatabaseFactory> _databaseFactory;
    BOOL _ok;
    NSInteger _recoveryCount;
    _Atomic int _updating;
}

- (instancetype)initWithURL:(NSURL *)url databaseFactory:(id<iTermDatabaseFactory>)databaseFactory {
    self = [super init];
    if (self) {
        _updating = ATOMIC_VAR_INIT(0);
        _thread = [[iTermThread alloc] initWithLabel:@"com.iterm2.graph-db"
                                        stateFactory:^iTermSynchronizedState * _Nonnull(dispatch_queue_t  _Nonnull queue) {
            return [[iTermGraphDatabaseState alloc] initWithQueue:queue];
        }];

        _url = url;
#warning TODO: Make this async
        [_thread dispatchSync:^(iTermGraphDatabaseState *state) {
            self.record = [self load:state factory:databaseFactory];
        }];
        if (!_ok) {
            return nil;
        }
    }
    return self;
}

- (void)updateSynchronously:(BOOL)sync
                      block:(void (^ NS_NOESCAPE)(iTermGraphEncoder * _Nonnull))block
                 completion:(nullable iTermCallback *)completion {
    assert([NSThread isMainThread]);

    if (self.updating && !sync) {
        __weak __typeof(self) weakSelf = self;
        // Wait for any queued updates to finish and then try again.
        [_thread dispatchAsync:^(id  _Nullable state) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf updateSynchronously:sync block:block completion:completion];
            });
        }];
        return;
    }
    [self beginUpdate];
    iTermGraphDeltaEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:self.record];
    block(encoder);
    __weak __typeof(self) weakSelf = self;

    void (^perform)(iTermGraphDatabaseState *) = ^(iTermGraphDatabaseState *state) {
        // This will mutate encoder.record.
        [weakSelf trySaveEncoder:encoder state:state];
        [completion invokeWithObject:@YES];
        // Save the now final record. A lot of the dance between threads is because we can only
        // write to record after -trySaveEncoder has finished.
        self.record = encoder.record;
        // Decrement the update count so that when this function returns the next block in the queue
        // can save.
        [weakSelf endUpdate];
    };
    if (sync) {
        [_thread dispatchSync:perform];
    } else {
        [_thread dispatchAsync:perform];
    }
}

- (id<iTermDatabase>)db {
    __block id<iTermDatabase> db = nil;
    [_thread dispatchSync:^(iTermGraphDatabaseState *state) {
        db = state.db;
    }];
    return db;
}

#pragma mark - Private

// any queue
- (BOOL)updating {
    return _updating;
}

// any queue
- (void)beginUpdate {
    _updating++;
}

// any queue
- (void)endUpdate {
    _updating--;
}

- (void)trySaveEncoder:(iTermGraphDeltaEncoder *)encoder state:(iTermGraphDatabaseState *)state {
    @try {
        if ([self save:encoder state:state]) {
            _recoveryCount = 0;
            return;
        }

        DLog(@"save failed: %@ with recovery count %@", self.db.lastError, @(_recoveryCount));
        if (_recoveryCount >= 3) {
            DLog(@"Not attempting recovery.");
            return;
        }
        _recoveryCount += 1;
        [self attemptRecovery:state record:encoder.record];
    } @catch (NSException *exception) {
        ITAssertWithMessage(NO, @"%@", exception.it_compressedDescription);
    }
}

- (void)attemptRecovery:(iTermGraphDatabaseState *)state
                 record:(iTermEncoderGraphRecord *)record {
#warning TEST THIS
    [state.db close];
    [state.db unlink];
    if (![self createDatabase:state factory:_databaseFactory]) {
        return;
    }
    iTermGraphDeltaEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithRecord:record];
    [self reallySave:encoder state:state];
}

- (BOOL)save:(iTermGraphDeltaEncoder *)encoder
       state:(iTermGraphDatabaseState *)state {
    if (!state.db) {
        return YES;
    }

    const BOOL ok = [state.db transaction:^BOOL{
        return [self reallySave:encoder state:state];
    }];
    if (!ok) {
        DLog(@"Transaction commit failed: %@", state.db.lastError);
    }
    return ok;
}

- (BOOL)reallySave:(iTermGraphDeltaEncoder *)encoder
             state:(iTermGraphDatabaseState *)state {
    DLog(@"Start saving");
    NSDate *start = [NSDate date];
    const BOOL ok =
    [encoder enumerateRecords:^(iTermEncoderGraphRecord * _Nullable before,
                                iTermEncoderGraphRecord * _Nullable after,
                                NSNumber *parent,
                                BOOL *stop) {
        if (before && !before.rowid) {
            @throw [NSException exceptionWithName:@"MissingRowID"
                                           reason:[NSString stringWithFormat:@"Before lacking a rowid: %@", before]
                                         userInfo:nil];
        }
        if (before && !after) {
            if (![state.db executeUpdate:@"delete from Node where rowid=?", before.rowid]) {
                *stop = YES;
                return;
            }
            return;
        }
        if (!before && after) {
            if (![state.db executeUpdate:@"insert into Node (key, identifier, parent, data) values (?, ?, ?, ?)",
                  after.key, after.identifier, parent, after.data ?: [NSData data]]) {
                *stop = YES;
                return;
            }
            NSNumber *lastInsertRowID = state.db.lastInsertRowId;
            assert(lastInsertRowID);
            @try {
                // Issue 9117
                after.rowid = lastInsertRowID;
            } @catch (NSException *exception) {
                @throw [exception it_rethrowWithMessage:@"after.key=%@ after.identifier=%@", after.key, after.identifier];
            }
            return;
        }
        if (before && after) {
            if (after.rowid == nil) {
                after.rowid = before.rowid;
            } else {
                if (before.generation == after.generation &&
                    after.generation != iTermGenerationAlwaysEncode) {
                    DLog(@"Don't update rowid %@ %@[%@] because it is unchanged", before.rowid, after.key, after.identifier);
                    return;
                }
            }
            assert(before.rowid.longLongValue == after.rowid.longLongValue);
            if ([before.data isEqual:after.data]) {
                return;
            }
            if (![state.db executeUpdate:@"update Node set data=? where rowid=?", after.data, before.rowid]) {
                *stop = YES;
            }
            return;
        }
        assert(NO);
    }];
    NSDate *end = [NSDate date];
    DLog(@"Save duration: %f0.1ms", (end.timeIntervalSinceNow - start.timeIntervalSinceNow) * 1000);
    return ok;
}

- (BOOL)createTables:(iTermGraphDatabaseState *)state {
    [state.db executeUpdate:@"PRAGMA journal_mode=WAL"];

    if (![state.db executeUpdate:@"create table if not exists Node (key text not null, identifier text not null, parent integer not null, data blob)"]) {
        return NO;
    }
    [state.db executeUpdate:@"create index if not exists parent_index on Node (parent)"];

    // Delete nodes without parents.
    [state.db executeUpdate:
     @"delete from Node where "
     @"  rowid in ("
     @"    select child.rowid as id "
     @"      from "
     @"        Node as child"
     @"        left join "
     @"          Node as parentNode "
     @"          on parentNode.rowid = child.parent "
     @"      where "
     @"        parentNode.rowid is NULL and "
     @"        child.parent != 0"
     @"  )"];
    return YES;
}

- (BOOL)createDatabase:(iTermGraphDatabaseState *)state
               factory:(id<iTermDatabaseFactory>)databaseFactory {
    state.db = [databaseFactory withURL:_url];
    if (![state.db open]) {
        return NO;
    }

    if (![self createTables:state]) {
        DLog(@"Create table failed: %@", state.db.lastError);
        return NO;
    }
    return YES;
}

- (iTermEncoderGraphRecord * _Nullable)load:(iTermGraphDatabaseState *)state
                                    factory:(id<iTermDatabaseFactory>)databaseFactory {
    if (![self createDatabase:state factory:databaseFactory]) {
        return nil;
    }
    _ok = YES;

    NSMutableArray<NSArray *> *nodes = [NSMutableArray array];
    {
        FMResultSet *rs = [state.db executeQuery:@"select key, identifier, parent, rowid, data from Node"];
        while ([rs next]) {
            [nodes addObject:@[ [rs stringForColumn:@"key"],
                                [rs stringForColumn:@"identifier"],
                                @([rs longLongIntForColumn:@"parent"]),
                                @([rs longLongIntForColumn:@"rowid"]),
                                [rs dataForColumn:@"data"] ?: [NSData data] ]];
        }
        [rs close];
    }

    iTermGraphTableTransformer *transformer = [[iTermGraphTableTransformer alloc] initWithNodeRows:nodes];
    return transformer.root;
}

@end

