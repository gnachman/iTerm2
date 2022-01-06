//
//  CapturedOutput.h
//  iTerm2
//
//  Created by George Nachman on 5/23/15.
//
//

#import <Foundation/Foundation.h>

@class CaptureTrigger;
@class iTermCapturedOutputMark;
@class iTermPromise<T>;

@interface CapturedOutput : NSObject
@property(nonatomic, copy) NSString *line;
@property(nonatomic, copy) NSArray *values;
@property(nonatomic, retain) iTermPromise<NSString *> *promisedCommand;
@property(nonatomic, assign) BOOL state;  // user-defined state
#warning TODO: Which threads can access mark? Who can change it? This is risky.
@property(nonatomic, retain) iTermCapturedOutputMark *mark;
@property(nonatomic, assign) long long absoluteLineNumber;

// Used for finding the |mark| later on while deserializing.
@property(nonatomic, copy) NSString *markGuid;

+ (instancetype)capturedOutputWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryValue;
- (BOOL)canMergeFrom:(CapturedOutput *)other;
- (void)mergeFrom:(CapturedOutput *)other;

@end
