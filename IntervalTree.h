#import <Foundation/Foundation.h>

@interface IntervalTreeEntry : NSObject
@property(nonatomic, assign) NSRange interval;
@property(nonatomic, retain) id object;
@end

// Contains links to nodes. Leaf nodes contain a list of IntervalTreeEntry entries.
@interface IntervalTreeNode : NSObject
@property(nonatomic, assign) NSRange interval;

// This is the designated initializer.
- (id)initWithInterval:(NSRange)interval;
- (NSArray *)entriesInInterval:(NSRange)interval;
- (void)addEntry:(IntervalTreeEntry *)entry;
- (BOOL)shouldSplitOnInterval:(NSRange)interval;
- (NSString *)debugStringWithPrefix:(NSString *)prefix;
@end

// Intermediate node in an Interval Tree. Its interval must be at least 2 large.
@interface IntervalTreeIntermediateNode : IntervalTreeNode
@property(nonatomic, retain) IntervalTreeNode *left;
@property(nonatomic, retain) IntervalTreeNode *right;

@end

// Leaf node in an interval tree.
@interface IntervalTreeLeafNode : IntervalTreeNode
@property(nonatomic, readonly) NSMutableArray *entries;

- (IntervalTreeIntermediateNode *)subtreeAfterSplittingOnInterval:(NSRange)interval;

@end

@interface IntervalTree : NSObject {
  IntervalTreeNode *_root;
  NSRange _interval;
}

+ (id)intervalTreeWithInterval:(NSRange)interval;
- (void)addEntryWithInterval:(NSRange)interval object:(NSObject *)object;
- (void)addEntry:(IntervalTreeEntry *)entry;
- (NSArray *)objectsInInterval:(NSRange)interval;
- (NSArray *)entriesInInterval:(NSRange)interval;

@end
