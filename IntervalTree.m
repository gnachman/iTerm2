#import "IntervalTree.h"

@implementation Interval

+ (Interval *)intervalWithLocation:(long long)location length:(long long)length {
  Interval *interval = [[[Interval alloc] init] autorelease];
  interval.location = location;
  interval.length = length;
  return interval;
}

+ (Interval *)maxInterval {
  Interval *interval = [[[Interval alloc] init] autorelease];
  interval.location = -1;
  interval.length = LLONG_MAX;
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

- (id)init {
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

@implementation IntervalTree

- (id)init {
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
  assert(interval.location >= 0);
  assert(interval.location < LLONG_MAX - 1 - interval.length);  // Only maxInterval can go up to LLONG_MAX.
  IntervalTreeEntry *entry = [IntervalTreeEntry entryWithInterval:interval
                                                           object:object];
  IntervalTreeValue *value = [_tree objectForKey:@(interval.location)];
  if (!value) {
    IntervalTreeValue *value = [[[IntervalTreeValue alloc] init] autorelease];
    [value.entries addObject:entry];
    [_tree setObject:value forKey:@(interval.location)];
  } else {
    [value.entries addObject:entry];
    [_tree notifyValueChangedForKey:@(interval.location)];
  }
  object.entry = entry;
}

- (void)removeObject:(id<IntervalTreeObject>)object {
  Interval *interval = object.entry.interval;
  IntervalTreeValue *value = [_tree objectForKey:interval];
  NSMutableArray *entries = value.entries;
  int i;
  for (i = 0; i < entries.count; i++) {
    if ([((IntervalTreeEntry *)entries[i]).object isEqual:object]) {
      break;
    }
  }
  if (i < entries.count) {
    [entries removeObjectAtIndex:i];
  }
  if (entries.count == 0) {
    [_tree removeObjectForKey:@(interval.location)];
  } else {
    [_tree notifyValueChangedForKey:@(interval.location)];
  }
  object.entry = nil;
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
  NSMutableSet *toVisit = [changedNodes mutableCopy];
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
  for (AATreeNode *node in parents) {
    [self recalculateMaxLimitInSubtreeAtNode:node
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

@end
