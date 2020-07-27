//
//  iTermGraphEncoder.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/26/20.
//

#import "iTermGraphEncoder.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"

static NSString *iTermEncoderRecordTypeToString(iTermEncoderRecordType type)  {
    switch (type) {
        case iTermEncoderRecordTypeData:
            return @"data";
        case iTermEncoderRecordTypeDate:
            return @"date";
        case iTermEncoderRecordTypeGraph:
            return @"graph";
        case iTermEncoderRecordTypeNumber:
            return @"number";
        case iTermEncoderRecordTypeString:
            return @"string";
    }
    return [@(type) stringValue];
}


@implementation iTermEncoderPODRecord

+ (instancetype)withString:(NSString *)string key:(NSString *)key {
    if (!string) {
        return nil;
    }
    return [[self alloc] initWithType:iTermEncoderRecordTypeString
                                  key:key
                                value:string];
}

+ (instancetype)withNumber:(NSNumber *)number key:(NSString *)key {
    if (!number) {
        return nil;
    }
    return [[self alloc] initWithType:iTermEncoderRecordTypeNumber
                                  key:key
                                value:number];
}


+ (instancetype)withData:(NSData *)data key:(NSString *)key {
    if (!data) {
        return nil;
    }
    return [[self alloc] initWithType:iTermEncoderRecordTypeData
                                  key:key
                                value:data];
}


+ (instancetype)withDate:(NSDate *)date key:(NSString *)key {
    if (!date) {
        return nil;
    }
    return [[self alloc] initWithType:iTermEncoderRecordTypeDate
                                  key:key
                                value:date];
}

