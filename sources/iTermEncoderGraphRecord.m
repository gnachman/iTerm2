//
//  iTermEncoderGraphRecord.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import "iTermEncoderGraphRecord.h"

#import "iTermTuple.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"

@implementation iTermEncoderGraphRecord

+ (instancetype)withPODs:(NSArray<iTermEncoderPODRecord *> *)podRecords
                  graphs:(NSArray<iTermEncoderGraphRecord *> *)graphRecords
              generation:(NSInteger)generation
                     key:(NSString *)key
              identifier:(NSString *)identifier
                   rowid:(NSNumber *)rowid {
    assert(identifier);
    return [[self alloc] initWithPODs:podRecords
                               graphs:graphRecords
                           generation:generation
                                  key:key
                           identifier:identifier
                                rowid:rowid];
}

- (instancetype)initWithPODs:(NSArray<iTermEncoderPODRecord *> *)podRecords
                      graphs:(NSArray<iTermEncoderGraphRecord *> *)graphRecords
                  generation:(NSInteger)generation
                         key:(NSString *)key
                  identifier:(NSString *)identifier
                       rowid:(NSNumber *)rowid {
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
        _rowid = rowid;
    }
    return self;
}

- (void)dump {
    [self dumpWithIndent:@""];
}

- (void)dumpWithIndent:(NSString *)indent {
    NSLog(@"%@%@[%@] rowid=%@ %@", indent, self.key, self.identifier, self.rowid,
          [[self.podRecords.allKeys mapWithBlock:^id(NSString *key) {
        return [NSString stringWithFormat:@"%@=%@", key, self.podRecords[key]];
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
            self.podRecords,
            [[self.graphRecords mapWithBlock:^id(iTermEncoderGraphRecord *anObject) {
        return [NSString stringWithFormat:@"<graph rowid=%@ key=%@ id=%@>",
                anObject.rowid, anObject.key, anObject.identifier];
    }] componentsJoinedByString:@", "]];
}

- (void)setRowid:(NSNumber *)rowid {
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
    if (![NSObject object:other.rowid isEqualToObject:self.rowid]) {
        return NO;
    }
    return YES;
}

- (iTermEncoderGraphRecord * _Nullable)childRecordWithKey:(NSString *)key
                                               identifier:(NSString *)identifier {
    return [_graphRecords objectPassingTest:^BOOL(iTermEncoderGraphRecord *element, NSUInteger index, BOOL *stop) {
        return ([element.key isEqualToString:key] &&
                [identifier isEqualToString:element.identifier]);
    }];
}

- (iTermEncoderGraphRecord * _Nullable)childArrayWithKey:(NSString *)key {
    return [self childRecordWithKey:@"__array" identifier:key];
}

- (iTermEncoderGraphRecord * _Nullable)childDictionaryWithKey:(NSString *)key {
    return [self childRecordWithKey:@"__dict" identifier:key];
}

- (BOOL)enumerateValuesVersus:(iTermEncoderGraphRecord * _Nullable)other
                        block:(void (^)(iTermEncoderPODRecord * _Nullable mine,
                                        iTermEncoderPODRecord * _Nullable theirs,
                                        BOOL *stop))block {
    NSSet<NSString *> *keys = [NSSet setWithArray:[_podRecords.allKeys ?: @[] arrayByAddingObjectsFromArray:other.podRecords.allKeys ?: @[]]];
    __block BOOL ok = YES;
    [keys enumerateObjectsUsingBlock:^(NSString * _Nonnull key, BOOL * _Nonnull stop) {
        block(self.podRecords[key], other.podRecords[key], stop);
        if (*stop) {
            ok = NO;
        }
    }];
    return ok;
}

#warning TODO: Test this
- (void)enumerateArrayWithKey:(NSString *)key
                        block:(void (^NS_NOESCAPE)(NSString *identifier,
                                                   NSInteger index,
                                                   iTermEncoderGraphRecord *obj,
                                                   BOOL *stop))block {
    iTermEncoderGraphRecord *record = [self childArrayWithKey:key];
    if (!record) {
        return;
    }

    NSArray<NSString *> *order = [[NSString castFrom:[record.podRecords[@"__order"] value]] componentsSeparatedByString:@"\t"] ?: @[];
    NSDictionary *items = [[record.graphRecords classifyWithBlock:^id(iTermEncoderGraphRecord *itemRecord) {
        return itemRecord.identifier;
    }] mapValuesWithBlock:^id(id key, NSArray<iTermEncoderGraphRecord *> *object) {
        return object.firstObject.propertyListValue;
    }];
    [order enumerateObjectsUsingBlock:^(NSString * _Nonnull key, NSUInteger idx, BOOL * _Nonnull stop) {
        id item = items[key] ?: record->_podRecords[key].value;
        block(key, idx, item, stop);
    }];
}

- (NSArray *)arrayWithKey:(NSString *)key {
    NSMutableArray *result = [NSMutableArray array];
    [self enumerateArrayWithKey:key block:^(NSString * _Nonnull identifier, NSInteger index, iTermEncoderGraphRecord * _Nonnull obj, BOOL * _Nonnull stop) {
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
    NSArray<NSString *> *order = [[NSString castFrom:[record.podRecords[@"__order"] value]] componentsSeparatedByString:@"\t"] ?: @[];
    return [order mapWithBlock:^id(NSString *key) {
        return items[key];
    }];
}

- (NSInteger)integerWithKey:(NSString *)key error:(out NSError *__autoreleasing  _Nullable * _Nullable)error {
    iTermEncoderPODRecord *record = _podRecords[key];
    if (!record) {
        *error = [[NSError alloc] initWithDomain:@"com.iterm2.graph-record" code:1 userInfo:@{ NSLocalizedDescriptionKey: @"No such record" }];
        return 0;
    }
    if (record.type != iTermEncoderRecordTypeNumber) {
        *error = [[NSError alloc] initWithDomain:@"com.iterm2.graph-record" code:1 userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Type mismatch. Record is %@", record] }];
        return 0;
    }
    return [[record value] integerValue];
}

- (NSString *)stringWithKey:(NSString *)key {
    iTermEncoderPODRecord *record = _podRecords[key];
    if (!record) {
        return nil;
    }
    if (record.type != iTermEncoderRecordTypeString) {
        return nil;
    }
    return [record value];
}

- (NSArray *)arrayValue {
    assert([self.key isEqualToString:@"__array"]);
    NSArray<NSString *> *order = [[NSString castFrom:[self.podRecords[@"__order"] value]] componentsSeparatedByString:@"\t"] ?: @[];
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
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [self.podRecords enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, iTermEncoderPODRecord * _Nonnull pod, BOOL * _Nonnull stop) {
        dict[key] = pod.value;
    }];
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
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [self.podRecords enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, iTermEncoderPODRecord * _Nonnull obj, BOOL * _Nonnull stop) {
        result[key] = obj.value;
    }];
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
    if (self.podRecords.count == 0 && self.graphRecords.count == 0) {
        return nil;
    }
    if ([self.key isEqualToString:@"__dict"]) {
        return [self dictionaryValue];
    }
    if ([self.key isEqualToString:@"__array"] && self.podRecords[@"__order"]) {
        return [self arrayValue];
    }
    return [self implicitDictionaryValue];
}

@end

