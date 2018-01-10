//
//  iTermTuple.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/9/18.
//

#import <Foundation/Foundation.h>

@interface iTermTuple<T1, T2> : NSObject<NSCoding, NSCopying>

@property (nonatomic, strong) T1 firstObject;
@property (nonatomic, strong) T2 secondObject;

+ (instancetype)tupleWithObject:(T1)firstObject andObject:(T2)secondObject;

@end
