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
                                  generation:0
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
        if (row.count != 3) {
            DLog(@"Wrong number of items in row: %@", row);
            _lastError = [NSError errorWithDomain:@"com.iterm2.graph-transformer"
                                             code:1
                                         userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Wrong number of items in row: %@", row] }];
            return nil;
        }
        NSString *key = [NSString castFrom:row[0]];
        NSString *identifier = [NSString castFrom:row[1]];
        NSString *parent = [NSString castFrom:row[2]];
        if (!row || !key || !identifier || !parent) {
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
