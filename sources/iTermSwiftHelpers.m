//
//  iTermSwiftHelpers.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/22.
//

#import "iTermSwiftHelpers.h"

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

