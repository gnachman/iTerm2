//
//  iTermGraphDeltaEncoder.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import "iTermGraphDeltaEncoder.h"

#import "NSArray+iTerm.h"

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

- (BOOL)encodeChildWithKey:(NSString *)key
                identifier:(NSString *)identifier
                generation:(NSInteger)generation
                     block:(BOOL (^ NS_NOESCAPE)(iTermGraphEncoder *subencoder))block {
    iTermEncoderGraphRecord *record = [_previousRevision childRecordWithKey:key
                                                                 identifier:identifier];
    if (!record) {
        // A wholly new key+identifier
        [super encodeChildWithKey:key identifier:identifier generation:generation block:block];
        return YES;
    }
    if (record.generation == generation) {
        // No change to generation
        [self encodeGraph:record];
        return YES;
    }
    // Same key+id, new generation.
    NSInteger realGeneration = generation;
    if (generation == iTermGenerationAlwaysEncode) {
        realGeneration = record.generation + 1;
    }
    assert(record.generation < generation);
    iTermGraphEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithKey:key
                                                                  identifier:identifier
                                                                  generation:realGeneration
                                                            previousRevision:record];
    if (!block(encoder)) {
        return NO;
    }
    [self encodeGraph:encoder.record];
    return YES;
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