- (instancetype)initWithType:(iTermEncoderRecordType)type
                         key:(NSString *)key
                       value:(__kindof NSObject *)value {
    self = [super init];
    if (self) {
        _type = type;
        _key = key;
        _value = value;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<iTermEncoderPODRecord: %@=%@ (%@)>", self.key, self.value, iTermEncoderRecordTypeToString(self.type)];
}

- (BOOL)isEqual:(id)object {
    if (object == nil) {
        return NO;
    }
    if (object == self) {
        return YES;
    }
    iTermEncoderPODRecord *other = [iTermEncoderPODRecord castFrom:object];
    if (!other) {
        return NO;
    }
    return (other.type == self.type &&
            [other.key isEqual:self.key] &&
            [other.value isEqual:self.value]);
}

@end

@implementation iTermEncoderGraphRecord

+ (instancetype)withPODs:(NSArray<iTermEncoderPODRecord *> *)podRecords
                  graphs:(NSArray<iTermEncoderGraphRecord *> *)graphRecords
              generation:(NSInteger)generation
                     key:(NSString *)key
              identifier:(NSString * _Nullable)identifier {
    return [[self alloc] initWithPODs:podRecords
                               graphs:graphRecords
                           generation:generation
                                  key:key
                           identifier:identifier];
}

- (instancetype)initWithPODs:(NSArray<iTermEncoderPODRecord *> *)podRecords
                      graphs:(NSArray<iTermEncoderGraphRecord *> *)graphRecords
                  generation:(NSInteger)generation
                         key:(NSString *)key
                  identifier:(NSString * _Nullable)identifier {
    assert(key);
    self = [super init];
    if (self) {
        _podRecords = [[podRecords classifyWithBlock:^id(iTermEncoderPODRecord *record) {
            return record.key;
        }] mapValuesWithBlock:^iTermEncoderPODRecord *(NSString * key,
                                                       NSArray<iTermEncoderPODRecord *> *object) {
            return object.firstObject;
        }];
        assert(_podRecords.count == podRecords.count);
        _graphRecords = graphRecords ?: @[];
        [graphRecords enumerateObjectsUsingBlock:^(iTermEncoderGraphRecord * _Nonnull child, NSUInteger idx, BOOL * _Nonnull stop) {
            child->_parent = self;
        }];
        _generation = generation;
        _identifier = identifier;
        _key = key;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<iTermEncoderGraphRecord: key=%@ gen=%@ id=%@ pod=%@ graphs=%@>",
            self.key,
            @(self.generation),
            self.identifier,
            self.podRecords,
            self.graphRecords];
}

- (NSComparisonResult)compareGraphRecord:(iTermEncoderGraphRecord *)other {
    NSComparisonResult result = [self.key compare:other.key];
    if (result != NSOrderedSame) {
        return result;
    }
    result = [@(self.generation) compare:@(other.generation)];
    if (result != NSOrderedSame) {
        return result;
    }
    result = [self.identifier ?: @"" compare:other.identifier ?: @""];
    if (result != NSOrderedSame) {
        return result;
    }
    return NSOrderedSame;
}

- (BOOL)isEqual:(id)object {
    if (object == nil) {
        return NO;
    }
    if (object == self) {
        return YES;
    }
    iTermEncoderGraphRecord *other = [iTermEncoderGraphRecord castFrom:object];
    if (!other) {
        return NO;
    }
    if (![other.key isEqual:self.key]) {
        return NO;
    }
    if (![other.podRecords isEqual:self.podRecords]) {
        return NO;
    }
    if (![[other.graphRecords sortedArrayUsingSelector:@selector(compareGraphRecord:)] isEqual:[self.graphRecords  sortedArrayUsingSelector:@selector(compareGraphRecord:)]]) {
        return NO;
    }
    if (other.generation != self.generation) {
        return NO;
    }
    if (![NSObject object:other.identifier ?: @"" isEqualToObject:self.identifier ?: @""]) {
        return NO;
    }
    return YES;
}

- (iTermEncoderGraphRecord * _Nullable)childRecordWithKey:(NSString *)key
                                               identifier:(NSString * _Nullable)identifier {
    return [_graphRecords objectPassingTest:^BOOL(iTermEncoderGraphRecord *element, NSUInteger index, BOOL *stop) {
        return ([element.key isEqualToString:key] &&
                [(identifier ?: @"") isEqualToString:(element.identifier ?: @"")]);
    }];
}

- (NSString *)nodeid {
    return [NSString stringWithFormat:@"%@,%@,%@", self.key, self.identifier ?: @"", @(self.generation)];
}

- (void)enumerateValuesVersus:(iTermEncoderGraphRecord * _Nullable)other
                        block:(void (^)(iTermEncoderPODRecord * _Nullable mine,
                                        iTermEncoderPODRecord * _Nullable theirs))block {
    NSSet<NSString *> *keys = [NSSet setWithArray:[_podRecords.allKeys ?: @[] arrayByAddingObjectsFromArray:other.podRecords.allKeys ?: @[]]];
    [keys enumerateObjectsUsingBlock:^(NSString * _Nonnull key, BOOL * _Nonnull stop) {
        block(self.podRecords[key], other.podRecords[key]);
    }];
}

@end

@implementation iTermGraphEncoder {
    NSMutableDictionary<NSString *, iTermEncoderPODRecord *> *_pod;
    NSString * _Nullable _identifier;
    NSInteger _generation;
    NSString *_key;
    NSMutableArray<iTermEncoderGraphRecord *> *_children;
    BOOL _committed;
    iTermEncoderGraphRecord *_record;
}

- (instancetype)initWithKey:(NSString *)key
                 identifier:(NSString * _Nullable)identifier
                 generation:(NSInteger)generation {
    self = [super init];
    if (self) {
        _key = key;
        _identifier = identifier;
        _generation = generation;
        _pod = [NSMutableDictionary dictionary];
        _children = [NSMutableArray array];
    }
    return self;
}


- (void)encodeString:(NSString *)string forKey:(NSString *)key {
    assert(!_committed);
    _pod[key] = [iTermEncoderPODRecord withString:string key:key];
}

- (void)encodeNumber:(NSNumber *)number forKey:(NSString *)key {
    assert(!_committed);
    _pod[key] = [iTermEncoderPODRecord withNumber:number key:key];
}

- (void)encodeData:(NSData *)data forKey:(NSString *)key {
    assert(!_committed);
    _pod[key] = [iTermEncoderPODRecord withData:data key:key];
}

- (void)encodeDate:(NSDate *)date forKey:(NSString *)key {
    assert(!_committed);
    _pod[key] = [iTermEncoderPODRecord withDate:date key:key];
}

- (void)encodeGraph:(iTermEncoderGraphRecord *)record {
    assert(!_committed);
    [_children addObject:record];
}

- (void)encodeChildWithKey:(NSString *)key
                identifier:(NSString * _Nullable)identifier
                generation:(NSInteger)generation
                     block:(void (^ NS_NOESCAPE)(iTermGraphEncoder *subencoder))block {
    assert(!_committed);
    iTermGraphEncoder *encoder = [[iTermGraphEncoder alloc] initWithKey:key identifier:identifier generation:generation];
    block(encoder);
    [self encodeGraph:encoder.record];
}

- (iTermEncoderGraphRecord *)record {
    if (!_committed) {
        _committed = YES;
        _record = [iTermEncoderGraphRecord withPODs:_pod.allValues
                                             graphs:_children
                                         generation:_generation
                                                key:_key
                                         identifier:_identifier];
    }
    return _record;
}

@end

static NSDictionary *iTermGraphEncoderNodeIDFromString(NSString *string) {
    assert(string);
    if (string.length == 0) {
        return @{};
    }
    NSArray<NSString *> *parts = [string componentsSeparatedByString:@","];
    assert(parts.count == 3);
    return @{ @"key": parts[0],
              @"identifier": parts[1],
              @"generation": @([parts[2] integerValue]) };
}

static iTermEncoderGraphRecord *iTermGraphDeltaEncoderMakeGraphRecord(NSDictionary *nodeID,
                                                                      NSDictionary *nodes) {
    NSDictionary *nodeDict = nodes[nodeID];
    NSArray<NSDictionary *> *childNodeIDs = nodeDict[@"children"];
    NSArray<iTermEncoderGraphRecord *> *childGraphRecords =
    [childNodeIDs mapWithBlock:^id(NSDictionary *childNodeID) {
        return iTermGraphDeltaEncoderMakeGraphRecord(childNodeID, nodes);
    }];
    return [iTermEncoderGraphRecord withPODs:[nodeDict[@"pod"] allValues]
                                      graphs:childGraphRecords
                                  generation:[nodeID[@"generation"] integerValue]
                                         key:nodeID[@"key"]
                                  identifier:nodeID[@"identifier"]];
};

@implementation iTermGraphDeltaEncoder

- (instancetype)initWithPreviousRevision:(iTermEncoderGraphRecord * _Nullable)previousRevision {
    return [self initWithKey:@""
                  identifier:nil
                  generation:previousRevision.generation + 1
            previousRevision:previousRevision];
}

- (instancetype)initWithKey:(NSString *)key
                 identifier:(NSString * _Nullable)identifier
                 generation:(NSInteger)generation
           previousRevision:(iTermEncoderGraphRecord * _Nullable)previousRevision {
    self = [super initWithKey:key identifier:identifier generation:generation];
    if (self) {
        _previousRevision = previousRevision;
    }
    return self;
}

- (void)encodeChildWithKey:(NSString *)key
                identifier:(NSString * _Nullable)identifier
                generation:(NSInteger)generation
                     block:(void (^ NS_NOESCAPE)(iTermGraphEncoder *subencoder))block {
    iTermEncoderGraphRecord *record = [_previousRevision childRecordWithKey:key
                                                                 identifier:identifier];
    if (!record) {
        // A wholly new key+identifier
        [super encodeChildWithKey:key identifier:identifier generation:generation block:block];
        return;
    }
    if (record.generation == generation) {
        // No change to generation
        [self encodeGraph:record];
        return;
    }
    // Same key+id, new generation.
    assert(record.generation < generation);
    iTermGraphEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithKey:key
                                                                  identifier:identifier
                                                                  generation:generation
                                                            previousRevision:record];
    block(encoder);
    [self encodeGraph:encoder.record];
}

