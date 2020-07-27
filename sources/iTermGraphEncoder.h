//
//  iTermGraphEncoder.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/26/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, iTermEncoderRecordType) {
    iTermEncoderRecordTypeString,
    iTermEncoderRecordTypeNumber,
    iTermEncoderRecordTypeData,
    iTermEncoderRecordTypeDate,
    iTermEncoderRecordTypeGraph
};

// Encodes plain old data, not graphs.
@interface iTermEncoderPODRecord: NSObject

// type won't be graph
@property (nonatomic, readonly) iTermEncoderRecordType type;
@property (nonatomic, readonly) NSString *key;
@property (nonatomic, readonly) __kindof NSObject *value;

+ (instancetype)withString:(NSString *)string key:(NSString *)key;
+ (instancetype)withNumber:(NSNumber *)number key:(NSString *)key;
+ (instancetype)withData:(NSData *)data key:(NSString *)key;
+ (instancetype)withDate:(NSDate *)date key:(NSString *)key;

@end

@interface iTermEncoderGraphRecord: NSObject
@property (nonatomic, readonly) NSDictionary<NSString *, iTermEncoderPODRecord *> *podRecords;
@property (nonatomic, readonly) NSArray<iTermEncoderGraphRecord *> *graphRecords;
@property (nonatomic, readonly) NSInteger generation;
@property (nonatomic, readonly, nullable) NSString *identifier;
@property (nonatomic, readonly) NSString *key;
@property (nonatomic, readonly, weak) iTermEncoderGraphRecord *parent;

+ (instancetype)withPODs:(NSArray<iTermEncoderPODRecord *> *)podRecords
                  graphs:(NSArray<iTermEncoderGraphRecord *> *)graphRecords
              generation:(NSInteger)generation
                     key:(NSString *)key
              identifier:(NSString * _Nullable)identifier;

- (void)enumerateValuesVersus:(iTermEncoderGraphRecord * _Nullable)other
                        block:(void (^)(iTermEncoderPODRecord * _Nullable mine,
                                        iTermEncoderPODRecord * _Nullable theirs))block;
@end

@interface iTermGraphEncoder : NSObject
@property (nonatomic, readonly) iTermEncoderGraphRecord *record;

- (void)encodeString:(NSString *)string forKey:(NSString *)key;
- (void)encodeNumber:(NSNumber *)number forKey:(NSString *)key;
- (void)encodeData:(NSData *)data forKey:(NSString *)key;
- (void)encodeDate:(NSDate *)date forKey:(NSString *)key;
- (void)encodeGraph:(iTermEncoderGraphRecord *)record;

// When encoding an array where all elements have the same key, use the identifer to distinguish
// array elements. For example, if you have an array of [obj1, obj2, obj3] whose identifiers are
// 1, 2, and 3 respectively and the array's value changes to [obj2, obj3, obj4] then the encoder
// can see that obj2 and obj3 don't need to be re-encoded if their generation is unchanged and
// that it can delete obj1.
- (void)encodeChildWithKey:(NSString *)key
                identifier:(NSString * _Nullable)identifier
                generation:(NSInteger)generation
                     block:(void (^ NS_NOESCAPE)(iTermGraphEncoder *subencoder))block;

- (instancetype)initWithKey:(NSString *)key
                 identifier:(NSString * _Nullable)identifier
                 generation:(NSInteger)generation NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface iTermGraphDeltaEncoder: iTermGraphEncoder
@property (nonatomic, readonly, nullable) iTermEncoderGraphRecord *previousRevision;

- (instancetype)initWithKey:(NSString *)key
                 identifier:(NSString * _Nullable)identifier
                 generation:(NSInteger)generation NS_UNAVAILABLE;

- (instancetype)initWithPreviousRevision:(iTermEncoderGraphRecord * _Nullable)previousRevision;

- (void)enumerateRecords:(void (^)(iTermEncoderGraphRecord * _Nullable before,
                                   iTermEncoderGraphRecord * _Nullable after,
                                   NSString *context))block;

@end

// Converts a table from a db into a graph record.
@interface iTermGraphTableTransformer: NSObject
@property (nonatomic, readonly, nullable) iTermEncoderGraphRecord *root;
@property (nonatomic, readonly) NSArray *nodeRows;
@property (nonatomic, readonly) NSArray *valueRows;

- (instancetype)initWithNodeRows:(NSArray *)nodeRows
                       valueRows:(NSArray *)valueRows NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

#pragma mark - Private - for tests only

- (NSDictionary<NSDictionary *, NSMutableDictionary *> *)nodes:(out NSDictionary **)rootNodeIDOut;
- (BOOL)attachValuesToNodes:(NSDictionary<NSDictionary *, NSMutableDictionary *> *)nodes;
- (BOOL)attachChildrenToParents:(NSDictionary<NSDictionary *, NSMutableDictionary *> *)nodes;

@end

// Encodes a graph to a series of update, insert, and delete instructions.
// Usage:
//
// iTermEncoderGraphRecord *saved =
//   [[[iTermGraphTableTransformer alloc] initWithNodeRows:nodes
//                                               valueRows:values] root];
// iTermGraphDeltaEncoder *encoder = [[iTermGraphSQLEncoder alloc] initWithRecord:saved];
// NSArray<NSString *> *sql =
//   [encoder sqlStatementsForNextRevision:^(iTermGraphEncoder *encoder) {
//     [encoder encodeString:@"red" forKey:@"color"];
//     [encoder encodeChildWithKey:@"tab"
//                      identifier:@"123-456"
//                      generation:tab.generation
//                           block:^(iTermGraphEncoder *subencoder) {
//       [subencoder encodeString:@"Hello world" forKey:@"title"];
//       for (LineBlock *block in blocks) {
//         [subencoder encodeChildWithKey:@"LineBlock"
//                             identifier:block.guid
//                             generation:block.generation
//                                  block:^(iTermGraphEncoder *blockEncoder) {
//           [blockEncoder encodeData:block.data forKey:@"data"];
//         }];
//       }
//     }];
@interface iTermGraphSQLEncoder: NSObject
@property (nonatomic, readonly) iTermEncoderGraphRecord *root;

- (instancetype)initWithRecord:(iTermEncoderGraphRecord *)record NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSArray<NSString *> *)sqlStatementsForNextRevision:(void (^ NS_NOESCAPE)(iTermGraphDeltaEncoder *encoder))block;

@end

NS_ASSUME_NONNULL_END
