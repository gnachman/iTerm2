//
//  IntervalMap.h
//  iTerm
//
//  Created by George Nachman on 12/8/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface IntRange : NSObject {
@public
    int min;
    int size;
}

+ (instancetype)rangeWithMin:(int)min limit:(int)limit;
+ (instancetype)rangeWithMin:(int)min size:(int)size;
- (BOOL)isEqualToIntRange:(IntRange *)other;
- (BOOL)intersectsRange:(IntRange *)other;
- (instancetype)intersectionWithRange:(IntRange *)other;
- (int)limit;
- (NSArray<IntRange*> *)rangesAfterSubtractingRange:(IntRange *)other;

@end

@interface IntervalMap : NSObject {
    NSMutableArray *elements_;
}

- (instancetype)init;
- (void)setObject:(id)object forRange:(IntRange *)range;
- (void)incrementNumbersBy:(int)amount inRange:(IntRange *)range;
- (NSArray *)allValues;

@end
