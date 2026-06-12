//
//  IntervalMap.m
//  iTerm
//
//  Created by George Nachman on 12/8/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import "IntervalMap.h"

@interface IntervalMapElement : NSObject {
    IntRange *range_;
    id value_;
}

@property (nonatomic, retain) IntRange *range;
@property (nonatomic, retain) id value;

+ (IntervalMapElement *)elementWithRange:(IntRange *)range value:(id)value;

@end

@implementation IntervalMapElement

@synthesize range = range_;
@synthesize value = value_;

+ (IntervalMapElement *)elementWithRange:(IntRange *)range value:(id)value
{
    IntervalMapElement *element = [[[IntervalMapElement alloc] init] autorelease];
    element.range = range;
    element.value = value;
    return element;
}

- (void)dealloc
{
    [range_ release];
    [value_ release];
    [super dealloc];
}

- (NSComparisonResult)compare:(IntervalMapElement *)other
{
    return [[NSNumber numberWithInt:self.range->min] compare:[NSNumber numberWithInt:other.range->min]];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@=%@", self.range, self.value];
}

@end

@implementation IntRange

+ (IntRange *)rangeWithMin:(int)min size:(int)size
{
    return [IntRange rangeWithMin:min limit:min + size];
}

+ (IntRange *)rangeWithMin:(int)min limit:(int)limit
{
    IntRange *range = [[[IntRange alloc] init] autorelease];
    range->min = min;
    range->size = MAX(0, limit - min);
    return range;
}

- (BOOL)isEqualToIntRange:(IntRange *)other
{
    return min == other->min && size == other->size;
}

- (int)limit
{
    return min + size;
}

- (BOOL)intersectsRange:(IntRange *)other
{
    return min < [other limit] && [self limit] > other->min;
}

- (IntRange *)intersectionWithRange:(IntRange *)other
{
    return [IntRange rangeWithMin:MAX(min, other->min)
                            limit:MIN([self limit], [other limit])];
}

- (NSArray *)rangesAfterSubtractingRange:(IntRange *)other
{
    NSMutableArray *result = [NSMutableArray array];
    // Possibilities:
    // 1.      2.      3.       4.       5.       6.
    // sssss |  sss  | sss    |    sss |   ssss | ssss
    //  ooo  | ooooo |    ooo | ooo    | oooo   |   oooo
    if (other->min > min && [other limit] < [self limit]) {
        // 1. Other is strictly inside self so return two results
        [result addObject:[IntRange rangeWithMin:min limit:[other limit]]];
        [result addObject:[IntRange rangeWithMin:other->min limit:[self limit]]];
    } else if (other->min <= min && [other limit] >= [self limit]) {
        // 2. Self is contained by other
    } else if ([other limit] <= min || other->min >= [self limit]) {
        // 3, 4. Disjoint
        [result addObject:[IntRange rangeWithMin:min limit:[self limit]]];
    } else if (other->min <= min) {
        // 5. Other starts before self but overlaps
        [result addObject:[IntRange rangeWithMin:[other limit] limit:[self limit]]];
    } else {
        // 6. Self starts before other but overlaps
        [result addObject:[IntRange rangeWithMin:min limit:other->min]];
    }
    return result;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"[%d,%d)", min, [self limit]];
}

@end

@implementation IntervalMap {
    NSMutableArray *elements_;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        elements_ = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [elements_ release];
    [super dealloc];
}

- (NSArray *)elementsInRange:(IntRange *)range
{
    NSMutableArray *result = [NSMutableArray array];
    for (IntervalMapElement *elt in elements_) {
        if ([elt.range intersectsRange:range]) {
            [result addObject:elt];
        }
    }
    return result;
}

- (void)insertElement:(IntervalMapElement *)elt
{
    [elements_ addObject:elt];
}

- (void)setObject:(id)object forRange:(IntRange *)range
{
    NSArray *overlappingElements = [self elementsInRange:range];
    for (IntervalMapElement *elt in overlappingElements) {
        // Remove overlapping element
        [elements_ removeObject:elt];

        // Break into zero or more elements that don't include any part of 'range'
        // and add them back with the original value.
        NSArray *fragments = [elt.range rangesAfterSubtractingRange:range];
        for (IntRange *fragment in fragments) {
            [self insertElement:[IntervalMapElement elementWithRange:fragment
                                                               value:elt.value]];
        }
    }
    // Insert a new element with just 'range' and its new value.
    [self insertElement:[IntervalMapElement elementWithRange:range value:object]];
}

- (NSArray *)ranges:(NSArray *)orig bySubtractingRange:(IntRange *)sub
{
    NSMutableArray *result = [NSMutableArray array];
    for (IntRange *range in orig) {
        NSArray *fragments = [range rangesAfterSubtractingRange:sub];
        if (fragments.count) {
            [result addObjectsFromArray:fragments];
        }
    }
    return result;
}

- (void)incrementNumbersBy:(int)amount inRange:(IntRange *)range
{
    NSArray *elts = [self elementsInRange:range];
    NSArray *newRanges = [NSArray arrayWithObject:range];
    for (IntervalMapElement *e in elts) {
        NSNumber *n = e.value;
        n = [NSNumber numberWithInt:[n intValue] + amount];
        IntRange *intersection = [e.range intersectionWithRange:range];
        [self setObject:n forRange:intersection];
        newRanges = [self ranges:newRanges bySubtractingRange:e.range];
    }
    for (IntRange *newRange in newRanges) {
        [self setObject:[NSNumber numberWithInt:amount] forRange:newRange];
    }
}

- (NSArray *)allValues
{
    NSMutableArray *result = [NSMutableArray array];
    for (IntervalMapElement *e in elements_) {
        [result addObject:e.value];
    }
    return result;
}

- (NSString *)description
{
    NSMutableString *result = [NSMutableString string];
    for (IntervalMapElement *e in elements_) {
        [result appendFormat:@"%@ ", [e description]];
    }
    return result;
}

@end
