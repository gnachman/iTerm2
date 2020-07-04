//
//  Expression2.m
//  CoreParse
//
//  Created by Ayal Spitz on 10/4/12.
//  Copyright (c) 2012 In The Beginning... All rights reserved.
//

#import "Expression2.h"
#import "Term2.h"

@implementation Expression2

@synthesize value;

- (id)initWithSyntaxTree:(CPSyntaxTree *)syntaxTree{
    self = [self init];
    
    if (nil != self){
        NSArray *components = [syntaxTree children];
        if ([components count] == 1){
            NSObject *term2 = [components objectAtIndex:0];
            if ([term2 isMemberOfClass:[Term2 class]]){
                self.value = [(Term2 *)term2 value];
            } else {
                self.value = -1;
            }
        } else {
            NSObject *term2 = [components objectAtIndex:2];
            if ([term2 isMemberOfClass:[Term2 class]]){
                self.value = [(Expression2 *)[components objectAtIndex:0] value] + [(Term2 *)term2 value];
            } else {
                self.value = -1;
            }
        }
    }
    
    return self;
}

@end
