//
//  PTYTextViewDataSource.m
//  iTerm2
//
//  Created by George Nachman on 7/26/18.
//

#import <Foundation/Foundation.h>
#import "PTYTextViewDataSource.h"

@implementation PTYTextViewSynchronousUpdateState

- (id)copyWithZone:(NSZone *)zone {
    PTYTextViewSynchronousUpdateState *copy = [[PTYTextViewSynchronousUpdateState alloc] init];
    copy.grid = [self.grid copy];
    copy.cursorVisible = self.cursorVisible;
    copy.colorMap = [self.colorMap copy];
    return copy;

}
@end
