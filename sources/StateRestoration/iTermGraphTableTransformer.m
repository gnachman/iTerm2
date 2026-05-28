//
//  iTermGraphTableTransformer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import "iTermGraphTableTransformer.h"

#import "DebugLogging.h"
#import "iTermGraphDatabase.h"
#import "iTermSessionRestoreDiag.h"
#import "NSArray+iTerm.h"
#import "NSData+iTerm.h"
#import "NSObject+iTerm.h"

static iTermEncoderGraphRecord *iTermGraphDeltaEncoderMakeGraphRecord(NSNumber *nodeID,
                                                                      NSDictionary *nodes,
                                                                      NSArray<NSString *> *path,
                                                                      iTermGraphDatabase *database) {
    NSDictionary *nodeDict = nodes[nodeID];
    NSArray<NSNumber *> *childNodeIDs = nodeDict[@"children"];
    NSString *tail = [NSString stringWithFormat:@"%@[%@]", nodeDict[@"key"], nodeDict[@"identifier"]];
    NSArray<iTermEncoderGraphRecord *> *childGraphRecords =
        [childNodeIDs mapWithBlock:^id(NSNumber *childNodeID) {
            return iTermGraphDeltaEncoderMakeGraphRecord(childNodeID, nodes, [path arrayByAddingObject:tail], database);
        }];

    // Check if this node has large data that needs lazy loading
    BOOL hasLargeData = [nodeDict[@"has_large_data"] boolValue];
    NSInteger generation = [nodeDict[@"generation"] integerValue];

    NSDictionary<NSString *, id> *pod = nil;
    if (!hasLargeData) {
        // Small data is loaded immediately
        NSData *data = nodeDict[@"data"];
        if (data.length) {
            NSError *error;
            pod = [data it_unarchivedObjectOfBasicClassesWithError:&error];
            if (error) {
                DLog(@"Failed to unarchive data for node %@: %@", nodeDict, error);
            }
        } else {
            pod = @{};
        }
    }
    // If hasLargeData, pod stays nil and will be lazy loaded via database

    DLog(@"key=%@ id=%@ rowid=%@ gen=%@ hasLarge=%@ children=%@ pod=%@",
         nodeDict[@"key"], nodeDict[@"identifier"],
         nodeDict[@"rowid"], @(generation), @(hasLargeData),
         childNodeIDs, [pod tastefulDescription]);

    // Issue 12866 diagnostic. See iTermSessionRestoreDiag.h. One GT line per
    // node as the in-memory tree is rebuilt from disk rows, with its full
    // path, so we can match it against the GW (write) and GROW (raw row) lines
    // and see exactly where a session leaf's POD goes missing.
    NSString *podKeyDesc;
    if (hasLargeData) {
        podKeyDesc = @"deferred";
    } else {
        NSString *joined = [[pod.allKeys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","];
        if (joined.length > 500) {
            joined = [[joined substringToIndex:500] stringByAppendingString:@"…"];
        }
        podKeyDesc = [NSString stringWithFormat:@"%lu[%@]", (unsigned long)pod.count, joined];
    }
    iTermSessionRestoreDiagLog(@"GT path=%@ key=%@ id=%@ rowid=%@ gen=%@ large=%d podKeys=%@ children=%lu",
                               [path componentsJoinedByString:@"/"],
                               nodeDict[@"key"], nodeDict[@"identifier"],
                               nodeDict[@"rowid"] ?: @"<nil>", @(generation),
                               (int)hasLargeData,
                               podKeyDesc,
                               (unsigned long)childNodeIDs.count);

    return [iTermEncoderGraphRecord withPODs:pod
                                      graphs:childGraphRecords
                                  generation:generation
                                         key:nodeDict[@"key"]
                                  identifier:nodeDict[@"identifier"]
                                       rowid:nodeDict[@"rowid"]
                                hasLargeData:hasLargeData
                                    database:database];
}

@implementation iTermGraphTableTransformer {
    iTermEncoderGraphRecord *_record;
    __weak iTermGraphDatabase *_database;
}

- (instancetype)initWithNodeRows:(NSArray *)nodeRows {
    return [self initWithNodeRows:nodeRows database:nil];
}

- (instancetype)initWithNodeRows:(NSArray *)nodeRows
                        database:(iTermGraphDatabase *)database {
    self = [super init];
    if (self) {
        _nodeRows = nodeRows;
        _database = database;
    }
    return self;
}

- (iTermEncoderGraphRecord * _Nullable)root {
    if (!_record) {
        _record = [self transform];
    }
    return _record;
}

- (NSDictionary<NSNumber *, NSMutableDictionary *> *)nodes:(out NSNumber **)rootNodeIDOut {
    // Create nodes
    // Row format: [key, identifier, parent, rowid, data, generation, has_large_data]
    NSMutableDictionary<NSNumber *, NSMutableDictionary *> *nodes = [NSMutableDictionary dictionary];
    for (NSArray *row in _nodeRows) {
        if (row.count != 7) {
            DLog(@"Wrong number of items in row: %@", row);
            _lastError = [NSError errorWithDomain:@"com.iterm2.graph-transformer"
                                             code:1
                                         userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Wrong number of items in row: %@", row] }];
            return nil;
        }
        NSString *key = [NSString castFrom:row[0]];
        NSString *identifier = [NSString castFrom:row[1]];
        NSNumber *parent = [NSNumber castFrom:row[2]];
        NSNumber *rowid = [NSNumber castFrom:row[3]];
        NSData *data = [NSData castFrom:row[4]];
        NSNumber *generation = [NSNumber castFrom:row[5]] ?: @0;
        NSNumber *hasLargeData = [NSNumber castFrom:row[6]] ?: @NO;

        if (!row || !key || !identifier || !parent) {
            DLog(@"Bad row: %@", row);
            _lastError = [NSError errorWithDomain:@"com.iterm2.graph-transformer"
                                             code:1
                                         userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Bad row: %@", row] }];
            return nil;
        }
        // data can be nil if hasLargeData is true (will be lazy loaded)
        if (!data && !hasLargeData.boolValue) {
            data = [NSData data];
        }

        if (parent.integerValue == 0 && key.length == 0) {
            if (*rootNodeIDOut) {
                DLog(@"Two roots found");
                iTermSessionRestoreDiagLog(@"GTERR two roots found (rowid=%@ and %@)", *rootNodeIDOut, rowid);
                _lastError = [NSError errorWithDomain:@"com.iterm2.graph-transformer"
                                                 code:1
                                             userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Two roots found"] }];
                return nil;
            }
            *rootNodeIDOut = rowid;
        }
        nodes[rowid] = [@{ @"pod": [NSMutableDictionary dictionary],
                           @"key": key,
                           @"identifier": identifier,
                           @"parent": parent,
                           @"children": [NSMutableArray array],
                           @"rowid": rowid,
                           @"data": data ?: [NSData data],
                           @"generation": generation,
                           @"has_large_data": hasLargeData } mutableCopy];
    }
    return nodes;
}

- (BOOL)attachChildrenToParents:(NSDictionary<NSNumber *, NSMutableDictionary *> *)nodes
              ignoringRootRowID:(NSNumber *)rootRowID {
    __block BOOL ok = YES;
    [nodes enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull nodeid,
                                               NSMutableDictionary * _Nonnull nodeDict,
                                               BOOL * _Nonnull stop) {
        if ([nodeid isEqualToNumber:rootRowID]) {
            return;
        }
        NSMutableDictionary<NSString *, id> *parentDict = nodes[nodeDict[@"parent"]];
        if (!parentDict) {
            ok = NO;
            DLog(@"Dangling parent pointer %@ from %@", nodeDict[@"parent"], nodeid);
            iTermSessionRestoreDiagLog(@"GTERR dangling parent=%@ from rowid=%@ key=%@ id=%@",
                                       nodeDict[@"parent"], nodeid,
                                       nodeDict[@"key"], nodeDict[@"identifier"]);
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
    NSNumber *rootNodeID = nil;
    iTermSessionRestoreDiagLog(@"GT begin transform rows=%lu", (unsigned long)_nodeRows.count);
    NSDictionary<NSNumber *, NSMutableDictionary *> *nodes = [self nodes:&rootNodeID];
    if (!nodes) {
        DLog(@"nodes: returned nil");
        iTermSessionRestoreDiagLog(@"GTERR nodes: returned nil (whole tree dropped)");
        return nil;
    }
    if (!rootNodeID) {
        DLog(@"No root found");
        iTermSessionRestoreDiagLog(@"GTERR no root found among %lu nodes (whole tree dropped)",
                                   (unsigned long)nodes.count);
        return nil;
    }
    if (![self attachChildrenToParents:nodes ignoringRootRowID:rootNodeID]) {
        DLog(@"Failed to attach children to parents");
        iTermSessionRestoreDiagLog(@"GTERR failed to attach children to parents (whole tree dropped)");
        return nil;
    }

    // Finally, we can construct a record.
    return iTermGraphDeltaEncoderMakeGraphRecord(rootNodeID, nodes, @[ @"(root)" ], _database);
}

@end
