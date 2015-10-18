#import "CPKKDTree.h"
#import "CPKKDTreeNode.h"

// To get debug logging, change this to:
// #define DebugLog(args...) NSLog(args)
#define DebugLog(args...)

@interface CPKKDTree ()
@property(nonatomic) CPKKDTreeNode *root;
@property(nonatomic) NSInteger dimensions;

// This is where values are stored before -build is called. Its elements are NSArray objects. Each
// array has two values; the first is the associated object, and the second is the key.
@property(nonatomic) NSMutableArray *stagedEntries;

// Valid only during a search. The current best guess.
@property(nonatomic) CPKKDTreeNode *guess;

// Valid only during a search. The current best distance from the target to |self.guess|.
@property(nonatomic) double bestDistance;
@end

@implementation CPKKDTree

- (instancetype)initWithDimensions:(NSInteger)dimensions {
    self = [super init];
    if (self) {
        self.dimensions = dimensions;
        self.stagedEntries = [[NSMutableArray alloc] init];
    }
    return self;
}

- (NSString *)debugDescription {
    return [NSString stringWithFormat:@"digraph {\n%@}\n", self.root.dot];
}

- (void)addObject:(id)object forKey:(NSArray *)key {
    NSAssert(self.stagedEntries, @"Cannot add an object after -build");
    [self.stagedEntries addObject:@[ object, key ]];
}

- (void)build {
    self.root = [self buildAtDepth:0 entries:self.stagedEntries];
    self.stagedEntries = nil;
}

- (CPKKDTreeNode *)buildAtDepth:(NSInteger)depth entries:(NSArray *)entries {
    if (!entries.count) {
        return nil;
    }

    NSInteger axis = depth % self.dimensions;
    NSInteger indexOfMedian = [self indexOfMedianEntryFromEntries:entries onAxis:axis];
    NSArray *tuple = entries[indexOfMedian];
    id object = tuple[0];
    NSArray *key = tuple[1];
    double median = [key[axis] doubleValue];

    CPKKDTreeNode *node = [[CPKKDTreeNode alloc] init];
    node.key = key;
    node.object = object;
    node.leftChild = [self buildAtDepth:depth + 1
                                entries:[self entriesBefore:median
                                                     onAxis:axis
                                                  fromArray:entries]];
    node.rightChild = [self buildAtDepth:depth + 1
                                 entries:[self entriesOnOrAfter:median
                                                         onAxis:axis
                                                      fromArray:entries
                                                         except:indexOfMedian]];
    return node;
}

- (NSInteger)indexOfMedianEntryFromEntries:(NSArray *)entries onAxis:(NSInteger)axis {
    // Sort entries by the |axis|th value in key.
    NSArray *sortedEntries =
        [entries sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            return [obj1[1][axis] compare:obj2[1][axis]];
        }];

    NSArray *medianKey = [sortedEntries[sortedEntries.count / 2] objectAtIndex:1];

    // Find the index of the tuple that has the median key
    for (NSInteger index = 0; index < entries.count; index++) {
        if ([entries[index][1] isEqualToArray:medianKey]) {
            return index;
        }
    }
    NSAssert(NO, @"Failed to find key");
    return 0;
}

- (NSArray *)entriesBefore:(double)pivot onAxis:(NSInteger)axis fromArray:(NSArray *)entries {
    NSMutableArray *result = [NSMutableArray array];
    for (NSArray *tuple in entries) {
        NSArray *key = tuple[1];
        if ([key[axis] doubleValue] < pivot) {
            [result addObject:tuple];
        }
    }
    return result;
}

- (NSArray *)entriesOnOrAfter:(double)pivot
                       onAxis:(NSInteger)axis
                    fromArray:(NSArray *)entries
                       except:(NSInteger)indexToExclude {
    NSMutableArray *result = [NSMutableArray array];
    NSInteger i = 0;
    for (NSArray *tuple in entries) {
        if (i != indexToExclude) {
            NSArray *key = tuple[1];
            if ([key[axis] doubleValue] >= pivot) {
                [result addObject:tuple];
            }
        }
        i++;
    }
    return result;
}

- (id)nearestNeighborTo:(NSArray *)key {
    NSAssert(self.stagedEntries == nil, @"You must call -build before querying the tree.");
    if (!self.root) {
        return nil;
    }

    self.guess = nil;
    self.bestDistance = DBL_MAX;
    [self findNearestNeighborTo:key depth:0 node:self.root];
    return self.guess.object;
}

// This implementation based on:
// http://web.stanford.edu/class/cs106l/handouts/assignment-3-kdtree.pdf
- (void)findNearestNeighborTo:(NSArray *)testPoint
                        depth:(NSInteger)depth
                         node:(CPKKDTreeNode *)curr {
    if (!curr) {
        return;
    }
    // If the current location is better than the best known location, update the best known
    // location. NOTE: The Stanford document uses the wrong arguments to distance.
    double distance = [curr distanceTo:testPoint];
    if (!self.guess) {
        DebugLog(@"No guess yet so pick %@ as the guess", curr);
        self.guess = curr;
        self.bestDistance = distance;
    } else {
        if (distance < self.bestDistance) {
            DebugLog(@"%@ is %f away, which is better than best distance of %f. "
                     @"Choose it as the guess",
                     curr, distance, self.bestDistance);
            self.bestDistance = distance;
            self.guess = curr;
        }
    }

    // Recursively search the half of the tree that contains the test point.
    NSInteger axis = depth % self.dimensions;
    double a_i = [testPoint[axis] doubleValue];
    double curr_i = [curr.key[axis] doubleValue];
    CPKKDTreeNode *otherChild;
    if (a_i < curr_i) {
        DebugLog(@"Check left child because test point %f is less than splitting plane %f",
                 a_i, curr_i);
        [self findNearestNeighborTo:testPoint
                              depth:depth + 1
                               node:curr.leftChild];
        otherChild = curr.rightChild;
    } else {
        DebugLog(@"Check right child because test point %f is more than splitting plane %f",
                 a_i, curr_i);
        [self findNearestNeighborTo:testPoint
                              depth:depth + 1
                               node:curr.rightChild];
        otherChild = curr.leftChild;
    }
    DebugLog(@"returned from recursion. At node %@", curr);
    
    // If the candidate hypersphere crosses this splitting plane, look on the
    // other side of the plane by examining the other subtree.
    if (fabs(curr_i - a_i) < self.bestDistance) {
        DebugLog(@"Hyperplane at %f for this node is close enough to the test point on this axis "
                 @"of %f to search since the distance between planes is %f and the best distance "
                 @"is %f",
                 curr_i, a_i, fabs(curr_i - a_i), self.bestDistance);
        [self findNearestNeighborTo:testPoint depth:depth + 1 node:otherChild];
    } else {
        DebugLog(@"Hyperplane at %f for this node is NOT close enough to the test point on this "
                 @"axis of %f to search since the distance between planes is %f and the best "
                 @"distance is %f",
                 curr_i, a_i, fabs(curr_i - a_i), self.bestDistance);
    }
}

@end
