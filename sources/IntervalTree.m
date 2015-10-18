#import "IntervalTree.h"

static const long long kMinLocation = LLONG_MIN / 2;
static const long long kMaxLimit = kMinLocation + LLONG_MAX;

static NSString *const kIntervalTreeEntriesKey = @"Entries";
static NSString *const kIntervalTreeIntervalKey = @"Interval";
static NSString *const kIntervalTreeObjectKey = @"Object";
static NSString *const kIntervalTreeClassNameKey = @"Class";

static NSString *const kIntervalLocationKey = @"Location";
static NSString *const kIntervalLengthKey = @"Length";

@interface IntervalTreeForwardLimitEnumerator : NSEnumerator {
    long long previousLimit_;
    IntervalTree *tree_;
}
@property(nonatomic, assign) long long previousLimit;
@end

@implementation IntervalTreeForwardLimitEnumerator
@synthesize previousLimit = previousLimit_;

- (instancetype)initWithTree:(IntervalTree *)tree {
    self = [super init];
    if (self) {
        tree_ = [tree retain];
        previousLimit_ = -2;
    }
    return self;
}

- (void)dealloc {
    [tree_ release];
    [super dealloc];
}

- (NSArray *)allObjects {
    NSMutableArray *result = [NSMutableArray array];
    NSObject *o = [self nextObject];
    while (o) {
        [result addObject:o];
    }
    return result;
}

- (id)nextObject {
    NSArray *objects;
    if (previousLimit_ == -2) {
        objects = [tree_ objectsWithSmallestLimit];
    } else if (previousLimit_ == -1) {
        return nil;
    } else {
        objects = [tree_ objectsWithSmallestLimitAfter:previousLimit_];
    }
    if (!objects.count) {
        previousLimit_ = -1;
    } else {
        id<IntervalTreeObject> obj = objects[0];
        previousLimit_ = [obj.entry.interval limit];
    }
    return objects;
}

@end

@interface IntervalTreeReverseLimitEnumerator : NSEnumerator {
    long long previousLimit_;
    IntervalTree *tree_;
}
@property(nonatomic, assign) long long previousLimit;
@end

@implementation IntervalTreeReverseLimitEnumerator

@synthesize previousLimit = previousLimit_;

- (instancetype)initWithTree:(IntervalTree *)tree {
    self = [super init];
    if (self) {
        tree_ = [tree retain];
        previousLimit_ = -2;
    }
    return self;
}

- (void)dealloc {
    [tree_ release];
    [super dealloc];
}

- (NSArray *)allObjects {
    NSMutableArray *result = [NSMutableArray array];
    NSObject *o = [self nextObject];
    while (o) {
        [result addObject:o];
    }
    return result;
}

- (id)nextObject {
    NSArray *objects;
    if (previousLimit_ == -2) {
        objects = [tree_ objectsWithLargestLimit];
    } else if (previousLimit_ == -1) {
        return nil;
    } else {
        objects = [tree_ objectsWithLargestLimitBefore:previousLimit_];
    }
    if (!objects.count) {
        previousLimit_ = -1;
        return nil;
    } else {
        id<IntervalTreeObject> obj = objects[0];
        previousLimit_ = [obj.entry.interval limit];
        return objects;
    }
}

@end

@interface IntervalTreeReverseEnumerator : NSEnumerator {
    long long previousLocation_;
    IntervalTree *tree_;
}
@property(nonatomic, assign) long long previousLocation;
@end

@implementation IntervalTreeReverseEnumerator

@synthesize previousLocation = previousLocation_;

- (instancetype)initWithTree:(IntervalTree *)tree {
    self = [super init];
    if (self) {
        tree_ = [tree retain];
        previousLocation_ = -2;
    }
    return self;
}

- (void)dealloc {
    [tree_ release];
    [super dealloc];
}

- (NSArray *)allObjects {
    NSMutableArray *result = [NSMutableArray array];
    NSObject *o = [self nextObject];
    while (o) {
        [result addObject:o];
    }
    return result;
}

