//
//  iTermStatusBarLayout.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import "iTermStatusBarLayout.h"

@implementation iTermStatusBarLayout {
    NSMutableArray<id<iTermStatusBarComponent>> *_components;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _components = [NSMutableArray array];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    if (self) {
        _components = [aDecoder decodeObjectOfClass:[NSArray class] forKey:@"components"];
        if (!_components) {
            _components = [NSMutableArray array];
        }
    }
    return self;
}

- (void)addComponent:(id<iTermStatusBarComponent>)component {
    [_components addObject:component];
    [self.delegate statusBarLayoutDidChange:self];
}

- (void)removeComponent:(id<iTermStatusBarComponent>)component {
    [_components removeObject:component];
    [self.delegate statusBarLayoutDidChange:self];
}

- (void)insertComponent:(id<iTermStatusBarComponent>)component atIndex:(NSInteger)index {
    [_components insertObject:component atIndex:index];
    [self.delegate statusBarLayoutDidChange:self];
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_components forKey:@"components"];
}

@end
