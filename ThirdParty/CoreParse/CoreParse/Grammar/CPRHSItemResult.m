//
//  CPRHSItemResult.m
//  CoreParse
//
//  Created by Thomas Davie on 23/10/2011.
//  Copyright (c) 2011 In The Beginning... All rights reserved.
//

#import "CPRHSItemResult.h"

#import "CPRule+Internal.h"

@implementation CPRHSItemResult

@synthesize contents = _contents;
@synthesize tagNames = _tagNames;
@synthesize shouldCollapse = _shouldCollapse;
@synthesize tagValues = _tagValues;

- (id)initWithSyntaxTree:(CPSyntaxTree *)syntaxTree
{
    self = [super init];
    
    if (nil != self)
    {
        NSArray *children = [syntaxTree children];
        CPRule *r = [syntaxTree rule];
        
        switch ([r tag])
        {
            case 0:
                [self setContents:[NSMutableArray array]];
                break;
            case 1:
                [self setContents:[[children mutableCopy] autorelease]];
                break;
            case 2:
            {
                NSMutableArray *nextContents = (NSMutableArray *)[children lastObject];
                NSUInteger i = 0;
                for (id newContent in [children subarrayWithRange:NSMakeRange(0, [children count] - 1)])
                {
                    [nextContents insertObject:newContent atIndex:i];
                    i++;
                }
                [self setContents:nextContents];
                break;
            }
            default:
                [self setContents:[[children mutableCopy] autorelease]];
                break;
        }
        
        [self setTagValues:[syntaxTree tagValues]];
        [self setTagNames:[r tagNames]];
        [self setShouldCollapse:[r shouldCollapse]];
    }
    
    return self;
}

- (void)dealloc
{
    [_contents release];
    [_tagNames release];
    [_tagValues release];
    
    [super dealloc];
}

- (BOOL)isRHSItemResult
{
    return YES;
}

@end

@implementation NSObject(CPIsRHSItemResult)

- (BOOL)isRHSItemResult
{
    return NO;
}

@end