- (id)nextObject {
    NSArray *objects;
    if (previousLocation_ == -2) {
        objects = [tree_ objectsWithLargestLocation];
    } else if (previousLocation_ == -1) {
        return nil;
    } else {
        objects = [tree_ objectsWithLargestLocationBefore:previousLocation_];
    }
    if (!objects.count) {
        previousLocation_ = -1;
        return nil;
    } else {
        id<IntervalTreeObject> obj = objects[0];
        previousLocation_ = [obj.entry.interval location];
        return objects;
    }
}

@end

@implementation Interval

+ (Interval *)intervalWithDictionary:(NSDictionary *)dict {
    if (!dict[kIntervalLocationKey] || !dict[kIntervalLengthKey]) {
        return nil;
    }
    return [self intervalWithLocation:[dict[kIntervalLocationKey] longLongValue]
                               length:[dict[kIntervalLengthKey] longLongValue]];
}

+ (Interval *)intervalWithLocation:(long long)location length:(long long)length {
    Interval *interval = [[[Interval alloc] init] autorelease];
    interval.location = location;
    interval.length = length;
    [interval boundsCheck];
    return interval;
}

+ (Interval *)maxInterval {
    Interval *interval = [[[Interval alloc] init] autorelease];
    interval.location = kMinLocation;
    interval.length = kMaxLimit - kMinLocation ;
    return interval;
}

- (long long)limit {
    return _location + _length;
}

- (BOOL)intersects:(Interval *)other {
    return MAX(self.location, other.location) < MIN(self.limit, other.limit);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p [%lld, %lld)>",
            self.class, self, self.location, self.limit];
}

- (void)boundsCheck {
    assert(_location >= kMinLocation);
    assert(_length >= 0);
    if (_location > 0) {
        assert(_location < kMaxLimit - _length);
    } else {
        assert(_location + _length < kMaxLimit);
    }
}

- (BOOL)isEqualToInterval:(Interval *)interval {
    return self.location == interval.location && self.length == interval.length;
}

- (NSDictionary *)dictionaryValue {
    return @{ kIntervalLocationKey: @(_location),
              kIntervalLengthKey: @(_length) };
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone {
    return [[Interval intervalWithLocation:_location length:_length] retain];
}

@end

@implementation IntervalTreeEntry

+ (IntervalTreeEntry *)entryWithInterval:(Interval *)interval
                                  object:(id<IntervalTreeObject>)object {
    IntervalTreeEntry *entry = [[[IntervalTreeEntry alloc] init] autorelease];
    entry.interval = interval;
    entry.object = object;
    return entry;
}

- (void)dealloc {
    [_interval release];
    [_object release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p interval=%@ object=%@>",
            self.class, self, self.interval, self.object];
}
@end

@implementation IntervalTreeValue

- (NSString *)description {
    NSMutableString *entriesString = [NSMutableString string];
    for (IntervalTreeEntry *entry in _entries) {
        [entriesString appendFormat:@"%@, ", entry];
    }
    return [NSString stringWithFormat:@"<%@: %p maxLimitAtSubtree=%lld entries=[%@]>",
            self.class,
            self,
            self.maxLimitAtSubtree,
            entriesString];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _entries = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_entries release];
    [super dealloc];
}

- (long long)maxLimit {
    long long max = -1;
    for (IntervalTreeEntry *entry in _entries) {
        max = MAX(max, [entry.interval limit]);
    }
    return max;
}

- (long long)location {
    long long location = ((IntervalTreeEntry *)_entries[0]).interval.location;
    return location;
}

- (Interval *)spanningInterval {
    return [Interval intervalWithLocation:self.location length:[self maxLimit] - self.location];
}

@end

