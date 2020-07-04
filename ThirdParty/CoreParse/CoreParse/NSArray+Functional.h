//
//  NSArray+Functional.h
//  CoreParse
//
//  Created by Tom Davie on 20/08/2012.
//  Copyright (c) 2012 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSArray (Functional)

- (NSArray *)cp_map:(id(^)(id obj))block;

@end
