//
//  VT100Screen+Mutation.m
//  iTerm2Shared
//
//  Created by George Nachman on 12/9/21.
//

// For mysterious reasons this needs to be in the iTerm2XCTests to avoid runtime failures to call
// its methods in tests. If I ever have an appetite for risk try https://stackoverflow.com/a/17581430/321984
#import "VT100Screen+Mutation.h"

#import "VT100Screen+Private.h"

@implementation VT100Screen (Mutation)

- (VT100Grid *)mutableCurrentGrid {
    return (VT100Grid *)currentGrid_;
}

- (VT100Grid *)mutableAltGrid {
    return (VT100Grid *)altGrid_;
}

- (VT100Grid *)mutablePrimaryGrid {
    return (VT100Grid *)primaryGrid_;
}

- (LineBuffer *)mutableLineBuffer {
    return (LineBuffer *)linebuffer_;
}

@end