@implementation IntervalTree {
    AATree *_tree;
    int _count;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [self init];
    if (self) {
        for (NSDictionary *entry in dict[kIntervalTreeEntriesKey]) {
            NSDictionary *intervalDict = entry[kIntervalTreeIntervalKey];
            NSDictionary *objectDict = entry[kIntervalTreeObjectKey];
            NSString *className = entry[kIntervalTreeClassNameKey];
            if (intervalDict && objectDict && className) {
                Class theClass = NSClassFromString(className);
                if ([theClass instancesRespondToSelector:@selector(initWithDictionary:)]) {
                    id<IntervalTreeObject> object = [[[theClass alloc] initWithDictionary:objectDict] autorelease];
                    Interval *interval = [Interval intervalWithDictionary:intervalDict];
                    [self addObject:object withInterval:interval];
                }
            }
        }
    }
    return self;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _tree = [[AATree alloc] initWithKeyComparator:^(NSNumber *key1, NSNumber *key2) {
            return [key1 compare:key2];
        }];
        assert(_tree);
        _tree.delegate = self;
    }
    return self;
}

- (void)dealloc {
    for (id<IntervalTreeObject> obj in [self objectsInInterval:[Interval maxInterval]]) {
        obj.entry = nil;
    }
    _tree.delegate = nil;
    [_tree release];
    [super dealloc];
}

- (void)addObject:(id<IntervalTreeObject>)object withInterval:(Interval *)interval {
    [interval boundsCheck];
    assert(object.entry == nil);  // Object must not belong to another tree
    IntervalTreeEntry *entry = [IntervalTreeEntry entryWithInterval:interval
                                                             object:object];
    IntervalTreeValue *value = [_tree objectForKey:@(interval.location)];
    if (!value) {
        IntervalTreeValue *newValue = [[[IntervalTreeValue alloc] init] autorelease];
        [newValue.entries addObject:entry];
        [_tree setObject:newValue forKey:@(interval.location)];
    } else {
        [value.entries addObject:entry];
        [_tree notifyValueChangedForKey:@(interval.location)];
    }
    object.entry = entry;
    ++_count;
}

- (void)removeObject:(id<IntervalTreeObject>)object {
    Interval *interval = object.entry.interval;
    long long theLocation = interval.location;
    IntervalTreeValue *value = [_tree objectForKey:@(interval.location)];
    NSMutableArray *entries = value.entries;
    IntervalTreeEntry *entry = nil;
    int i;
    for (i = 0; i < entries.count; i++) {
        if ([((IntervalTreeEntry *)entries[i]).object isEqual:object]) {
            entry = entries[i];
            break;
        }
    }
    if (entry) {
        assert(object.entry == entry);  // Was object added to another tree before being removed from this one?
        object.entry = nil;
        [entries removeObjectAtIndex:i];
        if (entries.count == 0) {
            [_tree removeObjectForKey:@(theLocation)];
        } else {
            [_tree notifyValueChangedForKey:@(theLocation)];
        }
        --_count;
    }
}

#pragma mark - Private

- (void)recalculateMaxLimitInSubtreeAtNode:(AATreeNode *)node
                     removeFromToVisitList:(NSMutableSet *)toVisit {
    IntervalTreeValue *value = (IntervalTreeValue *)node.data;
    if (![toVisit containsObject:node]) {
        return;
    }
    
    [toVisit removeObject:node];
    long long max = [value maxLimit];
    if (node.left) {
        if ([toVisit containsObject:node.left]) {
            [self recalculateMaxLimitInSubtreeAtNode:node.left
                               removeFromToVisitList:toVisit];
        }
        IntervalTreeValue *leftValue = (IntervalTreeValue *)node.left.data;
        max = MAX(max, leftValue.maxLimitAtSubtree);
    }
    if (node.right) {
        if ([toVisit containsObject:node.right]) {
            [self recalculateMaxLimitInSubtreeAtNode:node.right
                               removeFromToVisitList:toVisit];
        }
        IntervalTreeValue *rightValue = (IntervalTreeValue *)node.right.data;
        max = MAX(max, rightValue.maxLimitAtSubtree);
    }
    value.maxLimitAtSubtree = max;
}

