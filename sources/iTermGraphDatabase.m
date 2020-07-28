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
#import "iTermThreadSafety.h"

@class iTermGraphDatabaseState;

@interface FMResultSet (iTerm)<iTermDatabaseResultSet>
@end

static iTermEncoderGraphRecord *iTermGraphDeltaEncoderMakeGraphRecord(NSString *nodeID,
                                                                      NSDictionary *nodes) {
    NSDictionary *nodeDict = nodes[nodeID];
    NSArray<NSString *> *childNodeIDs = nodeDict[@"children"];
    NSArray<iTermEncoderGraphRecord *> *childGraphRecords =
    [childNodeIDs mapWithBlock:^id(NSString *childNodeID) {
        return iTermGraphDeltaEncoderMakeGraphRecord(childNodeID, nodes);
    }];
    iTermGraphExplodedContext exploded = iTermGraphExplodeContext(nodeID);
    return [iTermEncoderGraphRecord withPODs:[nodeDict[@"pod"] allValues]
                                      graphs:childGraphRecords
                                  generation:[nodeDict[@"generation"] integerValue]
                                         key:exploded.key
                                  identifier:exploded.identifier];
}

@implementation iTermGraphTableTransformer {
    iTermEncoderGraphRecord *_record;
}

- (instancetype)initWithNodeRows:(NSArray *)nodeRows
                       valueRows:(NSArray *)valueRows {
    self = [super init];
    if (self) {
        _nodeRows = nodeRows;
        _valueRows = valueRows;
    }
    return self;
}

- (iTermEncoderGraphRecord * _Nullable)root {
    if (!_record) {
        _record = [self transform];
    }
    return _record;
}

