#import "iTermTests.h"
#import "IntervalTreeTest.h"
#import "IntervalTree.h"

@implementation IntervalTreeTest {
  NSObject *obj1_;
  NSObject *obj2_;
  IntervalTree *tree_;
}

- (void)setup {
  obj1_ = [[[NSObject alloc] init] autorelease];
  obj2_ = [[[NSObject alloc] init] autorelease];
}

- (void)testEmptyTree {
  tree_ = [IntervalTree intervalTreeWithInterval:NSMakeRange(0, 256)];
  NSArray *entries = [tree_ entriesInInterval:NSMakeRange(0, 256)];
  assert(entries.count == 0);
}

- (void)assertEntriesInInterval:(NSRange)interval equal:(NSArray *)objects {
  NSArray *entries = [tree_ entriesInInterval:interval];
  assert(entries.count == objects.count);
  for (IntervalTreeEntry *entry in entries) {
    BOOL ok = NO;
    for (NSObject *obj in objects) {
      if (entry.object == obj) {
        ok = YES;
        break;
      }
    }
    assert(ok);
  }
}

- (void)testOneEntry {
  tree_ = [IntervalTree intervalTreeWithInterval:NSMakeRange(0, 256)];
  [tree_ addEntryWithInterval:NSMakeRange(100, 50) object:obj1_];

  [self assertEntriesInInterval:NSMakeRange(0, 100)
                          equal:@[]];
  [self assertEntriesInInterval:NSMakeRange(150, 1000)
                          equal:@[]];
  [self assertEntriesInInterval:NSMakeRange(100, 1)
                          equal:@[obj1_]];
  [self assertEntriesInInterval:NSMakeRange(125, 1)
                          equal:@[obj1_]];
  [self assertEntriesInInterval:NSMakeRange(149, 1)
                          equal:@[obj1_]];
}

- (void)testDisjointEntries {
  tree_ = [IntervalTree intervalTreeWithInterval:NSMakeRange(0, 256)];
  [tree_ addEntryWithInterval:NSMakeRange(10, 2) object:obj1_];
  [tree_ addEntryWithInterval:NSMakeRange(20, 2) object:obj2_];
  [self assertEntriesInInterval:NSMakeRange(0, 10) equal:@[]];
  [self assertEntriesInInterval:NSMakeRange(10, 1) equal:@[obj1_]];
  [self assertEntriesInInterval:NSMakeRange(10, 2) equal:@[obj1_]];
  [self assertEntriesInInterval:NSMakeRange(11, 1) equal:@[obj1_]];

  [self assertEntriesInInterval:NSMakeRange(20, 1) equal:@[obj2_]];
  [self assertEntriesInInterval:NSMakeRange(20, 2) equal:@[obj2_]];
  [self assertEntriesInInterval:NSMakeRange(21, 1) equal:@[obj2_]];

  [self assertEntriesInInterval:NSMakeRange(10, 12) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(10, 11) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(10, 10) equal:@[obj1_]];
  [self assertEntriesInInterval:NSMakeRange(0, 30) equal:@[obj1_, obj2_]];
}

- (void)testTwoEntriesWithSameInterval {
  tree_ = [IntervalTree intervalTreeWithInterval:NSMakeRange(0, 256)];
  [tree_ addEntryWithInterval:NSMakeRange(10, 2) object:obj1_];
  [tree_ addEntryWithInterval:NSMakeRange(10, 2) object:obj2_];
  [self assertEntriesInInterval:NSMakeRange(0, 10) equal:@[]];
  [self assertEntriesInInterval:NSMakeRange(12, 10) equal:@[]];
  [self assertEntriesInInterval:NSMakeRange(10, 1) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(10, 2) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(11, 1) equal:@[obj1_, obj2_]];
}

//  11111
// 2222
- (void)testAddOverlap1 {
  tree_ = [IntervalTree intervalTreeWithInterval:NSMakeRange(0, 256)];
  [tree_ addEntryWithInterval:NSMakeRange(10, 10) object:obj1_];
  [tree_ addEntryWithInterval:NSMakeRange(5, 10) object:obj2_];

  [self assertEntriesInInterval:NSMakeRange(0, 5) equal:@[]];
  [self assertEntriesInInterval:NSMakeRange(0, 30) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(0, 10) equal:@[obj2_]];
  [self assertEntriesInInterval:NSMakeRange(10, 5) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(15, 5) equal:@[obj1_]];
  [self assertEntriesInInterval:NSMakeRange(20, 5) equal:@[]];
}

//  11111
//  222
- (void)testAddOverlap2 {
  tree_ = [IntervalTree intervalTreeWithInterval:NSMakeRange(0, 256)];
  [tree_ addEntryWithInterval:NSMakeRange(10, 10) object:obj1_];
  [tree_ addEntryWithInterval:NSMakeRange(10, 5) object:obj2_];

  [self assertEntriesInInterval:NSMakeRange(0, 10) equal:@[]];
  [self assertEntriesInInterval:NSMakeRange(10, 1) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(10, 10) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(15, 10) equal:@[obj1_]];
  [self assertEntriesInInterval:NSMakeRange(20, 10) equal:@[]];
}

