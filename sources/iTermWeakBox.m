//
//  iTermWeakBox.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/7/21.
//

#import "iTermWeakBox.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"

@implementation iTermWeakBox

+ (instancetype)boxFor:(id)object {
    return [[self alloc] initWithObject:object];
}

- (instancetype)initWithObject:(id)object {
    self = [super init];
    if (self) {
        _object = object;
    }
    return self;
}

@end

@implementation NSMutableArray(WeakBox)

- (void)removeWeakBoxedObject:(id)object {
    const NSInteger i = [self indexOfObjectPassingTest:^BOOL(iTermWeakBox *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return obj.object == object;
    }];
    if (i != NSNotFound) {
        [self removeObjectAtIndex:i];
    }
}

- (void)pruneEmptyWeakBoxes {
    [self removeObjectsPassingTest:^BOOL(iTermWeakBox *box) {
        return box.object == nil;
    }];
}
@end

