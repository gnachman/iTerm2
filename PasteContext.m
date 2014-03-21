//
//  PasteContext.m
//  iTerm
//
//  Created by George Nachman on 3/12/13.
//
//

#import "PasteContext.h"
#import "iTermSettingsModel.h"

@implementation PasteContext

- (id)initWithBytesPerCallPrefKey:(NSString*)bytesPerCallKey
                     defaultValue:(int)bytesPerCallDefault
         delayBetweenCallsPrefKey:(NSString*)delayBetweenCallsKey
                     defaultValue:(float)delayBetweenCallsDefault
{
    self = [super init];
    if (self) {
        bytesPerCallKey_ = [bytesPerCallKey copy];
        bytesPerCall_ = bytesPerCallDefault;
        delayBetweenCallsKey_ = [delayBetweenCallsKey copy];
        delayBetweenCalls_ = delayBetweenCallsDefault;
        [self updateValues];
    }
    return self;
}

- (void)updateValues {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:bytesPerCallKey_]) {
        bytesPerCall_ = [[NSUserDefaults standardUserDefaults] integerForKey:bytesPerCallKey_];
    }
    if ([[NSUserDefaults standardUserDefaults] objectForKey:delayBetweenCallsKey_]) {
        delayBetweenCalls_ = [[NSUserDefaults standardUserDefaults] floatForKey:delayBetweenCallsKey_];
    }
}

- (int)bytesPerCall {
    return bytesPerCall_;
}

- (void)setBytesPerCall:(int)newBytesPerCall {
    bytesPerCall_ = newBytesPerCall;
    [[NSUserDefaults standardUserDefaults] setInteger:bytesPerCall_ forKey:bytesPerCallKey_];
}

- (float)delayBetweenCalls {
    return delayBetweenCalls_;
}

- (void)setDelayBetweenCalls:(float)newDelayBetweenCalls {
    delayBetweenCalls_ = newDelayBetweenCalls;
    [[NSUserDefaults standardUserDefaults] setFloat:newDelayBetweenCalls
                                             forKey:delayBetweenCallsKey_];
}

@end