//  11111
//   222
- (void)testAddOverlap3 {
  tree_ = [IntervalTree intervalTreeWithInterval:NSMakeRange(0, 256)];
  [tree_ addEntryWithInterval:NSMakeRange(10, 10) object:obj1_];
  [tree_ addEntryWithInterval:NSMakeRange(12, 5) object:obj2_];

  [self assertEntriesInInterval:NSMakeRange(0, 10) equal:@[]];
  [self assertEntriesInInterval:NSMakeRange(0, 100) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(0, 12) equal:@[obj1_]];
  [self assertEntriesInInterval:NSMakeRange(0, 13) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(12, 1) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(12, 10) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(17, 10) equal:@[obj1_]];
  [self assertEntriesInInterval:NSMakeRange(20, 10) equal:@[]];
}

//  11111
//    222
- (void)testAddOverlap4 {
  tree_ = [IntervalTree intervalTreeWithInterval:NSMakeRange(0, 256)];
  [tree_ addEntryWithInterval:NSMakeRange(10, 10) object:obj1_];
  [tree_ addEntryWithInterval:NSMakeRange(15, 5) object:obj2_];

  [self assertEntriesInInterval:NSMakeRange(0, 10) equal:@[]];
  [self assertEntriesInInterval:NSMakeRange(0, 11) equal:@[obj1_]];
  [self assertEntriesInInterval:NSMakeRange(0, 16) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(15, 10) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(0, 100) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(20, 100) equal:@[]];
}

//  11111
//     222
- (void)testAddOverlap5 {
  tree_ = [IntervalTree intervalTreeWithInterval:NSMakeRange(0, 256)];
  [tree_ addEntryWithInterval:NSMakeRange(10, 10) object:obj1_];
  [tree_ addEntryWithInterval:NSMakeRange(15, 10) object:obj2_];

  [self assertEntriesInInterval:NSMakeRange(0, 10) equal:@[]];
  [self assertEntriesInInterval:NSMakeRange(0, 11) equal:@[obj1_]];
  [self assertEntriesInInterval:NSMakeRange(0, 20) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(0, 30) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(15, 30) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(20, 30) equal:@[obj2_]];
  [self assertEntriesInInterval:NSMakeRange(30, 30) equal:@[]];
}

//  11111
// 2222222
- (void)testAddOverlap6 {
  tree_ = [IntervalTree intervalTreeWithInterval:NSMakeRange(0, 256)];
  [tree_ addEntryWithInterval:NSMakeRange(10, 10) object:obj1_];  // [10, 20)
  [tree_ addEntryWithInterval:NSMakeRange(5, 20) object:obj2_];   // [5, 25)

  [self assertEntriesInInterval:NSMakeRange(0, 5) equal:@[]];
  [self assertEntriesInInterval:NSMakeRange(0, 10) equal:@[obj2_]];
  [self assertEntriesInInterval:NSMakeRange(0, 15) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(0, 20) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(0, 25) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(0, 30) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(5, 5) equal:@[obj2_]];
  [self assertEntriesInInterval:NSMakeRange(5, 10) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(0, 100) equal:@[obj1_, obj2_]];
  [self assertEntriesInInterval:NSMakeRange(25, 100) equal:@[]];
}

- (NSRange)randomInterval {
  NSRange range;
  range.location = rand() % 255;
  range.length = 1 + \rand() % (256 - range.location);
  return range;
}

- (void)testRandomTree {
  const int ITERATIONS = 1000;
  srand(0);
  for (int j = 0; j < ITERATIONS; j++) {
    const int N = 50;
    NSMutableArray *entries = [NSMutableArray array];
    tree_ = [IntervalTree intervalTreeWithInterval:NSMakeRange(0, 256)];
    for (int i = 0; i < N; i++) {
      IntervalTreeEntry *entry = [[[IntervalTreeEntry alloc] init] autorelease];
      entry.interval = [self randomInterval];
      entry.object = [[[NSObject alloc] init] autorelease];
      [tree_ addEntry:entry];
      [entries addObject:entry];
    }

    const int TESTS = 100;
    for (int i = 0; i < TESTS; i++) {
      NSRange interval = [self randomInterval];
      NSArray *actualEntries = [tree_ entriesInInterval:interval];
      NSMutableArray *expectedEntries = [NSMutableArray array];
      for (int k = 0; k < N; k++) {
        IntervalTreeEntry *entry = entries[k];
        if (NSIntersectionRange(interval, entry.interval).length > 0) {
          [expectedEntries addObject:entries[k]];
        }
      }
      assert(actualEntries.count == expectedEntries.count);
      for (IntervalTreeEntry *expected in expectedEntries) {
        assert([actualEntries containsObject:expected]);
      }
    }
  }
}

@end
