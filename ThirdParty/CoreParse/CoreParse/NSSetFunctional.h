//
//  NSSetFunctional.h
//  CoreParse
//
//  Created by Tom Davie on 06/03/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSSet(Functional)

- (NSSet *)cp_map:(id(^)(id obj))block;

@end
