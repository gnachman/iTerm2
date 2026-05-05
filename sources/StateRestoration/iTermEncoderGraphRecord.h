//
//  iTermEncoderGraphRecord.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import <Foundation/Foundation.h>
#import "iTermTuple.h"

NS_ASSUME_NONNULL_BEGIN

// Suffix appended to a child record's key in implicitDictionaryValue to inject
// the record's generation into the resulting dictionary. Consumers can use
// [key stringByAppendingString:iTermEncoderGraphRecordGenerationKeySuffix]
// to look up the generation for a child that was converted to a property list.
extern NSString *const iTermEncoderGraphRecordGenerationKeySuffix;

@class iTermChangeTrackingDictionary;
@class iTermGraphDatabase;

@interface iTermEncoderGraphRecord: NSObject
@property (nonatomic, readonly) NSDictionary<NSString *, id> *pod;
@property (nonatomic, readonly) NSArray<iTermEncoderGraphRecord *> *graphRecords;
@property (nonatomic, readonly) NSInteger generation;
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSString *key;
@property (nonatomic, readonly, weak) iTermEncoderGraphRecord *parent;
@property (nullable, nonatomic, readonly) id propertyListValue;
@property (nullable, nonatomic, strong) NSNumber *rowid;
@property (nonatomic, readonly) NSData *data;  // encoded pod
@property (nonatomic, readonly) NSString *compactDescription;

// For lazy loading of large blobs
@property (nonatomic) BOOL hasLargeData;
@property (nonatomic, weak, nullable) iTermGraphDatabase *database;

+ (instancetype)withPODs:(NSDictionary<NSString *, id> * _Nullable)pod
                  graphs:(NSArray<iTermEncoderGraphRecord *> * _Nullable)graphRecords
              generation:(NSInteger)generation
                     key:(NSString *)key
              identifier:(NSString *)identifier
                   rowid:(NSNumber *_Nullable)rowid;

// Factory method with support for lazy loading of large data
+ (instancetype)withPODs:(NSDictionary<NSString *, id> * _Nullable)pod
                  graphs:(NSArray<iTermEncoderGraphRecord *> * _Nullable)graphRecords
              generation:(NSInteger)generation
                     key:(NSString *)key
              identifier:(NSString *)identifier
                   rowid:(NSNumber *_Nullable)rowid
            hasLargeData:(BOOL)hasLargeData
                database:(iTermGraphDatabase *_Nullable)database;

- (NSComparisonResult)compareGraphRecord:(iTermEncoderGraphRecord *)other;

// You probably want to use arrayWithKey or dictionaryWithKey. This is very low level.
- (iTermEncoderGraphRecord * _Nullable)childRecordWithKey:(NSString *)key
                                               identifier:(NSString *)identifier;
- (void)ensureIndexOfGraphRecords;

- (void)enumerateArrayWithKey:(NSString *)key
                        block:(void (^NS_NOESCAPE)(NSString *identifier,
                                                   NSInteger index,
                                                   id obj,  // could be POD or plist
                                                   BOOL *stop))block;
- (NSArray<iTermEncoderGraphRecord *> * _Nullable)recordArrayWithKey:(NSString *)key;
// Note: this doesn't work for arrays encoded as property lists.
- (NSArray *)arrayWithKey:(NSString *)key;
- (NSInteger)integerWithKey:(NSString *)key error:(out NSError **)error;
- (NSString *)stringWithKey:(NSString *)key;
- (nullable id)objectWithKey:(NSString *)key class:(Class)theClass;
- (void)eraseRowIDs;

// Returns a freshly-allocated tree with the same shape and POD content as the
// receiver, but with `rowid=nil` on every node and no shared instances with
// any existing tree. Children that share a `(key, identifier)` tuple at the
// same level are deduplicated (first occurrence wins, matching the behavior
// of `iTermOrderedDictionary byMapping:`). Used by `iTermGraphDatabase`'s
// recovery path so that the recovery encoder owns its tree exclusively and
// `reallySave`'s INSERT pass visits every record exactly once.
- (iTermEncoderGraphRecord *)deepCopyForRecovery;

- (NSMutableDictionary<iTermTuple<NSString *, NSString *> *, iTermEncoderGraphRecord *> *)index;

@end

@interface NSObject (iTermEncoderGraphRecord)
+ (nullable instancetype)fromGraphRecord:(iTermEncoderGraphRecord *)record withKey:(NSString *)key;
@end

NS_ASSUME_NONNULL_END
