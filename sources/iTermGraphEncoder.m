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
#import "iTermTuple.h"

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

+ (instancetype)withData:(NSData *)data type:(iTermEncoderRecordType)type key:(NSString *)key {
    id obj = nil;
    switch (type) {
        case iTermEncoderRecordTypeString:
            obj = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            break;
        case iTermEncoderRecordTypeNumber: {
            double d;
            if (data.length == sizeof(d)) {
                memmove(&d, data.bytes, sizeof(d));
                obj = @(d);
            }
            break;
        }
        case iTermEncoderRecordTypeData:
            obj = data;
            break;
        case iTermEncoderRecordTypeDate: {
            NSTimeInterval d;
            if (data.length == sizeof(d)) {
                memmove(&d, data.bytes, sizeof(d));
                obj = [NSDate dateWithTimeIntervalSince1970:d];
            }
            break;
        }
        case iTermEncoderRecordTypeGraph:
            DLog(@"Unexpected graph POD");
            assert(NO);
            break;
    }
    if (!obj) {
        return nil;
    }
    return [[self alloc] initWithType:type
                                  key:key
                                value:obj];
}

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
    if (other.type != self.type) {
        return NO;
    }
    if (![other.key isEqual:self.key]) {
        return NO;
    }
    if (![other.value isEqual:self.value]) {
        return NO;
    }
    return YES;
}

- (NSData *)data {
    switch (_type) {
        case iTermEncoderRecordTypeData:
            return _value;
        case iTermEncoderRecordTypeDate: {
            NSTimeInterval timeInterval = [(NSDate *)_value timeIntervalSince1970];
            return [NSData dataWithBytes:&timeInterval length:sizeof(timeInterval)];
        }
        case iTermEncoderRecordTypeNumber: {
            const double d = [_value doubleValue];
            return [NSData dataWithBytes:&d length:sizeof(d)];
        }
        case iTermEncoderRecordTypeString:
            return [(NSString *)_value dataUsingEncoding:NSUTF8StringEncoding];
        case iTermEncoderRecordTypeGraph:
            assert(NO);
    }
}
@end

@implementation iTermEncoderGraphRecord

