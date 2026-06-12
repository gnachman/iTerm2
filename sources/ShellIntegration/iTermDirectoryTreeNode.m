//
//  iTermDirectoryTreeNode.m
//  iTerm2
//
//  Created by George Nachman on 10/11/15.
//
//

#import "iTermDirectoryTreeNode.h"

@implementation iTermDirectoryTreeNode

+ (instancetype)nodeWithComponent:(NSString *)component {
    return [[[self alloc] initWithComponent:component] autorelease];
}

- (id)initWithComponent:(NSString *)component {
    self = [super init];
    if (self) {
        _component = [component copy];
        _children = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p component=%@ %lu children>",
            [self class], self, _component, (unsigned long)_children.count];
}

- (int)numberOfChildrenStartingWithString:(NSString *)prefix {
    int number = 0;
    for (NSString *child in _children) {
        if ([child hasPrefix:prefix]) {
            number++;
        }
    }
    return number;
}

- (void)dealloc {
    [_component release];
    [_children release];
    [super dealloc];
}

- (void)removePathWithParts:(NSArray *)parts {
    --_count;
    if (parts.count > 1) {
        NSString *firstPart = parts[0];
        NSArray *tailParts = [parts subarrayWithRange:NSMakeRange(1, parts.count - 1)];
        iTermDirectoryTreeNode *node = _children[firstPart];
        [node removePathWithParts:tailParts];
        if (!node.count) {
            [_children removeObjectForKey:firstPart];
        }
    }
}

@end
