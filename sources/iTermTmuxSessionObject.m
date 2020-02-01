//
//  iTermTmuxSessionObject.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/25/19.
//

#import "iTermTmuxSessionObject.h"

@implementation iTermTmuxSessionObject
- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p name=%@ number=%@>", NSStringFromClass(self.class), self, self.name, @(self.number)];
}
@end