- (NSDictionary<NSString *, NSMutableDictionary *> *)nodes:(out NSString **)rootNodeIDOut {
    // Create nodes
    NSMutableDictionary<NSString *, NSMutableDictionary *> *nodes = [NSMutableDictionary dictionary];
    for (NSArray *row in _nodeRows) {
        if (row.count != 4) {
            DLog(@"Wrong number of items in row: %@", row);
            _lastError = [NSError errorWithDomain:@"com.iterm2.graph-transformer"
                                             code:1
                                         userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Wrong number of items in row: %@", row] }];
            return nil;
        }
        NSString *key = [NSString castFrom:row[0]];
        NSString *identifier = [NSString castFrom:row[1]];
        NSString *parent = [NSString castFrom:row[2]];
        NSNumber *generation = [NSNumber castFrom:row[3]];
        if (!row || !key || !identifier || !parent || !generation) {
            DLog(@"Bad row: %@", row);
            _lastError = [NSError errorWithDomain:@"com.iterm2.graph-transformer"
                                             code:1
                                         userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Bad row: %@", row] }];
            return nil;
        }
        NSString *nodeid = iTermGraphContext(parent, key, identifier);
        if (parent.length == 0 && key.length == 0) {
            if (*rootNodeIDOut) {
                DLog(@"Two roots found");
                _lastError = [NSError errorWithDomain:@"com.iterm2.graph-transformer"
                                                 code:1
                                             userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Two roots found"] }];
                return nil;
            }
            *rootNodeIDOut = nodeid;
        }
        nodes[nodeid] = [@{ @"pod": [NSMutableDictionary dictionary],
                            @"parent": parent,
                            @"generation": generation,
                            @"children": [NSMutableArray array] } mutableCopy];
    }
    return nodes;
}

- (BOOL)attachValuesToNodes:(NSDictionary<NSString *, NSMutableDictionary *> *)nodes {
    for (NSArray *row in _valueRows) {
        if (row.count != 4) {
            DLog(@"Wrong number of fields in row: %@", row);
            _lastError = [NSError errorWithDomain:@"com.iterm2.graph-transformer"
                                             code:1
                                         userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Wrong number of fields in row: %@", row] }];
            return NO;
        }
        NSString *nodeid = [NSString castFrom:row[0]];
        NSString *key = [NSString castFrom:row[1]];
        NSNumber *type = [NSNumber castFrom:row[3]];
        if (!nodeid || !key || !type) {
            DLog(@"Bogus row: %@", row);
            _lastError = [NSError errorWithDomain:@"com.iterm2.graph-transformer"
                                             code:1
                                         userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Bogus row: %@", row] }];
            return NO;
        }
        iTermEncoderPODRecord *record = nil;
        record = [iTermEncoderPODRecord withData:row[2]
                                            type:(iTermEncoderRecordType)type.unsignedIntegerValue
                                             key:key];
        if (!record) {
            DLog(@"Bogus value with type %@: %@", type, row[2]);
            _lastError = [NSError errorWithDomain:@"com.iterm2.graph-transformer"
                                             code:1
                                         userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Bogus value with type %@: %@", type, row[2]] }];
            return NO;
        }
        NSMutableDictionary *nodeDict = nodes[nodeid];
        if (!nodeDict) {
            DLog(@"No such node: %@", nodeid);
            _lastError = [NSError errorWithDomain:@"com.iterm2.graph-transformer"
                                             code:1
                                         userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No such node: %@", nodeid] }];
            return NO;
        }
        NSMutableDictionary *pod = nodeDict[@"pod"];
        pod[key] = record;
    }
    return YES;
}

- (BOOL)attachChildrenToParents:(NSDictionary<NSString *, NSMutableDictionary *> *)nodes {
    __block BOOL ok = YES;
    [nodes enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull nodeid,
                                               NSMutableDictionary * _Nonnull nodeDict,
                                               BOOL * _Nonnull stop) {
        iTermGraphExplodedContext exploded = iTermGraphExplodeContext(nodeid);
        if (exploded.context.length == 0 && exploded.key.length == 0) {
            // This is the root.
            return;
        }
        NSMutableDictionary *parentDict = nodes[exploded.context];
        if (!parentDict) {
            ok = NO;
            DLog(@"Dangling parent pointer %@ from %@", nodeDict[@"parent"], nodeid);
            _lastError = [NSError errorWithDomain:@"com.iterm2.graph-transformer"
                                             code:1
                                         userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Dangling parent pointer %@ from %@", nodeDict[@"parent"], nodeid] }];
            *stop = YES;
        }
        NSMutableArray *children = parentDict[@"children"];
        [children addObject:nodeid];
    }];
    return ok;
}

- (iTermEncoderGraphRecord * _Nullable)transform {
    NSString *rootNodeID = nil;
    NSDictionary<NSDictionary *, NSMutableDictionary *> *nodes = [self nodes:&rootNodeID];
    if (!nodes) {
        DLog(@"nodes: returned nil");
        return nil;
    }
    if (!rootNodeID) {
        DLog(@"No root found");
        return nil;
    }
    if (![self attachValuesToNodes:nodes]) {
        DLog(@"Failed to attach values to nodes");
        return nil;
    }
    if (![self attachChildrenToParents:nodes]) {
        DLog(@"Failed to attach children to parents");
        return nil;
    }

    // Finally, we can construct a record.
    return iTermGraphDeltaEncoderMakeGraphRecord(rootNodeID, nodes);
}

@end

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
        [_thread dispatchSync:^(iTermGraphDatabaseState *state) {
            _record = [self load:state factory:databaseFactory];
        }];
        if (!_ok) {
            return nil;
        }
    }
    return self;
}

- (void)update:(void (^ NS_NOESCAPE)(iTermGraphEncoder * _Nonnull))block {
    iTermGraphDeltaEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:_record];
    block(encoder);
    [_thread dispatchAsync:^(iTermGraphDatabaseState *state) {
        [self save:encoder state:state];
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

- (NSString *)valueContextInGraph:(iTermEncoderGraphRecord *)record
                          context:(NSString *)context {
    return [record contextWithContext:context];
}

- (void)reallySave:(iTermGraphDeltaEncoder *)encoder
             state:(iTermGraphDatabaseState *)state {
    [encoder enumerateRecords:^(iTermEncoderGraphRecord * _Nullable before,
                                iTermEncoderGraphRecord * _Nullable after,
                                NSString *context) {
        if (before && !after) {
            [state.db executeUpdate:@"delete from Node where key=? and identifier=? and context=?",
             before.key, before.identifier, context];
            [before enumerateValuesVersus:nil block:^(iTermEncoderPODRecord * _Nullable mine,
                                                      iTermEncoderPODRecord * _Nullable theirs) {
                [state.db executeUpdate:@"delete from Value where key=? and context=?",
                 mine.key, [self valueContextInGraph:before context:context]];
            }];
        } else if (!before && after) {
            [state.db executeUpdate:@"insert into Node (key, identifier, context, generation) values (?, ?, ?, ?)",
             after.key, after.identifier, context, @(after.generation)];
            [after enumerateValuesVersus:nil block:^(iTermEncoderPODRecord * _Nullable record,
                                                     iTermEncoderPODRecord * _Nullable na) {
                [state.db executeUpdate:@"insert into Value (key, value, context, type) values (?, ?, ?, ?)",
                 record.key, record.data, [self valueContextInGraph:after context:context], @(record.type)];
            }];
        } else if (before && after) {
            if (![before isEqual:after]) {
                [state.db executeUpdate:@"update Node set generation=? where key=? and identifier=? and context=?",
                 @(after.generation), before.key, before.identifier, context];
            }
            [before enumerateValuesVersus:after block:^(iTermEncoderPODRecord * _Nullable mine,
                                                        iTermEncoderPODRecord * _Nullable theirs) {
                if (mine && theirs) {
                    if (![mine isEqual:theirs]) {
                        [state.db executeUpdate:@"update Value set value=?, type=? where key=? and context=?",
                         theirs.data, @(theirs.type), mine.key,
                         [self valueContextInGraph:before context:context]];
                    }
                } else if (!mine && theirs) {
                    [state.db executeUpdate:@"insert into Value (key, value, context, type) values (?, ?, ?, ?)",
                     theirs.key, theirs.data, [self valueContextInGraph:after context:context],
                     @(theirs.type)];
                } else if (mine && !theirs) {
                    [state.db executeUpdate:@"delete from Value where key=? and context=?",
                     mine.key, [self valueContextInGraph:before context:context]];
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

    [state.db executeUpdate:@"create table Node (key text, identifier text, context text, generation integer)"];
    [state.db executeUpdate:@"create table Value (key text, context text, value blob, type integer)"];

    NSMutableArray<NSArray *> *nodes = [NSMutableArray array];
    NSMutableArray<NSArray *> *values = [NSMutableArray array];
    {
        FMResultSet *rs = [state.db executeQuery:@"select * from Node"];
        while ([rs next]) {
            [nodes addObject:@[ [rs stringForColumn:@"key"],
                                [rs stringForColumn:@"identifier"],
                                [rs stringForColumn:@"context"],
                                @([rs longLongIntForColumn:@"generation"]) ]];
        }
        [rs close];
    }
    {
        FMResultSet *rs = [state.db executeQuery:@"select * from Value"];
        while ([rs next]) {
            [values addObject:@[
                [rs stringForColumn:@"context"],
                [rs stringForColumn:@"key"],
                [rs dataForColumn:@"value"],
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

@interface iTermSqliteDatabaseImpl: NSObject<iTermDatabase>
- (instancetype)initWithDatabase:(FMDatabase *)db NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@implementation iTermSqliteDatabaseFactory

- (nullable id<iTermDatabase>)withURL:(NSURL *)url {
    FMDatabase *db = [FMDatabase databaseWithPath:url.path];
    return [[iTermSqliteDatabaseImpl alloc] initWithDatabase:db];
}

@end

@implementation iTermSqliteDatabaseImpl {
    FMDatabase *_db;
}

- (instancetype)initWithDatabase:(FMDatabase *)db {
    self = [super init];
    if (self) {
        _db = db;
    }
    return self;
}

- (BOOL)executeUpdate:(NSString *)sql, ... {
    va_list args;
    va_start(args, sql);
    const BOOL result = [_db executeUpdate:sql withVAList:args];
    va_end(args);
    return result;
}

- (id<iTermDatabaseResultSet> _Nullable)executeQuery:(NSString*)sql, ... {
    va_list args;
    va_start(args, sql);
    FMResultSet * _Nullable result = [_db executeQuery:sql withVAList:args];
    va_end(args);
    return result;
}

- (BOOL)open {
    const BOOL ok = [_db open];
    if (ok) {
        return YES;
    }
    DLog(@"Failed to open db: %@", _db.lastError);

    // Delete and re-open.
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSURL *url = [NSURL fileURLWithPath:[_db databasePath]];
    [fileManager removeItemAtPath:url.path error:&error];
    DLog(@"Remove %@: error=%@", url.path, error);
    if ([_db open]) {
        return YES;
    }
    DLog(@"Failed to open db after deletion: %@", _db.lastError);
    return NO;
}

- (NSError *)lastError {
    return [_db lastError];
}

- (BOOL)transaction:(BOOL (^ NS_NOESCAPE)(void))block {
    [_db beginTransaction];
    if (block()) {
        return [_db commit];
    } else {
        return [_db rollback];
    }
}

@end
