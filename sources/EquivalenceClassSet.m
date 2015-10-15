#import "EquivalenceClassSet.h"

@implementation EquivalenceClassSet {
    // Maps objects belonging to an equivalence class to their class's number.
    NSMutableDictionary<NSObject<NSCopying> *, NSNumber *> *index_;

    // Maps a class's number to the objects that belong to it.
    NSMutableDictionary<NSNumber *, NSMutableSet<NSObject<NSCopying> *> *> *classes_;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        index_ = [[NSMutableDictionary alloc] init];
        classes_ = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc {
    [index_ release];
    [classes_ release];
    [super dealloc];
}

- (NSSet<NSObject<NSCopying> *> *)valuesEqualTo:(NSObject<NSCopying> *)target {
    NSNumber *ec = index_[target];
    return ec ? classes_[ec] : nil;
}

- (void)addValue:(NSObject<NSCopying> *)value toClass:(NSNumber *)ec {
    [self removeValue:value];
    index_[value] = ec;
    NSMutableSet<NSObject<NSCopying> *> *theSet = classes_[ec];
    if (!theSet) {
        theSet = [NSMutableSet set];
        classes_[ec] = theSet;
    }
    [theSet addObject:value];
}

- (NSNumber *)addEquivalenceClass {
    int i = 0;
    while (classes_[@(i)]) {
        i++;
    }
    return @(i);
}

- (void)setValue:(NSObject<NSCopying> *)n1 equalToValue:(NSObject<NSCopying> *)n2 {
    NSNumber *n1Class = index_[n1];
    NSNumber *n2Class = index_[n2];
    if (n1Class) {
        if (n2Class) {
            if ([n1Class intValue] != [n2Class intValue]) {
                // Merge the equivalence classes. Move every value in n2's class
                // (including n2, of course) into n1's.
                for (NSNumber *n in [[classes_[n2Class] copy] autorelease]) {
                    [self addValue:n toClass:n1Class];
                }
            }
        } else {
            // n2 does not belong to an existing equivalence class yet so add it to n1's class
            [self addValue:n2 toClass:n1Class];
        }
    } else {
        // n1 does not have an equivalence relation yet
        if (n2Class) {
            // n2 has an equivalence relation already so add n1 to it
            [self addValue:n1 toClass:n2Class];
        } else {
            // Neither n1 nor n2 has an existing relation so create a new equivalence class
            NSNumber *ec = [self addEquivalenceClass];
            [self addValue:n2 toClass:ec];
            [self addValue:n1 toClass:ec];
        }
    }
}

- (void)removeValue:(NSObject<NSCopying> *)target {
    NSNumber *ec = index_[target];
    if (!ec) {
        return;
    }
    NSMutableSet *c = classes_[ec];
    [c removeObject:target];
    [index_ removeObjectForKey:target];
    if (!c.count) {
        [classes_ removeObjectForKey:ec];
    } else if (c.count == 1) {
        // An equivalence class with one object is silly so remove its last element.
        [self removeValue:[[c allObjects] lastObject]];
    }
}

- (NSArray *)classes {
        return [classes_ allValues];
}

@end
