#import <Foundation/Foundation.h>

// Stores a set of equivalence classes. You can define that two objects are equal and then query for
// the set of objects that are equal to some query object. For example, you can say that @1, @2, and
// @3 are equivalent and that @4 and @5 are equivalent. A query for the values equal to @1 will
// give [ @1, @2, @3 ].
@interface EquivalenceClassSet : NSObject

// All equivalence classes. The type is hard to read, but it's an array of sets, where each set
// contains the objects that are equivalent.
@property(nonatomic, readonly) NSArray<NSSet<NSObject<NSCopying> *> *> *classes;

- (NSSet<NSObject<NSCopying> *> *)valuesEqualTo:(NSObject<NSCopying> *)target;
- (void)setValue:(NSObject<NSCopying> *)value equalToValue:(NSObject<NSCopying> *)otherValue;
- (void)removeValue:(NSObject<NSCopying> *)target;

@end
