#import "IntervalTree.h"

@implementation IntervalTreeEntry

- (void)dealloc {
  [_object release];
  [super dealloc];
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%p:%@ interval=%@ object=%@ >",
          self,
          [self class],
          [NSValue valueWithRange:_interval],
          _object];
}

@end

@implementation IntervalTreeNode

- (id)initWithInterval:(NSRange)interval {
  self = [super init];
  if (self) {
    _interval = interval;
  }
  return self;
}

- (void)dealloc {
  [super dealloc];
}

- (NSArray *)entriesInInterval:(NSRange)interval {
  // Subclass should implement this.
  assert(false);
}

- (void)addEntry:(IntervalTreeEntry *)entry {
  // Subclass should implement this.
  assert(false);
}

- (BOOL)shouldSplitOnInterval:(NSRange)interval {
    // Subclass should implement this.
    assert(false);
}

- (NSString *)debugStringWithPrefix:(NSString *)prefix {
  // Subclass should implement this
  assert(false);
}

@end

@implementation IntervalTreeIntermediateNode

- (void)dealloc {
  [_left release];
  [_right release];
  [super dealloc];
}

- (BOOL)intervalInLeftSubtree:(NSRange)interval {
  return (NSIntersectionRange(interval, _left.interval).length > 0);
}

- (BOOL)intervalInRightSubtree:(NSRange)interval {
  return (NSIntersectionRange(interval, _right.interval).length > 0);
}

- (NSArray *)entriesInInterval:(NSRange)interval {
  NSArray *leftEntries = nil;
  NSArray *rightEntries = nil;
  if ([self intervalInLeftSubtree:interval]) {
    leftEntries = [_left entriesInInterval:interval];
  }
  if ([self intervalInRightSubtree:interval]) {
    rightEntries = [_right entriesInInterval:interval];
  }
  NSMutableArray *results = [NSMutableArray array];
  if (leftEntries) {
    [results addObjectsFromArray:leftEntries];
  }
  if (rightEntries) {
    // This makes the algorithm quadratic in the worst case, but in practice it
    // won't matter because these trees tend to be sparse.
    for (IntervalTreeEntry *entry in rightEntries) {
      if (![results containsObject:entry]) {
        [results addObject:entry];
      }
    }
  }
  return results;
}

- (void)addEntry:(IntervalTreeEntry *)entry {
  if ([self intervalInLeftSubtree:entry.interval]) {
    if ([_left shouldSplitOnInterval:entry.interval]) {
      _left = [(IntervalTreeLeafNode *)_left subtreeAfterSplittingOnInterval:entry.interval];
    }
    [_left addEntry:entry];
  }
  if ([self intervalInRightSubtree:entry.interval]) {
    if ([_right shouldSplitOnInterval:entry.interval]) {
      _right = [(IntervalTreeLeafNode *)_right subtreeAfterSplittingOnInterval:entry.interval];
    }
    [_right addEntry:entry];
  }
}

- (BOOL)shouldSplitOnInterval:(NSRange)interval {
    return NO;
}

- (NSString *)debugStringWithPrefix:(NSString *)prefix {
  return [NSString stringWithFormat:
          @"<%p:%@ interval=%@\n"
           "%@left: %@\n"
           "%@right: %@>",
          self,
          [self class],
          [NSValue valueWithRange:self.interval],
          prefix,
          [_left debugStringWithPrefix:[prefix stringByAppendingString:@"  "]],
          prefix,
          [_right debugStringWithPrefix:[prefix stringByAppendingString:@"  "]]];
}

@end

@implementation IntervalTreeLeafNode

- (id)initWithInterval:(NSRange)interval {
  self = [super initWithInterval:interval];
  if (self) {
    _entries = [[NSMutableArray alloc] init];
  }
  return self;
}

- (void)dealloc {
  [_entries release];
  [super dealloc];
}

- (NSArray *)entriesInInterval:(NSRange)interval {
  return _entries;
}

- (void)addEntry:(IntervalTreeEntry *)entry {
  assert(_entries);
  [_entries addObject:entry];
}

- (NSString *)debugStringWithPrefix:(NSString *)prefix {
  return [NSString stringWithFormat:@"%@<%p:%@ interval=%@ entries=%@>",
          prefix,
          self,
          [self class],
          [NSValue valueWithRange:self.interval],
           _entries];
}

- (BOOL)shouldSplitOnInterval:(NSRange)interval {
  // Consider only the portion of |interval| that's contained in this node.
  interval = NSIntersectionRange(interval, self.interval);

  // If it's not the same, then we must split.
  return !NSEqualRanges(interval, self.interval);
}

