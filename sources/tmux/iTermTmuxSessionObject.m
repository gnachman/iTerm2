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

- (iTermTmuxSessionObject *)copyWithName:(NSString *)name {
    iTermTmuxSessionObject *copy = [[iTermTmuxSessionObject alloc] init];
    copy.name = name;
    copy.number = self.number;
    return copy;
}
@end