#pragma mark - AATreeDelegate

- (void)aaTree:(AATree *)tree didChangeSubtreesAtNodes:(NSSet *)changedNodes {
    NSMutableSet *toVisit = [[changedNodes mutableCopy] autorelease];
    for (AATreeNode *node in changedNodes) {
        if ([toVisit containsObject:node]) {
            [self recalculateMaxLimitInSubtreeAtNode:node
                               removeFromToVisitList:toVisit];
        }
    }
}

- (void)aaTree:(AATree *)tree didChangeValueAtNode:(AATreeNode *)node {
    NSArray *parents = [tree pathFromNode:node];
    NSMutableSet *parentSet = [NSMutableSet setWithArray:parents];
    for (AATreeNode *theNode in parents) {
        [self recalculateMaxLimitInSubtreeAtNode:theNode
                           removeFromToVisitList:parentSet];
    }
}

- (void)addObjectsInInterval:(Interval *)interval
                     toArray:(NSMutableArray *)result
                    fromNode:(AATreeNode *)node {
    IntervalTreeValue *nodeValue = (IntervalTreeValue *)node.data;
    if (nodeValue.maxLimitAtSubtree <= interval.location) {
        // The whole subtree has intervals that end before the requested |interval|.
        return;
    }
    
    Interval *nodeInterval = [nodeValue spanningInterval];
    if ([nodeInterval intersects:interval]) {
        // An entry at this node could possibly intersect the desired interval.
        for (IntervalTreeEntry *entry in nodeValue.entries) {
            if ([entry.interval intersects:interval]) {
                [result addObject:entry.object];
            }
        }
    }
    if (node.left) {
        // The requested interval includes points before this node's interval so we must search
        // intervals that start before this node.
        [self addObjectsInInterval:interval
                           toArray:result
                          fromNode:node.left];
    }
    if (interval.limit > nodeInterval.location && node.right) {
        [self addObjectsInInterval:interval
                           toArray:result
                          fromNode:node.right];
    }
}

- (NSArray *)objectsInInterval:(Interval *)interval {
    NSMutableArray *array = [NSMutableArray array];
    [self addObjectsInInterval:interval toArray:array fromNode:_tree.root];
    return array;
}

- (NSArray *)allObjects {
    return [self objectsInInterval:[Interval maxInterval]];
}

- (NSInteger)count {
    return _count;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p tree=%@>", self.class, self, _tree];
}

- (BOOL)containsObject:(id<IntervalTreeObject>)object {
    IntervalTreeValue *value = [_tree objectForKey:@(object.entry.interval.location)];
    for (IntervalTreeEntry *entry in value.entries) {
        if (entry.object == object) {
            return YES;
        }
    }
    return NO;
}

- (NSArray *)objectsWithLargestLimitFromNode:(AATreeNode *)node {
    if (!node) {
        return nil;
    }
    long long myMaxLimit = ((IntervalTreeValue *)node.data).maxLimit;
    long long leftMaxLimit = ((IntervalTreeValue *)node.left.data).maxLimitAtSubtree;
    long long rightMaxLimit = ((IntervalTreeValue *)node.right.data).maxLimitAtSubtree;
    long long bestLimit = MAX(MAX(myMaxLimit, leftMaxLimit), rightMaxLimit);

    NSMutableArray *objects = [NSMutableArray array];
    if (myMaxLimit == bestLimit) {
        IntervalTreeValue *value = node.data;
        long long maxLimit = LLONG_MIN;
        for (IntervalTreeEntry *entry in value.entries) {
            if (entry.interval.limit > maxLimit) {
                [objects removeAllObjects];
                [objects addObject:entry.object];
                maxLimit = entry.interval.limit;
            } else if (entry.interval.limit == maxLimit) {
                [objects addObject:entry.object];
            }
        }
    }
    if (leftMaxLimit == bestLimit) {
        [objects addObjectsFromArray:[self objectsWithLargestLimitFromNode:node.left]];
    }
    if (rightMaxLimit == bestLimit) {
        [objects addObjectsFromArray:[self objectsWithLargestLimitFromNode:node.right]];
    }
    return objects.count ? objects : nil;
}

