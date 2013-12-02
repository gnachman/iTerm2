#import "iTermTests.h"
#import "IntervalTreeTest.h"
#import "IntervalTree.h"

@interface ITObject : NSObject <IntervalTreeObject>
@end

@implementation ITObject
@synthesize entry;
@end

static Interval *MakeInterval(long long location, long long length) {
  Interval *interval = [[[Interval alloc] init] autorelease];
  interval.location = location;
  interval.length = length;
  return interval;
}

@implementation IntervalTreeTest {
  ITObject *obj1_;
  ITObject *obj2_;
  ITObject *obj3_;
  IntervalTree *tree_;
}

- (void)setup {
  obj1_ = [[[ITObject alloc] init] autorelease];
  obj2_ = [[[ITObject alloc] init] autorelease];
  obj3_ = [[[ITObject alloc] init] autorelease];
}

- (void)testEmptyTree {
  tree_ = [[[IntervalTree alloc] init] autorelease];
  NSArray *entries = [tree_ objectsInInterval:MakeInterval(0, 256)];
  assert(entries.count == 0);
}

- (void)assertEntriesInInterval:(Interval *)interval equal:(NSArray *)expectedObjects {
  NSArray *foundObjects = [tree_ objectsInInterval:interval];
  assert(foundObjects.count == expectedObjects.count);
  for (ITObject *object in foundObjects) {
    BOOL ok = NO;
    for (NSObject *obj in expectedObjects) {
      if (object == obj) {
        ok = YES;
        break;
      }
    }
    assert(ok);
  }
}

- (void)testOneEntry {
  tree_ = [[[IntervalTree alloc] init] autorelease];
  [tree_ addObject:obj1_ withInterval:MakeInterval(100, 50)];

  [self assertEntriesInInterval:MakeInterval(0, 100)
                          equal:@[]];
  [self assertEntriesInInterval:MakeInterval(150, 1000)
                          equal:@[]];
  [self assertEntriesInInterval:MakeInterval(100, 1)
                          equal:@[obj1_]];
  [self assertEntriesInInterval:MakeInterval(125, 1)
                          equal:@[obj1_]];
  [self assertEntriesInInterval:MakeInterval(149, 1)
                          equal:@[obj1_]];
}

- (void)testDisjointEntries {
  tree_ = [[[IntervalTree alloc] init] autorelease];
  [tree_ addObject:obj1_ withInterval:MakeInterval(10, 2)];
  [tree_ addObject:obj2_ withInterval:MakeInterval(20, 2)];
  [self assertEntriesInInterval:MakeInterval(0, 10) equal:@[]];
  [self assertEntriesInInterval:MakeInterval(10, 1) equal:@[obj1_]];
  [self assertEntriesInInterval:MakeInterval(10, 2) equal:@[obj1_]];
  [self assertEntriesInInterval:MakeInterval(11, 1) equal:@[obj1_]];

  [self assertEntriesInInterval:MakeInterval(20, 1) equal:@[obj2_]];
  [self assertEntriesInInterval:MakeInterval(20, 2) equal:@[obj2_]];
  [self assertEntriesInInterval:MakeInterval(21, 1) equal:@[obj2_]];

  [self assertEntriesInInterval:MakeInterval(10, 12) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(10, 11) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(10, 10) equal:@[obj1_]];
  [self assertEntriesInInterval:MakeInterval(0, 30) equal:@[obj1_, obj2_]];
}

- (void)testTwoEntriesWithSameInterval {
  tree_ = [[[IntervalTree alloc] init] autorelease];
  [tree_ addObject:obj1_ withInterval:MakeInterval(10, 2)];
  [tree_ addObject:obj2_ withInterval:MakeInterval(10, 2)];
  [self assertEntriesInInterval:MakeInterval(0, 10) equal:@[]];
  [self assertEntriesInInterval:MakeInterval(12, 10) equal:@[]];
  [self assertEntriesInInterval:MakeInterval(10, 1) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(10, 2) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(11, 1) equal:@[obj1_, obj2_]];
}

//  11111
// 2222
- (void)testAddOverlap1 {
  tree_ = [[[IntervalTree alloc] init] autorelease];
  [tree_ addObject:obj1_ withInterval:MakeInterval(10, 10)];
  [tree_ addObject:obj2_ withInterval:MakeInterval(5, 10)];

  [self assertEntriesInInterval:MakeInterval(0, 5) equal:@[]];
  [self assertEntriesInInterval:MakeInterval(0, 30) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(0, 10) equal:@[obj2_]];
  [self assertEntriesInInterval:MakeInterval(10, 5) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(15, 5) equal:@[obj1_]];
  [self assertEntriesInInterval:MakeInterval(20, 5) equal:@[]];
}

//  11111
//  222
- (void)testAddOverlap2 {
  tree_ = [[[IntervalTree alloc] init] autorelease];
  [tree_ addObject:obj1_ withInterval:MakeInterval(10, 10)];
  [tree_ addObject:obj2_ withInterval:MakeInterval(10, 5)];

  [self assertEntriesInInterval:MakeInterval(0, 10) equal:@[]];
  [self assertEntriesInInterval:MakeInterval(10, 1) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(10, 10) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(15, 10) equal:@[obj1_]];
  [self assertEntriesInInterval:MakeInterval(20, 10) equal:@[]];
}

