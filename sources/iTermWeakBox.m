//
//  iTermWeakBox.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/7/21.
//

#import "iTermWeakBox.h"
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
