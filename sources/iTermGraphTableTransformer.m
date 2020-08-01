//
//  iTermGraphTableTransformer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import "iTermGraphTableTransformer.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"

static iTermEncoderGraphRecord *iTermGraphDeltaEncoderMakeGraphRecord(NSNumber *nodeID,
                                                                      NSDictionary *nodes) {
    NSDictionary *nodeDict = nodes[nodeID];
    NSArray<NSNumber *> *childNodeIDs = nodeDict[@"children"];
    NSArray<iTermEncoderGraphRecord *> *childGraphRecords =
    [childNodeIDs mapWithBlock:^id(NSNumber *childNodeID) {
        return iTermGraphDeltaEncoderMakeGraphRecord(childNodeID, nodes);
    }];
    return [iTermEncoderGraphRecord withPODs:[nodeDict[@"pod"] allValues]
                                      graphs:childGraphRecords
                                  generation:0
                                         key:nodeDict[@"key"]
                                  identifier:nodeDict[@"identifier"]
                                       rowid:nodeDict[@"rowid"]];
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

- (NSDictionary<NSNumber *, NSMutableDictionary *> *)nodes:(out NSNumber **)rootNodeIDOut {
    // Create nodes
    NSMutableDictionary<NSNumber *, NSMutableDictionary *> *nodes = [NSMutableDictionary dictionary];
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
        NSNumber *parent = [NSNumber castFrom:row[2]];
        NSNumber *rowid = [NSNumber castFrom:row[3]];
        if (!row || !key || !identifier || !parent) {
            DLog(@"Bad row: %@", row);
            _lastError = [NSError errorWithDomain:@"com.iterm2.graph-transformer"
                                             code:1
                                         userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Bad row: %@", row] }];
            return nil;
        }
        if (parent.integerValue == 0 && key.length == 0) {
            if (*rootNodeIDOut) {
                DLog(@"Two roots found");
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
                           @"rowid": rowid } mutableCopy];
    }
    return nodes;
}

- (BOOL)attachValuesToNodes:(NSDictionary<NSNumber *, NSMutableDictionary *> *)nodes {
    for (NSArray *row in _valueRows) {
        if (row.count != 4) {
            DLog(@"Wrong number of fields in row: %@", row);
            _lastError = [NSError errorWithDomain:@"com.iterm2.graph-transformer"
                                             code:1
                                         userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Wrong number of fields in row: %@", row] }];
            return NO;
        }
        NSNumber *nodeid = [NSNumber castFrom:row[0]];
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
    NSDictionary<NSNumber *, NSMutableDictionary *> *nodes = [self nodes:&rootNodeID];
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
    if (![self attachChildrenToParents:nodes ignoringRootRowID:rootNodeID]) {
        DLog(@"Failed to attach children to parents");
        return nil;
    }

    // Finally, we can construct a record.
    return iTermGraphDeltaEncoderMakeGraphRecord(rootNodeID, nodes);
}

@end