- (void)enumerateRecords:(void (^)(iTermEncoderGraphRecord * _Nullable before,
                                   iTermEncoderGraphRecord * _Nullable after,
                                   NSString *context))block {
    block(_previousRevision, self.record, @"");
    [self enumerateBefore:_previousRevision after:self.record context:@"" block:block];
}

- (void)enumerateBefore:(iTermEncoderGraphRecord *)preRecord
                  after:(iTermEncoderGraphRecord *)postRecord
                context:(NSString *)context
                  block:(void (^)(iTermEncoderGraphRecord * _Nullable before,
                                  iTermEncoderGraphRecord * _Nullable after,
                                  NSString *context))block {
    NSDictionary<NSDictionary *, NSArray<iTermEncoderGraphRecord *> *> *before = [preRecord.graphRecords classifyWithBlock:^id(iTermEncoderGraphRecord *record) {
        return @{ @"key": record.key,
                  @"identifier": record.identifier ?: @"" };
    }];
    NSDictionary<NSDictionary *, NSArray<iTermEncoderGraphRecord *> *> *after = [postRecord.graphRecords classifyWithBlock:^id(iTermEncoderGraphRecord *record) {
        return @{ @"key": record.key,
                  @"identifier": record.identifier ?: @"" };
    }];
    NSSet<NSDictionary *> *allKeys = [NSSet setWithArray:[before.allKeys ?: @[] arrayByAddingObjectsFromArray:after.allKeys ?: @[] ]];
    [allKeys enumerateObjectsUsingBlock:^(NSDictionary * _Nonnull keyId, BOOL * _Nonnull stop) {
        // Run the block for this pair of nodes
        block(before[keyId].firstObject, after[keyId].firstObject, context);

        // Now recurse for their descendants.
        NSMutableString *newContext = [context mutableCopy];
        if (context.length > 0) {
            [newContext appendString:@"."];
        }
        [newContext appendString:keyId[@"key"]];
        NSString *identifier = keyId[@"identifier"];
        if (identifier.length) {
            [newContext appendFormat:@"[%@]", identifier];
        }
        [self enumerateBefore:before[keyId].firstObject
                        after:after[keyId].firstObject
                      context:newContext
                        block:block];
    }];
}


