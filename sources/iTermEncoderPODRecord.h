//
//  iTermEncoderPODRecord.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, iTermEncoderRecordType) {
    iTermEncoderRecordTypeString,
    iTermEncoderRecordTypeNumber,
    iTermEncoderRecordTypeData,
    iTermEncoderRecordTypeDate,
    iTermEncoderRecordTypeNull,
    iTermEncoderRecordTypeGraph,
};

// Encodes plain old data, not graphs.
@interface iTermEncoderPODRecord: NSObject

// type won't be graph
@property (nonatomic, readonly) iTermEncoderRecordType type;
@property (nonatomic, readonly) NSString *key;
@property (nonatomic, readonly) __kindof NSObject *value;
@property (nonatomic, readonly) NSData *data;

+ (instancetype)withData:(NSData *)data type:(iTermEncoderRecordType)type key:(NSString *)key;
+ (instancetype)withString:(NSString *)string key:(NSString *)key;
+ (instancetype)withNumber:(NSNumber *)number key:(NSString *)key;
+ (instancetype)withData:(NSData *)data key:(NSString *)key;
+ (instancetype)withDate:(NSDate *)date key:(NSString *)key;
+ (instancetype)withNullForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