+ (instancetype)withPODs:(NSArray<iTermEncoderPODRecord *> *)podRecords
                  graphs:(NSArray<iTermEncoderGraphRecord *> *)graphRecords
              generation:(NSInteger)generation
                     key:(NSString *)key
              identifier:(NSString *)identifier {
    assert(identifier);
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
                  identifier:(NSString *)identifier {
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

- (iTermEncoderGraphRecord *)copyWithIdentifier:(NSString *)identifier {
    return [[iTermEncoderGraphRecord alloc] initWithPODs:_podRecords.allValues
                                                  graphs:_graphRecords
                                              generation:_generation
                                                     key:_key
                                              identifier:identifier];
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
    result = [self.identifier compare:other.identifier];
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
    if (![NSObject object:other.identifier isEqualToObject:self.identifier]) {
        return NO;
    }
    return YES;
}

NSString *iTermGraphContext(NSString *context, NSString *key, NSString *identifier) {
    NSMutableString *result = [NSMutableString string];
    if (context.length) {
        [result appendString:context];
        [result appendString:@"."];
    }
    [result appendString:key];
    if (identifier.length) {
        [result appendFormat:@"[%@]", identifier];
    }
    return result;
}

static iTermTuple<NSString *, NSString *> *iTermSplitLastCharacter(NSString *string, NSString *c) {
    const NSRange range = [string rangeOfString:c options:NSBackwardsSearch];
    if (range.location == NSNotFound) {
        return [iTermTuple tupleWithObject:@"" andObject:string];
    }
    return [iTermTuple tupleWithObject:[string substringToIndex:range.location]
                             andObject:[string substringFromIndex:NSMaxRange(range)]];
}

iTermGraphExplodedContext iTermGraphExplodeContext(NSString *context) {
    iTermTuple<NSString *, NSString *> *parentTail = iTermSplitLastCharacter(context, @".");
    NSString *key;
    NSString *identifier = @"";
    if ([context hasSuffix:@"]"]) {
        iTermTuple<NSString *, NSString *> *keyTail = iTermSplitLastCharacter(parentTail.secondObject, @"[");
        key = keyTail.firstObject;
        iTermTuple<NSString *, NSString *> *identifierTail = iTermSplitLastCharacter(keyTail.secondObject, @"]");
        identifier = identifierTail.firstObject;
    } else {
        key = parentTail.secondObject;
    }
    return (iTermGraphExplodedContext) {
        .context = parentTail.firstObject,
        .key = key,
        .identifier = identifier
    };
}

- (NSString *)contextWithContext:(NSString *)context {
    return iTermGraphContext(context, self.key, self.identifier);
}

- (iTermEncoderGraphRecord * _Nullable)childRecordWithKey:(NSString *)key
                                               identifier:(NSString *)identifier {
    return [_graphRecords objectPassingTest:^BOOL(iTermEncoderGraphRecord *element, NSUInteger index, BOOL *stop) {
        return ([element.key isEqualToString:key] &&
                [identifier isEqualToString:element.identifier]);
    }];
}

- (NSString *)nodeid {
    return [NSString stringWithFormat:@"%@,%@,%@", self.key, self.identifier, @(self.generation)];
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
    NSString *_identifier;
    NSInteger _generation;
    NSString *_key;
    NSMutableArray<iTermEncoderGraphRecord *> *_children;
    BOOL _committed;
    iTermEncoderGraphRecord *_record;
}

- (instancetype)initWithKey:(NSString *)key
                 identifier:(NSString *)identifier
                 generation:(NSInteger)generation {
    assert(identifier);
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
                identifier:(NSString *)identifier
                generation:(NSInteger)generation
                     block:(void (^ NS_NOESCAPE)(iTermGraphEncoder *subencoder))block {
    assert(!_committed);
    iTermGraphEncoder *encoder = [[iTermGraphEncoder alloc] initWithKey:key
                                                             identifier:identifier
                                                             generation:generation];
    block(encoder);
    [self encodeGraph:encoder.record];
}

- (void)encodeArrayWithKey:(NSString *)key
                generation:(NSInteger)generation
               identifiers:(NSArray<NSString *> *)identifiers
                     block:(void (^ NS_NOESCAPE)(NSString *identifier, NSInteger index, iTermGraphEncoder *subencoder))block {
    [self encodeChildWithKey:@"__array" identifier:key generation:generation block:^(iTermGraphEncoder * _Nonnull subencoder) {
        [identifiers enumerateObjectsUsingBlock:^(NSString * _Nonnull identifier, NSUInteger idx, BOOL * _Nonnull stop) {
            block(identifier, idx, subencoder);
        }];
        [subencoder encodeString:[identifiers componentsJoinedByString:@","] forKey:@"__order"];
    }];
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

@implementation iTermGraphDeltaEncoder

- (instancetype)initWithPreviousRevision:(iTermEncoderGraphRecord * _Nullable)previousRevision {
    return [self initWithKey:@""
                  identifier:@""
                  generation:previousRevision.generation + 1
            previousRevision:previousRevision];
}

- (instancetype)initWithKey:(NSString *)key
                 identifier:(NSString *)identifier
                 generation:(NSInteger)generation
           previousRevision:(iTermEncoderGraphRecord * _Nullable)previousRevision {
    assert(identifier);
    self = [super initWithKey:key identifier:identifier generation:generation];
    if (self) {
        _previousRevision = previousRevision;
    }
    return self;
}

- (void)encodeChildWithKey:(NSString *)key
                identifier:(NSString *)identifier
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
                  @"identifier": record.identifier };
    }];
    NSDictionary<NSDictionary *, NSArray<iTermEncoderGraphRecord *> *> *after = [postRecord.graphRecords classifyWithBlock:^id(iTermEncoderGraphRecord *record) {
        return @{ @"key": record.key,
                  @"identifier": record.identifier };
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


