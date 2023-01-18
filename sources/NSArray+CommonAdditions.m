//
//  NSArray+CommonAdditions.m
//  iTerm2
//
//  Created by George Nachman on 2/24/22.
//

#import "NSArray+CommonAdditions.h"

@implementation NSArray (CommonAdditions)

- (instancetype)mapWithBlock:(id (^NS_NOESCAPE)(id anObject))block {
    NSMutableArray *temp = [NSMutableArray array];
    for (id anObject in self) {
        id mappedObject = block(anObject);
        if (mappedObject) {
            [temp addObject:mappedObject];
        }
    }
    return temp;
}

- (NSArray *)subarrayFromIndex:(NSUInteger)index {
    NSUInteger length;
    if (self.count >= index) {
        length = self.count - index;
    } else {
        return @[];
    }
    return [self subarrayWithRange:NSMakeRange(index, length)];
}

@end
