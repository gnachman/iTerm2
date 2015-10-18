#import <Foundation/Foundation.h>

/**
 * A K-D Tree stores a collections of points in K dimensions, plus an object associated with each
 * point. It enables efficient searching for the nearest neighbor of a point in that space.
 */
@interface CPKKDTree : NSObject

/**
 * Initializes the tree with the given number of dimensions.
 *
 * @param dimensions The number of dimensions for this tree (the "K" value)
 *
 * @return An initialized object.
 */
- (instancetype)initWithDimensions:(NSInteger)dimensions;

/**
 * Adds a point and an associated object to the tree.
 *
 * @param object The associated object
 * @param key An array of NSNumber objects. Must have exactly as many elements as the tree has 
 *   dimensions.
 */
- (void)addObject:(id)object forKey:(NSArray *)key;

/**
 * Constructs the tree. No more calls to -addObject:forKey: are allowed after this.
 */
- (void)build;

/**
 * Locates the nearest neighbor to |key| by Euclidean distance. This may not be used in more than
 * one thread at a time because it stores search state in self.
 *
 * @param key An array of NSNumber objects with as many elements as the tree has dimensions.
 *
 * @return The object assoicated with the point closest to |key| by Euclidean distance.
 */
- (id)nearestNeighborTo:(NSArray *)key;

@end
