//
//  PasteContext.h
//  iTerm
//
//  Created by George Nachman on 3/12/13.
//
//

#import <Foundation/Foundation.h>

@interface PasteContext : NSObject {
    NSString *bytesPerCallKey_;
    int bytesPerCall_;
    NSString *delayBetweenCallsKey_;
    float delayBetweenCalls_;
}

- (id)initWithBytesPerCallPrefKey:(NSString*)bytesPerCallKey
                     defaultValue:(int)bytesPerCallDefault
         delayBetweenCallsPrefKey:(NSString*)delayBetweenCallsKey
                     defaultValue:(float)delayBetweenCallsDefault;

- (int)bytesPerCall;
- (void)setBytesPerCall:(int)newBytesPerCall;
- (float)delayBetweenCalls;
- (void)setDelayBetweenCalls:(float)newDelayBetweenCalls;
- (void)updateValues;

@end
