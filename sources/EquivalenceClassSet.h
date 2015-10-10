#import <Foundation/Foundation.h>

@interface EquivalenceClassSet : NSObject {
    NSMutableDictionary *index_;
    NSMutableDictionary *classes_;
}

- (NSArray *)valuesEqualTo:(NSObject<NSCopying> *)target;
- (void)setValue:(NSObject<NSCopying> *)value equalToValue:(NSObject<NSCopying> *)otherValue;
- (void)removeValue:(NSObject<NSCopying> *)target;
@property (readonly, copy) NSArray<Class> *classes;

@end