- (NSArray *)objectsWithSmallestLimitFromNode:(AATreeNode *)node {
    if (!node) {
        return nil;
    }
    // Searching for the smallest limit among node, node.left subtree, and node.right subtree
    // If node's key >= node.left's first object, don't search right subtree

    NSArray *objectsFromLeft = nil;
    if (node.left) {
        objectsFromLeft = [self objectsWithSmallestLimitFromNode:node.left];
    }
    
    Interval *nodeInterval = nil;
    NSMutableArray *myObjects = [NSMutableArray array];
    // Set nodeInterval to the best interval in this node's value.
    IntervalTreeValue *nodeValue = (IntervalTreeValue *)node.data;
    for (IntervalTreeEntry *entry in nodeValue.entries) {
        if (!nodeInterval) {
            [myObjects addObject:entry.object];
            nodeInterval = entry.interval;
        } else if (entry.interval.limit < nodeInterval.limit) {
            [myObjects removeAllObjects];
            [myObjects addObject:entry.object];
            nodeInterval = entry.interval;
        } else if (nodeInterval && entry.interval.limit == nodeInterval.limit) {
            [myObjects addObject:entry.object];
        }
    }
    
    NSArray *objectsFromRight = nil;
    id<IntervalTreeObject> leftValue = objectsFromLeft[0];
    if (node.right &&
        (!objectsFromLeft.count || nodeInterval.location < leftValue.entry.interval.limit)) {
        objectsFromRight = [self objectsWithSmallestLimitFromNode:node.right];
    }
    
    id<IntervalTreeObject> rightValue = objectsFromRight[0];
    long long selfLimit = LLONG_MAX, leftLimit = LLONG_MAX, rightLimit = LLONG_MAX;
    if (nodeInterval) {
        selfLimit = nodeInterval.limit;
    }
    if (objectsFromLeft) {
        leftLimit = leftValue.entry.interval.limit;
    }
    if (objectsFromRight) {
        rightLimit = rightValue.entry.interval.limit;
    }
    long long bestLimit = MIN(MIN(selfLimit, leftLimit), rightLimit);
    NSMutableArray *result = [NSMutableArray array];
    if (selfLimit == bestLimit) {
        [result addObjectsFromArray:myObjects];
    }
    if (leftLimit == bestLimit) {
        [result addObjectsFromArray:objectsFromLeft];
    }
    if (rightLimit == bestLimit) {
        [result addObjectsFromArray:objectsFromRight];
    }
    return result.count ? result : nil;
}

- (NSArray *)objectsWithSmallestLimit {
    return [self objectsWithSmallestLimitFromNode:_tree.root];
}

- (NSArray *)objectsWithLargestLimit {
    return [self objectsWithLargestLimitFromNode:_tree.root];
}

- (NSArray *)objectsWithLargestLocation {
    AATreeNode *node = _tree.root;
    while (node.right) {
        node = node.right;
    }
    IntervalTreeValue *value = node.data;
    NSMutableArray *objects = [NSMutableArray array];
    for (IntervalTreeEntry *entry in value.entries) {
        [objects addObject:entry.object];
    }
    return objects;
}

- (NSArray *)objectsWithLargestLocationBefore:(long long)location {
    return [self objectsWithLargestLocationBefore:location atNode:_tree.root];
}

