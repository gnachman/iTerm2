//
//  NSArray+Functional.m
//  CoreParse
//
//  Created by Tom Davie on 20/08/2012.
//  Copyright (c) 2012 In The Beginning... All rights reserved.
//

#import "NSArray+Functional.h"

@implementation NSArray (Functional)

- (NSArray *)cp_map:(id(^)(id obj))block
{
    NSUInteger c = [self count];
    id *resultingObjects = malloc(c * sizeof(id));
    
    NSUInteger nonNilCount = 0;
    for (id obj in self)
    {
        id r = block(obj);
        if (nil != r)
        {
            resultingObjects[nonNilCount] = r;
            nonNilCount++;
        }
    }
    
    NSArray *a = [NSArray arrayWithObjects:resultingObjects count:nonNilCount];
    free(resultingObjects);
    return a;
}

@end