- (IntervalTreeIntermediateNode *)subtreeSplitWithLeftInterval:(NSRange)leftInterval
                                                 rightInterval:(NSRange)rightInterval {
  IntervalTreeIntermediateNode *myReplacement =
      [[[IntervalTreeIntermediateNode alloc] initWithInterval:self.interval] autorelease];
  myReplacement.left =
      [[[IntervalTreeLeafNode alloc] initWithInterval:leftInterval] autorelease];
  myReplacement.right =
      [[[IntervalTreeLeafNode alloc] initWithInterval:rightInterval] autorelease];
  for (IntervalTreeEntry *entry in _entries) {
    [myReplacement.left addEntry:entry];
    [myReplacement.right addEntry:entry];
  }
  return myReplacement;
}

- (IntervalTreeIntermediateNode *)subtreeAfterSplittingOnInterval:(NSRange)interval {
  interval = NSIntersectionRange(interval, self.interval);
  assert(interval.length > 0);
  assert(self.interval.length > 0);
  NSUInteger myStart = self.interval.location;
  NSUInteger myEnd = NSMaxRange(self.interval);
  NSUInteger argStart = interval.location;
  NSUInteger argEnd = NSMaxRange(interval);
  assert(myStart <= argStart);
  assert(myEnd >= argEnd);

  IntervalTreeIntermediateNode *myReplacement = nil;
  if (argStart > myStart && argEnd < myEnd) {
    // mmmmmmm
    //   aaa
    // Need to split in three. Split in two, then recurse on the right subtree.
    assert(argStart >= myStart);
    assert(myEnd >= argStart);
    NSRange leftInterval = NSMakeRange(myStart, argStart - myStart);
    NSRange rightInterval = NSMakeRange(argStart, myEnd - argStart);
    myReplacement = [self subtreeSplitWithLeftInterval:leftInterval
                                         rightInterval:rightInterval];
    NSRange rightSplit = NSMakeRange(argEnd, myEnd - argEnd);
    assert([myReplacement.right isKindOfClass:[IntervalTreeLeafNode class]]);
    myReplacement.right = [(IntervalTreeLeafNode *)myReplacement.right subtreeAfterSplittingOnInterval:rightSplit];
    return myReplacement;
  } else if (argEnd < myEnd) {
    // mmmmmmm
    // aaaa
    assert(argStart == myStart);
    NSRange leftInterval = interval;
    NSRange rightInterval = NSMakeRange(argEnd, myEnd - argEnd);
    myReplacement = [self subtreeSplitWithLeftInterval:leftInterval
                                         rightInterval:rightInterval];
  } else if (argStart > myStart) {
    // mmmmmmm
    //    aaaa
    assert(argEnd == myEnd);
    NSRange leftInterval = NSMakeRange(myStart, argStart - myStart);
    NSRange rightInterval = interval;
    myReplacement = [self subtreeSplitWithLeftInterval:leftInterval
                                         rightInterval:rightInterval];
  } else {
    assert(false);  // Bogus interval to split on
  }
  return myReplacement;
}

@end

@implementation IntervalTree

- (id)initWithInterval:(NSRange)interval {
  self = [super init];
  if (self) {
    _interval = interval;
    _root = [[IntervalTreeLeafNode alloc] initWithInterval:interval];
  }
  return self;
}

- (void)dealloc {
  [_root release];
  [super dealloc];
}

+ (id)intervalTreeWithInterval:(NSRange)interval {
  return [[[self alloc] initWithInterval:interval] autorelease];
}

- (void)addEntryWithInterval:(NSRange)interval object:(NSObject *)object {
  IntervalTreeEntry *entry = [[[IntervalTreeEntry alloc] init] autorelease];
  entry.interval = interval;
  entry.object = object;
  [self addEntry:entry];
}

- (void)addEntry:(IntervalTreeEntry *)entry {
  if ([_root isKindOfClass:[IntervalTreeLeafNode class]]) {
    if ([_root shouldSplitOnInterval:entry.interval]) {
      [_root autorelease];
      _root = [(IntervalTreeLeafNode *)_root subtreeAfterSplittingOnInterval:entry.interval];
    }
  }
  [_root addEntry:entry];
}

- (NSArray *)objectsInInterval:(NSRange)interval {
  NSArray *entries = [_root entriesInInterval:interval];
  NSMutableArray *objects = [NSMutableArray array];
  for (IntervalTreeEntry *entry in entries) {
    [objects addObject:entry.object];
  }
  return objects;
}

- (NSArray *)entriesInInterval:(NSRange)interval {
  return [_root entriesInInterval:interval];
}

- (NSString *)debugString {
    return [_root debugStringWithPrefix:@""];
}

@end
