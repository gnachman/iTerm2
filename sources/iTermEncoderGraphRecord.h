//
//  iTermEncoderGraphRecord.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import <Foundation/Foundation.h>

#import "iTermEncoderPODRecord.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermEncoderGraphRecord: NSObject
@property (nonatomic, readonly) NSDictionary<NSString *, iTermEncoderPODRecord *> *podRecords;
@property (nonatomic, readonly) NSArray<iTermEncoderGraphRecord *> *graphRecords;
@property (nonatomic, readonly) NSInteger generation;
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSString *key;
@property (nonatomic, readonly, weak) iTermEncoderGraphRecord *parent;
@property (nonatomic, readonly) id propertyListValue;

+ (instancetype)withPODs:(NSArray<iTermEncoderPODRecord *> *)podRecords
                  graphs:(NSArray<iTermEncoderGraphRecord *> *)graphRecords
              generation:(NSInteger)generation
                     key:(NSString *)key
              identifier:(NSString *)identifier;

- (void)enumerateValuesVersus:(iTermEncoderGraphRecord * _Nullable)other
                        block:(void (^)(iTermEncoderPODRecord * _Nullable mine,
                                        iTermEncoderPODRecord * _Nullable theirs))block;

- (NSString *)contextWithContext:(NSString *)context;
- (NSComparisonResult)compareGraphRecord:(iTermEncoderGraphRecord *)other;

- (iTermEncoderGraphRecord * _Nullable)childRecordWithKey:(NSString *)key
                                               identifier:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END
