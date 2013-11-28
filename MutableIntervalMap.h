#import <Foundation/Foundation.h>
#import "IntervalTree.h"


// A collection mapping Interval->NSObject.
@interface MutableIntervalMultiMap : NSObject {
  IntervalTreeNode *root_;
}

- (void)setObject:(id)object forInterval:(Interval *)interval;
- (NSArray *)objectsInInterval:(Interval *)interval;
- (NSArray *)entriesinterval:(Interval *)interval;
- (void)removeEntry:(IntervalMapEntry *)entry;

@end
