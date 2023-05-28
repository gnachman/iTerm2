//
//  iTermEncoderGraphRecord.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import "iTermEncoderGraphRecord.h"

#import "DebugLogging.h"
#import "iTermChangeTrackingDictionary.h"
#import "iTermTuple.h"
#import "NSArray+iTerm.h"
#import "NSData+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"

@implementation iTermEncoderGraphRecord {
    NSMutableDictionary<iTermTuple<NSString *, NSString *> *, iTermEncoderGraphRecord *> *_index;
}

+ (instancetype)withPODs:(NSDictionary<NSString *, id> *)pod
                  graphs:(NSArray<iTermEncoderGraphRecord *> *)graphRecords
              generation:(NSInteger)generation
                     key:(NSString *)key
              identifier:(NSString *)identifier
                   rowid:(NSNumber *_Nullable)rowid {
    assert(identifier);
    return [[self alloc] initWithPODs:pod
                               graphs:graphRecords
                           generation:generation
                                  key:key
                           identifier:identifier
                                rowid:rowid];
}

- (instancetype)initWithPODs:(NSDictionary<NSString *, id> *)pods
                      graphs:(NSArray<iTermEncoderGraphRecord *> *)graphRecords
                  generation:(NSInteger)generation
                         key:(NSString *)key
                  identifier:(NSString *)identifier
                       rowid:(NSNumber *)rowid {
    assert(key);
    self = [super init];
    if (self) {
        _pod = pods;
        _graphRecords = graphRecords ?: @[];
        [graphRecords enumerateObjectsUsingBlock:^(iTermEncoderGraphRecord * _Nonnull child, NSUInteger idx, BOOL * _Nonnull stop) {
            child->_parent = self;
        }];
        _generation = generation;
        _identifier = identifier;
        _key = key;
        _rowid = rowid;
    }
    return self;
}

- (void)dump {
    [self dumpWithIndent:@""];
}

- (NSString *)compactDescription {
    return [NSString stringWithFormat:@"key=%@ id=%@", self.key, self.identifier];
}

- (void)dumpWithIndent:(NSString *)indent {
    NSLog(@"%@%@[%@] rowid=%@ %@", indent, self.key, self.identifier, self.rowid,
          [[self.pod.allKeys mapWithBlock:^id(NSString *key) {
        return [NSString stringWithFormat:@"%@=%@", key, self.pod[key]];
    }] componentsJoinedByString:@", "]);
    for (iTermEncoderGraphRecord *child in _graphRecords) {
        [child dumpWithIndent:[@"  " stringByAppendingString:indent]];
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<iTermEncoderGraphRecord: rowid=%@ key=%@ gen=%@ id=%@ pod=%@ graphs=%@>",
            self.rowid,
            self.key,
            @(self.generation),
            self.identifier,
            self.pod,
            [[self.graphRecords mapWithBlock:^id(iTermEncoderGraphRecord *anObject) {
        return [NSString stringWithFormat:@"<graph rowid=%@ key=%@ id=%@>",
                anObject.rowid, anObject.key, anObject.identifier];
    }] componentsJoinedByString:@", "]];
}

