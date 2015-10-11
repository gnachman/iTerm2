//
//  PasteContext.h
//  iTerm
//
//  Created by George Nachman on 3/12/13.
//
//

#import <Foundation/Foundation.h>

@interface PasteContext : NSObject

- (instancetype)initWithBytesPerCallPrefKey:(NSString*)bytesPerCallKey
                     defaultValue:(int)bytesPerCallDefault
         delayBetweenCallsPrefKey:(NSString*)delayBetweenCallsKey
                     defaultValue:(float)delayBetweenCallsDefault;

@property(nonatomic, assign) BOOL blockAtNewline;
@property(nonatomic, assign) BOOL isBlocked;

@property int bytesPerCall;
@property float delayBetweenCalls;
- (void)updateValues;

@end
