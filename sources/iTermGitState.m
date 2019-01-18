//
//  iTermGitState.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import "iTermGitState.h"

@implementation iTermGitState

- (id)copyWithZone:(NSZone *)zone {
    iTermGitState *theCopy = [[iTermGitState alloc] init];
    theCopy.pushArrow = self.pushArrow.copy;
    theCopy.pullArrow = self.pullArrow.copy;
    theCopy.branch = self.branch.copy;
    theCopy.dirty = self.dirty;
    return theCopy;
}

@end
