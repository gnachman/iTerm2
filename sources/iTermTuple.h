//
//  iTermTuple.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/9/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermTuple<T1, T2> : NSObject<NSSecureCoding, NSCopying>

@property (nullable, nonatomic, strong) T1 firstObject;
@property (nullable, nonatomic, strong) T2 secondObject;
@property (nonatomic, readonly) id plistValue;

+ (instancetype)tupleWithObject:(nullable T1)firstObject andObject:(nullable T2)secondObject;
+ (instancetype)fromPlistValue:(id)plistValue;
+ (NSArray<iTermTuple<T1, T2> *> *)cartesianProductOfArray:(NSArray<T1> *)a1
                                                      with:(NSArray<T2> *)a2;

@end

@interface iTermTriple<T1, T2, T3> : iTermTuple<NSSecureCoding, NSCopying>

@property (nullable, nonatomic, strong) T3 thirdObject;

+ (instancetype)tupleWithObject:(nullable T1)firstObject andObject:(nullable T2)secondObject NS_UNAVAILABLE;
+ (instancetype)tripleWithObject:(nullable T1)firstObject andObject:(nullable T2)secondObject object:(nullable T3)thirdObject;

@end

NS_ASSUME_NONNULL_END

