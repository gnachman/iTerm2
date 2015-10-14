#import <Foundation/Foundation.h>

@interface EquivalenceClassSet : NSObject 

@property(nonatomic, readonly) NSArray<Class> *classes;

- (NSArray *)valuesEqualTo:(NSObject<NSCopying> *)target;
- (void)setValue:(NSObject<NSCopying> *)value equalToValue:(NSObject<NSCopying> *)otherValue;
- (void)removeValue:(NSObject<NSCopying> *)target;

@end
