//
//  ObjCExceptions.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/25/22.
//

#import "ObjCExceptions.h"

NSError * _Nullable ObjCTryImpl(void (^NS_NOESCAPE block)(void)) {
    @try {
        block();
        return nil;
    } @catch (NSException *e) {
        return [NSError errorWithDomain:e.name
                                   code:0
                               userInfo:@{ NSUnderlyingErrorKey: e,
                                           NSDebugDescriptionErrorKey: e.userInfo ?: @{ },
                                           NSLocalizedFailureReasonErrorKey: (e.reason ?: NSLocalizedStringWithDefaultValue(@"ObjCExceptions.UnknownReason", nil, [NSBundle mainBundle], @"Unknown reason", @"Fallback failure reason when a caught exception has no reason")) }];
    }
}