// Want objects with largest key < location
- (NSArray *)objectsWithLargestLocationBefore:(long long)location atNode:(AATreeNode *)node {
    if (!node) {
        return nil;
    }

    long long key = [node.key longLongValue];
    if (key >= location) {
        // If there is a left subtree, search it. If not, this will return an empty array.
        return [self objectsWithLargestLocationBefore:location atNode:node.left];
    }

    // key < location
    if (node.right) {
        // There is a larger value in the right subtree, but maybe there's nothing < location?
        NSArray *result = [self objectsWithLargestLocationBefore:location atNode:node.right];
        if (result) {
            return result;
        }
    }

    // If you get here then the there was no right subtree or the whole right subtrees had keys > location.
    // Return the objects in this node.
    IntervalTreeValue *value = node.data;
    NSMutableArray *objects = [NSMutableArray array];
    for (IntervalTreeEntry *entry in value.entries) {
        [objects addObject:entry.object];
    }
    return objects;
}

- (NSArray *)objectsWithSmallestLimitAfter:(long long)bound fromNode:(AATreeNode *)node {
    if (!node) {
        return nil;
    }
    // we can ignore all subtrees whose maxLimitAtSubtree is <= bound
    Interval *nodeInterval = nil;
    // Set nodeInterval to the best interval in this node's value.
    IntervalTreeValue *nodeValue = (IntervalTreeValue *)node.data;
    NSMutableArray *myObjects = nil;
    for (IntervalTreeEntry *entry in nodeValue.entries) {
        if (entry.interval.limit > bound && (!nodeInterval ||
                                             entry.interval.limit < nodeInterval.limit)) {
            if (myObjects) {
                [myObjects removeAllObjects];
            } else {
                myObjects = [NSMutableArray array];
            }
            nodeInterval = entry.interval;
            [myObjects addObject:entry.object];
        } else if (nodeInterval && entry.interval.limit == nodeInterval.limit) {
            [myObjects addObject:entry.object];
        }
    }
    
    
    NSArray *leftObjects = nil;
    NSArray *rightObjects = nil;
    
    IntervalTreeValue *leftValue = (IntervalTreeValue *)node.left.data;
    IntervalTreeValue *rightValue = (IntervalTreeValue *)node.right.data;
    
    if (node.left && leftValue.maxLimitAtSubtree > bound) {
        leftObjects = [self objectsWithSmallestLimitAfter:bound fromNode:node.left];
    }
    
    long long thisLocation = [node.key longLongValue];
    
    // ignore right subtree if node's location > left subtree's smallest limit and left subtree's
    // smallest limit < bound (because every interval in the right subtree will have a limit larger
    // than this node's location, and the left subtree has an interval that ends before that
    // location).
    id<IntervalTreeObject> bestLeft = leftObjects[0];
    const BOOL thisNodesLocationIsAfterLeftSubtreesSmallestLimitAfterBound =
        (bestLeft &&
         thisLocation > bestLeft.entry.interval.limit &&
         bestLeft.entry.interval.limit > bound);
    if (node.right &&
        rightValue.maxLimitAtSubtree > bound &&
        !thisNodesLocationIsAfterLeftSubtreesSmallestLimitAfterBound) {
        rightObjects = [self objectsWithSmallestLimitAfter:bound fromNode:node.right];
    }
    
    id<IntervalTreeObject> bestRight = rightObjects[0];
    long long selfLimit = LLONG_MAX, leftLimit = LLONG_MAX, rightLimit = LLONG_MAX;
    if (nodeInterval) {
        selfLimit = nodeInterval.limit;
    }
    if (bestLeft) {
        leftLimit = bestLeft.entry.interval.limit;
    }
    if (bestRight) {
        rightLimit = bestRight.entry.interval.limit;
    }
    long long bestLimit = MIN(MIN(selfLimit, leftLimit), rightLimit);
    NSMutableArray *result = [NSMutableArray array];
    if (selfLimit == bestLimit) {
        [result addObjectsFromArray:myObjects];
    }
    if (leftLimit == bestLimit) {
        [result addObjectsFromArray:leftObjects];
    }
    if (rightLimit == bestLimit) {
        [result addObjectsFromArray:rightObjects];
    }

    return result.count ? result : nil;
}

