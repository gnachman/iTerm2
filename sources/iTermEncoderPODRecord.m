//
//  iTermEncoderPODRecord.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import "iTermEncoderPODRecord.h"

#import "DebugLogging.h"
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
        case iTermEncoderRecordTypeNull:
            return @"null";
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
        case iTermEncoderRecordTypeNull:
            obj = [NSNull null];
            break;
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

+ (instancetype)withNullForKey:(NSString *)key {
    return [[self alloc] initWithType:iTermEncoderRecordTypeNull
                                  key:key
                                value:[NSNull null]];
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
        case iTermEncoderRecordTypeNull:
            return [NSData data];
        case iTermEncoderRecordTypeGraph:
            assert(NO);
    }
}
@end
