//
//  iTermSwiftHelpers.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/22.
//

#import "iTermSwiftHelpers.h"
#import <stdatomic.h>

static _Atomic NSInteger gNextObjectGeneration = 1;

NSInteger iTermAllocateObjectGeneration(void) {
    return atomic_fetch_add(&gNextObjectGeneration, 1);
}

@implementation ObjC: NSObject

+ (BOOL)catching:(void (^ NS_NOESCAPE)(void))block
           error:(NSError * _Nullable __autoreleasing * _Nullable)error {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        *error = [[NSError alloc] initWithDomain:exception.name
                                            code:0
                                        userInfo:exception.userInfo];
        return NO;
    }
}

@end