- (NSArray *)objectsWithLargestLimitBelow:(long long)bound fromNode:(AATreeNode *)node {
    if (!node) {
        return nil;
    }
    Interval *nodeInterval = nil;
    long long thisLocation = [node.key longLongValue];
    
    // Set nodeInterval to the best interval in this node's value.
    IntervalTreeValue *nodeValue = (IntervalTreeValue *)node.data;
    NSMutableArray *myObjects = nil;
    for (IntervalTreeEntry *entry in nodeValue.entries) {
        if (entry.interval.limit < bound && (!nodeInterval ||
                                             entry.interval.limit > nodeInterval.limit)) {
            if (myObjects) {
                [myObjects removeAllObjects];
            } else {
                myObjects = [NSMutableArray array];
            }
            nodeInterval = entry.interval;
            [myObjects addObject:entry.object];
        } else if (nodeInterval &&
                   entry.interval.limit == nodeInterval.limit) {
            [myObjects addObject:entry.object];
        }
    }
    
    NSArray *leftObjects = nil;
    NSArray *rightObjects = nil;
    IntervalTreeValue *leftValue = (IntervalTreeValue *)node.left.data;
    IntervalTreeValue *rightValue = (IntervalTreeValue *)node.right.data;

    if (node.left) {
        // Try to eliminate the left subtree from consideration if this node or the right subtree
        // is superior to it.
        const BOOL thisNodeBeatsWholeLeftSubtree = (nodeInterval &&
                                                    nodeInterval.limit < bound &&
                                                    nodeInterval.limit > leftValue.maxLimitAtSubtree);
        const BOOL rightSubtreeBeatsWholeLeftSubtree = (rightValue.maxLimitAtSubtree < bound &&
                                                        rightValue.maxLimitAtSubtree > leftValue.maxLimitAtSubtree);
        if (!thisNodeBeatsWholeLeftSubtree && !rightSubtreeBeatsWholeLeftSubtree) {
            leftObjects = [self objectsWithLargestLimitBelow:bound fromNode:node.left];
        }
    }
    id<IntervalTreeObject> bestLeft = leftObjects[0];
    if (thisLocation < bound && node.right) {
        // Try to eliminate the right subtree from consideration if this node or the left subtree
        // is superior to it.
        const BOOL thisNodeBeatsWholeRightSubtree = (nodeInterval &&
                                                     nodeInterval.limit < bound &&
                                                     nodeInterval.limit > rightValue.maxLimitAtSubtree);
        const BOOL leftSubtreeBeatsWholeRightSubtree = (leftValue &&
                                                        leftValue.maxLimitAtSubtree < bound &&
                                                        leftValue.maxLimitAtSubtree > rightValue.maxLimitAtSubtree);
        if (!thisNodeBeatsWholeRightSubtree && !leftSubtreeBeatsWholeRightSubtree) {
            rightObjects = [self objectsWithLargestLimitBelow:bound fromNode:node.right];
        }
    }
    id<IntervalTreeObject> bestRight = rightObjects[0];

    long long myLimit = LLONG_MIN;
    long long leftLimit = LLONG_MIN;
    long long rightLimit = LLONG_MIN;
    if (bestLeft) {
        leftLimit = bestLeft.entry.interval.limit;
    }
    if (bestRight) {
        rightLimit = bestRight.entry.interval.limit;
    }
    if (nodeInterval && bound > nodeInterval.limit) {
        myLimit = nodeInterval.limit;
    }
    long long bestLimit = MAX(MAX(leftLimit, rightLimit), myLimit);
    
    NSMutableArray *result = [NSMutableArray array];
    if (myLimit == bestLimit) {
        [result addObjectsFromArray:myObjects];
    }
    if (leftLimit == bestLimit) {
        [result addObjectsFromArray:leftObjects];
    }
    if (rightLimit == bestLimit) {
        [result addObjectsFromArray:rightObjects];
    }
    return result.count ? result : nil;
}

