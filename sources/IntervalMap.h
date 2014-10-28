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

+ (IntRange *)rangeWithMin:(int)min limit:(int)limit;
+ (IntRange *)rangeWithMin:(int)min size:(int)size;
- (BOOL)isEqualToIntRange:(IntRange *)other;
- (BOOL)intersectsRange:(IntRange *)other;
- (IntRange *)intersectionWithRange:(IntRange *)other;
- (int)limit;
- (NSArray *)rangesAfterSubtractingRange:(IntRange *)other;

@end

@interface IntervalMap : NSObject {
    NSMutableArray *elements_;
}

- (id)init;
- (void)dealloc;
- (void)setObject:(id)object forRange:(IntRange *)range;
- (void)incrementNumbersBy:(int)amount inRange:(IntRange *)range;
- (NSArray *)allValues;

@end
