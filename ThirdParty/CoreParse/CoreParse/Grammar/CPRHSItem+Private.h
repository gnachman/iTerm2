//
//  CPRHSItem+Private.h
//  CoreParse
//
//  Created by Tom Davie on 19/08/2012.
//  Copyright (c) 2012 In The Beginning... All rights reserved.
//

#import "CPRHSItem.h"

@interface CPRHSItem (Private)

- (void)addTag:(NSString *)tagName;
- (NSSet *)tagNamesWithError:(NSError **)err;

@end
