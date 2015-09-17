#import <Foundation/Foundation.h>

/**
 * A node in a CPKKDTree.
 */
@interface CPKKDTreeNode : NSObject

/** The associated object. */
@property(nonatomic) id object;

/** Array of NSNumber objects. */
@property(nonatomic) NSArray *key;
@property(nonatomic) CPKKDTreeNode *leftChild;
@property(nonatomic) CPKKDTreeNode *rightChild;

/** Euclidean distance from self.key to |key| */
- (double)distanceTo:(NSArray *)key;

/** Returns this subtree in Graphviz's "dot" langauge format. */
- (NSString *)dot;

@end
