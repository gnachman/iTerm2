//
//  PasteContext.m
//  iTerm
//
//  Created by George Nachman on 3/12/13.
//
//

#import "PasteContext.h"
#import "iTermAdvancedSettingsModel.h"

@implementation PasteContext {
    NSString *bytesPerCallKey_;
    int bytesPerCall_;
    NSString *delayBetweenCallsKey_;
    float delayBetweenCalls_;
}

@synthesize delayBetweenCalls = delayBetweenCalls_;
@synthesize bytesPerCall = bytesPerCall_;

- (instancetype)initWithBytesPerCallPrefKey:(NSString*)bytesPerCallKey
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
    if (bytesPerCallKey_ && [[NSUserDefaults standardUserDefaults] objectForKey:bytesPerCallKey_]) {
        bytesPerCall_ = [[NSUserDefaults standardUserDefaults] integerForKey:bytesPerCallKey_];
    }
    if (delayBetweenCallsKey_ && [[NSUserDefaults standardUserDefaults] objectForKey:delayBetweenCallsKey_]) {
        delayBetweenCalls_ = [[NSUserDefaults standardUserDefaults] floatForKey:delayBetweenCallsKey_];
    }
}

- (int)bytesPerCall {
    return bytesPerCall_;
}

- (void)setBytesPerCall:(int)newBytesPerCall {
    bytesPerCall_ = newBytesPerCall;
    if (bytesPerCallKey_) {
        [[NSUserDefaults standardUserDefaults] setInteger:bytesPerCall_ forKey:bytesPerCallKey_];
    }
}

- (float)delayBetweenCalls {
    return delayBetweenCalls_;
}

- (void)setDelayBetweenCalls:(float)newDelayBetweenCalls {
    delayBetweenCalls_ = newDelayBetweenCalls;
    if (delayBetweenCallsKey_) {
        [[NSUserDefaults standardUserDefaults] setFloat:newDelayBetweenCalls
                                                 forKey:delayBetweenCallsKey_];
    }
}

@end