- (void)setRowid:(NSNumber *)rowid {
    if (_rowid != nil) {
        @throw [NSException exceptionWithName:@"DuplicateRowID"
                                       reason:[NSString stringWithFormat:@"_rowid=%@ setRowid:%@", _rowid, rowid]
                                     userInfo:nil];
    }
    assert(_rowid == nil);
    _rowid = rowid;
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
    if (![other.pod isEqual:self.pod]) {
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
    if (![NSObject object:other.rowid isEqualToObject:self.rowid]) {
        return NO;
    }
    return YES;
}

- (iTermEncoderGraphRecord * _Nullable)childRecordWithKey:(NSString *)key
                                               identifier:(NSString *)identifier {
    if (_index) {
        iTermTuple<NSString *, NSString *> *tuple = [iTermTuple tupleWithObject:key
                                                                      andObject:identifier];
        return _index[tuple];
    }
    return [_graphRecords objectPassingTest:^BOOL(iTermEncoderGraphRecord *element, NSUInteger index, BOOL *stop) {
        return ([element.key isEqualToString:key] &&
                [identifier isEqualToString:element.identifier]);
    }];
}

- (NSMutableDictionary<iTermTuple<NSString *, NSString *> *, iTermEncoderGraphRecord *> *)index {
    [self ensureIndexOfGraphRecords];
    return _index;
}

- (void)ensureIndexOfGraphRecords {
    if (_index) {
        return;
    }
    _index = [NSMutableDictionary dictionary];
    for (iTermEncoderGraphRecord *element in _graphRecords) {
        iTermTuple<NSString *, NSString *> *key = [iTermTuple tupleWithObject:element.key
                                                                    andObject:element.identifier];
        _index[key] = element;
    }
}

- (iTermEncoderGraphRecord * _Nullable)childArrayWithKey:(NSString *)key {
    return [self childRecordWithKey:@"__array" identifier:key];
}

- (iTermEncoderGraphRecord * _Nullable)childDictionaryWithKey:(NSString *)key {
    return [self childRecordWithKey:@"__dict" identifier:key];
}

- (void)enumerateArrayWithKey:(NSString *)key
                        block:(void (^NS_NOESCAPE)(NSString *identifier,
                                                   NSInteger index,
                                                   id obj,
                                                   BOOL *stop))block {
    iTermEncoderGraphRecord *record = [self childArrayWithKey:key];
    if (!record) {
        return;
    }

    NSArray<NSString *> *order = [[NSString castFrom:record.pod[@"__order"]] componentsSeparatedByString:@"\t"] ?: @[];
    order = [order arrayByRemovingDuplicatesStably];
    NSDictionary *items = [[record.graphRecords classifyWithBlock:^id(iTermEncoderGraphRecord *itemRecord) {
        return itemRecord.identifier;
    }] mapValuesWithBlock:^id(id key, NSArray<iTermEncoderGraphRecord *> *object) {
        return object.firstObject.propertyListValue;
    }];
    [order enumerateObjectsUsingBlock:^(NSString * _Nonnull key, NSUInteger idx, BOOL * _Nonnull stop) {
        id item = items[key] ?: record->_pod[key];
        if (item) {
            block(key, idx, item, stop);
        }
    }];
}

- (NSArray *)arrayWithKey:(NSString *)key {
    NSMutableArray *result = [NSMutableArray array];
    [self enumerateArrayWithKey:key block:^(NSString * _Nonnull identifier, NSInteger index, id _Nonnull obj, BOOL * _Nonnull stop) {
        [result addObject:obj];
    }];
    return result;
}

- (NSArray<iTermEncoderGraphRecord *> * _Nullable)recordArrayWithKey:(NSString *)key {
    iTermEncoderGraphRecord *record = [self childArrayWithKey:key];
    if (!record) {
        return nil;
    }

    NSDictionary *items = [[record.graphRecords classifyWithBlock:^id(iTermEncoderGraphRecord *itemRecord) {
        return itemRecord.identifier;
    }] mapValuesWithBlock:^id(id key, NSArray<iTermEncoderGraphRecord *> *object) {
        return object.firstObject;
    }];
    NSArray<NSString *> *order = [[NSString castFrom:record.pod[@"__order"]] componentsSeparatedByString:@"\t"] ?: @[];
    order = [order arrayByRemovingDuplicatesStably];
    return [order mapWithBlock:^id(NSString *key) {
        return items[key];
    }];
}

- (id)objectWithKey:(NSString *)key class:(Class)desiredClass error:(out NSError *__autoreleasing  _Nullable * _Nullable)error {
    id instance = [desiredClass castFrom:_pod[key]];
    if (!instance) {
        if (error) {
            *error = [[NSError alloc] initWithDomain:@"com.iterm2.graph-record" code:1 userInfo:@{ NSLocalizedDescriptionKey: @"No such record or wrong type" }];
        }
        return nil;
    }
    return instance;
}

- (NSInteger)integerWithKey:(NSString *)key error:(out NSError *__autoreleasing  _Nullable * _Nullable)error {
    NSNumber *number = [self objectWithKey:key class:[NSNumber class] error:error];
    return number.integerValue;
}

- (NSString *)stringWithKey:(NSString *)key {
    return [self objectWithKey:key class:[NSString class] error:nil];
}

- (id)objectWithKey:(NSString *)key class:(Class)theClass {
    id obj = self.pod[key];
    if (obj) {
        return [theClass castFrom:obj];
    }
    iTermEncoderGraphRecord *record = [self childRecordWithKey:key identifier:@""];
    return [theClass castFrom:record.propertyListValue];
}

- (NSArray *)arrayValue {
    assert([self.key isEqualToString:@"__array"]);
    NSArray<NSString *> *order = [[NSString castFrom:self.pod[@"__order"]] componentsSeparatedByString:@"\t"] ?: @[];
    order = [order arrayByRemovingDuplicatesStably];
    NSDictionary *items = [[self.graphRecords classifyWithBlock:^id(iTermEncoderGraphRecord *itemRecord) {
        return itemRecord.identifier;
    }] mapValuesWithBlock:^id(id key, NSArray<iTermEncoderGraphRecord *> *object) {
        return object.firstObject.propertyListValue;
    }];
    NSArray *array = [order mapWithBlock:^id(NSString *key) {
        // Arrays encoded using `-[iTermGraphEncoder encodeObject:key:]` use __arrayValue for their key in the POD.
        return items[key][@"__arrayValue"] ?: items[key];
    }];
    return array;
}

- (NSDictionary *)dictionaryValue {
    assert([self.key isEqualToString:@"__dict"]);
    if (self.graphRecords.count == 0) {
        return self.pod;
    }
    NSMutableDictionary *dict = [self.pod mutableCopy];
    for (iTermEncoderGraphRecord *graph in self.graphRecords) {
        if ([graph.key isEqualToString:@"__array"] || [graph.key isEqualToString:@"__dict"]) {
            dict[graph.identifier] = graph.propertyListValue;
        } else {
            dict[graph.key] = graph.propertyListValue;
        }
    }
    return dict;
}

// Was not originally encoded as a dictionary, but we can make one from it nonetheless.
// This is meant as a fallback and may lose information because it ignores identifiers.
- (NSDictionary *)implicitDictionaryValue {
    if (self.graphRecords.count == 0) {
        return self.pod;
    }
    NSMutableDictionary *result = [self.pod ?: @{} mutableCopy];
    [self.graphRecords enumerateObjectsUsingBlock:^(iTermEncoderGraphRecord * _Nonnull child,
                                                    NSUInteger idx,
                                                    BOOL * _Nonnull stop) {
        if (child.identifier.length == 0) {
            result[child.key] = child.propertyListValue;
            return;
        }
        if ([child.key isEqualToString:@"__array"]) {
            result[child.identifier] = [child arrayValue];
        } else if ([child.key isEqualToString:@"__dict"]) {
            result[child.identifier] = [child dictionaryValue];
        } else {
            result[child.key] = [child propertyListValue];
        }
    }];
    return result;
}

- (id)propertyListValue {
    if (self.pod.count == 0 && self.graphRecords.count == 0) {
        return nil;
    }
    if (self.graphRecords.count == 0) {
        return self.pod;
    }
    if ([self.key isEqualToString:@"__dict"]) {
        return [self dictionaryValue];
    }
    if ([self.key isEqualToString:@"__array"] && self.pod[@"__order"]) {
        return [self arrayValue];
    }
    return [self implicitDictionaryValue];
}

- (NSData *)data {
    if (self.pod.count == 0) {
        return [NSData data];
    }
    NSError *error = nil;
    NSData *data = [NSData it_dataWithSecurelyArchivedObject:self.pod error:&error];
    if (error) {
        DLog(@"Failed to serialize pod %@ in %@: %@", self.pod, self, error);
    }
    return data;
}

- (void)eraseRowIDs {
    _rowid = nil;
    [_graphRecords enumerateObjectsUsingBlock:^(iTermEncoderGraphRecord * _Nonnull child, NSUInteger idx, BOOL * _Nonnull stop) {
        [child eraseRowIDs];
    }];
}

@end

@implementation NSObject (iTermEncoderGraphRecord)
+ (nullable instancetype)fromGraphRecord:(iTermEncoderGraphRecord *)record withKey:(NSString *)key {
    return [record objectWithKey:key class:self];
}
@end
