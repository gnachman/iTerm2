//
//  iTermDirectoryTree.m
//  iTerm2
//
//  Created by George Nachman on 10/11/15.
//
//

#import "iTermDirectoryTree.h"
#import "iTermDirectoryTreeNode.h"
#import "NSMutableAttributedString+iTerm.h"

@implementation iTermDirectoryTree

- (id)init {
    self = [super init];
    if (self) {
        _root = [[iTermDirectoryTreeNode alloc] initWithComponent:nil];
    }
    return self;
}

- (void)dealloc {
    [_root release];
    [super dealloc];
}

+ (NSMutableArray *)attributedComponentsInPath:(NSAttributedString *)path {
    NSMutableArray *components = [[[path attributedComponentsSeparatedByString:@"/"] mutableCopy] autorelease];
    for (int i = components.count - 1; i >= 0; i--) {
        if ([components[i] string].length == 0) {
            [components removeObjectAtIndex:i];
        }
    }
    return components;
}

+ (NSMutableArray *)componentsInPath:(NSString *)path {
    if (!path) {
        return nil;
    }
    NSMutableArray *components = [[[path componentsSeparatedByString:@"/"] mutableCopy] autorelease];
    NSUInteger index = [components indexOfObject:@""];
    while (index != NSNotFound && components.count > 0) {
        [components removeObjectAtIndex:index];
        index = [components indexOfObject:@""];
    }
    return components;
}

- (void)addPath:(NSString *)path {
    NSArray *parts = [iTermDirectoryTree componentsInPath:path];
    if (!parts.count) {
        return;
    }
    iTermDirectoryTreeNode *parent = _root;
    parent.count = parent.count + 1;
    for (int i = 0; i < parts.count; i++) {
        NSString *part = parts[i];
        iTermDirectoryTreeNode *node = parent.children[part];
        if (!node) {
            node = [iTermDirectoryTreeNode nodeWithComponent:part];
            parent.children[part] = node;
        }
        node.count = node.count + 1;
        parent = node;
    }
}

- (void)removePath:(NSString *)path {
    NSArray *parts = [iTermDirectoryTree  componentsInPath:path];
    if (!parts.count) {
        return;
    }
    [_root removePathWithParts:parts];
}

- (NSIndexSet *)abbreviationSafeIndexesInPath:(NSString *)path {
    NSArray *parts = [iTermDirectoryTree  componentsInPath:path];
    iTermDirectoryTreeNode *node = _root;
    NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];
    for (int i = 0; i < parts.count; i++) {
        NSString *part = parts[i];
        NSString *prefix = [part substringToIndex:1];
        if ([node numberOfChildrenStartingWithString:prefix] <= 1) {
            [indexSet addIndex:i];
        }
        node = node.children[part];
    }
    return indexSet;
}

@end
