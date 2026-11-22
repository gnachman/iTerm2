//
//  CapturedOutput.h
//  iTerm2
//
//  Created by George Nachman on 5/23/15.
//
//

#import <Foundation/Foundation.h>

@class CaptureTrigger;
@class CapturedOutput;
@class iTermCapturedOutputMark;
@protocol iTermCapturedOutputMarkReading;
@class iTermPromise<T>;

@protocol CapturedOutputReading<NSObject>
@property(nonatomic, copy, readonly) NSString *line;
@property(nonatomic, copy, readonly) NSArray *values;
@property(nonatomic, strong, readonly) iTermPromise<NSString *> *promisedCommand;
@property(nonatomic, readonly) BOOL state;  // user-defined state
@property(nonatomic, strong, readonly) id<iTermCapturedOutputMarkReading> mark;
@property(nonatomic, readonly) long long absoluteLineNumber;

// Used for finding the |mark| later on while deserializing.
@property(nonatomic, copy, readonly) NSString *markGuid;

// Restorable-state generation of -dictionaryValue. Changes whenever it may have, including when
// promisedCommand resolves. See iTermGeneration.h.
@property(nonatomic, readonly) NSInteger generation;

- (NSDictionary *)dictionaryValue;
- (id<CapturedOutputReading>)doppelganger;
@end

@interface CapturedOutput : NSObject<CapturedOutputReading>
@property(nonatomic, copy, readwrite) NSString *line;
@property(nonatomic, copy, readwrite) NSArray *values;
@property(nonatomic, retain, readwrite) iTermPromise<NSString *> *promisedCommand;
@property(nonatomic, assign, readwrite) BOOL state;  // user-defined state
@property(nonatomic, retain, readwrite) id<iTermCapturedOutputMarkReading> mark;
@property(nonatomic, assign, readwrite) long long absoluteLineNumber;
@property(nonatomic, readonly) BOOL isDoppelganger;

// Used for finding the |mark| later on while deserializing.
@property(nonatomic, copy, readwrite) NSString *markGuid;

+ (instancetype)capturedOutputWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryValue;
- (BOOL)canMergeFrom:(CapturedOutput *)other;
- (void)mergeFrom:(CapturedOutput *)other;

@end
