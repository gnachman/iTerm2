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
#import "iTermEncoderPODRecord.h"
#import "iTermGraphDeltaEncoder.h"
#import "iTermGraphTableTransformer.h"
#import "iTermThreadSafety.h"

@class iTermGraphDatabaseState;

@interface iTermGraphDatabaseState: iTermSynchronizedState<iTermGraphDatabaseState *>
@property (nonatomic, strong) id<iTermDatabase> db;
@end

@implementation iTermGraphDatabaseState
@end

@implementation iTermGraphDatabase {
    id<iTermDatabaseFactory> _databaseFactory;
    BOOL _ok;
}

- (instancetype)initWithURL:(NSURL *)url databaseFactory:(id<iTermDatabaseFactory>)databaseFactory {
    self = [super init];
    if (self) {
        _thread = [[iTermThread alloc] initWithLabel:@"com.iterm2.graph-db"
                                        stateFactory:^iTermSynchronizedState * _Nonnull(dispatch_queue_t  _Nonnull queue) {
            return [[iTermGraphDatabaseState alloc] initWithQueue:queue];
        }];

        _url = url;
#warning TODO: Make this async
        [_thread dispatchSync:^(iTermGraphDatabaseState *state) {
            _record = [self load:state factory:databaseFactory];
        }];
        if (!_ok) {
            return nil;
        }
    }
    return self;
}

- (void)update:(void (^ NS_NOESCAPE)(iTermGraphEncoder * _Nonnull))block
    completion:(iTermCallback *)completion {
    iTermGraphDeltaEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:_record];
    block(encoder);
    [_thread dispatchAsync:^(iTermGraphDatabaseState *state) {
        [self save:encoder state:state];
        [completion invokeWithObject:nil];
    }];
    _record = encoder.record;
}

- (id<iTermDatabase>)db {
    __block id<iTermDatabase> db = nil;
    [_thread dispatchSync:^(iTermGraphDatabaseState *state) {
        db = state.db;
    }];
    return db;
}

#pragma mark - Private

- (void)save:(iTermGraphDeltaEncoder *)encoder
       state:(iTermGraphDatabaseState *)state {
    if (!state.db) {
        return;
    }

    const BOOL ok = [state.db transaction:^BOOL{
        [self reallySave:encoder state:state];
        return YES;
    }];
    if (!ok) {
        DLog(@"Transaction commit failed: %@", state.db.lastError);
    }
}

- (void)reallySave:(iTermGraphDeltaEncoder *)encoder
             state:(iTermGraphDatabaseState *)state {
    [encoder enumerateRecords:^(iTermEncoderGraphRecord * _Nullable before,
                                iTermEncoderGraphRecord * _Nullable after,
                                NSNumber *parent) {
        if (before) {
            assert(before.rowid);
        }
        if (before && !after) {
            [state.db executeUpdate:@"delete from Node where rowid=?", before.rowid];
            [state.db executeUpdate:@"delete from Value where node=?", before.rowid];
        } else if (!before && after) {
            [state.db executeUpdate:@"insert into Node (key, identifier, parent) values (?, ?, ?)",
             after.key, after.identifier, parent];
            NSNumber *lastInsertRowID = state.db.lastInsertRowId;
            assert(lastInsertRowID);  // TODO
            after.rowid = lastInsertRowID;
            [after enumerateValuesVersus:nil block:^(iTermEncoderPODRecord * _Nullable record,
                                                     iTermEncoderPODRecord * _Nullable na) {
                [state.db executeUpdate:@"insert into Value (key, value, node, type) values (?, ?, ?, ?)",
                 record.key, record.data, lastInsertRowID, @(record.type)];
            }];
        } else if (before && after) {
            if (after.rowid == nil) {
                after.rowid = before.rowid;
            }
            assert(before.rowid.longLongValue == after.rowid.longLongValue);
            [before enumerateValuesVersus:after block:^(iTermEncoderPODRecord * _Nullable mine,
                                                        iTermEncoderPODRecord * _Nullable theirs) {
                if (mine && theirs) {
                    if (![mine isEqual:theirs]) {
                        [state.db executeUpdate:@"update Value set value=?, type=? where key=? and node=?",
                         theirs.data, @(theirs.type), mine.key, before.rowid];
                    }
                } else if (!mine && theirs) {
                    [state.db executeUpdate:@"insert into Value (key, value, node, type) values (?, ?, ?, ?)",
                     theirs.key, theirs.data, before.rowid, @(theirs.type)];
                } else if (mine && !theirs) {
                    [state.db executeUpdate:@"delete from Value where key=? and node=?",
                     mine.key, before.rowid];
                } else {
                    assert(NO);
                }
            }];
        } else {
            assert(NO);
        }
    }];
}

- (iTermEncoderGraphRecord * _Nullable)load:(iTermGraphDatabaseState *)state
                                    factory:(id<iTermDatabaseFactory>)databaseFactory {
    state.db = [databaseFactory withURL:_url];
    if (![state.db open]) {
        return nil;
    }
    _ok = YES;

    [state.db executeUpdate:@"create table if not exists Node (key text, identifier text, parent integer)"];
    [state.db executeUpdate:@"create table if not exists Value (key text, node integer, value blob, type integer)"];

    NSMutableArray<NSArray *> *nodes = [NSMutableArray array];
    NSMutableArray<NSArray *> *values = [NSMutableArray array];
    {
        FMResultSet *rs = [state.db executeQuery:@"select * from Node"];
        while ([rs next]) {
            [nodes addObject:@[ [rs stringForColumn:@"key"],
                                [rs stringForColumn:@"identifier"],
                                @([rs longLongIntForColumn:@"parent"]),
                                @([rs longLongIntForColumn:@"rowid"])]];
        }
        [rs close];
    }
    {
        FMResultSet *rs = [state.db executeQuery:@"select * from Value"];
        while ([rs next]) {
            [values addObject:@[
                @([rs longLongIntForColumn:@"node"]),
                [rs stringForColumn:@"key"],
                [rs dataForColumn:@"value"] ?: [NSData data],
                @([rs longLongIntForColumn:@"type"])
            ]];
        }
        [rs close];
    }

    iTermGraphTableTransformer *transformer = [[iTermGraphTableTransformer alloc] initWithNodeRows:nodes
                                                                                         valueRows:values];
    return transformer.root;
}

@end