- (NSArray *)objectsWithLargestLimitBefore:(long long)limit {
    return [self objectsWithLargestLimitBelow:limit fromNode:_tree.root];
}

- (NSArray *)objectsWithSmallestLimitAfter:(long long)limit {
    return [self objectsWithSmallestLimitAfter:limit fromNode:_tree.root];
}

- (NSEnumerator *)reverseEnumeratorAt:(long long)start {
    assert(start >= 0);
    IntervalTreeReverseEnumerator *enumerator =
        [[[IntervalTreeReverseEnumerator alloc] initWithTree:self] autorelease];
    enumerator.previousLocation = start + 1;
    return enumerator;
}

- (NSEnumerator *)reverseLimitEnumeratorAt:(long long)start {
    assert(start >= 0);
    IntervalTreeReverseLimitEnumerator *enumerator =
        [[[IntervalTreeReverseLimitEnumerator alloc] initWithTree:self] autorelease];
    enumerator.previousLimit = start;
    return enumerator;
}

- (NSEnumerator *)forwardLimitEnumeratorAt:(long long)start {
    assert(start >= 0);
    IntervalTreeForwardLimitEnumerator *enumerator =
        [[[IntervalTreeForwardLimitEnumerator alloc] initWithTree:self] autorelease];
    enumerator.previousLimit = start;
    return enumerator;
}

- (NSEnumerator *)reverseLimitEnumerator {
    return [[[IntervalTreeReverseLimitEnumerator alloc] initWithTree:self] autorelease];
}

- (NSEnumerator *)forwardLimitEnumerator {
    return [[[IntervalTreeForwardLimitEnumerator alloc] initWithTree:self] autorelease];
}

- (long long)bruteForceMaxLimitAtSubtree:(AATreeNode *)node {
    IntervalTreeValue *value = node.data;
    long long result = LLONG_MIN;
    for (IntervalTreeEntry *entry in value.entries) {
        result = MAX(result, entry.interval.limit);
    }
    if (node.left) {
        result = MAX([self bruteForceMaxLimitAtSubtree:node.left], result);
    }
    if (node.right) {
        result = MAX([self bruteForceMaxLimitAtSubtree:node.right], result);
    }
    return result;
}

- (void)sanityCheckAtNode:(AATreeNode *)node {
    IntervalTreeValue *value = node.data;
    long long location = [(NSNumber *)node.key longLongValue];
    assert(value.maxLimitAtSubtree = [self bruteForceMaxLimitAtSubtree:node]);
    IntervalTreeValue *leftValue = node.left.data;
    IntervalTreeValue *rightValue = node.right.data;
    if (leftValue) {
        assert([(NSNumber *)node.left.key longLongValue] < location);
    }
    if (rightValue) {
        assert([(NSNumber *)node.right.key longLongValue] > location);
    }
    for (IntervalTreeEntry *entry in value.entries) {
        assert(entry.interval.location == location);
        assert(entry.interval.limit <= value.maxLimitAtSubtree);
    }
    
    if (node.left) {
        [self sanityCheckAtNode:node.left];
    }
    if (node.right) {
        [self sanityCheckAtNode:node.right];
    }
}
- (void)sanityCheck {
    [self sanityCheckAtNode:_tree.root];
}

- (NSString *)debugString {
    return [_tree description];
}

- (NSDictionary *)dictionaryValueWithOffset:(long long)offset {
    NSMutableArray *objectDicts = [NSMutableArray array];
    for (id<IntervalTreeObject> object in self.allObjects) {
        Interval *interval = object.entry.interval;
        interval.location = interval.location + offset;
        [objectDicts addObject:@{ kIntervalTreeIntervalKey: object.entry.interval.dictionaryValue,
                                  kIntervalTreeObjectKey: object.dictionaryValue,
                                  kIntervalTreeClassNameKey: NSStringFromClass(object.class) }];
        interval.location = interval.location - offset;
    }
    return @{ kIntervalTreeEntriesKey: objectDicts };
}

@end
