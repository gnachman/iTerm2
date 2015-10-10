//
//  iTermDirectoryTreeNode.h
//  iTerm2
//
//  Created by George Nachman on 10/11/15.
//
//

#import <Foundation/Foundation.h>

@interface iTermDirectoryTreeNode : NSObject

@property(nonatomic, copy) NSString *component;
@property(nonatomic, readonly) NSMutableDictionary<NSString *, iTermDirectoryTreeNode *> *children;
@property(nonatomic, assign) int count;

- (id)initWithComponent:(NSString *)component;
+ (instancetype)nodeWithComponent:(NSString *)component;
- (int)numberOfChildrenStartingWithString:(NSString *)prefix;
- (void)removePathWithParts:(NSArray *)parts;

@end