//  11111
//   222
- (void)testAddOverlap3 {
  tree_ = [[[IntervalTree alloc] init] autorelease];
  [tree_ addObject:obj1_ withInterval:MakeInterval(10, 10)];
  [tree_ addObject:obj2_ withInterval:MakeInterval(12, 5)];

  [self assertEntriesInInterval:MakeInterval(0, 10) equal:@[]];
  [self assertEntriesInInterval:MakeInterval(0, 100) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(0, 12) equal:@[obj1_]];
  [self assertEntriesInInterval:MakeInterval(0, 13) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(12, 1) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(12, 10) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(17, 10) equal:@[obj1_]];
  [self assertEntriesInInterval:MakeInterval(20, 10) equal:@[]];
}

//  11111
//    222
- (void)testAddOverlap4 {
  tree_ = [[[IntervalTree alloc] init] autorelease];
  [tree_ addObject:obj1_ withInterval:MakeInterval(10, 10)];
  [tree_ addObject:obj2_ withInterval:MakeInterval(15, 5)];

  [self assertEntriesInInterval:MakeInterval(0, 10) equal:@[]];
  [self assertEntriesInInterval:MakeInterval(0, 11) equal:@[obj1_]];
  [self assertEntriesInInterval:MakeInterval(0, 16) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(15, 10) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(0, 100) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(20, 100) equal:@[]];
}

//  11111
//     222
- (void)testAddOverlap5 {
  tree_ = [[[IntervalTree alloc] init] autorelease];
  [tree_ addObject:obj1_ withInterval:MakeInterval(10, 10)];
  [tree_ addObject:obj2_ withInterval:MakeInterval(15, 10)];

  [self assertEntriesInInterval:MakeInterval(0, 10) equal:@[]];
  [self assertEntriesInInterval:MakeInterval(0, 11) equal:@[obj1_]];
  [self assertEntriesInInterval:MakeInterval(0, 20) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(0, 30) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(15, 30) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(20, 30) equal:@[obj2_]];
  [self assertEntriesInInterval:MakeInterval(30, 30) equal:@[]];
}

//  11111
// 2222222
- (void)testAddOverlap6 {
  tree_ = [[[IntervalTree alloc] init] autorelease];
  [tree_ addObject:obj1_ withInterval:MakeInterval(10, 10)];  // [10, 20)
  [tree_ addObject:obj2_ withInterval:MakeInterval(5, 20)];   // [5, 25)

  [self assertEntriesInInterval:MakeInterval(0, 5) equal:@[]];
  [self assertEntriesInInterval:MakeInterval(0, 10) equal:@[obj2_]];
  [self assertEntriesInInterval:MakeInterval(0, 15) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(0, 20) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(0, 25) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(0, 30) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(5, 5) equal:@[obj2_]];
  [self assertEntriesInInterval:MakeInterval(5, 10) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(0, 100) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:MakeInterval(25, 100) equal:@[]];
}

- (void)testWithSplit {
  tree_ = [[[IntervalTree alloc] init] autorelease];
  [tree_ addObject:obj1_ withInterval:MakeInterval(10, 10)];
  [tree_ addObject:obj2_ withInterval:MakeInterval(8, 10)];
  [tree_ addObject:obj3_ withInterval:MakeInterval(9, 10)];

}

- (void)testWithSkew {
  tree_ = [[[IntervalTree alloc] init] autorelease];
  [tree_ addObject:obj1_ withInterval:MakeInterval(10, 10)];
  [tree_ addObject:obj2_ withInterval:MakeInterval(12, 10)];
  [tree_ addObject:obj3_ withInterval:MakeInterval(11, 10)];
  
}

- (Interval *)randomInterval {
  NSRange range;
  range.location = rand() % 255;
  do {
    range.length = rand() % (256 - range.location);
  } while (range.length == 0);
  return MakeInterval(range.location, range.length);
}

#if 0
// Commented out because this is very slow.
- (void)testRandomTree {
  const int ITERATIONS = 1000;
  srand(0);
  for (int j = 0; j < ITERATIONS; j++) {
    const int N = 1 + j / 20;  // Number of entries
    NSMutableArray *entries = [NSMutableArray array];
    tree_ = [[[IntervalTree alloc] init] autorelease];
    for (int i = 0; i < N; i++) {
      IntervalTreeEntry *entry = [[[IntervalTreeEntry alloc] init] autorelease];
      entry.interval = [self randomInterval];
      entry.object = [[[ITObject alloc] init] autorelease];
      [tree_ addObject:entry.object withInterval:entry.interval];
      [entries addObject:entry];
    }

    const int TESTS = 100;
    for (int i = 0; i < TESTS; i++) {
      Interval *interval = [self randomInterval];
      NSArray *actualObjects = [tree_ objectsInInterval:interval];
      NSMutableArray *expectedObjects = [NSMutableArray array];
      for (int k = 0; k < N; k++) {
        IntervalTreeEntry *entry = entries[k];
        if ([interval intersects:entry.interval]) {
          [expectedObjects addObject:entry.object];
        }
      }
      assert(actualObjects.count == expectedObjects.count);
      for (IntervalTreeEntry *expected in expectedObjects) {
        assert([actualObjects containsObject:expected]);
      }
    }
  }
}
#endif

@end