@end

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

- (NSDictionary<NSDictionary *, NSMutableDictionary *> *)nodes:(out NSDictionary **)rootNodeIDOut {
    // Create nodes
    NSMutableDictionary<NSDictionary *, NSMutableDictionary *> *nodes = [NSMutableDictionary dictionary];
    for (NSArray *row in _nodeRows) {
        NSString *key = [NSString castFrom:row[0]];
        NSString *identifier = [NSString castFrom:row[1] ?: @""];
        NSString *parent = [NSString castFrom:row[2]];
        NSNumber *generation = [NSNumber castFrom:row[3]];
        if (!row || !key || !identifier || !parent || !generation) {
            DLog(@"Bad row: %@", row);
            return nil;
        }
        NSDictionary *nodeid = @{ @"key": key,
                                  @"identifier": identifier,
                                  @"generation": generation };
        if (parent.length == 0) {
            if (*rootNodeIDOut) {
                DLog(@"Two roots found");
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

- (BOOL)attachValuesToNodes:(NSDictionary<NSDictionary *, NSMutableDictionary *> *)nodes {
    for (NSArray *row in _valueRows) {
        NSString *nodeidString = [NSString castFrom:row[0]];
        NSString *key = [NSString castFrom:row[1]];
        NSNumber *type = [NSNumber castFrom:row[3]];
        if (!nodeidString || !key || !type) {
            DLog(@"Bogus row: %@", row);
            return NO;
        }
        iTermEncoderPODRecord *record = nil;
        switch ((iTermEncoderRecordType)type.unsignedIntegerValue) {
            case iTermEncoderRecordTypeString:
                record = [iTermEncoderPODRecord withString:[NSString castFrom:row[2]] key:key];
                break;
            case iTermEncoderRecordTypeNumber:
                record = [iTermEncoderPODRecord withNumber:[NSNumber castFrom:row[2]] key:key];
                break;
            case iTermEncoderRecordTypeData:
                record = [iTermEncoderPODRecord withData:[NSData castFrom:row[2]] key:key];
                break;
            case iTermEncoderRecordTypeDate:
                record = [iTermEncoderPODRecord withDate:[NSDate castFrom:row[2]] key:key];
                break;
            case iTermEncoderRecordTypeGraph:
                DLog(@"Unexpected graph POD");
                return NO;
        }
        if (!record) {
            DLog(@"Bogus value with type %@: %@", type, row[2]);
            return NO;
        }
        NSDictionary *nodeid = iTermGraphEncoderNodeIDFromString(nodeidString);
        if (!nodeid) {
            DLog(@"Bad node ID: %@", nodeidString);
            return NO;
        }
        NSMutableDictionary *nodeDict = nodes[nodeid];
        if (!nodeDict) {
            DLog(@"No such node: %@", nodeid);
            return NO;
        }
        NSMutableDictionary *pod = nodeDict[@"pod"];
        pod[key] = record;
    }
    return YES;
}

- (BOOL)attachChildrenToParents:(NSDictionary<NSDictionary *, NSMutableDictionary *> *)nodes {
    __block BOOL ok = YES;
    [nodes enumerateKeysAndObjectsUsingBlock:^(NSDictionary * _Nonnull nodeid,
                                               NSMutableDictionary * _Nonnull nodeDict,
                                               BOOL * _Nonnull stop) {
        NSDictionary *parentID = iTermGraphEncoderNodeIDFromString(nodeDict[@"parent"]);
        if (parentID.count == 0) {
            // This is the root.
            return;
        }
        NSMutableDictionary *parentDict = nodes[parentID];
        if (!parentDict) {
            ok = NO;
            DLog(@"Dangling parent pointer %@ from %@", parentID, nodeid);
            *stop = YES;
        }
        NSMutableArray *children = parentDict[@"children"];
        [children addObject:nodeid];
    }];
    return ok;
}

- (iTermEncoderGraphRecord * _Nullable)transform {
    NSDictionary *rootNodeID = nil;
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

@implementation iTermGraphSQLEncoder

- (instancetype)initWithRecord:(iTermEncoderGraphRecord *)record {
    self = [super init];
    if (self) {
        _root = record;
    }
    return self;
}

- (NSArray<NSString *> *)sqlStatementsForNextRevision:(void (^ NS_NOESCAPE)(iTermGraphDeltaEncoder *encoder))block {
    iTermGraphDeltaEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:_root];
    block(encoder);
    NSMutableArray<NSString *> *sql = [NSMutableArray array];
    [encoder enumerateRecords:^(iTermEncoderGraphRecord * _Nullable before,
                                iTermEncoderGraphRecord * _Nullable after,
                                NSString *context) {
        // TODO
    }];
    return sql;
}

@end
